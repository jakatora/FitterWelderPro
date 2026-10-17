// Zapis listy połączeń: klucz z wersją, kopia uszkodzonego zapisu przed
// nadpisaniem (tylko raz).

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:cut_list_app/domain/bolting/bolt_kit.dart';
import 'package:cut_list_app/features/bolt_kit/bolt_kit_store.dart';

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
}
