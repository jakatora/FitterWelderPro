import 'package:flutter_test/flutter_test.dart';
import 'package:cut_list_app/services/saddle_template.dart';

void main() {
  test('90 degree template measures cutback from the longest tips', () {
    final t = SaddleTemplate(headerOdMm: 100, branchOdMm: 60, angleDeg: 90);
    expect(t.points.first.depthMm, closeTo(10, 1e-9));
    expect(t.points[9].depthMm, closeTo(5.276925690687, 1e-9));
    expect(t.points[18].depthMm, closeTo(0, 1e-9));
  });

  test(
      '45 degree intersection includes cotangent tilt, not cosine approximation',
      () {
    final t = SaddleTemplate(headerOdMm: 200, branchOdMm: 100, angleDeg: 45);
    // Axial intersections at phi0 and180 differ by 2*r*cot(45)=100.
    expect(t.points.first.depthMm - t.points[36].depthMm, closeTo(100, 1e-9));
    expect(t.points[18].depthMm, closeTo(31.053130901849, 1e-9));
  });

  for (final bad in [double.nan, double.infinity, 0.0, -1.0, 2000.1]) {
    test('service rejects invalid header OD $bad', () {
      expect(
          () => SaddleTemplate(headerOdMm: bad, branchOdMm: 50, angleDeg: 90),
          throwsArgumentError);
    });
    test('service rejects invalid branch OD $bad', () {
      expect(
          () => SaddleTemplate(headerOdMm: 2000, branchOdMm: bad, angleDeg: 90),
          throwsArgumentError);
    });
  }
  for (final bad in [double.nan, double.infinity, 14.9, 90.1]) {
    test('service rejects invalid connection angle $bad', () {
      expect(
          () => SaddleTemplate(headerOdMm: 200, branchOdMm: 100, angleDeg: bad),
          throwsArgumentError);
    });
  }
  for (final count in [0, 1, 24, 1000000]) {
    test('service rejects unsafe sample count $count', () {
      expect(
          () => SaddleTemplate(
              headerOdMm: 200,
              branchOdMm: 100,
              angleDeg: 90,
              pointsCount: count),
          throwsArgumentError);
    });
  }
}
