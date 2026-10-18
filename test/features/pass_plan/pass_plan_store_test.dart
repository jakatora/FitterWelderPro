// Zapis ostatnich wejść planu ściegów: uszkodzony zapis nie znika po
// cichu — surowy tekst trafia raz pod klucz kopii, odczyt daje wartości
// domyślne z flagą straty; inny typ wartości w prefs nie wywala odczytu.

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:cut_list_app/domain/pass_plan/pass_plan_form.dart';
import 'package:cut_list_app/features/pass_plan/pass_plan_store.dart';

void main() {
  const store = PassPlanStore();

  test('zapis i odczyt formularza', () async {
    SharedPreferences.setMockInitialValues({});
    expect(await store.load(), isNull);
    final form = {...passPlanDefaultForm(), 'od': '114,3', 'count': '12'};
    await store.save(form);
    final loaded = await store.load();
    expect(loaded!.lossy, isFalse);
    expect(loaded.form, form);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.containsKey(kPassPlanCorruptPrefsKey), isFalse);
  });

  test('uszkodzony JSON: wartości domyślne, strata i kopia surowego zapisu',
      () async {
    SharedPreferences.setMockInitialValues(
        {kPassPlanPrefsKey: '{"v":1,"f":{"od":'});
    final loaded = await store.load();
    expect(loaded!.lossy, isTrue);
    expect(loaded.form, passPlanDefaultForm());
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(kPassPlanCorruptPrefsKey), '{"v":1,"f":{"od":');
  });

  test('kopia tylko raz — kolejne uszkodzenie jej nie nadpisuje', () async {
    SharedPreferences.setMockInitialValues({
      kPassPlanPrefsKey: 'drugie uszkodzenie',
      kPassPlanCorruptPrefsKey: 'pierwsze uszkodzenie',
    });
    expect((await store.load())!.lossy, isTrue);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(kPassPlanCorruptPrefsKey), 'pierwsze uszkodzenie');
  });

  test('zapis nad nieczytelnym surowcem najpierw robi kopię, potem nadpisuje',
      () async {
    // Np. zapis wywołany, zanim odczyt zdążył zachować kopię.
    SharedPreferences.setMockInitialValues(
        {kPassPlanPrefsKey: '{"v":1,"f":{"od":'});
    final form = {...passPlanDefaultForm(), 'od': '114,3'};
    await store.save(form);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(kPassPlanCorruptPrefsKey), '{"v":1,"f":{"od":');
    expect((await store.load())!.form, form);
    // Inny typ pod kluczem — też kopia.
    SharedPreferences.setMockInitialValues({kPassPlanPrefsKey: 7});
    await store.save(form);
    final p2 = await SharedPreferences.getInstance();
    expect(p2.getString(kPassPlanCorruptPrefsKey), '7');
    // Czytelny zapis — bez kopii.
    SharedPreferences.setMockInitialValues(
        {kPassPlanPrefsKey: encodePassPlanForm(passPlanDefaultForm())});
    await store.save(form);
    final p3 = await SharedPreferences.getInstance();
    expect(p3.containsKey(kPassPlanCorruptPrefsKey), isFalse);
  });

  test('inny typ wartości w prefs (liczba, lista) nie wywala odczytu',
      () async {
    for (final value in <Object>[
      5,
      true,
      <String>['a', 'b']
    ]) {
      SharedPreferences.setMockInitialValues({kPassPlanPrefsKey: value});
      final loaded = await store.load();
      expect(loaded!.lossy, isTrue, reason: '$value');
      expect(loaded.form, passPlanDefaultForm(), reason: '$value');
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(kPassPlanCorruptPrefsKey), isNotNull,
          reason: '$value');
    }
  });
}
