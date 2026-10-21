// Pure rolling-offset geometry behind "Rolling Offset"
// (lib/screens/rolling_offset_screen.dart). No Flutter imports — the screen
// and the voice assistant both get their numbers from here; pinned by
// test/domain/fitter/rolling_offset_test.dart.
//
// Rolling offset formulas:
//   True Offset = √(Rise² + Spread²)
//   Travel      = True Offset / sin(θ)   [θ = elbow angle]
//   Run         = True Offset / tan(θ)   = √(Travel² − True Offset²)
//   Multiplier  = 1 / sin(θ)
//
// Verification (Rise=300, Spread=400, θ=45°):
//   True Offset = √(90000+160000) = √250000 = 500mm
//   Multiplier  = 1/sin(45°) = √2 ≈ 1.4142
//   Travel      = 500 × 1.4142 = 707.1mm
//   Run         = 500/tan(45°) = 500mm

import 'dart:math' as math;

import '../../services/takeout_catalog.dart';

/// Roll of the offset plane (= how far the elbow is turned) measured from
/// the vertical, in degrees: atan(Spread / Rise). Rise is the vertical and
/// Spread the lateral offset as entered on this screen; the roll from the
/// horizontal is 90° minus this value.
double rollFromVerticalDeg(double rise, double spread) =>
    math.atan2(spread, rise) * 180.0 / math.pi;

/// Pipe to cut between the two offset elbows:
/// Travel − 2 × take-out − 2 × weld gap.
double rollingCutLengthMm({
  required double travelMm,
  required double takeoutMm,
  double gapMm = 0,
}) =>
    travelMm - 2.0 * takeoutMm - 2.0 * gapMm;

/// Above this multiplier (a very shallow elbow: tiny sin θ) the screen warns
/// the fitter to re-check the angle — Travel grows huge.
const double kRollingOffsetMultiplierWarning = 10.0;

/// Elbow angles the calculation accepts: > 5° and < 89°, or exactly 90°.
/// Below 5° sin(θ) collapses and the multiplier explodes; above 89° (except
/// 90°, where Run = 0 and Multiplier = 1) tan(θ) blows up.
bool rollingOffsetAngleValid(double angleDeg) =>
    angleDeg.isFinite && angleDeg > 5 && (angleDeg < 89 || angleDeg == 90);

class RollingOffsetResult {
  const RollingOffsetResult({
    required this.riseMm,
    required this.spreadMm,
    required this.angleDeg,
    required this.trueOffsetMm,
    required this.multiplier,
    required this.travelMm,
    required this.runMm,
    required this.rollFromVerticalDeg,
    required this.rollFromHorizontalDeg,
  });

  final double riseMm;
  final double spreadMm;

  /// Elbow angle θ, degrees.
  final double angleDeg;

  /// √(Rise² + Spread²), mm.
  final double trueOffsetMm;

  /// 1 / sin θ.
  final double multiplier;

  /// Centreline distance between the elbow intersection points, mm. Not a
  /// cut length — see [rollingOffsetCut].
  final double travelMm;

  /// Projection along the original pipe direction, mm (exactly 0 at 90°).
  final double runMm;

  /// Elbow roll from the vertical: atan(Spread / Rise), degrees.
  final double rollFromVerticalDeg;

  /// Roll from the horizontal: 90° − [rollFromVerticalDeg], degrees.
  final double rollFromHorizontalDeg;

  /// Multiplier above [kRollingOffsetMultiplierWarning]: check the angle.
  bool get multiplierWarning => multiplier > kRollingOffsetMultiplierWarning;
}

/// Rolling offset for [riseMm] (vertical) and [spreadMm] (lateral) with
/// elbows of [angleDeg]. `null` unless rise and spread are finite and > 0,
/// the angle passes [rollingOffsetAngleValid] and every result is finite.
RollingOffsetResult? rollingOffset({
  required double riseMm,
  required double spreadMm,
  required double angleDeg,
}) {
  if (!riseMm.isFinite || !spreadMm.isFinite || riseMm <= 0 || spreadMm <= 0) {
    return null;
  }
  if (!rollingOffsetAngleValid(angleDeg)) return null;

  final angleRad = angleDeg * math.pi / 180.0;
  final trueOffset = math.sqrt(riseMm * riseMm + spreadMm * spreadMm);
  final multiplier = 1.0 / math.sin(angleRad);
  final travel = trueOffset * multiplier;
  // 90° edge case: tan(π/2) is mathematically infinite, but math.tan
  // returns a huge finite float. Pin Run to 0.0 explicitly so the saw
  // gets a clean reading.
  final run = angleDeg == 90 ? 0.0 : trueOffset / math.tan(angleRad);
  if (![trueOffset, multiplier, travel, run].every((v) => v.isFinite)) {
    return null;
  }
  final rollV = rollFromVerticalDeg(riseMm, spreadMm);
  return RollingOffsetResult(
    riseMm: riseMm,
    spreadMm: spreadMm,
    angleDeg: angleDeg,
    trueOffsetMm: trueOffset,
    multiplier: multiplier,
    travelMm: travel,
    runMm: run,
    rollFromVerticalDeg: rollV,
    rollFromHorizontalDeg: 90.0 - rollV,
  );
}

/// Cut length between two ASME B16.9 long-radius elbows.
class RollingOffsetCut {
  const RollingOffsetCut({
    required this.takeout,
    required this.gapMm,
    required this.cutMm,
  });

  /// Take-out T of one elbow at the offset angle, with its table source.
  final ElbowTakeoutResult takeout;
  final double gapMm;

  /// Travel − 2·T − 2·gap, mm. May be ≤ 0 — see [elbowsOverlap].
  final double cutMm;

  /// The elbows overlap: the offset is too small for this DN and angle.
  bool get elbowsOverlap => cutMm <= 0;
}

/// Cut length for a rolling offset of [travelMm] built from two ASME B16.9 LR
/// elbows of nominal size [dn] bent through [angleDeg], with weld [gapMm] at
/// each end. `null` when [travelMm] is not finite and > 0, when B16.9 has no
/// take-out for that DN / angle, or when the gap is not finite or negative.
RollingOffsetCut? rollingOffsetCut({
  required double travelMm,
  required double angleDeg,
  required int dn,
  double gapMm = 0,
}) {
  if (!travelMm.isFinite || travelMm <= 0) return null;
  if (!gapMm.isFinite || gapMm < 0) return null;
  final t = b169ElbowTakeout(
      dn: dn, type: ElbowRadiusType.long15D, angleDeg: angleDeg);
  if (t == null) return null;
  return RollingOffsetCut(
    takeout: t,
    gapMm: gapMm,
    cutMm:
        rollingCutLengthMm(travelMm: travelMm, takeoutMm: t.mm, gapMm: gapMm),
  );
}

/// Complete assistant/native input, validated before any controller changes.
class RollingOffsetInput {
  RollingOffsetInput._(this.fields, this.result, this.cut);
  final Map<String, Object?> fields;
  final RollingOffsetResult result;
  final RollingOffsetCut? cut;
  static const keys = {'rise_mm', 'spread_mm', 'angle_deg', 'dn', 'gap_mm'};
  factory RollingOffsetInput.fromFields(Map<String, Object?> fields) {
    if (fields.keys.any((k) => !keys.contains(k))) {
      throw const FormatException('fields');
    }
    double positive(String key) {
      final n = fields[key];
      if (n is! num || !n.isFinite || n <= 0) throw FormatException(key);
      return n.toDouble();
    }

    final rise = positive('rise_mm'),
        spread = positive('spread_mm'),
        angle = positive('angle_deg');
    if (!rollingOffsetAngleValid(angle)) {
      throw const FormatException('angle_deg');
    }
    final r = rollingOffset(riseMm: rise, spreadMm: spread, angleDeg: angle);
    if (r == null) throw const FormatException('geometry');
    final dn = fields['dn'], gap = fields['gap_mm'];
    if (dn != null && (dn is! int || dn <= 0)) {
      throw const FormatException('dn');
    }
    if (gap != null && (gap is! num || !gap.isFinite || gap < 0)) {
      throw const FormatException('gap_mm');
    }
    RollingOffsetCut? cut;
    if (dn != null) {
      if (gap is! num) throw const FormatException('gap_mm');
      cut = rollingOffsetCut(
          travelMm: r.travelMm,
          angleDeg: angle,
          dn: dn as int,
          gapMm: gap.toDouble());
      if (cut == null) throw const FormatException('dn');
      if (!cut.cutMm.isFinite || cut.elbowsOverlap) {
        throw const FormatException('geometry');
      }
    }
    return RollingOffsetInput._(
        Map.unmodifiable({
          'rise_mm': rise,
          'spread_mm': spread,
          'angle_deg': angle,
          if (fields.containsKey('dn')) 'dn': dn,
          if (fields.containsKey('gap_mm'))
            'gap_mm': gap is num ? gap.toDouble() : null,
        }),
        r,
        cut);
  }
}
