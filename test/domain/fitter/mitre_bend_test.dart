// Kolano segmentowe: kąty cięcia, długości segmentów, szablon.

import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';

import 'package:cut_list_app/domain/fitter/mitre_bend.dart';

void main() {
  const od = 168.3;

  MitreBendResult calc(
          {double angle = 90,
          int welds = 3,
          double radius = 1.5 * od,
          double tangent = 0}) =>
      computeMitreBend(MitreBendInput(
        odMm: od,
        bendAngleDeg: angle,
        welds: welds,
        radiusMm: radius,
        tangentMm: tangent,
      ))!;

  test('90° na 3 spoinach: 30° na spoinie, cięcie 15°', () {
    final r = calc();
    expect(r.jointDeflectionDeg, 30);
    expect(r.cutAngleDeg, 15);
    expect(r.fullSegments, 2);
    expect(r.jointDeflectionDeg * 3, 90);
  });

  test('pełny segment: oś 2R·tg β, gardło i grzbiet ± D·tg β', () {
    final r = calc();
    final tb = math.tan(15 * math.pi / 180);
    final R = 1.5 * od;
    expect(r.fullSegment!.centreMm, closeTo(2 * R * tb, 1e-9));
    expect(r.fullSegment!.throatMm, closeTo(2 * (R - od / 2) * tb, 1e-9));
    expect(r.fullSegment!.heelMm, closeTo(2 * (R + od / 2) * tb, 1e-9));
    expect(r.fullSegment!.heelMm - r.fullSegment!.throatMm,
        closeTo(2 * r.cutDropMm, 1e-9));
    // Liczbowo dla DN150, R = 1,5D: ok. 135 / 90 / 180 mm.
    expect(r.fullSegment!.centreMm, closeTo(135.29, 0.01));
    expect(r.fullSegment!.throatMm, closeTo(90.19, 0.01));
    expect(r.fullSegment!.heelMm, closeTo(180.38, 0.01));
  });

  test('segment końcowy: połowa pełnego + odcinek prosty', () {
    final r = calc(tangent: 50);
    expect(
        r.endPiece.centreMm, closeTo(r.fullSegment!.centreMm / 2 + 50, 1e-9));
    expect(
        r.endPiece.throatMm, closeTo(r.fullSegment!.throatMm / 2 + 50, 1e-9));
    expect(r.pipeNeededMm,
        closeTo(2 * r.fullSegment!.centreMm + 2 * r.endPiece.centreMm, 1e-9));
  });

  test('jedno cięcie 90°: dwa kawałki ścięte pod 45°', () {
    final r = calc(welds: 1, tangent: 200);
    expect(r.cutAngleDeg, 45);
    expect(r.fullSegment, isNull);
    expect(r.endPiece.throatMm, closeTo(200 - od / 2, 1e-9));
    expect(r.endPiece.heelMm, closeTo(200 + od / 2, 1e-9));
  });

  test('szablon: 0 na gardle, D·tg β na grzbiecie, połowa w 90°', () {
    final r = calc();
    expect(r.pointAt(0).offsetMm, closeTo(0, 1e-12));
    expect(r.pointAt(180).offsetMm, closeTo(r.cutDropMm, 1e-9));
    expect(r.pointAt(90).offsetMm, closeTo(r.cutDropMm / 2, 1e-9));
    expect(r.pointAt(90).arcMm, closeTo(math.pi * od / 4, 1e-9));
    final pts = r.templatePoints(16);
    expect(pts, hasLength(17));
    expect(pts.last.offsetMm, closeTo(0, 1e-9));
    expect(pts[8].phiDeg, 180);
  });

  test('długość spoiny ukośnej: elipsa, dłuższa niż obwód rury', () {
    final r = calc();
    expect(r.weldLengthMm, greaterThan(math.pi * od));
    // Przy cięciu 0° (bez skosu) elipsa = okrąg.
    expect(ellipsePerimeter(50, 50), closeTo(2 * math.pi * 50, 1e-9));
  });

  test('błędy: R ≤ D/2, brak promienia, zły kąt, za krótki odcinek', () {
    MitreBendInput i(
            {double r = 300, int w = 3, double a = 90, double t = 0}) =>
        MitreBendInput(
            odMm: od, bendAngleDeg: a, welds: w, radiusMm: r, tangentMm: t);
    expect(i(r: od / 2).problems, contains(MitreProblem.radiusTooSmall));
    expect(i(r: 0).problems, contains(MitreProblem.radius));
    expect(i(a: 0).problems, contains(MitreProblem.angle));
    expect(i(w: 0).problems, contains(MitreProblem.welds));
    expect(i(w: 1, t: 10).problems, contains(MitreProblem.tangentTooShort));
    expect(i(w: 1, t: 100).problems, isEmpty);
    // Przy jednej spoinie promień nie gra roli.
    expect(i(w: 1, r: 0, t: 100).problems, isEmpty);
    expect(computeMitreBend(i(r: 10)), isNull);
  });
}
