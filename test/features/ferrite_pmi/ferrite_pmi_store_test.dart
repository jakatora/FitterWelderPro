// Historia „Ferryt i PMI”: limit bez cichego przycinania, przywrócenie
// usuniętego zawsze dozwolone, pusty protokół nie trafia do historii,
// uszkodzony zapis → kopia surowego tekstu (raz, przed nadpisaniem).

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

import 'package:cut_list_app/domain/ferrite_pmi/ferrite.dart';
import 'package:cut_list_app/domain/ferrite_pmi/ferrite_pmi_protocol.dart';
import 'package:cut_list_app/features/ferrite_pmi/ferrite_pmi_store.dart';

class _Disk extends InMemorySharedPreferencesStore {
  _Disk() : super.empty();
  String? pretendKey;
  @override
  Future<bool> setValue(String type, String key, Object value) async {
    if (pretendKey == null || pretendKey == key) return true;
    return super.setValue(type, key, value);
  }
}

FerritePmiProtocol _p(int i, {String date = '2026-10-18'}) =>
    FerritePmiProtocol(
      id: 'p$i',
      date: date,
      title: 'Spoina $i',
      sites: [
        FerriteSite(
            id: 'p$i-s',
            location: FerriteLocation.weld,
            readings: const ['45']),
      ],
      updatedAt: i,
    );

String _encoded(int n) =>
    jsonEncode(ferritePmiToJson([for (var i = 0; i < n; i++) _p(i)]));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const store = FerritePmiStore();

  test(
      'an unsupported protocol version is protected before editing the remaining history',
      () async {
    final future = {..._p(1).toJson(), 'v': 2};
    final good = _p(2);
    final raw = jsonEncode([future, good.toJson()]);
    SharedPreferences.setMockInitialValues({FerritePmiStore.key: raw});
    final report = await store.loadReport();
    expect(report.droppedProtocols, 1);
    expect(report.protocols.map((p) => p.id), [good.id]);
    await store.upsert(good.copyWith(notes: 'edited'));
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(FerritePmiStore.corruptBackupKey), raw);
    expect((await store.load()).single.notes, 'edited');
  });

  test('duplicate identity recovery cannot overwrite data without a raw backup',
      () async {
    final raw =
        jsonEncode([_p(1).toJson(), _p(1).copyWith(title: 'Other').toJson()]);
    SharedPreferences.setMockInitialValues({
      FerritePmiStore.key: raw,
      FerritePmiStore.corruptBackupKey: 'previous damage',
      FerritePmiStore.corruptLastBackupKey: 'another previous damage',
    });
    final report = await store.loadReport();
    expect(report.recoveredProtocols, 1);
    expect(report.backupFailed, isTrue);
    expect(report.protocols, hasLength(2));
    await expectLater(
        store.upsert(report.protocols.first.copyWith(notes: 'edit')),
        throwsStateError);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(FerritePmiStore.key), raw);
  });

  test('editing or deleting a duplicate protocol cannot erase its sibling',
      () async {
    final first = _p(1).copyWith(title: 'First');
    final second = _p(1).copyWith(title: 'Second');
    final raw = jsonEncode([first.toJson(), second.toJson()]);
    SharedPreferences.setMockInitialValues({FerritePmiStore.key: raw});
    final loaded = await store.load();
    expect(loaded.map((p) => p.id).toSet(), hasLength(2));
    final a = loaded.singleWhere((p) => p.title == 'First');
    final b = loaded.singleWhere((p) => p.title == 'Second');
    await store.upsert(a.copyWith(title: 'Edited'));
    expect((await store.load()).map((p) => p.title),
        containsAll(['Edited', 'Second']));
    await store.delete(a.id);
    expect((await store.load()).single.toJson(), b.toJson());
    await store.restore(a);
    expect((await store.load()).map((p) => p.id).toSet(), hasLength(2));
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(FerritePmiStore.corruptBackupKey), raw);
  });

  test('opaque records survive repeated edits without filling backup slots',
      () async {
    final raw = jsonEncode([
      {
        ..._p(1).copyWith(customMin: '30', customMax: '70').toJson(),
        'sites': [
          {
            'id': 's',
            'loc': 'weld',
            'readings': ['45']
          },
          {
            'loc': 'unknown',
            'readings': ['12']
          },
        ],
        'pmi': false,
      }
    ]);
    SharedPreferences.setMockInitialValues({FerritePmiStore.key: raw});
    for (var i = 0; i < 4; i++) {
      final p = (await store.load()).single;
      expect(p.ferriteVerdict, FerriteVerdict.none);
      expect(p.unreadableSites, hasLength(1));
      expect(p.unreadablePmi, [false]);
      await store.upsert(p.copyWith(notes: 'Edit $i'));
    }
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(FerritePmiStore.corruptBackupKey), raw);
    expect(prefs.getString(FerritePmiStore.corruptLastBackupKey), isNull);
    expect((await store.loadReport()).damaged, isFalse);
    expect((await store.load()).single.incomplete, isTrue);
  });

  test('restored damage remains invalid after saving and reloading the history',
      () async {
    final raw = jsonEncode([
      {
        ..._p(1).copyWith(customMin: '30', customMax: '70').toJson(),
        'sites': [
          {
            'id': 's',
            'loc': 'weld',
            'readings': ['45', null]
          }
        ],
      }
    ]);
    SharedPreferences.setMockInitialValues({FerritePmiStore.key: raw});
    final report = await store.loadReport();
    expect(report.damaged, isTrue);
    expect(report.protocols.single.ferriteVerdict, FerriteVerdict.none);
    await store.upsert(report.protocols.single);
    expect((await store.load()).single.ferriteVerdict, FerriteVerdict.none);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(FerritePmiStore.corruptBackupKey), raw);
  });

  test('pozorny sukces zapisu protokołu jest wykrywany', () async {
    SharedPreferences.setMockInitialValues({});
    SharedPreferencesStorePlatform.instance = _Disk();
    await expectLater(store.upsert(_p(1)), throwsStateError);
  });

  test('pozorna kopia nie pozwala nadpisać uszkodzonej historii', () async {
    SharedPreferences.setMockInitialValues({});
    final disk = _Disk()
      ..pretendKey = 'flutter.${FerritePmiStore.corruptBackupKey}';
    SharedPreferencesStorePlatform.instance = disk;
    const damaged = '{broken ferrite';
    await disk.setValue('String', 'flutter.${FerritePmiStore.key}', damaged);
    await expectLater(store.upsert(_p(1)), throwsStateError);
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    expect(prefs.get(FerritePmiStore.key), damaged);
  });

  test('zapis i odczyt: najnowsze na górze, pusty protokół pominięty',
      () async {
    SharedPreferences.setMockInitialValues({});
    await store.upsert(_p(1, date: '2026-10-17'));
    await store.upsert(_p(2, date: '2026-10-18'));
    await store.upsert(
        FerritePmiProtocol.blank(id: 'blank', now: DateTime(2026, 10, 18, 9)));
    final list = await store.load();
    expect(list.map((e) => e.id), ['p2', 'p1']);
  });

  test('pusty po edycji znika z historii', () async {
    SharedPreferences.setMockInitialValues({});
    await store.upsert(_p(1));
    await store.upsert(_p(1).copyWith(title: '', sites: const []));
    expect(await store.load(), isEmpty);
  });

  test('przy 200 protokołach nowy odrzucony, stare zostają (bez przycinania)',
      () async {
    SharedPreferences.setMockInitialValues(
        {FerritePmiStore.key: _encoded(FerritePmiStore.maxEntries)});
    await expectLater(
        store.upsert(_p(999)), throwsA(isA<FerritePmiStoreFull>()));
    final list = await store.load();
    expect(list.length, FerritePmiStore.maxEntries);
    expect(list.any((e) => e.id == 'p999'), isFalse);
    // Edycja istniejącego przy pełnej historii — dozwolona.
    await store.upsert(_p(5).copyWith(title: 'Spoina 5 — poprawka'));
    expect((await store.load()).firstWhere((e) => e.id == 'p5').title,
        'Spoina 5 — poprawka');
  });

  test('Cofnij: przywrócenie usuniętego zawsze dozwolone, także przy pełnej',
      () async {
    SharedPreferences.setMockInitialValues(
        {FerritePmiStore.key: _encoded(FerritePmiStore.maxEntries)});
    final victim = (await store.load()).first;
    await store.delete(victim.id);
    // W międzyczasie historia znów się zapełniła.
    await store.upsert(_p(777));
    expect((await store.load()).length, FerritePmiStore.maxEntries);
    await store.restore(victim);
    final list = await store.load();
    expect(list.length, FerritePmiStore.maxEntries + 1);
    expect(list.any((e) => e.id == victim.id), isTrue);
  });

  test('nieczytelny zapis: kopia surowego tekstu raz, przed nadpisaniem',
      () async {
    SharedPreferences.setMockInitialValues({FerritePmiStore.key: '{zepsute'});
    final load = await store.loadReport();
    expect(load.unreadable, isTrue);
    expect(load.protocols, isEmpty);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(FerritePmiStore.corruptBackupKey), '{zepsute');
    await store.upsert(_p(1));
    expect(prefs.getString(FerritePmiStore.corruptBackupKey), '{zepsute');
    expect((await store.load()).single.id, 'p1');
    // Drugi, inny uszkodzony zapis nie nadpisuje pierwszej kopii.
    await prefs.setString(FerritePmiStore.key, '[[[');
    await store.loadReport();
    expect(prefs.getString(FerritePmiStore.corruptBackupKey), '{zepsute');
    expect(prefs.getString(FerritePmiStore.corruptLastBackupKey), '[[[');
  });

  test('częściowo uszkodzony zapis: pominięte liczone, kopia i reszta wczytana',
      () async {
    final good = _p(1).toJson();
    final raw = jsonEncode([
      good,
      {'id': '', 'date': ''},
      {
        ...good,
        'id': 'p2',
        'readUnit': 'mm', // nieznana jednostka — nie zgadujemy
      },
      {
        ...good,
        'id': 'p3',
        'sites': [
          {
            'id': 'x',
            'loc': 'weld',
            'readings': ['31', 45, '50']
          },
          {'id': 'y', 'loc': 'nowhere'},
        ],
      },
    ]);
    SharedPreferences.setMockInitialValues({FerritePmiStore.key: raw});
    final load = await store.loadReport();
    expect(load.damaged, isTrue);
    expect(load.droppedProtocols, 2);
    // Odczyt 45 (liczba, nie tekst) i miejsce o nieznanym typie.
    expect(load.droppedItems, 2);
    expect(load.protocols.map((e) => e.id), containsAll(['p1', 'p3']));
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(FerritePmiStore.corruptBackupKey), raw);
  });

  test('dwie zajęte kopie nie pozwalają utracić trzeciego uszkodzenia',
      () async {
    const third = 'trzecie uszkodzenie';
    SharedPreferences.setMockInitialValues({
      FerritePmiStore.key: third,
      FerritePmiStore.corruptBackupKey: 'pierwsze uszkodzenie',
      FerritePmiStore.corruptLastBackupKey: 'drugie uszkodzenie',
    });

    await expectLater(store.upsert(_p(1)), throwsA(isA<StateError>()));
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(FerritePmiStore.key), third);
    expect(prefs.getString(FerritePmiStore.corruptBackupKey),
        'pierwsze uszkodzenie');
    expect(prefs.getString(FerritePmiStore.corruptLastBackupKey),
        'drugie uszkodzenie');
  });
}
