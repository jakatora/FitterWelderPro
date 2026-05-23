import 'package:flutter_test/flutter_test.dart';

import 'package:cut_list_app/services/orbital_tig.dart';

void main() {
  group('estimateOrbital', () {
    test('circumference is π·OD', () {
      final e = estimateOrbital(odMm: 50.8, wallMm: 1.65);
      expect(e.circumferenceMm, closeTo(159.59, 0.1));
    });

    test('four orbital levels, tapering toward overhead', () {
      final e = estimateOrbital(odMm: 50.8, wallMm: 1.65);
      expect(e.levelCurrentA.length, 4);
      for (var i = 1; i < 4; i++) {
        expect(e.levelCurrentA[i] <= e.levelCurrentA[i - 1], isTrue,
            reason: 'level $i should not exceed level ${i - 1}');
      }
    });

    test('thicker wall needs more current', () {
      final thin = estimateOrbital(odMm: 50.8, wallMm: 1.0);
      final thick = estimateOrbital(odMm: 50.8, wallMm: 3.0);
      expect(thick.levelCurrentA[0] > thin.levelCurrentA[0], isTrue);
    });

    test('weld time grows with diameter at equal wall', () {
      final small = estimateOrbital(odMm: 25.4, wallMm: 1.65);
      final big = estimateOrbital(odMm: 101.6, wallMm: 1.65);
      expect(big.weldTimeSec > small.weldTimeSec, isTrue);
    });

    test('single pass for thin wall, two passes above 2.5 mm', () {
      expect(estimateOrbital(odMm: 50.8, wallMm: 1.65).passes, 1);
      expect(estimateOrbital(odMm: 50.8, wallMm: 3.0).passes, 2);
    });

    test('travel speed stays within the thin-wall band', () {
      for (final wall in [0.5, 1.65, 2.5, 4.0]) {
        final e = estimateOrbital(odMm: 50.8, wallMm: wall);
        expect(e.travelSpeedMmMin >= 70 && e.travelSpeedMmMin <= 140, isTrue,
            reason: 'wall $wall → ${e.travelSpeedMmMin} mm/min out of band');
      }
    });

    test('heat input is positive and finite', () {
      final e = estimateOrbital(odMm: 50.8, wallMm: 1.65, arcVolts: 10);
      expect(e.heatInputKJmm > 0, isTrue);
      expect(e.heatInputKJmm.isFinite, isTrue);
    });
  });
}
