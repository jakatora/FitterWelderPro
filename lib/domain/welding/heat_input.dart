// Energia liniowa (heat input) — czyste funkcje, bez Fluttera.
//
// Dwie konwencje, które spawacz spotyka na WPS:
//
//  • EN 1011-1 / EN ISO 15614-1 (tzw. „heat input” Q):
//      Q [kJ/mm] = k × U × I × 60 / (v × 1000)      v w mm/min
//    k — sprawność cieplna procesu (EN 1011-1, tab. 1; ISO/TR 17671-1).
//
//  • ASME IX QW-409.1(a) — „heat input” BEZ współczynnika sprawności:
//      HI [J/in] = U × I × 60 / v [in/min]
//    w jednostkach SI to samo: HI [J/mm] = U × I × 60 / v [mm/min].
//    (To, co EN nazywa „arc energy”.)
//
// Te same parametry dają więc dwie różne liczby — np. TIG 12 V / 100 A /
// 90 mm/min: ASME 0,80 kJ/mm, EN (k = 0,6) 0,48 kJ/mm. Porównuj wynik z WPS
// liczonym w TEJ SAMEJ konwencji.

/// Proces spawania z numerem wg EN ISO 4063 i sprawnością cieplną k.
///
/// Wartości k wg EN 1011-1:2009 tab. 1 (= ISO/TR 17671-1): łuk kryty 1,0;
/// MMA, MIG/MAG i drut proszkowy (także samoosłonowy 114) 0,8; TIG i plazma
/// 0,6. Potwierdzenie: TWI FAQ „What is the difference between heat input
/// and arc energy?” (SAW 1,0 / MMA 0,8 / FCAW 0,8 / MIG/MAG 0,8 / TIG 0,6).
enum WeldingProcess {
  smaw('SMAW', 'MMA', '111', 0.8),
  gmaw('GMAW', 'MIG/MAG', '131/135', 0.8),
  fcawG('FCAW-G', 'FCAW-G', '136/137', 0.8),
  fcawS('FCAW-S', 'FCAW-S', '114', 0.8),
  gtaw('GTAW', 'TIG', '141', 0.6),
  saw('SAW', 'SAW', '121', 1.0);

  const WeldingProcess(
    this.code,
    this.euName,
    this.isoNumber,
    this.thermalEfficiency,
  );

  /// Skrót AWS/ASME używany w UI ekranu Heat input (SMAW, GTAW…).
  final String code;

  /// Nazwa potoczna w Europie (MMA, TIG…).
  final String euName;

  /// Numer procesu wg EN ISO 4063.
  final String isoNumber;

  /// Sprawność cieplna k wg EN 1011-1 tab. 1.
  final double thermalEfficiency;

  /// Etykieta typu „TIG 141”.
  String get euLabel => '$euName $isoNumber';

  static WeldingProcess? fromCode(String code) {
    for (final p in WeldingProcess.values) {
      if (p.code == code) return p;
    }
    return null;
  }
}

/// Konwencja liczenia energii liniowej.
enum HeatInputStandard {
  /// EN 1011-1 / EN ISO 15614-1: Q = k × energia łuku.
  en1011,

  /// ASME IX QW-409.1(a): bez współczynnika sprawności.
  asmeIx,
}

bool _positive(double x) => x.isFinite && x > 0;

/// Energia łuku U × I × 60 / v w kJ/mm (v w mm/min). `null` dla danych,
/// z których nie da się policzyć (zero, ujemne, NaN, nieskończoność).
double? arcEnergyKJPerMm({
  required double volts,
  required double amps,
  required double travelMmPerMin,
}) {
  if (!_positive(volts) || !_positive(amps) || !_positive(travelMmPerMin)) {
    return null;
  }
  return volts * amps * 60.0 / travelMmPerMin / 1000.0;
}

/// Energia liniowa w kJ/mm w wybranej konwencji.
///
/// [efficiency] (k) jest używane tylko dla [HeatInputStandard.en1011] i musi
/// leżeć w (0; 1]. Dla ASME IX jest ignorowane — kod liczy bez sprawności.
double? heatInputKJPerMm({
  required double volts,
  required double amps,
  required double travelMmPerMin,
  required HeatInputStandard standard,
  required double efficiency,
}) {
  final arc = arcEnergyKJPerMm(
    volts: volts,
    amps: amps,
    travelMmPerMin: travelMmPerMin,
  );
  if (arc == null) return null;
  switch (standard) {
    case HeatInputStandard.asmeIx:
      return arc;
    case HeatInputStandard.en1011:
      if (!_positive(efficiency) || efficiency > 1.0) return null;
      return arc * efficiency;
  }
}

/// Wynik porównania z zakresem energii liniowej z WPS.
enum WpsRangeVerdict {
  /// Spawacz nie wpisał zakresu — brak werdyktu.
  notSet,

  /// Min > max albo wartości ujemne — zakres do poprawy.
  invalidRange,
  inRange,
  belowMin,
  aboveMax,
}

/// Porównanie z zakresem WPS. Granice zakresu są granicami — bez żadnego
/// „pasma tolerancji”: wynik poza [min; max] jest poza WPS. Wystarczy jedna
/// granica (np. sam max dla stali nierdzewnej).
WpsRangeVerdict checkWpsRange(double heatInput, {double? min, double? max}) {
  if (min == null && max == null) return WpsRangeVerdict.notSet;
  if ((min != null && (!min.isFinite || min < 0)) ||
      (max != null && (!max.isFinite || max <= 0)) ||
      (min != null && max != null && min > max)) {
    return WpsRangeVerdict.invalidRange;
  }
  if (min != null && heatInput < min) return WpsRangeVerdict.belowMin;
  if (max != null && heatInput > max) return WpsRangeVerdict.aboveMax;
  return WpsRangeVerdict.inRange;
}
