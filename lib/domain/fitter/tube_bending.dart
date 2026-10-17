/// Gięcie rurek giętarką ręczną: długość cięcia i znaczniki gięć.
///
/// Monter mierzy rurkę tak jak na rysunku: odcinki proste do PUNKTÓW
/// PRZECIĘCIA OSI (wierzchołków) sąsiednich ramion. Giętarka robi łuk
/// o stałym promieniu po osi CLR, więc rurka po gięciu jest krótsza niż suma
/// tych wymiarów. Dla gięcia o kąt θ (zmiana kierunku):
///
///   długość łuku (po osi)   łuk  = π·CLR·θ / 180
///   odsunięcie (setback)    sb   = CLR·tg(θ/2)   — od wierzchołka do
///                                                  początku/końca łuku
///   zysk (gain)             gain = 2·sb − łuk     — o tyle krótsza rurka
///
/// Rurka z n gięciami, odcinki L₁ … Lₙ₊₁ (pierwszy od początku rurki do
/// wierzchołka 1, ostatni od wierzchołka n do końca):
///
///   długość rozwinięta      Σ L − Σ gain
///   wierzchołek k na prostej rurce   Pₖ = Σᵢ≤ₖ Lᵢ − Σᵢ<ₖ gainᵢ
///   początek łuku k                   Pₖ − sbₖ   (punkt styczności)
///   koniec łuku k                     Pₖ − sbₖ + łukₖ
///   prosta między gięciami k i k+1    Lₖ₊₁ − sbₖ − sbₖ₊₁
///
/// To ta sama metoda „z zyskiem” co w instrukcji Swagelok MS-13-43 (rozdz.
/// Adjustment (Gain) Calculations: P2 = P1 + odcinek − zysk poprzedniego
/// gięcia; suma = długość rurki). Swagelok w metodzie Measure-Bend ustawia
/// pod kreską rolki dla danego kąta właśnie WIERZCHOŁEK (Pₖ); RIDGID
/// (instrukcja serii 300/400) dla 90° mierzy do osi drugiego ramienia (też
/// wierzchołek), a dla 45° do środka łuku. Kreski giętarek różnych
/// producentów (0, L, R, podziałka kątów) NIE są wspólne, więc znacznik
/// ogólny to początek łuku (styczność), a przesunięcie do kreski giętarki
/// użytkownik wpisuje z instrukcji swojej giętarki ([TubeRunInput.markerOffsetMm]).
///
/// Sprężynowanie (dogięcie o kilka stopni) zmienia tylko kąt, do którego
/// gnie się na giętarce — długość rurki w łuku wyznacza matryca, więc nie
/// wpływa na długość cięcia ani na znaczniki.
///
/// Zaokrąglanie: długość cięcia ZAWSZE w górę do 0,5 mm (albo 1/32"), żeby
/// rurka nigdy nie wyszła za krótka — nadwyżka (< 1 kroku) zostaje na
/// ostatnim odcinku; znaczniki do najbliższego kroku (błąd ≤ pół kroku).
///
/// Wszystkie długości w mm (wartość kanoniczna); cale to tylko wyświetlanie.
/// Czysty Dart.
library;

import 'dart:math' as math;

const double kMmPerInch = 25.4;

/// Najwięcej gięć na jednej rurce.
const int kMaxTubeBends = 12;

/// Najdłuższy odcinek / CLR przyjmowany jako sensowny, mm.
const double kMaxTubeSegmentMm = 100000;
const double kMaxTubeClrMm = 5000;

enum TubeUnit { mm, inch }

extension TubeUnitSteps on TubeUnit {
  /// Krok zaokrąglenia długości cięcia i znaczników, mm.
  double get stepMm => this == TubeUnit.mm ? 0.5 : kMmPerInch / 32;
}

double _rad(double deg) => deg * math.pi / 180.0;

/// Szum zmiennoprzecinkowy, który nie może podnieść długości o cały krok.
const double _eps = 1e-6;

/// Długość cięcia zaokrąglona W GÓRĘ do kroku jednostki — nigdy krótsza
/// niż obliczona (z tolerancją [_eps] na szum obliczeń).
double roundCutLengthUpMm(double mm, TubeUnit unit) {
  final s = unit.stepMm;
  return ((mm - _eps) / s).ceil() * s;
}

/// Znacznik zaokrąglony do najbliższego kroku jednostki.
double roundMarkMm(double mm, TubeUnit unit) {
  final s = unit.stepMm;
  return (mm / s).round() * s;
}

/// Cale jako ułamek z dokładnością do 1/[denominator]: `9 3/8"`,
/// `-5/16"`, `12"`.
String formatInchFraction(double inches, {int denominator = 32}) {
  if (!inches.isFinite) return '—';
  final negative = inches < 0;
  final total = (inches.abs() * denominator).round();
  final whole = total ~/ denominator;
  var num = total % denominator;
  var den = denominator;
  while (num != 0 && num.isEven && den.isEven) {
    num ~/= 2;
    den ~/= 2;
  }
  final sign = negative && total != 0 ? '-' : '';
  if (num == 0) return '$sign$whole"';
  if (whole == 0) return '$sign$num/$den"';
  return '$sign$whole $num/$den"';
}

// ── Jedno gięcie ────────────────────────────────────────────────────────────

/// Kąt gięcia, który da się policzyć: 0° < θ < 180°. Przy 180° (U)
/// wierzchołek ucieka w nieskończoność — wymiarów „do przecięcia osi” nie ma.
bool tubeBendAngleOk(double deg) => deg.isFinite && deg > 0 && deg < 180;

class BendGeometry {
  final double angleDeg;
  final double clrMm;

  /// Długość łuku po osi, mm.
  final double arcMm;

  /// Odsunięcie (setback): wierzchołek → początek / koniec łuku, mm.
  final double setbackMm;

  /// Zysk (gain): o tyle rurka jest krótsza niż suma ramion, mm.
  final double gainMm;

  const BendGeometry({
    required this.angleDeg,
    required this.clrMm,
    required this.arcMm,
    required this.setbackMm,
    required this.gainMm,
  });
}

/// Geometria gięcia o [angleDeg] na promieniu po osi [clrMm]. Wywołuj dla
/// poprawnych danych ([tubeBendAngleOk], CLR > 0).
BendGeometry bendGeometry({required double angleDeg, required double clrMm}) {
  final arc = math.pi * clrMm * angleDeg / 180.0;
  final sb = clrMm * math.tan(_rad(angleDeg) / 2);
  return BendGeometry(
    angleDeg: angleDeg,
    clrMm: clrMm,
    arcMm: arc,
    setbackMm: sb,
    gainMm: 2 * sb - arc,
  );
}

// ── Problemy i ostrzeżenia ──────────────────────────────────────────────────

enum TubeBendProblemKind {
  /// CLR puste, ≤ 0 albo absurdalnie duże.
  radius,

  /// Kąt pusty, ≤ 0° albo ≥ 180° (w odsadzce: > 90°).
  angle,

  /// Odcinek pusty, ≤ 0 albo absurdalnie długi.
  segment,

  /// Minimalna prosta ujemna albo nie liczba.
  minStraight,

  /// Przesunięcie znacznika nie jest liczbą albo |x| > 1000 mm.
  markerOffset,

  /// Dogięcie ujemne albo > 30°.
  springback,

  /// Obrót płaszczyzny nie jest liczbą.
  rotation,

  /// Brak gięć albo więcej niż [kMaxTubeBends].
  bendCount,

  /// Odsadzka: przesunięcie H puste albo ≤ 0.
  offsetHeight,

  /// Odsadzka przestrzenna: przesunięcie boczne ujemne / nie liczba.
  offsetSpread,
}

class TubeBendProblem {
  final TubeBendProblemKind kind;

  /// Numer gięcia (dla [TubeBendProblemKind.angle] / `rotation`) albo
  /// odcinka (dla `segment`), od 1. `null` — pole wspólne.
  final int? index;

  const TubeBendProblem(this.kind, [this.index]);

  @override
  bool operator ==(Object other) =>
      other is TubeBendProblem && other.kind == kind && other.index == index;

  @override
  int get hashCode => Object.hash(kind, index);

  @override
  String toString() => 'TubeBendProblem($kind, $index)';
}

enum TubeBendWarningKind {
  /// Łuki sąsiednich gięć zachodzą na siebie: odcinek krótszy niż
  /// sbₖ + sbₖ₊₁. Takiej rurki nie da się wygiąć — blokuje wynik.
  arcsOverlap,

  /// Łuk wychodzi poza koniec rurki: odcinek krańcowy krótszy niż setback.
  /// Blokuje wynik.
  arcPastEnd,

  /// Prosta między gięciami krótsza niż wymagana przez giętarkę.
  straightTooShort,

  /// Prosta na końcu rurki krótsza niż wymagana (uchwyt giętarki, złączka).
  endStraightTooShort,

  /// Znacznik (z przesunięciem giętarki) wypada poza rurką.
  markOutsideTube,
}

class TubeBendWarning {
  final TubeBendWarningKind kind;

  /// Numer odcinka (od 1) albo — dla [TubeBendWarningKind.markOutsideTube] —
  /// numer gięcia.
  final int index;

  /// Rzeczywista prosta, mm (dla `markOutsideTube`: położenie znacznika).
  final double straightMm;

  /// Wymagana prosta, mm (0 dla zachodzących łuków).
  final double requiredMm;

  const TubeBendWarning(
      this.kind, this.index, this.straightMm, this.requiredMm);

  /// Geometria niemożliwa — długości cięcia i znaczników nie podajemy.
  bool get blocking =>
      kind == TubeBendWarningKind.arcsOverlap ||
      kind == TubeBendWarningKind.arcPastEnd;
}

// ── Rurka z wieloma gięciami ────────────────────────────────────────────────

class TubeRunInput {
  /// Promień gięcia po osi rurki (CLR) — stały dla giętarki, mm.
  final double clrMm;

  /// Odcinki proste do punktów przecięcia osi, mm — o jeden więcej niż gięć.
  final List<double> segmentsMm;

  /// Kąty gięć (zmiana kierunku), °.
  final List<double> anglesDeg;

  /// Obrót rurki (płaszczyzny gięcia) przed gięciem k względem gięcia k−1,
  /// °. Tylko informacyjnie (kolejność, szkic): długości nie zależą od
  /// obrotu. Pierwszy element jest pomijany. Pusta lista = wszystkie 0°.
  final List<double> rotationsDeg;

  /// Najkrótsza prosta, jaką giętarka chwyci (między gięciami i na końcach),
  /// mm. 0 = bez sprawdzania.
  final double minStraightMm;

  /// Przesunięcie znacznika względem początku łuku, mm (z instrukcji
  /// giętarki; + w stronę końca rurki). 0 = znacznik w punkcie styczności.
  final double markerOffsetMm;

  /// Dogięcie na sprężynowanie, ° — informacyjnie.
  final double springbackDeg;

  const TubeRunInput({
    required this.clrMm,
    required this.segmentsMm,
    required this.anglesDeg,
    this.rotationsDeg = const [],
    this.minStraightMm = 0,
    this.markerOffsetMm = 0,
    this.springbackDeg = 0,
  });

  /// Jedno gięcie: ramię A (od początku rurki do wierzchołka) i ramię B.
  factory TubeRunInput.single({
    required double clrMm,
    required double angleDeg,
    required double legAMm,
    required double legBMm,
    double minStraightMm = 0,
    double markerOffsetMm = 0,
    double springbackDeg = 0,
  }) =>
      TubeRunInput(
        clrMm: clrMm,
        segmentsMm: [legAMm, legBMm],
        anglesDeg: [angleDeg],
        minStraightMm: minStraightMm,
        markerOffsetMm: markerOffsetMm,
        springbackDeg: springbackDeg,
      );

  int get bendCount => anglesDeg.length;

  double rotationAt(int bendIndex0) =>
      bendIndex0 < rotationsDeg.length ? rotationsDeg[bendIndex0] : 0;

  List<TubeBendProblem> get problems {
    final out = <TubeBendProblem>[];
    if (!(clrMm > 0) || clrMm > kMaxTubeClrMm) {
      out.add(const TubeBendProblem(TubeBendProblemKind.radius));
    }
    if (anglesDeg.isEmpty || anglesDeg.length > kMaxTubeBends) {
      out.add(const TubeBendProblem(TubeBendProblemKind.bendCount));
    }
    if (segmentsMm.length != anglesDeg.length + 1) {
      out.add(const TubeBendProblem(TubeBendProblemKind.bendCount));
    }
    for (final (i, a) in anglesDeg.indexed) {
      if (!tubeBendAngleOk(a)) {
        out.add(TubeBendProblem(TubeBendProblemKind.angle, i + 1));
      }
    }
    for (final (i, s) in segmentsMm.indexed) {
      if (!(s > 0) || s > kMaxTubeSegmentMm) {
        out.add(TubeBendProblem(TubeBendProblemKind.segment, i + 1));
      }
    }
    for (var i = 1; i < rotationsDeg.length && i < anglesDeg.length; i++) {
      if (!rotationsDeg[i].isFinite) {
        out.add(TubeBendProblem(TubeBendProblemKind.rotation, i + 1));
      }
    }
    if (!(minStraightMm >= 0) || minStraightMm > kMaxTubeSegmentMm) {
      out.add(const TubeBendProblem(TubeBendProblemKind.minStraight));
    }
    if (!markerOffsetMm.isFinite || markerOffsetMm.abs() > 1000) {
      out.add(const TubeBendProblem(TubeBendProblemKind.markerOffset));
    }
    if (!(springbackDeg >= 0) || springbackDeg > 30) {
      out.add(const TubeBendProblem(TubeBendProblemKind.springback));
    }
    return out;
  }
}

/// Jedno gięcie na rurce: geometria i położenia od początku rurki.
class TubeBendMark {
  /// Numer gięcia od 1 (kolejność od początku rurki).
  final int number;
  final BendGeometry geometry;

  /// Obrót przed tym gięciem, 0–360° (0 dla pierwszego).
  final double rotationDeg;

  /// Wierzchołek na prostej rurce (metoda z zyskiem), mm od początku.
  final double vertexMm;

  /// Początek łuku (punkt styczności), mm od początku.
  final double arcStartMm;

  /// Koniec łuku, mm od początku.
  final double arcEndMm;

  /// Znacznik do ustawienia w giętarce: początek łuku + przesunięcie
  /// znacznika giętarki, mm od początku.
  final double markMm;

  /// Kąt, do którego gnie się na giętarce (θ + dogięcie), °.
  final double bendToDeg;

  const TubeBendMark({
    required this.number,
    required this.geometry,
    required this.rotationDeg,
    required this.vertexMm,
    required this.arcStartMm,
    required this.arcEndMm,
    required this.markMm,
    required this.bendToDeg,
  });

  double get angleDeg => geometry.angleDeg;

  /// Środek łuku, mm od początku (RIDGID 300/400 mierzy do niego przy 45°).
  double get arcMiddleMm => (arcStartMm + arcEndMm) / 2;
}

class TubeRunResult {
  final TubeRunInput input;
  final List<TubeBendMark> bends;

  /// Odcinki proste po gięciu (styczność–styczność, koniec–styczność), mm —
  /// tyle samo co odcinków wejścia. Ujemny = łuki zachodzą.
  final List<double> straightsMm;

  final double totalSegmentsMm;
  final double totalGainMm;

  /// Długość rozwinięta (bez zaokrąglenia), mm.
  final double developedMm;

  final List<TubeBendWarning> warnings;

  const TubeRunResult({
    required this.input,
    required this.bends,
    required this.straightsMm,
    required this.totalSegmentsMm,
    required this.totalGainMm,
    required this.developedMm,
    required this.warnings,
  });

  /// Da się wygiąć (żadne ostrzeżenie nie blokuje wyniku).
  bool get feasible => !warnings.any((w) => w.blocking);

  /// Długość cięcia zaokrąglona w górę do kroku [unit], mm.
  double cutLengthMm(TubeUnit unit) => roundCutLengthUpMm(developedMm, unit);
}

double _normDeg(double d) {
  final r = d % 360;
  return r < 0 ? r + 360 : r;
}

/// Liczy rurkę; `null`, gdy dane są błędne (patrz [TubeRunInput.problems]).
TubeRunResult? computeTubeRun(TubeRunInput i) {
  if (i.problems.isNotEmpty) return null;
  final n = i.bendCount;
  final geo = [
    for (final a in i.anglesDeg) bendGeometry(angleDeg: a, clrMm: i.clrMm),
  ];
  final bends = <TubeBendMark>[];
  var vertex = 0.0;
  for (var k = 0; k < n; k++) {
    vertex += i.segmentsMm[k];
    if (k > 0) vertex -= geo[k - 1].gainMm;
    final start = vertex - geo[k].setbackMm;
    bends.add(TubeBendMark(
      number: k + 1,
      geometry: geo[k],
      rotationDeg: k == 0 ? 0 : _normDeg(i.rotationAt(k)),
      vertexMm: vertex,
      arcStartMm: start,
      arcEndMm: start + geo[k].arcMm,
      markMm: start + i.markerOffsetMm,
      bendToDeg: geo[k].angleDeg + i.springbackDeg,
    ));
  }
  final straights = <double>[
    for (var s = 0; s <= n; s++)
      i.segmentsMm[s] -
          (s > 0 ? geo[s - 1].setbackMm : 0) -
          (s < n ? geo[s].setbackMm : 0),
  ];
  final total = i.segmentsMm.fold<double>(0, (a, b) => a + b);
  final gain = geo.fold<double>(0, (a, g) => a + g.gainMm);
  final developed = total - gain;

  final warnings = <TubeBendWarning>[];
  for (var s = 0; s <= n; s++) {
    final end = s == 0 || s == n;
    final st = straights[s];
    // Tolerancja na szum: prosta „równo zero” to łuki stykające się.
    if (st < -_eps) {
      warnings.add(TubeBendWarning(
          end
              ? TubeBendWarningKind.arcPastEnd
              : TubeBendWarningKind.arcsOverlap,
          s + 1,
          st,
          0));
    } else if (i.minStraightMm > 0 && st < i.minStraightMm - _eps) {
      warnings.add(TubeBendWarning(
          end
              ? TubeBendWarningKind.endStraightTooShort
              : TubeBendWarningKind.straightTooShort,
          s + 1,
          st,
          i.minStraightMm));
    }
  }
  // Przy niemożliwej geometrii znacznik i tak jest bez znaczenia — jeden
  // komunikat zamiast dwóch.
  final blocked = warnings.any((w) => w.blocking);
  for (final b in bends) {
    if (blocked) break;
    if (b.markMm < -_eps || b.markMm > developed + _eps) {
      warnings.add(TubeBendWarning(
          TubeBendWarningKind.markOutsideTube, b.number, b.markMm, 0));
    }
  }
  return TubeRunResult(
    input: i,
    bends: bends,
    straightsMm: straights,
    totalSegmentsMm: total,
    totalGainMm: gain,
    developedMm: developed,
    warnings: warnings,
  );
}

// ── Odsadzka (offset) i odsadzka przestrzenna (rolling offset) ─────────────

class TubeOffsetInput {
  final double clrMm;

  /// Przesunięcie osi H (w odsadzce przestrzennej: pionowe — rise), mm.
  final double heightMm;

  /// Przesunięcie boczne (spread) prostopadłe do H, mm; 0 = odsadzka płaska.
  final double spreadMm;

  /// Kąt obu gięć, ° (0 < θ ≤ 90).
  final double angleDeg;

  /// Od początku rurki do wierzchołka pierwszego gięcia, mm.
  final double legAMm;

  /// Od wierzchołka drugiego gięcia do końca rurki, mm.
  final double legBMm;

  final double minStraightMm;
  final double markerOffsetMm;
  final double springbackDeg;

  const TubeOffsetInput({
    required this.clrMm,
    required this.heightMm,
    required this.angleDeg,
    required this.legAMm,
    required this.legBMm,
    this.spreadMm = 0,
    this.minStraightMm = 0,
    this.markerOffsetMm = 0,
    this.springbackDeg = 0,
  });

  /// Rzeczywiste przesunięcie osi √(H² + S²) — jak w narzędziu „Rolling
  /// offset” dla rur (True Offset = √(Rise² + Spread²)).
  double get trueOffsetMm =>
      math.sqrt(heightMm * heightMm + spreadMm * spreadMm);

  /// Odległość między gięciami po osi (wierzchołek–wierzchołek) = H / sin θ.
  double get travelMm => trueOffsetMm / math.sin(_rad(angleDeg));

  TubeRunInput get run => TubeRunInput(
        clrMm: clrMm,
        segmentsMm: [legAMm, travelMm, legBMm],
        anglesDeg: [angleDeg, angleDeg],
        // Drugie gięcie w przeciwną stronę — ta sama płaszczyzna.
        rotationsDeg: const [0, 180],
        minStraightMm: minStraightMm,
        markerOffsetMm: markerOffsetMm,
        springbackDeg: springbackDeg,
      );

  List<TubeBendProblem> get problems {
    final out = <TubeBendProblem>[];
    if (!(heightMm > 0) || heightMm > kMaxTubeSegmentMm) {
      out.add(const TubeBendProblem(TubeBendProblemKind.offsetHeight));
    }
    if (!(spreadMm >= 0) || spreadMm > kMaxTubeSegmentMm) {
      out.add(const TubeBendProblem(TubeBendProblemKind.offsetSpread));
    }
    if (!(angleDeg > 0) || angleDeg > 90) {
      out.add(const TubeBendProblem(TubeBendProblemKind.angle));
    }
    if (out.isNotEmpty) {
      // Odcinek środkowy liczony z H i θ — bez nich nie ma co sprawdzać.
      return [
        ...out,
        ...run.problems.where((p) =>
            p.kind != TubeBendProblemKind.angle &&
            !(p.kind == TubeBendProblemKind.segment && p.index == 2)),
      ];
    }
    return run.problems;
  }
}

class TubeOffsetResult {
  final TubeOffsetInput input;

  /// √(H² + S²), mm.
  final double trueOffsetMm;

  /// Między wierzchołkami po osi = przesunięcie / sin θ, mm.
  final double travelMm;

  /// Postęp wzdłuż trasy między wierzchołkami = przesunięcie / tg θ, mm.
  final double advanceMm;

  /// Skrócenie trasy przez odsadzkę: travel − postęp = przesunięcie·tg(θ/2).
  final double shrinkMm;

  /// Obrót płaszczyzny odsadzki od pionu = atan(S / H), ° (0 dla płaskiej).
  final double rollFromVerticalDeg;

  final TubeRunResult run;

  const TubeOffsetResult({
    required this.input,
    required this.trueOffsetMm,
    required this.travelMm,
    required this.advanceMm,
    required this.shrinkMm,
    required this.rollFromVerticalDeg,
    required this.run,
  });
}

/// Liczy odsadzkę; `null`, gdy dane są błędne ([TubeOffsetInput.problems]).
TubeOffsetResult? computeTubeOffset(TubeOffsetInput i) {
  if (i.problems.isNotEmpty) return null;
  final run = computeTubeRun(i.run);
  if (run == null) return null;
  final t = i.trueOffsetMm;
  final a = _rad(i.angleDeg);
  final travel = i.travelMm;
  // 90°: tg → ∞, postęp dokładnie 0.
  final advance = i.angleDeg == 90 ? 0.0 : t / math.tan(a);
  return TubeOffsetResult(
    input: i,
    trueOffsetMm: t,
    travelMm: travel,
    advanceMm: advance,
    shrinkMm: travel - advance,
    rollFromVerticalDeg: math.atan2(i.spreadMm, i.heightMm) * 180.0 / math.pi,
    run: run,
  );
}
