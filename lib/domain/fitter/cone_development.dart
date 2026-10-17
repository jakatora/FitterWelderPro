/// Rozwinięcia blach dla kotlarza: stożek ścięty współosiowy (wzór
/// analityczny) i stożek mimośrodowy / ukośny (rozwinięcie z wierzchołka
/// + tabela linii prawdziwych do triangulacji). Wspólna geometria szablonów
/// płaskich (punkty, obrys, orientacja na arkuszu) używana też przez
/// przejście kwadrat–koło (transition_development.dart).
///
/// ── Oś obojętna ────────────────────────────────────────────────────────────
/// Rozwinięcie liczy się po średnicy średniej (oś obojętna w połowie
/// grubości): zewnętrzna → D − t, wewnętrzna → D + t, średnia → D.
/// (Konwencja warsztatowa; dla stożka średnica w płaszczyźnie końca leży
/// dokładniej o t/(2·cos α) od powierzchni — przy α ≤ 30° różnica < 0,16·t
/// na średnicy, w granicy tolerancji zwijania).
///
/// ── Stożek ścięty współosiowy ──────────────────────────────────────────────
/// Dm, dm — średnice średnie, H — wysokość, s = (Dm − dm)/2 — wysięg tworzącej
/// w rzucie, L = √(H² + s²) — tworząca, sin α = s / L (α — kąt połówkowy).
///   R = (Dm/2)·L/s = (Dm/2)/sin α      promień łuku zewnętrznego
///   r = (dm/2)·L/s                      promień łuku wewnętrznego, R − r = L
///   θ = 360°·(Dm/2)/R = 360°·sin α       kąt wycinka
///   długości łuków: R·θ = π·Dm, r·θ = π·dm (obwody).
///   cięciwa 2ρ·sin(θ/2), strzałka ρ·(1 − cos(θ/2)).
/// Rzędne od cięciwy (trasowanie bez cyrkla): dla punktu x od końca cięciwy
/// c = 2ρ·sin(θ/2): y = √(ρ² − (x − c/2)²) − ρ·cos(θ/2).
///
/// ── Stożek mimośrodowy (ukośny) ────────────────────────────────────────────
/// Koło dolne Dm (środek 0,0,0), górne dm (środek e,0,H), płaszczyzny
/// równoległe. Tworzące łączą punkty o tym samym kącie φ (jednokładność
/// względem wierzchołka V = (e·k, 0, H·k), k = Dm/(Dm − dm)). Długość tworzącej
/// (linia prawdziwa) |P(φ)Q(φ)|. Rozwinięcie: tworzące odkładane z wierzchołka
/// pod kątem ψ(φ) = ∫ |(P − V) × P'| / |P − V|² dφ (dokładny kąt rozwinięcia
/// powierzchni stożkowej, całka Simpsona). Dzięki temu cięciwy NA BLASZE
/// w tabeli są dokładne — klasyczna triangulacja cięciwami z rzutu skraca
/// obwód (np. o ~0,9 % przy 12 podziałach).
///
/// Czysty Dart.
library;

import 'dart:math' as math;

typedef Pt = math.Point<double>;

const double _deg = math.pi / 180;

// ─── Geometria wspólna ───────────────────────────────────────────────────────

/// Wektor 3D (mm).
class V3 {
  final double x, y, z;
  const V3(this.x, this.y, this.z);
  V3 operator +(V3 o) => V3(x + o.x, y + o.y, z + o.z);
  V3 operator -(V3 o) => V3(x - o.x, y - o.y, z - o.z);
  V3 operator *(double k) => V3(x * k, y * k, z * k);
  double dot(V3 o) => x * o.x + y * o.y + z * o.z;
  V3 cross(V3 o) => V3(y * o.z - z * o.y, z * o.x - x * o.z, x * o.y - y * o.x);
  double get length => math.sqrt(dot(this));
  double distanceTo(V3 o) => (this - o).length;
}

/// Jak wymiarowane są średnice (i boki prostokąta przejścia).
enum DiameterRef { outside, inside, mean }

/// Wymiar po osi obojętnej z wymiaru odniesienia [v] i grubości [t].
double neutralDim(double v, double t, DiameterRef ref) => switch (ref) {
      DiameterRef.outside => v - t,
      DiameterRef.inside => v + t,
      DiameterRef.mean => v,
    };

/// Opisany punkt rozwinięcia (np. „3”, „3'”, „A”).
class PatternMark {
  final String label;
  final Pt at;
  const PatternMark(this.label, this.at);
}

/// Jedna część rozwinięcia w układzie arkusza: lewy dolny róg prostokąta
/// opisanego = (0, 0), X w prawo, Y w górę, wymiary w mm.
class FlatPatternPart {
  /// Obrys (linia cięcia), wielokąt zamknięty — ostatni punkt łączy się
  /// z pierwszym.
  final List<Pt> outline;

  /// Linie tworzących / gięcia (odcinki lub łamane).
  final List<List<Pt>> bendLines;

  /// Linie pomocnicze triangulacji (przekątne).
  final List<List<Pt>> helperLines;

  /// Pas naddatku na zakład / spoinę (wielokąt zamknięty; pusty = brak).
  final List<Pt> allowance;

  /// Punkty trasowania z etykietami.
  final List<PatternMark> marks;

  final double widthMm;
  final double heightMm;

  const FlatPatternPart({
    required this.outline,
    required this.widthMm,
    required this.heightMm,
    this.bendLines = const [],
    this.helperLines = const [],
    this.allowance = const [],
    this.marks = const [],
  });

  /// Czy mieści się na arkuszu [sheetA] × [sheetB] (w dowolnym obrocie o 90°).
  bool fitsSheet(double sheetA, double sheetB) =>
      fitsRect(widthMm, heightMm, sheetA, sheetB);
}

bool fitsRect(double w, double h, double a, double b) =>
    (w <= a + 1e-6 && h <= b + 1e-6) || (w <= b + 1e-6 && h <= a + 1e-6);

/// Kąt rozwinięcia (rad, ≥ 0) powierzchni stożkowej o wierzchołku [apex]
/// między tworzącymi przez c(φ0) i c(φ1): ∫ |(c − K) × c'| / |c − K|² dφ.
/// Całka Simpsona — funkcja podcałkowa jest gładka (analityczna).
double developedFanAngle(V3 apex, V3 Function(double phi) c,
    V3 Function(double phi) dc, double phi0, double phi1,
    {int steps = 16}) {
  double f(double p) {
    final v = c(p) - apex;
    final l2 = v.dot(v);
    if (l2 <= 0) return 0;
    return v.cross(dc(p)).length / l2;
  }

  final n = steps.isEven ? steps : steps + 1;
  final h = (phi1 - phi0) / n;
  var s = f(phi0) + f(phi1);
  for (var i = 1; i < n; i++) {
    s += f(phi0 + i * h) * (i.isOdd ? 4 : 2);
  }
  return (s * h / 3).abs();
}

/// Obrót punktu [p] wokół początku o kąt [a] (rad, przeciwnie do zegara).
Pt rotatePt(Pt p, double a) {
  final c = math.cos(a), s = math.sin(a);
  return Pt(p.x * c - p.y * s, p.x * s + p.y * c);
}

double cross2(Pt a, Pt b) => a.x * b.y - a.y * b.x;

/// Przekształcenie do układu arkusza: odcinek [a]→[b] (końce krawędzi
/// dolnej) poziomo, środek krawędzi dolnej [down] pod nim (gdy leży na nim
/// — środek krawędzi górnej [up] nad nim), prostokąt opisany na [all]
/// zaczyna się w (0, 0).
class PlateFrame {
  final double _angle;
  final Pt _origin;
  final double minX, minY, maxX, maxY;

  PlateFrame._(
      this._angle, this._origin, this.minX, this.minY, this.maxX, this.maxY);

  factory PlateFrame.fit(Pt a, Pt b,
      {required Pt down, required Pt up, required Iterable<Pt> all}) {
    final d = b - a;
    double angle;
    if (d.magnitude > 1e-9) {
      angle = -math.atan2(d.y, d.x);
      final dy = rotatePt(down - a, angle).y;
      final uy = rotatePt(up - a, angle).y;
      final flip = dy.abs() > 1e-6 * d.magnitude ? dy > 0 : uy < 0;
      if (flip) angle += math.pi;
    } else {
      // Końce się pokrywają — „góra” prosto do góry.
      final u = up - down;
      angle = math.pi / 2 - math.atan2(u.y, u.x);
    }
    var minX = double.infinity, minY = double.infinity;
    var maxX = -double.infinity, maxY = -double.infinity;
    for (final p in all) {
      final q = rotatePt(p, angle);
      minX = math.min(minX, q.x);
      minY = math.min(minY, q.y);
      maxX = math.max(maxX, q.x);
      maxY = math.max(maxY, q.y);
    }
    return PlateFrame._(angle, Pt(minX, minY), minX, minY, maxX, maxY);
  }

  Pt map(Pt p) => rotatePt(p, _angle) - _origin;
  double get width => maxX - minX;
  double get height => maxY - minY;
}

/// Ile kroków próbkowania na jeden podział obwodu, żeby krok kąta φ był
/// ≤ 1° (długość łamanej różni się od łuku o < 2·10⁻⁵).
int densifyFor(int divisions) => math.max(4, (360 / divisions).ceil());

double polylineLength(List<Pt> pts) {
  var s = 0.0;
  for (var i = 1; i < pts.length; i++) {
    s += pts[i].distanceTo(pts[i - 1]);
  }
  return s;
}

// ─── Stożek ścięty współosiowy ───────────────────────────────────────────────

enum ConeSizeMode { height, halfAngle, slant }

enum ConeProblem {
  largeDia,
  smallDia,

  /// d ≥ D — to nie stożek (walczak zwija się z prostokąta).
  smallNotLess,
  height,
  halfAngle,
  slant,

  /// Tworząca krótsza niż różnica promieni — stożek nie istnieje.
  slantTooShort,

  /// t < 0 albo t ≥ min(D, d)/2 (dla d = 0: D/2).
  thickness,
  parts,
  allowance,
}

class ConeInput {
  /// Średnica duża, mm (wg [ref]).
  final double largeDiaMm;

  /// Średnica mała, mm (0 = stożek pełny, z wierzchołkiem).
  final double smallDiaMm;
  final ConeSizeMode mode;
  final double heightMm;
  final double halfAngleDeg;

  /// Tworząca (długość boku stożka między końcami), mm.
  final double slantMm;
  final double thicknessMm;
  final DiameterRef ref;

  /// Na ile części dzielić wycinek (1–12).
  final int parts;

  /// Naddatek na zakład / spoinę wzdłuż jednej krawędzi prostej części, mm.
  final double allowanceMm;

  const ConeInput({
    required this.largeDiaMm,
    required this.smallDiaMm,
    this.mode = ConeSizeMode.height,
    this.heightMm = 0,
    this.halfAngleDeg = 0,
    this.slantMm = 0,
    this.thicknessMm = 0,
    this.ref = DiameterRef.mean,
    this.parts = 1,
    this.allowanceMm = 0,
  });

  double get meanLargeMm => neutralDim(largeDiaMm, thicknessMm, ref);
  double get meanSmallMm =>
      smallDiaMm == 0 ? 0 : neutralDim(smallDiaMm, thicknessMm, ref);

  List<ConeProblem> get problems {
    final out = <ConeProblem>[];
    final dOk = largeDiaMm.isFinite && largeDiaMm > 0 && largeDiaMm <= 50000;
    if (!dOk) out.add(ConeProblem.largeDia);
    final sOk = smallDiaMm.isFinite && smallDiaMm >= 0;
    if (!sOk) {
      out.add(ConeProblem.smallDia);
    } else if (dOk && smallDiaMm >= largeDiaMm) {
      out.add(ConeProblem.smallNotLess);
    }
    final tOk = thicknessMm.isFinite &&
        thicknessMm >= 0 &&
        (!dOk ||
            !sOk ||
            thicknessMm < (smallDiaMm > 0 ? smallDiaMm : largeDiaMm) / 2);
    if (!tOk) out.add(ConeProblem.thickness);
    switch (mode) {
      case ConeSizeMode.height:
        if (!(heightMm.isFinite && heightMm > 0 && heightMm <= 100000)) {
          out.add(ConeProblem.height);
        }
      case ConeSizeMode.halfAngle:
        if (!(halfAngleDeg.isFinite && halfAngleDeg > 0 && halfAngleDeg < 90)) {
          out.add(ConeProblem.halfAngle);
        }
      case ConeSizeMode.slant:
        if (!(slantMm.isFinite && slantMm > 0 && slantMm <= 100000)) {
          out.add(ConeProblem.slant);
        } else if (out.isEmpty &&
            slantMm <= (meanLargeMm - meanSmallMm) / 2 + 1e-9) {
          out.add(ConeProblem.slantTooShort);
        }
    }
    if (parts < 1 || parts > 12) out.add(ConeProblem.parts);
    if (!(allowanceMm.isFinite && allowanceMm >= 0 && allowanceMm <= 200)) {
      out.add(ConeProblem.allowance);
    }
    return out;
  }
}

/// Rzędna łuku od cięciwy.
class ChordOffset {
  /// Od końca cięciwy, mm.
  final double xMm;

  /// Od cięciwy do łuku, mm.
  final double yMm;
  const ChordOffset(this.xMm, this.yMm);
}

/// Wycinek pierścienia kołowego (cały stożek albo jedna jego część).
class ConeSector {
  final double angleDeg;
  final double outerRadiusMm;
  final double innerRadiusMm;
  final double allowanceMm;

  const ConeSector({
    required this.angleDeg,
    required this.outerRadiusMm,
    required this.innerRadiusMm,
    this.allowanceMm = 0,
  });

  double get _half => angleDeg / 2 * _deg;
  double get outerArcMm => outerRadiusMm * angleDeg * _deg;
  double get innerArcMm => innerRadiusMm * angleDeg * _deg;
  double get outerChordMm => 2 * outerRadiusMm * math.sin(_half);
  double get innerChordMm => 2 * innerRadiusMm * math.sin(_half);
  double get outerSagittaMm => outerRadiusMm * (1 - math.cos(_half));
  double get innerSagittaMm => innerRadiusMm * (1 - math.cos(_half));

  /// Przekątna kontrolna: koniec łuku zewnętrznego → przeciwny koniec
  /// łuku wewnętrznego (do sprawdzenia trasowania).
  double get diagonalMm {
    final rr = outerRadiusMm, r = innerRadiusMm;
    return math.sqrt(
        math.max(0, rr * rr + r * r - 2 * rr * r * math.cos(angleDeg * _deg)));
  }

  /// Odległość cięciwy wewnętrznej od zewnętrznej (wzdłuż osi symetrii).
  double get chordGapMm => (outerRadiusMm - innerRadiusMm) * math.cos(_half);

  /// Punkt (ρ, β) w układzie wierzchołka: oś symetrii w dół, β od osi.
  static Pt _polar(double rho, double beta) =>
      Pt(rho * math.sin(beta), -rho * math.cos(beta));

  /// Kandydaci do prostokąta opisanego (układ wierzchołka).
  List<Pt> _extremes() {
    final h = _half;
    final rr = outerRadiusMm, r = innerRadiusMm;
    final pts = <Pt>[
      _polar(rr, -h),
      _polar(rr, h),
      _polar(rr, 0),
      if (h >= math.pi / 2) ...[
        _polar(rr, -math.pi / 2),
        _polar(rr, math.pi / 2)
      ],
      if (r > 0) ...[_polar(r, -h), _polar(r, h)] else const Pt(0, 0),
      ..._allowanceRaw(),
    ];
    return pts;
  }

  /// Pas naddatku wzdłuż prawej krawędzi prostej (β = +θ/2).
  List<Pt> _allowanceRaw() {
    if (allowanceMm <= 0) return const [];
    final h = _half;
    final n = Pt(math.cos(h), math.sin(h)) * allowanceMm;
    final inner = _polar(innerRadiusMm, h);
    final outer = _polar(outerRadiusMm, h);
    return [inner, outer, outer + n, inner + n];
  }

  ({double minX, double minY, double maxX, double maxY}) _bounds() {
    var minX = double.infinity, minY = double.infinity;
    var maxX = -double.infinity, maxY = -double.infinity;
    for (final p in _extremes()) {
      minX = math.min(minX, p.x);
      minY = math.min(minY, p.y);
      maxX = math.max(maxX, p.x);
      maxY = math.max(maxY, p.y);
    }
    return (minX: minX, minY: minY, maxX: maxX, maxY: maxY);
  }

  /// Prostokąt blachy (oś symetrii pionowo, łuk zewnętrzny na dole),
  /// z naddatkiem.
  double get widthMm {
    final b = _bounds();
    return b.maxX - b.minX;
  }

  double get heightMm {
    final b = _bounds();
    return b.maxY - b.minY;
  }

  bool fitsSheet(double a, double b) => fitsRect(widthMm, heightMm, a, b);

  /// Czy łuk da się trasować od cięciwy (wycinek ≤ 180°).
  bool get chordOffsetsPossible => angleDeg <= 180 + 1e-9;

  /// Rzędne łuku ([outer] — zewnętrzny, inaczej wewnętrzny) od cięciwy co
  /// [stepMm], plus koniec cięciwy i jej środek (strzałka). Pusta lista, gdy
  /// wycinek > 180° albo promień 0.
  List<ChordOffset> chordOffsets(
      {required bool outer, required double stepMm}) {
    final rho = outer ? outerRadiusMm : innerRadiusMm;
    if (rho <= 0 || !chordOffsetsPossible || !(stepMm > 0)) return const [];
    final c = 2 * rho * math.sin(_half);
    final base = rho * math.cos(_half);
    final xs = <double>[];
    for (var k = 0; k * stepMm < c - 1e-6; k++) {
      xs.add(k * stepMm);
    }
    xs.add(c);
    if (!xs.any((x) => (x - c / 2).abs() < 1e-6)) xs.add(c / 2);
    xs.sort();
    return [
      for (final x in xs)
        ChordOffset(
            x,
            math.max(
                0,
                math.sqrt(math.max(0, rho * rho - (x - c / 2) * (x - c / 2))) -
                    base)),
    ];
  }

  /// Szablon w układzie arkusza: obrys, tworzące co θ/[generators],
  /// pas naddatku.
  FlatPatternPart pattern({int generators = 8}) {
    final b = _bounds();
    Pt map(Pt p) => Pt(p.x - b.minX, p.y - b.minY);
    final h = _half;
    final steps = math.max(8, (angleDeg / 0.5).ceil());
    final outline = <Pt>[
      for (var i = 0; i <= steps; i++)
        map(_polar(outerRadiusMm, -h + 2 * h * i / steps)),
      if (innerRadiusMm > 0)
        for (var i = steps; i >= 0; i--)
          map(_polar(innerRadiusMm, -h + 2 * h * i / steps))
      else
        map(const Pt(0, 0)),
    ];
    final lines = <List<Pt>>[
      for (var i = 1; i < generators; i++)
        [
          map(_polar(innerRadiusMm, -h + 2 * h * i / generators)),
          map(_polar(outerRadiusMm, -h + 2 * h * i / generators)),
        ],
    ];
    return FlatPatternPart(
      outline: outline,
      bendLines: lines,
      allowance: [for (final p in _allowanceRaw()) map(p)],
      widthMm: b.maxX - b.minX,
      heightMm: b.maxY - b.minY,
    );
  }
}

class ConeResult {
  final ConeInput input;
  final double meanLargeMm;
  final double meanSmallMm;
  final double heightMm;
  final double slantMm;
  final double halfAngleDeg;

  /// R — promień łuku zewnętrznego (duża średnica), mm.
  final double outerRadiusMm;

  /// r — promień łuku wewnętrznego (mała średnica), mm; 0 dla pełnego stożka.
  final double innerRadiusMm;

  /// θ — kąt całego wycinka, °.
  final double sectorAngleDeg;

  const ConeResult({
    required this.input,
    required this.meanLargeMm,
    required this.meanSmallMm,
    required this.heightMm,
    required this.slantMm,
    required this.halfAngleDeg,
    required this.outerRadiusMm,
    required this.innerRadiusMm,
    required this.sectorAngleDeg,
  });

  bool get isFull => meanSmallMm == 0;
  int get parts => input.parts;
  double get outerArcMm => math.pi * meanLargeMm;
  double get innerArcMm => math.pi * meanSmallMm;

  /// Cały wycinek (bez naddatku).
  ConeSector get whole => ConeSector(
      angleDeg: sectorAngleDeg,
      outerRadiusMm: outerRadiusMm,
      innerRadiusMm: innerRadiusMm);

  /// Jedna część (θ / N) z naddatkiem.
  ConeSector get part => sectorFor(parts);

  ConeSector sectorFor(int n) => ConeSector(
      angleDeg: sectorAngleDeg / n,
      outerRadiusMm: outerRadiusMm,
      innerRadiusMm: innerRadiusMm,
      allowanceMm: input.allowanceMm);

  /// Pole rozwinięcia (bez naddatku), mm².
  double get areaMm2 =>
      sectorAngleDeg *
      _deg /
      2 *
      (outerRadiusMm * outerRadiusMm - innerRadiusMm * innerRadiusMm);

  /// Masa blachy rozwinięcia (netto), kg — gęstość kg/m³.
  double massKg({double densityKgM3 = 7850}) =>
      areaMm2 * input.thicknessMm * 1e-9 * densityKgM3;

  /// Stożek bardzo smukły — cyrkiel R za duży, trasuj z tabeli rzędnych.
  bool get needsOrdinates => outerRadiusMm > 3000;

  /// Wycinek prawie płaski — źle się zwija, lepiej dzielić.
  bool get nearlyFlat => sectorAngleDeg > 300;

  /// Najmniejsza liczba części (≤ 12), przy której część mieści się na
  /// arkuszu [sheetA] × [sheetB]; przy θ > 300° co najmniej 2. Null — żadna.
  int? recommendedParts(double sheetA, double sheetB) {
    for (var n = nearlyFlat ? 2 : 1; n <= 12; n++) {
      if (sectorFor(n).fitsSheet(sheetA, sheetB)) return n;
    }
    return null;
  }
}

/// Liczy rozwinięcie; `null`, gdy dane są błędne (patrz [ConeInput.problems]).
ConeResult? computeCone(ConeInput i) {
  if (i.problems.isNotEmpty) return null;
  final dl = i.meanLargeMm;
  final ds = i.meanSmallMm;
  final run = (dl - ds) / 2;
  double h, l;
  switch (i.mode) {
    case ConeSizeMode.height:
      h = i.heightMm;
      l = math.sqrt(h * h + run * run);
    case ConeSizeMode.halfAngle:
      final a = i.halfAngleDeg * _deg;
      h = run / math.tan(a);
      l = run / math.sin(a);
    case ConeSizeMode.slant:
      l = i.slantMm;
      h = math.sqrt(math.max(0, l * l - run * run));
  }
  final sinA = run / l;
  final rr = dl / 2 * l / run;
  final r = ds / 2 * l / run;
  return ConeResult(
    input: i,
    meanLargeMm: dl,
    meanSmallMm: ds,
    heightMm: h,
    slantMm: l,
    halfAngleDeg: math.asin(sinA.clamp(0.0, 1.0)) / _deg,
    outerRadiusMm: rr,
    innerRadiusMm: r,
    sectorAngleDeg: 360 * sinA,
  );
}

// ─── Stożek mimośrodowy / ukośny ─────────────────────────────────────────────

enum EccentricProblem {
  largeDia,
  smallDia,
  smallNotLess,
  height,
  offset,
  thickness,
  divisions,
  parts,
}

/// Dozwolone liczby podziałów obwodu.
const kConeDivisions = [12, 16, 24, 32, 48];

class EccentricConeInput {
  final double largeDiaMm;

  /// 0 = stożek pełny (ukośny, z wierzchołkiem).
  final double smallDiaMm;
  final double heightMm;

  /// Przesunięcie osi koła małego względem dużego (w rzucie), mm.
  final double offsetMm;

  /// Jedna tworząca pionowa — przesunięcie liczone: e = (Dm − dm)/2.
  final bool verticalSide;
  final double thicknessMm;
  final DiameterRef ref;

  /// Podział obwodu na N części (12/16/24/32/48).
  final int divisions;

  /// Części blachy: 1, 2 albo 4.
  final int parts;

  /// Szew po krótkiej stronie (najkrótsza tworząca), inaczej po długiej.
  final bool seamOnShortSide;

  const EccentricConeInput({
    required this.largeDiaMm,
    required this.smallDiaMm,
    required this.heightMm,
    this.offsetMm = 0,
    this.verticalSide = false,
    this.thicknessMm = 0,
    this.ref = DiameterRef.mean,
    this.divisions = 16,
    this.parts = 1,
    this.seamOnShortSide = true,
  });

  double get meanLargeMm => neutralDim(largeDiaMm, thicknessMm, ref);
  double get meanSmallMm =>
      smallDiaMm == 0 ? 0 : neutralDim(smallDiaMm, thicknessMm, ref);

  /// Przesunięcie użyte do obliczeń, mm.
  double get effectiveOffsetMm =>
      verticalSide ? (meanLargeMm - meanSmallMm) / 2 : offsetMm;

  List<EccentricProblem> get problems {
    final out = <EccentricProblem>[];
    final dOk = largeDiaMm.isFinite && largeDiaMm > 0 && largeDiaMm <= 50000;
    if (!dOk) out.add(EccentricProblem.largeDia);
    final sOk = smallDiaMm.isFinite && smallDiaMm >= 0;
    if (!sOk) {
      out.add(EccentricProblem.smallDia);
    } else if (dOk && smallDiaMm >= largeDiaMm) {
      out.add(EccentricProblem.smallNotLess);
    }
    if (!(heightMm.isFinite && heightMm > 0 && heightMm <= 100000)) {
      out.add(EccentricProblem.height);
    }
    if (!verticalSide &&
        !(offsetMm.isFinite && offsetMm >= 0 && offsetMm <= 100000)) {
      out.add(EccentricProblem.offset);
    }
    if (!(thicknessMm.isFinite &&
        thicknessMm >= 0 &&
        (!dOk ||
            !sOk ||
            thicknessMm < (smallDiaMm > 0 ? smallDiaMm : largeDiaMm) / 2))) {
      out.add(EccentricProblem.thickness);
    }
    if (!kConeDivisions.contains(divisions)) {
      out.add(EccentricProblem.divisions);
    }
    if (!const [1, 2, 4].contains(parts)) out.add(EccentricProblem.parts);
    return out;
  }
}

/// Wiersz tabeli triangulacji: podział j (od szwu).
class EccentricRow {
  /// Numer punktu (1 = szew).
  final int index;

  /// Kąt φ od szwu, °.
  final double phiDeg;

  /// Linia prawdziwa: tworząca j–j' (dół–góra), mm.
  final double generatorMm;

  /// Cięciwa NA BLASZE j → j+1 (krawędź dolna), mm; null w ostatnim wierszu.
  final double? bottomChordMm;

  /// Cięciwa na blasze j' → (j+1)' (krawędź górna), mm.
  final double? topChordMm;

  /// Przekątna na blasze j' → j+1, mm.
  final double? diagonalMm;

  const EccentricRow({
    required this.index,
    required this.phiDeg,
    required this.generatorMm,
    this.bottomChordMm,
    this.topChordMm,
    this.diagonalMm,
  });
}

class EccentricConeResult {
  final EccentricConeInput input;
  final double meanLargeMm;
  final double meanSmallMm;
  final double offsetMm;

  /// Wysokość wierzchołka nad kołem dużym, mm.
  final double apexHeightMm;
  final double shortestGeneratorMm;
  final double longestGeneratorMm;

  /// Pochylenie boku krótkiego / długiego od pionu, ° (ujemne = na zewnątrz).
  final double shortSideAngleDeg;
  final double longSideAngleDeg;

  /// Wiersze N + 1 (ostatni = szew zamykający).
  final List<EccentricRow> rows;
  final List<FlatPatternPart> parts;

  /// Długość krawędzi dolnej / górnej na blasze (wszystkie części), mm —
  /// kontrola: = π·Dm i π·dm.
  final double bottomEdgeMm;
  final double topEdgeMm;

  /// Kąt rozwinięcia wokół wierzchołka (całość), °.
  final double developedAngleDeg;

  /// Odległości wierzchołek → punkty koła dolnego (rozwinięcie), mm.
  final List<double> apexDistancesMm;

  const EccentricConeResult({
    required this.input,
    required this.meanLargeMm,
    required this.meanSmallMm,
    required this.offsetMm,
    required this.apexHeightMm,
    required this.shortestGeneratorMm,
    required this.longestGeneratorMm,
    required this.shortSideAngleDeg,
    required this.longSideAngleDeg,
    required this.rows,
    required this.parts,
    required this.bottomEdgeMm,
    required this.topEdgeMm,
    required this.developedAngleDeg,
    required this.apexDistancesMm,
  });

  bool get isFull => meanSmallMm == 0;

  /// Cięciwa podziału w RZUCIE (stała) — klasyczna triangulacja.
  double get planChordBottomMm =>
      meanLargeMm * math.sin(math.pi / input.divisions);
  double get planChordTopMm =>
      meanSmallMm * math.sin(math.pi / input.divisions);
}

/// Liczy stożek mimośrodowy; `null`, gdy dane są błędne.
EccentricConeResult? computeEccentricCone(EccentricConeInput i) {
  if (i.problems.isNotEmpty) return null;
  final densify = densifyFor(i.divisions);
  final r1 = i.meanLargeMm / 2;
  final r2 = i.meanSmallMm / 2;
  final e = i.effectiveOffsetMm;
  final h = i.heightMm;
  final k = r2 / r1;
  final s = r1 / (r1 - r2);
  final apex = V3(e * s, 0, h * s);
  final n = i.divisions;
  final phiSeam = i.seamOnShortSide ? 0.0 : math.pi;

  V3 bottom(double phi) => V3(r1 * math.cos(phi), r1 * math.sin(phi), 0);
  V3 dBottom(double phi) => V3(-r1 * math.sin(phi), r1 * math.cos(phi), 0);

  // Orientacja: rozwinięcie oglądane od zewnątrz.
  final p0 = bottom(phiSeam), p1 = bottom(phiSeam + 2 * math.pi / n);
  final normal = (p0 - apex).cross(p1 - apex);
  final centroid = (apex + p0 + p1) * (1 / 3);
  final axisPt = V3(e * centroid.z / h, 0, centroid.z);
  final sign = normal.dot(centroid - axisPt) >= 0 ? 1.0 : -1.0;

  // Gęste próbkowanie: φ_m, ρ_m, ψ_m (kąt rozwinięcia).
  final m = n * densify;
  final phis = [for (var j = 0; j <= m; j++) phiSeam + 2 * math.pi * j / m];
  final rhos = [for (final p in phis) bottom(p).distanceTo(apex)];
  final psis = <double>[0];
  for (var j = 1; j <= m; j++) {
    psis.add(psis.last +
        developedFanAngle(apex, bottom, dBottom, phis[j - 1], phis[j],
            steps: 8));
  }
  Pt dev(int j, double scale) =>
      Pt(math.cos(sign * psis[j]), math.sin(sign * psis[j])) *
      (rhos[j] * scale);

  // Wiersze (punkty podziału).
  final rows = <EccentricRow>[];
  for (var j = 0; j <= n; j++) {
    final a = j * densify;
    final rho = rhos[a];
    final gen = rho * (1 - k);
    if (j == n) {
      rows.add(EccentricRow(index: j + 1, phiDeg: 360, generatorMm: gen));
      break;
    }
    final b = a + densify;
    final dpsi = psis[b] - psis[a];
    final rho2 = rhos[b];
    final chord = math.sqrt(
        math.max(0, rho * rho + rho2 * rho2 - 2 * rho * rho2 * math.cos(dpsi)));
    final diag = math.sqrt(math.max(0,
        k * k * rho * rho + rho2 * rho2 - 2 * k * rho * rho2 * math.cos(dpsi)));
    rows.add(EccentricRow(
      index: j + 1,
      phiDeg: 360.0 * j / n,
      generatorMm: gen,
      bottomChordMm: chord,
      topChordMm: k * chord,
      diagonalMm: diag,
    ));
  }

  // Części.
  final perPart = m ~/ i.parts;
  final parts = <FlatPatternPart>[];
  var bottomEdge = 0.0, topEdge = 0.0;
  for (var p = 0; p < i.parts; p++) {
    final from = p * perPart, to = (p + 1) * perPart;
    final bottomPts = [for (var j = from; j <= to; j++) dev(j, 1)];
    final topPts = [for (var j = from; j <= to; j++) dev(j, k)];
    bottomEdge += polylineLength(bottomPts);
    topEdge += polylineLength(topPts);
    final rawOutline = <Pt>[
      ...bottomPts,
      if (k > 0) ...topPts.reversed else const Pt(0, 0),
    ];
    final frame = PlateFrame.fit(bottomPts.first, bottomPts.last,
        down: bottomPts[bottomPts.length ~/ 2],
        up: k > 0 ? topPts[topPts.length ~/ 2] : const Pt(0, 0),
        all: rawOutline);
    final gens = <List<Pt>>[];
    final diags = <List<Pt>>[];
    final marks = <PatternMark>[];
    for (var j = from; j <= to; j += densify) {
      final idx = j ~/ densify + 1;
      final bp = frame.map(dev(j, 1));
      final tp = frame.map(dev(j, k));
      if (j != from && j != to) gens.add([bp, tp]);
      if (j + densify <= to && k > 0) {
        diags.add([tp, frame.map(dev(j + densify, 1))]);
      }
      marks.add(PatternMark('$idx', bp));
      if (k > 0) marks.add(PatternMark("$idx'", tp));
    }
    if (k == 0) marks.add(PatternMark('V', frame.map(const Pt(0, 0))));
    parts.add(FlatPatternPart(
      outline: [for (final q in rawOutline) frame.map(q)],
      bendLines: gens,
      helperLines: diags,
      marks: marks,
      widthMm: frame.width,
      heightMm: frame.height,
    ));
  }

  final run1 = r1 - r2 - e, run2 = r1 - r2 + e;
  return EccentricConeResult(
    input: i,
    meanLargeMm: i.meanLargeMm,
    meanSmallMm: i.meanSmallMm,
    offsetMm: e,
    apexHeightMm: h * s,
    shortestGeneratorMm: math.sqrt(run1 * run1 + h * h),
    longestGeneratorMm: math.sqrt(run2 * run2 + h * h),
    shortSideAngleDeg: math.atan2(run1, h) / _deg,
    longSideAngleDeg: math.atan2(run2, h) / _deg,
    rows: rows,
    parts: parts,
    bottomEdgeMm: bottomEdge,
    topEdgeMm: topEdge,
    developedAngleDeg: psis.last / _deg,
    apexDistancesMm: [for (var j = 0; j <= m; j += densify) rhos[j]],
  );
}

/// Generator długości ekstremalnych zgodny z tabelą (pomocniczo w testach).
double eccentricGeneratorAt(EccentricConeInput i, double phiDeg) {
  final r1 = i.meanLargeMm / 2;
  final r2 = i.meanSmallMm / 2;
  final e = i.effectiveOffsetMm;
  final phi = phiDeg * _deg;
  final p = V3(r1 * math.cos(phi), r1 * math.sin(phi), 0);
  final q = V3(e + r2 * math.cos(phi), r2 * math.sin(phi), i.heightMm);
  return p.distanceTo(q);
}
