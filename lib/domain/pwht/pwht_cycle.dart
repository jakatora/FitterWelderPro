// Cykl obróbki cieplnej po spawaniu (PWHT) — czysta matematyka, bez Fluttera.
//
// Cykl ma trzy części kontrolowane:
//   1. nagrzewanie od temperatury kontrolnej do temperatury wytrzymania
//      z szybkością nie większą niż dopuszczalna,
//   2. wytrzymanie (holding / soak) przez czas minimalny z tabeli normy,
//   3. chłodzenie od temperatury wytrzymania do temperatury kontrolnej
//      z szybkością nie większą niż dopuszczalna.
// Poniżej temperatury kontrolnej szybkość nie jest regulowana (reguła, z której
// pochodzą szybkości, mówi, od jakiej temperatury je liczyć) — aplikacja NIE
// wlicza tych odcinków do czasu cyklu, bo zależą od pieca / maty / izolacji.
//
// Wartości liczbowe reguł (współczynniki, limity) są w pwht_tables.dart razem
// ze źródłem. Tu tylko arytmetyka.

/// Reguła szybkości nagrzewania i chłodzenia powyżej temperatury kontrolnej:
///
///   v = k / t   [°C/h],  t — grubość [mm]
///   v ≤ cap (jeśli reguła ma górny limit)
///   v nie musi być mniejsza niż floor (jeśli reguła to mówi)
///
/// Przykład (ASME VIII-1 UCS-56): nagrzewanie k = 5500, cap = 222, floor = 55.
class PwhtRateRule {
  const PwhtRateRule({
    required this.id,
    required this.namePl,
    required this.nameEn,
    required this.source,
    required this.controlTempC,
    required this.heatCoefficient,
    required this.heatCapCPerH,
    required this.coolCoefficient,
    required this.coolCapCPerH,
    required this.floorCPerH,
    required this.notePl,
    required this.noteEn,
    required this.belowControlPl,
    required this.belowControlEn,
  });

  /// Co reguła mówi o chłodzeniu poniżej temperatury kontrolnej.
  final String belowControlPl;
  final String belowControlEn;

  /// Trwały identyfikator reguły (do testów i tekstu planu).
  final String id;
  final String namePl;
  final String nameEn;

  /// Norma, paragraf, wydanie — drukowane w planie.
  final String source;

  /// Temperatura, powyżej której szybkości są kontrolowane [°C].
  final int controlTempC;

  /// k nagrzewania [°C·mm/h].
  final double heatCoefficient;

  /// Górny limit nagrzewania [°C/h]; null = brak limitu w regule.
  final double? heatCapCPerH;

  /// k chłodzenia [°C·mm/h].
  final double coolCoefficient;

  /// Górny limit chłodzenia [°C/h]; null = brak limitu w regule.
  final double? coolCapCPerH;

  /// „Nie musi być mniejsza niż” [°C/h]; null = reguła tego nie mówi.
  final double? floorCPerH;

  final String notePl;
  final String noteEn;

  double _rate(double k, double? cap, double tMm) {
    var v = k / tMm;
    if (cap != null && v > cap) v = cap;
    final floor = floorCPerH;
    if (floor != null && v < floor) v = floor;
    return v;
  }

  /// Maksymalna dopuszczalna szybkość nagrzewania [°C/h] dla grubości [tMm].
  /// `null` dla grubości ≤ 0 albo nieskończonej.
  double? maxHeatingRate(double tMm) {
    if (!tMm.isFinite || tMm <= 0) return null;
    return _rate(heatCoefficient, heatCapCPerH, tMm);
  }

  /// Maksymalna dopuszczalna szybkość chłodzenia [°C/h] dla grubości [tMm].
  double? maxCoolingRate(double tMm) {
    if (!tMm.isFinite || tMm <= 0) return null;
    return _rate(coolCoefficient, coolCapCPerH, tMm);
  }
}

/// Punkt wykresu temperatura–czas.
class PwhtCyclePoint {
  const PwhtCyclePoint(this.hours, this.tempC);

  /// Czas od osiągnięcia temperatury kontrolnej [h].
  final double hours;
  final double tempC;
}

/// Kontrolowana część cyklu PWHT.
class PwhtCycle {
  const PwhtCycle({
    required this.controlTempC,
    required this.holdTempC,
    required this.heatingRateCPerH,
    required this.coolingRateCPerH,
    required this.holdMinutes,
  });

  /// Temperatura kontrolna (start i koniec części kontrolowanej) [°C].
  final int controlTempC;

  /// Temperatura wytrzymania przyjęta do planu [°C].
  final int holdTempC;

  /// Szybkości przyjęte do planu [°C/h].
  final double heatingRateCPerH;
  final double coolingRateCPerH;

  /// Minimalny czas wytrzymania [min].
  final int holdMinutes;

  /// Nagrzewanie od temperatury kontrolnej do wytrzymania [h].
  double get rampUpHours => (holdTempC - controlTempC) / heatingRateCPerH;

  double get holdHours => holdMinutes / 60.0;

  /// Chłodzenie od wytrzymania do temperatury kontrolnej [h].
  double get rampDownHours => (holdTempC - controlTempC) / coolingRateCPerH;

  /// Czas części kontrolowanej [h] — bez nagrzewania do temperatury
  /// kontrolnej i bez swobodnego chłodzenia poniżej niej.
  double get totalHours => rampUpHours + holdHours + rampDownHours;

  /// Cztery punkty łamanej: start, początek wytrzymania, koniec, koniec cyklu.
  List<PwhtCyclePoint> get points => [
        PwhtCyclePoint(0, controlTempC.toDouble()),
        PwhtCyclePoint(rampUpHours, holdTempC.toDouble()),
        PwhtCyclePoint(rampUpHours + holdHours, holdTempC.toDouble()),
        PwhtCyclePoint(totalHours, controlTempC.toDouble()),
      ];
}

/// Buduje cykl. `null`, gdy dane nie dają sensownego cyklu (szybkość ≤ 0,
/// temperatura wytrzymania nie wyższa od kontrolnej, ujemny czas).
PwhtCycle? buildPwhtCycle({
  required int controlTempC,
  required int holdTempC,
  required double heatingRateCPerH,
  required double coolingRateCPerH,
  required int holdMinutes,
}) {
  if (holdTempC <= controlTempC) return null;
  if (!heatingRateCPerH.isFinite || heatingRateCPerH <= 0) return null;
  if (!coolingRateCPerH.isFinite || coolingRateCPerH <= 0) return null;
  if (holdMinutes < 0) return null;
  return PwhtCycle(
    controlTempC: controlTempC,
    holdTempC: holdTempC,
    heatingRateCPerH: heatingRateCPerH,
    coolingRateCPerH: coolingRateCPerH,
    holdMinutes: holdMinutes,
  );
}

/// Czas w godzinach → „3 h 05 min” / „45 min”. Zaokrąglenie W GÓRĘ do pełnej
/// minuty (plan nie może skracać czasu minimalnego).
String formatPwhtDuration(double hours) {
  if (!hours.isFinite || hours < 0) return '—';
  final total = (hours * 60 - 1e-9).ceil().clamp(0, 1 << 30);
  final h = total ~/ 60;
  final m = total % 60;
  if (h == 0) return '$m min';
  return '$h h ${m.toString().padLeft(2, '0')} min';
}
