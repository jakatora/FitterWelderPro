import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';

import 'package:cut_list_app/services/saddle_template.dart';

/// Index of the point sitting at [deg] degrees around the branch when the
/// template is built with the default 73 points (one point every 5°).
int _idx(int deg) => deg ~/ 5;

/// Independent re-implementation of the documented saddle formula, used as the
/// oracle for the tests. Returns the RAW (unshifted) depth at [phiRad]:
///
///   d(φ)      = R_h − √(R_h² − R_b²·sin²φ)                        for α = 90°
///   d(φ, α)   = (R_h − √(R_h² − R_b²·sin²φ))/sin α + R_b·cos α·cos φ  for α < 90°
///
/// All lengths in millimetres.
double _rawDepthMm({
  required double headerOdMm,
  required double branchOdMm,
  required double angleDeg,
  required double phiRad,
}) {
  final rh = headerOdMm / 2.0;
  final rb = branchOdMm / 2.0;
  final angleRad = angleDeg * math.pi / 180.0;
  final sinPhi = math.sin(phiRad);
  final under = rh * rh - rb * rb * sinPhi * sinPhi;
  final z = under > 0 ? math.sqrt(under) : 0.0;
  if (angleDeg >= 90) return rh - z;
  return (rh - z) / math.sin(angleRad) +
      rb * math.cos(angleRad) * math.cos(phiRad);
}

/// Expected depth profile: the raw profile shifted so that its shallowest
/// point becomes 0 mm (baseline shift). The SHAPE must be identical to the raw
/// profile — only the reference level moves.
List<double> _expectedProfileMm({
  required double headerOdMm,
  required double branchOdMm,
  required double angleDeg,
  int pointsCount = 73,
}) {
  final raw = <double>[];
  for (int i = 0; i < pointsCount; i++) {
    final phi = (i / (pointsCount - 1)) * 2 * math.pi;
    raw.add(_rawDepthMm(
      headerOdMm: headerOdMm,
      branchOdMm: branchOdMm,
      angleDeg: angleDeg,
      phiRad: phi,
    ));
  }
  final minRaw = raw.reduce(math.min);
  return raw.map((d) => d - minRaw).toList();
}

void main() {
  group('SaddleTemplate · 90° branch (control case — must not change)', () {
    // DN100 branch on a DN200 header: R_h = 100 mm, R_b = 50 mm.
    final tpl = SaddleTemplate(headerOdMm: 200, branchOdMm: 100, angleDeg: 90);

    test('grid: 73 points, 5° apart, first at 0° and last at 360°', () {
      expect(tpl.points.length, 73);
      expect(tpl.points.first.phiDeg, closeTo(0, 1e-12));
      expect(tpl.points.last.phiDeg, closeTo(360, 1e-9));
      expect(tpl.points[_idx(90)].phiDeg, closeTo(90, 1e-9));
    });

    test('golden depths (hand-computed from d = R_h − √(R_h² − R_b²·sin²φ))',
        () {
      // Literal values are the regression guard: the 90° template is the one
      // fitters already print, so it must survive the baseline-shift rework.
      expect(tpl.points[_idx(0)].depthMm, 0.0);
      expect(tpl.points[_idx(30)].depthMm, closeTo(3.1754163448145789, 1e-12));
      expect(tpl.points[_idx(45)].depthMm, closeTo(6.4585653306514672, 1e-12));
      expect(tpl.points[_idx(60)].depthMm, closeTo(9.8612181134002697, 1e-12));
      expect(tpl.points[_idx(90)].depthMm, closeTo(13.397459621556138, 1e-12));
      expect(tpl.points[_idx(180)].depthMm, 0.0);
      expect(tpl.points[_idx(270)].depthMm, closeTo(13.397459621556138, 1e-9));
      expect(tpl.points.last.depthMm, closeTo(0.0, 1e-9));
    });

    test('every point matches the closed-form formula (no shift at 90°)', () {
      final expected = _expectedProfileMm(
        headerOdMm: 200,
        branchOdMm: 100,
        angleDeg: 90,
      );
      for (int i = 0; i < tpl.points.length; i++) {
        expect(tpl.points[i].depthMm, closeTo(expected[i], 1e-9),
            reason: 'point $i (${tpl.points[i].phiDeg}°)');
      }
    });

    test('maxDepthMm is the depth at the 90°/270° flanks', () {
      expect(tpl.maxDepthMm, closeTo(13.397459621556138, 1e-12));
    });

    test('unrolled x follows R_b·φ and strip length is π·branch OD', () {
      expect(tpl.points[_idx(90)].xMm, closeTo(78.53981633974483, 1e-9));
      expect(tpl.points.last.xMm, closeTo(314.1592653589793, 1e-9));
      expect(tpl.stripLengthMm, closeTo(314.1592653589793, 1e-9));
    });
  });

  group('SaddleTemplate · 45° branch (the flattened-profile bug)', () {
    // DN100 on DN200 @45°: the raw formula goes negative between 120° and 240°.
    final tpl = SaddleTemplate(headerOdMm: 200, branchOdMm: 100, angleDeg: 45);

    test('no depth is negative', () {
      for (final p in tpl.points) {
        expect(p.depthMm, greaterThanOrEqualTo(0.0),
            reason: 'point at ${p.phiDeg}°');
      }
    });

    test('only the natural crown sits at 0 mm — no flat run of zeros', () {
      // Old behaviour clamped each point separately, so 25 consecutive points
      // (120°…240°) came out as exactly 0 → a straight line on the template.
      final zeroIdx = <int>[];
      for (int i = 0; i < tpl.points.length; i++) {
        if (tpl.points[i].depthMm < 1e-9) zeroIdx.add(i);
      }
      expect(zeroIdx, [_idx(180)],
          reason: 'the profile minimum must be a single point at 180°');

      for (int i = 0; i < tpl.points.length - 1; i++) {
        final flat = tpl.points[i].depthMm < 1e-9 &&
            tpl.points[i + 1].depthMm < 1e-9;
        expect(flat, isFalse,
            reason: 'points $i and ${i + 1} are both 0 mm → flat template');
      }
    });

    test('the once-clamped 120°…240° span is still a curve', () {
      // Strictly monotonic down to the crown and back up again: a clamped
      // region would show zero-length steps here.
      for (int i = _idx(120); i < _idx(180); i++) {
        expect(tpl.points[i].depthMm, greaterThan(tpl.points[i + 1].depthMm),
            reason: 'flat step between ${tpl.points[i].phiDeg}° and '
                '${tpl.points[i + 1].phiDeg}°');
      }
      for (int i = _idx(180); i < _idx(240); i++) {
        expect(tpl.points[i + 1].depthMm, greaterThan(tpl.points[i].depthMm),
            reason: 'flat step between ${tpl.points[i].phiDeg}° and '
                '${tpl.points[i + 1].phiDeg}°');
      }
    });

    test('shape is the raw curve moved by −min, not clipped', () {
      final expected = _expectedProfileMm(
        headerOdMm: 200,
        branchOdMm: 100,
        angleDeg: 45,
      );
      for (int i = 0; i < tpl.points.length; i++) {
        expect(tpl.points[i].depthMm, closeTo(expected[i], 1e-9),
            reason: 'point $i (${tpl.points[i].phiDeg}°)');
      }
      // Peak-to-peak of the raw curve = 2·R_b·cos α = 70.7107 mm.
      expect(tpl.points[_idx(0)].depthMm, closeTo(70.710678118654755, 1e-9));
      expect(tpl.maxDepthMm, closeTo(70.710678118654755, 1e-9));
    });

    test('differences between neighbouring points survive the shift', () {
      // A baseline shift cannot change any Δdepth; clamping did.
      final expected = _expectedProfileMm(
        headerOdMm: 200,
        branchOdMm: 100,
        angleDeg: 45,
      );
      for (int i = 0; i < tpl.points.length - 1; i++) {
        final got = tpl.points[i + 1].depthMm - tpl.points[i].depthMm;
        final want = expected[i + 1] - expected[i];
        expect(got, closeTo(want, 1e-9), reason: 'step $i → ${i + 1}');
      }
    });
  });

  group('SaddleTemplate · profile symmetry about the 180° axis', () {
    for (final angle in <double>[90, 60, 45, 30]) {
      test('${angle.toStringAsFixed(0)}° profile is mirror-symmetric', () {
        final tpl =
            SaddleTemplate(headerOdMm: 200, branchOdMm: 100, angleDeg: angle);
        final last = tpl.points.length - 1;
        for (int i = 0; i <= last ~/ 2; i++) {
          expect(tpl.points[i].depthMm, closeTo(tpl.points[last - i].depthMm, 1e-9),
              reason: '${tpl.points[i].phiDeg}° vs '
                  '${tpl.points[last - i].phiDeg}°');
        }
      });
    }
  });

  group('SaddleTemplate · edge case: branch OD == header OD', () {
    test('90°, equal diameters → max depth equals the pipe radius', () {
      final tpl =
          SaddleTemplate(headerOdMm: 200, branchOdMm: 200, angleDeg: 90);
      // At φ = 90° the two equal cylinders touch on the header axis, so the
      // fish-mouth reaches exactly R = 100 mm deep.
      expect(tpl.points[_idx(90)].depthMm, closeTo(100.0, 1e-9));
      expect(tpl.points[_idx(270)].depthMm, closeTo(100.0, 1e-9));
      expect(tpl.maxDepthMm, closeTo(100.0, 1e-9));
      expect(tpl.points[_idx(0)].depthMm, 0.0);
      expect(tpl.points[_idx(180)].depthMm, 0.0);
      // The two zeros (0°/360° and 180°) are the real crowns, never adjacent.
      for (int i = 0; i < tpl.points.length - 1; i++) {
        expect(tpl.points[i].depthMm < 1e-9 && tpl.points[i + 1].depthMm < 1e-9,
            isFalse,
            reason: 'flat pair at index $i');
      }
    });

    test('60°, equal diameters → finite, non-negative, shifted profile', () {
      final tpl =
          SaddleTemplate(headerOdMm: 200, branchOdMm: 200, angleDeg: 60);
      final expected = _expectedProfileMm(
        headerOdMm: 200,
        branchOdMm: 200,
        angleDeg: 60,
      );
      for (int i = 0; i < tpl.points.length; i++) {
        expect(tpl.points[i].depthMm.isFinite, isTrue);
        expect(tpl.points[i].depthMm, greaterThanOrEqualTo(0.0));
        expect(tpl.points[i].depthMm, closeTo(expected[i], 1e-9),
            reason: 'point $i (${tpl.points[i].phiDeg}°)');
      }
      expect(tpl.points[_idx(180)].depthMm, 0.0);
      expect(tpl.maxDepthMm, closeTo(165.47005383792517, 1e-9));
    });

    test('branch larger than header is rejected', () {
      expect(
        () => SaddleTemplate(headerOdMm: 200, branchOdMm: 219.1, angleDeg: 90),
        throwsArgumentError,
      );
    });

    test('angle outside [15°, 90°] is rejected', () {
      expect(
        () => SaddleTemplate(headerOdMm: 200, branchOdMm: 100, angleDeg: 10),
        throwsArgumentError,
      );
      expect(
        () => SaddleTemplate(headerOdMm: 200, branchOdMm: 100, angleDeg: 91),
        throwsArgumentError,
      );
    });
  });
}
