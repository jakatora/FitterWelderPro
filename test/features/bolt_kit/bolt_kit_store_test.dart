// Zapis listy połączeń: klucz z wersją, nienadpisywane kopie uszkodzeń.

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

import 'package:cut_list_app/domain/bolting/bolt_kit.dart';
import 'package:cut_list_app/features/bolt_kit/bolt_kit_store.dart';

/// Magazyn, którego pierwszy odczyt rzuca (chwilowy błąd platformy), a
/// kolejne działają.
class _FlakyStore extends BoltKitStore {
  _FlakyStore();

  var reads = 0;

  @override
  Future<Object?> readRaw() async {
    if (reads++ == 0) throw StateError('kanał platformy niedostępny');
    return super.readRaw();
  }
}

class _ControlledPreferences extends InMemorySharedPreferencesStore {
  _ControlledPreferences() : super.empty();

  String? refusedKey;
  String? unpersistedKey;

  @override
  Future<bool> setValue(String valueType, String key, Object value) async {
    if (key == refusedKey) return false;
    if (key == unpersistedKey) return true;
    return super.setValue(valueType, key, value);
  }
}

const _joint = BoltKitJoint(
  id: 'a',
  dn: 100,
  cls: 300,
  facing: FlangeFacing.rf,
  material: BoltMaterial.b7,
  count: 2,
);

void main() {
  test('zapis i odczyt', () async {
    SharedPreferences.setMockInitialValues({});
    const store = BoltKitStore();
    await store.save(const BoltKitState(joints: [_joint], sparePercent: 5));
    final l = await store.load();
    expect(l.damaged, isFalse);
    expect(l.state.joints.single.count, 2);
    expect(l.state.sparePercent, 5);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.containsKey(BoltKitStore.corruptKey), isFalse);
  });

  test('uszkodzony zapis: drugi surowy zapis dostaje osobną kopię', () async {
    SharedPreferences.setMockInitialValues(
        {BoltKitStore.key: '{"v":1,"joints":[{'});
    const store = BoltKitStore();
    final l = await store.load();
    expect(l.damaged, isTrue);
    expect(l.state.joints, isEmpty);

    await store.save(const BoltKitState(joints: [_joint]));
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(BoltKitStore.corruptKey), '{"v":1,"joints":[{');
    expect((await store.load()).damaged, isFalse);

    // Kolejne uszkodzenie nie nadpisuje pierwszej kopii.
    await prefs.setString(BoltKitStore.key, 'zepsute');
    await store.save(const BoltKitState());
    expect(prefs.getString(BoltKitStore.corruptKey), '{"v":1,"joints":[{');
    expect(prefs.getString('${BoltKitStore.corruptKey}_2'), 'zepsute');
  });

  test('dwie pełne kopie blokują nadpisanie trzeciego uszkodzenia', () async {
    SharedPreferences.setMockInitialValues({
      BoltKitStore.key: 'trzecie uszkodzenie',
      BoltKitStore.corruptKey: 'pierwsze',
      '${BoltKitStore.corruptKey}_2': 'drugie',
    });
    await expectLater(const BoltKitStore().save(const BoltKitState()),
        throwsA(isA<BoltKitSaveBlocked>()));
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(BoltKitStore.key), 'trzecie uszkodzenie');
    expect(prefs.getString(BoltKitStore.corruptKey), 'pierwsze');
    expect(prefs.getString('${BoltKitStore.corruptKey}_2'), 'drugie');
  });

  test('odmowa kopii po odczycie nie pozwala nadpisać listy', () async {
    SharedPreferences.setMockInitialValues({});
    final disk = _ControlledPreferences();
    SharedPreferencesStorePlatform.instance = disk;
    await disk.setValue('String', 'flutter.${BoltKitStore.key}', 'zepsute');
    disk.refusedKey = 'flutter.${BoltKitStore.corruptKey}';
    const store = BoltKitStore();
    expect((await store.load()).damaged, isTrue);
    await expectLater(
        store.save(const BoltKitState()), throwsA(isA<BoltKitSaveBlocked>()));
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    expect(prefs.getString(BoltKitStore.key), 'zepsute');
    expect(prefs.containsKey(BoltKitStore.corruptKey), isFalse);
  });

  test('kopia przyjęta tylko do cache nie pozwala nadpisać listy', () async {
    SharedPreferences.setMockInitialValues({});
    final disk = _ControlledPreferences();
    SharedPreferencesStorePlatform.instance = disk;
    await disk.setValue('String', 'flutter.${BoltKitStore.key}', 'zepsute');
    disk.unpersistedKey = 'flutter.${BoltKitStore.corruptKey}';
    await expectLater(const BoltKitStore().save(const BoltKitState()),
        throwsA(isA<BoltKitSaveBlocked>()));
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    expect(prefs.getString(BoltKitStore.key), 'zepsute');
  });

  test('odmowa głównego zapisu nie pokazuje nowej listy po odczycie', () async {
    SharedPreferences.setMockInitialValues({});
    final disk = _ControlledPreferences();
    SharedPreferencesStorePlatform.instance = disk;
    final original = encodeBoltKit(const BoltKitState(joints: [_joint]));
    await disk.setValue('String', 'flutter.${BoltKitStore.key}', original);
    disk.refusedKey = 'flutter.${BoltKitStore.key}';
    const store = BoltKitStore();
    await expectLater(
        store.save(const BoltKitState()), throwsA(isA<StateError>()));
    expect((await store.load()).state.joints.single.id, 'a');
  });

  test('pozorny sukces głównego zapisu jest wykrywany po przeładowaniu',
      () async {
    SharedPreferences.setMockInitialValues({});
    final disk = _ControlledPreferences();
    SharedPreferencesStorePlatform.instance = disk;
    final original = encodeBoltKit(const BoltKitState(joints: [_joint]));
    await disk.setValue('String', 'flutter.${BoltKitStore.key}', original);
    disk.unpersistedKey = 'flutter.${BoltKitStore.key}';
    const store = BoltKitStore();
    await expectLater(
        store.save(const BoltKitState()), throwsA(isA<StateError>()));
    expect((await store.load()).state.joints.single.id, 'a');
  });

  test('wartość innego typu → uszkodzony, kopia jako tekst', () async {
    SharedPreferences.setMockInitialValues({BoltKitStore.key: 42});
    const store = BoltKitStore();
    expect((await store.load()).damaged, isTrue);
    await store.save(const BoltKitState());
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(BoltKitStore.corruptKey), '42');
  });

  group('nieudany odczyt', () {
    const other = BoltKitJoint(
      id: 'b',
      dn: 50,
      cls: 150,
      facing: FlangeFacing.rf,
      material: BoltMaterial.b8m,
      count: 1,
    );

    test(
        'pierwszy odczyt rzuca: pusta lista, a pierwszy zapis zachowuje '
        'dobrą listę w kopii', () async {
      final original =
          encodeBoltKit(const BoltKitState(joints: [_joint], sparePercent: 5));
      SharedPreferences.setMockInitialValues({BoltKitStore.key: original});
      final store = _FlakyStore();
      final l = await store.load();
      expect(l.readFailed, isTrue);
      expect(l.damaged, isTrue);
      expect(l.state.joints, isEmpty);

      await store.save(const BoltKitState(joints: [other]),
          afterFailedRead: true);
      final prefs = await SharedPreferences.getInstance();
      // Lista sprzed błędu odczytu nie przepadła — jest w kopii.
      expect(prefs.getString(BoltKitStore.corruptKey), original);
      final copy =
          decodeBoltKitReport(prefs.getString(BoltKitStore.corruptKey));
      expect(copy.state.joints.single.id, 'a');
      final now = await store.load();
      expect(now.readFailed, isFalse);
      expect(now.state.joints.single.id, 'b');

      // Kolejne zapisy już bez kopii — w pamięci jest lista tego ekranu.
      await store.save(const BoltKitState(joints: [other, _joint]));
      expect(prefs.getString(BoltKitStore.corruptKey), original);
    });

    test('dwie kopie zajęte → zapis wstrzymany, lista nienadpisana', () async {
      final original = encodeBoltKit(const BoltKitState(joints: [_joint]));
      SharedPreferences.setMockInitialValues({
        BoltKitStore.key: original,
        BoltKitStore.corruptKey: 'starsza kopia',
        '${BoltKitStore.corruptKey}_2': 'druga kopia',
      });
      const store = BoltKitStore();
      await expectLater(
          store.save(const BoltKitState(joints: [other]),
              afterFailedRead: true),
          throwsA(isA<BoltKitSaveBlocked>()));
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(BoltKitStore.key), original);
      expect(prefs.getString(BoltKitStore.corruptKey), 'starsza kopia');
      expect(prefs.getString('${BoltKitStore.corruptKey}_2'), 'druga kopia');
    });

    test('zajęta pierwsza kopia pozwala zachować nieodczytaną listę w drugiej',
        () async {
      final original = encodeBoltKit(const BoltKitState(joints: [_joint]));
      SharedPreferences.setMockInitialValues({
        BoltKitStore.key: original,
        BoltKitStore.corruptKey: 'starsza kopia',
      });
      await const BoltKitStore()
          .save(const BoltKitState(joints: [other]), afterFailedRead: true);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(BoltKitStore.corruptKey), 'starsza kopia');
      expect(prefs.getString('${BoltKitStore.corruptKey}_2'), original);
      expect(
          decodeBoltKitReport(prefs.getString(BoltKitStore.key))
              .state
              .joints
              .single
              .id,
          'b');
    });

    test('kopia równa tej wartości → zapis przechodzi', () async {
      final original = encodeBoltKit(const BoltKitState(joints: [_joint]));
      SharedPreferences.setMockInitialValues({
        BoltKitStore.key: original,
        BoltKitStore.corruptKey: original,
      });
      await const BoltKitStore()
          .save(const BoltKitState(joints: [other]), afterFailedRead: true);
      final prefs = await SharedPreferences.getInstance();
      expect(
          decodeBoltKitReport(prefs.getString(BoltKitStore.key))
              .state
              .joints
              .single
              .id,
          'b');
    });

    test('nic nie było zapisane albo pusta lista — zapis bez kopii', () async {
      for (final initial in <Map<String, Object>>[
        {},
        {BoltKitStore.key: encodeBoltKit(const BoltKitState())},
      ]) {
        SharedPreferences.setMockInitialValues(initial);
        await const BoltKitStore()
            .save(const BoltKitState(joints: [other]), afterFailedRead: true);
        final prefs = await SharedPreferences.getInstance();
        expect(prefs.containsKey(BoltKitStore.corruptKey), isFalse,
            reason: '$initial');
      }
    });
  });
}
