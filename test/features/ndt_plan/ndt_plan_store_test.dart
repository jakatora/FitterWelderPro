// Magazyn reguł planu badań NDT: osobno per projekt, klucz z wersją, kopia
// uszkodzonego zapisu przed nadpisaniem, trwałość i kolejność zapisów.

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

import 'package:cut_list_app/domain/ndt/ndt_plan.dart';
import 'package:cut_list_app/features/ndt_plan/ndt_plan_store.dart';

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

class _DelayedFirstWrite extends InMemorySharedPreferencesStore {
  _DelayedFirstWrite() : super.empty();

  final entered = Completer<void>();
  final release = Completer<void>();
  final secondEntered = Completer<void>();
  var writes = 0;

  @override
  Future<bool> setValue(String valueType, String key, Object value) async {
    if (key == 'flutter.${NdtPlanStore.keyFor('Blok 4')}') {
      writes++;
      if (writes == 1) {
        entered.complete();
        await release.future;
      } else if (writes == 2) {
        secondEntered.complete();
      }
    }
    return super.setValue(valueType, key, value);
  }
}

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

  test('uszkodzony zapis: dwa różne surowe teksty mają osobne kopie', () async {
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
    expect(
        prefs.getString(NdtPlanStore.secondCorruptKeyFor('Blok 4')), 'zepsute');
  });

  test('pełne kopie blokują trzecie uszkodzenie', () async {
    SharedPreferences.setMockInitialValues({
      NdtPlanStore.keyFor('Blok 4'): 'trzecie',
      NdtPlanStore.corruptKeyFor('Blok 4'): 'pierwsze',
      NdtPlanStore.secondCorruptKeyFor('Blok 4'): 'drugie',
    });
    await expectLater(
        store.save('Blok 4', NdtRuleSet.fromPreset(NdtPreset.rt100)),
        throwsStateError);
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    expect(prefs.getString(NdtPlanStore.keyFor('Blok 4')), 'trzecie');
  });

  test('druga kopia projektu nie koliduje z pierwszą kopią innego', () async {
    SharedPreferences.setMockInitialValues({
      NdtPlanStore.keyFor('Blok 4'): 'a1',
      NdtPlanStore.keyFor('Blok 4_2'): 'b1',
    });
    final rules = NdtRuleSet.fromPreset(NdtPreset.rt100);
    await store.save('Blok 4_2', rules);
    await store.save('Blok 4', rules);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(NdtPlanStore.keyFor('Blok 4'), 'a2');
    await store.save('Blok 4', rules);
    await prefs.reload();
    expect(prefs.getString(NdtPlanStore.corruptKeyFor('Blok 4_2')), 'b1');
    expect(prefs.getString(NdtPlanStore.corruptKeyFor('Blok 4')), 'a1');
    expect(prefs.getString(NdtPlanStore.secondCorruptKeyFor('Blok 4')), 'a2');
  });

  test('odmowa zapisu kopii blokuje nadpisanie reguł', () async {
    SharedPreferences.setMockInitialValues({});
    final disk = _ControlledPreferences();
    SharedPreferencesStorePlatform.instance = disk;
    await disk.setValue(
        'String', 'flutter.${NdtPlanStore.keyFor('Blok 4')}', 'uszkodzone');
    disk.refusedKey = 'flutter.${NdtPlanStore.corruptKeyFor('Blok 4')}';
    await expectLater(
        store.save('Blok 4', NdtRuleSet.fromPreset(NdtPreset.rt100)),
        throwsStateError);
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    expect(prefs.getString(NdtPlanStore.keyFor('Blok 4')), 'uszkodzone');
  });

  test('pozorny sukces kopii blokuje nadpisanie reguł', () async {
    SharedPreferences.setMockInitialValues({});
    final disk = _ControlledPreferences();
    SharedPreferencesStorePlatform.instance = disk;
    await disk.setValue(
        'String', 'flutter.${NdtPlanStore.keyFor('Blok 4')}', 'uszkodzone');
    disk.unpersistedKey = 'flutter.${NdtPlanStore.corruptKeyFor('Blok 4')}';
    await expectLater(
        store.save('Blok 4', NdtRuleSet.fromPreset(NdtPreset.rt100)),
        throwsStateError);
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    expect(prefs.getString(NdtPlanStore.keyFor('Blok 4')), 'uszkodzone');
  });

  test('odmowa głównego zapisu nie zmienia trwałych reguł', () async {
    SharedPreferences.setMockInitialValues({});
    final disk = _ControlledPreferences();
    SharedPreferencesStorePlatform.instance = disk;
    final old = NdtRuleSet.fromPreset(NdtPreset.b313);
    await disk.setValue(
        'String', 'flutter.${NdtPlanStore.keyFor('Blok 4')}', old.encode());
    disk.refusedKey = 'flutter.${NdtPlanStore.keyFor('Blok 4')}';
    await expectLater(
        store.save('Blok 4', NdtRuleSet.fromPreset(NdtPreset.rt100)),
        throwsStateError);
    expect((await store.load('Blok 4')).set, old);
  });

  test('pozorny sukces głównego zapisu jest wykrywany', () async {
    SharedPreferences.setMockInitialValues({});
    final disk = _ControlledPreferences();
    SharedPreferencesStorePlatform.instance = disk;
    final old = NdtRuleSet.fromPreset(NdtPreset.b313);
    await disk.setValue(
        'String', 'flutter.${NdtPlanStore.keyFor('Blok 4')}', old.encode());
    disk.unpersistedKey = 'flutter.${NdtPlanStore.keyFor('Blok 4')}';
    await expectLater(
        store.save('Blok 4', NdtRuleSet.fromPreset(NdtPreset.rt100)),
        throwsStateError);
    expect((await store.load('Blok 4')).set, old);
  });

  test('opóźniony starszy zapis nie zastępuje nowszych reguł', () async {
    SharedPreferences.setMockInitialValues({});
    final disk = _DelayedFirstWrite();
    SharedPreferencesStorePlatform.instance = disk;
    final first = store.save('Blok 4', NdtRuleSet.fromPreset(NdtPreset.b313));
    await disk.entered.future;
    final second = store.save('Blok 4', NdtRuleSet.fromPreset(NdtPreset.rt100));
    await Future.any<void>([
      disk.secondEntered.future,
      Future<void>.delayed(const Duration(milliseconds: 300)),
    ]);
    disk.release.complete();
    await Future.wait([first, second]);
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    expect((await store.load('Blok 4')).set,
        NdtRuleSet.fromPreset(NdtPreset.rt100));
  });

  test('N5: błąd odczytu to nie uszkodzenie — readFailed, zapis rzuca',
      () async {
    final failing = NdtPlanStore(prefs: () async => throw StateError('io'));
    final load = await failing.load('Blok 4');
    expect(load.readFailed, isTrue);
    expect(load.intact, isFalse);
    expect(load.set.rules, isEmpty);
    await expectLater(
        failing.save('Blok 4', NdtRuleSet.fromPreset(NdtPreset.rt100)),
        throwsStateError);
    // Zwykły uszkodzony zapis nie jest błędem odczytu.
    SharedPreferences.setMockInitialValues(
        {NdtPlanStore.keyFor('Blok 4'): 'zepsute'});
    final damaged = await store.load('Blok 4');
    expect(damaged.intact, isFalse);
    expect(damaged.readFailed, isFalse);
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
