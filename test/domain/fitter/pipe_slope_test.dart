// Spadek rury (lib/domain/fitter/pipe_slope.dart).
//
// Wartości referencyjne przepisane z logiki ekranu
// lib/screens/pipe_slope_screen.dart sprzed refaktoru (_calculate, tryby
// length_to_rise / rise_to_length / slope_from_lr):
//   Wznios  = długość × % / 100          2 % na 5000 mm = 100 mm
//   Długość = wznios / (% / 100)         60 mm przy 1 % = 6000 mm
//   %       = wznios / długość × 100     60 / 6000 = 1 %
//   Kąt     = atan(% / 100)  (tryb „wyznacz %”: atan(wznios / długość))
//   mm/m    = % × 10
//
// Test „zgodność z dawnym ekranem” porównuje bit w bit z kopią starego kodu.

import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';

import 'package:cut_list_app/domain/fitter/pipe_slope.dart';

// ── Kopia logiki ekranu sprzed refaktoru (wyrocznia) ─────────────────────────
// Zwraca (długość, wznios, %, kąt, mm/m) albo null, gdy ekran pokazałby błąd
// danych lub „wynik poza zakresem”.

typedef _Legacy = (double, double, double, double, double);

_Legacy? _legacyLengthToRise(double length, double slope) {
  if (!length.isFinite || !slope.isFinite || length <= 0 || slope <= 0) {
    return null;
  }
  final rise = length * slope / 100.0;
  final angleRad = math.atan(slope / 100.0);
  final angleDeg = angleRad * 180.0 / math.pi;
  final mmPerM = slope * 10.0;
  if (![rise, angleDeg, mmPerM].every((v) => v.isFinite)) return null;
  return (length, rise, slope, angleDeg, mmPerM);
}

_Legacy? _legacyRiseToLength(double rise, double slope) {
  if (!rise.isFinite || !slope.isFinite || rise <= 0 || slope <= 0) {
    return null;
  }
  final length = rise / (slope / 100.0);
  final angleRad = math.atan(slope / 100.0);
  final angleDeg = angleRad * 180.0 / math.pi;
  final mmPerM = slope * 10.0;
  if (![length, angleDeg, mmPerM].every((v) => v.isFinite)) return null;
  return (length, rise, slope, angleDeg, mmPerM);
}

_Legacy? _legacySlopeFromLr(double length, double rise) {
  if (!length.isFinite || !rise.isFinite || length <= 0 || rise <= 0) {
    return null;
  }
  final slope = (rise / length) * 100.0;
  final angleRad = math.atan(rise / length);
  final angleDeg = angleRad * 180.0 / math.pi;
  final mmPerM = slope * 10.0;
  if (![slope, angleDeg, mmPerM].every((v) => v.isFinite)) return null;
  return (length, rise, slope, angleDeg, mmPerM);
}

_Legacy? _tuple(PipeSlopeResult? r) =>
    r == null ? null : (r.lengthMm, r.riseMm, r.slopePct, r.angleDeg, r.mmPerM);

const _grid = <double>[
  0.001,
  0.5,
  0.67,
  1,
  2,
  3.3,
  60,
  100,
  5000,
  6000,
  12345.6,
  1e-300,
  1e10,
  1e306,
  1e308,
  0,
  -0.0,
  -1,
  double.infinity,
  double.negativeInfinity,
  double.nan,
];

void main() {
  group('wartości referencyjne', () {
    test('2 % na 5000 mm = 100 mm wzniosu', () {
      final r = slopeRiseFromLength(lengthMm: 5000, slopePct: 2)!;
      expect(r.riseMm, 100.0);
      expect(r.lengthMm, 5000.0);
      expect(r.slopePct, 2.0);
      expect(r.mmPerM, 20.0);
      expect(r.angleDeg, math.atan(0.02) * 180 / math.pi);
      expect(r.angleDeg.toStringAsFixed(3), '1.146');
    });

    test('1 % na 6000 mm = 60 mm; kąt 0.573°, 10 mm/m (przykład ekranu)', () {
      final r = slopeRiseFromLength(lengthMm: 6000, slopePct: 1)!;
      expect(r.riseMm.toStringAsFixed(1), '60.0');
      expect(r.angleDeg.toStringAsFixed(3), '0.573');
      expect(r.mmPerM.toStringAsFixed(1), '10.0');
    });

    test('wznios 60 mm przy 1 % → długość 6000 mm', () {
      final r = slopeLengthFromRise(riseMm: 60, slopePct: 1)!;
      expect(r.lengthMm, 6000.0);
      expect(r.riseMm, 60.0);
      expect(r.mmPerM, 10.0);
    });

    test('długość 6000, wznios 60 → 1 %; kąt z atan(wznios/długość)', () {
      final r = slopeFromLengthAndRise(lengthMm: 6000, riseMm: 60)!;
      expect(r.slopePct, 1.0);
      expect(r.slopePct.toStringAsFixed(3), '1.000');
      expect(r.angleDeg, math.atan(60 / 6000) * 180.0 / math.pi);
      expect(r.mmPerM, 10.0);
    });

    test('pojedyncze wielkości: kąt i mm/m', () {
      expect(slopeAngleDeg(1), math.atan(0.01) * 180.0 / math.pi);
      expect(slopeAngleDeg(1), closeTo(0.5729387, 1e-7));
      expect(slopeMmPerM(0.5), 5.0);
      expect(slopeMmPerM(2), 20.0);
    });
  });

  group('dane nieprawidłowe → null', () {
    test('zero, ujemne, NaN, nieskończoność', () {
      for (final bad in [0.0, -1.0, double.nan, double.infinity]) {
        expect(slopeRiseFromLength(lengthMm: bad, slopePct: 1), isNull,
            reason: 'długość $bad');
        expect(slopeRiseFromLength(lengthMm: 1000, slopePct: bad), isNull,
            reason: '% $bad');
        expect(slopeLengthFromRise(riseMm: bad, slopePct: 1), isNull,
            reason: 'wznios $bad');
        expect(slopeLengthFromRise(riseMm: 10, slopePct: bad), isNull,
            reason: '% $bad');
        expect(slopeFromLengthAndRise(lengthMm: bad, riseMm: 10), isNull,
            reason: 'długość $bad');
        expect(slopeFromLengthAndRise(lengthMm: 1000, riseMm: bad), isNull,
            reason: 'wznios $bad');
        expect(slopeAngleDeg(bad), isNull, reason: 'kąt z % $bad');
        expect(slopeMmPerM(bad), isNull, reason: 'mm/m z % $bad');
      }
    });

    test('przepełnienie wyniku → null', () {
      expect(slopeRiseFromLength(lengthMm: 1e308, slopePct: 1e10), isNull);
      expect(slopeLengthFromRise(riseMm: 1e308, slopePct: 1e-10), isNull);
      expect(slopeFromLengthAndRise(lengthMm: 1e-300, riseMm: 1e300), isNull);
    });
  });

  group('zgodność z dawnym ekranem (bit w bit)', () {
    test('Długość → Wznios', () {
      for (final a in _grid) {
        for (final b in _grid) {
          expect(_tuple(slopeRiseFromLength(lengthMm: a, slopePct: b)),
              _legacyLengthToRise(a, b),
              reason: 'L=$a %=$b');
        }
      }
    });

    test('Wznios → Długość', () {
      for (final a in _grid) {
        for (final b in _grid) {
          expect(_tuple(slopeLengthFromRise(riseMm: a, slopePct: b)),
              _legacyRiseToLength(a, b),
              reason: 'R=$a %=$b');
        }
      }
    });

    test('Wyznacz %', () {
      for (final a in _grid) {
        for (final b in _grid) {
          expect(_tuple(slopeFromLengthAndRise(lengthMm: a, riseMm: b)),
              _legacySlopeFromLr(a, b),
              reason: 'L=$a R=$b');
        }
      }
    });
  });
}
