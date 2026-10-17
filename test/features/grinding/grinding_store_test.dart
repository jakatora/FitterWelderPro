// Magazyn „Moje szlifierki”: uszkodzony zapis nie znika po cichu — surowa
// wartość trafia RAZ pod klucz kopii (przy odczycie i przed zapisem);
// inny typ wartości w SharedPreferences nie wywala odczytu.

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:cut_list_app/domain/grinding/grinder_profile.dart';
import 'package:cut_list_app/features/grinding/grinding_store.dart';

const _a = GrinderProfile(id: 'a', name: 'A', maxRpm: 11000, diameterMm: 125);

void main() {
  const store = GrinderStore();

  test('brak zapisu → pusta lista, nieuszkodzony', () async {
    SharedPreferences.setMockInitialValues({});
    final r = await store.load();
    expect(r.grinders, isEmpty);
    expect(r.damaged, isFalse);
  });

  test('zapis i odczyt', () async {
    SharedPreferences.setMockInitialValues({});
    await store.save([_a]);
    final r = await store.load();
    expect(r.grinders, [_a]);
    expect(r.damaged, isFalse);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.containsKey(kGrindersCorruptPrefsKey), isFalse);
  });

  test('uszkodzony JSON: pusta lista, damaged i kopia surowego zapisu',
      () async {
    SharedPreferences.setMockInitialValues({kGrindersPrefsKey: '[{"id":'});
    final r = await store.load();
    expect(r.grinders, isEmpty);
    expect(r.damaged, isTrue);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(kGrindersCorruptPrefsKey), '[{"id":');
  });

  test('kopia tylko raz — kolejne uszkodzenie jej nie nadpisuje', () async {
    SharedPreferences.setMockInitialValues({
      kGrindersPrefsKey: 'drugie uszkodzenie',
      kGrindersCorruptPrefsKey: 'pierwsze uszkodzenie',
    });
    expect((await store.load()).damaged, isTrue);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(kGrindersCorruptPrefsKey), 'pierwsze uszkodzenie');
  });

  test('wartość innego typu → damaged i kopia, bez wyjątku', () async {
    SharedPreferences.setMockInitialValues({kGrindersPrefsKey: 42});
    final r = await store.load();
    expect(r.grinders, isEmpty);
    expect(r.damaged, isTrue);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(kGrindersCorruptPrefsKey), '42');
  });

  test('zapis po uszkodzeniu nie gubi oryginału (kopia przed nadpisaniem)',
      () async {
    const broken = '[{"id":"a","name":"A","rpm":11000,"d":125},{"id":';
    SharedPreferences.setMockInitialValues({kGrindersPrefsKey: broken});
    // Zapis bez wcześniejszego odczytu — kopia i tak powstaje.
    await store.save([_a]);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(kGrindersCorruptPrefsKey), broken);
    expect((await store.load()).grinders, [_a]);
  });
}
