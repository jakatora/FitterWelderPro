// Długość szpilek: tabela ASME B16.5 (RF / RTJ), spójność z katalogiem
// kołnierzy (liczba i średnica) i tryb z wymiarów z zaokrągleniem w górę.

import 'package:flutter_test/flutter_test.dart';

import 'package:cut_list_app/domain/bolting/stud_length.dart';
import 'package:cut_list_app/services/flange_catalog.dart';

AsmeStud _stud(int dn, int cls, FlangeFacing f) {
  final r = lookupAsmeStud(dn, cls, f);
  expect(r, isA<StudFound>(), reason: 'DN$dn Class $cls ${f.name}');
  return (r as StudFound).stud;
}

/// Liczba i średnica śrub w źródle tabeli długości (DNOW „Number and Size
/// of Bolts for Flanged Joints — ASME B16.5”, zgodne z USA Fastener
/// i wermac.org) — przepisane tu niezależnie od [FlangeCatalog], żeby test
/// złapał rozjazd katalogu i tabeli długości.
const Map<String, (int, String)> _sourceBolting = {
  '15_150': (4, '1/2'),
  '20_150': (4, '1/2'),
  '25_150': (4, '1/2'),
  '32_150': (4, '1/2'),
  '40_150': (4, '1/2'),
  '50_150': (4, '5/8'),
  '65_150': (4, '5/8'),
  '80_150': (4, '5/8'),
  '100_150': (8, '5/8'),
  '150_150': (8, '3/4'),
  '200_150': (8, '3/4'),
  '250_150': (12, '7/8'),
  '300_150': (12, '7/8'),
  '15_300': (4, '1/2'),
  '20_300': (4, '5/8'),
  '25_300': (4, '5/8'),
  '32_300': (4, '5/8'),
  '40_300': (4, '3/4'),
  '50_300': (8, '5/8'),
  '65_300': (8, '3/4'),
  '80_300': (8, '3/4'),
  '100_300': (8, '3/4'),
  '150_300': (12, '3/4'),
  '200_300': (12, '7/8'),
  '250_300': (16, '1'),
  '300_300': (16, '1-1/8'),
  '15_600': (4, '1/2'),
  '20_600': (4, '5/8'),
  '25_600': (4, '5/8'),
  '32_600': (4, '5/8'),
  '40_600': (4, '3/4'),
  '50_600': (8, '5/8'),
  '65_600': (8, '3/4'),
  '80_600': (8, '3/4'),
  '100_600': (8, '7/8'),
  '150_600': (12, '1'),
  '200_600': (12, '1-1/8'),
  '250_600': (16, '1-1/4'),
  '300_600': (20, '1-1/4'),
  '15_900': (4, '3/4'),
  '20_900': (4, '3/4'),
  '25_900': (4, '7/8'),
  '32_900': (4, '7/8'),
  '40_900': (4, '1'),
  '50_900': (8, '7/8'),
  '65_900': (8, '1'),
  '80_900': (8, '7/8'),
  '100_900': (8, '1-1/8'),
  '150_900': (12, '1-1/8'),
  '200_900': (12, '1-3/8'),
  '250_900': (16, '1-3/8'),
  '300_900': (20, '1-3/8'),
  '15_1500': (4, '3/4'),
  '20_1500': (4, '3/4'),
  '25_1500': (4, '7/8'),
  '32_1500': (4, '7/8'),
  '40_1500': (4, '1'),
  '50_1500': (8, '7/8'),
  '65_1500': (8, '1'),
  '80_1500': (8, '1-1/8'),
  '100_1500': (8, '1-1/4'),
  '150_1500': (12, '1-3/8'),
  '200_1500': (12, '1-5/8'),
  '250_1500': (12, '1-7/8'),
  '300_1500': (16, '2'),
};

StudDimensionsResult _ok(StudDimensionsOutcome o) {
  expect(o, isA<StudDimensionsOk>());
  return (o as StudDimensionsOk).result;
}

void main() {
  group('tabela ASME B16.5 — wiersze kontrolne', () {
    test('Class 150 DN50 RF: 4 × 5/8" × 3-1/4" (82,55 mm), RTJ 3-3/4"', () {
      final rf = _stud(50, 150, FlangeFacing.rf);
      expect(rf.boltCount, 4);
      expect(rf.nutCount, 8);
      expect(rf.size.label, '5/8');
      expect(studDesignation(rf.size, rf.lengthQuarterIn), '5/8" × 3-1/4"');
      expect(rf.lengthMm, closeTo(82.55, 1e-9));
      expect(
          formatQuarterInch(_stud(50, 150, FlangeFacing.rtj).lengthQuarterIn),
          '3-3/4"');
    });

    test('Class 300 DN150 RF: 12 × 3/4" × 4-3/4", RTJ 5-1/2"', () {
      final rf = _stud(150, 300, FlangeFacing.rf);
      expect(rf.boltCount, 12);
      expect(studDesignation(rf.size, rf.lengthQuarterIn), '3/4" × 4-3/4"');
      expect(
          formatQuarterInch(_stud(150, 300, FlangeFacing.rtj).lengthQuarterIn),
          '5-1/2"');
    });

    test('Class 600 DN100: 8 × 7/8" × 5-3/4", RF = RTJ', () {
      final rf = _stud(100, 600, FlangeFacing.rf);
      expect(studDesignation(rf.size, rf.lengthQuarterIn), '7/8" × 5-3/4"');
      expect(_stud(100, 600, FlangeFacing.rtj).lengthQuarterIn,
          rf.lengthQuarterIn);
    });

    test(
        'Class 900 DN80: 8 × 7/8" × 5-3/4" — krótsza niż DN65 (1"), jak w B16.5',
        () {
      final dn80 = _stud(80, 900, FlangeFacing.rf);
      expect(studDesignation(dn80.size, dn80.lengthQuarterIn), '7/8" × 5-3/4"');
      expect(formatQuarterInch(_stud(65, 900, FlangeFacing.rf).lengthQuarterIn),
          '6-1/4"');
    });

    test('Class 1500 DN300: 16 × 2" × 14-3/4" RF, 15-1/4" RTJ', () {
      final rf = _stud(300, 1500, FlangeFacing.rf);
      expect(rf.boltCount, 16);
      expect(studDesignation(rf.size, rf.lengthQuarterIn), '2" × 14-3/4"');
      expect(
          formatQuarterInch(_stud(300, 1500, FlangeFacing.rtj).lengthQuarterIn),
          '15-1/4"');
    });

    test('Class 150 DN15 i DN20 RTJ — brak w B16.5, nie zgadujemy', () {
      for (final dn in [15, 20]) {
        final r = lookupAsmeStud(dn, 150, FlangeFacing.rtj);
        expect(r, isA<StudNotFound>());
        expect((r as StudNotFound).problem, StudLookupProblem.noRtj);
      }
      expect(lookupAsmeStud(25, 150, FlangeFacing.rtj), isA<StudFound>());
    });

    test('DN × Class spoza tabeli → komunikat (DN125, DN350, Class 2500)', () {
      for (final (dn, cls) in [(125, 150), (350, 300), (100, 2500), (0, 0)]) {
        final r = lookupAsmeStud(dn, cls, FlangeFacing.rf);
        expect(r, isA<StudNotFound>(), reason: 'DN$dn Class $cls');
        expect((r as StudNotFound).problem, StudLookupProblem.notInCatalog);
      }
    });

    test('rozbieżne źródła → dłuższa wartość i notatka', () {
      expect(_stud(200, 600, FlangeFacing.rtj).lengthQuarterIn, 31); // 7-3/4"
      expect(_stud(200, 900, FlangeFacing.rf).lengthQuarterIn, 35); // 8-3/4"
      expect(_stud(200, 1500, FlangeFacing.rtj).lengthQuarterIn, 51); // 12-3/4"
      expect(studLengthSourceNote(200, 600, FlangeFacing.rtj, en: false),
          contains('Przyjęto dłuższą'));
      expect(studLengthSourceNote(200, 1500, FlangeFacing.rtj, en: true),
          contains('The longer one is used'));
      expect(
          studLengthSourceNote(200, 600, FlangeFacing.rf, en: false), isNull);
      expect(
          studLengthSourceNote(150, 300, FlangeFacing.rf, en: false), isNull);
    });

    test('przylga w tabeli: 2 mm (1/16") dla Class 150/300, 7 mm (1/4") wyżej',
        () {
      expect(assumedRaisedFaceMm(150), 2);
      expect(assumedRaisedFaceMm(300), 2);
      expect(assumedRaisedFaceInch(300), '1/16"');
      expect(assumedRaisedFaceMm(600), 7);
      expect(assumedRaisedFaceInch(1500), '1/4"');
    });
  });

  group('spójność z FlangeCatalog', () {
    test('tabela długości obejmuje dokładnie DN × Class katalogu', () {
      final catalog = {
        for (final dn in FlangeCatalog.dns)
          for (final cls in FlangeCatalog.classes)
            if (FlangeCatalog.lookup(dn, cls) != null) '${dn}_$cls',
      };
      expect(studLengthTableKeys.toSet(), catalog);
      expect(catalog, hasLength(65));
    });

    test('liczba i średnica szpilek: katalog = źródło tabeli długości', () {
      expect(_sourceBolting.keys.toSet(), studLengthTableKeys.toSet());
      for (final e in _sourceBolting.entries) {
        final parts = e.key.split('_');
        final b =
            FlangeCatalog.lookup(int.parse(parts[0]), int.parse(parts[1]))!;
        expect((b.boltCount, b.boltSize), e.value, reason: e.key);
        final s =
            _stud(int.parse(parts[0]), int.parse(parts[1]), FlangeFacing.rf);
        expect((s.boltCount, s.size.label), e.value, reason: e.key);
      }
    });

    test('RTJ nigdy krótsze niż RF; RF nie maleje z klasą przy tym samym DN',
        () {
      for (final dn in FlangeCatalog.dns) {
        var prev = 0;
        for (final cls in FlangeCatalog.classes) {
          final rf = _stud(dn, cls, FlangeFacing.rf);
          expect(rf.lengthQuarterIn, greaterThanOrEqualTo(prev),
              reason: 'DN$dn Class $cls');
          prev = rf.lengthQuarterIn;
          final rtj = lookupAsmeStud(dn, cls, FlangeFacing.rtj);
          if (rtj is StudFound) {
            expect(rtj.stud.lengthQuarterIn,
                greaterThanOrEqualTo(rf.lengthQuarterIn),
                reason: 'DN$dn Class $cls');
          }
        }
      }
    });

    test('każda szpilka mieści 2 nakrętki (2·d) i oba kołnierze (> 1")', () {
      for (final key in studLengthTableKeys) {
        final p = key.split('_');
        final s = _stud(int.parse(p[0]), int.parse(p[1]), FlangeFacing.rf);
        expect(s.lengthIn, greaterThan(2 * s.size.diameterIn + 1), reason: key);
      }
    });
  });

  group('z wymiarów', () {
    test('przykład ręczny: 24 + 24 + 4,5 + 2 × 18 + 2 × 2,5 = 93,5 → 95 mm',
        () {
      final r = _ok(computeStudLength(
        flange1Mm: 24,
        flange2Mm: 24,
        gasketMm: 4.5,
        nutMm: 18,
        protrusionMm: 2.5,
      ));
      expect(r.requiredMm, closeTo(93.5, 1e-9));
      expect(r.orderMm, 95);
      expect(r.orderQuarterIn, isNull);
    });

    test('ten sam przykład: co 10 mm → 100; co 1/4" → 3-3/4" (95,25 mm)', () {
      StudDimensionsResult at(LengthSeries s) => _ok(computeStudLength(
            flange1Mm: 24,
            flange2Mm: 24,
            gasketMm: 4.5,
            nutMm: 18,
            protrusionMm: 2.5,
            series: s,
          ));
      expect(at(LengthSeries.mm10).orderMm, 100);
      final inch = at(LengthSeries.quarterInch);
      expect(inch.orderQuarterIn, 15);
      expect(formatQuarterInch(inch.orderQuarterIn!), '3-3/4"');
      expect(inch.orderMm, closeTo(95.25, 1e-9));
    });

    test('podkładki: 2 × 3 mm dodają 6 mm', () {
      final r = _ok(computeStudLength(
        flange1Mm: 30,
        flange2Mm: 30,
        gasketMm: 3,
        nutMm: 20,
        protrusionMm: 2.5,
        washers: 2,
        washerMm: 3,
      ));
      expect(r.requiredMm, closeTo(30 + 30 + 3 + 40 + 5 + 6, 1e-9));
      expect(r.orderMm, 115);
    });

    test('granica kroku: 115,00 → 115 (nie 120); 115,01 → 120', () {
      expect(
          _ok(computeStudLength(
                  flange1Mm: 50,
                  flange2Mm: 50,
                  gasketMm: 3,
                  nutMm: 6,
                  protrusionMm: 0))
              .orderMm,
          115);
      expect(
          _ok(computeStudLength(
                  flange1Mm: 50,
                  flange2Mm: 50,
                  gasketMm: 3.01,
                  nutMm: 6,
                  protrusionMm: 0))
              .orderMm,
          120);
    });

    test('błąd liczb zmiennoprzecinkowych nie przeskakuje o krok', () {
      expect(stepsUp(114.99999999999999, 5), 23);
      expect(stepsUp(115.00000000000001, 5), 23);
      expect(stepsUp(0.1 + 0.2, 0.3), 1);
      expect(stepsUp(95.25, kMmPerQuarterInch), 15);
      expect(stepsUp(95.26, kMmPerQuarterInch), 16);
    });

    test('zaokrąglenie zawsze w górę: siatka wartości, każdy typoszereg', () {
      for (final s in LengthSeries.values) {
        for (var t = 10.0; t <= 60; t += 0.7) {
          for (final g in [0.0, 1.5, 3.2, 4.5]) {
            final r = _ok(computeStudLength(
              flange1Mm: t,
              flange2Mm: t + 0.3,
              gasketMm: g,
              nutMm: 16,
              protrusionMm: 2,
              series: s,
            ));
            final step = seriesStepMm(s);
            expect(r.orderMm, greaterThanOrEqualTo(r.requiredMm - 1e-9),
                reason: '${s.name} ${r.requiredMm}');
            expect(r.orderMm - r.requiredMm, lessThan(step + 1e-9),
                reason: '${s.name} ${r.requiredMm}');
          }
        }
      }
    });

    test('puste / nieczytelne pole → brak wyniku z listą pól (nie zero)', () {
      final o = computeStudLength(
        flange1Mm: 24,
        flange2Mm: null,
        gasketMm: 4.5,
        nutMm: null,
        protrusionMm: 2,
      );
      expect(o, isA<StudDimensionsInvalid>());
      expect((o as StudDimensionsInvalid).fields,
          [StudInputField.flange2, StudInputField.nut]);
    });

    test('NaN / ∞ → błąd pola, nie wynik', () {
      final o = computeStudLength(
        flange1Mm: double.nan,
        flange2Mm: double.infinity,
        gasketMm: 4.5,
        nutMm: 16,
        protrusionMm: double.negativeInfinity,
      );
      expect((o as StudDimensionsInvalid).fields, [
        StudInputField.flange1,
        StudInputField.flange2,
        StudInputField.protrusion,
      ]);
    });

    test('granice pól', () {
      StudDimensionsOutcome c({
        double f = 24,
        double g = 3,
        double m = 16,
        double p = 2,
        int w = 0,
        double? wt,
      }) =>
          computeStudLength(
              flange1Mm: f,
              flange2Mm: 24,
              gasketMm: g,
              nutMm: m,
              protrusionMm: p,
              washers: w,
              washerMm: wt);
      expect(c(f: 0), isA<StudDimensionsInvalid>());
      expect(c(f: kMaxFlangeMm), isA<StudDimensionsOk>());
      expect(c(f: kMaxFlangeMm + 0.01), isA<StudDimensionsInvalid>());
      // Uszczelka 0 (styk metal–metal) i wystawanie 0 (na równo) są dozwolone.
      expect(c(g: 0), isA<StudDimensionsOk>());
      expect(c(p: 0), isA<StudDimensionsOk>());
      expect(c(g: -1), isA<StudDimensionsInvalid>());
      expect(c(m: 0), isA<StudDimensionsInvalid>());
      expect(c(p: kMaxProtrusionMm + 1), isA<StudDimensionsInvalid>());
      // Podkładki bez grubości albo w niedozwolonej liczbie — błąd pola.
      expect(
          (c(w: 2) as StudDimensionsInvalid).fields, [StudInputField.washer]);
      expect(c(w: 3, wt: 3), isA<StudDimensionsInvalid>());
      expect(c(w: 2, wt: 3), isA<StudDimensionsOk>());
      // Grubość podkładki przy 0 sztuk jest ignorowana.
      expect(_ok(c(w: 0, wt: 99)).washerMm, 0);
    });
  });

  group('formatowanie', () {
    test('ćwiartki cala z łącznikiem', () {
      expect(formatQuarterInch(9), '2-1/4"');
      expect(formatQuarterInch(16), '4"');
      expect(formatQuarterInch(3), '3/4"');
      expect(formatQuarterInch(2), '1/2"');
      expect(formatQuarterInch(59), '14-3/4"');
      expect(formatQuarterInch(0), '—');
    });

    test('mm: przecinek w PL, kropka w EN; NaN → „—”', () {
      expect(formatMm(82.55, decimals: 2, en: false), '82,55 mm');
      expect(formatMm(82.55, decimals: 2, en: true), '82.55 mm');
      expect(formatMm(95, decimals: 0, en: false), '95 mm');
      expect(fmtStudNum(double.nan, en: false), '—');
      expect(fmtStudNum(double.infinity, en: true), '—');
    });
  });
}
