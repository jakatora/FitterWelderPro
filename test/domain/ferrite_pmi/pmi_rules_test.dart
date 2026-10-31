// PMI — reguły werdyktu na gatunkach testowych (niezależnie od tabeli
// norm): zakres włącznie z granicami, niepewność przyrządu (domyślnie 0),
// brak odczytu kluczowego pierwiastka, nieczytelne dane, suma > 100 %,
// minimum Ti zależne od C, gatunki niskowęglowe, przecinek = kropka.

import 'package:flutter_test/flutter_test.dart';

import 'package:cut_list_app/domain/ferrite_pmi/pmi.dart';

const _spec = PmiSpec(
  key: 't',
  standard: 'TEST',
  designation: 'T',
  carbonText: 'C ≤ 0,03',
  ranges: {
    PmiElement.cr: PmiRange(min: 16.5, max: 18.5),
    PmiElement.ni: PmiRange(min: 10, max: 13),
    PmiElement.mo: PmiRange(min: 2, max: 2.5),
    PmiElement.mn: PmiRange(max: 2),
  },
  sourcePl: 's',
  sourceEn: 's',
);

const _grade = PmiGrade(
  id: 'g',
  family: PmiFamily.austenitic,
  title: 'G',
  specs: [_spec],
  keyElements: {PmiElement.cr, PmiElement.ni, PmiElement.mo},
);

const _gradeL = PmiGrade(
  id: 'gl',
  family: PmiFamily.austenitic,
  title: 'GL',
  specs: [_spec],
  keyElements: {PmiElement.cr, PmiElement.ni, PmiElement.mo},
  carbonCritical: true,
);

const _tiSpec = PmiSpec(
  key: 'ti',
  standard: 'TEST',
  designation: 'Ti',
  carbonText: 'C ≤ 0,08',
  ranges: {
    PmiElement.cr: PmiRange(min: 17, max: 19),
    PmiElement.ni: PmiRange(min: 9, max: 12),
    PmiElement.ti: PmiRange(
        max: 0.7, carbonMin: PmiCarbonLinkedMin(factor: 5, cMax: 0.08)),
  },
  sourcePl: 's',
  sourceEn: 's',
);

const _tiGrade = PmiGrade(
  id: 'ti',
  family: PmiFamily.austenitic,
  title: 'Ti',
  specs: [_tiSpec],
  keyElements: {PmiElement.cr, PmiElement.ni, PmiElement.ti},
);

PmiResult _eval(Map<PmiElement, String> r,
        {Map<PmiElement, String> u = const {}, PmiGrade grade = _grade}) =>
    evaluatePmi(grade: grade, spec: grade.specs.first, readings: r, uncertainty: u);

const _ok = {
  PmiElement.cr: '17,0',
  PmiElement.ni: '11,0',
  PmiElement.mo: '2,1',
};

void main() {
  test('PMI interval does not snap small deviations or uncertainties into range', () {
    expect(pmiIntervalStatus(16.4999999996, 0, 16.5, 18.5), PmiElementStatus.outOfRange);
    expect(pmiIntervalStatus(18.5000000004, 0, 16.5, 18.5), PmiElementStatus.outOfRange);
    expect(pmiIntervalStatus(16.5, 4e-10, 16.5, 18.5), PmiElementStatus.toVerify);
    expect(pmiIntervalStatus(16.5, 1e-16, 16.5, 18.5), PmiElementStatus.toVerify);
    expect(_eval({..._ok, PmiElement.mo: '2.1'}, u: {PmiElement.mo: '0.1000000004'}).verdict,
        PmiVerdict.toVerify);
  });

  test('invalid interval input remains invalid without an arithmetic exception', () {
    expect(pmiIntervalStatus(double.nan, 0, 16.5, 18.5), PmiElementStatus.invalid);
    expect(pmiIntervalStatus(17, -1, 16.5, 18.5), PmiElementStatus.invalid);
    expect(pmiIntervalStatus(17, 0, double.infinity, 18.5), PmiElementStatus.invalid);
  });

  test('residual and carbon-dependent limits retain deviations below 1e-9', () {
    expect(_eval({..._ok, PmiElement.cu: '1.0000000004'}).verdict, PmiVerdict.nonConforming);
    final ti = _eval({PmiElement.cr: '18', PmiElement.ni: '10', PmiElement.ti: '0.3999999996'}, grade: _tiGrade);
    expect(ti.verdict, PmiVerdict.toVerify);
    expect(ti.checks.firstWhere((c) => c.element == PmiElement.ti).status,
        PmiElementStatus.carbonDependent);
  });

  test('chemical total above 100 is not rounded into a physical total', () {
    final result = _eval({PmiElement.cr: '90', PmiElement.ni: '10', PmiElement.mo: '0.0000000004'});
    expect(result.verdict, PmiVerdict.none);
    expect(result.reason, PmiNoVerdict.sumOver100);
  });

  test('wszystkie kluczowe w zakresie → zgodny', () {
    expect(_eval(_ok).verdict, PmiVerdict.conforming);
  });

  test('gatunek „L”: najlepszy werdykt „zgodny (bez weryfikacji C)”', () {
    expect(_eval(_ok, grade: _gradeL).verdict, PmiVerdict.conformingNoCarbon);
  });

  test('Mo 1,9 przy min 2,0, u = 0 → niezgodny', () {
    final r = _eval({..._ok, PmiElement.mo: '1,9'});
    expect(r.verdict, PmiVerdict.nonConforming);
    expect(r.checks.firstWhere((c) => c.element == PmiElement.mo).status,
        PmiElementStatus.outOfRange);
  });

  test('Mo 1,9 ± 0,1 przy min 2,0 → do weryfikacji', () {
    final r = _eval({..._ok, PmiElement.mo: '1,9'}, u: {PmiElement.mo: '0,1'});
    expect(r.verdict, PmiVerdict.toVerify);
  });

  test('Mo 1,89 ± 0,1 → niezgodny (cały przedział poniżej)', () {
    final r = _eval({..._ok, PmiElement.mo: '1,89'}, u: {PmiElement.mo: '0,1'});
    expect(r.verdict, PmiVerdict.nonConforming);
  });

  test('w zakresie, ale bliżej granicy niż niepewność → do weryfikacji', () {
    final r = _eval({..._ok, PmiElement.mo: '2,05'}, u: {PmiElement.mo: '0,1'});
    expect(r.verdict, PmiVerdict.toVerify);
    final ok = _eval({..._ok, PmiElement.mo: '2,1'}, u: {PmiElement.mo: '0,1'});
    expect(ok.verdict, PmiVerdict.conforming);
  });

  test('granice włącznie: Cr 16,5 i 18,5 → w zakresie', () {
    expect(_eval({..._ok, PmiElement.cr: '16,5'}).verdict,
        PmiVerdict.conforming);
    expect(_eval({..._ok, PmiElement.cr: '18,5'}).verdict,
        PmiVerdict.conforming);
    expect(_eval({..._ok, PmiElement.cr: '16,49'}).verdict,
        PmiVerdict.nonConforming);
  });

  test('przecinek = kropka', () {
    for (final mo in ['1,9', '2,0', '2,5', '2,51']) {
      final dot = mo.replaceAll(',', '.');
      expect(_eval({..._ok, PmiElement.mo: mo}).verdict,
          _eval({..._ok, PmiElement.mo: dot}).verdict,
          reason: mo);
    }
  });

  test('kluczowy pierwiastek bez odczytu → brak werdyktu', () {
    final r = _eval({PmiElement.cr: '17', PmiElement.ni: '11'});
    expect(r.verdict, PmiVerdict.none);
    expect(r.reason, PmiNoVerdict.missingKey);
  });

  test('brak kluczowego, ale inny wyraźnie poza → niezgodny', () {
    final r = _eval({PmiElement.cr: '12', PmiElement.ni: '11'});
    expect(r.verdict, PmiVerdict.nonConforming);
  });

  test('wpisany niekluczowy z zakresem w normie też oceniany (Mn 2,5)', () {
    final r = _eval({..._ok, PmiElement.mn: '2,5'});
    expect(r.verdict, PmiVerdict.nonConforming);
  });

  test('wpisany pierwiastek bez zakresu w normie — tylko informacja', () {
    final r = _eval({..._ok, PmiElement.cu: '0,3'});
    expect(r.verdict, PmiVerdict.conforming);
    expect(r.checks.firstWhere((c) => c.element == PmiElement.cu).status,
        PmiElementStatus.notSpecified);
  });

  test('nieczytelny odczyt albo niepewność → brak werdyktu', () {
    expect(_eval({..._ok, PmiElement.cr: '1,7,0'}).reason,
        PmiNoVerdict.invalidInput);
    expect(_eval(_ok, u: {PmiElement.cr: 'x'}).reason,
        PmiNoVerdict.invalidInput);
    expect(_eval(_ok, u: {PmiElement.cr: '-0,1'}).reason,
        PmiNoVerdict.invalidInput);
    expect(_eval({..._ok, PmiElement.cu: '-1'}).reason,
        PmiNoVerdict.invalidInput);
  });

  test('suma > 100 % (np. 170 zamiast 17,0) → brak werdyktu', () {
    final r = _eval({..._ok, PmiElement.cr: '95'});
    expect(r.verdict, PmiVerdict.none);
    expect(r.reason, PmiNoVerdict.sumOver100);
  });

  test('brak gatunku albo normy → brak werdyktu', () {
    final r = evaluatePmi(grade: null, spec: null, readings: _ok);
    expect(r.verdict, PmiVerdict.none);
    expect(r.reason, PmiNoVerdict.noGrade);
  });

  group('minimum Ti = 5 × C (XRF nie mierzy C)', () {
    const base = {PmiElement.cr: '18', PmiElement.ni: '10'};
    test('Ti ≥ 5 × Cmax (0,40) → w zakresie', () {
      expect(_eval({...base, PmiElement.ti: '0,40'}, grade: _tiGrade).verdict,
          PmiVerdict.conforming);
    });
    test('Ti 0,30 < 5 × Cmax → do weryfikacji (zależy od C)', () {
      final r = _eval({...base, PmiElement.ti: '0,30'}, grade: _tiGrade);
      expect(r.verdict, PmiVerdict.toVerify);
      expect(r.checks.firstWhere((c) => c.element == PmiElement.ti).status,
          PmiElementStatus.carbonDependent);
    });
    test('Ti 0 (nie wykryty) → niezgodny', () {
      expect(_eval({...base, PmiElement.ti: '0'}, grade: _tiGrade).verdict,
          PmiVerdict.nonConforming);
    });
    test('Ti 0,75 > 0,70 → niezgodny', () {
      expect(_eval({...base, PmiElement.ti: '0,75'}, grade: _tiGrade).verdict,
          PmiVerdict.nonConforming);
    });
  });

  test('przedział: równość z granicą po odjęciu niepewności = w zakresie', () {
    // 16,8 − 0,3 = 16,500000000000004 bez wyrównania.
    expect(pmiIntervalStatus(16.8, 0.3, 16.5, 18.5), PmiElementStatus.inRange);
    expect(pmiIntervalStatus(16.2, 0.3, 16.5, 18.5), PmiElementStatus.toVerify);
    expect(pmiIntervalStatus(16.19, 0.3, 16.5, 18.5),
        PmiElementStatus.outOfRange);
  });
}
