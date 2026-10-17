// Magazyn reguł planu badań NDT: osobno per projekt, klucz z wersją, kopia
// uszkodzonego zapisu przed nadpisaniem (tylko raz).

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:cut_list_app/domain/ndt/ndt_plan.dart';
import 'package:cut_list_app/features/ndt_plan/ndt_plan_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const store = NdtPlanStore();

  test('zapis i odczyt per projekt (klucz bez wielkości liter i spacji)',
      () async {
    SharedPreferences.setMockInitialValues({});
    final b313 = NdtRuleSet.fromPreset(NdtPreset.b313);
    final rt100 = NdtRuleSet.fromPreset(NdtPreset.rt100);
    await store.save('Blok 4', b313);
    await store.save('Browar', rt100);
    expect(NdtPlanStore.keyFor(' BLOK 4 '), 'ndt_plan.rules_v1.blok 4');
    final a = await store.load(' blok 4 ');
    expect(a.intact, isTrue);
    expect(a.saved, isTrue);
    expect(a.set, b313);
    expect((await store.load('Browar')).set, rt100);
    final none = await store.load('Inny');
    expect(none.saved, isFalse);
    expect(none.intact, isTrue);
    expect(none.set.rules, isEmpty);
  });

  test('uszkodzony zapis: kopia surowego tekstu przed nadpisaniem, tylko raz',
      () async {
    const raw = '{"v":1,"rules":[{"id":"a","method":"RT","pct":150';
    SharedPreferences.setMockInitialValues(
        {NdtPlanStore.keyFor('Blok 4'): raw});
    final load = await store.load('Blok 4');
    expect(load.intact, isFalse);
    expect(load.set.rules, isEmpty);

    await store.save('Blok 4', NdtRuleSet.fromPreset(NdtPreset.rt100));
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(NdtPlanStore.corruptKeyFor('Blok 4')), raw);
    expect((await store.load('Blok 4')).intact, isTrue);

    // Kolejny uszkodzony zapis nie nadpisuje pierwszej kopii.
    await prefs.setString(NdtPlanStore.keyFor('Blok 4'), 'zepsute');
    await store.save('Blok 4', NdtRuleSet.fromPreset(NdtPreset.b313));
    expect(prefs.getString(NdtPlanStore.corruptKeyFor('Blok 4')), raw);
  });

  test('reguła spoza zakresu w zapisie = uszkodzony; wartość nie-tekst też',
      () async {
    SharedPreferences.setMockInitialValues({
      NdtPlanStore.keyFor('A'):
          '{"v":1,"rules":[{"id":"a","method":"RT","pct":-5,"joints":["BW"]}]}',
      NdtPlanStore.keyFor('B'): 42,
    });
    final a = await store.load('A');
    expect(a.intact, isFalse);
    expect(a.dropped, 1);
    final b = await store.load('B');
    expect(b.intact, isFalse);
    await store.save('B', const NdtRuleSet());
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(NdtPlanStore.corruptKeyFor('B')), '42');
  });
}
