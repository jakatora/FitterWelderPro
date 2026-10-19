// Rolling offset (lib/domain/fitter/rolling_offset.dart).
//
// Wartości referencyjne przepisane z logiki ekranu
// lib/screens/rolling_offset_screen.dart sprzed refaktoru (_calculate,
// rollFromVerticalDeg, rollingCutLengthMm):
//   True offset = √(Rise² + Spread²)     300/400 → 500
//   Multiplier  = 1 / sin θ              45° → 1,4142
//   Travel      = True offset × Multiplier → 707,1
//   Run         = True offset / tan θ    (90° → dokładnie 0)
//   Obrót od pionu = atan(Spread / Rise) = 53,13°, od poziomu 36,87°
//   Kąt: > 5° i < 89° albo dokładnie 90°
//   Cięcie = Travel − 2·T − 2·szczelina (T: kolano LR ASME B16.9)
//
// Test „zgodność z dawnym ekranem” porównuje bit w bit z kopią starego kodu.

import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';

import 'package:cut_list_app/domain/fitter/rolling_offset.dart';
import 'package:cut_list_app/services/takeout_catalog.dart';

// ── Kopia logiki ekranu sprzed refaktoru (wyrocznia) ─────────────────────────
// (offset, multiplier, travel, run, obrót od pionu, obrót od poziomu)

typedef _Legacy = (double, double, double, double, double, double);

_Legacy? _legacy(double rise, double spread, double angleDeg) {
  if (!rise.isFinite || !spread.isFinite || rise <= 0 || spread <= 0) {
    return null;
  }
  if (!angleDeg.isFinite ||
      angleDeg <= 5 ||
      (angleDeg >= 89 && angleDeg != 90)) {
    return null;
  }
  final angleRad = angleDeg * math.pi / 180.0;
  final trueOffset = math.sqrt(rise * rise + spread * spread);
  final multiplier = 1.0 / math.sin(angleRad);
  final travel = trueOffset * multiplier;
  final run = angleDeg == 90 ? 0.0 : trueOffset / math.tan(angleRad);
  if (![trueOffset, multiplier, travel, run].every((v) => v.isFinite)) {
    return null;
  }
  final rollV = math.atan2(spread, rise) * 180.0 / math.pi;
  return (trueOffset, multiplier, travel, run, rollV, 90.0 - rollV);
}

_Legacy? _tuple(RollingOffsetResult? r) => r == null
    ? null
    : (
        r.trueOffsetMm,
        r.multiplier,
        r.travelMm,
        r.runMm,
        r.rollFromVerticalDeg,
        r.rollFromHorizontalDeg
      );

const _sizes = <double>[
  0.1,
  1,
  10,
  250,
  300,
  400,
  600,
  12345.6,
  1e150,
  1e200,
  0,
  -5,
  double.infinity,
  double.nan,
];

const _angles = <double>[
  0,
  5,
  5.0001,
  11.25,
  22.5,
  30,
  45,
  60,
  88.9,
  89,
  89.5,
  90,
  91,
  -45,
  double.nan,
  double.infinity,
];

void main() {
  group('wartości referencyjne', () {
    test('rise 300 / spread 400 / 45° (przykład ekranu)', () {
      final r = rollingOffset(riseMm: 300, spreadMm: 400, angleDeg: 45)!;
      expect(r.trueOffsetMm, 500.0);
      expect(r.multiplier, 1.0 / math.sin(math.pi / 4));
      expect(r.multiplier.toStringAsFixed(4), '1.4142');
      expect(r.travelMm, closeTo(707.1068, 1e-4));
      expect(r.travelMm.toStringAsFixed(1), '707.1');
      expect(r.runMm, closeTo(500, 1e-9));
      expect(r.runMm.toStringAsFixed(1), '500.0');
      expect(r.rollFromVerticalDeg, closeTo(53.130102, 1e-6));
      expect(r.rollFromHorizontalDeg, closeTo(36.869898, 1e-6));
      expect(r.rollFromVerticalDeg.toStringAsFixed(1), '53.1');
      expect(r.rollFromHorizontalDeg.toStringAsFixed(1), '36.9');
      expect(r.angleDeg, 45.0);
      expect(r.multiplierWarning, isFalse);
    });

    test('rise 250 / spread 600 / 30° → 650, travel 1300', () {
      final r = rollingOffset(riseMm: 250, spreadMm: 600, angleDeg: 30)!;
      expect(r.trueOffsetMm, 650.0);
      expect(r.travelMm, closeTo(1300, 1e-9));
      expect(r.travelMm.toStringAsFixed(1), '1300.0');
      expect(r.rollFromVerticalDeg.toStringAsFixed(1), '67.4');
      expect(r.rollFromHorizontalDeg.toStringAsFixed(1), '22.6');
    });

    test('90°: run dokładnie 0, multiplier 1', () {
      final r = rollingOffset(riseMm: 300, spreadMm: 400, angleDeg: 90)!;
      expect(r.runMm, 0.0);
      expect(r.multiplier, 1.0);
      expect(r.travelMm, 500.0);
    });

    test('multiplier > 10 → ostrzeżenie (bardzo płaskie kolano)', () {
      final r = rollingOffset(riseMm: 300, spreadMm: 400, angleDeg: 5.5)!;
      expect(r.multiplier, greaterThan(10));
      expect(r.multiplierWarning, isTrue);
    });

    test('dotychczasowe funkcje', () {
      expect(rollFromVerticalDeg(250, 600),
          closeTo(math.atan(600 / 250) * 180 / math.pi, 1e-9));
      expect(rollFromVerticalDeg(300, 400), closeTo(53.13, 0.005));
      expect(rollingCutLengthMm(travelMm: 707.107, takeoutMm: 64, gapMm: 3),
          closeTo(573.107, 1e-9));
      expect(rollingCutLengthMm(travelMm: 100, takeoutMm: 20), 60.0);
    });

    test('zakres kąta jak na ekranie', () {
      expect(rollingOffsetAngleValid(45), isTrue);
      expect(rollingOffsetAngleValid(5.0001), isTrue);
      expect(rollingOffsetAngleValid(88.9), isTrue);
      expect(rollingOffsetAngleValid(90), isTrue);
      expect(rollingOffsetAngleValid(5), isFalse);
      expect(rollingOffsetAngleValid(89), isFalse);
      expect(rollingOffsetAngleValid(89.5), isFalse);
      expect(rollingOffsetAngleValid(91), isFalse);
      expect(rollingOffsetAngleValid(double.nan), isFalse);
    });
  });

  group('długość cięcia z kolanami ASME B16.9 LR', () {
    test('300/400/45° + DN100, szczelina 3 → T = B = 64, cięcie 573.1', () {
      final r = rollingOffset(riseMm: 300, spreadMm: 400, angleDeg: 45)!;
      final c = rollingOffsetCut(
          travelMm: r.travelMm, angleDeg: 45, dn: 100, gapMm: 3)!;
      expect(c.takeout.mm, 64.0);
      expect(c.takeout.basis, TakeoutBasis.tableB45);
      expect(c.takeout.type, ElbowRadiusType.long15D);
      expect(c.gapMm, 3.0);
      expect(c.cutMm, r.travelMm - 2.0 * 64 - 2.0 * 3);
      expect(c.cutMm.toStringAsFixed(1), '573.1');
      expect(c.elbowsOverlap, isFalse);
    });

    test('250/600/30° + DN100 → T = 152·tan15° = 40.7, cięcie 1218.5', () {
      final r = rollingOffset(riseMm: 250, spreadMm: 600, angleDeg: 30)!;
      final c = rollingOffsetCut(travelMm: r.travelMm, angleDeg: 30, dn: 100)!;
      expect(c.takeout.basis, TakeoutBasis.segment);
      expect(c.takeout.mm.toStringAsFixed(1), '40.7');
      expect(c.cutMm.toStringAsFixed(1), '1218.5');
      expect(c.gapMm, 0.0);
    });

    test('kolana nachodzą → cięcie ≤ 0 z flagą, nie null', () {
      final r = rollingOffset(riseMm: 10, spreadMm: 10, angleDeg: 45)!;
      final c = rollingOffsetCut(travelMm: r.travelMm, angleDeg: 45, dn: 100)!;
      expect(c.cutMm, lessThanOrEqualTo(0));
      expect(c.elbowsOverlap, isTrue);
    });

    test('brak DN w tabeli, zła szczelina albo kąt → null', () {
      expect(rollingOffsetCut(travelMm: 700, angleDeg: 45, dn: 7), isNull);
      expect(rollingOffsetCut(travelMm: 700, angleDeg: 45, dn: 100, gapMm: -1),
          isNull);
      expect(
          rollingOffsetCut(
              travelMm: 700, angleDeg: 45, dn: 100, gapMm: double.nan),
          isNull);
      expect(
          rollingOffsetCut(
              travelMm: 700, angleDeg: 45, dn: 100, gapMm: double.infinity),
          isNull);
      expect(rollingOffsetCut(travelMm: 700, angleDeg: 0, dn: 100), isNull);
      expect(rollingOffsetCut(travelMm: double.nan, angleDeg: 45, dn: 100),
          isNull);
      expect(rollingOffsetCut(travelMm: 0, angleDeg: 45, dn: 100), isNull);
    });
  });

  group('dane nieprawidłowe → null', () {
    test('zero, ujemne, NaN, nieskończoność, kąt poza zakresem', () {
      for (final bad in [0.0, -1.0, double.nan, double.infinity]) {
        expect(rollingOffset(riseMm: bad, spreadMm: 400, angleDeg: 45), isNull,
            reason: 'rise $bad');
        expect(rollingOffset(riseMm: 300, spreadMm: bad, angleDeg: 45), isNull,
            reason: 'spread $bad');
        expect(rollingOffset(riseMm: 300, spreadMm: 400, angleDeg: bad), isNull,
            reason: 'kąt $bad');
      }
      expect(rollingOffset(riseMm: 300, spreadMm: 400, angleDeg: 5), isNull);
      expect(rollingOffset(riseMm: 300, spreadMm: 400, angleDeg: 89), isNull);
    });

    test('przepełnienie → null', () {
      expect(
          rollingOffset(riseMm: 1e200, spreadMm: 1e200, angleDeg: 45), isNull);
    });
  });

  test('zgodność z dawnym ekranem (bit w bit)', () {
    for (final rise in _sizes) {
      for (final spread in _sizes) {
        for (final angle in _angles) {
          expect(
              _tuple(rollingOffset(
                  riseMm: rise, spreadMm: spread, angleDeg: angle)),
              _legacy(rise, spread, angle),
              reason: 'R=$rise S=$spread θ=$angle');
        }
      }
    }
  });
}
