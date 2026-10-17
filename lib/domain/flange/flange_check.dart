/// Odbiór połączenia kołnierzowego przed skręceniem: osiowanie wg ASME
/// PCC-1-2019 zał. E, lista kontrolna montażu i werdykt protokołu.
///
/// Domena czysta (bez Fluttera): model protokołu, ocena kryteriów,
/// przeliczenia mm ↔ cale, formatowanie liczb i JSON. Ekran:
/// `lib/features/flange_check/flange_check_page.dart`, zapis:
/// `flange_check_store.dart` obok ekranu (SharedPreferences), eksport:
/// `lib/services/flange_check_export.dart`.
///
/// Zasada werdyktu: zielony TYLKO gdy każde kryterium ma pomiar w granicy
/// i każdy punkt listy jest odhaczony. Brak pomiaru to nie „OK” — to
/// „niekompletny”. Jedno kryterium poza granicą = „niezgodny”, nawet gdy
/// innych pomiarów jeszcze brak.
library;

import 'dart:convert';
import 'dart:math' as math;

import '../quotes/quote_calculator.dart' show formatQty;
import 'flange_pcc1.dart';

export 'flange_pcc1.dart';

/// Dokładnie: 1 cal = 25,4 mm.
const double kMmPerInch = 25.4;

/// Tolerancja porównań w mm — 0,8 − 0,8 liczone na liczbach zmiennoprzecinkowych
/// daje czasem 0,800000000003; pomiar „na granicy” ma przechodzić.
const double _kEpsMm = 1e-6;

/// Liczby śrub w kołnierzu: od 4 do 64, wielokrotność 4.
const int kMinBolts = 4;
const int kMaxBolts = 64;

/// Dozwolone liczby punktów pomiaru szczeliny po obwodzie.
const List<int> kGapPointCounts = [4, 8];

/// Od tej średnicy podpowiadamy 8 punktów pomiaru szczeliny zamiast 4.
/// To praktyka (przy dużym obwodzie 4 punkty łatwo „przegapiają” klin),
/// nie wymóg PCC-1 — monter może zawsze wybrać sam.
const int kEightPointMinDn = 300;

enum LengthUnit { mm, inch }

double mmToUnit(double mm, LengthUnit u) =>
    u == LengthUnit.mm ? mm : mm / kMmPerInch;

double unitToMm(double v, LengthUnit u) =>
    u == LengthUnit.mm ? v : v * kMmPerInch;

// ═══════════════════════════════════════════════════════════════════════════
// TOLERANCJE
// ═══════════════════════════════════════════════════════════════════════════

/// Granica w obu układach, tak jak podaje ją PCC-1: „1.5 mm (1/16 in.)”.
///
/// Wartości metryczna i calowa w normie NIE są dokładnym przeliczeniem
/// (1/16" = 1,5875 mm, nie 1,5 mm). Pomiar ocenia się w układzie, w którym go
/// zrobiono: protokół w calach porównuje z 1/16", w mm — z 1,5 mm. Dzięki
/// temu odczyt dokładnie 1/16" z calowej szczelinomierki nie jest „poza
/// tolerancją” tylko dlatego, że jest o 0,09 mm większy od wersji metrycznej.
class DualLimit {
  final double mm;
  final double inch;

  const DualLimit(this.mm, this.inch);

  /// Własna granica wpisana w mm — wartość calowa to dokładne przeliczenie.
  factory DualLimit.fromMm(double mm) => DualLimit(mm, mm / kMmPerInch);

  /// Własna granica wpisana w calach — wartość w mm to dokładne przeliczenie.
  factory DualLimit.fromInch(double inch) => DualLimit(inch * kMmPerInch, inch);

  /// Nowa granica wpisana w jednostce [u].
  factory DualLimit.entered(double v, LengthUnit u) =>
      u == LengthUnit.mm ? DualLimit.fromMm(v) : DualLimit.fromInch(v);

  /// Granica w jednostce [u] (tak, jak ją pokazujemy i wpisujemy).
  double inUnit(LengthUnit u) => u == LengthUnit.mm ? mm : inch;

  /// Granica w mm dla protokołu mierzonego w jednostce [u].
  double limitMm(LengthUnit u) => u == LengthUnit.mm ? mm : inch * kMmPerInch;

  bool get isValid => mm.isFinite && inch.isFinite && mm > 0 && inch > 0;

  Map<String, Object?> toJson() => {'mm': mm, 'in': inch};

  static DualLimit? fromJson(Object? json) {
    if (json is! Map) return null;
    final mm = _num(json['mm']);
    final inch = _num(json['in']);
    if (mm == null || inch == null) return null;
    final l = DualLimit(mm, inch);
    return l.isValid ? l : null;
  }

  @override
  bool operator ==(Object other) =>
      other is DualLimit && other.mm == mm && other.inch == inch;

  @override
  int get hashCode => Object.hash(mm, inch);
}

/// Zestaw tolerancji osiowania. Domyślnie [FlangeTolerances.pcc1]; zakład
/// bywa ostrzejszy, więc każdą wartość można zmienić — protokół zapisuje,
/// z jakimi tolerancjami go oceniono.
class FlangeTolerances {
  /// Przesunięcie osi (centerline high/low).
  final DualLimit centerline;

  /// Równoległość: różnica max − min szczeliny po obwodzie.
  final DualLimit parallelism;

  /// Przesunięcie obrotowe otworów (two-hole / rotational).
  final DualLimit rotation;

  /// Największa szczelina ≤ [gapFactor] × grubość uszczelki.
  final double gapFactor;

  const FlangeTolerances({
    required this.centerline,
    required this.parallelism,
    required this.rotation,
    required this.gapFactor,
  });

  /// ASME PCC-1-2019 zał. E — wartości i źródła w `flange_pcc1.dart`.
  static const FlangeTolerances pcc1 = FlangeTolerances(
    centerline: kPcc1Centerline,
    parallelism: kPcc1Parallelism,
    rotation: kPcc1Rotation,
    gapFactor: kPcc1GapFactor,
  );

  bool get isPcc1 => this == pcc1;

  bool get isValid =>
      centerline.isValid &&
      parallelism.isValid &&
      rotation.isValid &&
      gapFactor.isFinite &&
      gapFactor > 0;

  FlangeTolerances copyWith({
    DualLimit? centerline,
    DualLimit? parallelism,
    DualLimit? rotation,
    double? gapFactor,
  }) =>
      FlangeTolerances(
        centerline: centerline ?? this.centerline,
        parallelism: parallelism ?? this.parallelism,
        rotation: rotation ?? this.rotation,
        gapFactor: gapFactor ?? this.gapFactor,
      );

  Map<String, Object?> toJson() => {
        'centerline': centerline.toJson(),
        'parallelism': parallelism.toJson(),
        'rotation': rotation.toJson(),
        'gapFactor': gapFactor,
      };

  /// Brakujące lub zepsute pole → wartość PCC-1 (nigdy wyjątek).
  static FlangeTolerances fromJson(Object? json) {
    if (json is! Map) return pcc1;
    final factor = _num(json['gapFactor']);
    return FlangeTolerances(
      centerline: DualLimit.fromJson(json['centerline']) ?? pcc1.centerline,
      parallelism: DualLimit.fromJson(json['parallelism']) ?? pcc1.parallelism,
      rotation: DualLimit.fromJson(json['rotation']) ?? pcc1.rotation,
      gapFactor: factor != null && factor > 0 ? factor : pcc1.gapFactor,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is FlangeTolerances &&
      other.centerline == centerline &&
      other.parallelism == parallelism &&
      other.rotation == rotation &&
      other.gapFactor == gapFactor;

  @override
  int get hashCode => Object.hash(centerline, parallelism, rotation, gapFactor);
}

// ═══════════════════════════════════════════════════════════════════════════
// DANE POŁĄCZENIA
// ═══════════════════════════════════════════════════════════════════════════

/// DN i odpowiadające mu NPS — rury i kołnierze B16.5 (do NPS 24) oraz
/// B16.47 (NPS 26–60).
const List<(int, String)> kFlangeSizes = [
  (15, '1/2'),
  (20, '3/4'),
  (25, '1'),
  (32, '1 1/4'),
  (40, '1 1/2'),
  (50, '2'),
  (65, '2 1/2'),
  (80, '3'),
  (100, '4'),
  (125, '5'),
  (150, '6'),
  (200, '8'),
  (250, '10'),
  (300, '12'),
  (350, '14'),
  (400, '16'),
  (450, '18'),
  (500, '20'),
  (600, '24'),
  (650, '26'),
  (700, '28'),
  (750, '30'),
  (800, '32'),
  (850, '34'),
  (900, '36'),
  (950, '38'),
  (1000, '40'),
  (1050, '42'),
  (1100, '44'),
  (1150, '46'),
  (1200, '48'),
  (1300, '52'),
  (1400, '56'),
  (1500, '60'),
];

/// „DN150 / 6"”, albo samo „DN…” dla średnicy spoza tabeli.
String flangeSizeLabel(int dn) {
  final nps = kFlangeSizes.where((s) => s.$1 == dn).firstOrNull?.$2;
  return nps == null ? 'DN$dn' : 'DN$dn / $nps"';
}

/// 8 punktów dla dużych średnic, inaczej 4.
int recommendedGapPoints(int? dn) =>
    dn != null && dn >= kEightPointMinDn ? 8 : 4;

/// Liczba śrub w granicach 4–64 i wielokrotnością 4.
bool isValidBoltCount(int n) => n >= kMinBolts && n <= kMaxBolts && n % 4 == 0;

class FlangeJoint {
  /// Oznaczenie: nr linii / kołnierza (np. „L-101-F1”).
  final String tag;
  final int? dn;

  /// Klasa / PN jako tekst: „150”, „CL300”, „PN40”.
  final String rating;
  final String gasketType;
  final double? gasketThicknessMm;
  final String boltGrade;
  final int? boltCount;

  /// Miejsce / projekt.
  final String location;
  final String fitter;

  /// Data odbioru `RRRR-MM-DD`.
  final String date;

  const FlangeJoint({
    this.tag = '',
    this.dn,
    this.rating = '',
    this.gasketType = '',
    this.gasketThicknessMm,
    this.boltGrade = '',
    this.boltCount,
    this.location = '',
    this.fitter = '',
    this.date = '',
  });

  FlangeJoint copyWith({
    String? tag,
    int? Function()? dn,
    String? rating,
    String? gasketType,
    double? Function()? gasketThicknessMm,
    String? boltGrade,
    int? Function()? boltCount,
    String? location,
    String? fitter,
    String? date,
  }) =>
      FlangeJoint(
        tag: tag ?? this.tag,
        dn: dn != null ? dn() : this.dn,
        rating: rating ?? this.rating,
        gasketType: gasketType ?? this.gasketType,
        gasketThicknessMm: gasketThicknessMm != null
            ? gasketThicknessMm()
            : this.gasketThicknessMm,
        boltGrade: boltGrade ?? this.boltGrade,
        boltCount: boltCount != null ? boltCount() : this.boltCount,
        location: location ?? this.location,
        fitter: fitter ?? this.fitter,
        date: date ?? this.date,
      );

  Map<String, Object?> toJson() => {
        'tag': tag,
        'dn': dn,
        'rating': rating,
        'gasketType': gasketType,
        'gasketMm': gasketThicknessMm,
        'boltGrade': boltGrade,
        'boltCount': boltCount,
        'location': location,
        'fitter': fitter,
        'date': date,
      };

  static FlangeJoint fromJson(Object? json) {
    if (json is! Map) return const FlangeJoint();
    final dn = _num(json['dn']);
    final bolts = _num(json['boltCount']);
    return FlangeJoint(
      tag: _str(json['tag']),
      dn: dn != null && dn > 0 ? dn.round() : null,
      rating: _str(json['rating']),
      gasketType: _str(json['gasketType']),
      gasketThicknessMm: _num(json['gasketMm']),
      boltGrade: _str(json['boltGrade']),
      boltCount: bolts?.round(),
      location: _str(json['location']),
      fitter: _str(json['fitter']),
      date: _str(json['date']),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// POMIARY
// ═══════════════════════════════════════════════════════════════════════════

/// Siła potrzebna do zbliżenia i zestawienia kołnierzy (ocena jakościowa).
enum AlignmentForce {
  /// Ręcznie / niewielką siłą — śruby wchodzą w otwory bez forsowania.
  light,

  /// Potrzebna duża siła: ściąganie śrubami, wciągarką, klinami.
  heavy,
}

class FlangeMeasurements {
  /// Przesunięcie osi (high/low), mm — wartość bezwzględna.
  final double? centerlineMm;

  /// Przesunięcie obrotowe otworów, mm.
  final double? rotationMm;

  /// Szczelina między powierzchniami w 4 lub 8 punktach po obwodzie, mm.
  /// Punkt `i` leży pod kątem `360° / n · i` (0° = góra, „godzina 12”).
  final List<double?> gapsMm;

  /// `null` — nie oceniono.
  final AlignmentForce? force;

  const FlangeMeasurements({
    this.centerlineMm,
    this.rotationMm,
    this.gapsMm = const [null, null, null, null],
    this.force,
  });

  factory FlangeMeasurements.empty({int points = 4}) => FlangeMeasurements(
      gapsMm: List<double?>.filled(_validPoints(points), null));

  int get gapPointCount => gapsMm.length;

  bool get isEmpty =>
      centerlineMm == null &&
      rotationMm == null &&
      force == null &&
      gapsMm.every((g) => g == null);

  List<double> get enteredGaps => [
        for (final g in gapsMm)
          if (g != null) g
      ];

  bool get allGapsEntered => gapsMm.every((g) => g != null);

  FlangeMeasurements copyWith({
    double? Function()? centerlineMm,
    double? Function()? rotationMm,
    List<double?>? gapsMm,
    AlignmentForce? Function()? force,
  }) =>
      FlangeMeasurements(
        centerlineMm: centerlineMm != null ? centerlineMm() : this.centerlineMm,
        rotationMm: rotationMm != null ? rotationMm() : this.rotationMm,
        gapsMm: gapsMm ?? this.gapsMm,
        force: force != null ? force() : this.force,
      );

  /// Zmiana liczby punktów z zachowaniem odczytów, które leżą pod tym samym
  /// kątem: punkty 4-punktowe (0°, 90°, 180°, 270°) to parzyste punkty
  /// 8-punktowe. Przejście 8 → 4 gubi odczyty z 45°, 135°… — te kąty nie
  /// istnieją w pomiarze 4-punktowym.
  FlangeMeasurements withGapPoints(int points) {
    final n = _validPoints(points);
    if (n == gapPointCount) return this;
    final out = List<double?>.filled(n, null);
    for (var i = 0; i < n; i++) {
      final angle = 360 / n * i;
      final j = angle / (360 / gapPointCount);
      if ((j - j.round()).abs() < 1e-9 && j.round() < gapPointCount) {
        out[i] = gapsMm[j.round()];
      }
    }
    return copyWith(gapsMm: out);
  }

  FlangeMeasurements withGap(int index, double? mm) {
    final g = List<double?>.of(gapsMm);
    g[index] = mm;
    return copyWith(gapsMm: g);
  }

  Map<String, Object?> toJson() => {
        'centerlineMm': centerlineMm,
        'rotationMm': rotationMm,
        'gapsMm': gapsMm,
        'force': force?.name,
      };

  static FlangeMeasurements fromJson(Object? json) {
    if (json is! Map) return FlangeMeasurements.empty();
    final raw = json['gapsMm'];
    final gaps = <double?>[
      if (raw is List)
        for (final g in raw) _nonNegative(_num(g))
    ];
    final n = gaps.length <= 4 ? 4 : 8;
    final fixed =
        List<double?>.generate(n, (i) => i < gaps.length ? gaps[i] : null);
    return FlangeMeasurements(
      centerlineMm: _nonNegative(_num(json['centerlineMm'])),
      rotationMm: _nonNegative(_num(json['rotationMm'])),
      gapsMm: fixed,
      force: AlignmentForce.values
          .where((f) => f.name == json['force'])
          .firstOrNull,
    );
  }
}

int _validPoints(int n) => n <= 4 ? 4 : 8;

/// Kąt punktu pomiaru szczeliny w stopniach (0° = góra).
double gapPointAngle(int index, int count) => 360 / count * index;

// ═══════════════════════════════════════════════════════════════════════════
// LISTA KONTROLNA
// ═══════════════════════════════════════════════════════════════════════════

/// Punkty listy kontrolnej montażu. Nazwy enumów są kluczami JSON — nie
/// zmieniać.
enum FlangeChecklistItem {
  /// Powierzchnie uszczelniające czyste, bez uszkodzeń ponad PCC-1 zał. D.
  faces,

  /// Właściwa uszczelka: typ, rozmiar, klasa; nowa.
  gasket,

  /// Śruby i nakrętki: gatunek, średnica, długość; wystają z nakrętki.
  bolting,

  /// Smar na gwintach i powierzchniach nośnych nakrętek.
  lubrication,

  /// Kolejność dokręcania (wzór) i rundy.
  sequence,
}

// ═══════════════════════════════════════════════════════════════════════════
// OCENA
// ═══════════════════════════════════════════════════════════════════════════

enum FlangeCriterion { centerline, parallelism, rotation, spacing, force }

enum CheckVerdict { ok, fail, missing }

enum ProtocolVerdict {
  /// Wszystko zmierzone w granicach i odhaczone — zielony.
  accepted,

  /// Co najmniej jedno kryterium poza tolerancją.
  rejected,

  /// Brak pomiaru, nieodhaczony punkt albo błędne dane.
  incomplete,
}

/// Błędy danych, które blokują zielony werdykt.
enum FlangeDataProblem { boltCount, gasketThickness, tolerances }

class CriterionResult {
  final FlangeCriterion criterion;
  final CheckVerdict verdict;

  /// Wartość oceniana, mm: przesunięcie, max − min, największa szczelina.
  final double? valueMm;

  /// Granica, mm (dla [FlangeCriterion.force] — brak).
  final double? limitMm;

  const CriterionResult(this.criterion, this.verdict,
      {this.valueMm, this.limitMm});
}

CheckVerdict _against(double? value, double? limit) {
  if (value == null || limit == null) return CheckVerdict.missing;
  return value <= limit + _kEpsMm ? CheckVerdict.ok : CheckVerdict.fail;
}

class FlangeEvaluation {
  final List<CriterionResult> criteria;
  final Set<FlangeChecklistItem> checked;
  final List<FlangeDataProblem> problems;

  const FlangeEvaluation({
    required this.criteria,
    required this.checked,
    required this.problems,
  });

  CriterionResult of(FlangeCriterion c) =>
      criteria.firstWhere((r) => r.criterion == c);

  int count(CheckVerdict v) => criteria.where((c) => c.verdict == v).length;

  int get checkedCount => checked.length;
  int get checklistTotal => FlangeChecklistItem.values.length;
  bool get allChecked => checkedCount == checklistTotal;

  ProtocolVerdict get verdict {
    if (criteria.any((c) => c.verdict == CheckVerdict.fail)) {
      return ProtocolVerdict.rejected;
    }
    if (problems.isNotEmpty ||
        criteria.any((c) => c.verdict != CheckVerdict.ok) ||
        !allChecked) {
      return ProtocolVerdict.incomplete;
    }
    return ProtocolVerdict.accepted;
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// PROTOKÓŁ
// ═══════════════════════════════════════════════════════════════════════════

class FlangeCheck {
  final String id;
  final FlangeJoint joint;
  final FlangeMeasurements measurements;
  final Set<FlangeChecklistItem> checked;

  /// Jednostka, w której mierzono — decyduje, którą wersję granicy PCC-1
  /// (mm czy cale) bierzemy do oceny.
  final LengthUnit unit;
  final FlangeTolerances tolerances;
  final String notes;
  final int createdAt;
  final int updatedAt;

  const FlangeCheck({
    required this.id,
    this.joint = const FlangeJoint(),
    this.measurements = const FlangeMeasurements(),
    this.checked = const {},
    this.unit = LengthUnit.mm,
    this.tolerances = FlangeTolerances.pcc1,
    this.notes = '',
    this.createdAt = 0,
    this.updatedAt = 0,
  });

  FlangeCheck copyWith({
    String? id,
    FlangeJoint? joint,
    FlangeMeasurements? measurements,
    Set<FlangeChecklistItem>? checked,
    LengthUnit? unit,
    FlangeTolerances? tolerances,
    String? notes,
    int? createdAt,
    int? updatedAt,
  }) =>
      FlangeCheck(
        id: id ?? this.id,
        joint: joint ?? this.joint,
        measurements: measurements ?? this.measurements,
        checked: checked ?? this.checked,
        unit: unit ?? this.unit,
        tolerances: tolerances ?? this.tolerances,
        notes: notes ?? this.notes,
        createdAt: createdAt ?? this.createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
      );

  List<FlangeDataProblem> get problems {
    final bolts = joint.boltCount;
    final t = joint.gasketThicknessMm;
    return [
      if (bolts != null && !isValidBoltCount(bolts))
        FlangeDataProblem.boltCount,
      if (t != null && !(t > 0 && t.isFinite))
        FlangeDataProblem.gasketThickness,
      if (!tolerances.isValid) FlangeDataProblem.tolerances,
    ];
  }

  FlangeEvaluation evaluate() {
    final m = measurements;
    final tol = tolerances;
    final gaps = m.enteredGaps;
    final spread =
        gaps.length >= 2 ? gaps.reduce(math.max) - gaps.reduce(math.min) : null;
    final maxGap = gaps.isEmpty ? null : gaps.reduce(math.max);

    // Szczelina: komplet punktów daje wynik; niepełny pomiar może dać tylko
    // „poza tolerancją” (max − min i max mogą już tylko rosnąć), nigdy „OK”.
    CriterionResult partial(FlangeCriterion c, double? value, double? limit) {
      final v = _against(value, limit);
      if (m.allGapsEntered || v == CheckVerdict.fail) {
        return CriterionResult(c, v, valueMm: value, limitMm: limit);
      }
      return CriterionResult(c, CheckVerdict.missing,
          valueMm: value, limitMm: limit);
    }

    final t = joint.gasketThicknessMm;
    final spacingLimit = t != null && t > 0 && t.isFinite && tol.gapFactor > 0
        ? tol.gapFactor * t
        : null;

    return FlangeEvaluation(
      criteria: [
        CriterionResult(
          FlangeCriterion.centerline,
          _against(m.centerlineMm, _limit(tol.centerline, unit)),
          valueMm: m.centerlineMm,
          limitMm: _limit(tol.centerline, unit),
        ),
        partial(
            FlangeCriterion.parallelism, spread, _limit(tol.parallelism, unit)),
        CriterionResult(
          FlangeCriterion.rotation,
          _against(m.rotationMm, _limit(tol.rotation, unit)),
          valueMm: m.rotationMm,
          limitMm: _limit(tol.rotation, unit),
        ),
        partial(FlangeCriterion.spacing, maxGap, spacingLimit),
        CriterionResult(
          FlangeCriterion.force,
          switch (m.force) {
            null => CheckVerdict.missing,
            AlignmentForce.light => CheckVerdict.ok,
            AlignmentForce.heavy => CheckVerdict.fail,
          },
        ),
      ],
      checked: checked,
      problems: problems,
    );
  }

  /// Nowy protokół „jak poprzedni”: te same dane połączenia, jednostka
  /// i tolerancje; numer w oznaczeniu +1; BEZ pomiarów, odhaczeń i uwag.
  FlangeCheck duplicate({
    required String id,
    required String date,
    required int now,
  }) =>
      FlangeCheck(
        id: id,
        joint: joint.copyWith(tag: nextTag(joint.tag), date: date),
        measurements:
            FlangeMeasurements.empty(points: measurements.gapPointCount),
        checked: const {},
        unit: unit,
        tolerances: tolerances,
        notes: '',
        createdAt: now,
        updatedAt: now,
      );

  Map<String, Object?> toJson() => {
        'id': id,
        'joint': joint.toJson(),
        'measurements': measurements.toJson(),
        'checked': [
          for (final i in FlangeChecklistItem.values)
            if (checked.contains(i)) i.name
        ],
        'unit': unit.name,
        'tolerances': tolerances.toJson(),
        'notes': notes,
        'createdAt': createdAt,
        'updatedAt': updatedAt,
      };

  /// `null`, gdy wpis nie ma identyfikatora (nie da się go edytować ani
  /// usunąć). Pozostałe zepsute pola → wartości domyślne.
  static FlangeCheck? fromJson(Object? json) {
    if (json is! Map) return null;
    final id = json['id'];
    if (id is! String || id.isEmpty) return null;
    final rawChecked = json['checked'];
    return FlangeCheck(
      id: id,
      joint: FlangeJoint.fromJson(json['joint']),
      measurements: FlangeMeasurements.fromJson(json['measurements']),
      checked: {
        if (rawChecked is List)
          for (final c in rawChecked)
            ...FlangeChecklistItem.values.where((i) => i.name == c),
      },
      unit: json['unit'] == LengthUnit.inch.name
          ? LengthUnit.inch
          : LengthUnit.mm,
      tolerances: FlangeTolerances.fromJson(json['tolerances']),
      notes: _str(json['notes']),
      createdAt: _num(json['createdAt'])?.round() ?? 0,
      updatedAt: _num(json['updatedAt'])?.round() ?? 0,
    );
  }
}

double? _limit(DualLimit l, LengthUnit u) => l.isValid ? l.limitMm(u) : null;

/// Lista protokołów → JSON (do SharedPreferences).
String encodeFlangeChecks(List<FlangeCheck> checks) => jsonEncode({
      'v': 1,
      'checks': [for (final c in checks) c.toJson()]
    });

/// JSON → lista protokołów. Nigdy nie rzuca: pusty, uszkodzony albo obcy
/// JSON daje pustą listę; pojedynczy zepsuty wpis jest pomijany.
List<FlangeCheck> decodeFlangeChecks(String? raw) {
  if (raw == null || raw.trim().isEmpty) return [];
  try {
    final json = jsonDecode(raw);
    final list = json is Map ? json['checks'] : json;
    if (list is! List) return [];
    final out = <FlangeCheck>[];
    final ids = <String>{};
    for (final e in list) {
      final c = FlangeCheck.fromJson(e);
      if (c != null && ids.add(c.id)) out.add(c);
    }
    return out;
  } catch (_) {
    return [];
  }
}

/// Następne oznaczenie: ostatnia liczba +1 z zachowaniem zer wiodących.
/// „L-101-F1” → „L-101-F2”, „K09” → „K10”, bez cyfr — bez zmian.
String nextTag(String tag) {
  final m = RegExp(r'(\d+)(?!.*\d)').firstMatch(tag);
  if (m == null) return tag;
  final digits = m.group(1)!;
  final next = (BigInt.parse(digits) + BigInt.one).toString();
  final padded = next.padLeft(digits.length, '0');
  return tag.replaceRange(m.start, m.end, padded);
}

// ═══════════════════════════════════════════════════════════════════════════
// FORMATOWANIE (przecinek w PL, kropka w EN)
// ═══════════════════════════════════════════════════════════════════════════

String fmtNum(double v, {int decimals = 2, required bool en}) {
  final s = formatQty(v, decimals: decimals);
  return en ? s.replaceAll(',', '.') : s;
}

/// Cale: ułamek do 1/64 („1/16"”, „1 1/8"”), inaczej dziesiętnie („0,039"”).
String formatInch(double inch, {required bool en}) {
  for (final den in const [1, 2, 4, 8, 16, 32, 64]) {
    final n = inch * den;
    if ((n - n.round()).abs() < 1e-6) {
      final num = n.round();
      final whole = num ~/ den;
      final rest = num % den;
      if (rest == 0) return '$whole"';
      return whole == 0 ? '$rest/$den"' : '$whole $rest/$den"';
    }
  }
  return '${fmtNum(inch, decimals: 3, en: en)}"';
}

/// Pomiar w jednostce protokołu: „1,25 mm” albo „0,0625"”.
String formatLength(double mm, LengthUnit unit, {required bool en}) =>
    unit == LengthUnit.mm
        ? '${fmtNum(mm, decimals: 2, en: en)} mm'
        : '${fmtNum(mm / kMmPerInch, decimals: 4, en: en)}"';

/// Granica w obu układach, pierwsza w jednostce protokołu:
/// „1,5 mm (1/16")” albo „1/16" (1,5 mm)”.
String formatLimit(DualLimit l, LengthUnit primary, {required bool en}) {
  final mm = '${fmtNum(l.mm, decimals: 2, en: en)} mm';
  final inch = formatInch(l.inch, en: en);
  return primary == LengthUnit.mm ? '$mm ($inch)' : '$inch ($mm)';
}

/// Wartość do pola tekstowego w jednostce [u] (bez jednostki).
String fieldText(double? mm, LengthUnit u, {required bool en}) {
  if (mm == null) return '';
  return u == LengthUnit.mm
      ? fmtNum(mm, decimals: 2, en: en)
      : fmtNum(mm / kMmPerInch, decimals: 4, en: en);
}

// ── JSON helpers ─────────────────────────────────────────────────────────────

double? _num(Object? v) =>
    v is num && v.toDouble().isFinite ? v.toDouble() : null;

double? _nonNegative(double? v) => v != null && v >= 0 ? v : null;

String _str(Object? v) => v is String ? v : '';
