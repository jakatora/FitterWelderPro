import 'package:flutter_test/flutter_test.dart';

import 'package:cut_list_app/services/bar_nesting.dart';

void main() {
  group('nestCutsToBars', () {
    test('one piece equal to the full bar uses 0 cuts', () {
      final plans = nestCutsToBars(
        cutsMm: [6000],
        stockLengthMm: 6000,
        sawKerfMm: 3,
      );
      expect(plans.length, 1);
      expect(plans.first.cutsCount, 0);
      expect(plans.first.remainingMm, 0);
    });

    test('three pieces that fully consume the bar use n-1 cuts', () {
      final plans = nestCutsToBars(
        cutsMm: [2000, 2000, 2000],
        stockLengthMm: 6000,
        sawKerfMm: 0,
      );
      expect(plans.length, 1);
      expect(plans.first.cutsCount, 2);
      expect(plans.first.piecesMm, [2000, 2000, 2000]);
    });

    test('pieces with leftover scrap use n cuts (kerf-per-cut accounting)', () {
      final plans = nestCutsToBars(
        cutsMm: [1500, 1500, 1500],
        stockLengthMm: 6000,
        sawKerfMm: 3,
      );
      expect(plans.length, 1);
      expect(plans.first.piecesMm.length, 3);
      expect(plans.first.cutsCount, 3);
      // 6000 - 3*1500 - 3*3 = 1491 mm of scrap.
      expect(plans.first.remainingMm, closeTo(1491, 0.001));
    });

    test('a cut longer than a stock bar spans multiple bars', () {
      final plans = nestCutsToBars(
        cutsMm: [14000],
        stockLengthMm: 6000,
        sawKerfMm: 0,
      );
      expect(plans.length, 3);
      expect(plans[0].piecesMm.first, 6000);
      expect(plans[1].piecesMm.first, 6000);
      expect(plans[2].piecesMm.first, 2000);
    });

    test('empty input yields no plans', () {
      expect(nestCutsToBars(
        cutsMm: [],
        stockLengthMm: 6000,
        sawKerfMm: 3,
      ), isEmpty);
    });
  });
}
