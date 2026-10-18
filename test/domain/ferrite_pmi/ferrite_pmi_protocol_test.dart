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
    final unknownSpec =
        _protocol().pmi.single.copyWith(specKey: 'astm-1999');
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

    test('jednostki różne: w protokole „brak werdyktu” z powodem', () {
      final t = ferritePmiProtocolText(
          _protocol().copyWith(customUnit: FerriteUnit.percent),
          en: false,
          now: _now);
      expect(t, contains('BRAK WERDYKTU · odczyty w FN, wymaganie w %'));
    });
  });
}
