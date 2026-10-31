// Magazyn historii „Tolerancji spoola”: zapis, sortowanie, pusty protokół,
// limit 200 bez cichego przycinania, przywracanie (także ponad limit),
// kopia surowego zapisu przy uszkodzeniu.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';
import 'package:cut_list_app/domain/spool_check/spool_check.dart';
import 'package:cut_list_app/features/spool_check/spool_check_store.dart';

class _UnpersistedDisk extends InMemorySharedPreferencesStore {
  _UnpersistedDisk() : super.empty();
  String? pretendKey;
  String? refusedKey;
  @override
  Future<bool> setValue(String type, String key, Object value) async {
    if (key == refusedKey) return false;
    if (pretendKey == null || pretendKey == key) return true;
    return super.setValue(type, key, value);
  }
}

SpoolCheck _c(String id, {String date = '2026-10-18', int updated = 1}) =>
    SpoolCheck(
      id: id,
      spoolNo: 'S-$id',
      date: date,
      dn: 150,
      items: [
        SpoolItem(
            id: '$id-a',
            kind: SpoolItemKind.faceToFace,
            drawingMm: 1250,
            measuredMm: 1251),
      ],
      updatedAt: updated,
    );

/// Pamięć, która odmawia zapisu kopii uszkodzonej historii (setString →
/// false albo wyjątek) — reszta jak prawdziwa.
class _NoBackupPrefs implements SharedPreferences {
  _NoBackupPrefs(this._real, {this.throwOnBackup = false});
  final SharedPreferences _real;
  final bool throwOnBackup;
  final List<String> refused = [];

  @override
  Future<void> reload() => _real.reload();

  static bool _isBackup(String key) =>
      key == SpoolCheckStore.corruptBackupKey ||
      key == SpoolCheckStore.corruptLastBackupKey;

  @override
  Object? get(String key) => _real.get(key);

  @override
  String? getString(String key) => _real.getString(key);

  @override
  Future<bool> setString(String key, String value) async {
    if (_isBackup(key)) {
      refused.add(key);
      if (throwOnBackup) throw StateError('disk full');
      return false;
    }
    return _real.setString(key, value);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

String _many(int n) => jsonEncode(spoolChecksToJson([
      for (var i = 0; i < n; i++) _c('p$i', date: '2020-01-01'),
    ]));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('odmowa zapisu nie dodaje protokołu do odczytanej historii', () async {
    SharedPreferences.setMockInitialValues({});
    final disk = _UnpersistedDisk()..pretendKey = 'unused';
    SharedPreferencesStorePlatform.instance = disk;
    const store = SpoolCheckStore();
    await store.upsert(_c('old'));
    disk.refusedKey = 'flutter.${SpoolCheckStore.key}';
    await expectLater(store.upsert(_c('new')), throwsStateError);
    expect((await store.load()).map((c) => c.id), ['old']);
  });

  test('pozorny sukces zapisu protokołu jest wykrywany', () async {
    SharedPreferences.setMockInitialValues({});
    SharedPreferencesStorePlatform.instance = _UnpersistedDisk();
    await expectLater(
        const SpoolCheckStore().upsert(_c('new')), throwsStateError);
  });

  test('pozorna kopia nie pozwala nadpisać uszkodzonej historii', () async {
    SharedPreferences.setMockInitialValues({});
    final disk = _UnpersistedDisk()
      ..pretendKey = 'flutter.${SpoolCheckStore.corruptBackupKey}';
    SharedPreferencesStorePlatform.instance = disk;
    const damaged = '{broken spool';
    await disk.setValue('String', 'flutter.${SpoolCheckStore.key}', damaged);
    await expectLater(const SpoolCheckStore().upsert(_c('new')),
        throwsA(isA<SpoolCheckStoreUnavailable>()));
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    expect(prefs.get(SpoolCheckStore.key), damaged);
  });
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test(
      'zapis i odczyt: najnowszy na górze; pusty protokół nie trafia do '
      'historii, a zapisany i wyczyszczony znika', () async {
    const store = SpoolCheckStore();
    await store.upsert(_c('old', date: '2026-10-01'));
    await store.upsert(_c('new', date: '2026-10-18'));
    await store.upsert(SpoolCheck.blank(id: 'blank', now: DateTime(2026)));
    expect((await store.load()).map((c) => c.id), ['new', 'old']);

    await store.upsert(SpoolCheck(id: 'old', date: '2026-10-01'));
    expect((await store.load()).map((c) => c.id), ['new']);
  });

  test('uszkodzony JSON: kopia surowego zapisu raz, przed nadpisaniem',
      () async {
    SharedPreferences.setMockInitialValues(
        {SpoolCheckStore.key: '[{"id": "x"'});
    const store = SpoolCheckStore();
    final load = await store.loadReport();
    expect(load.unreadable, isTrue);
    expect(load.checks, isEmpty);
    await store.upsert(_c('a'));
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(SpoolCheckStore.corruptBackupKey), '[{"id": "x"');
    expect((await store.load()).single.id, 'a');

    // Kolejny, inny uszkodzony zapis nie nadpisuje pierwszej kopii.
    await prefs.setString(SpoolCheckStore.key, '{zepsute');
    await store.load();
    expect(prefs.getString(SpoolCheckStore.corruptBackupKey), '[{"id": "x"');
    expect(prefs.getString(SpoolCheckStore.corruptLastBackupKey), '{zepsute');
  });

  test('dwie zajęte kopie blokują nadpisanie trzeciego uszkodzenia', () async {
    SharedPreferences.setMockInitialValues({
      SpoolCheckStore.key: 'trzecie uszkodzenie',
      SpoolCheckStore.corruptBackupKey: 'pierwsze uszkodzenie',
      SpoolCheckStore.corruptLastBackupKey: 'drugie uszkodzenie',
    });
    const store = SpoolCheckStore();
    final load = await store.loadReport();
    expect(load.backupFailed, isTrue);
    await expectLater(
        store.upsert(_c('nowy')), throwsA(isA<SpoolCheckStoreUnavailable>()));
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(SpoolCheckStore.key), 'trzecie uszkodzenie');
    expect(prefs.getString(SpoolCheckStore.corruptBackupKey),
        'pierwsze uszkodzenie');
    expect(prefs.getString(SpoolCheckStore.corruptLastBackupKey),
        'drugie uszkodzenie');
  });

  test(
      'uszkodzone pozycje w zapisie: raport uszkodzeń i kopia surowego '
      'zapisu', () async {
    final json = _c('a').toJson();
    json['items'] = [
      ...(json['items'] as List),
      {'id': 'zz', 'kind': 'nieznany'},
    ];
    final raw = jsonEncode([
      json,
      {'id': ''}
    ]);
    SharedPreferences.setMockInitialValues({SpoolCheckStore.key: raw});
    final load = await const SpoolCheckStore().loadReport();
    expect(load.damaged, isTrue);
    expect(load.droppedChecks, 1);
    expect(load.damagedEntries, 1);
    expect(load.checks.single.items, hasLength(1));
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(SpoolCheckStore.corruptBackupKey), raw);
  });

  test(
      'pełna historia: zmiana zapisanego działa, nowy odrzucony, nic nie '
      'wypada', () async {
    SharedPreferences.setMockInitialValues(
        {SpoolCheckStore.key: _many(SpoolCheckStore.maxEntries)});
    const store = SpoolCheckStore();
    final first = (await store.load()).first;
    await store.upsert(first.copyWith(notes: 'zmiana'));
    expect((await store.load()).firstWhere((c) => c.id == first.id).notes,
        'zmiana');
    await expectLater(
        store.upsert(_c('nowy')), throwsA(isA<SpoolCheckStoreFull>()));
    final ids = (await store.load()).map((c) => c.id).toSet();
    expect(ids, hasLength(SpoolCheckStore.maxEntries));
    expect(ids, isNot(contains('nowy')));
  });

  test('przywrócenie usuniętego działa zawsze — także przy pełnej historii',
      () async {
    SharedPreferences.setMockInitialValues(
        {SpoolCheckStore.key: _many(SpoolCheckStore.maxEntries)});
    const store = SpoolCheckStore();
    final victim = (await store.load()).first;
    await store.delete(victim.id);
    // W międzyczasie ktoś dopisał nowy protokół — historia znów pełna.
    await store.upsert(_c('wstawiony'));
    expect(await store.load(), hasLength(SpoolCheckStore.maxEntries));
    await store.restore(victim);
    final ids = (await store.load()).map((c) => c.id).toSet();
    expect(ids, contains(victim.id));
    expect(ids, contains('wstawiony'));
    expect(ids, hasLength(SpoolCheckStore.maxEntries + 1));
  });

  test(
      'nieudana kopia uszkodzonego zapisu (setString = false albo wyjątek) — '
      'zapis, usunięcie i przywrócenie rzucają, historia nietknięta', () async {
    final json = _c('a').toJson();
    json['items'] = [
      ...(json['items'] as List),
      {'id': 'zz', 'kind': 'nieznany'},
    ];
    for (final raw in [
      jsonEncode([json]),
      '[{"id": "x"'
    ]) {
      for (final throwing in [false, true]) {
        SharedPreferences.setMockInitialValues({SpoolCheckStore.key: raw});
        final real = await SharedPreferences.getInstance();
        final fake = _NoBackupPrefs(real, throwOnBackup: throwing);
        final store = SpoolCheckStore(prefs: () async => fake);
        final load = await store.loadReport();
        expect(load.damaged, isTrue);
        expect(load.backupFailed, isTrue);
        await expectLater(store.upsert(_c('nowy')),
            throwsA(isA<SpoolCheckStoreUnavailable>()));
        await expectLater(
            store.delete('a'), throwsA(isA<SpoolCheckStoreUnavailable>()));
        await expectLater(
            store.restore(_c('b')), throwsA(isA<SpoolCheckStoreUnavailable>()));
        await expectLater(store.restoreItem('a', _c('a').items.single, 0),
            throwsA(isA<SpoolCheckStoreUnavailable>()));
        expect(real.getString(SpoolCheckStore.key), raw,
            reason: 'historia nie może być nadpisana bez kopii');
        expect(real.getString(SpoolCheckStore.corruptBackupKey), isNull);
        expect(fake.refused, isNotEmpty);
      }
    }
    // Gdy pamięć znów przyjmuje kopię — zapis działa, kopia jest.
    final real = await SharedPreferences.getInstance();
    await const SpoolCheckStore().upsert(_c('nowy'));
    expect(real.getString(SpoolCheckStore.corruptBackupKey), '[{"id": "x"');
    expect((await const SpoolCheckStore().load()).single.id, 'nowy');
  });

  test('przywrócenie pozycji w zapisie (ekran edycji zamknięty)', () async {
    const store = SpoolCheckStore();
    final c = _c('a');
    final item = c.items.single;
    await store.upsert(c.copyWith(items: []).copyWith(spoolNo: 'S-a'));
    await store.restoreItem('a', item, 0);
    expect((await store.load()).single.items.single.id, item.id);
    // Drugi raz — bez dubla; brak protokołu — nic.
    await store.restoreItem('a', item, 0);
    await store.restoreItem('brak', item, 0);
    expect((await store.load()).single.items, hasLength(1));
  });
}
