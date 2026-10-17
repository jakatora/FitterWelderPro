// Zapis listy połączeń: klucz z wersją, kopia uszkodzonego zapisu przed
// nadpisaniem (tylko raz).

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

  test('uszkodzony zapis: komunikat, kopia przed nadpisaniem — tylko raz',
      () async {
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

    test('kopia zajęta inną wartością → zapis wstrzymany, lista nienadpisana',
        () async {
      final original = encodeBoltKit(const BoltKitState(joints: [_joint]));
      SharedPreferences.setMockInitialValues({
        BoltKitStore.key: original,
        BoltKitStore.corruptKey: 'starsza kopia',
      });
      const store = BoltKitStore();
      await expectLater(
          store.save(const BoltKitState(joints: [other]),
              afterFailedRead: true),
          throwsA(isA<BoltKitSaveBlocked>()));
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(BoltKitStore.key), original);
      expect(prefs.getString(BoltKitStore.corruptKey), 'starsza kopia');
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
