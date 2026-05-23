import 'package:flutter_test/flutter_test.dart';

import 'package:cut_list_app/data/heat_tint.dart';

void main() {
  group('heat tint chart', () {
    test('has exactly 10 levels numbered 1..10', () {
      expect(kHeatTintLevels.length, 10);
      for (var i = 0; i < 10; i++) {
        expect(kHeatTintLevels[i].level, i + 1);
      }
    });

    test('acceptance only loosens-to-stricter going down the chart', () {
      // Verdict severity must be non-decreasing: a darker bead is never a
      // better verdict than a lighter one.
      int rank(HeatTintVerdict v) => switch (v) {
            HeatTintVerdict.pharma => 0,
            HeatTintVerdict.food => 1,
            HeatTintVerdict.marginal => 2,
            HeatTintVerdict.reject => 3,
          };
      for (var i = 1; i < kHeatTintLevels.length; i++) {
        expect(
          rank(kHeatTintLevels[i].verdict) >=
              rank(kHeatTintLevels[i - 1].verdict),
          isTrue,
          reason: 'level ${kHeatTintLevels[i].level} verdict regressed',
        );
      }
    });

    test('level 1 is pharma-grade, level 10 is reject', () {
      expect(kHeatTintLevels.first.verdict, HeatTintVerdict.pharma);
      expect(kHeatTintLevels.last.verdict, HeatTintVerdict.reject);
    });

    test('every level has a name in both languages', () {
      for (final l in kHeatTintLevels) {
        expect(l.namePl.trim().isNotEmpty, isTrue);
        expect(l.nameEn.trim().isNotEmpty, isTrue);
        expect(l.approxO2.trim().isNotEmpty, isTrue);
      }
    });
  });
}
