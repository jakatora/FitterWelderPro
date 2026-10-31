// Zapis ostatnich danych kalkulatora zawiesi w SharedPreferences: brak
// zapisu, zapis i odczyt, uszkodzony JSON, wartość innego typu.

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

import 'package:cut_list_app/domain/rigging/rigging_calc.dart';
import 'package:cut_list_app/domain/rigging/rigging_inputs.dart';
import 'package:cut_list_app/features/rigging/rigging_store.dart';

class _RefusingPreferences extends InMemorySharedPreferencesStore {
  _RefusingPreferences() : super.empty();
  bool refuse = false;
  bool pretend = false;

  @override
  Future<bool> setValue(String valueType, String key, Object value) {
    if (refuse) return Future.value(false);
    if (pretend) return Future.value(true);
    return super.setValue(valueType, key, value);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const store = RiggingStore();

  test('pozorny sukces zapisu jest wykrywany po odczycie z urządzenia',
      () async {
    SharedPreferences.setMockInitialValues({});
    final disk = _RefusingPreferences();
    SharedPreferencesStorePlatform.instance = disk;
    await store.save(const RiggingSavedInputs(unit: MassUnit.kg));
    disk.pretend = true;
    await expectLater(store.save(const RiggingSavedInputs(unit: MassUnit.t)),
        throwsStateError);
    expect((await store.load()).inputs!.unit, MassUnit.kg);
  });

  test('odmowa zapisu nie udaje trwałego zapamiętania ustawień', () async {
    SharedPreferences.setMockInitialValues({});
    final disk = _RefusingPreferences();
    SharedPreferencesStorePlatform.instance = disk;
    await store.save(const RiggingSavedInputs(unit: MassUnit.kg));
    disk.refuse = true;
    await expectLater(store.save(const RiggingSavedInputs(unit: MassUnit.t)),
        throwsStateError);
    expect((await store.load()).inputs!.unit, MassUnit.kg);
  });

  test('brak zapisu → null, nie uszkodzony', () async {
    SharedPreferences.setMockInitialValues({});
    final l = await store.load();
    expect(l.inputs, isNull);
    expect(l.damaged, isFalse);
  });

  test('zapis i odczyt', () async {
    SharedPreferences.setMockInitialValues({});
    const s = RiggingSavedInputs(
        unit: MassUnit.t, sling: SlingType.chain, mode: HitchMode.choke);
    await store.save(s);
    final l = await store.load();
    expect(l.damaged, isFalse);
    expect(l.inputs!.toJson(), s.toJson());
  });

  test('uszkodzony JSON → domyślne z flagą, bez wyjątku', () async {
    SharedPreferences.setMockInitialValues({RiggingStore.key: '{zepsute'});
    final l = await store.load();
    expect(l.damaged, isTrue);
    expect(l.inputs!.toJson(), const RiggingSavedInputs().toJson());
  });

  test('wartość innego typu → domyślne z flagą', () async {
    SharedPreferences.setMockInitialValues({RiggingStore.key: 42});
    final l = await store.load();
    expect(l.damaged, isTrue);
    expect(l.inputs!.toJson(), const RiggingSavedInputs().toJson());
  });
}
