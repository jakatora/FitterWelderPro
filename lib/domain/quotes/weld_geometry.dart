/// Geometria spoin do wyceny: przekrój rowka → objętość stopiwa na jedną
/// spoinę, z podziałem na grań i resztę (wypełnienie + lico).
///
/// Model (wszystko w mm):
///   • rowek V / I (I = V o kącie 0°) spawany z jednej strony:
///       A(h) = b·h + max(0, h − c)²·tg(α/2)
///     gdzie b — szczelina, c — próg (płaska część czoła), α — kąt rowka
///     (CAŁKOWITY, np. 60° dla fazy 30° na obu elementach), h — wysokość
///     od strony grani;
///   • rowek X (blachy, spawane z dwóch stron, próg w środku):
///       A = b·t + 2·((t − c)/2)²·tg(α/2);
///   • nadlew lica (odcinek paraboli): 2/3 · szerokość · wysokość, lico
///     zachodzi [kCapOverlapMm] na każdą krawędź rowka;
///   • nadlew grani od środka rury: 2/3 · (b + 2) · [kRootReinforcementMm];
///   • pachwina o grubości obliczeniowej a: A = a² (przyprostokątne a·√2),
///     plus wypukłość [kFilletConvexity];
///   • króciec nasadzany (set-on): faza na króćcu, rowek jednostronny
///     A(h) = b·h + ½·max(0, h − c)²·tg β, plus spoina pachwinowa
///     przykrywająca tc = min(0,7·t, 6 mm) wg ASME B31.3 rys. 328.5.4D.
///
/// Długość spoiny obwodowej liczona na średnicy przy środku ciężkości
/// danej części przekroju (grań przy średnicy wewnętrznej, lico na
/// zewnętrznej) — różnica względem „π·OD dla wszystkiego" to kilka procent
/// na grubych ściankach.
///
/// Wymiary rowka domyślne: EN ISO 9692-1 (rury: faza 30° → α = 60°,
/// c ≈ 1,5, b ≈ 2,5) albo ASME B16.25 (faza 37,5° → α = 75°, c = 1,6).
///
/// Czysty Dart.
library;

import 'dart:math' as math;

/// Wysokość lica nad powierzchnią (EN ISO 5817 poz. 1.9: h ≤ 1 + 0,1·b
/// dla poziomu B — przyjmujemy typowe 1,5 mm).
const double kCapHeightMm = 1.5;

/// O ile lico wychodzi poza krawędź rowka z każdej strony.
const double kCapOverlapMm = 1.5;

/// Nadlew grani po stronie wewnętrznej (spawanie jednostronne).
const double kRootReinforcementMm = 1.0;

/// Wypukłość spoiny pachwinowej — dodatek do pola trójkąta.
const double kFilletConvexity = 0.10;

/// Wysokość ściegu graniowego (z ewentualnym ściegiem gorącym) liczona od
/// dna rowka: tyle przekroju kładzie proces grani przy schemacie „grań +
/// wypełnienie".
const double kRootPassHeightMm = 3.0;

/// Grubość obliczeniowa pierwszego ściegu pachwiny przy schemacie
/// „grań + wypełnienie" — reszta przekroju idzie procesem wypełnienia.
const double kFilletRootThroatMm = 3.0;

/// Rodzaj złącza w wycenie.
enum JointKind {
  /// Spoina obwodowa doczołowa rura–rura / rura–kształtka.
  pipeButt('PIPE_BUTT'),

  /// Pachwina na rurze: mufa (SW), kołnierz nasuwany, rura w płycie.
  pipeFillet('PIPE_FILLET'),

  /// Króciec nasadzany (set-on) na rurę główną.
  branch('BRANCH'),

  /// Spoina doczołowa blach — długość w metrach.
  plateButt('PLATE_BUTT'),

  /// Spoina pachwinowa blach / kształtowników — długość w metrach.
  plateFillet('PLATE_FILLET');

  const JointKind(this.code);
  final String code;

  /// Złącze na rurze (liczone w calach-średnicach, z formowaniem grani).
  bool get onPipe => this != plateButt && this != plateFillet;

  /// Spoina pachwinowa (grubość a zamiast ścianki i rowka).
  bool get isFillet => this == pipeFillet || this == plateFillet;

  /// Długość podawana w metrach (blachy), nie z obwodu.
  bool get hasLength => this == plateButt || this == plateFillet;

  static JointKind fromCode(String? code) {
    for (final k in values) {
      if (k.code == code) return k;
    }
    return pipeButt;
  }
}

/// Kształt rowka spoiny doczołowej.
enum GrooveType {
  /// Rowek V (Y z progiem) — spawany z jednej strony.
  v('V'),

  /// Rowek X — spawany z dwóch stron (blachy).
  x('X'),

  /// Bez ukosowania (I) — cienkie ścianki.
  square('I');

  const GrooveType(this.code);
  final String code;

  static GrooveType fromCode(String? code) {
    for (final g in values) {
      if (g.code == code) return g;
    }
    return v;
  }
}

/// Objętości stopiwa jednej spoiny.
class WeldVolumes {
  /// mm³ kładzione procesem grani (przy schemacie jednoprocesowym liczy się
  /// razem z [fillMm3]).
  final double rootMm3;

  /// mm³ wypełnienia i lica.
  final double fillMm3;

  /// Długość spoiny po licu (mm) — do „kosztu na metr".
  final double lengthMm;

  const WeldVolumes({
    required this.rootMm3,
    required this.fillMm3,
    required this.lengthMm,
  });

  double get totalMm3 => rootMm3 + fillMm3;

  static const zero = WeldVolumes(rootMm3: 0, fillMm3: 0, lengthMm: 0);
}

/// Pole rowka jednostronnego V/I do wysokości [h] od strony grani.
double grooveAreaV({
  required double h,
  required double gap,
  required double rootFace,
  required double includedAngleDeg,
}) {
  if (h <= 0) return 0;
  final tanHalf = math.tan(includedAngleDeg / 2 * math.pi / 180);
  final open = math.max(0.0, h - rootFace);
  return gap * h + open * open * tanHalf;
}

/// Pole rowka jednostronnego ½V (faza tylko na jednym elemencie, kąt
/// fazy [bevelDeg]) do wysokości [h].
double grooveAreaHalfV({
  required double h,
  required double gap,
  required double rootFace,
  required double bevelDeg,
}) {
  if (h <= 0) return 0;
  final tanB = math.tan(bevelDeg * math.pi / 180);
  final open = math.max(0.0, h - rootFace);
  return gap * h + 0.5 * open * open * tanB;
}

/// Szerokość rowka V na powierzchni (bez zakładki lica).
double grooveTopWidthV({
  required double t,
  required double gap,
  required double rootFace,
  required double includedAngleDeg,
}) {
  final tanHalf = math.tan(includedAngleDeg / 2 * math.pi / 180);
  return gap + 2 * math.max(0.0, t - rootFace) * tanHalf;
}

/// Pole nadlewu (odcinek paraboli) o szerokości [width] i wysokości
/// [height].
double reinforcementArea(double width, double height) =>
    width <= 0 || height <= 0 ? 0 : 2 / 3 * width * height;

/// Pole pachwiny o grubości obliczeniowej [a] z wypukłością.
double filletArea(double a) => a <= 0 ? 0 : a * a * (1 + kFilletConvexity);

/// Długość linii przenikania króćca o promieniu zewnętrznym [r] z rurą
/// główną o promieniu [bigR] (osie prostopadłe, króciec centralnie).
///
/// Krzywa: x = r·cos φ, y = r·sin φ, z = √(R² − r²·sin² φ). Dla r ≪ R
/// dąży do 2πr; dla r = R wynosi ~1,22·2πr. Gdy rura główna nieznana
/// albo mniejsza od króćca — liczymy jak dla r = R (górna granica), a dla
/// R ≤ 0 — 2πr.
double saddlePerimeter(double r, double bigR) {
  if (r <= 0) return 0;
  if (bigR <= 0) return 2 * math.pi * r;
  final rr = math.min(r, bigR);
  const steps = 720;
  var length = 0.0;
  double z(double phi) {
    final s = math.sin(phi);
    final v = bigR * bigR - rr * rr * s * s;
    return v <= 0 ? 0 : math.sqrt(v);
  }

  var px = rr, py = 0.0, pz = z(0);
  for (var i = 1; i <= steps; i++) {
    final phi = 2 * math.pi * i / steps;
    final x = rr * math.cos(phi), y = rr * math.sin(phi), zz = z(phi);
    final dx = x - px, dy = y - py, dz = zz - pz;
    length += math.sqrt(dx * dx + dy * dy + dz * dz);
    px = x;
    py = y;
    pz = zz;
  }
  return length;
}

/// Spoina obwodowa doczołowa rury (rowek V / I, jednostronnie).
WeldVolumes pipeButtVolumes({
  required double od,
  required double t,
  required double gap,
  required double rootFace,
  required double includedAngleDeg,
  double rootHeight = kRootPassHeightMm,
}) {
  if (od <= 0 || t <= 0 || 2 * t >= od) return WeldVolumes.zero;
  final hr = math.min(t, rootHeight);
  final aRoot = grooveAreaV(
      h: hr, gap: gap, rootFace: rootFace, includedAngleDeg: includedAngleDeg);
  final aAll = grooveAreaV(
      h: t, gap: gap, rootFace: rootFace, includedAngleDeg: includedAngleDeg);
  final aRest = math.max(0.0, aAll - aRoot);
  final capW = grooveTopWidthV(
          t: t,
          gap: gap,
          rootFace: rootFace,
          includedAngleDeg: includedAngleDeg) +
      2 * kCapOverlapMm;
  final aCap = reinforcementArea(capW, kCapHeightMm);
  final aPen = reinforcementArea(gap + 2, kRootReinforcementMm);

  final id = od - 2 * t;
  // Środek ściegu graniowego: ID + hr; reszta rowka — środek ciężkości
  // bliżej powierzchni (trójkąt): 1/3 głębokości od zewnątrz.
  final lRoot = math.pi * (id + hr);
  final lRest = math.pi * (od - 2 * (t - hr) / 3);
  return WeldVolumes(
    rootMm3: aRoot * lRoot + aPen * math.pi * id,
    fillMm3: aRest * lRest + aCap * math.pi * od,
    lengthMm: math.pi * od,
  );
}

/// Grubość obliczeniowa a pachwiny mufy SW dla ścianki rury [wallMm]:
/// ASME B31.3 rys. 328.5.2C — noga Cx ≥ 1,09·t → a ≈ 0,77·t, zaokrąglone
/// w górę do 0,5 mm, min. 3 mm. Jedna reguła dla okna pozycji i importu
/// spoin.
double socketWeldThroatMm(double wallMm) {
  final a = ((0.77 * wallMm) * 2).ceil() / 2;
  return a < 3 ? 3.0 : a;
}

/// Spoina pachwinowa obwodowa na rurze (mufa / kołnierz nasuwany).
WeldVolumes pipeFilletVolumes({
  required double od,
  required double throat,
}) {
  if (od <= 0 || throat <= 0) return WeldVolumes.zero;
  final leg = throat * math.sqrt2;
  final length = math.pi * (od + 2 * leg / 3);
  final rootA = filletArea(math.min(throat, kFilletRootThroatMm));
  final allA = filletArea(throat);
  return WeldVolumes(
    rootMm3: rootA * length,
    fillMm3: math.max(0.0, allA - rootA) * length,
    lengthMm: math.pi * (od + 2 * leg),
  );
}

/// Króciec nasadzany: rowek ½V na króćcu + pachwina przykrywająca.
WeldVolumes branchVolumes({
  required double branchOd,
  required double t,
  required double headerOd,
  required double gap,
  required double rootFace,
  required double bevelDeg,
  double rootHeight = kRootPassHeightMm,
}) {
  if (branchOd <= 0 || t <= 0 || 2 * t >= branchOd) return WeldVolumes.zero;
  final hr = math.min(t, rootHeight);
  final aRoot =
      grooveAreaHalfV(h: hr, gap: gap, rootFace: rootFace, bevelDeg: bevelDeg);
  final aAll =
      grooveAreaHalfV(h: t, gap: gap, rootFace: rootFace, bevelDeg: bevelDeg);
  final tc = math.min(0.7 * t, 6.0);
  final aCover = filletArea(tc);
  final aPen = reinforcementArea(gap + 2, kRootReinforcementMm);
  final perimeter = saddlePerimeter(branchOd / 2, headerOd / 2);
  return WeldVolumes(
    rootMm3: (aRoot + aPen) * perimeter,
    fillMm3: (math.max(0.0, aAll - aRoot) + aCover) * perimeter,
    lengthMm: perimeter,
  );
}

/// Spoina doczołowa blach na długości [lengthMm].
WeldVolumes plateButtVolumes({
  required double t,
  required double lengthMm,
  required GrooveType groove,
  required double gap,
  required double rootFace,
  required double includedAngleDeg,
  double rootHeight = kRootPassHeightMm,
}) {
  if (t <= 0 || lengthMm <= 0) return WeldVolumes.zero;
  final angle = groove == GrooveType.square ? 0.0 : includedAngleDeg;
  if (groove == GrooveType.x) {
    final tanHalf = math.tan(angle / 2 * math.pi / 180);
    final c = math.min(rootFace, t);
    final halfOpen = math.max(0.0, (t - c) / 2);
    final aAll = gap * t + 2 * halfOpen * halfOpen * tanHalf;
    // Strefa grani: ±hr/2 wokół progu w środku grubości.
    final hr = math.min(t, rootHeight);
    final rootOpen = math.max(0.0, hr / 2 - c / 2);
    final aRoot = gap * hr + 2 * rootOpen * rootOpen * tanHalf;
    final capW = gap + 2 * halfOpen * tanHalf + 2 * kCapOverlapMm;
    final aCaps = 2 * reinforcementArea(capW, kCapHeightMm);
    return WeldVolumes(
      rootMm3: aRoot * lengthMm,
      fillMm3: (math.max(0.0, aAll - aRoot) + aCaps) * lengthMm,
      lengthMm: lengthMm,
    );
  }
  final hr = math.min(t, rootHeight);
  final aRoot =
      grooveAreaV(h: hr, gap: gap, rootFace: rootFace, includedAngleDeg: angle);
  final aAll =
      grooveAreaV(h: t, gap: gap, rootFace: rootFace, includedAngleDeg: angle);
  final capW = grooveTopWidthV(
          t: t, gap: gap, rootFace: rootFace, includedAngleDeg: angle) +
      2 * kCapOverlapMm;
  final aCap = reinforcementArea(capW, kCapHeightMm);
  final aPen = reinforcementArea(gap + 2, kRootReinforcementMm);
  return WeldVolumes(
    rootMm3: (aRoot + aPen) * lengthMm,
    fillMm3: (math.max(0.0, aAll - aRoot) + aCap) * lengthMm,
    lengthMm: lengthMm,
  );
}

/// Spoina pachwinowa blach na długości [lengthMm].
WeldVolumes plateFilletVolumes({
  required double throat,
  required double lengthMm,
}) {
  if (throat <= 0 || lengthMm <= 0) return WeldVolumes.zero;
  final rootA = filletArea(math.min(throat, kFilletRootThroatMm));
  final allA = filletArea(throat);
  return WeldVolumes(
    rootMm3: rootA * lengthMm,
    fillMm3: math.max(0.0, allA - rootA) * lengthMm,
    lengthMm: lengthMm,
  );
}
