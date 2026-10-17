// Zapis ostatnich danych kalkulatora zawiesi w SharedPreferences: brak
// zapisu, zapis i odczyt, uszkodzony JSON, wartość innego typu.

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:cut_list_app/domain/rigging/rigging_calc.dart';
import 'package:cut_list_app/domain/rigging/rigging_inputs.dart';
import 'package:cut_list_app/features/rigging/rigging_store.dart';

void main() {
  const store = RiggingStore();

  test('brak zapisu → null, nie uszkodzony', () async {
    SharedPreferences.setMockInitialValues({});
    final l = await store.load();
    expect(l.inputs, isNull);
    expect(l.damaged, isFalse);
  });

  test('zapis i odczyt', () async {
    SharedPreferences.setMockInitialValues({});
    const s = RiggingSavedInputs(
        mass: '1600', sling: SlingType.chain, mode: HitchMode.choke);
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
    expect(l.inputs!.mass, '');
  });
}
