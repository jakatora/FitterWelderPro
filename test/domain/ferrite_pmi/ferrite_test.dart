// Ferryt: zakres włącznie z granicami, odczyty „tak jak wpisano” (bez
// zaokrąglania w stronę zgodności), FN ≠ %, reguła „każdy odczyt” i „średnia
// z N”, brak / nieczytelne dane ≠ OK, preset dla innego miejsca.

import 'package:flutter_test/flutter_test.dart';

import 'package:cut_list_app/domain/ferrite_pmi/ferrite.dart';
import 'ferrite_mean_reference.dart';

const _fn30to70 = FerriteRequirement(min: 30, max: 70, unit: FerriteUnit.fn);

FerriteSite _site(List<String> r,
        {FerriteLocation loc = FerriteLocation.weld}) =>
    FerriteSite(id: 's', location: loc, readings: r);

FerriteSiteResult _eval(
  List<String> readings, {
  FerriteRequirement? req = _fn30to70,
  FerriteUnit unit = FerriteUnit.fn,
  FerriteRule rule = FerriteRule.everyReading,
  String n = '',
  FerritePreset? preset,
  FerriteLocation loc = FerriteLocation.weld,
}) =>
    evaluateFerriteSite(_site(readings, loc: loc),
        requirement: req,
        readingUnit: unit,
        rule: rule,
        minCountText: n,
        preset: preset);

void main() {
  test('decimal means match independent rational reference values', () {
    for (final (readings, expected) in ferriteMeanReferences) {
      final result = _eval(readings,
          req: const FerriteRequirement(min: 0, unit: FerriteUnit.fn),
          rule: FerriteRule.average, n: '1');
      expect(result.mean, double.parse(expected), reason: readings.join(' / '));
      expect(result.mean!.isFinite, isTrue);
      expect(result.verdict, FerriteVerdict.pass);
    }
  });

  test('averaging cannot round an out-of-range reading into conformance', () {
    for (final text in ['29.9999999996', '70.0000000004']) {
      final single = _eval([text], rule: FerriteRule.average, n: '1');
      expect(single.verdict, FerriteVerdict.fail, reason: text);
      expect(single.mean, double.parse(text));
      final repeated = _eval([text, text], rule: FerriteRule.average, n: '2');
      expect(repeated.verdict, FerriteVerdict.fail, reason: text);
      expect(repeated.mean, double.parse(text));
    }
  });

  test('a finite average does not overflow when the sum is larger than double', () {
    const bounds = FerriteRequirement(min: 1e308, max: 1e308, unit: FerriteUnit.fn);
    final result = _eval(['1e308', '1e308'], req: bounds,
        rule: FerriteRule.average, n: '2');
    expect(result.mean, 1e308);
    expect(result.verdict, FerriteVerdict.pass);
  });

  test('exact formatting preserves values in scientific notation in PL and EN', () {
    for (final value in [1e30, -1e30, 1e-13, double.minPositive, double.maxFinite]) {
      for (final en in [false, true]) {
        final text = ferriteExact(value, en: en);
        expect(double.parse(text.replaceAll(',', '.')), value, reason: text);
      }
    }
  });

  group('każdy odczyt w zakresie (domyślna reguła)', () {
    test('28, 31, 45 przy FN 30–70 → poza zakresem (28 poniżej)', () {
      final r = _eval(['28', '31', '45']);
      expect(r.verdict, FerriteVerdict.fail);
      expect(r.statuses, [
        FerriteReadingStatus.below,
        FerriteReadingStatus.inRange,
        FerriteReadingStatus.inRange,
      ]);
      expect(r.outOfRangeCount, 1);
    });

    test('granice włącznie: 30 i 70 przy FN 30–70 → w zakresie', () {
      expect(_eval(['30', '70']).verdict, FerriteVerdict.pass);
      expect(_eval(['70,0000001']).verdict, FerriteVerdict.fail);
      expect(_eval(['29,9999999']).verdict, FerriteVerdict.fail);
    });

    test('bez zaokrąglania: 29,96 przy min 30 to poniżej, nie „30”', () {
      final r = _eval(['29,96']);
      expect(r.verdict, FerriteVerdict.fail);
      expect(r.statuses.single, FerriteReadingStatus.below);
    });

    test('przecinek = kropka: ten sam werdykt', () {
      for (final pair in [
        ['30,5', '30.5'],
        ['29,99', '29.99'],
        ['70,01', '70.01'],
      ]) {
        expect(_eval([pair[0]]).verdict, _eval([pair[1]]).verdict,
            reason: pair.join(' / '));
        expect(_eval([pair[0]]).values, _eval([pair[1]]).values);
      }
    });

    test('nieczytelny odczyt ≠ OK: brak werdyktu, gdy reszta w zakresie', () {
      final r = _eval(['31', '1,2,3']);
      expect(r.verdict, FerriteVerdict.none);
      expect(r.reason, FerriteNoVerdict.invalidReading);
      expect(r.statuses.last, FerriteReadingStatus.invalid);
    });

    test('nieczytelny obok odczytu poza zakresem → poza zakresem', () {
      expect(_eval(['25', 'abc']).verdict, FerriteVerdict.fail);
    });

    test('ujemny odczyt i > 100 % → nieczytelny', () {
      expect(_eval(['-1']).reason, FerriteNoVerdict.invalidReading);
      const pct = FerriteRequirement(min: 30, max: 70, unit: FerriteUnit.percent);
      final r = _eval(['45', '101'], req: pct, unit: FerriteUnit.percent);
      expect(r.verdict, FerriteVerdict.none);
      expect(r.reason, FerriteNoVerdict.invalidReading);
      // 100 % — fizycznie możliwe, ale poza 30–70.
      expect(_eval(['100'], req: pct, unit: FerriteUnit.percent).verdict,
          FerriteVerdict.fail);
    });

    test('brak odczytów → brak werdyktu', () {
      final r = _eval([]);
      expect(r.verdict, FerriteVerdict.none);
      expect(r.reason, FerriteNoVerdict.noReadings);
    });
  });

  group('jednostki: FN ≠ %', () {
    test('odczyty FN przy wymaganiu w % → brak werdyktu (bez przeliczania)',
        () {
      const pct = FerriteRequirement(min: 30, max: 70, unit: FerriteUnit.percent);
      final r = _eval(['45', '50'], req: pct, unit: FerriteUnit.fn);
      expect(r.verdict, FerriteVerdict.none);
      expect(r.reason, FerriteNoVerdict.unitMismatch);
      // Statusy odczytów nie są liczone (nie ma z czym porównać).
      expect(r.statuses, [null, null]);
    });

    test('odczyty % przy wymaganiu FN → brak werdyktu', () {
      final r = _eval(['45'], unit: FerriteUnit.percent);
      expect(r.reason, FerriteNoVerdict.unitMismatch);
    });

    test('ta sama jednostka % → werdykt', () {
      const pct = FerriteRequirement(min: 30, max: 70, unit: FerriteUnit.percent);
      expect(_eval(['45'], req: pct, unit: FerriteUnit.percent).verdict,
          FerriteVerdict.pass);
    });
  });

  group('wymaganie', () {
    test('nieprawidłowe zakresy → brak werdyktu', () {
      for (final req in [
        const FerriteRequirement(unit: FerriteUnit.fn),
        const FerriteRequirement(min: 70, max: 30, unit: FerriteUnit.fn),
        const FerriteRequirement(min: -1, max: 10, unit: FerriteUnit.fn),
        const FerriteRequirement(min: 30, max: 120, unit: FerriteUnit.percent),
        const FerriteRequirement(min: double.nan, max: 70, unit: FerriteUnit.fn),
      ]) {
        expect(req.isValid, isFalse, reason: req.text(en: false));
        final r = _eval(['45'], req: req, unit: req.unit);
        expect(r.verdict, FerriteVerdict.none);
        expect(r.reason, FerriteNoVerdict.invalidRequirement);
      }
    });

    test('granica otwarta: FN ≥ 3 i ≤ 0,5 %', () {
      const min3 = FerriteRequirement(min: 3, unit: FerriteUnit.fn);
      expect(_eval(['3'], req: min3).verdict, FerriteVerdict.pass);
      expect(_eval(['2,9'], req: min3).verdict, FerriteVerdict.fail);
      expect(_eval(['250'], req: min3).verdict, FerriteVerdict.pass);
      const max05 = FerriteRequirement(max: 0.5, unit: FerriteUnit.percent);
      expect(_eval(['0,5'], req: max05, unit: FerriteUnit.percent).verdict,
          FerriteVerdict.pass);
      expect(_eval(['0,51'], req: max05, unit: FerriteUnit.percent).verdict,
          FerriteVerdict.fail);
    });

    test('preset nieznany (requirement null) → brak werdyktu', () {
      expect(_eval(['45'], req: null).reason, FerriteNoVerdict.unknownPreset);
    });

    test('tekst zakresu z jednostką i przecinkiem', () {
      expect(_fn30to70.text(en: false), 'FN 30–70');
      expect(
          const FerriteRequirement(min: 3, unit: FerriteUnit.fn).text(en: false),
          'FN ≥ 3');
      expect(
          const FerriteRequirement(max: 0.5, unit: FerriteUnit.percent)
              .text(en: false),
          '≤ 0,5 %');
      expect(
          const FerriteRequirement(max: 0.5, unit: FerriteUnit.percent)
              .text(en: true),
          '≤ 0.5 %');
    });
  });

  group('średnia z N odczytów', () {
    test('średnia w zakresie mimo pojedynczego odczytu poza — w zakresie', () {
      final r = _eval(['28', '31', '45'], rule: FerriteRule.average, n: '3');
      expect(r.verdict, FerriteVerdict.pass);
      expect(r.mean, closeTo(34.6667, 1e-3));
      // Pojedynczy poza zakresem — widoczny jako informacja.
      expect(r.outOfRangeCount, 1);
    });

    test('mniej odczytów niż N → brak werdyktu', () {
      final r = _eval(['31', '45'], rule: FerriteRule.average, n: '3');
      expect(r.verdict, FerriteVerdict.none);
      expect(r.reason, FerriteNoVerdict.tooFewReadings);
    });

    test('N puste, 0, ułamek albo nieczytelne → brak werdyktu', () {
      for (final n in ['', '0', '2,5', 'x', '-3']) {
        final r = _eval(['31', '45', '50'], rule: FerriteRule.average, n: n);
        expect(r.verdict, FerriteVerdict.none, reason: n);
        expect(r.reason, FerriteNoVerdict.invalidCount, reason: n);
      }
    });

    test('nieczytelny odczyt przy średniej → brak werdyktu', () {
      final r =
          _eval(['31', '45', '1,2,3'], rule: FerriteRule.average, n: '2');
      expect(r.verdict, FerriteVerdict.none);
      expect(r.reason, FerriteNoVerdict.invalidReading);
    });

    test('średnia równa granicy = w zakresie (bez szumu liczb)', () {
      expect(_eval(['29,9', '30,1'], rule: FerriteRule.average, n: '2').mean,
          30);
      // (0,1 + 0,2) / 2 = 0,15000000000000002 bez wyrównania — „powyżej”.
      const max015 = FerriteRequirement(max: 0.15, unit: FerriteUnit.percent);
      final r = _eval(['0,1', '0,2'],
          req: max015,
          unit: FerriteUnit.percent,
          rule: FerriteRule.average,
          n: '2');
      expect(r.mean, 0.15);
      expect(r.verdict, FerriteVerdict.pass);
    });

    test('średnia poza zakresem → poza zakresem', () {
      final r = _eval(['25', '30', '31'], rule: FerriteRule.average, n: '3');
      expect(r.verdict, FerriteVerdict.fail);
    });
  });

  group('preset dla innego miejsca', () {
    const weldOnly = FerritePreset(
      id: 't',
      group: FerritePresetGroup.duplex,
      requirement: _fn30to70,
      appliesTo: {FerriteLocation.weld, FerriteLocation.hazA,
          FerriteLocation.hazB},
      titlePl: 't',
      titleEn: 't',
      sourcePl: 's',
      sourceEn: 's',
    );

    test('materiał rodzimy przy presecie dla spoiny / SWC → brak werdyktu',
        () {
      final r = _eval(['45'], preset: weldOnly, loc: FerriteLocation.base);
      expect(r.verdict, FerriteVerdict.none);
      expect(r.reason, FerriteNoVerdict.notForLocation);
      expect(_eval(['45'], preset: weldOnly, loc: FerriteLocation.hazB).verdict,
          FerriteVerdict.pass);
    });
  });

  group('minimalna liczba odczytów (przegląd)', () {
    const min3 = FerritePreset(
      id: 'm3',
      group: FerritePresetGroup.austenitic,
      requirement: FerriteRequirement(min: 3, max: 10, unit: FerriteUnit.fn),
      appliesTo: {FerriteLocation.weld},
      titlePl: 't',
      titleEn: 't',
      sourcePl: 's',
      sourceEn: 's',
      minReadings: 3,
    );
    FerriteSiteResult p(List<String> r, {String n = '',
            FerriteRule rule = FerriteRule.everyReading}) =>
        _eval(r, req: min3.requirement, preset: min3, n: n, rule: rule);

    test('preset ≥ 3 odczytów: 1 odczyt w zakresie → brak werdyktu', () {
      final r = p(['5']);
      expect(r.verdict, FerriteVerdict.none);
      expect(r.reason, FerriteNoVerdict.tooFewReadings);
      expect(r.minCount, 3);
      expect(p(['5', '6', '7']).verdict, FerriteVerdict.pass);
    });

    test('preset ≥ 3: odczyt poza zakresem i tak „poza zakresem”', () {
      expect(p(['5', '12']).verdict, FerriteVerdict.fail);
    });

    test('pole może wymaganie presetu tylko podnieść (2 → 3, 4 → 4)', () {
      expect(ferriteEffectiveMinCount('2',
          rule: FerriteRule.everyReading, preset: min3), 3);
      expect(ferriteEffectiveMinCount('4',
          rule: FerriteRule.everyReading, preset: min3), 4);
      expect(p(['5', '6', '7'], n: '4').reason,
          FerriteNoVerdict.tooFewReadings);
      // Średnia z N = 2 przy presecie ≥ 3 → obowiązuje 3.
      expect(p(['5', '6'], n: '2', rule: FerriteRule.average).reason,
          FerriteNoVerdict.tooFewReadings);
    });

    test('zakres ręczny: pole puste = 1, „3” przy 2 odczytach → brak '
        'werdyktu, „0” / ułamek → brak werdyktu', () {
      expect(_eval(['45']).verdict, FerriteVerdict.pass);
      expect(_eval(['45', '50'], n: '3').reason,
          FerriteNoVerdict.tooFewReadings);
      expect(_eval(['45', '50', '55'], n: '3').verdict, FerriteVerdict.pass);
      for (final n in ['0', '1,5', 'x']) {
        expect(_eval(['45'], n: n).reason, FerriteNoVerdict.invalidCount,
            reason: n);
      }
    });
  });

  group('protokół: werdykt wielu miejsc', () {
    FerriteSiteResult r(List<String> v) => _eval(v);
    test('jedno poza → poza; wszystkie w zakresie → w zakresie; inaczej brak',
        () {
      expect(ferriteOverall([r(['45']), r(['28'])]), FerriteVerdict.fail);
      expect(ferriteOverall([r(['45']), r(['50'])]), FerriteVerdict.pass);
      expect(ferriteOverall([r(['45']), r([])]), FerriteVerdict.none);
      expect(ferriteOverall([]), FerriteVerdict.none);
    });
  });

  group('formatowanie', () {
    test('odczyt tak, jak wpisano — bez zaokrąglania', () {
      expect(ferriteExact(29.96, en: false), '29,96');
      expect(ferriteExact(30, en: false), '30');
      expect(ferriteExact(30.123456, en: true), '30.123456');
    });

    test('średnia zaokrąglana w stronę werdyktu', () {
      expect(ferriteFormatAgainst(29.96, _fn30to70, en: false), '29,9');
      expect(ferriteFormatAgainst(70.04, _fn30to70, en: false), '70,1');
      expect(ferriteFormatAgainst(34.6667, _fn30to70, en: false), '34,7');
      const odd = FerriteRequirement(min: 30.04, max: 70, unit: FerriteUnit.fn);
      // 30,04 zaokrąglone do 30,0 wyglądałoby na „poniżej”.
      expect(ferriteFormatAgainst(30.04, odd, en: false), '30,04');
    });
  });
}
