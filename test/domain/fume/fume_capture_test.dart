// Kalkulator zasięgu odciągu (DallaValle): zasięg w dół do cm, wymagana
// wydajność w górę, kołnierz 0,75, granica ważności 1,5·D, szczelina,
// minimum prędkości uchwycenia (tylko zaostrzalne), jednostki bez wpływu
// na werdykt, puste i nieczytelne pola.
//
// Liczby (policzone niezależnie):
//  • Q 1200 m³/h, D 300 mm, bez kołnierza, V 0,5 → X = 0,2441 m → 24 cm;
//    z kołnierzem → 0,2860 m → 28 cm; granica 1,5·D = 45 cm;
//  • Q 1000 m³/h, D 150 mm → X = 0,2319 m > 1,5·D = 0,225 m → poza
//    zakresem; bezpiecznie 22 cm;
//  • X 20 cm, D 300 mm, V 0,5 → Q = 0,235343 m³/s = 847,23 m³/h → 848 m³/h,
//    235,34 l/s → 236 l/s;
//  • Q 100 m³/h, D 300 mm → Q/V < A → zasięg 0 → za mała wydajność.

import 'package:flutter_test/flutter_test.dart';

import 'package:cut_list_app/domain/fume/fume_capture.dart';
import 'package:cut_list_app/domain/fume/fume_hazards.dart';
import 'package:cut_list_app/domain/fume/fume_sources.dart';

FumeCaptureResult _calc({
  double? flow = 1200,
  FumeFlowUnit flowUnit = FumeFlowUnit.m3h,
  FumeHoodShape shape = FumeHoodShape.round,
  double? diameter = 300,
  double? width,
  double? height,
  FumeLengthUnit lengthUnit = FumeLengthUnit.mm,
  bool flanged = false,
  double? v = 0.5,
  double minV = kFumeCaptureMinMs,
  double? distance,
}) =>
    computeFumeCapture(FumeCaptureInput(
      flow: flow,
      flowUnit: flowUnit,
      shape: shape,
      diameter: diameter,
      width: width,
      height: height,
      lengthUnit: lengthUnit,
      flanged: flanged,
      captureVelocity: v,
      minCaptureVelocity: minV,
      distance: distance,
    ))!;

void main() {
  group('zasięg z wydajności', () {
    test('otwór swobodny: Q 1200 m³/h, D 300 mm, V 0,5 → 24 cm (w dół)', () {
      final r = _calc();
      expect(r.reachM, closeTo(0.24413, 1e-5));
      expect(r.reachCm, 24);
      expect(r.validityLimitCm, 45);
      expect(r.reachState, FumeReachState.within);
    });

    test('sam zasięg bez odległości X to informacja, nie „ok”', () {
      final r = _calc();
      expect(r.distanceMissing, isTrue);
      expect(r.level, FumeLevel.incomplete);
      // Rzeczywista odległość 20 cm w zasięgu (24 cm) — dopiero teraz ok.
      final x = _calc(distance: 200);
      expect(x.distanceMissing, isFalse);
      expect(x.flowSufficient, isTrue);
      expect(x.level, FumeLevel.ok);
    });

    test('błędna, niepusta odległość nie znika po cichu — nigdy „ok”', () {
      // Za daleko (ponad limit pola 3 m) → stop.
      final far = _calc(distance: 5000);
      expect(far.distanceProblem, FumeCaptureProblem.distanceTooFar);
      expect(far.distanceM, isNull);
      expect(far.level, FumeLevel.stop);
      // Nieczytelna („abc” → NaN) i zero → brak oceny.
      for (final bad in [double.nan, 0.0, -20.0]) {
        final r = _calc(distance: bad);
        expect(r.distanceProblem, FumeCaptureProblem.distanceInvalid,
            reason: '$bad');
        expect(r.level, FumeLevel.incomplete, reason: '$bad');
      }
      // Bez wydajności też: za daleko → stop, nie „brak wyniku”.
      final noQ = _calc(flow: null, distance: 5000);
      expect(noQ.level, FumeLevel.stop);
      // Za mała wydajność wygrywa z błędną odległością (gorsza ocena).
      expect(_calc(flow: 100, distance: double.nan).level, FumeLevel.stop);
    });

    test('kołnierz: ta sama wydajność sięga dalej (Q = 0,75·V·…) → 28 cm', () {
      final r = _calc(flanged: true);
      expect(r.coefficient, kFumeFlangeFactor);
      expect(r.reachM, closeTo(0.28604, 1e-5));
      expect(r.reachCm, 28);
    });

    test('wyższa prędkość uchwycenia → bliżej (V 1,0 → 16 cm)', () {
      final r = _calc(v: 1.0);
      expect(r.reachCm, 16);
    });

    test('poza zakresem równania (X > 1,5·D) → ostrożnie, przyjmij bliżej', () {
      final r = _calc(flow: 1000, diameter: 150);
      expect(r.reachM, closeTo(0.23192, 1e-5));
      expect(r.reachCm, 23);
      expect(r.validityLimitCm, 22); // 22,5 cm w dół
      expect(r.reachState, FumeReachState.beyondValidity);
      expect(r.level, isNot(FumeLevel.ok));
      expect(r.safeReachCm, 22);
      // Z rzeczywistą odległością poza 1,5·D (25 cm) i wystarczającą Q —
      // ostrożnie, nie zielono.
      final x = _calc(flow: 2000, diameter: 150, distance: 250);
      expect(x.flowSufficient, isTrue);
      expect(x.distanceWithinValidity, isFalse);
      expect(x.level, FumeLevel.caution);
    });

    test('za mała wydajność — prędkość nie osiągnięta nawet przy otworze', () {
      final r = _calc(flow: 100);
      expect(r.reachM, 0);
      expect(r.reachState, FumeReachState.tooLowFlow);
      expect(r.level, FumeLevel.stop);
    });

    test('prostokąt: granica ważności od KRÓTSZEGO boku', () {
      final r = _calc(
          shape: FumeHoodShape.rectangular,
          diameter: null,
          width: 200,
          height: 100,
          flow: 800);
      expect(r.characteristicM, closeTo(0.1, 1e-12));
      expect(r.areaM2, closeTo(0.02, 1e-12));
      expect(r.reachCm, 20);
      expect(r.validityLimitCm, 15);
      expect(r.reachState, FumeReachState.beyondValidity);
      expect(r.level, isNot(FumeLevel.ok));
    });

    test('szczelina (stosunek boków < 0,2) — równanie nie dotyczy, bez wyniku',
        () {
      final r = _calc(
          shape: FumeHoodShape.rectangular,
          diameter: null,
          width: 500,
          height: 50,
          distance: 10);
      expect(r.isSlot, isTrue);
      expect(r.reachM, isNull);
      expect(r.requiredFlowM3s, isNull);
      expect(r.level, FumeLevel.caution);
      // Stosunek dokładnie 0,2 to jeszcze nie szczelina.
      final edge = _calc(
          shape: FumeHoodShape.rectangular,
          diameter: null,
          width: 500,
          height: 100);
      expect(edge.isSlot, isFalse);
    });
  });

  group('wymagana wydajność przy zadanej odległości', () {
    test('X 20 cm, D 300 mm → 848 m³/h / 236 l/s (w górę)', () {
      final cm = _calc(
          flow: null,
          diameter: 30,
          distance: 20,
          lengthUnit: FumeLengthUnit.cm);
      expect(cm.requiredFlowM3s, closeTo(0.2353429, 1e-7));
      expect(cm.requiredFlowDisplay(FumeFlowUnit.m3h), 848);
      expect(cm.requiredFlowDisplay(FumeFlowUnit.ls), 236);
      // Bez wydajności nie ma z czym porównać — to nie jest „ok”.
      expect(cm.level, FumeLevel.incomplete);
    });

    test('Q równa wymaganej przechodzi, o 1 m³/h mniej — stop', () {
      final ok = _calc(
          flow: 848, diameter: 30, distance: 20, lengthUnit: FumeLengthUnit.cm);
      expect(ok.flowSufficient, isTrue);
      expect(ok.level, FumeLevel.ok);
      expect(ok.velocityAtDistanceDisplay, greaterThanOrEqualTo(0.5));
      final low = _calc(
          flow: 847, diameter: 30, distance: 20, lengthUnit: FumeLengthUnit.cm);
      expect(low.flowSufficient, isFalse);
      expect(low.level, FumeLevel.stop);
      expect(low.velocityAtDistanceDisplay, lessThan(0.5));
    });

    test('odległość ponad 1,5·D — nawet przy wystarczającej Q nie zielone', () {
      final r = _calc(
          flow: 5000,
          diameter: 15,
          distance: 30,
          lengthUnit: FumeLengthUnit.cm);
      expect(r.flowSufficient, isTrue);
      expect(r.distanceWithinValidity, isFalse);
      expect(r.level, FumeLevel.caution);
    });

    test('prędkość przy łuku ponad 1,0 m/s — ryzyko dla osłony gazowej', () {
      final r = _calc(
          flow: 1500, diameter: 10, distance: 5, lengthUnit: FumeLengthUnit.cm);
      expect(r.velocityAtDistanceMs, greaterThan(kFumeShieldDraughtMs));
      expect(r.shieldDraughtRisk, isTrue);
      final calm = _calc(
          flow: 848, diameter: 30, distance: 20, lengthUnit: FumeLengthUnit.cm);
      expect(calm.shieldDraughtRisk, isFalse);
    });
  });

  group('jednostki nie zmieniają werdyktu', () {
    test('m³/h ↔ l/s ↔ cfm, mm ↔ cm — identyczne wyniki w SI', () {
      final cases = [
        (1800.0, FumeFlowUnit.m3h, 150.0, FumeLengthUnit.mm, 20.0 * 10),
        (500.0, FumeFlowUnit.ls, 15.0, FumeLengthUnit.cm, 20.0),
      ];
      final results = [
        for (final (q, qu, d, lu, x) in cases)
          _calc(flow: q, flowUnit: qu, diameter: d, lengthUnit: lu, distance: x)
      ];
      final a = results[0];
      final b = results[1];
      expect(a.flowM3s, b.flowM3s);
      expect(a.reachM, b.reachM);
      expect(a.requiredFlowM3s, b.requiredFlowM3s);
      expect(a.level, b.level);
      expect(a.reachCm, b.reachCm);
      expect(a.safeReachCm, b.safeReachCm);
    });

    test('ułamkowe wymiary: 123,4 mm ≡ 12,34 cm — ten sam zasięg', () {
      for (final q in [600.0, 900.0, 1234.5, 2000.0]) {
        final mm = _calc(flow: q, diameter: 123.4);
        final cm =
            _calc(flow: q, diameter: 12.34, lengthUnit: FumeLengthUnit.cm);
        expect(mm.reachM, cm.reachM, reason: '$q');
        expect(mm.level, cm.level, reason: '$q');
      }
    });

    test('cfm: 1 ft³/min = 0,028316846592/60 m³/s', () {
      expect(FumeFlowUnit.cfm.toM3s(1), closeTo(0.0004719474432, 1e-15));
      final cfm = _calc(flow: 1000, flowUnit: FumeFlowUnit.cfm);
      final m3h = _calc(flow: 1000 * 0.028316846592 * 60);
      expect(cfm.reachCm, m3h.reachCm);
    });

    test('zmiana jednostki pola: długość dokładnie, wydajność w dół', () {
      expect(convertFumeLength(150, FumeLengthUnit.mm, FumeLengthUnit.cm), 15);
      expect(convertFumeLength(12.34, FumeLengthUnit.cm, FumeLengthUnit.mm),
          123.4);
      expect(convertFumeFlow(1000, FumeFlowUnit.m3h, FumeFlowUnit.ls), 277.77);
      expect(convertFumeFlow(500, FumeFlowUnit.ls, FumeFlowUnit.m3h), 1800);
      // Po przeliczeniu w dół wydajność nie rośnie — werdykt nie łagodnieje.
      final before = _calc(flow: 1000, diameter: 300, distance: 200);
      final after = _calc(
          flow: convertFumeFlow(1000, FumeFlowUnit.m3h, FumeFlowUnit.ls),
          flowUnit: FumeFlowUnit.ls,
          diameter: 300,
          distance: 200);
      expect(after.flowM3s!, lessThanOrEqualTo(before.flowM3s!));
    });
  });

  group('prędkość uchwycenia — tylko zaostrzalna', () {
    test('domyślnie 0,5 m/s; poniżej minimum — błąd, bez wyniku', () {
      expect(kFumeCaptureDefaultMs, 0.5);
      expect(kFumeCaptureMinMs, 0.5);
      const low =
          FumeCaptureInput(flow: 1200, diameter: 300, captureVelocity: 0.4);
      expect(fumeCaptureProblems(low),
          contains(FumeCaptureProblem.velocityBelowMin));
      expect(computeFumeCapture(low), isNull);
      // Równe minimum — przyjęte.
      expect(
          computeFumeCapture(const FumeCaptureInput(
              flow: 1200, diameter: 300, captureVelocity: 0.5)),
          isNotNull);
    });

    test('szlifowanie: minimum wyższe (ACGIH) — 1,0 m/s odrzucone', () {
      final minG = fumeCaptureMinFor(FumeProcess.grinding);
      expect(minG, kFumeCaptureGrindingMinMs);
      expect(minG, greaterThan(kFumeCaptureMinMs));
      final i = FumeCaptureInput(
          flow: 1200,
          diameter: 300,
          captureVelocity: 1.0,
          minCaptureVelocity: minG);
      expect(fumeCaptureProblems(i),
          contains(FumeCaptureProblem.velocityBelowMin));
      expect(fumeCaptureMinFor(FumeProcess.mma), kFumeCaptureMinMs);
      expect(fumeCaptureMinFor(null), kFumeCaptureMinMs);
    });
  });

  group('puste i nieczytelne pola ≠ wynik', () {
    test('bez wymiaru otworu — brak wyniku', () {
      const i = FumeCaptureInput(flow: 1200);
      expect(
          fumeCaptureProblems(i), contains(FumeCaptureProblem.openingMissing));
      expect(computeFumeCapture(i), isNull);
    });

    test('ani wydajności, ani odległości — nic do liczenia', () {
      const i = FumeCaptureInput(diameter: 300);
      expect(fumeCaptureProblems(i),
          contains(FumeCaptureProblem.nothingToCompute));
      expect(computeFumeCapture(i), isNull);
    });

    test('nieczytelna wydajność — błąd pola, nie zero', () {
      const i = FumeCaptureInput(flow: double.nan, diameter: 300);
      expect(fumeCaptureProblems(i), contains(FumeCaptureProblem.flowInvalid));
      expect(computeFumeCapture(i), isNull);
      const neg = FumeCaptureInput(flow: -5, diameter: 300, distance: 200);
      // Zła wydajność wyłącza tylko jej część — wymagana Q nadal liczona.
      final r = computeFumeCapture(neg)!;
      expect(r.flowM3s, isNull);
      expect(r.requiredFlowM3s, isNotNull);
    });

    test('limity pól: wydajność, otwór, odległość, prędkość', () {
      expect(
          fumeCaptureProblems(
              const FumeCaptureInput(flow: 200000, diameter: 300)),
          contains(FumeCaptureProblem.flowTooHigh));
      expect(
          fumeCaptureProblems(
              const FumeCaptureInput(flow: 1000, diameter: 3000)),
          contains(FumeCaptureProblem.openingTooLarge));
      expect(
          fumeCaptureProblems(const FumeCaptureInput(
              flow: 1000, diameter: 300, distance: 5000)),
          contains(FumeCaptureProblem.distanceTooFar));
      expect(
          fumeCaptureProblems(const FumeCaptureInput(
              flow: 1000, diameter: 300, captureVelocity: 50)),
          contains(FumeCaptureProblem.velocityTooHigh));
    });
  });

  test('stałe równania wg ACGIH: kołnierz 0,75, X ≤ 1,5·D, W/L ≥ 0,2', () {
    expect(kFumeFlangeFactor, 0.75);
    expect(kFumeDallaValleMaxXOverD, 1.5);
    expect(kFumeMinAspectRatio, 0.2);
    expect(kFumeShieldDraughtMs, 1.0);
  });

  group('zaokrąglenia w stronę bezpieczeństwa', () {
    test('zasięg w dół do cm, wymagana wydajność w górę', () {
      expect(fumeFloorCm(0.2999), 29);
      expect(fumeFloorCm(0.3), 30); // 0,3·100 = 30,000000000000004
      expect(fumeCeil(847.2), 848);
      expect(fumeCeil(848.0000000000001), 848);
      expect(fumeCeil(848), 848);
    });
  });
}
