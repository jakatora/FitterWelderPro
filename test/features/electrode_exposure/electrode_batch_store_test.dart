// Magazyn partii elektrod (A4): uszkodzony zapis nie znika po cichu —
// surowy tekst trafia raz pod klucz kopii, zanim nadpisze go następny
// zapis; inny typ wartości w SharedPreferences nie wywala odczytu.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:cut_list_app/domain/welding/electrode_exposure.dart';
import 'package:cut_list_app/features/electrode_exposure/electrode_batch_store.dart';

ElectrodeBatch _batch(String id) => ElectrodeBatch.takenOut(
    id: id, electrode: ElectrodeClass.e7018, at: DateTime(2026, 10, 17, 7));

void main() {
  const store = ElectrodeBatchStore();

  test('uszkodzony JSON: pusta lista i kopia surowego zapisu', () async {
    SharedPreferences.setMockInitialValues(
        {kElectrodeBatchesPrefsKey: '{"v":1,"batches":[{"id":'});
    expect(await store.load(), isEmpty);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(kElectrodeBatchesCorruptPrefsKey),
        '{"v":1,"batches":[{"id":');
  });

  test('kopia tylko raz — kolejne uszkodzenie jej nie nadpisuje', () async {
    SharedPreferences.setMockInitialValues({
      kElectrodeBatchesPrefsKey: 'drugie uszkodzenie',
      kElectrodeBatchesCorruptPrefsKey: 'pierwsze uszkodzenie',
    });
    expect(await store.load(), isEmpty);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(kElectrodeBatchesCorruptPrefsKey),
        'pierwsze uszkodzenie');
  });

  test('inny typ wartości w prefs (liczba, lista) nie wywala odczytu',
      () async {
    for (final value in <Object>[
      5,
      true,
      <String>['a', 'b']
    ]) {
      SharedPreferences.setMockInitialValues(
          {kElectrodeBatchesPrefsKey: value});
      expect(await store.load(), isEmpty, reason: '$value');
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(kElectrodeBatchesCorruptPrefsKey), isNotNull,
          reason: '$value');
    }
  });

  test(
      'nieznane zdarzenie: partia zostaje, kopia zapisana, zapis jej nie '
      'kasuje', () async {
    final json = _batch('b1').returnToOven(DateTime(2026, 10, 17, 9)).toJson();
    final raw = jsonEncode({
      'v': 1,
      'batches': [
        {
          ...json,
          'ev': [
            ...(json['ev']! as List),
            {'k': 'zdarzenieZNowszejWersji', 'at': 0},
          ],
        },
      ],
    });
    SharedPreferences.setMockInitialValues({kElectrodeBatchesPrefsKey: raw});
    final loaded = await store.load();
    expect(loaded.single.id, 'b1');
    expect(loaded.single.events, hasLength(2));
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(kElectrodeBatchesCorruptPrefsKey), raw);

    await store.save(loaded);
    expect(prefs.getString(kElectrodeBatchesCorruptPrefsKey), raw,
        reason: 'kopia przeżywa nadpisanie głównego klucza');
    expect(decodeBatches(prefs.getString(kElectrodeBatchesPrefsKey)).single.id,
        'b1');
  });

  test('poprawny zapis — bez kopii', () async {
    SharedPreferences.setMockInitialValues({
      kElectrodeBatchesPrefsKey: encodeBatches([_batch('b1')])
    });
    expect((await store.load()).single.id, 'b1');
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.containsKey(kElectrodeBatchesCorruptPrefsKey), isFalse);
  });
}
