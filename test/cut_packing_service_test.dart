import 'package:flutter_test/flutter_test.dart';

import 'package:cut_list_app/services/cut_packing_service.dart';

void main() {
  test('greedy packing matches example behaviour', () {
    final cuts = [3000, 2100, 2000, 1900, 1500, 1100, 900, 600].map((e) => e.toDouble()).toList();
    final bars = CutPackingService.packGreedyLargestThatFits(cuts, stockLength: 6000);

    // First bar should start with 3000 and then fit 2100 and 600 -> sum 5700.
    expect(bars.isNotEmpty, true);
    expect(bars.first.first, 3000);
    expect(bars.first, containsAllInOrder([3000, 2100, 600]));
    expect(bars.first.fold(0.0, (a, b) => a + b), 5700);
  });

  test('no bar exceeds stock length', () {
    final cuts = [3500, 2600, 1000, 900, 800].map((e) => e.toDouble()).toList();
    final bars = CutPackingService.packGreedyLargestThatFits(cuts);
    for (final b in bars) {
      final sum = b.fold(0.0, (a, x) => a + x);
      expect(sum <= 6000, true);
    }
  });
}
