// Podgrzewanie: Seferian, CE IIW, reguła orientacyjna CE, minimum B31.3.
//
// Seferian (Grigorenko/Kostin, Przegląd Spawalnictwa 7/2013, za Seferianem):
//   [C]c = C + (Mn+Cr)/9 + Ni/18 + 7Mo/90;  [C] = [C]c·(1 + 0,005·t)
//   Tp = 350·√([C] − 0,25)
// Ręcznie, C 0,20 / Mn 1,50:
//   [C]c = 0,20 + 1,50/9 = 0,36667
//   t=10: [C] = 0,36667·1,05 = 0,38500 → √0,13500 = 0,36742 → 128,6 °C
//   t=30: [C] = 0,36667·1,15 = 0,42167 → √0,17167 = 0,41433 → 145,0 °C
//   t=60: [C] = 0,36667·1,30 = 0,47667 → √0,22667 = 0,47610 → 166,6 °C
// Stary kod („350·√(CEV−0,25) + 0,25·√t − 25”, CEV 0,45) dawał 132,3 °C dla
// t=10 — to nie była metoda Seferiana.

import 'package:flutter_test/flutter_test.dart';

import 'package:cut_list_app/domain/welding/preheat.dart';

void main() {
  group('seferianPreheat', () {
    final cases = <({
      String name,
      double c,
      double mn,
      double cr,
      double ni,
      double mo,
      double t,
      double chemical,
      double total,
      double tp,
    })>[
      (
        name: 'CS 0,20C/1,50Mn t=10',
        c: 0.20, mn: 1.50, cr: 0, ni: 0, mo: 0, t: 10,
        chemical: 0.366667, total: 0.385000, tp: 128.598,
      ),
      (
        name: 'CS 0,20C/1,50Mn t=30',
        c: 0.20, mn: 1.50, cr: 0, ni: 0, mo: 0, t: 30,
        chemical: 0.366667, total: 0.421667, tp: 145.014,
      ),
      (
        name: 'CS 0,20C/1,50Mn t=60',
        c: 0.20, mn: 1.50, cr: 0, ni: 0, mo: 0, t: 60,
        chemical: 0.366667, total: 0.476667, tp: 166.633,
      ),
      (
        // [C]c = 0,25 + 1,06/9 = 0,367778; ·1,075 = 0,395361 → 133,4 °C
        name: 'A106 B z katalogu t=15',
        c: 0.25, mn: 1.06, cr: 0, ni: 0, mo: 0, t: 15,
        chemical: 0.367778, total: 0.395361, tp: 133.442,
      ),
      (
        // [C]c = 0,15 + (0,5+1,2)/9 + 7·0,55/90 = 0,381667; ·1,10 → 144,2 °C
        name: 'P11 (Cr, Mo) t=20',
        c: 0.15, mn: 0.50, cr: 1.20, ni: 0, mo: 0.55, t: 20,
        chemical: 0.381667, total: 0.419833, tp: 144.238,
      ),
      (
        // [C]c = 0,10 + 1/9 + 1/18 + 7·0,3/90 = 0,29; ·1,125 = 0,32625 → 96,6 °C
        name: 'Ni + Mo t=25',
        c: 0.10, mn: 1.0, cr: 0, ni: 1.0, mo: 0.3, t: 25,
        chemical: 0.290000, total: 0.326250, tp: 96.647,
      ),
      (
        // Strażnik NaN (test welder_journey): [C] = 0,196 ≤ 0,25 → 0 °C
        name: 'niskowęglowa 0,12C/0,60Mn t=10',
        c: 0.12, mn: 0.60, cr: 0, ni: 0, mo: 0, t: 10,
        chemical: 0.186667, total: 0.196000, tp: 0,
      ),
    ];
    for (final k in cases) {
      test(k.name, () {
        final r = seferianPreheat(
          c: k.c,
          mn: k.mn,
          cr: k.cr,
          ni: k.ni,
          mo: k.mo,
          thicknessMm: k.t,
        )!;
        expect(r.chemicalCe, closeTo(k.chemical, 1e-5));
        expect(r.totalCe, closeTo(k.total, 1e-5));
        expect(r.preheatC, closeTo(k.tp, 1e-2));
        expect(r.preheatC.isNaN, isFalse);
      });
    }

    test('dane bez sensu → null, nie NaN', () {
      expect(seferianPreheat(c: 0.2, mn: 1.5, thicknessMm: 0), isNull);
      expect(seferianPreheat(c: -0.1, mn: 1.5, thicknessMm: 10), isNull);
      expect(seferianPreheat(c: double.nan, mn: 1.5, thicknessMm: 10), isNull);
    });
  });

  group('carbonEquivalentIiw', () {
    test('CS 0,20C/1,50Mn → 0,450', () {
      expect(carbonEquivalentIiw(c: 0.20, mn: 1.50), closeTo(0.45, 1e-12));
    });
    test('A106 B z katalogu → 0,4267', () {
      expect(carbonEquivalentIiw(c: 0.25, mn: 1.06), closeTo(0.426667, 1e-6));
    });
    test('pełny wzór: 0,03 + 2/6 + (17+2,5)/5 + 12/15 = 5,0633 (316L)', () {
      expect(
        carbonEquivalentIiw(c: 0.03, mn: 2.0, cr: 17.0, mo: 2.5, ni: 12.0),
        closeTo(5.063333, 1e-6),
      );
    });
  });

  group('isStainlessComposition (EN 10088-1: Cr ≥ 10,5 %)', () {
    for (final (cr, expected) in [
      (0.0, false),
      (9.0, false), // P91 — nie nierdzewna
      (10.49, false),
      (10.5, true),
      (17.0, true),
    ]) {
      test('Cr $cr → $expected', () {
        expect(isStainlessComposition(cr: cr), expected);
      });
    }
  });

  group('ceRuleOfThumb — pasma orientacyjne', () {
    final cases = <({double ce, double t, CeBand band, double tp})>[
      (ce: 0.30, t: 10, band: CeBand.low, tp: 0),
      (ce: 0.30, t: 25, band: CeBand.low, tp: 50),
      (ce: 0.35, t: 10, band: CeBand.medium, tp: 125),
      (ce: 0.4267, t: 15, band: CeBand.medium, tp: 125), // A106 B
      (ce: 0.45, t: 10, band: CeBand.high, tp: 175),
      (ce: 0.50, t: 10, band: CeBand.high, tp: 175), // A53 B
      (ce: 0.55, t: 10, band: CeBand.critical, tp: 250),
    ];
    for (final k in cases) {
      test('CE ${k.ce}, t ${k.t} → ${k.band.name} ${k.tp} °C', () {
        final r = ceRuleOfThumb(ce: k.ce, thicknessMm: k.t);
        expect(r.band, k.band);
        expect(r.preheatC, k.tp);
      });
    }
  });

  group('b313MinPreheatC — ASME B31.3-2012 Tab. 330.1.1', () {
    final cases = <({String pNo, double t, double? rm, int? expected})>[
      (pNo: '1', t: 10, rm: null, expected: 10),
      (pNo: '1', t: 24.9, rm: 415, expected: 10),
      (pNo: '1', t: 25, rm: null, expected: 80),
      (pNo: '1', t: 10, rm: 550, expected: 80),
      (pNo: '3', t: 12, rm: null, expected: 10),
      (pNo: '3', t: 13, rm: null, expected: 80),
      (pNo: '4', t: 5, rm: null, expected: 120),
      (pNo: '5A', t: 5, rm: null, expected: 175),
      (pNo: '6', t: 5, rm: null, expected: 200),
      (pNo: '8', t: 30, rm: null, expected: 10),
      (pNo: '15E', t: 5, rm: null, expected: 200),
      (pNo: '10H', t: 5, rm: null, expected: null), // brak danych w aplikacji
      (pNo: '43', t: 5, rm: null, expected: null),
      (pNo: '1', t: 0, rm: null, expected: null),
    ];
    for (final k in cases) {
      test('P-No ${k.pNo}, t ${k.t}, Rm ${k.rm} → ${k.expected}', () {
        expect(
          b313MinPreheatC(pNo: k.pNo, thicknessMm: k.t, smtsMpa: k.rm),
          k.expected,
        );
      });
    }
  });
}
