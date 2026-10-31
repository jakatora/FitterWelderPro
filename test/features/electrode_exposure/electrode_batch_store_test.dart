// Magazyn partii elektrod (A4): uszkodzony zapis nie znika po cichu —
// surowy tekst trafia raz pod klucz kopii, zanim nadpisze go następny
// zapis; inny typ wartości w SharedPreferences nie wywala odczytu.

import 'dart:convert';
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

import 'package:cut_list_app/domain/welding/electrode_exposure.dart';
import 'package:cut_list_app/features/electrode_exposure/electrode_batch_store.dart';

ElectrodeBatch _batch(String id) => ElectrodeBatch.takenOut(
    id: id, electrode: ElectrodeClass.e7018, at: DateTime(2026, 10, 17, 7));

class _RefuseWritePreferences extends InMemorySharedPreferencesStore {
  _RefuseWritePreferences() : super.empty();

  String? refusedKey;

  @override
  Future<bool> setValue(String valueType, String key, Object value) async {
    if (key == refusedKey) return false;
    return super.setValue(valueType, key, value);
  }
}

class _DelayFirstWritePreferences extends InMemorySharedPreferencesStore {
  _DelayFirstWritePreferences() : super.empty();

  final firstStarted = Completer<void>();
  final releaseFirst = Completer<void>();
  var writes = 0;

  @override
  Future<bool> setValue(String valueType, String key, Object value) async {
    if (key == 'flutter.$kElectrodeBatchesPrefsKey' && writes++ == 0) {
      firstStarted.complete();
      await releaseFirst.future;
    }
    return super.setValue(valueType, key, value);
  }
}

void main() {
  const store = ElectrodeBatchStore();

  test('odczyt podczas zapisu czeka na nową partię', () async {
    SharedPreferences.setMockInitialValues({});
    final disk = _DelayFirstWritePreferences();
    SharedPreferencesStorePlatform.instance = disk;
    final writing = store.save([_batch('nowa')]);
    await disk.firstStarted.future;
    final reading = store.load();
    await Future<void>.delayed(Duration.zero);
    disk.releaseFirst.complete();
    await writing;
    expect((await reading).map((batch) => batch.id), ['nowa']);
  });

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

  test('drugi uszkodzony zapis dostaje osobną kopię przed nadpisaniem',
      () async {
    SharedPreferences.setMockInitialValues({
      kElectrodeBatchesPrefsKey: 'drugie uszkodzenie',
      kElectrodeBatchesCorruptPrefsKey: 'pierwsze uszkodzenie',
    });
    await store.save([_batch('nowa')]);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(kElectrodeBatchesCorruptPrefsKey),
        'pierwsze uszkodzenie');
    expect(prefs.getString('${kElectrodeBatchesCorruptPrefsKey}_2'),
        'drugie uszkodzenie');
    expect(decodeBatches(prefs.getString(kElectrodeBatchesPrefsKey)).single.id,
        'nowa');
  });

  test('brak trwałej kopii blokuje nadpisanie uszkodzonego zapisu', () async {
    SharedPreferences.setMockInitialValues({});
    final disk = _RefuseWritePreferences();
    SharedPreferencesStorePlatform.instance = disk;
    await disk.setValue(
        'String', 'flutter.$kElectrodeBatchesPrefsKey', 'uszkodzony dziennik');
    disk.refusedKey = 'flutter.$kElectrodeBatchesCorruptPrefsKey';

    await expectLater(store.save([_batch('nowa')]), throwsA(isA<StateError>()));
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    expect(prefs.getString(kElectrodeBatchesPrefsKey), 'uszkodzony dziennik');
    expect(prefs.containsKey(kElectrodeBatchesCorruptPrefsKey), isFalse);
  });

  test('pełne trzy kopie blokują nadpisanie czwartego uszkodzenia', () async {
    SharedPreferences.setMockInitialValues({
      kElectrodeBatchesPrefsKey: 'czwarte uszkodzenie',
      kElectrodeBatchesCorruptPrefsKey: 'pierwsze',
      '${kElectrodeBatchesCorruptPrefsKey}_2': 'drugie',
      '${kElectrodeBatchesCorruptPrefsKey}_3': 'trzecie',
    });

    await expectLater(store.save([_batch('nowa')]), throwsA(isA<StateError>()));
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(kElectrodeBatchesPrefsKey), 'czwarte uszkodzenie');
    expect(prefs.getString(kElectrodeBatchesCorruptPrefsKey), 'pierwsze');
    expect(prefs.getString('${kElectrodeBatchesCorruptPrefsKey}_2'), 'drugie');
    expect(prefs.getString('${kElectrodeBatchesCorruptPrefsKey}_3'), 'trzecie');
  });

  test('odmowa zapisu głównego klucza jest błędem', () async {
    SharedPreferences.setMockInitialValues({});
    final disk = _RefuseWritePreferences();
    SharedPreferencesStorePlatform.instance = disk;
    disk.refusedKey = 'flutter.$kElectrodeBatchesPrefsKey';

    await expectLater(store.save([_batch('nowa')]), throwsA(isA<StateError>()));
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    expect(prefs.containsKey(kElectrodeBatchesPrefsKey), isFalse);
  });

  test('odczyt po odmowie zapisu pokazuje trwałą, starszą listę', () async {
    SharedPreferences.setMockInitialValues({});
    final disk = _RefuseWritePreferences();
    SharedPreferencesStorePlatform.instance = disk;
    await disk.setValue('String', 'flutter.$kElectrodeBatchesPrefsKey',
        encodeBatches([_batch('stara')]));
    disk.refusedKey = 'flutter.$kElectrodeBatchesPrefsKey';

    await expectLater(store.save([_batch('nowa')]), throwsA(isA<StateError>()));
    expect((await store.load()).single.id, 'stara');
  });

  test('późny pierwszy zapis nie zastępuje nowszej listy partii', () async {
    SharedPreferences.setMockInitialValues({});
    final disk = _DelayFirstWritePreferences();
    SharedPreferencesStorePlatform.instance = disk;
    addTearDown(() {
      if (!disk.releaseFirst.isCompleted) {
        disk.releaseFirst.complete();
      }
    });

    final first = store.save([_batch('a')]);
    await disk.firstStarted.future;
    final second = store.save([_batch('a'), _batch('b')]);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    disk.releaseFirst.complete();
    await Future.wait([first, second]);

    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    expect(
        decodeBatches(prefs.getString(kElectrodeBatchesPrefsKey))
            .map((batch) => batch.id),
        ['a', 'b']);
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
