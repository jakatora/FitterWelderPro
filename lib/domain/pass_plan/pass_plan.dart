// Plan ściegów i elektrod — ile ściegów wyjdzie na złącze, ile elektrod
// wziąć z suszarki i ile to potrwa. Moduł WARSZTATOWY (wycena jest
// osobno, w domain/quotes). Czysty Dart, bez Fluttera.
//
// 1. Przekrój złącza: geometria wyceny (weld_geometry.dart) — objętości
//    z [volumesOf], pola warstw z plateButtVolumes / plateFilletVolumes
//    przy długości 1 mm (ten sam przekrój, co rura). Bez własnych wzorów
//    na przekrój.
// 2. Warstwy:
//    • grań — do wysokości [kRootPassHeightMm] (pachwina: pierwszy ścieg
//      a = [kFilletRootThroatMm]), jak w wycenie; 1 ścieg (rowek X — 2,
//      po jednym z każdej strony);
//    • ścieg gorący — 1 ścieg o przekroju ściegu swojej średnicy, tylko
//      rowek jednostronny (rura, blacha V / I);
//    • lico — górne [kCapLayerDepthMm] rowka (X: z obu stron) + nadlew;
//    • wypełnienie — reszta; resztka poniżej [kFillMergeFraction] ściegu
//      dochodzi do lica.
//    Liczba ściegów = pole warstwy / przekrój ściegu, W GÓRĘ.
// 3. Objętość warstwy: grań — rootMm3 z geometrii; reszta (fillMm3)
//    dzielona proporcjonalnie do pól warstw (na rurze lico leży na
//    większej średnicy niż grań — dlatego nie pole × π·OD).
// 4. Spoiwo: elektroda — masa stopiwa / masa stopiwa z elektrody wg karty
//    (poprawka na ogarek); pręt TIG i drut MAG — masa / uzysk profilu
//    procesu wyceny.
// 5. Czas łuku: elektroda — czas stapiania z karty (s na gram stopiwa);
//    TIG, MAG — wydajność stapiania profilu. Czas pracy = łuk /
//    współczynnik jarzenia łuku.
// 6. Ekspozycja: okno = limit − zapas ostrzeżenia z modułu ekspozycji;
//    najwięcej naraz = okno × tempo zużycia, W DÓŁ.
//
// Zaokrąglenia: ilości i czasy W GÓRĘ, liczone z dokładnych wartości (nie
// z zaokrągleń warstw — niedokończona elektroda idzie na następną warstwę
// albo następne złącze); „ile naraz z suszarki” W DÓŁ.
// Brak / nieczytelne dane → lista problemów i brak wyniku (nie zero).
library;

import 'dart:math' as math;

import '../quotes/quote_calculator.dart' show volumesOf;
import '../quotes/quote_process.dart';
import '../quotes/weld_geometry.dart';
import '../quotes/weld_quote.dart';
import '../welding/electrode_exposure.dart';
import 'pass_plan_sources.dart';

// ═══════════════════════════════════════════════════════════════════════════
// ZAOKRĄGLENIA
// ═══════════════════════════════════════════════════════════════════════════

const double _tol = 1e-9;
const double _areaEps = 1e-6;

/// W górę, odporne na szum zmiennoprzecinkowy (24,000000001 → 24).
int ceilTol(double v) => v <= _tol ? 0 : (v - _tol).ceil();

/// W dół, odporne na szum (13,999999999 → 14).
int floorTol(double v) => v <= 0 ? 0 : (v + _tol).floor();

/// W górę do 0,01.
double ceilHundredth(double v) => ceilTol(v * 100) / 100;

/// Gęstość stopiwa stali węglowej, g/mm³ (wartość z wyceny).
final double kSteelGPerMm3 = QuoteMaterial.carbon.densityGcm3 * 1e-3;

// ═══════════════════════════════════════════════════════════════════════════
// MODEL
// ═══════════════════════════════════════════════════════════════════════════

/// Złącza obsługiwane przez plan (króciec — tylko w wycenie).
const List<JointKind> kPassPlanJointKinds = [
  JointKind.pipeButt,
  JointKind.plateButt,
  JointKind.pipeFillet,
  JointKind.plateFillet,
];

/// Spoiwo warstwy.
enum PassConsumable {
  tig(QuoteProcess.tig, null),
  mma25(QuoteProcess.mma, 2.5),
  mma32(QuoteProcess.mma, 3.2),
  mma40(QuoteProcess.mma, 4.0),
  mag(QuoteProcess.mag, null);

  const PassConsumable(this.process, this.electrodeMm);

  final QuoteProcess process;

  /// Średnica elektrody otulonej; `null` — pręt TIG / drut MAG.
  final double? electrodeMm;

  bool get isElectrode => electrodeMm != null;

  /// Przyjęty przekrój ściegu, mm².
  double get defaultBeadAreaMm2 => kDefaultBeadAreaMm2[name]!;

  static PassConsumable? byName(String? n) {
    for (final c in values) {
      if (c.name == n) return c;
    }
    return null;
  }
}

/// Wybór spoiwa dla warstw (kolejność chipów).
const List<PassConsumable> kRootChoices = [
  PassConsumable.tig,
  PassConsumable.mma25,
  PassConsumable.mma32,
  PassConsumable.mag,
];
const List<PassConsumable> kHotChoices = [
  PassConsumable.mma25,
  PassConsumable.mma32,
  PassConsumable.tig,
];
const List<PassConsumable> kFillChoices = [
  PassConsumable.mma25,
  PassConsumable.mma32,
  PassConsumable.mma40,
  PassConsumable.tig,
  PassConsumable.mag,
];
const List<PassConsumable> kCapChoices = kFillChoices;

/// Procesy, których współczynnik jarzenia łuku da się zmienić.
const List<QuoteProcess> kPassPlanProcesses = [
  QuoteProcess.tig,
  QuoteProcess.mma,
  QuoteProcess.mag,
];

/// Domyślny współczynnik jarzenia łuku z profilu wyceny, %.
double defaultArcOnPct(QuoteProcess p) =>
    kDefaultProcessProfiles[p]!.dutyCycle * 100;

enum PassLayer { root, hot, fill, cap }

/// Kolejność pracy — decyduje o tempie zużycia elektrod.
enum WorkOrder {
  /// Złącze po złączu: grań, ścieg gorący, wypełnienie, lico — elektrody
  /// leżą na powietrzu także w czasie spawania grani TIG.
  jointByJoint,

  /// Najpierw granie na wszystkich złączach, elektrody wyjmowane dopiero do
  /// reszty warstw (tylko przy grani TIG / MAG).
  rootsFirst,
}

/// Wiersz karty dla elektrody [c]: 350 mm albo 450 mm ([long]); średnica
/// bez wersji 450 mm w karcie (Ø2,5) — 350 mm.
ElectrodeCardRow electrodeRowFor(PassConsumable c, {required bool long}) {
  final d = c.electrodeMm!;
  final want = long ? 450 : 350;
  return kOk4800Card.firstWhere(
    (r) => r.diameterMm == d && r.lengthMm == want,
    orElse: () => kOk4800Card.firstWhere((r) => r.diameterMm == d),
  );
}

/// Masa stopiwa z jednej elektrody przy ogarku [stubMm], g: karta
/// przeliczona proporcjonalnie do zużytej długości.
double depositPerElectrodeG(ElectrodeCardRow r, double stubMm) =>
    r.depositG * (r.lengthMm - stubMm) / (r.lengthMm - kCardStubMm);

/// Masa pręta TIG Ø[diameterMm] × [kTigRodLengthMm], g.
double tigRodMassG(double diameterMm) =>
    kSteelGPerMm3 * math.pi / 4 * diameterMm * diameterMm * kTigRodLengthMm;

/// Dane wejściowe. Liczby z pól: puste albo nieczytelne → NaN (zgłosi to
/// [passPlanProblems]). Wartości domyślne = przykład z warsztatu: 8 złączy
/// 168,3 × 7,11, rowek V 60°, grań TIG, ścieg gorący Ø2,5, reszta Ø3,2.
class PassPlanInput {
  final JointKind kind;
  final double odMm;
  final double wallMm;
  final double throatMm;
  final double lengthM;
  final double count;
  final GrooveType groove;
  final double angleDeg;
  final double rootFaceMm;
  final double gapMm;

  final PassConsumable root;

  /// `null` — bez ściegu gorącego.
  final PassConsumable? hot;
  final PassConsumable fill;
  final PassConsumable cap;

  /// Elektrody Ø3,2 / Ø4,0 w długości 450 mm (Ø2,5 zawsze 350 mm).
  final bool longElectrodes;
  final double tigRodMm;
  final double stubMm;
  final double reservePct;

  /// Przekroje ściegów nadpisane w polu, mm² (brak klucza — przyjęty).
  final Map<PassConsumable, double> beadAreasMm2;

  /// Współczynniki jarzenia łuku nadpisane w polu, % (brak — profil).
  final Map<QuoteProcess, double> arcOnPct;

  /// `null` — elektroda nie zasadowa (rutylowa, celulozowa): bez limitu.
  final ElectrodeClass? electrodeClass;
  final ElectrodeSource source;

  /// Limit z WPS / karty, min; `null` — z tabeli modułu ekspozycji.
  final double? limitMinutes;
  final WorkOrder order;
  final double shiftH;

  const PassPlanInput({
    this.kind = JointKind.pipeButt,
    this.odMm = 168.3,
    this.wallMm = 7.11,
    this.throatMm = 6,
    this.lengthM = 1,
    this.count = 8,
    this.groove = GrooveType.v,
    this.angleDeg = 60,
    this.rootFaceMm = 1.5,
    this.gapMm = 2.5,
    this.root = PassConsumable.tig,
    this.hot = PassConsumable.mma25,
    this.fill = PassConsumable.mma32,
    this.cap = PassConsumable.mma32,
    this.longElectrodes = false,
    this.tigRodMm = kDefaultTigRodMm,
    this.stubMm = kDefaultStubMm,
    this.reservePct = kDefaultReservePct,
    this.beadAreasMm2 = const {},
    this.arcOnPct = const {},
    this.electrodeClass = ElectrodeClass.enIso2560B,
    this.source = ElectrodeSource.oven,
    this.limitMinutes,
    this.order = WorkOrder.jointByJoint,
    this.shiftH = kDefaultShiftH,
  });

  PassPlanInput copyWith({
    JointKind? kind,
    double? odMm,
    double? wallMm,
    double? throatMm,
    double? lengthM,
    double? count,
    GrooveType? groove,
    double? angleDeg,
    double? rootFaceMm,
    double? gapMm,
    PassConsumable? root,
    PassConsumable? Function()? hot,
    PassConsumable? fill,
    PassConsumable? cap,
    bool? longElectrodes,
    double? tigRodMm,
    double? stubMm,
    double? reservePct,
    Map<PassConsumable, double>? beadAreasMm2,
    Map<QuoteProcess, double>? arcOnPct,
    ElectrodeClass? Function()? electrodeClass,
    ElectrodeSource? source,
    double? Function()? limitMinutes,
    WorkOrder? order,
    double? shiftH,
  }) =>
      PassPlanInput(
        kind: kind ?? this.kind,
        odMm: odMm ?? this.odMm,
        wallMm: wallMm ?? this.wallMm,
        throatMm: throatMm ?? this.throatMm,
        lengthM: lengthM ?? this.lengthM,
        count: count ?? this.count,
        groove: groove ?? this.groove,
        angleDeg: angleDeg ?? this.angleDeg,
        rootFaceMm: rootFaceMm ?? this.rootFaceMm,
        gapMm: gapMm ?? this.gapMm,
        root: root ?? this.root,
        hot: hot != null ? hot() : this.hot,
        fill: fill ?? this.fill,
        cap: cap ?? this.cap,
        longElectrodes: longElectrodes ?? this.longElectrodes,
        tigRodMm: tigRodMm ?? this.tigRodMm,
        stubMm: stubMm ?? this.stubMm,
        reservePct: reservePct ?? this.reservePct,
        beadAreasMm2: beadAreasMm2 ?? this.beadAreasMm2,
        arcOnPct: arcOnPct ?? this.arcOnPct,
        electrodeClass:
            electrodeClass != null ? electrodeClass() : this.electrodeClass,
        source: source ?? this.source,
        limitMinutes: limitMinutes != null ? limitMinutes() : this.limitMinutes,
        order: order ?? this.order,
        shiftH: shiftH ?? this.shiftH,
      );

  bool get isButt => !kind.isFillet;

  /// Ścieg gorący ma sens tylko w rowku spawanym z jednej strony.
  bool get hotApplicable => isButt && groove != GrooveType.x;

  /// Ścieg gorący, który naprawdę wchodzi do planu.
  PassConsumable? get effectiveHot => hotApplicable ? hot : null;

  /// „Najpierw granie” ma sens, gdy grań nie jest elektrodą.
  bool get rootsFirstAvailable => !root.isElectrode;

  WorkOrder get effectiveOrder =>
      rootsFirstAvailable ? order : WorkOrder.jointByJoint;

  /// Spoiwa warstw liczonych z przekroju ściegu (grań liczy się z wysokości,
  /// więc jej przekrój ściegu nie wchodzi do rachunku).
  List<PassConsumable> get beadConsumables => <PassConsumable>{
        for (final c in [effectiveHot, fill, cap])
          if (c != null) c,
      }.toList();

  /// Spoiwa wszystkich warstw w kolejności, bez powtórzeń.
  List<PassConsumable> get layerConsumables => <PassConsumable>{
        for (final c in [root, effectiveHot, fill, cap])
          if (c != null) c,
      }.toList();

  List<QuoteProcess> get usedProcesses =>
      layerConsumables.map((c) => c.process).toSet().toList();

  bool get usesElectrodes => layerConsumables.any((c) => c.isElectrode);
  bool get usesTig => layerConsumables.contains(PassConsumable.tig);

  double beadArea(PassConsumable c) => beadAreasMm2[c] ?? c.defaultBeadAreaMm2;

  /// Współczynnik jarzenia łuku, %.
  double arcOnPctOf(QuoteProcess p) => arcOnPct[p] ?? defaultArcOnPct(p);

  double arcOnFraction(QuoteProcess p) => arcOnPctOf(p) / 100;
}

/// Złącze wyceny z danych planu — ta sama walidacja i ta sama geometria.
/// Pola nieużywane przez rodzaj złącza = 0; rowek I bez progu i kąta.
QuoteJoint quoteJointOf(PassPlanInput i) {
  double orZero(double v) => v.isFinite ? v : 0;
  final square = i.groove == GrooveType.square;
  final c = i.count;
  return QuoteJoint(
    id: 'pass-plan',
    kind: i.kind,
    odMm: i.kind.onPipe ? i.odMm : 0,
    wallMm: i.kind.isFillet ? 0 : i.wallMm,
    throatMm: i.kind.isFillet ? i.throatMm : 0,
    lengthM: i.kind.hasLength ? i.lengthM : 0,
    count: _countOk(c) ? c.toInt() : 1,
    groove: i.groove,
    angleDeg: square ? 0 : orZero(i.angleDeg),
    rootFaceMm: square ? 0 : orZero(i.rootFaceMm),
    gapMm: orZero(i.gapMm),
  );
}

bool _countOk(double c) =>
    c.isFinite && c >= 1 && c <= kMaxJointCount && c == c.roundToDouble();

// ═══════════════════════════════════════════════════════════════════════════
// PROBLEMY
// ═══════════════════════════════════════════════════════════════════════════

enum PassPlanProblemKind {
  /// Problem złącza z walidacji wyceny ([PassPlanProblem.joint]).
  joint,
  count,
  kind,
  grooveXOnPipe,
  gapMissing,
  rootFaceMissing,
  angleMissing,
  stub,
  reserve,
  tigRod,
  beadArea,
  arcOn,
  shift,
  limit,
}

class PassPlanProblem {
  final PassPlanProblemKind kind;
  final JointProblem? joint;
  final PassConsumable? consumable;
  final QuoteProcess? process;

  const PassPlanProblem(this.kind, {this.joint, this.consumable, this.process});

  @override
  bool operator ==(Object other) =>
      other is PassPlanProblem &&
      other.kind == kind &&
      other.joint == joint &&
      other.consumable == consumable &&
      other.process == process;

  @override
  int get hashCode => Object.hash(kind, joint, consumable, process);

  @override
  String toString() =>
      'PassPlanProblem(${kind.name}${joint == null ? '' : ', ${joint!.name}'}'
      '${consumable == null ? '' : ', ${consumable!.name}'}'
      '${process == null ? '' : ', ${process!.code}'})';
}

bool _in(double v, double min, double max) =>
    v.isFinite && v >= min && v <= max;

/// Pusta lista — plan da się policzyć.
List<PassPlanProblem> passPlanProblems(PassPlanInput i) {
  final out = <PassPlanProblem>[];
  if (!_countOk(i.count)) {
    out.add(const PassPlanProblem(PassPlanProblemKind.count));
  }
  if (!kPassPlanJointKinds.contains(i.kind)) {
    out.add(const PassPlanProblem(PassPlanProblemKind.kind));
    return out;
  }
  if (i.isButt) {
    if (i.kind.onPipe && i.groove == GrooveType.x) {
      out.add(const PassPlanProblem(PassPlanProblemKind.grooveXOnPipe));
    }
    if (!i.gapMm.isFinite) {
      out.add(const PassPlanProblem(PassPlanProblemKind.gapMissing));
    }
    if (i.groove != GrooveType.square) {
      if (!i.rootFaceMm.isFinite) {
        out.add(const PassPlanProblem(PassPlanProblemKind.rootFaceMissing));
      }
      if (!i.angleDeg.isFinite) {
        out.add(const PassPlanProblem(PassPlanProblemKind.angleMissing));
      }
    }
  }
  for (final p in quoteJointOf(i).problems) {
    if (p == JointProblem.count) continue;
    out.add(PassPlanProblem(PassPlanProblemKind.joint, joint: p));
  }
  if (!_in(i.stubMm, kMinStubMm, kMaxStubMm) && i.usesElectrodes) {
    out.add(const PassPlanProblem(PassPlanProblemKind.stub));
  }
  if (!_in(i.reservePct, 0, kMaxReservePct)) {
    out.add(const PassPlanProblem(PassPlanProblemKind.reserve));
  }
  if (i.usesTig && !kTigRodDiametersMm.contains(i.tigRodMm)) {
    out.add(const PassPlanProblem(PassPlanProblemKind.tigRod));
  }
  for (final c in i.beadConsumables) {
    final a = i.beadArea(c);
    if (!(a.isFinite && a > 0 && a <= kMaxBeadAreaMm2)) {
      out.add(PassPlanProblem(PassPlanProblemKind.beadArea, consumable: c));
    }
  }
  for (final p in i.usedProcesses) {
    if (!_in(i.arcOnPctOf(p), kMinArcOnPct, kMaxArcOnPct)) {
      out.add(PassPlanProblem(PassPlanProblemKind.arcOn, process: p));
    }
  }
  if (i.usesElectrodes) {
    if (!(i.shiftH.isFinite && i.shiftH > 0 && i.shiftH <= kMaxShiftH)) {
      out.add(const PassPlanProblem(PassPlanProblemKind.shift));
    }
    final l = i.limitMinutes;
    if (i.electrodeClass != null &&
        l != null &&
        !_in(l, 1, kMaxLimitMinutes.toDouble())) {
      out.add(const PassPlanProblem(PassPlanProblemKind.limit));
    }
  }
  return out;
}

/// Najdłuższy limit czasu na powietrzu przyjmowany z pola (jak w module
/// ekspozycji: 7 dni).
const int kMaxLimitMinutes = 7 * 24 * 60;

// ═══════════════════════════════════════════════════════════════════════════
// WYNIK
// ═══════════════════════════════════════════════════════════════════════════

/// Jedna warstwa na JEDNO złącze.
class PassLayerPlan {
  final PassLayer layer;
  final PassConsumable consumable;

  /// Wiersz karty (elektroda) albo `null`.
  final ElectrodeCardRow? electrode;
  final int passes;

  /// Pole przekroju warstwy, mm².
  final double areaMm2;
  final double volumeMm3;
  final double depositG;

  /// Zużyte spoiwo TIG / MAG, g (elektroda — 0, liczy się w sztukach).
  final double fillerG;

  /// Elektrody albo pręty TIG (ułamek); drut MAG — 0.
  final double units;
  final double arcMin;
  final double workMin;

  const PassLayerPlan({
    required this.layer,
    required this.consumable,
    required this.electrode,
    required this.passes,
    required this.areaMm2,
    required this.volumeMm3,
    required this.depositG,
    required this.fillerG,
    required this.units,
    required this.arcMin,
    required this.workMin,
  });

  /// Elektrody / pręty na tę warstwę jednego złącza, W GÓRĘ.
  int get unitsCeil => ceilTol(units);
}

/// Spoiwo na całość — jedna pozycja listy „weź”.
class PassSupply {
  final PassConsumable consumable;
  final ElectrodeCardRow? electrode;

  /// Pręt TIG, mm (tylko TIG).
  final double? tigRodMm;
  final double unitsPerJoint;
  final double depositGPerJoint;
  final double fillerGPerJoint;
  final int jointCount;
  final double reservePct;

  const PassSupply({
    required this.consumable,
    required this.electrode,
    required this.tigRodMm,
    required this.unitsPerJoint,
    required this.depositGPerJoint,
    required this.fillerGPerJoint,
    required this.jointCount,
    required this.reservePct,
  });

  bool get isElectrode => electrode != null;

  /// Liczone w sztukach (elektrody, pręty), nie w kg (drut).
  bool get countsUnits => consumable != PassConsumable.mag;

  double get _reserveFactor => 1 + reservePct / 100;

  int get unitsPerJointCeil => ceilTol(unitsPerJoint);
  int get unitsJob => ceilTol(unitsPerJoint * jointCount);
  int get unitsJobWithReserve =>
      ceilTol(unitsPerJoint * jointCount * _reserveFactor);

  double get fillerKgPerJoint => ceilHundredth(fillerGPerJoint / 1000);
  double get fillerKgJob => ceilHundredth(fillerGPerJoint * jointCount / 1000);
  double get fillerKgJobWithReserve =>
      ceilHundredth(fillerGPerJoint * jointCount * _reserveFactor / 1000);
}

/// „Weź z suszarki” dla jednej średnicy elektrody.
class ExposureTake {
  final ElectrodeCardRow electrode;

  /// Tempo zużycia, elektrod na godzinę pracy.
  final double ratePerH;

  /// Najwięcej naraz (W DÓŁ); `null` — bez limitu.
  final int? maxAtOnce;

  /// Weź teraz: najwięcej naraz, ale nie więcej niż całość z zapasem.
  final int takeNow;

  /// Potrzebne w czasie zmiany (albo całej roboty, jeśli krótsza), W GÓRĘ.
  final int neededInShift;

  const ExposureTake({
    required this.electrode,
    required this.ratePerH,
    required this.maxAtOnce,
    required this.takeNow,
    required this.neededInShift,
  });
}

class ExposurePlan {
  /// `null` — elektroda nie zasadowa, bez limitu.
  final ElectrodeClass? electrodeClass;
  final ElectrodeSource source;

  /// Limit czasu na powietrzu, min; `null` — bez limitu.
  final int? limitMinutes;

  /// Limit z tabeli modułu ekspozycji (nie wpisany).
  final bool limitFromTable;

  /// Zapas przed końcem limitu (jak ostrzeżenie modułu ekspozycji), min.
  final int leadMinutes;

  /// Okno na zużycie porcji = limit − zapas, min.
  final int windowMinutes;
  final WorkOrder order;

  /// Czas pracy na złącze, z którego liczone jest tempo, min.
  final double workMinPerJoint;
  final double shiftH;

  /// Godziny pracy z elektrodami w tej zmianie (zmiana albo cała robota).
  final double hoursInShift;

  /// Cała robota mieści się w jednej zmianie.
  final bool wholeJobInShift;
  final List<ExposureTake> takes;

  /// Ile razy iść do suszarki w czasie [hoursInShift]; `null` — okno za
  /// krótkie na choćby jedną elektrodę.
  final int? portions;

  const ExposurePlan({
    required this.electrodeClass,
    required this.source,
    required this.limitMinutes,
    required this.limitFromTable,
    required this.leadMinutes,
    required this.windowMinutes,
    required this.order,
    required this.workMinPerJoint,
    required this.shiftH,
    required this.hoursInShift,
    required this.wholeJobInShift,
    required this.takes,
    required this.portions,
  });

  bool get hasLimit => limitMinutes != null;

  double get totalRatePerH => takes.fold(0.0, (s, t) => s + t.ratePerH);
  int get totalTakeNow => takes.fold(0, (s, t) => s + t.takeNow);

  /// Choć jedna średnica nie mieści nawet jednej sztuki w oknie.
  bool get someBelowOne => takes.any((t) => t.maxAtOnce == 0);
}

class PassPlanResult {
  final PassPlanInput input;
  final int jointCount;
  final List<PassLayerPlan> layers;
  final List<PassSupply> supplies;

  /// Resztka wypełnienia doszła do lica.
  final bool fillMerged;

  /// Wybrano ścieg gorący, ale po grani nie ma na niego miejsca (cienka
  /// ścianka) — pominięty.
  final bool hotNoRoom;

  /// Wybrano ścieg gorący, ale rowek X / pachwina — pominięty.
  final bool hotNotApplicable;

  /// `null` — w planie nie ma elektrod otulonych.
  final ExposurePlan? exposure;

  const PassPlanResult({
    required this.input,
    required this.jointCount,
    required this.layers,
    required this.supplies,
    required this.fillMerged,
    required this.hotNoRoom,
    required this.hotNotApplicable,
    required this.exposure,
  });

  int get passesPerJoint => layers.fold(0, (s, l) => s + l.passes);
  double get depositGPerJoint => layers.fold(0.0, (s, l) => s + l.depositG);
  double get arcMinPerJoint => layers.fold(0.0, (s, l) => s + l.arcMin);
  double get workMinPerJoint => layers.fold(0.0, (s, l) => s + l.workMin);
  double get arcMinJob => arcMinPerJoint * jointCount;
  double get workMinJob => workMinPerJoint * jointCount;
  double get depositKgJob =>
      ceilHundredth(depositGPerJoint * jointCount / 1000);

  PassLayerPlan? layer(PassLayer l) =>
      layers.where((x) => x.layer == l).firstOrNull;
}

// ═══════════════════════════════════════════════════════════════════════════
// RACHUNEK
// ═══════════════════════════════════════════════════════════════════════════

/// Pola warstw na jedno złącze (przekrój, mm²).
class PassLayerAreas {
  final double root;
  final double hot;
  final double fill;
  final double cap;
  final bool fillMerged;
  final bool hotNoRoom;

  const PassLayerAreas({
    required this.root,
    required this.hot,
    required this.fill,
    required this.cap,
    required this.fillMerged,
    required this.hotNoRoom,
  });

  double get total => root + hot + fill + cap;
}

/// Podział przekroju złącza na warstwy. Pole narastające od strony grani
/// bierzemy z geometrii wyceny przy długości 1 mm (dla rury przekrój jest
/// ten sam co dla blachy — różni się tylko długość).
PassLayerAreas passLayerAreas(PassPlanInput i) {
  final double Function(double x) cumulative;
  final double extent;
  final double total;
  final double rootX;
  final double capX;
  if (i.kind.isFillet) {
    final a = i.throatMm;
    cumulative = (x) => plateFilletVolumes(throat: x, lengthMm: 1).totalMm3;
    extent = a;
    total = cumulative(a);
    rootX = math.min(a, kFilletRootThroatMm);
    capX = a - kCapLayerDepthMm;
  } else {
    final square = i.groove == GrooveType.square;
    WeldVolumes at(double x) => plateButtVolumes(
          t: i.wallMm,
          lengthMm: 1,
          groove: i.groove,
          gap: i.gapMm,
          rootFace: square ? 0 : i.rootFaceMm,
          includedAngleDeg: square ? 0 : i.angleDeg,
          rootHeight: x,
        );
    cumulative = (x) => at(x).rootMm3;
    extent = i.wallMm;
    total = at(kRootPassHeightMm).totalMm3;
    rootX = math.min(i.wallMm, kRootPassHeightMm);
    capX = i.wallMm - (i.groove == GrooveType.x ? 2 : 1) * kCapLayerDepthMm;
  }
  final groove = cumulative(extent);
  final reinforcement = math.max(0.0, total - groove);
  final root = cumulative(rootX);
  final capFrom = math.max(rootX, capX);
  final belowCap = cumulative(capFrom);
  var cap = math.max(0.0, groove - belowCap) + reinforcement;
  final mid = math.max(0.0, belowCap - root);

  var hot = 0.0;
  var hotNoRoom = false;
  final hc = i.effectiveHot;
  if (hc != null) {
    if (mid > _areaEps) {
      hot = math.min(i.beadArea(hc), mid);
    } else {
      hotNoRoom = true;
    }
  }
  var fill = mid - hot;
  if (fill < _areaEps) fill = 0;
  var merged = false;
  if (fill > 0 && fill < kFillMergeFraction * i.beadArea(i.fill)) {
    cap += fill;
    fill = 0;
    merged = true;
  }
  if (cap < _areaEps) cap = 0;
  return PassLayerAreas(
    root: root,
    hot: hot,
    fill: fill,
    cap: cap,
    fillMerged: merged,
    hotNoRoom: hotNoRoom,
  );
}

PassLayerPlan _layerPlan(
  PassPlanInput i,
  PassLayer layer,
  PassConsumable c,
  int passes,
  double area,
  double volume,
) {
  final g = volume * kSteelGPerMm3;
  ElectrodeCardRow? row;
  double units;
  double fillerG;
  double arcMin;
  if (c.isElectrode) {
    row = electrodeRowFor(c, long: i.longElectrodes);
    units = g / depositPerElectrodeG(row, i.stubMm);
    fillerG = 0;
    arcMin = g * row.arcSecondsPerGram / 60;
  } else {
    final p = kDefaultProcessProfiles[c.process]!;
    fillerG = g / p.efficiency;
    units = c == PassConsumable.tig ? fillerG / tigRodMassG(i.tigRodMm) : 0;
    arcMin = g / 1000 / p.depositionKgH * 60;
  }
  return PassLayerPlan(
    layer: layer,
    consumable: c,
    electrode: row,
    passes: passes,
    areaMm2: area,
    volumeMm3: volume,
    depositG: g,
    fillerG: fillerG,
    units: units,
    arcMin: arcMin,
    workMin: arcMin / i.arcOnFraction(c.process),
  );
}

/// Plan; `null`, gdy są problemy (patrz [passPlanProblems]).
PassPlanResult? planPasses(PassPlanInput i) {
  if (passPlanProblems(i).isNotEmpty) return null;
  final vol = volumesOf(quoteJointOf(i));
  if (!(vol.totalMm3 > 0)) return null;
  final a = passLayerAreas(i);
  final xGroove = i.isButt && i.groove == GrooveType.x;
  final rest = a.hot + a.fill + a.cap;
  double share(double area) => rest > _areaEps ? vol.fillMm3 * area / rest : 0;

  final layers = <PassLayerPlan>[
    _layerPlan(i, PassLayer.root, i.root, xGroove ? 2 : 1, a.root, vol.rootMm3),
    if (a.hot > 0)
      _layerPlan(i, PassLayer.hot, i.effectiveHot!, 1, a.hot, share(a.hot)),
    if (a.fill > 0)
      _layerPlan(i, PassLayer.fill, i.fill,
          ceilTol(a.fill / i.beadArea(i.fill)), a.fill, share(a.fill)),
    if (a.cap > 0)
      _layerPlan(
          i,
          PassLayer.cap,
          i.cap,
          math.max(ceilTol(a.cap / i.beadArea(i.cap)), xGroove ? 2 : 1),
          a.cap,
          share(a.cap)),
  ];

  final count = i.count.toInt();
  final supplies = _supplies(i, layers, count);
  return PassPlanResult(
    input: i,
    jointCount: count,
    layers: layers,
    supplies: supplies,
    fillMerged: a.fillMerged,
    hotNoRoom: a.hotNoRoom,
    hotNotApplicable: i.hot != null && !i.hotApplicable,
    exposure: _exposure(i, layers, supplies, count),
  );
}

List<PassSupply> _supplies(
    PassPlanInput i, List<PassLayerPlan> layers, int count) {
  final order = <String>[];
  final groups = <String, List<PassLayerPlan>>{};
  for (final l in layers) {
    final key = l.electrode == null
        ? l.consumable.name
        : 'mma-${l.electrode!.diameterMm}-${l.electrode!.lengthMm}';
    if (!groups.containsKey(key)) order.add(key);
    (groups[key] ??= []).add(l);
  }
  return [
    for (final key in order)
      () {
        final ls = groups[key]!;
        final first = ls.first;
        return PassSupply(
          consumable: first.consumable,
          electrode: first.electrode,
          tigRodMm: first.consumable == PassConsumable.tig ? i.tigRodMm : null,
          unitsPerJoint: ls.fold(0.0, (s, l) => s + l.units),
          depositGPerJoint: ls.fold(0.0, (s, l) => s + l.depositG),
          fillerGPerJoint: ls.fold(0.0, (s, l) => s + l.fillerG),
          jointCount: count,
          reservePct: i.reservePct,
        );
      }(),
  ];
}

ExposurePlan? _exposure(PassPlanInput i, List<PassLayerPlan> layers,
    List<PassSupply> supplies, int count) {
  final electrodes = supplies.where((s) => s.isElectrode).toList();
  if (electrodes.isEmpty) return null;
  final order = i.effectiveOrder;
  final workPerJoint = layers
      .where(
          (l) => order == WorkOrder.jointByJoint || l.layer != PassLayer.root)
      .fold(0.0, (s, l) => s + l.workMin);
  final hoursPerJoint = workPerJoint / 60;
  final jobH = hoursPerJoint * count;
  final hoursInShift = math.min(i.shiftH, jobH);

  final cls = i.electrodeClass;
  int? limit;
  if (cls != null) {
    final typed = i.limitMinutes;
    // Limit z pola — w dół do pełnej minuty (krótszy = bezpieczniej).
    limit =
        typed != null ? floorTol(typed) : defaultLimitMinutes(cls, i.source);
  }
  final lead = limit == null ? 0 : warnLeadMinutes(limit);
  final window = limit == null ? 0 : math.max(0, limit - lead);

  final takes = <ExposureTake>[
    for (final s in electrodes)
      () {
        final rate = hoursPerJoint > 0 ? s.unitsPerJoint / hoursPerJoint : 0.0;
        final z = limit == null ? null : floorTol(window / 60 * rate);
        final all = s.unitsJobWithReserve;
        return ExposureTake(
          electrode: s.electrode!,
          ratePerH: rate,
          maxAtOnce: z,
          takeNow: z == null ? all : math.min(z, all),
          neededInShift: math.min(ceilTol(rate * hoursInShift), s.unitsJob),
        );
      }(),
  ];

  int? portions;
  if (limit == null) {
    portions = 1;
  } else {
    for (final t in takes) {
      final z = t.maxAtOnce!;
      if (z < 1) continue;
      final p = ceilTol(t.neededInShift / z);
      portions = math.max(portions ?? 0, p);
    }
  }

  return ExposurePlan(
    electrodeClass: cls,
    source: i.source,
    limitMinutes: limit,
    limitFromTable: cls != null && i.limitMinutes == null,
    leadMinutes: lead,
    windowMinutes: window,
    order: order,
    workMinPerJoint: workPerJoint,
    shiftH: i.shiftH,
    hoursInShift: hoursInShift,
    wholeJobInShift: jobH <= i.shiftH + _tol,
    takes: takes,
    portions: portions,
  );
}
