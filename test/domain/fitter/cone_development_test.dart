// Rozwinięcie stożka: wzory analityczne, niezmienniki (łuki = obwody,
// tworząca = √(H² + Δr²)), podział na części, rzędne od cięciwy, walidacja
// i zgodność metody wierzchołkowej/triangulacji (stożek mimośrodowy z e = 0)
// ze wzorem analitycznym.
//
// Wartości oczekiwane policzone niezależnie (Python, wzory z nagłówka
// lib/domain/fitter/cone_development.dart).

import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';

import 'package:cut_list_app/domain/fitter/cone_development.dart';

void main() {
  const eps = 1e-6;

  group('stożek ścięty współosiowy — wzory', () {
    // D 1000 / d 400 zewn., t 6, H 600 → Dm 994, dm 394, Δr 300.
    final r = computeCone(const ConeInput(
      largeDiaMm: 1000,
      smallDiaMm: 400,
      heightMm: 600,
      thicknessMm: 6,
      ref: DiameterRef.outside,
    ))!;

    test('D 1000 / d 400 zewn., t 6, H 600 → R 1111,33, r 440,51, θ 161,00°',
        () {
      expect(r.meanLargeMm, 994);
      expect(r.meanSmallMm, 394);
      expect(r.slantMm, closeTo(670.8204, 1e-4));
      expect(r.halfAngleDeg, closeTo(26.5651, 1e-4));
      expect(r.outerRadiusMm, closeTo(1111.3258, 1e-4));
      expect(r.innerRadiusMm, closeTo(440.5054, 1e-4));
      expect(r.sectorAngleDeg, closeTo(160.9969, 1e-4));
      final w = r.whole;
      expect(w.outerChordMm, closeTo(2192.1593, 1e-4));
      expect(w.innerChordMm, closeTo(868.9243, 1e-4));
      expect(w.outerSagittaMm, closeTo(927.8744, 1e-4));
      expect(w.innerSagittaMm, closeTo(367.7893, 1e-4));
      expect(w.diagonalMm, closeTo(1534.5424, 1e-4));
      expect(w.widthMm, closeTo(2192.1593, 1e-4));
      expect(w.heightMm, closeTo(1038.6096, 1e-4));
    });

    test('niezmienniki: łuki = obwody średnie, R − r = tworząca = √(H² + Δr²)',
        () {
      for (final input in const [
        ConeInput(largeDiaMm: 1000, smallDiaMm: 400, heightMm: 600),
        ConeInput(
            largeDiaMm: 2500,
            smallDiaMm: 300,
            heightMm: 150,
            thicknessMm: 12,
            ref: DiameterRef.inside),
        ConeInput(largeDiaMm: 600, smallDiaMm: 0, heightMm: 400),
        ConeInput(largeDiaMm: 1000, smallDiaMm: 900, heightMm: 2000),
      ]) {
        final c = computeCone(input)!;
        final w = c.whole;
        expect(w.outerArcMm, closeTo(math.pi * c.meanLargeMm, eps));
        expect(w.innerArcMm, closeTo(math.pi * c.meanSmallMm, eps));
        final dr = (c.meanLargeMm - c.meanSmallMm) / 2;
        expect(c.slantMm,
            closeTo(math.sqrt(c.heightMm * c.heightMm + dr * dr), eps));
        expect(c.outerRadiusMm - c.innerRadiusMm, closeTo(c.slantMm, eps));
        // Kąt wycinka z promienia: θ = 360°·(Dm/2)/R.
        expect(c.sectorAngleDeg,
            closeTo(360 * c.meanLargeMm / 2 / c.outerRadiusMm, eps));
      }
    });

    test('wymiar wewnętrzny: Dm = D + t', () {
      final c = computeCone(const ConeInput(
          largeDiaMm: 1000,
          smallDiaMm: 500,
          heightMm: 400,
          thicknessMm: 10,
          ref: DiameterRef.inside))!;
      expect(c.meanLargeMm, 1010);
      expect(c.meanSmallMm, 510);
    });

    test(
        'stożek pełny d = 0, Dm 600, H 400 → R 500, θ 216°, prostokąt 1000 × 654,51',
        () {
      final c = computeCone(
          const ConeInput(largeDiaMm: 600, smallDiaMm: 0, heightMm: 400))!;
      expect(c.isFull, isTrue);
      expect(c.outerRadiusMm, closeTo(500, eps));
      expect(c.innerRadiusMm, 0);
      expect(c.sectorAngleDeg, closeTo(216, eps));
      expect(c.whole.outerChordMm, closeTo(951.0565, 1e-4));
      expect(c.whole.widthMm, closeTo(1000, eps));
      expect(c.whole.heightMm, closeTo(654.5085, 1e-4));
      // > 180° — od cięciwy się nie da; z 2 części już tak.
      expect(c.whole.chordOffsetsPossible, isFalse);
      expect(c.whole.chordOffsets(outer: true, stepMm: 100), isEmpty);
      expect(c.sectorFor(2).chordOffsetsPossible, isTrue);
      // Obrys zawiera wierzchołek.
      final p = c.whole.pattern();
      expect(p.outline.any((q) => q.y > 654), isTrue);
    });

    test(
        'wymiar kątem: Dm 1000, dm 500, α 30° → H 433,01, R 1000, r 500, θ 180°',
        () {
      final c = computeCone(const ConeInput(
          largeDiaMm: 1000,
          smallDiaMm: 500,
          mode: ConeSizeMode.halfAngle,
          halfAngleDeg: 30))!;
      expect(c.heightMm, closeTo(433.0127, 1e-4));
      expect(c.slantMm, closeTo(500, eps));
      expect(c.outerRadiusMm, closeTo(1000, eps));
      expect(c.innerRadiusMm, closeTo(500, eps));
      expect(c.sectorAngleDeg, closeTo(180, eps));
      expect(c.whole.widthMm, closeTo(2000, eps));
      expect(c.whole.heightMm, closeTo(1000, eps));
    });

    test('wymiar tworzącą: Dm 800, dm 200, L 500 → H 400, R 666,67, θ 216°',
        () {
      final c = computeCone(const ConeInput(
          largeDiaMm: 800,
          smallDiaMm: 200,
          mode: ConeSizeMode.slant,
          slantMm: 500))!;
      expect(c.heightMm, closeTo(400, eps));
      expect(c.outerRadiusMm, closeTo(2000 / 3, eps));
      expect(c.innerRadiusMm, closeTo(500 / 3, eps));
      expect(c.sectorAngleDeg, closeTo(216, eps));
    });

    test('naddatek 20 mm przy θ 180°: krawędź pozioma, prostokąt 2000 × 1020',
        () {
      final c = computeCone(const ConeInput(
          largeDiaMm: 1000,
          smallDiaMm: 500,
          mode: ConeSizeMode.halfAngle,
          halfAngleDeg: 30,
          allowanceMm: 20))!;
      expect(c.part.widthMm, closeTo(2000, eps));
      expect(c.part.heightMm, closeTo(1020, eps));
      final p = c.part.pattern();
      expect(p.allowance, hasLength(4));
      expect(p.heightMm, closeTo(1020, eps));
    });
  });

  group('podział na części', () {
    final c = computeCone(const ConeInput(
      largeDiaMm: 1000,
      smallDiaMm: 400,
      heightMm: 600,
      thicknessMm: 6,
      ref: DiameterRef.outside,
      parts: 2,
    ))!;

    test('2 części: θ/2, łuk połowy obwodu, prostokąt 1436,09 × 775,11', () {
      final p = c.part;
      expect(p.angleDeg, closeTo(c.sectorAngleDeg / 2, eps));
      expect(p.outerArcMm, closeTo(1561.3715, 1e-4));
      expect(p.outerArcMm * 2, closeTo(math.pi * 994, eps));
      expect(p.innerArcMm * 2, closeTo(math.pi * 394, eps));
      expect(p.widthMm, closeTo(1436.0855, 1e-4));
      expect(p.heightMm, closeTo(775.1139, 1e-4));
    });

    test('zalecany podział wg arkusza', () {
      // 1 część 2192 × 1039 mieści się obrócona na 1500 × 3000.
      expect(c.recommendedParts(1500, 3000), 1);
      // Na 1000 × 2000 dopiero połówki (1436 × 775).
      expect(c.recommendedParts(1000, 2000), 2);
      expect(c.recommendedParts(100, 100), isNull);
    });

    test('prawie płaski (θ > 300°) — co najmniej 2 części', () {
      final flat = computeCone(
          const ConeInput(largeDiaMm: 1000, smallDiaMm: 0, heightMm: 50))!;
      expect(flat.sectorAngleDeg, greaterThan(300));
      expect(flat.nearlyFlat, isTrue);
      expect(flat.recommendedParts(5000, 5000), 2);
    });
  });

  group('trasowanie bez cyrkla — rzędne od cięciwy', () {
    test('R 1000, θ 180°, co 500 mm: 0 / 866,03 / 1000 / 866,03 / 0', () {
      final c = computeCone(const ConeInput(
          largeDiaMm: 1000,
          smallDiaMm: 500,
          mode: ConeSizeMode.halfAngle,
          halfAngleDeg: 30))!;
      final o = c.whole.chordOffsets(outer: true, stepMm: 500);
      expect(o, hasLength(5));
      for (final (n, p) in o.indexed) {
        expect(p.xMm, closeTo(500.0 * n, eps));
      }
      expect(o[0].yMm, closeTo(0, eps));
      expect(o[1].yMm, closeTo(866.0254, 1e-4));
      expect(o[2].yMm, closeTo(1000, eps));
      expect(o[4].yMm, closeTo(0, eps));
      final inner = c.whole.chordOffsets(outer: false, stepMm: 500);
      expect(inner.last.xMm, closeTo(1000, eps));
      expect(inner[1].yMm, closeTo(500, eps));
      // Odstęp cięciw: (R − r)·cos 90° = 0.
      expect(c.whole.chordGapMm, closeTo(0, eps));
    });

    test('smukły stożek (R ≈ 20 m) — tabela zamiast cyrkla, środek = strzałka',
        () {
      final c = computeCone(
          const ConeInput(largeDiaMm: 1000, smallDiaMm: 900, heightMm: 2000))!;
      expect(c.outerRadiusMm, closeTo(20006.2490, 1e-4));
      expect(c.needsOrdinates, isTrue);
      final o = c.whole.chordOffsets(outer: true, stepMm: 100);
      final mid =
          o.firstWhere((p) => (p.xMm - c.whole.outerChordMm / 2).abs() < 1e-6);
      expect(mid.yMm, closeTo(61.6341, 1e-4));
      expect(o.last.xMm, closeTo(3138.3658, 1e-4));
      expect(o.last.yMm, closeTo(0, 1e-6));
      // Rzędna z niezależnego wzoru: y = R·cos(β) − R·cos(θ/2),
      // sin β = (x − c/2)/R.
      final x = o[5].xMm;
      final beta = math.asin((x - c.whole.outerChordMm / 2) / c.outerRadiusMm);
      expect(
          o[5].yMm,
          closeTo(
              c.outerRadiusMm * math.cos(beta) -
                  c.outerRadiusMm *
                      math.cos(c.sectorAngleDeg / 2 * math.pi / 180),
              1e-6));
    });
  });

  group('walidacja', () {
    List<ConeProblem> p(ConeInput i) => i.problems;

    test('d ≥ D, H ≤ 0, zła grubość, kąt, tworząca — komunikaty, bez wyniku',
        () {
      expect(
          p(const ConeInput(largeDiaMm: 500, smallDiaMm: 500, heightMm: 100)),
          contains(ConeProblem.smallNotLess));
      expect(p(const ConeInput(largeDiaMm: 500, smallDiaMm: 200, heightMm: 0)),
          contains(ConeProblem.height));
      expect(
          p(const ConeInput(
              largeDiaMm: 500,
              smallDiaMm: 200,
              heightMm: 100,
              thicknessMm: 100)),
          contains(ConeProblem.thickness));
      expect(
          p(const ConeInput(
              largeDiaMm: 500, smallDiaMm: 0, heightMm: 100, thicknessMm: 250)),
          contains(ConeProblem.thickness));
      expect(
          p(const ConeInput(
              largeDiaMm: 500,
              smallDiaMm: 200,
              mode: ConeSizeMode.halfAngle,
              halfAngleDeg: 90)),
          contains(ConeProblem.halfAngle));
      expect(
          p(const ConeInput(
              largeDiaMm: 500,
              smallDiaMm: 200,
              mode: ConeSizeMode.slant,
              slantMm: 150)),
          contains(ConeProblem.slantTooShort));
      expect(
          p(const ConeInput(
              largeDiaMm: 500, smallDiaMm: 200, heightMm: 100, parts: 0)),
          contains(ConeProblem.parts));
      expect(
          p(const ConeInput(
              largeDiaMm: 500,
              smallDiaMm: 200,
              heightMm: 100,
              allowanceMm: -1)),
          contains(ConeProblem.allowance));
      expect(
          computeCone(
              const ConeInput(largeDiaMm: 0, smallDiaMm: 0, heightMm: 1)),
          isNull);
    });

    test('NaN / ∞ nie przechodzą', () {
      expect(
          p(const ConeInput(
              largeDiaMm: double.nan, smallDiaMm: 100, heightMm: 100)),
          contains(ConeProblem.largeDia));
      expect(
          p(const ConeInput(
              largeDiaMm: 500, smallDiaMm: double.infinity, heightMm: 100)),
          contains(ConeProblem.smallDia));
      expect(
          p(const ConeInput(
              largeDiaMm: 500, smallDiaMm: 100, heightMm: double.nan)),
          contains(ConeProblem.height));
    });

    test('poprawne dane — bez problemów, wyniki skończone', () {
      for (final i in const [
        ConeInput(largeDiaMm: 1000, smallDiaMm: 999, heightMm: 5000),
        ConeInput(largeDiaMm: 1000, smallDiaMm: 0, heightMm: 1),
        ConeInput(
            largeDiaMm: 1000,
            smallDiaMm: 10,
            mode: ConeSizeMode.halfAngle,
            halfAngleDeg: 0.01),
      ]) {
        final c = computeCone(i)!;
        for (final v in [
          c.outerRadiusMm,
          c.innerRadiusMm,
          c.sectorAngleDeg,
          c.whole.widthMm,
          c.whole.heightMm,
        ]) {
          expect(v.isFinite, isTrue);
        }
      }
    });
  });

  group('stożek mimośrodowy (triangulacja / rozwinięcie z wierzchołka)', () {
    test('e = 0 daje to samo co wzór analityczny', () {
      const base = ConeInput(largeDiaMm: 1000, smallDiaMm: 400, heightMm: 600);
      final c = computeCone(base)!;
      final e = computeEccentricCone(const EccentricConeInput(
          largeDiaMm: 1000, smallDiaMm: 400, heightMm: 600, divisions: 48))!;
      // Wierzchołek → punkty koła dolnego = R; kąt rozwinięcia = θ.
      for (final rho in e.apexDistancesMm) {
        expect(rho, closeTo(c.outerRadiusMm, 1e-6));
      }
      expect(e.developedAngleDeg, closeTo(c.sectorAngleDeg, 1e-6));
      // Tworzące = L.
      for (final row in e.rows) {
        expect(row.generatorMm, closeTo(c.slantMm, 1e-6));
      }
      // Cięciwa na blasze = cięciwa łuku R przy kącie θ/N.
      expect(
          e.rows.first.bottomChordMm,
          closeTo(
              2 *
                  c.outerRadiusMm *
                  math.sin(c.sectorAngleDeg / 48 / 2 * math.pi / 180),
              1e-6));
      // Prostokąt blachy jak ze wzoru (próbkowanie łuku co ~0,4°).
      expect(e.parts.single.widthMm, closeTo(c.whole.widthMm, 0.05));
      expect(e.parts.single.heightMm, closeTo(c.whole.heightMm, 0.05));
    });

    test('krawędzie na blasze = obwody kół, zbieżność cięciw przy N → duże',
        () {
      const i = EccentricConeInput(
          largeDiaMm: 800,
          smallDiaMm: 400,
          heightMm: 500,
          offsetMm: 150,
          thicknessMm: 5,
          ref: DiameterRef.outside,
          divisions: 24);
      final e = computeEccentricCone(i)!;
      expect(e.bottomEdgeMm, closeTo(math.pi * 795, math.pi * 795 * 1e-4));
      expect(e.topEdgeMm, closeTo(math.pi * 395, math.pi * 395 * 1e-4));
      double chordSum(int n) {
        final r = computeEccentricCone(EccentricConeInput(
            largeDiaMm: 800,
            smallDiaMm: 400,
            heightMm: 500,
            offsetMm: 150,
            thicknessMm: 5,
            ref: DiameterRef.outside,
            divisions: n))!;
        return r.rows.fold(0.0, (s, row) => s + (row.bottomChordMm ?? 0));
      }

      final err12 = math.pi * 795 - chordSum(12);
      final err48 = math.pi * 795 - chordSum(48);
      expect(err12, greaterThan(0));
      expect(err48, greaterThan(0));
      expect(err48, lessThan(err12 / 10));
      // Cięciwy na blasze dłuższe niż w rzucie (rzut skraca obwód).
      expect(e.rows.first.bottomChordMm!, greaterThan(e.planChordBottomMm));
    });

    test('jedna tworząca pionowa: D 800, d 400, H 500 → 500 i 640,31 (38,66°)',
        () {
      final e = computeEccentricCone(const EccentricConeInput(
          largeDiaMm: 800,
          smallDiaMm: 400,
          heightMm: 500,
          verticalSide: true,
          divisions: 16))!;
      expect(e.offsetMm, closeTo(200, eps));
      expect(e.shortestGeneratorMm, closeTo(500, eps));
      expect(e.longestGeneratorMm, closeTo(640.3124, 1e-4));
      expect(e.shortSideAngleDeg, closeTo(0, eps));
      expect(e.longSideAngleDeg, closeTo(38.6598, 1e-4));
      // Szew po krótkiej stronie: pierwszy wiersz to tworząca pionowa.
      expect(e.rows.first.generatorMm, closeTo(500, eps));
      expect(e.rows[8].generatorMm, closeTo(640.3124, 1e-4));
      expect(e.rows.last.generatorMm, closeTo(500, eps));
    });

    test('linie prawdziwe zgodne z rzutem: e 100, φ 90° → 547,72', () {
      const i = EccentricConeInput(
          largeDiaMm: 800, smallDiaMm: 400, heightMm: 500, offsetMm: 100);
      final e = computeEccentricCone(i)!;
      expect(e.rows[4].phiDeg, closeTo(90, eps));
      expect(e.rows[4].generatorMm, closeTo(547.7226, 1e-4));
      for (final row in e.rows) {
        expect(row.generatorMm,
            closeTo(eccentricGeneratorAt(i, row.phiDeg), 1e-6));
      }
    });

    test('kąt rozwinięcia = suma kątów drobnej triangulacji (niezależnie)', () {
      const i = EccentricConeInput(
          largeDiaMm: 900, smallDiaMm: 300, heightMm: 400, offsetMm: 250);
      final e = computeEccentricCone(i)!;
      // Wierzchołek z jednokładności: V = (e·k, 0, H·k), k = R1/(R1 − R2).
      const r1 = 450.0, r2 = 150.0, k = r1 / (r1 - r2);
      const vx = 250 * k, vz = 400 * k;
      const m = 20000;
      var sum = 0.0;
      List<double> dir(int j) {
        final f = 2 * math.pi * j / m;
        final x = r1 * math.cos(f) - vx, y = r1 * math.sin(f), z = -vz;
        final l = math.sqrt(x * x + y * y + z * z);
        return [x / l, y / l, z / l];
      }

      var prev = dir(0);
      for (var j = 1; j <= m; j++) {
        final cur = dir(j);
        final dot = prev[0] * cur[0] + prev[1] * cur[1] + prev[2] * cur[2];
        sum += math.acos(dot.clamp(-1.0, 1.0));
        prev = cur;
      }
      expect(e.developedAngleDeg, closeTo(sum * 180 / math.pi, 1e-4));
    });

    test('podział na 2 i 4 części: suma krawędzi bez zmian, części ≤ całość',
        () {
      for (final n in [2, 4]) {
        final e = computeEccentricCone(EccentricConeInput(
            largeDiaMm: 800,
            smallDiaMm: 400,
            heightMm: 500,
            verticalSide: true,
            parts: n))!;
        expect(e.parts, hasLength(n));
        expect(e.bottomEdgeMm, closeTo(math.pi * 800, math.pi * 800 * 1e-4));
        for (final p in e.parts) {
          expect(p.widthMm, greaterThan(0));
          expect(p.heightMm, greaterThan(0));
          for (final q in p.outline) {
            expect(q.x, greaterThanOrEqualTo(-1e-6));
            expect(q.y, greaterThanOrEqualTo(-1e-6));
            expect(q.x, lessThanOrEqualTo(p.widthMm + 1e-6));
            expect(q.y, lessThanOrEqualTo(p.heightMm + 1e-6));
          }
        }
      }
    });

    test('stożek ukośny pełny (d = 0): górna krawędź to wierzchołek', () {
      final e = computeEccentricCone(const EccentricConeInput(
          largeDiaMm: 600, smallDiaMm: 0, heightMm: 400, offsetMm: 100))!;
      expect(e.isFull, isTrue);
      expect(e.topEdgeMm, closeTo(0, eps));
      expect(e.rows.first.topChordMm, closeTo(0, eps));
      expect(e.parts.single.marks.any((m) => m.label == 'V'), isTrue);
    });

    test('walidacja: e < 0, zły podział, 3 części, d ≥ D', () {
      List<EccentricProblem> p(EccentricConeInput i) => i.problems;
      expect(
          p(const EccentricConeInput(
              largeDiaMm: 800, smallDiaMm: 400, heightMm: 500, offsetMm: -1)),
          contains(EccentricProblem.offset));
      expect(
          p(const EccentricConeInput(
              largeDiaMm: 800, smallDiaMm: 400, heightMm: 500, divisions: 10)),
          contains(EccentricProblem.divisions));
      expect(
          p(const EccentricConeInput(
              largeDiaMm: 800, smallDiaMm: 400, heightMm: 500, parts: 3)),
          contains(EccentricProblem.parts));
      expect(
          p(const EccentricConeInput(
              largeDiaMm: 400, smallDiaMm: 800, heightMm: 500)),
          contains(EccentricProblem.smallNotLess));
      expect(
          computeEccentricCone(const EccentricConeInput(
              largeDiaMm: 800, smallDiaMm: 400, heightMm: 0)),
          isNull);
    });
  });
}
