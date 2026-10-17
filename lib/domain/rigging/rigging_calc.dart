/// Zawiesia i podwieszanie: nośność układu zawiesia wg współczynników trybu
/// (metoda obciążenia jednorodnego — EN 1492-1, EN 1492-2, EN 818-4/-6,
/// EN 13414-1/-2) i werdykt OK / STOP dla ładunku (spool, kształtka,
/// zbiornik) podwieszanego pod suwnicę albo dźwig.
///
/// Zasady bezpieczeństwa werdyktu (każda sprawdzana testem):
///   • werdykt: nośność = WLL × współczynnik ≥ masa → OK, inaczej STOP;
///   • liczone w KILOGRAMACH — jednostka na ekranie (kg / t) nie zmienia
///     wyniku; masa zaokrąglana W GÓRĘ do 1 kg, nośność W DÓŁ do 1 kg;
///   • kąt od pionu β > 60° → STOP („niedozwolone”); β dokładnie 45° idzie
///     do przedziału niekorzystnego (×1,0 / ×1,5);
///   • kąt nieznany, nieczytelny albo niefizyczny → brak werdyktu (nie OK);
///   • brak masy / WLL / potwierdzenia etykiety → brak werdyktu (nie OK);
///   • brak albo nieczytelna etykieta → STOP („nie używać”), bez względu
///     na kolor pasa;
///   • ładunek niesymetryczny → jak jedno cięgno (konserwatywnie);
///   • siła w cięgnie T = W / (n · cos β) tylko informacyjnie — werdykt
///     wyłącznie z tabeli współczynników.
///
/// Źródła i to, co przyjęto w aplikacji: rigging_sources.dart.
///
/// Czysty Dart.
library;

import 'dart:math' as math;

import '../fitter/fitter_calcs.dart'
    show PipeMaterial, kPipeDensityKgM3, pipeMassKgPerM;

// ═══════════════════════════════════════════════════════════════════════════
// RODZAJE I KONFIGURACJE
// ═══════════════════════════════════════════════════════════════════════════

/// Rodzaj zawiesia.
enum SlingType {
  /// Pas poliestrowy płaski — EN 1492-1.
  webbing,

  /// Pas okrągły (zawiesie wężowe) — EN 1492-2.
  roundsling,

  /// Łańcuchowe klasy 8 — EN 818-4 (użytkowanie EN 818-6).
  chain,

  /// Linowe stalowe — EN 13414-1 (użytkowanie EN 13414-2).
  wireRope;

  /// Pasy tekstylne — mają kod kolorów EN 1492.
  bool get isTextile => this == webbing || this == roundsling;
}

/// Sposób zawiązania / konfiguracja zawiesia.
enum HitchMode {
  /// Proste — jedno cięgno pionowo.
  straight,

  /// Zadusznik (pętla zaciskowa) — jedno cięgno.
  choke,

  /// Koszowe równoległe — ładunek w pętli, oba końce na haku, cięgna
  /// pionowe.
  basketParallel,

  /// Koszowe pod kątem — jak wyżej, cięgna rozchylone.
  basketAngled,

  /// Dwa cięgna (zawiesie dwucięgnowe albo dwa pasy na jednym haku).
  twoLeg,

  /// Trzy albo cztery cięgna (zawiesie wielocięgnowe).
  multiLeg;

  /// Konfiguracja z kątem rozchylenia — bez kąta nie ma werdyktu.
  bool get needsAngle =>
      this == basketAngled || this == twoLeg || this == multiLeg;

  /// Zawiesie wielocięgnowe (cięgna mogą być zawiązane na zadusznik).
  bool get isMultiLeg => this == twoLeg || this == multiLeg;

  /// Koszowe (równoległe albo pod kątem).
  bool get isBasket => this == basketParallel || this == basketAngled;
}

/// Jak monter podał kąt.
enum AngleKind {
  /// β — kąt cięgna od pionu (ten jest w tablicach).
  fromVertical,

  /// α — kąt wierzchołkowy między cięgnami (przy 4 cięgnach — między
  /// cięgnami przeciwległymi po przekątnej); α = 2β.
  included,
}

/// Przedział kąta β z tablic.
enum AngleBand {
  /// 0° ≤ β < 45°.
  upTo45,

  /// 45° ≤ β ≤ 60° (45° należy TU — strona bezpieczna).
  from45to60,

  /// β > 60° — niedozwolone.
  over60,
}

/// Górna granica β od pionu — powyżej STOP.
const double kRiggingMaxBetaDeg = 60;

/// Granica przedziałów tablicy; dokładnie 45° → przedział niekorzystny.
const double kRiggingBandEdgeDeg = 45;

/// Odchyłka od pionu, przy której koszowe uznaje się jeszcze za
/// „równoległe” (DGUV 209-021: 0°, tolerancja manipulacji do 6°).
const double kRiggingParallelToleranceDeg = 6;

/// β od pionu z wpisanej wartości. `null` — brak, nieczytelny albo
/// niefizyczny kąt (β < 0 albo β ≥ 90°).
double? betaFromInput(double? value, AngleKind kind) {
  if (value == null || !value.isFinite) return null;
  final beta = kind == AngleKind.included ? value / 2 : value;
  if (beta < 0 || beta >= 90) return null;
  return beta;
}

/// Kąt w drugiej konwencji (β ↔ α = 2β) — przełączenie konwencji nie
/// zmienia geometrii.
double convertAngle(double value, {required AngleKind from}) =>
    from == AngleKind.fromVertical ? value * 2 : value / 2;

/// Przedział tablicy dla β. Dokładnie 45° → [AngleBand.from45to60],
/// dokładnie 60° → nadal dozwolone.
AngleBand angleBand(double betaDeg) {
  if (betaDeg > kRiggingMaxBetaDeg) return AngleBand.over60;
  if (betaDeg >= kRiggingBandEdgeDeg) return AngleBand.from45to60;
  return AngleBand.upTo45;
}

// ═══════════════════════════════════════════════════════════════════════════
// WSPÓŁCZYNNIKI TRYBU
// ═══════════════════════════════════════════════════════════════════════════

/// Współczynnik trybu (mnożnik WLL z etykiety).
class ModeFactor {
  final double value;

  /// Wartość przyjęta w aplikacji — nie potwierdzona wprost w źródle albo
  /// rozstrzygnięta w stronę bezpieczeństwa (rigging_sources.dart).
  final bool adopted;

  const ModeFactor(this.value, {this.adopted = false});

  @override
  bool operator ==(Object other) =>
      other is ModeFactor && other.value == value && other.adopted == adopted;

  @override
  int get hashCode => Object.hash(value, adopted);

  @override
  String toString() => 'ModeFactor($value${adopted ? ', adopted' : ''})';
}

/// Współczynnik trybu przy SYMETRYCZNYM ładunku.
///
/// [band] wymagany dla [HitchMode.needsAngle]; `null` albo
/// [AngleBand.over60] → `null` (brak współczynnika: brak kąta albo
/// konfiguracja niedozwolona). [chokedLegs] — cięgna zawiesia
/// wielocięgnowego zawiązane na zadusznik (×0,8); dla innych trybów
/// ignorowane.
///
/// Wartości (rigging_sources.dart):
///   proste 1,0 · zadusznik 0,8 · koszowe równoległe 2,0 · koszowe 1,4 / 1,0
///   · 2 cięgna 1,4 / 1,0 (na zadusznik 1,12 / 0,8) · 3–4 cięgna 2,1 / 1,5
///   (na zadusznik 1,68 / 1,2); łańcuch w koszowym 1,0 (przyjęte).
ModeFactor? modeFactor(
  SlingType sling,
  HitchMode mode, {
  AngleBand? band,
  bool chokedLegs = false,
}) {
  if (mode.needsAngle && (band == null || band == AngleBand.over60)) {
    return null;
  }
  final low = band == AngleBand.upTo45;
  final chain = sling == SlingType.chain;
  return switch (mode) {
    HitchMode.straight => const ModeFactor(1.0),
    HitchMode.choke => const ModeFactor(0.8),
    // Łańcuch: brak potwierdzonego ×2 (DGUV bez kolumny, LEEA ×1,0 przy
    // zaczepieniu o ogniwo) — przyjęte ×1,0 przy każdym kącie.
    HitchMode.basketParallel =>
      chain ? const ModeFactor(1.0, adopted: true) : const ModeFactor(2.0),
    HitchMode.basketAngled => chain
        ? const ModeFactor(1.0, adopted: true)
        : (low ? const ModeFactor(1.4) : const ModeFactor(1.0)),
    HitchMode.twoLeg => chokedLegs
        ? (low ? const ModeFactor(1.12) : const ModeFactor(0.8))
        : (low ? const ModeFactor(1.4) : const ModeFactor(1.0)),
    // Na zadusznik — łańcuch: LEEA 14.5.2.8 (×0,8); pasy i liny — przez
    // analogię (przyjęte).
    HitchMode.multiLeg => chokedLegs
        ? ModeFactor(low ? 1.68 : 1.2, adopted: !chain)
        : (low ? const ModeFactor(2.1) : const ModeFactor(1.5)),
  };
}

/// Współczynnik po uwzględnieniu niesymetrii: ładunek niesymetryczny
/// (środek ciężkości poza osią, różne kąty cięgien) → jak JEDNO cięgno —
/// ×1,0, a gdy cięgna zawiązane na zadusznik ×0,8. Proste i zadusznik
/// to już jedno cięgno — bez zmian.
///
/// Źródła: EN 818-6 A.1.3.5 (łańcuch, wg RUD), Dolezych (dwa pasy pod
/// różnymi kątami); dla pozostałych przypadków przyjęte w aplikacji.
ModeFactor applyAsymmetry(
  ModeFactor symmetric,
  SlingType sling,
  HitchMode mode, {
  required bool chokedLegs,
}) {
  if (mode == HitchMode.straight || mode == HitchMode.choke) return symmetric;
  final single = mode.isMultiLeg && chokedLegs ? 0.8 : 1.0;
  if (symmetric.value <= single) return symmetric;
  final sourced = (sling == SlingType.chain && mode.isMultiLeg) ||
      (sling.isTextile && mode == HitchMode.twoLeg);
  return ModeFactor(single, adopted: !sourced);
}

// ═══════════════════════════════════════════════════════════════════════════
// MASA I JEDNOSTKI
// ═══════════════════════════════════════════════════════════════════════════

enum MassUnit { kg, t }

/// Wartość w kilogramach.
double toKg(double value, MassUnit unit) =>
    unit == MassUnit.t ? value * 1000 : value;

/// Kilogramy w danej jednostce.
double fromKg(double kg, MassUnit unit) => unit == MassUnit.t ? kg / 1000 : kg;

/// Szum zmiennoprzecinkowy (2800,0000000000005) nie może zmienić
/// zaokrąglenia: siatka 1e-6 kg.
double _snap(double kg) => (kg * 1e6).roundToDouble() / 1e6;

/// Masa ładunku zaokrąglona W GÓRĘ do 1 kg.
int ceilKg(double kg) => _snap(kg).ceil();

/// Nośność zaokrąglona W DÓŁ do 1 kg.
int floorKg(double kg) => _snap(kg).floor();

/// Dlaczego masy z rury nie da się policzyć.
enum PipeLoadProblem { od, wall, length, extra }

/// Masa ładunku z rury (spool): kg/m z istniejącej domeny ciężaru rur
/// (`pipeMassKgPerM`, gęstości `kPipeDensityKgM3`) × długość + dodatki
/// (kołnierze, armatura, zawartość), zaokrąglona w górę do 1 kg.
class PipeLoadMass {
  final double kgPerM;
  final double pipeKg;
  final double extraKg;

  /// Razem, zaokrąglone w górę.
  final int totalKg;

  const PipeLoadMass({
    required this.kgPerM,
    required this.pipeKg,
    required this.extraKg,
    required this.totalKg,
  });
}

/// Wynik liczenia masy z rury: masa albo problem z danymi.
class PipeLoadResult {
  final PipeLoadMass? mass;
  final PipeLoadProblem? problem;
  const PipeLoadResult.ok(PipeLoadMass this.mass) : problem = null;
  const PipeLoadResult.error(PipeLoadProblem this.problem) : mass = null;
}

/// [odMm] średnica zewnętrzna, [wallMm] ścianka, [lengthM] długość w metrach,
/// [extraKg] dodatki (puste = 0). Pusta / nieczytelna wartość → problem,
/// nigdy cicha zero.
PipeLoadResult pipeLoadMass({
  required double? odMm,
  required double? wallMm,
  required double? lengthM,
  required PipeMaterial material,
  double? extraKg = 0,
}) {
  if (odMm == null || !odMm.isFinite || odMm <= 0) {
    return const PipeLoadResult.error(PipeLoadProblem.od);
  }
  if (wallMm == null || !wallMm.isFinite || wallMm <= 0 || wallMm >= odMm / 2) {
    return const PipeLoadResult.error(PipeLoadProblem.wall);
  }
  if (lengthM == null || !lengthM.isFinite || lengthM <= 0) {
    return const PipeLoadResult.error(PipeLoadProblem.length);
  }
  if (extraKg == null || !extraKg.isFinite || extraKg < 0) {
    return const PipeLoadResult.error(PipeLoadProblem.extra);
  }
  final kgPerM = pipeMassKgPerM(odMm, wallMm, kPipeDensityKgM3[material]!);
  final pipeKg = kgPerM * lengthM;
  return PipeLoadResult.ok(PipeLoadMass(
    kgPerM: kgPerM,
    pipeKg: pipeKg,
    extraKg: extraKg,
    totalKg: ceilKg(pipeKg + extraKg),
  ));
}

// ═══════════════════════════════════════════════════════════════════════════
// TYPOSZEREG PASÓW
// ═══════════════════════════════════════════════════════════════════════════

/// Typoszereg WLL pasów [t]: 1–10 t z kodu kolorów EN 1492-1/-2, powyżej
/// typowe pasy okrągłe producentów (przyjęte w aplikacji).
const List<double> kSlingWllSeriesT = [
  1,
  2,
  3,
  4,
  5,
  6,
  8,
  10,
  12,
  15,
  20,
  25,
  30,
  40,
  50,
];

// ═══════════════════════════════════════════════════════════════════════════
// WERDYKT
// ═══════════════════════════════════════════════════════════════════════════

/// Etykieta zawiesia.
enum LabelState {
  /// Nie potwierdzono — brak werdyktu.
  unknown,

  /// Etykieta / zawieszka jest i jest czytelna (WLL odczytane z niej).
  readable,

  /// Brak albo nieczytelna — STOP, nie używać.
  missing,
}

enum RiggingVerdict {
  /// Nośność układu ≥ masa, wszystko podane.
  ok,

  /// STOP — nośność układu mniejsza niż masa.
  overload,

  /// STOP — β > 60°.
  angleNotAllowed,

  /// STOP — brak albo nieczytelna etykieta.
  noLabel,

  /// Brak werdyktu — brakuje danych (nigdy nie OK).
  incomplete;

  bool get isStop =>
      this == overload || this == angleNotAllowed || this == noLabel;
}

/// Czego brakuje do werdyktu.
enum RiggingIssue {
  massMissing,
  massInvalid,
  wllMissing,
  wllInvalid,
  angleMissing,
  angleInvalid,
  labelUnconfirmed,
}

/// Dane wejściowe — już w kilogramach i stopniach.
///
/// [massKg] / [wllKg]: `null` = pole puste; NaN = wpisano, ale
/// nieczytelne. Kąt: [angleValue] w konwencji [angleKind]; `null` =
/// puste, NaN = nieczytelne.
class RiggingInput {
  final double? massKg;
  final SlingType sling;
  final HitchMode mode;
  final bool chokedLegs;
  final double? angleValue;
  final AngleKind angleKind;
  final bool asymmetric;
  final double? wllKg;
  final LabelState label;

  const RiggingInput({
    required this.massKg,
    required this.sling,
    required this.mode,
    this.chokedLegs = false,
    this.angleValue,
    this.angleKind = AngleKind.fromVertical,
    this.asymmetric = false,
    required this.wllKg,
    required this.label,
  });

  RiggingInput copyWith({
    double? massKg,
    SlingType? sling,
    HitchMode? mode,
    bool? chokedLegs,
    double? angleValue,
    AngleKind? angleKind,
    bool? asymmetric,
    double? wllKg,
    LabelState? label,
  }) =>
      RiggingInput(
        massKg: massKg ?? this.massKg,
        sling: sling ?? this.sling,
        mode: mode ?? this.mode,
        chokedLegs: chokedLegs ?? this.chokedLegs,
        angleValue: angleValue ?? this.angleValue,
        angleKind: angleKind ?? this.angleKind,
        asymmetric: asymmetric ?? this.asymmetric,
        wllKg: wllKg ?? this.wllKg,
        label: label ?? this.label,
      );
}

/// Siła w cięgnie z fizyki — TYLKO informacyjnie.
class LegTension {
  /// Liczba cięgien przyjęta do wzoru.
  final int legs;
  final double betaDeg;

  /// T = W / (n · cos β), zaokrąglone w górę [kg].
  final int perLegKg;

  /// Przy 3–4 cięgnach: gdy niosą tylko dwa (sztywny ładunek).
  final int? perLegIfTwoCarryKg;

  const LegTension({
    required this.legs,
    required this.betaDeg,
    required this.perLegKg,
    this.perLegIfTwoCarryKg,
  });
}

class RiggingResult {
  final RiggingVerdict verdict;
  final List<RiggingIssue> issues;

  /// β od pionu (gdy podany i czytelny).
  final double? betaDeg;
  final AngleBand? band;

  /// Współczynnik przy symetrycznym ładunku i ten użyty do werdyktu
  /// (po niesymetrii).
  final ModeFactor? symmetricFactor;
  final ModeFactor? factor;

  /// Masa zaokrąglona w górę [kg].
  final int? massKg;

  /// WLL z etykiety [kg] (pełna precyzja).
  final double? wllKg;

  /// Nośność układu = WLL × współczynnik, zaokrąglona w dół [kg].
  final int? capacityKg;

  /// Najmniejsze WLL [kg], przy którym ten układ uniesie masę.
  final int? requiredWllKg;

  /// Najmniejszy pas z typoszeregu [t] (tylko pasy tekstylne); `null` —
  /// poza typoszeregiem albo nie dotyczy.
  final double? suggestedSeriesT;

  /// Siła w cięgnie (informacyjnie); `null` przy niesymetrii albo braku
  /// danych.
  final LegTension? tension;

  const RiggingResult({
    required this.verdict,
    this.issues = const [],
    this.betaDeg,
    this.band,
    this.symmetricFactor,
    this.factor,
    this.massKg,
    this.wllKg,
    this.capacityKg,
    this.requiredWllKg,
    this.suggestedSeriesT,
    this.tension,
  });

  /// Niesymetria obniżyła współczynnik.
  bool get asymmetryReduced =>
      factor != null &&
      symmetricFactor != null &&
      factor!.value < symmetricFactor!.value;
}

bool _validPositive(double? v) => v != null && v.isFinite && v > 0;

/// Nośność układu [kg] — WLL × współczynnik, w dół do 1 kg.
int capacityKg(double wllKg, ModeFactor f) => floorKg(wllKg * f.value);

/// Najmniejsze całkowite WLL [kg], dla którego [capacityKg] ≥ [massKg].
int requiredWllKg(int massKg, ModeFactor f) {
  var w = (massKg / f.value).ceil();
  if (w < 1) w = 1;
  while (floorKg(w * f.value) < massKg) {
    w++;
  }
  while (w > 1 && floorKg((w - 1) * f.value) >= massKg) {
    w--;
  }
  return w;
}

/// Najmniejszy pas z [kSlingWllSeriesT], który uniesie [massKg] w tym
/// układzie; `null` — ponad typoszereg.
double? suggestedSeriesT(int massKg, ModeFactor f) {
  for (final t in kSlingWllSeriesT) {
    if (capacityKg(t * 1000, f) >= massKg) return t;
  }
  return null;
}

/// Liczba cięgien do informacyjnej siły T.
int _tensionLegs(HitchMode mode) => switch (mode) {
      HitchMode.straight || HitchMode.choke => 1,
      HitchMode.basketParallel ||
      HitchMode.basketAngled ||
      HitchMode.twoLeg =>
        2,
      HitchMode.multiLeg => 3,
    };

/// T = W / (n · cos β) w górę do 1 kg — fizyka, informacyjnie.
LegTension legTension(int massKg, HitchMode mode, double betaDeg) {
  final n = _tensionLegs(mode);
  final cos = math.cos(betaDeg * math.pi / 180);
  return LegTension(
    legs: n,
    betaDeg: betaDeg,
    perLegKg: ceilKg(massKg / (n * cos)),
    perLegIfTwoCarryKg:
        mode == HitchMode.multiLeg ? ceilKg(massKg / (2 * cos)) : null,
  );
}

/// Ocena układu zawiesia.
///
/// Kolejność: brak etykiety → STOP; β > 60° → STOP; przeciążenie (gdy da się
/// policzyć — nawet przy niepotwierdzonej etykiecie, bo STOP nigdy nie jest
/// fałszywym „OK”) → STOP; braki → brak werdyktu; inaczej OK.
RiggingResult evaluateRigging(RiggingInput input) {
  final issues = <RiggingIssue>[];

  final massRaw = input.massKg;
  if (massRaw == null) {
    issues.add(RiggingIssue.massMissing);
  } else if (!_validPositive(massRaw)) {
    issues.add(RiggingIssue.massInvalid);
  }
  final wllRaw = input.wllKg;
  if (wllRaw == null) {
    issues.add(RiggingIssue.wllMissing);
  } else if (!_validPositive(wllRaw)) {
    issues.add(RiggingIssue.wllInvalid);
  }

  double? beta;
  AngleBand? band;
  if (input.mode.needsAngle) {
    final a = input.angleValue;
    if (a == null) {
      issues.add(RiggingIssue.angleMissing);
    } else {
      beta = betaFromInput(a, input.angleKind);
      if (beta == null) {
        issues.add(RiggingIssue.angleInvalid);
      } else {
        band = angleBand(beta);
      }
    }
  } else {
    // Proste, zadusznik, koszowe równoległe — cięgna pionowe.
    beta = 0;
  }
  if (input.label == LabelState.unknown) {
    issues.add(RiggingIssue.labelUnconfirmed);
  }

  final massKg = _validPositive(massRaw) ? ceilKg(massRaw!) : null;
  final wllKg = _validPositive(wllRaw) ? wllRaw : null;

  final sym = modeFactor(input.sling, input.mode,
      band: band, chokedLegs: input.chokedLegs);
  final factor = sym == null
      ? null
      : input.asymmetric
          ? applyAsymmetry(sym, input.sling, input.mode,
              chokedLegs: input.chokedLegs)
          : sym;

  final capacity =
      wllKg != null && factor != null ? capacityKg(wllKg, factor) : null;
  final required =
      massKg != null && factor != null ? requiredWllKg(massKg, factor) : null;
  final series = massKg != null && factor != null && input.sling.isTextile
      ? suggestedSeriesT(massKg, factor)
      : null;
  final tension = massKg != null &&
          beta != null &&
          band != AngleBand.over60 &&
          !input.asymmetric
      ? legTension(massKg, input.mode, beta)
      : null;

  RiggingResult result(RiggingVerdict v) => RiggingResult(
        verdict: v,
        issues: List.unmodifiable(issues),
        betaDeg: beta,
        band: band,
        symmetricFactor: sym,
        factor: factor,
        massKg: massKg,
        wllKg: wllKg,
        capacityKg: capacity,
        requiredWllKg: required,
        suggestedSeriesT: series,
        tension: tension,
      );

  if (input.label == LabelState.missing) return result(RiggingVerdict.noLabel);
  if (band == AngleBand.over60) return result(RiggingVerdict.angleNotAllowed);
  if (capacity != null && massKg != null && capacity < massKg) {
    return result(RiggingVerdict.overload);
  }
  if (issues.isNotEmpty || capacity == null || massKg == null) {
    return result(RiggingVerdict.incomplete);
  }
  return result(RiggingVerdict.ok);
}
