import 'dart:math' as math;

/// Point on the outside-surface intersection, unrolled onto the branch.
class SaddleCutPoint {
  final double phiDeg;

  /// Arc length along the outside circumference, NOT a straight chord.
  final double xMm;

  /// Axial cutback from the plane through the longest tips towards the body.
  final double depthMm;
  const SaddleCutPoint(this.phiDeg, this.xMm, this.depthMm);
}

/// Exact centred cylinder intersection. No wall, bevel, gap or allowances.
/// Main axis X; branch unit u=(cos a,0,sin a), body along +u.
/// Radial basis e1=(sin a,0,-cos a), e2=(0,1,0); phi=0 lies in the axes' plane.
/// p=t*u+r*cos(phi)*e1+r*sin(phi)*e2, and header y²+z²=R² imply
/// t=(sqrt(R²-r²*sin²(phi))+r*cos(a)*cos(phi))/sin(a).
/// Report t-min(t), using the analytic minimum, not the sampled minimum.
class SaddleGeometry {
  final double headerOdMm;
  final double branchOdMm;
  final double angleDeg;
  late final double _rh;
  late final double _rb;
  late final double _sinA;
  late final double _cosA;
  late final double tipPlaneMm;
  late final double minimumAngleDeg;
  late final double maxDepthMm;
  late final double stripLengthMm;

  SaddleGeometry(
      {required this.headerOdMm,
      required this.branchOdMm,
      required this.angleDeg}) {
    if (!headerOdMm.isFinite ||
        !branchOdMm.isFinite ||
        headerOdMm <= 0 ||
        branchOdMm <= 0 ||
        headerOdMm > 2000 ||
        branchOdMm > 2000) {
      throw ArgumentError('OD must be finite, above 0 and at most 2000 mm');
    }
    if (branchOdMm > headerOdMm) {
      throw ArgumentError('Branch OD must be <= header OD');
    }
    if (!angleDeg.isFinite || angleDeg < 15 || angleDeg > 90) {
      throw ArgumentError('Angle must be in [15, 90] degrees');
    }
    _rh = headerOdMm / 2;
    _rb = branchOdMm / 2;
    _sinA = angleDeg == 90 ? 1 : math.sin(angleDeg * math.pi / 180);
    _cosA = angleDeg == 90 ? 0 : math.cos(angleDeg * math.pi / 180);
    final radialDifference = math.sqrt((_rh - _rb) * (_rh + _rb));
    if (_rh * _cosA <= _rb) {
      tipPlaneMm = radialDifference;
      final cosPhi =
          (-radialDifference * _cosA / (_rb * _sinA)).clamp(-1.0, 1.0);
      minimumAngleDeg = math.acos(cosPhi) * 180 / math.pi;
    } else {
      tipPlaneMm = (_rh - _rb * _cosA) / _sinA;
      minimumAngleDeg = 180;
    }
    maxDepthMm = (_rh + _rb * _cosA) / _sinA - tipPlaneMm;
    stripLengthMm = math.pi * branchOdMm;
  }

  SaddleCutPoint pointAt(double phiDeg) {
    if (!phiDeg.isFinite || phiDeg < 0 || phiDeg > 360) {
      throw ArgumentError.value(phiDeg, 'phiDeg', 'Must be in [0, 360]');
    }
    final phi = (phiDeg == 360 ? 0 : phiDeg) * math.pi / 180;
    final transverse = _rb * math.sin(phi);
    final height = math
        .sqrt(math.max(0, (_rh - transverse.abs()) * (_rh + transverse.abs())));
    final axial = (height + _rb * _cosA * math.cos(phi)) / _sinA;
    return SaddleCutPoint(phiDeg, stripLengthMm * phiDeg / 360,
        (axial - tipPlaneMm).clamp(0.0, maxDepthMm));
  }

  List<SaddleCutPoint> sample(int count) {
    if (count < 25 || count > 3601) {
      throw ArgumentError.value(count, 'pointsCount', 'Must be in [25, 3601]');
    }
    return List.unmodifiable(
        List.generate(count, (i) => pointAt(i * 360 / (count - 1))));
  }

  /// Print polyline, with exact page-boundary samples and refined curvature.
  /// Quarter/midpoint deviations from each segment must be <=0.02 mm.
  List<SaddleCutPoint> profileBetween(double startMm, double endMm) {
    if (!startMm.isFinite ||
        !endMm.isFinite ||
        startMm < 0 ||
        endMm > stripLengthMm ||
        startMm >= endMm) {
      throw ArgumentError('Invalid profile interval');
    }
    SaddleCutPoint atX(double x) {
      final p = pointAt((x / stripLengthMm * 360).clamp(0.0, 360.0));
      return SaddleCutPoint(p.phiDeg, x, p.depthMm);
    }

    final knots = <double>{startMm, endMm};
    for (final angle in [
      for (var i = 0; i <= 72; i++) i * 5.0,
      minimumAngleDeg,
      360 - minimumAngleDeg
    ]) {
      final x = stripLengthMm * angle / 360;
      if (x > startMm && x < endMm) knots.add(x);
    }
    final ordered = knots.toList()..sort();
    final result = <SaddleCutPoint>[atX(startMm)];
    void refine(SaddleCutPoint a, SaddleCutPoint b, int level) {
      var error = 0.0;
      for (final fraction in [.25, .5, .75]) {
        final actual = atX(a.xMm + (b.xMm - a.xMm) * fraction);
        final linear = a.depthMm + (b.depthMm - a.depthMm) * fraction;
        error = math.max(error, (actual.depthMm - linear).abs());
      }
      if (error > .02) {
        if (level >= 20) {
          throw StateError('Cannot resolve print contour accurately');
        }
        final mid = atX((a.xMm + b.xMm) / 2);
        refine(a, mid, level + 1);
        refine(mid, b, level + 1);
      } else {
        result.add(b);
      }
    }

    for (var i = 1; i < ordered.length; i++) {
      refine(atX(ordered[i - 1]), atX(ordered[i]), 0);
    }
    return List.unmodifiable(result);
  }
}
