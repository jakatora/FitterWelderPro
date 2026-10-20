import 'package:flutter_test/flutter_test.dart';
import 'package:cut_list_app/domain/fitter/fitter_calcs.dart';
import 'package:cut_list_app/domain/fitter/pipe_weight.dart';

void main() {
  test(
      '316L 60.3 x 3.91 mass and two 1 m pieces agree with published app fixture',
      () {
    final r = pipeWeight(
        odMm: 60.3,
        wallMm: 3.91,
        material: PipeMaterial.ss316,
        lengthMm: 1000,
        quantity: 2)!;
    expect(r.kgPerM, closeTo(5.541, .001));
    expect(r.kgPerPiece, r.kgPerM);
    expect(r.kgTotal, closeTo(11.082, .002));
  });
  test('absent length and quantity never become hidden 1 m or 1 piece', () {
    final r =
        pipeWeight(odMm: 60.3, wallMm: 3.91, material: PipeMaterial.ss316)!;
    expect(r.kgPerPiece, isNull);
    expect(r.kgTotal, isNull);
    final one = pipeWeight(
        odMm: 60.3,
        wallMm: 3.91,
        material: PipeMaterial.ss316,
        lengthMm: 6000)!;
    expect(one.kgPerPiece, closeTo(33.246, .006));
    expect(one.kgTotal, isNull);
  });
  test('304L and 316L retain their distinct densities', () {
    final a =
        pipeWeight(odMm: 60.3, wallMm: 3.91, material: PipeMaterial.ss304)!;
    final b =
        pipeWeight(odMm: 60.3, wallMm: 3.91, material: PipeMaterial.ss316)!;
    expect(a.kgPerM / b.kgPerM, closeTo(.9875, 1e-10));
  });
  test('invalid dimensions, quantity and overflow are refused', () {
    for (final pair in [
      (0.0, 1.0),
      (10.0, 5.0),
      (-10.0, 1.0),
      (double.nan, 1.0),
      (1e308, 2e307)
    ]) {
      expect(
          pipeWeight(odMm: pair.$1, wallMm: pair.$2, material: PipeMaterial.cs),
          isNull);
    }
    for (final q in [-1.0, 0.0, 1.5, double.infinity, 2147483648.0]) {
      expect(
          pipeWeight(
              odMm: 60.3,
              wallMm: 3.91,
              material: PipeMaterial.ss316,
              lengthMm: 1000,
              quantity: q),
          isNull);
    }
    expect(
        pipeWeight(
            odMm: 60.3,
            wallMm: 3.91,
            material: PipeMaterial.ss316,
            quantity: 2),
        isNull);
    expect(
        pipeWeight(
            odMm: 60.3,
            wallMm: 3.91,
            material: PipeMaterial.ss316,
            lengthMm: -1),
        isNull);
  });
}
