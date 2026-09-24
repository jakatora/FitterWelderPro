import 'dart:math' as math;
import 'package:flutter_test/flutter_test.dart';
import 'package:cut_list_app/services/saddle_template.dart';

void main() {
  test('default grid includes both wrap endpoints without changing arc length',
      () {
    final t = SaddleTemplate(headerOdMm: 200, branchOdMm: 100, angleDeg: 90);
    expect(t.points.length, 73);
    expect(t.points[18].phiDeg, closeTo(90, 1e-10));
    expect(t.points[18].xMm, closeTo(78.53981633974483, 1e-9));
    expect(t.points.last.phiDeg, closeTo(360, 1e-9));
    expect(t.stripLengthMm, closeTo(314.1592653589793, 1e-9));
    expect(t.points.last.depthMm, closeTo(t.points.first.depthMm, 1e-9));
    expect(() => t.points.clear(), throwsUnsupportedError);
  });

  // Independently derived physical baseline fixtures, not a mirrored formula.
  for (final fixture in [
    (45.0, 91.42135623730951, 100.0),
    (60.0, 86.60254037844386, 57.735026918962575),
    (75.0, 86.60254037844386, 30.322537283320),
    (90.0, 86.60254037844386, 13.397459621556138),
  ]) {
    test('points at angle ${fixture.$1} lie on the header surface', () {
      final t = SaddleTemplate(
          headerOdMm: 200, branchOdMm: 100, angleDeg: fixture.$1);
      final alpha = fixture.$1 * math.pi / 180;
      expect(t.tipPlaneMm, closeTo(fixture.$2, 1e-9));
      expect(t.maxDepthMm, closeTo(fixture.$3, 1e-6));
      for (final p in t.points) {
        final phi = p.phiDeg * math.pi / 180;
        final axial = fixture.$2 + p.depthMm;
        final y = 50 * math.sin(phi);
        final z =
            axial * math.sin(alpha) - 50 * math.cos(phi) * math.cos(alpha);
        expect(z, greaterThanOrEqualTo(-1e-9));
        expect(y * y + z * z, closeTo(10000, 1e-6));
        expect(p.depthMm, inInclusiveRange(0, t.maxDepthMm));
      }
    });
  }

  test('75 degree baseline uses the continuous minimum between grid points',
      () {
    final t = SaddleTemplate(headerOdMm: 200, branchOdMm: 100, angleDeg: 75);
    expect(t.minimumAngleDeg, closeTo(117.652096, 1e-5));
    expect(t.pointAt(t.minimumAngleDeg).depthMm, closeTo(0, 1e-9));
    expect(t.pointAt(120).depthMm, closeTo(.017264, 1e-6));
    expect(t.points.map((p) => p.depthMm).reduce(math.min), greaterThan(0));
    final coarse = SaddleTemplate(
        headerOdMm: 200, branchOdMm: 100, angleDeg: 75, pointsCount: 26);
    expect(coarse.tipPlaneMm, closeTo(t.tipPlaneMm, 1e-12));
    expect(coarse.maxDepthMm, closeTo(t.maxDepthMm, 1e-12));
  });

  test('45 degree branch retains a curved contour around its longest tip', () {
    final t = SaddleTemplate(headerOdMm: 200, branchOdMm: 100, angleDeg: 45);
    expect(t.pointAt(180).depthMm, closeTo(0, 1e-9));
    expect(t.pointAt(135).depthMm, closeTo(5.510869, 1e-5));
    for (var i = 24; i < 36; i++) {
      expect(t.points[i].depthMm, greaterThan(t.points[i + 1].depthMm));
    }
    for (var i = 36; i < 48; i++) {
      expect(t.points[i].depthMm, lessThan(t.points[i + 1].depthMm));
    }
  });

  for (final angle in [15.0, 30.0, 45.0, 60.0, 75.0, 90.0]) {
    test('closed mirror symmetry at connection angle $angle', () {
      final t =
          SaddleTemplate(headerOdMm: 200, branchOdMm: 100, angleDeg: angle);
      for (var i = 0; i < t.points.length; i++) {
        expect(t.points[i].depthMm,
            closeTo(t.points[t.points.length - 1 - i].depthMm, 1e-9));
      }
    });
  }

  test('15 degree profile exceeds A4 height without silently shortening it',
      () {
    final t = SaddleTemplate(headerOdMm: 200, branchOdMm: 100, angleDeg: 15);
    expect(t.maxDepthMm, closeTo(373.2050807568877, 1e-8));
  });

  test('equal radii at 60 degrees have zero at the tips and 173.205 mm maximum',
      () {
    final t = SaddleTemplate(headerOdMm: 200, branchOdMm: 200, angleDeg: 60);
    expect(t.pointAt(90).depthMm, closeTo(0, 1e-8));
    expect(t.pointAt(270).depthMm, closeTo(0, 1e-8));
    expect(t.maxDepthMm, closeTo(173.20508075688772, 1e-8));
    expect(t.pointAt(180).depthMm, closeTo(57.735026918962575, 1e-8));
  });

  test('equal radii perpendicular profile has two longest tips', () {
    final t = SaddleTemplate(headerOdMm: 200, branchOdMm: 200, angleDeg: 90);
    expect(t.pointAt(0).depthMm, closeTo(100, 1e-9));
    expect(t.pointAt(90).depthMm, closeTo(0, 1e-9));
    expect(t.pointAt(180).depthMm, closeTo(100, 1e-9));
  });

  test('larger branch is rejected', () {
    expect(() => SaddleTemplate(headerOdMm: 100, branchOdMm: 101, angleDeg: 90),
        throwsArgumentError);
  });

  test('print contour evaluates exact boundary points instead of dropping them',
      () {
    final t = SaddleTemplate(headerOdMm: 200, branchOdMm: 100, angleDeg: 45);
    final line = t.profileBetween(255, 260);
    expect(line.first.xMm, 255);
    expect(line.last.xMm, 260);
    for (final p in line) {
      final phi = p.xMm / 50;
      final z = (91.42135623730951 + p.depthMm) / math.sqrt(2) -
          50 * math.cos(phi) / math.sqrt(2);
      final y = 50 * math.sin(phi);
      expect(y * y + z * z, closeTo(10000, 1e-6));
    }
  });

  for (final branch in [100.0, 1999.999, 2000.0]) {
    test('print approximation stays within 0.021 mm for branch $branch', () {
      final t =
          SaddleTemplate(headerOdMm: 2000, branchOdMm: branch, angleDeg: 15);
      final line = t.profileBetween(0, t.stripLengthMm);
      for (var i = 1; i < line.length; i++) {
        final a = line[i - 1];
        final b = line[i];
        for (var part = 1; part < 10; part++) {
          final fraction = part / 10;
          final x = a.xMm + fraction * (b.xMm - a.xMm);
          final interpolation = a.depthMm + fraction * (b.depthMm - a.depthMm);
          expect(interpolation,
              closeTo(t.pointAt(x / t.stripLengthMm * 360).depthMm, .021));
        }
      }
    });
  }
}
