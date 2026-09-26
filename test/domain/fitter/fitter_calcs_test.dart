// Czyste obliczenia zakładek „Kalkulatory montera” (lib/domain/fitter/).
// Liczby wyliczone niezależnie (kalkulator / Python), źródła przy grupach.

import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';

import 'package:cut_list_app/domain/fitter/fitter_calcs.dart';

void main() {
  // FAZOWANIE. EN ISO 9692-1 podaje kąt ROWKA α (całkowity, np. 60°);
  // ASME B16.25 podaje kąt fazy NA STRONĘ β = 37,5° ± 2,5° (rowek 75°),
  // próg 1,6 ± 0,8 mm. Szerokość fazy na stronę w = h·tan β.
  group('fazowanie', () {
    test('V: t 20, b 2, β 30° → h 18, w 10,39, rowek 20,78', () {
      final g = bevelGeometry(
          joint: BevelJoint.v,
          wallMm: 20,
          angleDeg: 30,
          convention: BevelAngleConvention.perSide,
          rootFaceMm: 2,
          gapMm: 0);
      expect(g.depthPerFaceMm, 18);
      expect(g.widthPerSideMm, closeTo(10.392, 0.001));
      expect(g.grooveOpeningMm, closeTo(20.785, 0.001));
      expect(g.grooveDeg, 60);
      expect(g.bevelledFaces, 1);
    });

    test('X: głębokość (t − b)/2 na stronę → w 5,20 (nie 10,39)', () {
      final g = bevelGeometry(
          joint: BevelJoint.x,
          wallMm: 20,
          angleDeg: 30,
          convention: BevelAngleConvention.perSide,
          rootFaceMm: 2,
          gapMm: 2);
      expect(g.depthPerFaceMm, 9);
      expect(g.widthPerSideMm, closeTo(5.196, 0.001));
      expect(g.grooveOpeningMm, closeTo(12.392, 0.001)); // 2 + 2·5,196
      expect(g.bevelledFaces, 2);
    });

    test('ISO 9692-1: kąt rowka 60° → β 30°, t 10 b 1 → w 5,20 (nie 15,59)',
        () {
      final g = bevelGeometry(
          joint: BevelJoint.v,
          wallMm: 10,
          angleDeg: 60,
          convention: BevelAngleConvention.grooveIncluded,
          rootFaceMm: 1,
          gapMm: 0);
      expect(g.perSideDeg, 30);
      expect(g.widthPerSideMm, closeTo(5.196, 0.001));
    });

    test('ASME B16.25: 37,5° na stronę, t 10, b 1,6, g 3 → w 6,45, rowek 15,89',
        () {
      final g = bevelGeometry(
          joint: BevelJoint.v,
          wallMm: 10,
          angleDeg: 37.5,
          convention: BevelAngleConvention.perSide,
          rootFaceMm: 1.6,
          gapMm: 3);
      expect(g.widthPerSideMm, closeTo(6.4455, 0.0005));
      expect(g.grooveOpeningMm, closeTo(15.891, 0.001));
      expect(g.grooveDeg, 75);
    });

    test('przeliczenie konwencji 37,5 ↔ 75', () {
      expect(
          convertBevelAngle(37.5,
              from: BevelAngleConvention.perSide,
              to: BevelAngleConvention.grooveIncluded),
          75);
      expect(
          convertBevelAngle(60,
              from: BevelAngleConvention.grooveIncluded,
              to: BevelAngleConvention.perSide),
          30);
    });

    test('walidacja bez cichych wartości domyślnych', () {
      BevelInputError? v(
              {double? t = 10,
              double? a = 30,
              double? b = 1,
              double? g = 0,
              BevelAngleConvention c = BevelAngleConvention.perSide}) =>
          validateBevel(
              wallMm: t, angleDeg: a, convention: c, rootFaceMm: b, gapMm: g);
      expect(v(), isNull);
      expect(v(t: null), BevelInputError.thickness);
      expect(v(a: null), BevelInputError.angle);
      expect(v(b: null), BevelInputError.rootFace);
      expect(v(g: null), BevelInputError.gap);
      expect(v(a: 90), BevelInputError.angle); // tan → ∞
      expect(v(a: 0), BevelInputError.angle);
      expect(v(a: 118, c: BevelAngleConvention.grooveIncluded), isNull);
      expect(v(b: 10), BevelInputError.rootFace);
      expect(v(g: -1), BevelInputError.gap);
    });
  });

  // SPADEK: α = atan(p/100). Piła ze skalą 0° = cięcie prostopadłe → α.
  test('kąt piły: 2 % → 1,146° od prostopadłej / 88,854° na skali 90°', () {
    final s = slopeSawAngles(2);
    expect(s.fromSquareDeg, closeTo(1.1458, 0.0001));
    expect(s.scale90Deg, closeTo(88.8542, 0.0001));
  });

  // CIĘCIE KOLANKA: DN50 LR (A = 76 wg ASME B16.9, OD 60,3):
  // extrados (R + OD/2)·π/2 = 166,74; intrados (R − OD/2)·π/2 = 72,02.
  test('cięcie kolanka DN50 LR 90° → 60°: 111,16 / 48,01, OD 60,30', () {
    final r = elbowCut(
        baseAngleDeg: 90,
        extradosMm: 166.7400,
        intradosMm: 72.0210,
        targetAngleDeg: 60)!;
    expect(r.longCutMm, closeTo(111.16, 0.01));
    expect(r.shortCutMm, closeTo(48.01, 0.01));
    expect(r.longRemainMm, closeTo(55.58, 0.01));
    expect(r.remainAngleDeg, 30);
    expect(r.odDerivedMm, closeTo(60.30, 0.01));
    expect(
        elbowCut(
            baseAngleDeg: 90,
            extradosMm: 70,
            intradosMm: 140,
            targetAngleDeg: 60),
        isNull);
    expect(
        elbowCut(
            baseAngleDeg: 45,
            extradosMm: 140,
            intradosMm: 70,
            targetAngleDeg: 45),
        isNull);
  });

  // OBRÓT: łuk = obwód·°/360; OD 60,3 → obwód π·60,3; 90° → 47,36.
  group('obrót kolanka', () {
    test('OD 60,3 i obwód „0” → liczy z OD (nie 0,0 mm)', () {
      final r = rotationArc(odMm: 60.3, circumferenceMm: 0, degrees: 90);
      expect(r.arc!.arcMm, closeTo(47.36, 0.01));
      expect(r.arc!.circumferenceMm, closeTo(math.pi * 60.3, 1e-9));
    });

    test('25 % = 90°', () {
      final r = rotationArc(odMm: 60.3, percent: 25);
      expect(r.arc!.degrees, 90);
      expect(r.arc!.arcMm, closeTo(47.36, 0.01));
    });

    test('stopnie wygrywają z %, > 360° oznaczone', () {
      expect(rotationArc(circumferenceMm: 360, degrees: 400).arc!.overFullTurn,
          isTrue);
      expect(
          rotationArc(circumferenceMm: 360, degrees: 90, percent: 50)
              .arc!
              .arcMm,
          90);
    });

    test('błędy', () {
      expect(rotationArc(degrees: 90).error, RotationError.noSize);
      expect(rotationArc(odMm: 60.3, circumferenceMm: 0).error,
          RotationError.noRotation);
    });
  });

  // REDUKCJA: B16.9 DN100×50, H = 102; cel 88,9 → 102·25,4/54 = 47,98.
  test('redukcja 114,3×60,3, L 102, cel 88,9 → 47,98 od dużego końca', () {
    expect(
        reducerCutFromLargeMm(
            d1Mm: 114.3, d2Mm: 60.3, lengthMm: 102, targetMm: 88.9),
        closeTo(47.98, 0.01));
    expect(
        reducerCutFromLargeMm(
            d1Mm: 60.3, d2Mm: 114.3, lengthMm: 102, targetMm: 88.9),
        closeTo(47.98, 0.01));
    expect(
        reducerCutFromLargeMm(
            d1Mm: 114.3, d2Mm: 60.3, lengthMm: 102, targetMm: 130),
        isNull);
    expect(
        reducerCutFromLargeMm(
            d1Mm: 60.3, d2Mm: 60.3, lengthMm: 102, targetMm: 60.3),
        isNull);
  });

  // CIĘŻAR: ρ 316L = 8,0 kg/dm³ (EN 10088-1, TEAM EDELSTAHL 1.4404),
  // 304L = 7,9 (Industeel UR 304L), CS 7,85.
  group('ciężar rury', () {
    test('gęstości', () {
      expect(kPipeDensityKgM3[PipeMaterial.ss316], 8000);
      expect(kPipeDensityKgM3[PipeMaterial.ss304], 7900);
      expect(kPipeDensityKgM3[PipeMaterial.cs], 7850);
    });

    test('60,3 × 3,91: 316L 5,541 kg/m (było 5,493), CS 5,437', () {
      expect(pipeMassKgPerM(60.3, 3.91, 8000), closeTo(5.5414, 0.0001));
      expect(pipeMassKgPerM(60.3, 3.91, 7850), closeTo(5.4375, 0.0001));
    });
  });

  // DYLATACJA: α 304L = 16,0·10⁻⁶/K (20–100 °C, Industeel UR 304L).
  test('dylatacja 304L 50 m, ΔT 100 → 80,0 mm (było 86,0)', () {
    expect(kExpansionAlpha[ExpansionMaterial.ss304L], 16.0e-6);
    expect(
        thermalExpansionMm(
            kExpansionAlpha[ExpansionMaterial.ss304L]!, 50, 100),
        closeTo(80.0, 1e-9));
    expect(thermalExpansionMm(12e-6, 50, 100), closeTo(60.0, 1e-9));
  });
}
