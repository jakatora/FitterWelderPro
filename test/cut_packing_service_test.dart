import 'package:flutter_test/flutter_test.dart';

import 'package:cut_list_app/services/cut_packing_service.dart';

void main() {
  test('greedy packing fills the first bar with the largest pieces that fit', () {
    final cuts = [3000, 2100, 2000, 1900, 1500, 1100, 900, 600]
        .map((e) => e.toDouble())
        .toList();
    final bars = CutPackingService.packGreedyLargestThatFits(cuts, stockLength: 6000);

    // Largest-that-fits → 3000 + 2100 + 900 saturates the 6000 mm stock.
    expect(bars.isNotEmpty, isTrue);
    expect(bars.first, containsAllInOrder([3000, 2100, 900]));
    expect(bars.first.fold(0.0, (a, b) => a + b), 6000);
  });

  test('no bar exceeds stock length', () {
    final cuts = [3500, 2600, 1000, 900, 800].map((e) => e.toDouble()).toList();
    final bars = CutPackingService.packGreedyLargestThatFits(cuts);
    for (final b in bars) {
      final sum = b.fold(0.0, (a, x) => a + x);
      expect(sum <= 6000, isTrue);
    }
  });

  test('all input cuts are accounted for', () {
    final cuts = [3000, 2100, 2000, 1900, 1500, 1100, 900, 600]
        .map((e) => e.toDouble())
        .toList();
    final bars = CutPackingService.packGreedyLargestThatFits(cuts);
    final flat = bars.expand((b) => b).toList()..sort();
    final sortedIn = List<double>.from(cuts)..sort();
    expect(flat, sortedIn);
  });

  test('empty input yields no bars', () {
    expect(CutPackingService.packGreedyLargestThatFits([]), isEmpty);
  });
}
