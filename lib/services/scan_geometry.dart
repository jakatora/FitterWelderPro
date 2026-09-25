/// 3D geometry of a scanned isometric: run directions, offsets and the
/// closure of the dimension chain.
///
/// An isometric draws every run along one of three axes — east/west,
/// north/south, up/down — and a run that is not along an axis (an offset,
/// a rolling offset) is dimensioned by its projections on a hatched
/// triangle. This file turns what the model read ("E", `{"E": 500, "N":
/// 300, "UP": 400}`) into vectors, so the planner can:
///
///   * tell the straight-through run of a tee from its branch by direction,
///   * derive the true (skew) length of an offset from its projections —
///     arithmetic on printed numbers, never a guess — and flag a printed
///     skew length that disagrees with them,
///   * check the bend angle of every elbow against the directions of its two
///     runs (a 45° elbow in a 38° offset takes the wrong take-out),
///   * check that the chain of run dimensions closes against the overall
///     dimensions and elevation marks of the drawing.
///
/// Pure Dart, no Flutter. Axis convention: +X = east, +Y = north, +Z = up.
library;

import 'dart:math' as math;

/// Tolerance of a closure / projection check, mm. Drawings round to the
/// millimetre and a chain of five dimensions can drift by a few.
const double kClosureToleranceMm = 3.0;

/// Tolerance of an elbow angle check, degrees.
const double kAngleToleranceDeg = 1.0;

class Vec3 {
  final double x;
  final double y;
  final double z;
  const Vec3(this.x, this.y, this.z);

  static const Vec3 zero = Vec3(0, 0, 0);

  double get length => math.sqrt(x * x + y * y + z * z);

  Vec3 operator +(Vec3 o) => Vec3(x + o.x, y + o.y, z + o.z);
  Vec3 operator -(Vec3 o) => Vec3(x - o.x, y - o.y, z - o.z);
  Vec3 operator *(double k) => Vec3(x * k, y * k, z * k);
  Vec3 operator -() => Vec3(-x, -y, -z);

  double dot(Vec3 o) => x * o.x + y * o.y + z * o.z;

  /// Unit vector, or null for a zero vector.
  Vec3? get unit {
    final l = length;
    if (!l.isFinite || l < 1e-9) return null;
    return Vec3(x / l, y / l, z / l);
  }

  /// Whether the vector lies along one of the three drawing axes.
  bool get isAxial {
    final u = unit;
    if (u == null) return false;
    const eps = 1e-6;
    final nonZero = [u.x, u.y, u.z].where((c) => c.abs() > eps).length;
    return nonZero == 1;
  }

  /// Component along an axis word (`E`, `N`, `UP`, `X`…), or null when the
  /// word is not an axis.
  double? along(String axis) {
    final a = axisVector(axis);
    if (a == null) return null;
    return dot(a);
  }

  @override
  String toString() =>
      'Vec3(${x.toStringAsFixed(1)}, ${y.toStringAsFixed(1)}, ${z.toStringAsFixed(1)})';
}

/// Unit vector of an axis word as isometrics print it, or null.
Vec3? axisVector(String token) {
  final t = token.trim().toUpperCase().replaceAll(' ', '');
  switch (t) {
    case 'E':
    case 'EAST':
    case '+X':
    case 'X':
    case 'WSCHOD':
      return const Vec3(1, 0, 0);
    case 'W':
    case 'WEST':
    case '-X':
    case 'ZACHOD':
      return const Vec3(-1, 0, 0);
    case 'N':
    case 'NORTH':
    case '+Y':
    case 'Y':
    case 'PN':
      return const Vec3(0, 1, 0);
    case 'S':
    case 'SOUTH':
    case '-Y':
    case 'PD':
      return const Vec3(0, -1, 0);
    case 'UP':
    case 'U':
    case '+Z':
    case 'Z':
    case 'GORA':
    case 'GÓRA':
      return const Vec3(0, 0, 1);
    case 'DOWN':
    case 'D':
    case 'DN':
    case '-Z':
    case 'DOL':
    case 'DÓŁ':
      return const Vec3(0, 0, -1);
  }
  return null;
}

/// Unit direction of a run from what the model returned: an axis word or a
/// `{x, y, z}` map. Null when there is nothing usable.
Vec3? directionVector(Object? direction) {
  if (direction is String) return axisVector(direction);
  if (direction is Map) {
    double c(String k) {
      final v = direction[k];
      return v is num ? v.toDouble() : 0.0;
    }

    return Vec3(c('x'), c('y'), c('z')).unit;
  }
  return null;
}

/// The run as a vector from its projections (`{"E": 500, "N": 300}`), or
/// null when there are none or one of the keys is not an axis word — a
/// projection we cannot place is not silently dropped from the sum.
Vec3? projectionVector(Map<String, double> projections) {
  if (projections.isEmpty) return null;
  var v = Vec3.zero;
  for (final e in projections.entries) {
    final a = axisVector(e.key);
    if (a == null || !e.value.isFinite) return null;
    v = v + a * e.value;
  }
  return v.length < 1e-9 ? null : v;
}

/// True length of an offset from its projections, rounded to 0.1 mm — the
/// resolution a fitter can mark and the builder's parser reads back.
double? skewLengthMm(Map<String, double> projections) {
  final v = projectionVector(projections);
  if (v == null) return null;
  return (v.length * 10).roundToDouble() / 10;
}

/// "√(500² + 300² + 400²) = 707.1" — the arithmetic behind [skewLengthMm],
/// shown next to the derived number.
String skewFormula(Map<String, double> projections) {
  String n(double v) =>
      v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(1);
  final parts = projections.values.map((v) => '${n(v.abs())}²').join(' + ');
  final len = skewLengthMm(projections);
  return '√($parts) = ${len == null ? '?' : n(len)}';
}

/// Bend angle in degrees between a run coming INTO a joint along [inDir]
/// and the run leaving it along [outDir] — 0 for straight through, 90 for a
/// square turn.
double bendAngleDeg(Vec3 inDir, Vec3 outDir) {
  final a = inDir.unit;
  final b = outDir.unit;
  if (a == null || b == null) return double.nan;
  final c = a.dot(b).clamp(-1.0, 1.0);
  return math.acos(c) * 180 / math.pi;
}

/// Parses an elevation mark as printed, to millimetres. Accepts only forms
/// that are unambiguous:
///   * metres with exactly three decimals (`EL +3.250`, `EL 102.450`,
///     `EL. -0.500`) — the metric isometric convention;
///   * whole millimetres of at least three digits (`EL 3250`);
///   * feet-inches (`EL 10'-6"`).
/// Anything else (`EL 3.25`, `EL 12`) returns null — the closure check then
/// skips the mark instead of guessing its unit.
double? parseElevationMm(String raw) {
  var t = raw.toUpperCase().replaceAll(',', '.').trim();
  t = t.replaceFirst(RegExp(r'^(EL|ELEV|RZ|H)\.?\s*[:=]?\s*'), '');
  t = t.replaceAll(' ', '');
  final ftIn = RegExp(r"^([+-]?)(\d+)'-?(\d+(?:\.\d+)?)?(?:\x22)?$").firstMatch(t);
  if (ftIn != null) {
    final sign = ftIn.group(1) == '-' ? -1 : 1;
    final ft = double.parse(ftIn.group(2)!);
    final inch = double.tryParse(ftIn.group(3) ?? '0') ?? 0;
    return sign * (ft * 304.8 + inch * 25.4);
  }
  final metres = RegExp(r'^([+-]?\d+\.\d{3})$').firstMatch(t);
  if (metres != null) return double.parse(metres.group(1)!) * 1000;
  final mm = RegExp(r'^([+-]?\d{3,})$').firstMatch(t);
  if (mm != null) return double.parse(mm.group(1)!);
  return null;
}
