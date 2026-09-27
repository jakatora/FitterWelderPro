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

    // 2" (50,8 × 1,65), 10 V: I = 48·1,65 + 0,12·50,8 = 85,3 A,
    // v = 130 − 18·1,65 = 100,3 mm/min → 1,6717 mm/s;
    // EN (η 0,6): 0,6·10·85,296/1,6717/1000 = 0,306 kJ/mm;
    // ASME IX (bez η): 0,510 kJ/mm.
    test('HI EN (η 0,6) i ASME IX (bez η)', () {
      final e = estimateOrbital(odMm: 50.8, wallMm: 1.65, arcVolts: 10);
      expect(e.heatInputKJmm, closeTo(0.306, 0.001));
      expect(e.arcEnergyKJmm, closeTo(0.510, 0.001));
    });
  });

  // Przegląd G4: 168,3 × 6,0 dawało 308 A, 273 × 10 → 513 A „autogenicznie”.
  group('checkOrbitalRange', () {
    test('cienka ścianka w zakresie', () {
      expect(checkOrbitalRange(odMm: 50.8, wallMm: 1.65), OrbitalRange.ok);
      expect(checkOrbitalRange(odMm: 168.3, wallMm: 3.0), OrbitalRange.ok);
    });
    test('ścianka > 3 mm poza zakresem', () {
      expect(checkOrbitalRange(odMm: 168.3, wallMm: 6.0),
          OrbitalRange.wallTooThick);
      expect(checkOrbitalRange(odMm: 273, wallMm: 10),
          OrbitalRange.wallTooThick);
    });
    test('prąd > 200 A poza zakresem (duże OD)', () {
      // 48·3 + 0,12·500 = 204 A
      expect(checkOrbitalRange(odMm: 500, wallMm: 3.0),
          OrbitalRange.currentTooHigh);
    });
  });
}
