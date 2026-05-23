import 'package:flutter_test/flutter_test.dart';

import 'package:cut_list_app/data/tungsten.dart';

void main() {
  group('sizeForCurrent', () {
    test('90 A picks the 1.6 mm electrode', () {
      expect(sizeForCurrent(90)!.diaMm, 1.6);
    });

    test('40 A picks the 1.0 mm electrode', () {
      expect(sizeForCurrent(40)!.diaMm, 1.0);
    });

    test('200 A picks the 2.4 mm electrode', () {
      expect(sizeForCurrent(200)!.diaMm, 2.4);
    });

    test('below the lowest band clamps to the smallest electrode', () {
      expect(sizeForCurrent(5)!.diaMm, 1.0);
    });

    test('above the highest band clamps to the largest electrode', () {
      expect(sizeForCurrent(900)!.diaMm, 3.2);
    });
  });

  group('tungsten reference data', () {
    test('current bands are ordered and non-overlapping going up', () {
      for (var i = 1; i < kTungstenSizes.length; i++) {
        expect(kTungstenSizes[i].diaMm > kTungstenSizes[i - 1].diaMm, isTrue);
        expect(kTungstenSizes[i].minA >= kTungstenSizes[i - 1].minA, isTrue);
      }
    });

    test('every band has min < max', () {
      for (final s in kTungstenSizes) {
        expect(s.minA < s.maxA, isTrue);
      }
    });

    test('at least one electrode type is flagged for stainless DC', () {
      expect(kTungstenTypes.any((t) => t.bestForSs), isTrue);
    });

    test('pure tungsten is not recommended for stainless DC', () {
      final wp = kTungstenTypes.firstWhere((t) => t.code == 'WP');
      expect(wp.bestForSs, isFalse);
    });
  });
}
