// Plan obróbki cieplnej po spawaniu (PWHT) — czyste funkcje, bez Fluttera.
//
// MODUŁ BEZPIECZEŃSTWA-KRYTYCZNY. Wiążące parametry PWHT podaje WPS /
// procedura PWHT i specyfikacja projektu. Aplikacja pokazuje wartości
// z tabel normy (każda liczba ma źródło w pwht_tables.dart) i liczy z nich
// plan cyklu. Jeżeli dla kombinacji norma + grupa aplikacja nie ma
// sprawdzonych danych — mówi to wprost, zamiast zgadywać.

import 'pwht_cycle.dart';
import 'pwht_tables.dart';

export 'pwht_cycle.dart';
export 'pwht_tables.dart';

/// Werdykt „czy PWHT wymagane”.
enum PwhtVerdict {
  /// Grubość powyżej progu zwolnienia albo grupa bez zwolnienia (P91).
  required,

  /// Grubość w progu zwolnienia, ale zwolnienie ma warunki (podgrzewanie,
  /// skład, spawanie wielowarstwowe…) — bez ich spełnienia PWHT jest
  /// wymagane.
  exemptIfConditionsMet,

  /// Grubość w progu zwolnienia, tabela nie stawia dodatkowych warunków.
  exempt,

  /// Tabela normy nie wymaga PWHT dla tej grupy (np. austenityczne P-No 8),
  /// chyba że wymaga go WPS / specyfikacja.
  notRequiredByTable,
}

/// Dane wejściowe planu.
class PwhtInput {
  const PwhtInput({
    required this.code,
    required this.material,
    required this.thicknessMm,
    this.outsideDiameterMm,
    this.weldWidthMm,
  });

  final PwhtCode code;
  final PwhtMaterial material;

  /// Grubość kontrolna [mm] — dla złącza doczołowego pełnego przetopu:
  /// grubość grubszego elementu w złączu (por. komentarz przy tabeli).
  final double thicknessMm;

  /// Średnica zewnętrzna [mm] — opcjonalna (pasma grzania, jeśli dostępne).
  final double? outsideDiameterMm;

  /// Szerokość lica spoiny [mm] — opcjonalna (pasmo wytrzymania).
  final double? weldWidthMm;
}

/// Wynik planu.
class PwhtPlan {
  const PwhtPlan({
    required this.input,
    required this.entry,
    required this.verdict,
    required this.holdMinutes,
    required this.holdTempC,
    required this.rateRule,
    required this.heatingRateCPerH,
    required this.coolingRateCPerH,
    required this.cycle,
    required this.soakBandMm,
    required this.controlZones,
  });

  /// Zalecana liczba stref regulacji (AWS D10.10) — tylko gdy podano
  /// średnicę zewnętrzną i jest co planować.
  final PwhtControlZones? controlZones;

  final PwhtInput input;
  final PwhtTableEntry entry;
  final PwhtVerdict verdict;

  /// Minimalny czas wytrzymania [min]; null, gdy tabela nie podaje (P-No 8).
  final int? holdMinutes;

  /// Temperatura wytrzymania przyjęta do wykresu i czasu cyklu — środek
  /// zakresu z tabeli, zaokrąglony do 5 °C. null, gdy tabela nie podaje.
  final int? holdTempC;

  /// Reguła szybkości (ze źródłem) — null, gdy brak zakresu temperatur.
  final PwhtRateRule? rateRule;
  final double? heatingRateCPerH;
  final double? coolingRateCPerH;

  /// Część kontrolowana cyklu; null, gdy nie da się jej policzyć.
  final PwhtCycle? cycle;

  /// Minimalna szerokość pasma wytrzymania [mm] wg reguły normy (jeśli
  /// aplikacja ma sprawdzoną regułę), null w przeciwnym razie.
  final double? soakBandMm;

  /// Czy w ogóle jest co planować (zakres temperatur + czas z tabeli).
  bool get hasCycleData => entry.holdRange != null && holdMinutes != null;
}

/// Środek zakresu zaokrąglony do 5 °C (w dół, żeby nie wyjść poza zakres
/// przy nieparzystych granicach — i tak leży wewnątrz zakresu).
int midpointHoldTempC(PwhtTempRange r) {
  final mid = (r.minC + r.maxC) / 2;
  final rounded = (mid / 5).floor() * 5;
  if (rounded < r.minC) return r.minC;
  if (rounded > r.maxC) return r.maxC;
  return rounded;
}

/// Liczy plan. `null` dla grubości ≤ 0 / nieskończonej albo kombinacji
/// norma + grupa, dla której aplikacja nie ma sprawdzonych danych.
PwhtPlan? planPwht(PwhtInput input) {
  final t = input.thicknessMm;
  if (!t.isFinite || t <= 0) return null;
  final entry = pwhtTableEntry(input.code, input.material);
  if (entry == null) return null;

  final PwhtVerdict verdict;
  if (entry.notRequiredByTable) {
    verdict = PwhtVerdict.notRequiredByTable;
  } else {
    final ex = entry.exemption;
    if (ex == null || !ex.covers(t)) {
      verdict = PwhtVerdict.required;
    } else if (ex.conditionsFor(t).isEmpty) {
      verdict = PwhtVerdict.exempt;
    } else {
      verdict = PwhtVerdict.exemptIfConditionsMet;
    }
  }

  final range = entry.holdRange;
  final hold = entry.holdTime?.minutesFor(t);
  final holdTemp = range == null ? null : midpointHoldTempC(range);
  final rule = range == null ? null : pwhtRateRuleFor(input.code);
  final heat = rule?.maxHeatingRate(t);
  final cool = rule?.maxCoolingRate(t);
  PwhtCycle? cycle;
  if (rule != null &&
      holdTemp != null &&
      hold != null &&
      heat != null &&
      cool != null) {
    cycle = buildPwhtCycle(
      controlTempC: rule.controlTempC,
      holdTempC: holdTemp,
      heatingRateCPerH: heat,
      coolingRateCPerH: cool,
      holdMinutes: hold,
    );
  }

  // Pasmo i strefy mają sens tylko, gdy tabela podaje parametry obróbki.
  final soak = range == null
      ? null
      : soakBandWidthMm(
          code: input.code,
          thicknessMm: t,
          weldWidthMm: input.weldWidthMm,
        );
  final zones =
      range == null ? null : d1010ControlZones(input.outsideDiameterMm);

  return PwhtPlan(
    input: input,
    entry: entry,
    verdict: verdict,
    holdMinutes: hold,
    holdTempC: holdTemp,
    rateRule: rule,
    heatingRateCPerH: heat,
    coolingRateCPerH: cool,
    cycle: cycle,
    soakBandMm: soak,
    controlZones: zones,
  );
}
