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

    // AWS D18.2 (Guide to Weld Discoloration Levels on Inside of Austenitic
    // Stainless Steel Tube): "The Sample Numbers refer to the amount of
    // oxygen (ppm) in the purging gas: No.1 10, No.2 25, No.3 50, No.4 100,
    // No.5 200, No.6 500, No.7 1000, No.8 5000, No.9 12500, No.10 25000"
    // (cytat za prezentacją 3-A SSI „Hygienic Welding: How Do You Know
    // When It's Right?", slajd 10).
    const d182Ppm = [10, 25, 50, 100, 200, 500, 1000, 5000, 12500, 25000];

    test('O₂ of each level matches the AWS D18.2 sample', () {
      for (var i = 0; i < 10; i++) {
        expect(kHeatTintLevels[i].o2Ppm, d182Ppm[i],
            reason: 'level ${i + 1}');
      }
    });

    test('displayed O₂ band shows the AWS D18.2 sample value', () {
      const shown = [
        '~ 10 ppm', '~ 25 ppm', '~ 50 ppm', '~ 100 ppm', '~ 200 ppm',
        '~ 500 ppm', '~ 1000 ppm', '~ 5000 ppm', '~ 12 500 ppm',
        '~ 25 000 ppm',
      ];
      for (var i = 0; i < 10; i++) {
        expect(kHeatTintLevels[i].approxO2, shown[i],
            reason: 'level ${i + 1}');
      }
    });

    test('heatTintLevelForO2Ppm picks the nearest sample on a log scale', () {
      expect(heatTintLevelForO2Ppm(1).level, 1);
      expect(heatTintLevelForO2Ppm(10).level, 1);
      expect(heatTintLevelForO2Ppm(100).level, 4);
      expect(heatTintLevelForO2Ppm(520).level, 6);
      expect(heatTintLevelForO2Ppm(210000).level, 10);
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
