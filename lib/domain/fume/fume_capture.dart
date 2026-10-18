/// Kalkulator zasięgu odciągu miejscowego (ssawka, ramię odciągowe) —
/// równanie DallaValle.
///
///   otwór swobodny:     Q = V · (10·X² + A)
///   otwór z kołnierzem: Q = 0,75 · V · (10·X² + A)
///
/// Q — wydajność [m³/s], V — prędkość uchwycenia w punkcie X [m/s],
/// X — odległość od otworu wzdłuż osi [m], A — pole otworu [m²].
/// Źródła i granice ważności: fume_sources.dart.
///
/// Zasady zapisane w kodzie (i w testach):
/// * wejście w dowolnej jednostce (m³/h, l/s, cfm; mm, cm) jest najpierw
///   przeliczane na SI i zaokrąglane do 1e-9 — te same wielkości fizyczne
///   dają IDENTYCZNY wynik niezależnie od jednostki wpisu;
/// * maksymalna odległość X — w DÓŁ do pełnego centymetra, wymagana
///   wydajność — w GÓRĘ do pełnej jednostki wyświetlanej (1 m³/h, 1 l/s,
///   1 cfm), prędkość przy łuku — w DÓŁ do 0,01 m/s;
/// * prędkość uchwycenia nie może być niższa niż minimum procesu
///   ([FumeCaptureInput.minCaptureVelocity]; próg tylko zaostrzalny);
/// * poza zakresem ważności równania (X > 1,5·D, szczelina) wynik nigdy nie
///   jest „ok” — co najwyżej „ostrożnie”, z poleceniem „przyjmij bliżej”;
/// * puste albo nieczytelne pole to brak wyniku, nie zero.
///
/// Czysty Dart.
library;

import 'dart:math' as math;

import 'fume_sources.dart';

/// Tolerancja porównań — tylko szum liczb zmiennoprzecinkowych.
const double kFumeEps = 1e-9;

/// Wielkość w SI zaokrąglona do 1e-9 — wspólny punkt wyjścia dla każdej
/// jednostki wpisu.
double fumeCanon(double v) => (v * 1e9).roundToDouble() / 1e9;

// ── Jednostki ──────────────────────────────────────────────────────────────

/// Jednostka wydajności odciągu.
enum FumeFlowUnit {
  /// m³/h — tabliczka i karta katalogowa w Europie.
  m3h('m³/h'),

  /// l/s — część kart katalogowych i norm.
  ls('l/s'),

  /// ft³/min — urządzenia z rynku USA.
  cfm('cfm');

  const FumeFlowUnit(this.symbol);
  final String symbol;

  /// Wartość w tej jednostce → m³/s (bez zaokrąglenia).
  double toM3s(double v) => switch (this) {
        FumeFlowUnit.m3h => v / 3600,
        FumeFlowUnit.ls => v / 1000,
        // 1 ft³ = 0,028316846592 m³ (dokładnie).
        FumeFlowUnit.cfm => v * 0.028316846592 / 60,
      };

  /// m³/s → ta jednostka.
  double fromM3s(double q) => switch (this) {
        FumeFlowUnit.m3h => q * 3600,
        FumeFlowUnit.ls => q * 1000,
        FumeFlowUnit.cfm => q * 60 / 0.028316846592,
      };

  static FumeFlowUnit? byName(Object? name) {
    for (final u in values) {
      if (u.name == name) return u;
    }
    return null;
  }
}

/// Jednostka długości (wymiary ssawki i odległość od łuku).
enum FumeLengthUnit {
  mm('mm', 1000),
  cm('cm', 100);

  const FumeLengthUnit(this.symbol, this.perMetre);
  final String symbol;

  /// Ile jednostek w metrze.
  final double perMetre;

  double toM(double v) => v / perMetre;
  double fromM(double m) => m * perMetre;

  static FumeLengthUnit? byName(Object? name) {
    for (final u in values) {
      if (u.name == name) return u;
    }
    return null;
  }
}

/// Kształt otworu ssawki.
enum FumeHoodShape {
  round,
  rectangular;

  static FumeHoodShape? byName(Object? name) {
    for (final s in values) {
      if (s.name == name) return s;
    }
    return null;
  }
}

// ── Limity wejścia (sensowność pola, nie fizyka) ───────────────────────────

/// Wydajność ponad 100 000 m³/h to pomyłka w polu, nie ramię odciągowe.
const double kFumeMaxFlowM3s = 100000 / 3600;

/// Wymiar otworu ponad 2 m — pomyłka w polu.
const double kFumeMaxOpeningM = 2;

/// Odległość od łuku ponad 3 m — pomyłka w polu.
const double kFumeMaxDistanceM = 3;

/// Prędkość uchwycenia ponad 10 m/s — pomyłka w polu.
const double kFumeMaxCaptureMs = 10;

// ── Wejście ────────────────────────────────────────────────────────────────

/// Dane kalkulatora. `null` — pole puste; [double.nan] — pole nieczytelne.
/// Liczby w jednostkach [flowUnit] i [lengthUnit], tak jak je wpisano.
class FumeCaptureInput {
  const FumeCaptureInput({
    this.flow,
    this.flowUnit = FumeFlowUnit.m3h,
    this.shape = FumeHoodShape.round,
    this.diameter,
    this.width,
    this.height,
    this.lengthUnit = FumeLengthUnit.mm,
    this.flanged = false,
    this.captureVelocity = kFumeCaptureDefaultMs,
    this.minCaptureVelocity = kFumeCaptureMinMs,
    this.distance,
  });

  final double? flow;
  final FumeFlowUnit flowUnit;
  final FumeHoodShape shape;

  /// Średnica otworu (kształt okrągły).
  final double? diameter;

  /// Boki otworu (kształt prostokątny).
  final double? width;
  final double? height;

  final FumeLengthUnit lengthUnit;

  /// Otwór z kołnierzem (płaska kryza wokół otworu).
  final bool flanged;

  /// Prędkość uchwycenia przy łuku [m/s].
  final double? captureVelocity;

  /// Najniższa dopuszczalna prędkość uchwycenia dla procesu [m/s]
  /// (`fumeCaptureMinFor`) — niższej nie przyjmujemy.
  final double minCaptureVelocity;

  /// Odległość ssawka–łuk (opcjonalna) — wtedy liczy się też wymagana
  /// wydajność.
  final double? distance;
}

enum FumeCaptureProblem {
  /// Brak wymiaru otworu.
  openingMissing,

  /// Wymiar nieczytelny albo ≤ 0.
  openingInvalid,

  /// Wymiar ponad [kFumeMaxOpeningM].
  openingTooLarge,

  /// Wydajność nieczytelna albo ≤ 0 (puste pole to nie błąd).
  flowInvalid,

  /// Wydajność ponad [kFumeMaxFlowM3s].
  flowTooHigh,

  /// Brak prędkości uchwycenia.
  velocityMissing,

  /// Prędkość nieczytelna.
  velocityInvalid,

  /// Prędkość poniżej minimum procesu — próg tylko zaostrzalny.
  velocityBelowMin,

  /// Prędkość ponad [kFumeMaxCaptureMs].
  velocityTooHigh,

  /// Odległość nieczytelna albo ≤ 0 (puste pole to nie błąd).
  distanceInvalid,

  /// Odległość ponad [kFumeMaxDistanceM].
  distanceTooFar,

  /// Ani wydajności, ani odległości — nie ma czego liczyć.
  nothingToCompute,
}

/// Problem jednego pola liczbowego: null — poprawne albo puste.
FumeCaptureProblem? _fieldProblem(
    double? v,
    double? maxSi,
    double Function(double) toSi,
    FumeCaptureProblem invalid,
    FumeCaptureProblem tooHigh) {
  if (v == null) return null;
  if (!v.isFinite || v <= 0) return invalid;
  if (maxSi != null && toSi(v) > maxSi + kFumeEps) return tooHigh;
  return null;
}

/// Co psuje albo uniemożliwia obliczenie. Kolejność: otwór, wydajność,
/// prędkość, odległość, brak czegokolwiek do liczenia.
List<FumeCaptureProblem> fumeCaptureProblems(FumeCaptureInput i) {
  final out = <FumeCaptureProblem>[];
  final dims =
      i.shape == FumeHoodShape.round ? [i.diameter] : [i.width, i.height];
  if (dims.any((d) => d == null)) {
    out.add(FumeCaptureProblem.openingMissing);
  }
  for (final d in dims) {
    final p = _fieldProblem(d, kFumeMaxOpeningM, i.lengthUnit.toM,
        FumeCaptureProblem.openingInvalid, FumeCaptureProblem.openingTooLarge);
    if (p != null && !out.contains(p)) out.add(p);
  }
  final f = _fieldProblem(i.flow, kFumeMaxFlowM3s, i.flowUnit.toM3s,
      FumeCaptureProblem.flowInvalid, FumeCaptureProblem.flowTooHigh);
  if (f != null) out.add(f);
  final v = i.captureVelocity;
  if (v == null) {
    out.add(FumeCaptureProblem.velocityMissing);
  } else if (!v.isFinite || v <= 0) {
    out.add(FumeCaptureProblem.velocityInvalid);
  } else if (v < i.minCaptureVelocity - kFumeEps) {
    out.add(FumeCaptureProblem.velocityBelowMin);
  } else if (v > kFumeMaxCaptureMs + kFumeEps) {
    out.add(FumeCaptureProblem.velocityTooHigh);
  }
  final x = _fieldProblem(i.distance, kFumeMaxDistanceM, i.lengthUnit.toM,
      FumeCaptureProblem.distanceInvalid, FumeCaptureProblem.distanceTooFar);
  if (x != null) out.add(x);
  if (i.flow == null && i.distance == null) {
    out.add(FumeCaptureProblem.nothingToCompute);
  }
  return out;
}

// ── Wynik ──────────────────────────────────────────────────────────────────

/// Ocena — wspólna skala modułu.
enum FumeLevel {
  /// Zielone — spełnione w zakresie, który aplikacja umie sprawdzić.
  ok,

  /// Żółte — nie zielone: poza zakresem równania, brak danych do pełnej
  /// oceny, brak odciągu przy wystarczającej ŚOI…
  caution,

  /// Czerwone — nie wystarcza.
  stop,

  /// Brak danych — nie ma oceny (to NIE jest „ok”).
  incomplete;

  /// Gorsza z dwóch ocen: stop > caution > incomplete > ok.
  FumeLevel worse(FumeLevel other) =>
      _rank(this) >= _rank(other) ? this : other;

  static int _rank(FumeLevel l) => switch (l) {
        FumeLevel.ok => 0,
        FumeLevel.incomplete => 1,
        FumeLevel.caution => 2,
        FumeLevel.stop => 3,
      };
}

/// Stan zasięgu policzonego z wydajności.
enum FumeReachState {
  /// X w zakresie ważności równania.
  within,

  /// X wyszedł ponad 1,5·D — równanie tego nie gwarantuje.
  beyondValidity,

  /// Wydajność nie daje prędkości uchwycenia nawet 1 cm od otworu.
  tooLowFlow,
}

/// Wynik kalkulatora (wszystko w SI; zaokrąglone wartości do ekranu
/// w polach `…Cm`, `…Display`).
class FumeCaptureResult {
  const FumeCaptureResult({
    required this.input,
    required this.areaM2,
    required this.coefficient,
    required this.velocityMs,
    required this.characteristicM,
    required this.isSlot,
    this.flowM3s,
    this.reachM,
    this.distanceM,
    this.requiredFlowM3s,
    this.velocityAtDistanceMs,
    this.distanceProblem,
  });

  final FumeCaptureInput input;

  /// Pole odległości wpisane, ale błędne ([FumeCaptureProblem.distanceInvalid])
  /// albo ponad limit ([FumeCaptureProblem.distanceTooFar]) — wtedy ocena
  /// nigdy nie jest „ok” (błędne pole nie znika po cichu).
  final FumeCaptureProblem? distanceProblem;

  /// Pole otworu A [m²].
  final double areaM2;

  /// 1,0 — otwór swobodny; 0,75 — z kołnierzem.
  final double coefficient;

  /// Prędkość uchwycenia V [m/s].
  final double velocityMs;

  /// Wymiar charakterystyczny D [m]: średnica albo KRÓTSZY bok — granica
  /// ważności liczy się od niego (krótszy bok daje ostrzejszą granicę).
  final double characteristicM;

  /// Otwór prostokątny o stosunku boków < [kFumeMinAspectRatio] —
  /// szczelina, równanie nie dotyczy.
  final bool isSlot;

  /// Wydajność Q [m³/s] (null — pole puste).
  final double? flowM3s;

  /// Dokładne X z równania [m]; 0 — Q nie wystarcza nawet przy otworze.
  final double? reachM;

  /// Odległość wpisana [m].
  final double? distanceM;

  /// Wymagana Q [m³/s] przy [distanceM].
  final double? requiredFlowM3s;

  /// Prędkość w osi przy [distanceM] dla wpisanej Q [m/s].
  final double? velocityAtDistanceMs;

  /// Granica ważności równania: 1,5·D [m].
  double get validityLimitM => kFumeDallaValleMaxXOverD * characteristicM;

  /// Granica ważności w DÓŁ do pełnego cm.
  int get validityLimitCm => fumeFloorCm(validityLimitM);

  /// Zasięg w DÓŁ do pełnego cm (null — brak Q).
  int? get reachCm => reachM == null ? null : fumeFloorCm(reachM!);

  /// Odległość, której wolno używać: zasięg, ale nie dalej niż granica
  /// ważności (oba w dół do cm).
  int? get safeReachCm {
    final r = reachCm;
    if (r == null) return null;
    return math.min(r, validityLimitCm);
  }

  FumeReachState? get reachState {
    final r = reachM;
    if (r == null) return null;
    if (fumeFloorCm(r) < 1) return FumeReachState.tooLowFlow;
    if (r > validityLimitM + kFumeEps) return FumeReachState.beyondValidity;
    return FumeReachState.within;
  }

  /// Wpisana odległość mieści się w granicy ważności.
  bool? get distanceWithinValidity =>
      distanceM == null ? null : distanceM! <= validityLimitM + kFumeEps;

  /// Wpisana Q wystarcza na wpisaną odległość (null — brak jednego z nich).
  bool? get flowSufficient {
    final q = flowM3s;
    final need = requiredFlowM3s;
    if (q == null || need == null) return null;
    return q >= need - kFumeEps;
  }

  /// Wymagana wydajność w jednostce [u], w GÓRĘ do pełnej jednostki.
  int? requiredFlowDisplay(FumeFlowUnit u) {
    final q = requiredFlowM3s;
    if (q == null) return null;
    return fumeCeil(u.fromM3s(q));
  }

  /// Prędkość przy wpisanej odległości w DÓŁ do 0,01 m/s.
  double? get velocityAtDistanceDisplay {
    final v = velocityAtDistanceMs;
    if (v == null) return null;
    return fumeFloor(v * 100) / 100;
  }

  /// Prędkość przy łuku ponad [kFumeShieldDraughtMs] (ACGIH VS-90-02,
  /// HSE RR683) — ryzyko zakłócenia osłony gazowej.
  bool get shieldDraughtRisk {
    final v = velocityAtDistanceMs;
    return v != null && v > kFumeShieldDraughtMs + kFumeEps;
  }

  /// Ocena kalkulatora. „Ok” tylko wtedy, gdy podano RZECZYWISTĄ odległość
  /// ssawki od łuku, wydajność na nią wystarcza i odległość mieści się
  /// w zakresie równania. Sam zasięg z wydajności (bez odległości) to
  /// informacja, nie potwierdzenie — [FumeLevel.incomplete].
  FumeLevel get level {
    final fromDistance = switch (distanceProblem) {
      FumeCaptureProblem.distanceTooFar => FumeLevel.stop,
      FumeCaptureProblem.distanceInvalid => FumeLevel.incomplete,
      _ => FumeLevel.ok,
    };
    return _baseLevel.worse(fromDistance);
  }

  FumeLevel get _baseLevel {
    if (isSlot) return FumeLevel.caution;
    final hasQ = flowM3s != null;
    final hasX = distanceM != null;
    if (hasQ && reachState == FumeReachState.tooLowFlow) return FumeLevel.stop;
    if (hasQ && hasX) {
      if (flowSufficient != true) return FumeLevel.stop;
      if (distanceWithinValidity != true) return FumeLevel.caution;
      return FumeLevel.ok;
    }
    // Sam zasięg albo sama wymagana wydajność — nie ma czego porównać.
    return FumeLevel.incomplete;
  }

  /// Brakuje rzeczywistej odległości ssawki od łuku (pole puste).
  bool get distanceMissing => distanceM == null && distanceProblem == null;
}

/// Liczba ≥ 0 w DÓŁ do całości, odporna na szum (2,9999999999 → 3).
int fumeFloor(double v) => (v + kFumeEps).floor();

/// Liczba w GÓRĘ do całości, odporna na szum (848,0000000001 → 848).
int fumeCeil(double v) => (v - kFumeEps).ceil();

/// Metry → pełne cm w DÓŁ.
int fumeFloorCm(double m) => fumeFloor(m * 100);

/// Wynik albo `null`, gdy dane nie pozwalają liczyć ([fumeCaptureProblems]
/// zawiera problem otworu, prędkości albo nic nie wpisano). Błędne pole
/// wydajności wyłącza tylko tę część wyniku; błędne pole odległości też,
/// ale zostaje w [FumeCaptureResult.distanceProblem] i psuje ocenę.
FumeCaptureResult? computeFumeCapture(FumeCaptureInput i) {
  final problems = fumeCaptureProblems(i);
  const blocking = {
    FumeCaptureProblem.openingMissing,
    FumeCaptureProblem.openingInvalid,
    FumeCaptureProblem.openingTooLarge,
    FumeCaptureProblem.velocityMissing,
    FumeCaptureProblem.velocityInvalid,
    FumeCaptureProblem.velocityBelowMin,
    FumeCaptureProblem.velocityTooHigh,
    FumeCaptureProblem.nothingToCompute,
  };
  if (problems.any(blocking.contains)) return null;
  final flowOk = !problems.contains(FumeCaptureProblem.flowInvalid) &&
      !problems.contains(FumeCaptureProblem.flowTooHigh) &&
      i.flow != null;
  final distanceProblem = problems.contains(FumeCaptureProblem.distanceTooFar)
      ? FumeCaptureProblem.distanceTooFar
      : problems.contains(FumeCaptureProblem.distanceInvalid)
          ? FumeCaptureProblem.distanceInvalid
          : null;
  final distOk = distanceProblem == null && i.distance != null;
  if (!flowOk && !distOk && distanceProblem == null) return null;

  final u = i.lengthUnit;
  final double area;
  final double characteristic;
  var slot = false;
  if (i.shape == FumeHoodShape.round) {
    final d = fumeCanon(u.toM(i.diameter!));
    area = math.pi * d * d / 4;
    characteristic = d;
  } else {
    final w = fumeCanon(u.toM(i.width!));
    final h = fumeCanon(u.toM(i.height!));
    area = w * h;
    final short = math.min(w, h);
    final long = math.max(w, h);
    characteristic = short;
    slot = short / long < kFumeMinAspectRatio - kFumeEps;
  }
  final k = i.flanged ? kFumeFlangeFactor : 1.0;
  final v = fumeCanon(i.captureVelocity!);

  final q = flowOk ? fumeCanon(i.flowUnit.toM3s(i.flow!)) : null;
  double? reach;
  if (q != null && !slot) {
    final inner = (q / (k * v) - area) / 10;
    reach = inner <= 0 ? 0 : math.sqrt(inner);
  }
  final x = distOk ? fumeCanon(u.toM(i.distance!)) : null;
  double? required;
  double? vAtX;
  if (x != null && !slot) {
    required = k * v * (10 * x * x + area);
    if (q != null) vAtX = q / (k * (10 * x * x + area));
  }
  return FumeCaptureResult(
    input: i,
    areaM2: area,
    coefficient: k,
    velocityMs: v,
    characteristicM: characteristic,
    isSlot: slot,
    flowM3s: q,
    reachM: reach,
    distanceM: x,
    requiredFlowM3s: required,
    velocityAtDistanceMs: vAtX,
    distanceProblem: distanceProblem,
  );
}

// ── Formatowanie ───────────────────────────────────────────────────────────

/// Liczba do pola / tekstu: do [decimals] miejsc, bez zbędnych zer,
/// przecinek po polsku. `0.5` → „0,5”.
String formatFumeNumber(double v, {required bool en, int decimals = 3}) {
  var s = v.toStringAsFixed(decimals);
  if (s.contains('.')) s = s.replaceFirst(RegExp(r'\.?0+$'), '');
  if (s == '-0') s = '0';
  return en ? s : s.replaceAll('.', ',');
}

/// Wartość pola po zmianie jednostki długości: przesunięcie przecinka jest
/// dokładne (mm ↔ cm), więc wynik to ta sama długość.
double convertFumeLength(double v, FumeLengthUnit from, FumeLengthUnit to) {
  if (from == to) return v;
  // Do 6 miejsc po przecinku — przesunięcie o jedno miejsce nie gubi cyfr
  // wpisanych z rozsądną dokładnością.
  final m = from.toM(v);
  final r = to.fromM(m);
  return double.parse(r.toStringAsFixed(6));
}

/// Wartość pola po zmianie jednostki wydajności — w DÓŁ do 0,01 nowej
/// jednostki (bezpieczniej założyć odrobinę mniej powietrza).
double convertFumeFlow(double v, FumeFlowUnit from, FumeFlowUnit to) {
  if (from == to) return v;
  final r = to.fromM3s(from.toM3s(v));
  return fumeFloor(r * 100) / 100;
}
