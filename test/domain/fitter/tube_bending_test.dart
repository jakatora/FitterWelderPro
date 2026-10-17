// Gięcie rurek: łuk, odsunięcie, zysk, długość cięcia i znaczniki.
// Wartości oczekiwane policzone niezależnie (na kartce / z tożsamości
// trygonometrycznych), nie wzorem z kodu.

import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';

import 'package:cut_list_app/domain/fitter/tube_bending.dart';
import 'package:cut_list_app/screens/rolling_offset_screen.dart'
    show rollFromVerticalDeg;

void main() {
  group('jedno gięcie — geometria', () {
    test('CLR 38 mm, 90°: łuk 59,69, setback 38, gain 16,31', () {
      final g = bendGeometry(angleDeg: 90, clrMm: 38);
      // Łuk: ćwiartka okręgu 2π·38/4 = 19π = 59,690…
      expect(g.arcMm, closeTo(59.6903, 1e-4));
      // tg 45° = 1 → setback = CLR.
      expect(g.setbackMm, closeTo(38, 1e-9));
      // 2·38 − 19π = 16,3097…
      expect(g.gainMm, closeTo(16.3097, 1e-4));
    });

    test('CLR 38 mm, 45°: łuk 29,85, setback 15,74, gain 1,64', () {
      final g = bendGeometry(angleDeg: 45, clrMm: 38);
      // Ósma część okręgu: 2π·38/8 = 9,5π = 29,845…
      expect(g.arcMm, closeTo(29.8451, 1e-4));
      // tg 22,5° = √2 − 1.
      expect(g.setbackMm, closeTo(38 * (math.sqrt2 - 1), 1e-9));
      expect(g.setbackMm, closeTo(15.7401, 1e-4));
      // 2·15,7401 − 29,8451 = 1,6351.
      expect(g.gainMm, closeTo(1.6351, 1e-4));
    });

    test('jedno gięcie 90°: A 200 + B 150 − 16,31 = 333,69 → cięcie 334 mm',
        () {
      final r = computeTubeRun(TubeRunInput.single(
          clrMm: 38, angleDeg: 90, legAMm: 200, legBMm: 150))!;
      expect(r.developedMm, closeTo(333.6903, 1e-4));
      expect(r.cutLengthMm(TubeUnit.mm), 334);
      final b = r.bends.single;
      // Znacznik ogólny = początek łuku = 200 − 38.
      expect(b.arcStartMm, closeTo(162, 1e-9));
      expect(b.markMm, closeTo(162, 1e-9));
      expect(b.vertexMm, closeTo(200, 1e-9));
      expect(b.arcEndMm, closeTo(162 + 59.6903, 1e-4));
      expect(r.straightsMm[0], closeTo(162, 1e-9));
      expect(r.straightsMm[1], closeTo(112, 1e-9));
      expect(r.feasible, isTrue);
      expect(r.warnings, isEmpty);
    });
  });

  group('odsadzka', () {
    test('H 100 przy 45° → między gięciami 141,42; skrócenie 41,42', () {
      final o = computeTubeOffset(const TubeOffsetInput(
          clrMm: 38, heightMm: 100, angleDeg: 45, legAMm: 200, legBMm: 200))!;
      // 100 / sin 45° = 100·√2.
      expect(o.travelMm, closeTo(141.42, 0.005));
      expect(o.advanceMm, closeTo(100, 1e-9));
      // H·tg 22,5° = 100·(√2 − 1).
      expect(o.shrinkMm, closeTo(41.42, 0.005));
      expect(o.rollFromVerticalDeg, 0);
      // 200 + 141,4214 + 200 − 2 × 1,6351 = 538,1512 → w górę 538,5.
      expect(o.run.developedMm, closeTo(538.1512, 1e-4));
      expect(o.run.cutLengthMm(TubeUnit.mm), 538.5);
      // Znaczniki: 200 − 15,7401; drugi wierzchołek 200 + 141,4214 − 1,6351.
      expect(o.run.bends[0].arcStartMm, closeTo(184.2599, 1e-4));
      expect(o.run.bends[1].vertexMm, closeTo(339.7863, 1e-4));
      expect(o.run.bends[1].arcStartMm, closeTo(324.0462, 1e-4));
      // Drugie gięcie w przeciwną stronę.
      expect(o.run.bends[1].rotationDeg, 180);
    });

    test('mnożniki odsadzki jak w tabeli Swagelok (MS-13-43)', () {
      // Offset bend allowance: 30° 2,000 · 45° 1,414 · 60° 1,154.
      for (final (angle, factor) in const [
        (30.0, 2.000),
        (45.0, 1.414),
        (60.0, 1.154),
      ]) {
        final o = computeTubeOffset(TubeOffsetInput(
            clrMm: 10,
            heightMm: 100,
            angleDeg: angle,
            legAMm: 100,
            legBMm: 100))!;
        expect(o.travelMm / 100, closeTo(factor, 0.001), reason: '$angle');
      }
    });

    test('90°: postęp 0, między gięciami = H', () {
      final o = computeTubeOffset(const TubeOffsetInput(
          clrMm: 20, heightMm: 100, angleDeg: 90, legAMm: 100, legBMm: 100))!;
      expect(o.advanceMm, 0);
      expect(o.travelMm, closeTo(100, 1e-9));
      expect(o.shrinkMm, closeTo(100, 1e-9));
    });

    test('przestrzenna: rise 300 + spread 400 → 500, travel 707,1 przy 45°',
        () {
      final o = computeTubeOffset(const TubeOffsetInput(
          clrMm: 38,
          heightMm: 300,
          spreadMm: 400,
          angleDeg: 45,
          legAMm: 200,
          legBMm: 200))!;
      expect(o.trueOffsetMm, closeTo(500, 1e-9));
      expect(o.travelMm, closeTo(707.107, 1e-3));
      // Ta sama definicja obrotu co w narzędziu „Rolling offset” dla rur.
      expect(
          o.rollFromVerticalDeg, closeTo(rollFromVerticalDeg(300, 400), 1e-12));
      expect(o.rollFromVerticalDeg, closeTo(53.13, 0.005));
    });

    test('błędne dane odsadzki → komunikaty, bez wyniku', () {
      List<TubeBendProblemKind> kinds(TubeOffsetInput i) =>
          i.problems.map((p) => p.kind).toList();
      expect(
          kinds(const TubeOffsetInput(
              clrMm: 38, heightMm: 0, angleDeg: 45, legAMm: 1, legBMm: 1)),
          [TubeBendProblemKind.offsetHeight]);
      expect(
          kinds(const TubeOffsetInput(
              clrMm: 38, heightMm: 100, angleDeg: 120, legAMm: 1, legBMm: 1)),
          [TubeBendProblemKind.angle]);
      expect(
          kinds(const TubeOffsetInput(
              clrMm: 38,
              heightMm: 100,
              spreadMm: -5,
              angleDeg: 45,
              legAMm: 1,
              legBMm: 1)),
          [TubeBendProblemKind.offsetSpread]);
      expect(
          computeTubeOffset(const TubeOffsetInput(
              clrMm: 38,
              heightMm: double.nan,
              angleDeg: 45,
              legAMm: 100,
              legBMm: 100)),
          isNull);
    });
  });

  group('rurka z wieloma gięciami', () {
    // CLR 38; odcinki 150 / 200 / 250 / 120 do przecięcia osi; 90°, 45°, 90°.
    const input = TubeRunInput(
      clrMm: 38,
      segmentsMm: [150, 200, 250, 120],
      anglesDeg: [90, 45, 90],
    );

    test('3 gięcia: długość cięcia i znaczniki policzone ręcznie', () {
      final r = computeTubeRun(input)!;
      // Σ odcinków 720; Σ zysku 16,3097 + 1,6351 + 16,3097 = 34,2545.
      expect(r.totalSegmentsMm, 720);
      expect(r.totalGainMm, closeTo(34.2545, 1e-4));
      expect(r.developedMm, closeTo(685.7455, 1e-4));
      expect(r.cutLengthMm(TubeUnit.mm), 686);

      // Wierzchołki na prostej rurce: 150; 150 + 200 − 16,3097 = 333,6903;
      // 333,6903 + 250 − 1,6351 = 582,0552.
      expect(r.bends.map((b) => b.vertexMm).toList(), [
        closeTo(150, 1e-9),
        closeTo(333.6903, 1e-4),
        closeTo(582.0552, 1e-4),
      ]);
      // Początki łuków: 150 − 38 = 112; 333,6903 − 15,7401 = 317,9501;
      // 582,0552 − 38 = 544,0552.
      expect(r.bends.map((b) => b.arcStartMm).toList(), [
        closeTo(112, 1e-9),
        closeTo(317.9501, 1e-4),
        closeTo(544.0552, 1e-4),
      ]);
      // Końce łuków: 112 + 59,6903; 317,9501 + 29,8451; 544,0552 + 59,6903.
      expect(r.bends.map((b) => b.arcEndMm).toList(), [
        closeTo(171.6903, 1e-4),
        closeTo(347.7953, 1e-4),
        closeTo(603.7455, 1e-4),
      ]);
      // Środek łuku 2 (45°): 317,9501 + 29,8451 / 2 = 332,8727.
      expect(r.bends[1].arcMiddleMm, closeTo(332.8727, 1e-4));
      // Znaczniki do najbliższych 0,5 mm: 112 / 318 / 544.
      expect(r.bends.map((b) => roundMarkMm(b.markMm, TubeUnit.mm)).toList(),
          [112, 318, 544]);
      // Proste: 150 − 38; 200 − 38 − 15,74; 250 − 15,74 − 38; 120 − 38.
      expect(r.straightsMm, [
        closeTo(112, 1e-9),
        closeTo(146.2599, 1e-4),
        closeTo(196.2599, 1e-4),
        closeTo(82, 1e-9),
      ]);
      // Ostatnia prosta kończy się na długości rozwiniętej.
      expect(r.bends.last.arcEndMm + r.straightsMm.last,
          closeTo(r.developedMm, 1e-9));
      expect(r.warnings, isEmpty);
    });

    test('obrót płaszczyzny i dogięcie nie zmieniają długości ani znaczników',
        () {
      final base = computeTubeRun(input)!;
      final other = computeTubeRun(const TubeRunInput(
        clrMm: 38,
        segmentsMm: [150, 200, 250, 120],
        anglesDeg: [90, 45, 90],
        rotationsDeg: [0, 180, -90],
        springbackDeg: 3,
      ))!;
      expect(other.developedMm, base.developedMm);
      for (var k = 0; k < 3; k++) {
        expect(other.bends[k].markMm, base.bends[k].markMm);
        expect(other.bends[k].vertexMm, base.bends[k].vertexMm);
      }
      expect(other.bends.map((b) => b.bendToDeg), [93, 48, 93]);
      expect(other.bends.map((b) => b.rotationDeg), [0, 180, 270]);
    });

    test('przesunięcie znacznika giętarki przesuwa tylko znaczniki', () {
      final r = computeTubeRun(const TubeRunInput(
        clrMm: 38,
        segmentsMm: [150, 200, 250, 120],
        anglesDeg: [90, 45, 90],
        markerOffsetMm: 38,
      ))!;
      // +38 przy 90° = znacznik w wierzchołku (jak kreska Swagelok dla 90°).
      expect(r.bends[0].markMm, closeTo(150, 1e-9));
      expect(r.bends[0].arcStartMm, closeTo(112, 1e-9));
      expect(r.developedMm, closeTo(685.7455, 1e-4));
      final off = computeTubeRun(const TubeRunInput(
        clrMm: 38,
        segmentsMm: [150, 200, 250, 120],
        anglesDeg: [90, 45, 90],
        markerOffsetMm: -200,
      ))!;
      expect(
          off.warnings
              .where((w) => w.kind == TubeBendWarningKind.markOutsideTube),
          hasLength(1));
      expect(off.feasible, isTrue);
    });

    test('nakładające się łuki → ostrzeżenie blokujące', () {
      // 60 < 38 + 38: prosta 60 − 76 = −16.
      final r = computeTubeRun(const TubeRunInput(
          clrMm: 38, segmentsMm: [100, 60, 100], anglesDeg: [90, 90]))!;
      final w = r.warnings.single;
      expect(w.kind, TubeBendWarningKind.arcsOverlap);
      expect(w.index, 2);
      expect(w.straightMm, closeTo(-16, 1e-9));
      expect(w.blocking, isTrue);
      expect(r.feasible, isFalse);
      // Dokładnie styczne łuki (76 = 38 + 38) to jeszcze nie zachodzenie.
      final touching = computeTubeRun(const TubeRunInput(
          clrMm: 38, segmentsMm: [100, 76, 100], anglesDeg: [90, 90]))!;
      expect(touching.warnings, isEmpty);
    });

    test('łuk poza końcem rurki → ostrzeżenie blokujące', () {
      final r = computeTubeRun(TubeRunInput.single(
          clrMm: 38, angleDeg: 90, legAMm: 30, legBMm: 100))!;
      expect(r.warnings.single.kind, TubeBendWarningKind.arcPastEnd);
      expect(r.warnings.single.index, 1);
      expect(r.feasible, isFalse);
    });

    test('prosta krótsza niż uchwyt giętarki → ostrzeżenie, wynik zostaje', () {
      final r = computeTubeRun(const TubeRunInput(
          clrMm: 38,
          segmentsMm: [50, 90, 100],
          anglesDeg: [90, 90],
          minStraightMm: 20))!;
      // Początek: 50 − 38 = 12 < 20; środek: 90 − 76 = 14 < 20; koniec 62.
      expect(r.warnings.map((w) => (w.kind, w.index)), [
        (TubeBendWarningKind.endStraightTooShort, 1),
        (TubeBendWarningKind.straightTooShort, 2),
      ]);
      expect(r.warnings.first.straightMm, closeTo(12, 1e-9));
      expect(r.warnings.first.requiredMm, 20);
      expect(r.feasible, isTrue);
    });
  });

  group('błędne dane → komunikat, bez wyniku', () {
    TubeRunInput withAngle(double a) =>
        TubeRunInput.single(clrMm: 38, angleDeg: a, legAMm: 200, legBMm: 150);

    test('kąt 0 / 180 / ujemny / pusty', () {
      for (final a in [0.0, 180.0, -45.0, double.nan, 200.0]) {
        expect(withAngle(a).problems,
            [const TubeBendProblem(TubeBendProblemKind.angle, 1)],
            reason: '$a');
        expect(computeTubeRun(withAngle(a)), isNull, reason: '$a');
      }
      expect(tubeBendAngleOk(179.9), isTrue);
      expect(tubeBendAngleOk(0.1), isTrue);
    });

    test('puste pola i CLR', () {
      final i = TubeRunInput(
          clrMm: 0,
          segmentsMm: const [double.nan, 100, -5],
          anglesDeg: const [90, 45],
          rotationsDeg: const [0, double.nan],
          minStraightMm: -1,
          markerOffsetMm: double.nan,
          springbackDeg: 45);
      expect(i.problems, [
        const TubeBendProblem(TubeBendProblemKind.radius),
        const TubeBendProblem(TubeBendProblemKind.segment, 1),
        const TubeBendProblem(TubeBendProblemKind.segment, 3),
        const TubeBendProblem(TubeBendProblemKind.rotation, 2),
        const TubeBendProblem(TubeBendProblemKind.minStraight),
        const TubeBendProblem(TubeBendProblemKind.markerOffset),
        const TubeBendProblem(TubeBendProblemKind.springback),
      ]);
      expect(computeTubeRun(i), isNull);
    });

    test('liczba gięć: 0 i ponad limit', () {
      expect(
          const TubeRunInput(clrMm: 38, segmentsMm: [100], anglesDeg: [])
              .problems
              .map((p) => p.kind),
          contains(TubeBendProblemKind.bendCount));
      expect(
          TubeRunInput(
            clrMm: 38,
            segmentsMm: List.filled(kMaxTubeBends + 2, 200),
            anglesDeg: List.filled(kMaxTubeBends + 1, 30),
          ).problems.map((p) => p.kind),
          contains(TubeBendProblemKind.bendCount));
    });
  });

  group('zaokrąglenie i jednostki', () {
    test('długość cięcia zawsze w górę — rurka nigdy za krótka', () {
      final rnd = math.Random(7);
      for (final unit in TubeUnit.values) {
        for (var n = 0; n < 2000; n++) {
          final v = rnd.nextDouble() * 3000;
          final cut = roundCutLengthUpMm(v, unit);
          expect(cut, greaterThanOrEqualTo(v - 1e-6), reason: '$unit $v');
          expect(cut - v, lessThan(unit.stepMm + 1e-9), reason: '$unit $v');
        }
      }
      // Szum zmiennoprzecinkowy nie dokłada całego kroku.
      expect(roundCutLengthUpMm(238.0000000001, TubeUnit.mm), 238);
      expect(roundCutLengthUpMm(238.01, TubeUnit.mm), 238.5);
      expect(roundCutLengthUpMm(237.6473, TubeUnit.mm), 238);
    });

    test('znaczniki do najbliższego kroku', () {
      expect(roundMarkMm(317.9501, TubeUnit.mm), 318);
      expect(roundMarkMm(317.74, TubeUnit.mm), 317.5);
      expect(
          roundMarkMm(25.4 * 3.2, TubeUnit.inch) / 25.4, closeTo(3.1875, 1e-9));
    });

    test('cale ↔ mm: ten sam wynik, krok 1/32" w calach', () {
      // CLR 1,5", 90°, ramiona 6" + 4": zysk 1,5·(2 − π/2) = 0,6438".
      final inch = computeTubeRun(TubeRunInput.single(
          clrMm: 1.5 * kMmPerInch,
          angleDeg: 90,
          legAMm: 6 * kMmPerInch,
          legBMm: 4 * kMmPerInch))!;
      expect(inch.bends.single.geometry.gainMm / kMmPerInch,
          closeTo(0.6438, 1e-4));
      expect(inch.developedMm / kMmPerInch, closeTo(9.3562, 1e-4));
      // 9,3562" → w górę do 1/32" = 9 12/32 = 9 3/8".
      expect(
          inch.cutLengthMm(TubeUnit.inch) / kMmPerInch, closeTo(9.375, 1e-9));
      expect(formatInchFraction(inch.cutLengthMm(TubeUnit.inch) / kMmPerInch),
          '9 3/8"');
      // Ta sama rurka w mm: 237,647 → 238.
      expect(inch.developedMm, closeTo(237.647, 1e-3));
      expect(inch.cutLengthMm(TubeUnit.mm), 238);
      // Wynik w mm nie zależy od jednostki, w której wpisano dane.
      final mm = computeTubeRun(TubeRunInput.single(
          clrMm: 38.1, angleDeg: 90, legAMm: 152.4, legBMm: 101.6))!;
      expect(mm.developedMm, closeTo(inch.developedMm, 1e-9));
    });

    test('ułamki cala', () {
      expect(formatInchFraction(9.375), '9 3/8"');
      expect(formatInchFraction(0.3125), '5/16"');
      expect(formatInchFraction(12), '12"');
      expect(formatInchFraction(-0.5), '-1/2"');
      expect(formatInchFraction(0.001), '0"');
      expect(formatInchFraction(2.97), '2 31/32"');
      expect(formatInchFraction(2.99), '3"');
      expect(formatInchFraction(double.nan), '—');
    });
  });
}
