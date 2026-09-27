// Moment dokręcania śrub kołnierzowych — czysta arytmetyka z
// lib/domain/bolting/bolt_torque.dart.
//
// Wzory:
//   A_s = 0,7854 · (d − 0,9743/n)²   [in²]   — ASME B1.1, pole przekroju
//         czynnego dla gwintu calowego UN (d = średnica nominalna [in],
//         n = zwoje na cal). 1 in² = 645,16 mm².
//   F   = frac · SMYS · A_s          [N]
//   T   = K · F · d                  [N·m]   (d w metrach)
//
// Szereg gwintu wg ASME B16.5 dla śrub dwustronnych: UNC-2A dla ≤ 1",
// 8UN-2A (8 zw./cal) dla > 1" (potwierdzone m.in. w katalogu producenta
// śrub Euroguarco: „Stud Bolts up to 1" included UNC-2A — over 1" 8UN-2A”).
//
// Poprzednio ekran liczył A_s współczynnikiem metrycznym 0,9382·p (ISO 898-1)
// i dla śrub ≥ 1-1/8" brał skok z szeregu UNC (7, 6, 5, 4 zw./cal; do tego
// 2" UNC to 4,5, nie 4). Wartości „stare” niżej policzone ręcznie tamtym
// wzorem — test pilnuje, żeby do nich nie wrócić.
//
// Wartości oczekiwane (B7, SMYS 724 MPa, 50 % → σ = 362 MPa, K = 0,16):
//   5/8-11 UNC : A_s = 0,7854·(0,625 − 0,088573)² = 0,22600 in² = 145,81 mm²
//                F = 362·145,81 = 52 782 N; T = 0,16·52 782·0,015875 = 134,07 N·m
//                (stary wzór: 147,70 mm², 135,85 N·m)
//   1-1/8-8UN  : A_s = 0,7854·(1,125 − 0,121788)² = 0,79046 in² = 509,97 mm²
//                F = 184 610 N; T = 0,16·184 610·0,028575 = 844,03 N·m
//                (stary: 7 zw./cal → 497,80 mm², 824,03 N·m)
//   1-1/2-8UN  : A_s = 0,7854·(1,5 − 0,121788)² = 1,49183 in² = 962,48 mm²
//                F = 348 418 N; T = 0,16·348 418·0,0381 = 2123,95 N·m
//                (stary: 6 zw./cal → 914,78 mm², 2018,70 N·m, −5,0 %)
//   2-8UN      : A_s = 0,7854·(2 − 0,121788)² = 2,77064 in² = 1787,51 mm²
//                F = 647 080 N; T = 0,16·647 080·0,0508 = 5259,45 N·m
//                (stary: 4 zw./cal → 1579,31 mm², 4646,87 N·m, −11,6 %)
// Tablicowe A_s z ASME B1.1 (Machinery's Handbook): 1/2-13 0,1419; 5/8-11
// 0,226; 3/4-10 0,334; 7/8-9 0,462; 1-8 0,606; 1-1/8-8 0,790; 1-1/4-8 1,000;
// 1-3/8-8 1,233; 1-1/2-8 1,492; 1-5/8-8 1,78; 1-3/4-8 2,08; 1-7/8-8 2,41;
// 2-8 2,77 in².

import 'package:flutter_test/flutter_test.dart';

import 'package:cut_list_app/domain/bolting/bolt_torque.dart';

void main() {
  group('szereg gwintu wg ASME B16.5', () {
    test('≤ 1" to UNC, > 1" to 8UN (8 zw./cal)', () {
      const expected = {
        '1/2': 13,
        '5/8': 11,
        '3/4': 10,
        '7/8': 9,
        '1': 8,
        '1-1/8': 8,
        '1-1/4': 8,
        '1-3/8': 8,
        '1-1/2': 8,
        '1-5/8': 8,
        '1-3/4': 8,
        '1-7/8': 8,
        '2': 8,
      };
      for (final e in expected.entries) {
        final size = flangeBoltSize(e.key);
        expect(size, isNotNull, reason: e.key);
        expect(size!.threadsPerInch, e.value, reason: e.key);
        expect(size.series, size.diameterIn > 1.0 ? '8UN' : 'UNC',
            reason: e.key);
      }
      expect(kFlangeBoltSizes.map((s) => s.label).toList(),
          expected.keys.toList());
    });

    test('nieznany rozmiar daje null, nie wyjątek', () {
      expect(flangeBoltSize('9/16'), isNull);
      expect(flangeBoltSize(''), isNull);
    });

    test('oznaczenie gwintu jak na świadectwie śruby', () {
      expect(flangeBoltSize('5/8')!.threadDesignation, '5/8"-11 UNC');
      expect(flangeBoltSize('1-1/2')!.threadDesignation, '1-1/2"-8 UN');
    });
  });

  group('pole przekroju czynnego A_s wg ASME B1.1', () {
    test('zgodne z tablicą B1.1 dla wszystkich rozmiarów', () {
      const tableIn2 = {
        '1/2': 0.1419,
        '5/8': 0.226,
        '3/4': 0.334,
        '7/8': 0.462,
        '1': 0.606,
        '1-1/8': 0.790,
        '1-1/4': 1.000,
        '1-3/8': 1.233,
        '1-1/2': 1.492,
        '1-5/8': 1.78,
        '1-3/4': 2.08,
        '1-7/8': 2.41,
        '2': 2.77,
      };
      for (final e in tableIn2.entries) {
        final s = flangeBoltSize(e.key)!;
        // Tablica podaje 3–4 cyfry znaczące; 0,5 % mieści zaokrąglenie.
        expect(tensileStressAreaIn2(s.diameterIn, s.threadsPerInch),
            closeTo(e.value, e.value * 0.005),
            reason: e.key);
      }
    });

    test('5/8-11: 145,81 mm², nie 147,70 mm² ze wzoru metrycznego', () {
      final a = tensileStressAreaMm2(flangeBoltSize('5/8')!);
      expect(a, closeTo(145.81, 0.01));
      expect(a, isNot(closeTo(147.70, 0.5)));
    });

    test('wejście spoza dziedziny rzuca ArgumentError', () {
      expect(() => tensileStressAreaIn2(0, 8), throwsArgumentError);
      expect(() => tensileStressAreaIn2(1, 0), throwsArgumentError);
      // d ≤ 0,9743/n — gwint „zjadłby” cały rdzeń.
      expect(() => tensileStressAreaIn2(0.1, 8), throwsArgumentError);
    });
  });

  group('moment T = K·F·d (B7, 50 % SMYS, K = 0,16)', () {
    // (rozmiar, A_s [mm²], F [kN], T [N·m], stary T [N·m])
    const cases = <(String, double, double, double, double)>[
      ('5/8', 145.81, 52.782, 134.07, 135.85),
      ('1-1/8', 509.97, 184.61, 844.03, 824.03),
      ('1-1/2', 962.48, 348.42, 2123.95, 2018.70),
      ('2', 1787.51, 647.08, 5259.45, 4646.87),
    ];
    for (final (label, asMm2, fKn, tNm, oldTNm) in cases) {
      test('$label": A_s $asMm2 mm², T $tNm N·m (było $oldTNm)', () {
        final r = boltTorque(
          size: flangeBoltSize(label)!,
          smysMpa: 724,
          nutFactor: 0.16,
          preloadFraction: 0.50,
        );
        expect(r.stressAreaMm2, closeTo(asMm2, 0.01));
        expect(r.preloadN / 1000, closeTo(fKn, 0.01));
        expect(r.torqueNm, closeTo(tNm, 0.01));
        expect(r.torqueNm, isNot(closeTo(oldTNm, 1.0)));
        // 1 ft·lbf = 1,3558 N·m — ten sam przelicznik co na ekranie.
        expect(r.torqueFtLb, closeTo(tNm / 1.3558, 0.01));
      });
    }

    test('B8M (SMYS 207 MPa), pasta Cu: 5/8" → 38,33 N·m', () {
      // σ = 103,5 MPa; F = 103,5·145,81 = 15 091 N;
      // T = 0,16·15 091·0,015875 = 38,33 N·m.
      final r = boltTorque(
        size: flangeBoltSize('5/8')!,
        smysMpa: 207,
        nutFactor: 0.16,
        preloadFraction: 0.50,
      );
      expect(r.torqueNm, closeTo(38.33, 0.01));
    });

    test('odrzuca ułamek preloadu i K spoza sensownego zakresu', () {
      final s = flangeBoltSize('5/8')!;
      expect(
          () => boltTorque(
              size: s, smysMpa: 724, nutFactor: 0, preloadFraction: 0.5),
          throwsArgumentError);
      expect(
          () => boltTorque(
              size: s, smysMpa: 724, nutFactor: 0.16, preloadFraction: 0),
          throwsArgumentError);
      expect(
          () => boltTorque(
              size: s, smysMpa: 724, nutFactor: 0.16, preloadFraction: 1.01),
          throwsArgumentError);
      expect(
          () => boltTorque(
              size: s, smysMpa: -1, nutFactor: 0.16, preloadFraction: 0.5),
          throwsArgumentError);
    });
  });

  // ASME PCC-1-2019, tab. 1 (legacy): R1 20–30 %, R2 50–70 %, R3 100 %,
  // R4 okrężnie 100 %, R5 „time permitting, wait a minimum of 4 h and repeat
  // Round 4”. 200 N·m → R1 40–60, R2 100–140, R3 200.
  group('pcc1LegacyRounds', () {
    test('momenty rund dla 200 N·m', () {
      final r = pcc1LegacyRounds(200);
      expect(r.map((x) => x.label), ['20–30 %', '50–70 %', '100 %']);
      expect(r.map((x) => x.formatNm()), ['40–60', '100–140', '200']);
      // 40/1,3558 = 29,5 → „30”; 60/1,3558 = 44,3 → „44”.
      expect(r.first.formatFtLb(), '30–44');
    });
    test('notatka: runda 5 po min. 4 h', () {
      final pl = pcc1ShareLines(200, english: false);
      expect(pl, contains('po min. 4 h'));
      expect(pl, isNot(contains('20min')));
      expect(pcc1ShareLines(200, english: true), contains('after min. 4 h'));
    });
  });
}
