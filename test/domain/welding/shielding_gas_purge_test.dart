// Gaz osłonowy / butle oraz czas formowania (purge).
//
// Gaz — ręcznie: 20 spoin × 5 min × 10 L/min = 1000 L;
//   pre/post (5 s + 10 s) × 20 = 300 s = 5 min × 10 L/min = 50 L → 1050 L.
//   Butla 50 L × 200 bar ≈ 10 000 L (gaz doskonały) → 1050 / 10 000 = 0,105
//   butli. Stary kod dzielił 1050 L przez „50 L gazu” → 21 butli (200× za dużo).
//   Z rezerwą 10 bar: 50 × 190 = 9 500 L → 0,1105 butli.
//
// Purge — ręcznie: OD 60,3 / t 2,0 → ID 56,3 mm; L = 1000 mm
//   V = π·28,15²·1000 / 10⁶ = 2,48947 L; Q = 10 L/min = 0,16667 L/s
//   N = ln(210 000 / 20) = 9,25913;  t = 2,48947 / 0,16667 · 9,25913 = 138,30 s

import 'package:flutter_test/flutter_test.dart';

import 'package:cut_list_app/domain/welding/purge.dart';
import 'package:cut_list_app/domain/welding/shielding_gas.dart';

void main() {
  group('estimateGasConsumption', () {
    test('20 spoin × 5 min × 10 L/min + pre/post 5+10 s = 1050 L', () {
      final g = estimateGasConsumption(
        welds: 20,
        weldMinutes: 5,
        torchLpm: 10,
        preFlowS: 5,
        postFlowS: 10,
      )!;
      expect(g.torchL, closeTo(1000, 1e-9));
      expect(g.prePostFlowL, closeTo(50, 1e-9));
      expect(g.purgeL, 0);
      expect(g.totalL, closeTo(1050, 1e-9));
    });

    test('purge doliczany tylko, gdy podano przepływ i czas', () {
      final g = estimateGasConsumption(
        welds: 10,
        weldMinutes: 2,
        torchLpm: 8,
        purgeLpm: 15,
        purgeMinutes: 3,
      )!;
      // 10·2·8 = 160; purge 10·3·15 = 450
      expect(g.totalL, closeTo(610, 1e-9));
      expect(
        estimateGasConsumption(
          welds: 10,
          weldMinutes: 2,
          torchLpm: 8,
          purgeLpm: 15,
        )!
            .purgeL,
        0,
      );
    });

    test('brak spoin / ujemne → null', () {
      expect(
        estimateGasConsumption(welds: 0, weldMinutes: 5, torchLpm: 10),
        isNull,
      );
      expect(
        estimateGasConsumption(
            welds: 5, weldMinutes: 5, torchLpm: 10, preFlowS: -1),
        isNull,
      );
    });
  });

  group('usableCylinderGasL + cylindersNeeded', () {
    final cases = <({
      double v,
      double p,
      double res,
      double? gas,
      double? bottles,
    })>[
      (v: 50, p: 200, res: 0, gas: 10000, bottles: 0.105),
      (v: 50, p: 200, res: 10, gas: 9500, bottles: 1050 / 9500),
      (v: 50, p: 300, res: 0, gas: 15000, bottles: 0.07),
      (v: 20, p: 200, res: 0, gas: 4000, bottles: 0.2625),
      (v: 50, p: 200, res: 200, gas: null, bottles: null),
      (v: 0, p: 200, res: 0, gas: null, bottles: null),
    ];
    for (final k in cases) {
      test('${k.v} L × ${k.p} bar − ${k.res} bar → ${k.gas} L', () {
        final gas = usableCylinderGasL(
          waterCapacityL: k.v,
          fillPressureBar: k.p,
          reserveBar: k.res,
        );
        if (k.gas == null) {
          expect(gas, isNull);
          return;
        }
        expect(gas, closeTo(k.gas!, 1e-9));
        expect(
          cylindersNeeded(totalGasL: 1050, usableGasPerCylinderL: gas!),
          closeTo(k.bottles!, 1e-9),
        );
      });
    }
  });

  group('estimatePurge', () {
    test('OD 60,3 × 2,0, 1 m, 10 L/min, 210 000 → 20 ppm ≈ 138,3 s', () {
      final r = estimatePurge(
        odMm: 60.3,
        wallMm: 2.0,
        lengthMm: 1000,
        flowLpm: 10,
        initialPpm: 210000,
        targetPpm: 20,
      );
      expect(r.error, isNull);
      expect(r.estimate!.volumeL, closeTo(2.48947, 1e-5));
      expect(r.estimate!.volumeChanges, closeTo(9.25913, 1e-5));
      expect(r.estimate!.timeSec, closeTo(138.302, 1e-3));
    });

    final invalid = <({
      String name,
      double od,
      double t,
      double c0,
      double target,
      PurgeInputError error,
    })>[
      // Stary kod: ln(0) = −∞ → czas ∞ → floor() rzucał wyjątek w build().
      (name: 'cel 0 ppm', od: 60.3, t: 2, c0: 210000, target: 0,
          error: PurgeInputError.target),
      (name: 'C₀ 0 ppm', od: 60.3, t: 2, c0: 0, target: 20,
          error: PurgeInputError.initialConcentration),
      // Stary kod: ujemny czas.
      (name: 'cel ≥ C₀', od: 60.3, t: 2, c0: 100, target: 200,
          error: PurgeInputError.targetNotBelowInitial),
      (name: 'cel = C₀', od: 60.3, t: 2, c0: 100, target: 100,
          error: PurgeInputError.targetNotBelowInitial),
      (name: 'OD ≤ 2t', od: 4, t: 2, c0: 210000, target: 20,
          error: PurgeInputError.geometry),
    ];
    for (final k in invalid) {
      test('${k.name} → ${k.error.name}', () {
        final r = estimatePurge(
          odMm: k.od,
          wallMm: k.t,
          lengthMm: 1000,
          flowLpm: 10,
          initialPpm: k.c0,
          targetPpm: k.target,
        );
        expect(r.estimate, isNull);
        expect(r.error, k.error);
      });
    }
  });
}
