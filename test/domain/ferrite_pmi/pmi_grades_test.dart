// PMI — tabela gatunków: wartości sprawdzone w normach (EN i ASTM, z
// wydaniem), różnice EN / ASTM oceniane wobec wybranej normy, pierwiastki
// kluczowe mają zakres w każdej normie, gatunki „L” / duplex / P91 →
// „zgodny (bez weryfikacji C)”, podpowiedź najbliższego gatunku.

import 'package:flutter_test/flutter_test.dart';

import 'package:cut_list_app/domain/ferrite_pmi/ferrite_pmi_sources.dart';
import 'package:cut_list_app/domain/ferrite_pmi/ferrite_pmi_text.dart';
import 'package:cut_list_app/domain/ferrite_pmi/pmi.dart';

PmiSpec _spec(String grade, String key) =>
    pmiGradeById(grade)!.specByKey(key)!;

PmiRange _r(String grade, String key, PmiElement e) =>
    _spec(grade, key).ranges[e]!;

void _range(String grade, String key, PmiElement e, double? min, double? max) {
  final r = _r(grade, key, e);
  expect(r.min, min, reason: '$grade/$key ${e.symbol} min');
  expect(r.max, max, reason: '$grade/$key ${e.symbol} max');
}

PmiResult _eval(String grade, String key, Map<PmiElement, String> readings,
        {Map<PmiElement, String> u = const {}}) =>
    evaluatePmi(
        grade: pmiGradeById(grade),
        spec: _spec(grade, key),
        readings: readings,
        uncertainty: u,
        table: kPmiGrades);

PmiElementCheck _check(PmiResult r, PmiElement e) =>
    r.checks.firstWhere((c) => c.element == e);

void main() {
  test('tabela: 13 gatunków z zadania, unikalne id i klucze wariantów', () {
    // Kolejność wg rodzin (austenityczne, duplex, Cr-Mo) — jak na liście
    // wyboru.
    expect(kPmiGrades.map((g) => g.id), [
      '1.4301',
      '1.4307',
      '1.4401',
      '1.4404',
      '1.4571',
      '1.4541',
      '1.4539',
      '1.4845',
      '1.4462',
      '1.4410',
      '1.7335',
      '1.7380',
      '1.4903',
    ]);
    for (final g in kPmiGrades) {
      final keys = g.specs.map((s) => s.key).toList();
      expect(keys.toSet().length, keys.length, reason: g.id);
      expect(g.specs.first.standard, startsWith('EN '), reason: g.id);
      expect(g.keyElements, isNotEmpty, reason: g.id);
    }
  });

  test('każdy wariant: norma z rokiem wydania i źródło', () {
    // EN: „:2014”; ASTM: „-25a”, „-23” (rok dwiema cyframi).
    final year = RegExp(r':(19|20)\d\d|-\d\d[a-z]?\b');
    for (final g in kPmiGrades) {
      for (final s in g.specs) {
        expect(year.hasMatch(s.standard), isTrue,
            reason: '${g.id}/${s.key}: ${s.standard}');
        expect(s.sourcePl.trim(), isNotEmpty, reason: '${g.id}/${s.key}');
        expect(s.sourceEn.trim(), isNotEmpty, reason: '${g.id}/${s.key}');
        expect(s.carbonText.trim(), isNotEmpty, reason: '${g.id}/${s.key}');
      }
    }
  });

  test('pierwiastki kluczowe mają zakres w każdej normie gatunku', () {
    for (final g in kPmiGrades) {
      for (final s in g.specs) {
        for (final e in g.keyElements) {
          expect(s.ranges[e], isNotNull,
              reason: '${g.id}/${s.key} ${e.symbol}');
        }
      }
    }
  });

  test('zakresy spójne: min ≤ max, w 0–100 %', () {
    for (final g in kPmiGrades) {
      for (final s in g.specs) {
        for (final MapEntry(key: e, value: r) in s.ranges.entries) {
          final lo = r.min ?? 0, hi = r.max ?? 100;
          expect(lo <= hi && lo >= 0 && hi <= 100, isTrue,
              reason: '${g.id}/${s.key} ${e.symbol}');
          expect(r.min != null || r.max != null || r.carbonMin != null,
              isTrue,
              reason: '${g.id}/${s.key} ${e.symbol}');
        }
      }
    }
  });

  group('wartości sprawdzone w normach (ASTM)', () {
    test('304: A240-25a 18,0–20,0 / 8,0–11,0; SA-240 (A240-17) 17,5–19,5 / '
        '8,0–10,5; A312-25 18,0–20,0 / 8,0–11,0', () {
      _range('1.4301', 'a240', PmiElement.cr, 18.0, 20.0);
      _range('1.4301', 'a240', PmiElement.ni, 8.0, 11.0);
      _range('1.4301', 'sa240', PmiElement.cr, 17.5, 19.5);
      _range('1.4301', 'sa240', PmiElement.ni, 8.0, 10.5);
      _range('1.4301', 'a312', PmiElement.cr, 18.0, 20.0);
      _range('1.4301', 'a312', PmiElement.ni, 8.0, 11.0);
    });

    test('304L: Ni A240 8,0–12,0, A312 8,0–13,0', () {
      _range('1.4307', 'a240', PmiElement.ni, 8.0, 12.0);
      _range('1.4307', 'a312', PmiElement.ni, 8.0, 13.0);
      _range('1.4307', 'sa240', PmiElement.cr, 17.5, 19.5);
    });

    test('316L: Mo 2,00–3,00, Ni 10,0–14,0 (A240-25a i A312-25)', () {
      for (final k in ['a240', 'a312']) {
        _range('1.4404', k, PmiElement.mo, 2.0, 3.0);
        _range('1.4404', k, PmiElement.ni, 10.0, 14.0);
        _range('1.4404', k, PmiElement.cr, 16.0, 18.0);
      }
    });

    test('321 / 316Ti: Ti 5 × (C + N) – 0,70', () {
      for (final (g, k) in [('1.4541', 'a240'), ('1.4571', 'astm')]) {
        final ti = _r(g, k, PmiElement.ti);
        expect(ti.max, 0.70, reason: g);
        expect(ti.carbonMin!.factor, 5, reason: g);
        expect(ti.carbonMin!.plusN, isTrue, reason: g);
      }
    });

    test('duplex: S32205 Cr 22,0–23,0 Mo 3,0–3,5; S31803 Cr 21,0–23,0 '
        'Mo 2,5–3,5; S32750 Mo 3,0–5,0 Mn ≤ 1,20', () {
      _range('1.4462', 's32205', PmiElement.cr, 22.0, 23.0);
      _range('1.4462', 's32205', PmiElement.mo, 3.0, 3.5);
      _range('1.4462', 's31803', PmiElement.cr, 21.0, 23.0);
      _range('1.4462', 's31803', PmiElement.mo, 2.5, 3.5);
      _range('1.4410', 's32750', PmiElement.mo, 3.0, 5.0);
      _range('1.4410', 's32750', PmiElement.mn, null, 1.20);
    });

    test('A335-23: P11 Cr 1,00–1,50, P12 Cr 0,80–1,25, P22 Cr 1,90–2,60, '
        'P91 V 0,18–0,25 Nb 0,06–0,10', () {
      _range('1.7335', 'p11', PmiElement.cr, 1.00, 1.50);
      _range('1.7335', 'p11', PmiElement.si, 0.50, 1.00);
      _range('1.7335', 'p12', PmiElement.cr, 0.80, 1.25);
      _range('1.7335', 'p12', PmiElement.mo, 0.44, 0.65);
      _range('1.7380', 'p22', PmiElement.cr, 1.90, 2.60);
      _range('1.7380', 'p22', PmiElement.mo, 0.87, 1.13);
      _range('1.4903', 'p91t1', PmiElement.cr, 8.00, 9.50);
      _range('1.4903', 'p91t1', PmiElement.v, 0.18, 0.25);
      _range('1.4903', 'p91t1', PmiElement.nb, 0.06, 0.10);
      _range('1.4903', 'p91t1', PmiElement.ni, null, 0.40);
      _range('1.4903', 'p91t2', PmiElement.ni, null, 0.20);
    });
  });

  group('wartości sprawdzone w normach (EN)', () {
    test('EN 10088-1:2014: 1.4301 Cr 17,5–19,5; 1.4404 Mo 2,00–2,50, Ni '
        '10,0–13,0; 1.4571 Ni 10,5–13,5, Ti 5 × C – 0,70', () {
      _range('1.4301', 'en', PmiElement.cr, 17.5, 19.5);
      _range('1.4301', 'en', PmiElement.ni, 8.0, 10.5);
      _range('1.4404', 'en', PmiElement.mo, 2.0, 2.5);
      _range('1.4404', 'en', PmiElement.ni, 10.0, 13.0);
      _range('1.4571', 'en', PmiElement.ni, 10.5, 13.5);
      final ti = _r('1.4571', 'en', PmiElement.ti);
      expect(ti.max, 0.70);
      expect(ti.carbonMin!.plusN, isFalse);
      expect(ti.carbonMin!.worstCaseMin, 0.40);
      _range('1.4462', 'en', PmiElement.mo, 2.5, 3.5);
      _range('1.4410', 'en', PmiElement.mo, 3.0, 4.5);
      _range('1.4539', 'en', PmiElement.cu, 1.2, 2.0);
      _range('1.4845', 'en', PmiElement.si, null, 1.5);
    });

    test('EN 10216-5 (rury): 1.4301 Cr od 17,0 — inaczej niż EN 10088', () {
      _range('1.4301', 'en10216', PmiElement.cr, 17.0, 19.5);
      final r = {
        PmiElement.cr: '17,2',
        PmiElement.ni: '8,5',
        PmiElement.mo: '0,1',
      };
      expect(_eval('1.4301', 'en10216', r).verdict, PmiVerdict.conforming);
      expect(_eval('1.4301', 'en', r).verdict, PmiVerdict.nonConforming);
    });

    test('EN 10216-2 i EN 10028-2: Cr-Mo — Mn i Ni różne dla rur i blach',
        () {
      _range('1.7335', 'en', PmiElement.mn, 0.40, 0.70);
      _range('1.7335', 'en10028', PmiElement.mn, 0.40, 1.00);
      _range('1.7335', 'en', PmiElement.ni, null, 0.30);
      _range('1.7380', 'en10028', PmiElement.mn, 0.40, 0.80);
      _range('1.4903', 'en', PmiElement.ni, null, 0.40);
      _range('1.4903', 'en10028', PmiElement.ni, null, 0.30);
      // P91 z Ni 0,35: rura zgodna, blacha nie.
      final r = {
        PmiElement.cr: '8,8',
        PmiElement.mo: '0,95',
        PmiElement.v: '0,21',
        PmiElement.nb: '0,08',
        PmiElement.ni: '0,35',
        PmiElement.mn: '0,45',
        PmiElement.si: '0,35',
      };
      expect(_eval('1.4903', 'en', r).verdict, PmiVerdict.conformingNoCarbon);
      expect(_eval('1.4903', 'en10028', r).verdict, PmiVerdict.nonConforming);
    });
  });

  group('EN i ASTM się różnią — ocena wobec wybranej normy', () {
    test('Cr 17,8 w 304: SA-240 (17,5–19,5) zgodny, A240-25a (18,0–20,0) '
        'niezgodny', () {
      // Mo — pierwiastek kontrolny 304 (bez odczytu: do weryfikacji).
      final r = {
        PmiElement.cr: '17,8',
        PmiElement.ni: '8,5',
        PmiElement.mo: '0,2',
      };
      expect(_eval('1.4301', 'sa240', r).verdict, PmiVerdict.conforming);
      expect(_eval('1.4301', 'a240', r).verdict, PmiVerdict.nonConforming);
    });

    test('Ni 12,5 w 304L: A312 zgodny (bez weryfikacji C), A240 niezgodny', () {
      final r = {
        PmiElement.cr: '18,5',
        PmiElement.ni: '12,5',
        PmiElement.mo: '0,1',
      };
      expect(_eval('1.4307', 'a312', r).verdict,
          PmiVerdict.conformingNoCarbon);
      expect(_eval('1.4307', 'a240', r).verdict, PmiVerdict.nonConforming);
    });

    test('13CrMo4-5 — Cr 0,9: P12 w zakresie, P11 poza (to nie ten sam '
        'gatunek)', () {
      // Mn (P12 0,30–0,61) i Si (P11 0,50–1,00) mają dolne granice —
      // wymagane.
      final r = {
        PmiElement.cr: '0,9',
        PmiElement.mo: '0,5',
        PmiElement.mn: '0,5',
        PmiElement.si: '0,3',
      };
      expect(_eval('1.7335', 'p12', r).verdict, PmiVerdict.conforming);
      expect(_eval('1.7335', 'p11', r).verdict, PmiVerdict.nonConforming);
      expect(pmiGradeById('1.7335')!.notePl, contains('P11'));
    });
  });

  group('węgiel: XRF nie mierzy C', () {
    test('304L, 316L, 904L, duplex, P91 — „zgodny (bez weryfikacji C)”', () {
      for (final id in ['1.4307', '1.4404', '1.4539', '1.4462', '1.4410',
          '1.4903']) {
        expect(pmiGradeById(id)!.carbonCritical, isTrue, reason: id);
      }
      final r = _eval('1.4404', 'en', {
        PmiElement.cr: '17,0',
        PmiElement.ni: '10,5',
        PmiElement.mo: '2,1',
      });
      expect(r.verdict, PmiVerdict.conformingNoCarbon);
    });

    test('316 i 316L z tego samego odczytu — oba pasują (różni je tylko C)',
        () {
      final readings = {
        PmiElement.cr: '17,0',
        PmiElement.ni: '10,5',
        PmiElement.mo: '2,1',
        PmiElement.mn: '1,2',
      };
      final fits = pmiNearestGrades(readings, kPmiGrades)
          .where((m) => m.fits)
          .map((m) => m.grade.id)
          .toSet();
      expect(fits, containsAll(['1.4401', '1.4404']));
      expect(fits, isNot(contains('1.4301')));
    });

    test('notatka XRF wymienia 304/304L, 316/316L i P91', () {
      final pl = pmiCarbonNote(en: false);
      expect(pl, contains('węgla'));
      expect(pl, contains('304L'));
      expect(pl, contains('316L'));
      expect(pl, contains('P91'));
      expect(pmiCarbonNote(en: true), contains('carbon'));
    });
  });

  group('pierwiastki odróżniające sąsiedni gatunek (przegląd)', () {
    test('304 (EN): Cr 17,6, Ni 10,3, Mo 2,1 → niezgodny, możliwy 316', () {
      final r = _eval('1.4301', 'en', {
        PmiElement.cr: '17,6',
        PmiElement.ni: '10,3',
        PmiElement.mo: '2,1',
      });
      expect(r.verdict, PmiVerdict.nonConforming);
      final mo = _check(r, PmiElement.mo);
      expect(mo.status, PmiElementStatus.outOfRange);
      expect(mo.note, PmiCheckNote.residualAbove);
      expect(mo.possibleGrade, '1.4401 / 316');
      final text =
          pmiElementStatusText(mo, grade: pmiGradeById('1.4301')!, en: false);
      expect(text, 'Mo 2,1 % — nie występuje w 1.4301 / 304 (próg resztkowy '
          '0,5 %); możliwy 1.4401 / 316');
    });

    test('304 z Mo 0,3 (pod progiem 0,5) — nie blokuje: zgodny', () {
      final r = _eval('1.4301', 'en', {
        PmiElement.cr: '18,0',
        PmiElement.ni: '9,0',
        PmiElement.mo: '0,3',
      });
      expect(r.verdict, PmiVerdict.conforming);
      expect(_check(r, PmiElement.mo).status, PmiElementStatus.notSpecified);
      // Równo z progiem — też nie blokuje (granica włącznie).
      expect(
          _eval('1.4301', 'en', {
            PmiElement.cr: '18,0',
            PmiElement.ni: '9,0',
            PmiElement.mo: '0,5',
          }).verdict,
          PmiVerdict.conforming);
    });

    test('304 z Mo 0,45 ± 0,1 — próg w niepewności → do weryfikacji', () {
      final r = _eval('1.4301', 'en', {
        PmiElement.cr: '18,0',
        PmiElement.ni: '9,0',
        PmiElement.mo: '0,45',
      }, u: {
        PmiElement.mo: '0,1'
      });
      expect(r.verdict, PmiVerdict.toVerify);
      expect(_check(r, PmiElement.mo).note, PmiCheckNote.residualNear);
    });

    test('304 bez odczytu Mo → do weryfikacji „brak odczytu Mo — nie '
        'wyklucza 316”', () {
      final r = _eval('1.4301', 'en', {
        PmiElement.cr: '18,0',
        PmiElement.ni: '9,0',
      });
      expect(r.verdict, PmiVerdict.toVerify);
      final mo = _check(r, PmiElement.mo);
      expect(mo.note, PmiCheckNote.controlMissing);
      expect(
          pmiElementStatusText(mo, grade: pmiGradeById('1.4301')!, en: false),
          contains('brak odczytu Mo — nie wyklucza 316'));
      // Mo kontrolny w 304L, 321, 310S; w A312 TP310S Mo ma zakres (≤ 0,75)
      // — tam zwykła ocena, bez wymogu odczytu.
      for (final id in ['1.4307', '1.4541', '1.4845']) {
        expect(pmiGradeById(id)!.controlElements, contains(PmiElement.mo),
            reason: id);
      }
      expect(
          _eval('1.4845', 'a312', {
            PmiElement.cr: '25',
            PmiElement.ni: '20',
          }).verdict,
          PmiVerdict.conforming);
    });

    test('Ti 0,3 w 304 → niezgodny, możliwy 321', () {
      final r = _eval('1.4301', 'en', {
        PmiElement.cr: '18,2',
        PmiElement.ni: '9,5',
        PmiElement.mo: '0,1',
        PmiElement.ti: '0,3',
      });
      expect(r.verdict, PmiVerdict.nonConforming);
      expect(_check(r, PmiElement.ti).possibleGrade, '1.4541 / 321');
    });

    test('P11 bez odczytu Si → brak werdyktu (Si 0,50–1,00 odróżnia od P12)',
        () {
      final p11 = {
        PmiElement.cr: '1,2',
        PmiElement.mo: '0,5',
        PmiElement.mn: '0,45',
      };
      final r = _eval('1.7335', 'p11', p11);
      expect(r.verdict, PmiVerdict.none);
      expect(r.reason, PmiNoVerdict.missingKey);
      expect(_check(r, PmiElement.si).status, PmiElementStatus.missing);
      expect(_eval('1.7335', 'p11', {...p11, PmiElement.si: '0,7'}).verdict,
          PmiVerdict.conforming);
      // Si 0,3 — to raczej P12, nie P11.
      expect(_eval('1.7335', 'p11', {...p11, PmiElement.si: '0,3'}).verdict,
          PmiVerdict.nonConforming);
    });

    test('P91 bez Mn albo bez Si → brak werdyktu; komplet → zgodny (bez '
        'weryfikacji C)', () {
      final full = {
        PmiElement.cr: '8,8',
        PmiElement.mo: '0,95',
        PmiElement.v: '0,21',
        PmiElement.nb: '0,08',
        PmiElement.mn: '0,45',
        PmiElement.si: '0,35',
      };
      for (final k in ['en', 'p91t1', 'p91t2']) {
        expect(_eval('1.4903', k, full).verdict,
            PmiVerdict.conformingNoCarbon,
            reason: k);
        final noMn = _eval('1.4903', k, {...full}..remove(PmiElement.mn));
        expect(noMn.reason, PmiNoVerdict.missingKey, reason: '$k bez Mn');
        final noSi = _eval('1.4903', k, {...full}..remove(PmiElement.si));
        expect(noSi.reason, PmiNoVerdict.missingKey, reason: '$k bez Si');
      }
    });

    test('wymagane = kluczowe + każdy pierwiastek z dolną granicą w normie',
        () {
      final p91 = pmiGradeById('1.4903')!;
      expect(p91.requiredIn(p91.specByKey('en')!),
          containsAll([PmiElement.si, PmiElement.mn, PmiElement.v]));
      // Blacha EN 10028-2: Si bez dolnej granicy — nie wymagany.
      expect(p91.requiredIn(p91.specByKey('en10028')!),
          isNot(contains(PmiElement.si)));
      final g304 = pmiGradeById('1.4301')!;
      expect(g304.requiredIn(g304.specByKey('en')!),
          {PmiElement.cr, PmiElement.ni});
    });
  });

  test('podpowiedź: 304L z Ti 0,01 nie wygląda jak 321', () {
    final m = pmiNearestGrades({
      PmiElement.cr: '18,2',
      PmiElement.ni: '8,4',
      PmiElement.ti: '0,01',
    }, kPmiGrades);
    expect(m.first.fits, isTrue);
    expect(['1.4301', '1.4307'], contains(m.first.grade.id));
    final ti = m.where((e) => e.grade.id == '1.4541');
    expect(ti.every((e) => !e.fits), isTrue);
  });
}
