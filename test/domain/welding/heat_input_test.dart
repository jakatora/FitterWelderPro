// Energia liniowa: EN 1011-1 (z k) vs ASME IX QW-409.1 (bez k).
//
// Liczby przeliczone ręcznie (U·I·60 / v, v w mm/min → J/mm, /1000 → kJ/mm):
//  • 12 V · 100 A · 60 / 90 mm/min = 800 J/mm = 0,80 kJ/mm (ASME IX)
//    × k 0,6 (TIG, EN 1011-1 tab. 1) = 0,48 kJ/mm (EN)
//  • 12 V · 100 A · 60 / 100 mm/min = 720 J/mm → × 0,6 = 0,432 kJ/mm
//    (to samo co test audytu ekranu: 0,43 w UI)
//  • 22 V · 110 A · 60 / 200 mm/min = 726 J/mm → × 0,8 (MMA) = 0,5808 kJ/mm
//  • 32 V · 500 A · 60 / 600 mm/min = 1600 J/mm → × 1,0 (SAW) = 1,6 kJ/mm

import 'package:flutter_test/flutter_test.dart';

import 'package:cut_list_app/domain/welding/heat_input.dart';

void main() {
  group('sprawność cieplna k wg EN 1011-1 tab. 1', () {
    const expected = <WeldingProcess, double>{
      WeldingProcess.smaw: 0.8, // MMA 111 — było 1,00 w Kalkulatorach
      WeldingProcess.gmaw: 0.8,
      WeldingProcess.fcawG: 0.8,
      WeldingProcess.fcawS: 0.8, // 114 — było 0,75 (bez źródła)
      WeldingProcess.gtaw: 0.6,
      WeldingProcess.saw: 1.0,
    };
    for (final e in expected.entries) {
      test('${e.key.code} (${e.key.isoNumber}) → k = ${e.value}', () {
        expect(e.key.thermalEfficiency, e.value);
      });
    }

    test('kody z ekranu Heat input mapują się na procesy', () {
      for (final p in WeldingProcess.values) {
        expect(WeldingProcess.fromCode(p.code), p);
      }
      expect(WeldingProcess.fromCode('XYZ'), isNull);
    });
  });

  group('heatInputKJPerMm', () {
    final cases = <({
      String name,
      double u,
      double i,
      double v,
      HeatInputStandard std,
      double k,
      double expected,
    })>[
      (
        name: 'TIG ASME IX bez k',
        u: 12,
        i: 100,
        v: 90,
        std: HeatInputStandard.asmeIx,
        k: 0.6,
        expected: 0.80,
      ),
      (
        name: 'TIG EN k=0,6',
        u: 12,
        i: 100,
        v: 90,
        std: HeatInputStandard.en1011,
        k: 0.6,
        expected: 0.48,
      ),
      (
        name: 'TIG EN 100 mm/min (audyt)',
        u: 12,
        i: 100,
        v: 100,
        std: HeatInputStandard.en1011,
        k: 0.6,
        expected: 0.432,
      ),
      (
        name: 'MMA EN k=0,8',
        u: 22,
        i: 110,
        v: 200,
        std: HeatInputStandard.en1011,
        k: 0.8,
        expected: 0.5808,
      ),
      (
        name: 'SAW EN k=1,0 = ASME',
        u: 32,
        i: 500,
        v: 600,
        std: HeatInputStandard.en1011,
        k: 1.0,
        expected: 1.6,
      ),
    ];
    for (final c in cases) {
      test(c.name, () {
        expect(
          heatInputKJPerMm(
            volts: c.u,
            amps: c.i,
            travelMmPerMin: c.v,
            standard: c.std,
            efficiency: c.k,
          ),
          closeTo(c.expected, 1e-9),
        );
      });
    }

    test('ASME ignoruje k (nawet nieprawidłowe)', () {
      expect(
        heatInputKJPerMm(
          volts: 12,
          amps: 100,
          travelMmPerMin: 90,
          standard: HeatInputStandard.asmeIx,
          efficiency: 0,
        ),
        closeTo(0.8, 1e-9),
      );
    });

    for (final bad in [0.0, -1.0, double.nan, double.infinity]) {
      test('odrzuca prędkość $bad', () {
        expect(
          heatInputKJPerMm(
            volts: 12,
            amps: 100,
            travelMmPerMin: bad,
            standard: HeatInputStandard.en1011,
            efficiency: 0.6,
          ),
          isNull,
        );
      });
    }

    for (final badK in [0.0, -0.5, 1.5]) {
      test('EN odrzuca k = $badK', () {
        expect(
          heatInputKJPerMm(
            volts: 12,
            amps: 100,
            travelMmPerMin: 90,
            standard: HeatInputStandard.en1011,
            efficiency: badK,
          ),
          isNull,
        );
      });
    }
  });

  group('checkWpsRange — granice WPS bez pasma tolerancji', () {
    final cases = <({
      double hi,
      double? min,
      double? max,
      WpsRangeVerdict expected,
    })>[
      (hi: 0.58, min: null, max: null, expected: WpsRangeVerdict.notSet),
      (hi: 1.0, min: 1.0, max: 2.5, expected: WpsRangeVerdict.inRange),
      (hi: 2.5, min: 1.0, max: 2.5, expected: WpsRangeVerdict.inRange),
      // Stary kod: 0,95 było „złote — w paśmie ±10 %”. Poza WPS to poza WPS.
      (hi: 0.95, min: 1.0, max: 2.5, expected: WpsRangeVerdict.belowMin),
      (hi: 2.6, min: 1.0, max: 2.5, expected: WpsRangeVerdict.aboveMax),
      (hi: 0.5808, min: 0.5, max: 0.55, expected: WpsRangeVerdict.aboveMax),
      // Jedna granica wystarczy (typowo sam max dla nierdzewki).
      (hi: 0.9, min: null, max: 1.0, expected: WpsRangeVerdict.inRange),
      (hi: 1.1, min: null, max: 1.0, expected: WpsRangeVerdict.aboveMax),
      (hi: 0.4, min: 0.5, max: null, expected: WpsRangeVerdict.belowMin),
      (hi: 1.0, min: 2.0, max: 1.0, expected: WpsRangeVerdict.invalidRange),
      (hi: 1.0, min: -1.0, max: 2.0, expected: WpsRangeVerdict.invalidRange),
      (hi: 1.0, min: null, max: 0.0, expected: WpsRangeVerdict.invalidRange),
    ];
    for (final c in cases) {
      test('HI ${c.hi} w [${c.min}; ${c.max}] → ${c.expected.name}', () {
        expect(checkWpsRange(c.hi, min: c.min, max: c.max), c.expected);
      });
    }
  });

  // 1 in = 25,4 mm (definicja cala): 0,80 kJ/mm × 25,4 = 20,32 kJ/in
  // = 20 320 J/in; 0,5808 kJ/mm → 14,75 kJ/in → 14 752 J/in.
  group('jednostki kJ/mm ↔ kJ/in ↔ J/in', () {
    test('0,80 kJ/mm', () {
      expect(HeatInputUnit.kjPerIn.fromKjPerMm(0.80), closeTo(20.32, 1e-9));
      expect(HeatInputUnit.jPerIn.fromKjPerMm(0.80), closeTo(20320, 1e-6));
      expect(HeatInputUnit.jPerIn.format(0.80), '20320');
      expect(HeatInputUnit.kjPerIn.format(0.5808), '14.8');
      expect(HeatInputUnit.kjPerMm.format(0.5808), '0.58');
    });
    test('powrót do kJ/mm', () {
      expect(HeatInputUnit.jPerIn.toKjPerMm(25400), closeTo(1.0, 1e-12));
      expect(HeatInputUnit.kjPerIn.toKjPerMm(50.8), closeTo(2.0, 1e-12));
    });
  });

  // v = L / t · 60: 300 mm w 90 s → 200 mm/min; 150 mm w 100 s → 90 mm/min.
  group('travelSpeedMmPerMin (długość ściegu + czas jarzenia)', () {
    test('liczby', () {
      expect(travelSpeedMmPerMin(lengthMm: 300, seconds: 90), closeTo(200, 1e-9));
      expect(travelSpeedMmPerMin(lengthMm: 150, seconds: 100), closeTo(90, 1e-9));
    });
    test('zero / ujemne / NaN → null', () {
      expect(travelSpeedMmPerMin(lengthMm: 0, seconds: 10), isNull);
      expect(travelSpeedMmPerMin(lengthMm: 100, seconds: 0), isNull);
      expect(travelSpeedMmPerMin(lengthMm: -1, seconds: 10), isNull);
      expect(travelSpeedMmPerMin(lengthMm: double.nan, seconds: 10), isNull);
    });
  });
}
