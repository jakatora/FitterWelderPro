// Zapis ostatniej rurki: klucz z wersją, kopia uszkodzonego zapisu przed
// nadpisaniem (tylko raz), odporność na błąd odczytu.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

import 'package:cut_list_app/domain/fitter/tube_bending.dart';
import 'package:cut_list_app/features/tube_bending/tube_bending_store.dart';

class _UnpersistedDisk extends InMemorySharedPreferencesStore {
  _UnpersistedDisk() : super.empty();
  String? pretendKey;
  @override
  Future<bool> setValue(String valueType, String key, Object value) async {
    if (pretendKey == null || pretendKey == key) return true;
    return super.setValue(valueType, key, value);
  }
}

class _FlakyStore extends TubeBendingStore {
  _FlakyStore();

  var reads = 0;

  @override
  Future<Object?> readRaw() async {
    if (reads++ == 0) throw StateError('kanał platformy niedostępny');
    return super.readRaw();
  }
}

const _tube = TubeBendingSaved(
  mode: TubeBendingMode.multi,
  unit: TubeUnit.inch,
  clrMm: 38.1,
  minStraightMm: 20,
  springbackDeg: 2,
  singleAngleDeg: 90,
  singleLegAMm: 200,
  offsetHeightMm: 100,
  offsetAngleDeg: 45,
  segmentsMm: [150, null, 120],
  anglesDeg: [90, 45],
  rotationsDeg: [null, 180],
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('pozorny sukces zapisu rurki jest zgłaszany jako błąd', () async {
    SharedPreferences.setMockInitialValues({});
    SharedPreferencesStorePlatform.instance = _UnpersistedDisk();
    await expectLater(const TubeBendingStore().save(_tube), throwsStateError);
  });

  test('nieutrwalona kopia nie pozwala nadpisać uszkodzonego oryginału',
      () async {
    SharedPreferences.setMockInitialValues({});
    final disk = _UnpersistedDisk()
      ..pretendKey = 'flutter.${TubeBendingStore.corruptKey}';
    SharedPreferencesStorePlatform.instance = disk;
    const damaged = '{broken tube';
    await disk.setValue('String', 'flutter.${TubeBendingStore.key}', damaged);
    await expectLater(const TubeBendingStore().save(_tube), throwsStateError);
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    expect(prefs.get(TubeBendingStore.key), damaged);
    expect(prefs.get(TubeBendingStore.corruptKey), isNull);
  });
  test('zapis i odczyt (puste pola zostają puste)', () async {
    SharedPreferences.setMockInitialValues({});
    const store = TubeBendingStore();
    await store.save(_tube);
    final l = await store.load();
    expect(l.damaged, isFalse);
    final s = l.state!;
    expect(s.mode, TubeBendingMode.multi);
    expect(s.unit, TubeUnit.inch);
    expect(s.clrMm, 38.1);
    expect(s.markerOffsetMm, isNull);
    expect(s.segmentsMm, [150, null, 120]);
    expect(s.anglesDeg, [90, 45]);
    expect(s.rotationsDeg, [null, 180]);
    expect(s.singleLegBMm, isNull);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.containsKey(TubeBendingStore.corruptKey), isFalse);
  });

  test('nic nie zapisano → brak stanu, nieuszkodzony', () async {
    SharedPreferences.setMockInitialValues({});
    final l = await const TubeBendingStore().load();
    expect(l.state, isNull);
    expect(l.damaged, isFalse);
  });

  test('uszkodzony JSON: kopia przed nadpisaniem; zajęta kopia blokuje zapis',
      () async {
    SharedPreferences.setMockInitialValues(
        {TubeBendingStore.key: '{"v":1,"angles":[90'});
    const store = TubeBendingStore();
    final l = await store.load();
    expect(l.damaged, isTrue);
    expect(l.state, isNull);

    await store.save(_tube);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(TubeBendingStore.corruptKey), '{"v":1,"angles":[90');
    expect((await store.load()).damaged, isFalse);

    // Inne uszkodzenie nie może zniknąć, gdy miejsce na kopię jest zajęte.
    await prefs.setString(TubeBendingStore.key, 'zepsute');
    await expectLater(store.save(_tube), throwsA(isA<StateError>()));
    expect(prefs.getString(TubeBendingStore.corruptKey), '{"v":1,"angles":[90');
    expect(prefs.getString(TubeBendingStore.key), 'zepsute');
  });

  test('niespójne listy, zła wersja, wartość innego typu → uszkodzony', () {
    final good = encodeTubeBending(_tube);
    expect(decodeTubeBending(good).intact, isTrue);
    String patched(String k, Object? v) =>
        jsonEncode(Map<String, Object?>.from(jsonDecode(good) as Map)..[k] = v);
    for (final bad in [
      patched('segments', [150, 120]),
      patched('rotations', [null]),
      patched('v', 2),
      patched('mode', 'spirala'),
      patched('clr', '38'),
      patched('single', [90]),
      '[]',
      '',
    ]) {
      expect(decodeTubeBending(bad).intact, isFalse, reason: bad);
      expect(decodeTubeBending(bad).state, isNull, reason: bad);
    }
  });

  test('wartość innego typu w pamięci → kopia jako tekst', () async {
    SharedPreferences.setMockInitialValues({TubeBendingStore.key: 42});
    const store = TubeBendingStore();
    expect((await store.load()).damaged, isTrue);
    await store.save(_tube);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(TubeBendingStore.corruptKey), '42');
  });

  test('nieudany odczyt: pusty stan, pierwszy zapis zachowuje dobrą rurkę',
      () async {
    final original = encodeTubeBending(_tube);
    SharedPreferences.setMockInitialValues({TubeBendingStore.key: original});
    final store = _FlakyStore();
    final l = await store.load();
    expect(l.readFailed, isTrue);
    expect(l.state, isNull);
    const other = TubeBendingSaved(
      mode: TubeBendingMode.single,
      unit: TubeUnit.mm,
      segmentsMm: [100, 100],
      anglesDeg: [90],
      rotationsDeg: [null],
    );
    await store.save(other, afterFailedRead: true);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(TubeBendingStore.corruptKey), original);
    expect((await store.load()).state!.mode, TubeBendingMode.single);
  });
}
