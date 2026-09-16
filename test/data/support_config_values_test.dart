// support-config (P1): wartości policzone ręcznie z tabeli MSS SP-69,
// niezależnie od kodu aplikacji.
//   DN50: ciecz 3000, gaz 4000; izolacja: 3000 × 0,88 = 2640.
//   DN100: ciecz 4300 × 0,88 = 3784, gaz 5200 × 0,88 = 4576.
//   Podpory = ⌈L ÷ rozstaw⌉ + 1.

import 'package:flutter_test/flutter_test.dart';

import 'package:cut_list_app/data/support_spacing.dart';

void main() {
  group('maxSupportSpacingMm', () {
    test('DN50 bez izolacji', () {
      expect(maxSupportSpacingMm(50, liquidFilled: true, insulated: false),
          3000);
      expect(maxSupportSpacingMm(50, liquidFilled: false, insulated: false),
          4000);
    });

    test('izolacja zmniejsza rozstaw o 12 %', () {
      expect(maxSupportSpacingMm(50, liquidFilled: true, insulated: true),
          2640);
      expect(maxSupportSpacingMm(100, liquidFilled: true, insulated: true),
          3784);
      expect(maxSupportSpacingMm(100, liquidFilled: false, insulated: true),
          4576);
    });

    test('DN spoza tabeli bierze najbliższy wiersz', () {
      expect(maxSupportSpacingMm(70, liquidFilled: true, insulated: false),
          3400);
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

    test('izolowany DN50, 5,25 m', () {
      expect(supportsOnRun(5250, 2640), 3);
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
