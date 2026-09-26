// support-config (P1): wartości z tabeli MSS SP-58 Tab. 4 / ASME B31.1
// Tab. 121.5 (przypięte wiersz po wierszu w support_spacing_norm_test.dart).
//   DN50: ciecz 3000, gaz 4000. Izolacja NIE obniża rozstawu (B31.1 121.5
//   zakłada rurę izolowaną); własny zapas 10 %: 3000 × 0,90 = 2700,
//   DN100: 4300 × 0,90 = 3870, gaz 5200 × 0,90 = 4680.
//   Podpory = ⌈L ÷ rozstaw⌉ + 1.

import 'package:flutter_test/flutter_test.dart';

import 'package:cut_list_app/data/support_spacing.dart';

void main() {
  group('maxSupportSpacingMm', () {
    test('DN50 wg tabeli', () {
      expect(maxSupportSpacingMm(50, liquidFilled: true), 3000);
      expect(maxSupportSpacingMm(50, liquidFilled: false), 4000);
    });

    test('własny zapas 10 % tylko na życzenie', () {
      expect(maxSupportSpacingMm(50, liquidFilled: true, ownMarginPct: 10),
          2700);
      expect(maxSupportSpacingMm(100, liquidFilled: true, ownMarginPct: 10),
          3870);
      expect(maxSupportSpacingMm(100, liquidFilled: false, ownMarginPct: 10),
          4680);
    });

    test('DN spoza tabeli bierze najbliższy wiersz', () {
      expect(maxSupportSpacingMm(70, liquidFilled: true), 3400);
    });
  });

  group('supportsOnRun', () {
    test('odcinek równy wielokrotności rozstawu nie dostaje dodatkowej podpory',
        () {
      expect(supportsOnRun(6000, 3000), 3);
    });

    test('1 mm ponad wielokrotność dodaje podporę', () {
      expect(supportsOnRun(6001, 3000), 4);
    });

    test('DN50 z zapasem 10 % (2700), 5,25 m', () {
      expect(supportsOnRun(5250, 2700), 3);
    });

    test('DN100 ciecz, 50 m', () {
      expect(supportsOnRun(50000, 4300), 13);
    });

    test('bardzo krótki odcinek ma dwie podpory', () {
      expect(supportsOnRun(1, 3000), 2);
    });

    test('błędne dane nie dają wyniku', () {
      expect(supportsOnRun(0, 3000), isNull);
      expect(supportsOnRun(-5, 3000), isNull);
      expect(supportsOnRun(1000, 0), isNull);
    });
  });

  group('runLengthMm', () {
    test('przecinek i kropka dają pełne milimetry', () {
      expect(runLengthMm('4,35'), 4350);
      expect(runLengthMm('4.35'), 4350);
      expect(runLengthMm('12.6'), 12600);
      expect(runLengthMm('5,25'), 5250);
    });

    test('4,35 m przy rozstawie 4350 mm to dokładnie jeden przęsło', () {
      expect(supportsOnRun(runLengthMm('4,35')!, 4350), 2);
    });

    test('wpis nie będący liczbą', () {
      expect(runLengthMm(''), isNull);
      expect(runLengthMm('.'), isNull);
    });

    test('długość poniżej pół milimetra to 0 mm', () {
      expect(runLengthMm('0.0004'), 0);
    });
  });

  group('formatMmAsMetres', () {
    test('nie ukrywa cyfr znaczących', () {
      expect(formatMmAsMetres(3000), '3.0');
      expect(formatMmAsMetres(4300), '4.3');
      expect(formatMmAsMetres(2640), '2.64');
      expect(formatMmAsMetres(5250), '5.25');
      expect(formatMmAsMetres(3784), '3.784');
    });
  });
}
