// Źródła: każdy preset ferrytu ze źródłem i wydaniem, „typowe — decyduje
// specyfikacja”, zakresy prawidłowe, dotyczą jawnie podanych miejsc;
// lista źródeł na ekranie obejmuje wszystkie normy użyte w module.

import 'package:flutter_test/flutter_test.dart';

import 'package:cut_list_app/domain/ferrite_pmi/ferrite.dart';
import 'package:cut_list_app/domain/ferrite_pmi/ferrite_pmi_sources.dart';

void main() {
  final year = RegExp(r'(19|20)\d\d');

  test('presety ferrytu: źródło z wydaniem, zakres prawidłowy, miejsca', () {
    expect(kFerritePresets, isNotEmpty);
    final ids = kFerritePresets.map((p) => p.id).toList();
    expect(ids.toSet().length, ids.length);
    for (final p in kFerritePresets) {
      expect(p.requirement.isValid, isTrue, reason: p.id);
      expect(p.appliesTo, isNotEmpty, reason: p.id);
      expect(year.hasMatch(p.sourcePl), isTrue, reason: '${p.id}: ${p.sourcePl}');
      expect(year.hasMatch(p.sourceEn), isTrue, reason: '${p.id}: ${p.sourceEn}');
      expect(p.titlePl.trim(), isNotEmpty, reason: p.id);
      expect(p.titleEn.trim(), isNotEmpty, reason: p.id);
      expect(ferritePresetById(p.id), same(p));
    }
    expect(ferritePresetById('nie-ma'), isNull);
  });

  test('presety: wartości zweryfikowane, jednostka i miejsca jak w źródle', () {
    void check(String id, double? min, double? max, FerriteUnit unit,
        Set<FerriteLocation> where) {
      final p = ferritePresetById(id)!;
      expect(p.requirement.min, min, reason: id);
      expect(p.requirement.max, max, reason: id);
      expect(p.requirement.unit, unit, reason: id);
      expect(p.appliesTo, where, reason: id);
    }

    const weld = {FerriteLocation.weld};
    const haz = {FerriteLocation.hazA, FerriteLocation.hazB};
    const base = {FerriteLocation.base};
    check('iso17781_weld', 30, 70, FerriteUnit.percent, weld);
    check('iso17781_base', 35, 60, FerriteUnit.percent, base);
    check('api938c_2011_weld', 25, 60, FerriteUnit.percent, weld);
    check('api938c_2011_haz', 40, 65, FerriteUnit.percent, haz);
    check('api938c_2011_base', 30, 65, FerriteUnit.percent, base);
    check('iogp_s705_fn3_10', 3, 10, FerriteUnit.fn, weld);
    check('asme_uha51_308l', 4, 14, FerriteUnit.fn, weld);
    check('urea_316lug_base', null, 0.6, FerriteUnit.percent, base);
    expect(kFerritePresets, hasLength(8));
    // Minimalna liczba odczytów tylko tam, gdzie źródło ją podaje.
    for (final p in kFerritePresets) {
      expect(p.minReadings, p.id == 'iogp_s705_fn3_10' ? 3 : 1, reason: p.id);
    }
    expect(ferritePresetById('iogp_s705_fn3_10')!.sourcePl, contains('12.13.3'));
    // Wydanie w tytule — 938-C wyd. 2011 nie udaje aktualnego.
    expect(ferritePresetById('api938c_2011_weld')!.titlePl, contains('2011'));
    // Brak niepotwierdzonych presetów NORSOK M-601.
    expect(kFerritePresets.any((p) => p.sourcePl.contains('NORSOK')), isFalse);
  });

  test('lista źródeł: każda norma z presetów i tabeli PMI jest opisana', () {
    final all = kFerritePmiSources.map((s) => s.pl).join('\n');
    for (final name in [
      'EN ISO 8249',
      'AWS A4.2',
      'EN 10088-1',
      'ASTM A240',
      'ASTM A312',
      'ASTM A790',
      'ASTM A335',
      'EN 10216-2',
      'EN 10216-5',
      'EN 10028-2',
      'EN 10095',
      'ISO 17781',
      'API TR 938-C',
      'IOGP S-705',
      'UHA-51',
    ]) {
      expect(all, contains(name), reason: name);
    }
    for (final s in kFerritePmiSources) {
      expect(s.en.trim(), isNotEmpty);
    }
  });

  test('notatka FN / %: bez przeliczenia wpływającego na werdykt', () {
    expect(ferriteFnPercentNote(en: false), contains('nie przelicza'));
    expect(ferriteFnPercentNote(en: true), contains('does not convert'));
    expect(FerriteUnit.values, hasLength(2));
  });
}
