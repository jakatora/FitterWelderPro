import 'package:flutter_test/flutter_test.dart';

import 'package:cut_list_app/services/cut_calculator.dart';

void main() {
  group('calculateCutOffsets', () {
    test('subtracts both offsets from ISO', () {
      final cut = calculateCutOffsets(
        isoMm: 3200,
        startOffsetMm: 76,
        endOffsetMm: 76,
      );
      expect(cut, closeTo(3048, 0.0001));
    });

    test('works with zero offsets', () {
      final cut = calculateCutOffsets(
        isoMm: 500,
        startOffsetMm: 0,
        endOffsetMm: 0,
      );
      expect(cut, closeTo(500, 0.0001));
    });
  });
}
