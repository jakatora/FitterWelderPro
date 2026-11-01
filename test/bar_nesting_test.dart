import 'package:flutter_test/flutter_test.dart';

import 'package:cut_list_app/services/bar_nesting.dart';

void main() {
  group('nestCutsToBars', () {
    test('two pieces plus one kerf consume one bar exactly', () {
      final plans = nestCutsToBars(
        cutsMm: [3000, 2997],
        stockLengthMm: 6000,
        sawKerfMm: 3,
      );
      expect(plans, hasLength(1));
      expect(plans.single.piecesMm, [3000, 2997]);
      expect(plans.single.cutsCount, 1);
      expect(plans.single.remainingMm, 0);
    });

    test('three pieces plus two kerfs consume one bar exactly', () {
      final plans = nestCutsToBars(
        cutsMm: [1998, 1998, 1998],
        stockLengthMm: 6000,
        sawKerfMm: 3,
      );
      expect(plans, hasLength(1));
      expect(plans.single.cutsCount, 2);
      expect(plans.single.remainingMm, 0);
      expect(plans.single.piecesMm, [1998, 1998, 1998]);
    });

    test('a pair exceeding the stock after one kerf still needs two bars', () {
      final plans = nestCutsToBars(
        cutsMm: [3000, 2998],
        stockLengthMm: 6000,
        sawKerfMm: 3,
      );
      expect(plans, hasLength(2));
    });

    test('fractional kerf also permits an exact end of stock', () {
      final plans = nestCutsToBars(
        cutsMm: [2999.75, 2999],
        stockLengthMm: 6000,
        sawKerfMm: 1.25,
      );
      expect(plans, hasLength(1));
      expect(plans.single.cutsCount, 1);
      expect(plans.single.remainingMm, closeTo(0, 1e-8));
    });

    test('packing preserves every piece and the material balance', () {
      const lengths = [1000.0, 1998.0, 2000.0, 2997.0, 3000.0];
      for (final a in lengths) {
        for (final b in lengths) {
          for (final c in lengths) {
            final plans = nestCutsToBars(
              cutsMm: [a, b, c],
              stockLengthMm: 6000,
              sawKerfMm: 3,
            );
            expect(plans.expand((p) => p.piecesMm), unorderedEquals([a, b, c]));
            for (final plan in plans) {
              final net = plan.piecesMm.reduce((a, b) => a + b);
              expect(net + plan.cutsCount * 3 + plan.remainingMm,
                  closeTo(6000, 1e-8));
              expect(plan.remainingMm, greaterThanOrEqualTo(0));
            }
          }
        }
      }
    });

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
      expect(
          nestCutsToBars(
            cutsMm: [],
            stockLengthMm: 6000,
            sawKerfMm: 3,
          ),
          isEmpty);
    });
  });
}
