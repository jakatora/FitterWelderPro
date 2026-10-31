// Protokół „Ferryt i PMI”: JSON w obie strony bez zmiany odczytów (tekst
// „tak jak wpisano”), wymaganie z presetu / ze specyfikacji, nieznany preset
// i wariant normy → brak werdyktu, puste miejsca pominięte w ocenie, tekst
// protokołu do udostępnienia.

import 'package:flutter_test/flutter_test.dart';

import 'package:cut_list_app/domain/ferrite_pmi/ferrite.dart';
import 'package:cut_list_app/domain/ferrite_pmi/ferrite_pmi_protocol.dart';
import 'package:cut_list_app/domain/ferrite_pmi/ferrite_pmi_sources.dart';
import 'package:cut_list_app/domain/ferrite_pmi/ferrite_pmi_text.dart';
import 'package:cut_list_app/domain/ferrite_pmi/pmi.dart';

final _now = DateTime(2026, 10, 18, 9, 30);

FerritePmiProtocol _protocol() => FerritePmiProtocol(
      id: 'p1',
      date: '2026-10-18',
      title: 'W-12',
      inspector: 'J. Kowalski',
      instrument: 'Ferrytomierz FMP30, kal. 2026-09',
      customMin: '30',
      customMax: '70',
      sites: const [
        FerriteSite(
            id: 's1',
            location: FerriteLocation.weld,
            label: 'lico',
            readings: ['28', '31,0', '45.50']),
        FerriteSite(id: 's2', location: FerriteLocation.hazA),
      ],
      pmi: const [
        PmiItem(
          id: 'i1',
          label: 'Rura poz. 3',
          gradeId: '1.4404',
          readings: {
            PmiElement.cr: '17,0',
            PmiElement.ni: '10,5',
            PmiElement.mo: '1,9',
          },
          uncertainty: {PmiElement.mo: '0,1'},
        ),
      ],
      createdAt: 1,
      updatedAt: 2,
    );

void main() {
  test('opaque-only data is retained, and known failures remain failures', () {
    const opaque = FerritePmiProtocol(
        id: 'r',
        date: '2026-10-31',
        unreadableSites: [null],
        unreadablePmi: [false]);
    expect(opaque.isBlank, isFalse);
    expect(opaque.hasFerrite, isTrue);
    expect(opaque.hasPmi, isTrue);
    expect(opaque.ferriteVerdict, FerriteVerdict.none);
    expect(FerritePmiProtocol.fromJson(opaque.toJson())!.toJson(),
        opaque.toJson());
    final failing =
        opaque.copyWith(customMin: '30', customMax: '70', sites: const [
      FerriteSite(id: 's', location: FerriteLocation.weld, readings: ['12']),
    ]);
    expect(failing.ferriteVerdict, FerriteVerdict.fail);
    expect(failing.incomplete, isTrue);
  });

  test('unreadable whole locations cannot disappear into a passing protocol',
      () {
    final broken = {
      'id': 'future',
      'loc': 'unknown-location',
      'readings': ['12']
    };
    final raw = _protocol().copyWith(sites: const [
      FerriteSite(id: 's', location: FerriteLocation.weld, readings: ['45']),
    ]).toJson();
    raw['sites'] = [
      {
        'id': 's',
        'loc': 'weld',
        'readings': ['45']
      },
      broken,
    ];
    final restored = FerritePmiProtocol.fromJson(raw)!;
    expect(restored.ferriteVerdict, FerriteVerdict.none);
    expect(ferritePmiProtocolText(restored, en: true, now: _now),
        contains('Incomplete record'));
    final saved = restored.copyWith(title: 'Edited').toJson();
    expect(saved.toString(), contains('unknown-location'));
    final reloaded = FerritePmiProtocol.fromJson(saved)!;
    expect(reloaded.ferriteVerdict, FerriteVerdict.none);
    expect(reloaded.droppedOnLoad, 0,
        reason:
            'Preserved opaque data must not repeatedly consume backup slots');
  });

  test('malformed measurement containers are retained in the saved protocol',
      () {
    for (final field in ['sites', 'pmi']) {
      final raw = _protocol().toJson();
      raw[field] = {
        'unreadable-original': [12, false]
      };
      final restored = FerritePmiProtocol.fromJson(raw)!;
      expect(restored.droppedOnLoad, 1, reason: field);
      expect(restored.toJson().toString(), contains('unreadable-original'));
      expect(ferritePmiProtocolText(restored, en: false, now: _now),
          contains('Niepełny protokół'));
      final reloaded = FerritePmiProtocol.fromJson(restored.toJson())!;
      expect(reloaded.toJson(), restored.toJson());
      expect(reloaded.droppedOnLoad, 0);
    }
  });

  test('unreadable restored ferrite readings cannot disappear into a pass', () {
    for (final invalid in [null, 45, true, <String, Object?>{}, <Object?>[]]) {
      final raw = _protocol().copyWith(sites: const [
        FerriteSite(id: 's', location: FerriteLocation.weld, readings: ['45']),
      ]).toJson();
      raw['sites'] = [
        {
          'id': 's',
          'loc': 'weld',
          'readings': ['45', invalid]
        },
      ];
      final restored = FerritePmiProtocol.fromJson(raw)!;
      expect(restored.droppedOnLoad, 1);
      expect(restored.ferriteVerdict, FerriteVerdict.none);
      expect(restored.sites.single.readings.length, 2);
      expect(restored.evaluateFerrite().single.reason,
          FerriteNoVerdict.invalidReading);
      expect(ferritePmiProtocolText(restored, en: false, now: _now),
          contains('Wynik ferrytu: BRAK WERDYKTU'));
      expect(FerritePmiProtocol.fromJson(restored.toJson())!.ferriteVerdict,
          FerriteVerdict.none,
          reason: 'Saving cannot erase the invalid measurement');
      expect(
          restored.copyWith(sites: [
            restored.sites.single.copyWith(readings: ['45']),
          ]).ferriteVerdict,
          FerriteVerdict.pass,
          reason: 'An explicit correction must allow a new valid assessment');
    }
  });

  test(
      'restored invalid requirements cannot become open limits or default rules',
      () {
    for (final field in ['min', 'max', 'n', 'preset']) {
      final raw = _protocol().copyWith(sites: const [
        FerriteSite(id: 's', location: FerriteLocation.weld, readings: ['45']),
      ]).toJson();
      raw[field] = 30;
      final restored = FerritePmiProtocol.fromJson(raw)!;
      expect(restored.ferriteVerdict, FerriteVerdict.none, reason: field);
      expect(restored.droppedOnLoad, 1, reason: field);
      expect(FerritePmiProtocol.fromJson(restored.toJson())!.ferriteVerdict,
          FerriteVerdict.none,
          reason: field);
    }
  });

  test(
      'restored malformed reading container cannot remove a failed measurement site',
      () {
    final raw = _protocol().toJson();
    raw['sites'] = [
      {
        'id': 'good',
        'loc': 'weld',
        'readings': ['45']
      },
      {
        'id': 'broken',
        'loc': 'hazA',
        'readings': {'value': '45'}
      },
    ];
    final restored = FerritePmiProtocol.fromJson(raw)!;
    expect(restored.ferriteVerdict, FerriteVerdict.none);
    expect(restored.droppedOnLoad, 1);
    expect(restored.filledSites.length, 2);
  });

  test(
      'invalid restored PMI values and uncertainties are not silently absent or zero',
      () {
    const valid = PmiItem(id: 'pmi', gradeId: '1.4404', readings: {
      PmiElement.cr: '17',
      PmiElement.ni: '11',
      PmiElement.mo: '2.2',
    });
    expect(valid.evaluate().verdict, PmiVerdict.conformingNoCarbon);
    for (final field in ['r', 'u']) {
      for (final invalid in [
        null,
        0.2,
        true,
        <String, Object?>{},
        <Object?>[]
      ]) {
        final raw = valid.toJson();
        raw[field] = {
          ...raw[field] as Map,
          (field == 'r' ? 'cu' : 'cr'): invalid
        };
        final (item, lost) = PmiItem.fromJson(raw);
        expect(lost, 1);
        expect(item!.evaluate().verdict, PmiVerdict.none);
        expect(item.evaluate().reason, PmiNoVerdict.invalidInput);
        expect(PmiItem.fromJson(item.toJson()).$1!.evaluate().verdict,
            PmiVerdict.none);
        expect(
            item
                .copyWith(readings: valid.readings, uncertainty: {})
                .evaluate()
                .verdict,
            PmiVerdict.conformingNoCarbon);
      }
    }
    final (badMap, lost) = PmiItem.fromJson({
      ...valid.toJson(),
      'u': ['0.2']
    });
    expect(lost, 1);
    expect(badMap!.evaluate().verdict, PmiVerdict.none);
    expect(badMap.evaluate().reason, PmiNoVerdict.invalidInput);
    final (badSpec, specLost) =
        PmiItem.fromJson({...valid.toJson(), 'spec': 123});
    expect(specLost, 1);
    expect(badSpec!.evaluate().verdict, PmiVerdict.none,
        reason:
            'An unreadable specification must not select the default standard');
  });

  test('JSON w obie strony: odczyty jako tekst, bez zmian', () {
    final p = _protocol();
    final back = FerritePmiProtocol.fromJson(p.toJson())!;
    expect(back.toJson(), p.toJson());
    expect(back.sites.first.readings, ['28', '31,0', '45.50']);
    expect(back.pmi.single.readings[PmiElement.mo], '1,9');
    expect(back.droppedOnLoad, 0);
  });

  test('puste miejsce pominięte w ocenie; jedno poza → protokół poza', () {
    final p = _protocol();
    expect(p.filledSites.length, 1);
    expect(p.ferriteVerdict, FerriteVerdict.fail);
  });

  test('pusty zakres ze specyfikacji → brak werdyktu, nieczytelny → też', () {
    expect(_protocol().copyWith(customMin: '', customMax: '').ferriteVerdict,
        FerriteVerdict.none);
    final bad = _protocol().copyWith(customMin: '3,0,1');
    expect(bad.requirement!.isValid, isFalse);
    expect(bad.ferriteVerdict, FerriteVerdict.none);
  });

  test('nieznany preset (zapis z innej wersji) → brak werdyktu', () {
    final p = _protocol().copyWith(presetId: 'nie-ma-takiego');
    expect(p.requirement, isNull);
    final r = p.evaluateFerrite().first;
    expect(r.reason, FerriteNoVerdict.unknownPreset);
    expect(p.ferriteVerdict, FerriteVerdict.none);
  });

  test('nieznany gatunek albo wariant normy → brak werdyktu PMI', () {
    const unknownGrade = PmiItem(id: 'x', gradeId: 'X99', readings: {
      PmiElement.cr: '17',
    });
    expect(unknownGrade.evaluate().reason, PmiNoVerdict.noGrade);
    final unknownSpec = _protocol().pmi.single.copyWith(specKey: 'astm-1999');
    expect(unknownSpec.spec, isNull);
    expect(unknownSpec.evaluate().verdict, PmiVerdict.none);
  });

  test('nowy protokół jest pusty; wpisany tytuł — już nie', () {
    final b = FerritePmiProtocol.blank(id: 'b', now: _now);
    expect(b.isBlank, isTrue);
    expect(b.date, '2026-10-18');
    expect(b.copyWith(title: 'x').isBlank, isFalse);
    expect(
        b.copyWith(sites: [
          b.sites.first.copyWith(readings: ['45'])
        ]).isBlank,
        isFalse);
  });

  test('wymaganie z presetu ma pierwszeństwo przed polami własnymi', () {
    final preset = kFerritePresets.first;
    final p = _protocol().copyWith(presetId: preset.id);
    expect(p.requirement, same(preset.requirement));
  });

  group('tekst protokołu', () {
    test('PL: nagłówek, wymaganie, odczyty tak jak wpisano, werdykty', () {
      final t = ferritePmiProtocolText(_protocol(), en: false, now: _now);
      expect(t, startsWith('FERRYT I PMI — PROTOKÓŁ'));
      expect(t, contains('Wykonał: J. Kowalski'));
      expect(t, contains('FN 30–70'));
      expect(t, contains('1. Spoina — lico: 28; 31,0; 45,50 FN'));
      expect(t, contains('POZA ZAKRESEM'));
      expect(t, contains('Wynik ferrytu: POZA ZAKRESEM'));
      expect(t, contains('Mo* 1,9 ± 0,1'));
      expect(t, contains('Werdykt: DO WERYFIKACJI'));
      expect(t, contains('XRF nie mierzy węgla'));
      expect(t, contains('2026-10-18 09:30'));
      // Puste miejsce (SWC A bez odczytów) nie trafia do protokołu.
      expect(t, isNot(contains('SWC strona A')));
    });

    test('EN: angielskie etykiety, kropka dziesiętna', () {
      final t = ferritePmiProtocolText(_protocol(), en: true, now: _now);
      expect(t, startsWith('FERRITE AND PMI — RECORD'));
      expect(t, contains('1. Weld metal — lico: 28; 31.0; 45.50 FN'));
      expect(t, contains('Verdict: TO BE VERIFIED'));
    });

    test('preset: TYPOWE i źródło w protokole', () {
      final preset = kFerritePresets.first;
      final t = ferritePmiProtocolText(
          _protocol().copyWith(presetId: preset.id),
          en: false,
          now: _now);
      expect(t, contains('TYPOWE — decyduje specyfikacja projektu'));
      expect(t, contains(preset.sourcePl));
    });

    test(
        'preset IOGP S-705 przy 1 odczycie: „specyfikacja wymaga ≥ 3 '
        'odczytów”', () {
      final p = FerritePmiProtocol(
        id: 'i',
        date: '2026-10-18',
        presetId: 'iogp_s705_fn3_10',
        sites: const [
          FerriteSite(id: 's', location: FerriteLocation.weld, readings: ['6']),
        ],
      );
      expect(p.ferriteVerdict, FerriteVerdict.none);
      final t = ferritePmiProtocolText(p, en: false, now: _now);
      expect(
          t,
          contains('za mało odczytów: 1 — specyfikacja wymaga ≥ 3 '
              'odczytów'));
      expect(t, contains('min. odczytów na miejsce: 3'));
    });

    test('jednostki różne: w protokole „brak werdyktu” z powodem', () {
      final t = ferritePmiProtocolText(
          _protocol().copyWith(customUnit: FerriteUnit.percent),
          en: false,
          now: _now);
      expect(t, contains('BRAK WERDYKTU · odczyty w FN, wymaganie w %'));
    });
  });
}
