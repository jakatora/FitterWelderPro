// Zapis ostatnich wejść planu ściegów: uszkodzony zapis nie znika po
// cichu — surowy tekst trafia pod klucz kopii, odczyt daje wartości
// domyślne z flagą straty; inny typ wartości w prefs nie wywala odczytu.

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

import 'package:cut_list_app/domain/pass_plan/pass_plan_form.dart';
import 'package:cut_list_app/features/pass_plan/pass_plan_store.dart';

class _ControlledPreferences extends InMemorySharedPreferencesStore {
  _ControlledPreferences() : super.empty();

  String? refusedKey;
  bool delayFirstMainWrite = false;
  final firstWriteStarted = Completer<void>();
  final releaseFirstWrite = Completer<void>();
  var mainWrites = 0;

  @override
  Future<bool> setValue(String valueType, String key, Object value) async {
    if (key == refusedKey) return false;
    if (key == 'flutter.$kPassPlanPrefsKey' &&
        delayFirstMainWrite &&
        mainWrites++ == 0) {
      firstWriteStarted.complete();
      await releaseFirstWrite.future;
    }
    return super.setValue(valueType, key, value);
  }
}

void main() {
  const store = PassPlanStore();

  test('odczyt podczas autozapisu czeka na aktualny formularz', () async {
    SharedPreferences.setMockInitialValues({});
    final disk = _ControlledPreferences()..delayFirstMainWrite = true;
    SharedPreferencesStorePlatform.instance = disk;
    final form = {...passPlanDefaultForm(), 'od': '114,3', 'count': '12'};
    final writing = store.save(form);
    await disk.firstWriteStarted.future;
    final reading = store.load();
    await Future<void>.delayed(Duration.zero);
    disk.releaseFirstWrite.complete();
    await writing;
    expect((await reading)?.form, form);
  });

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

  test('drugi uszkodzony zapis zachowuje osobną kopię', () async {
    SharedPreferences.setMockInitialValues({
      kPassPlanPrefsKey: 'drugie uszkodzenie',
      kPassPlanCorruptPrefsKey: 'pierwsze uszkodzenie',
    });
    await store.save(passPlanDefaultForm());
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(kPassPlanCorruptPrefsKey), 'pierwsze uszkodzenie');
    expect(
        prefs.getString('${kPassPlanCorruptPrefsKey}_2'), 'drugie uszkodzenie');
  });

  test('pełne kopie blokują nadpisanie trzeciego uszkodzenia', () async {
    SharedPreferences.setMockInitialValues({
      kPassPlanPrefsKey: 'trzecie uszkodzenie',
      kPassPlanCorruptPrefsKey: 'pierwsze',
      '${kPassPlanCorruptPrefsKey}_2': 'drugie',
    });
    await expectLater(
        store.save(passPlanDefaultForm()), throwsA(isA<StateError>()));
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(kPassPlanPrefsKey), 'trzecie uszkodzenie');
    expect(prefs.getString(kPassPlanCorruptPrefsKey), 'pierwsze');
    expect(prefs.getString('${kPassPlanCorruptPrefsKey}_2'), 'drugie');
  });

  test('odmowa trwałego zapisu kopii blokuje nadpisanie', () async {
    SharedPreferences.setMockInitialValues({});
    final disk = _ControlledPreferences();
    SharedPreferencesStorePlatform.instance = disk;
    await disk.setValue('String', 'flutter.$kPassPlanPrefsKey', 'uszkodzony');
    disk.refusedKey = 'flutter.$kPassPlanCorruptPrefsKey';

    await expectLater(
        store.save(passPlanDefaultForm()), throwsA(isA<StateError>()));
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    expect(prefs.getString(kPassPlanPrefsKey), 'uszkodzony');
    expect(prefs.containsKey(kPassPlanCorruptPrefsKey), isFalse);
  });

  test('odmowa zapisu formularza jest błędem', () async {
    SharedPreferences.setMockInitialValues({});
    final disk = _ControlledPreferences();
    SharedPreferencesStorePlatform.instance = disk;
    disk.refusedKey = 'flutter.$kPassPlanPrefsKey';

    await expectLater(
        store.save(passPlanDefaultForm()), throwsA(isA<StateError>()));
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    expect(prefs.containsKey(kPassPlanPrefsKey), isFalse);
  });

  test('równoległe autozapisy zachowują najnowszy formularz', () async {
    SharedPreferences.setMockInitialValues({});
    final disk = _ControlledPreferences()..delayFirstMainWrite = true;
    SharedPreferencesStorePlatform.instance = disk;
    addTearDown(() {
      if (!disk.releaseFirstWrite.isCompleted) {
        disk.releaseFirstWrite.complete();
      }
    });
    final first =
        store.save({...passPlanDefaultForm(), PassPlanField.count: '2'});
    await disk.firstWriteStarted.future;
    final second =
        store.save({...passPlanDefaultForm(), PassPlanField.count: '3'});
    await Future<void>.delayed(const Duration(milliseconds: 50));
    disk.releaseFirstWrite.complete();
    await Future.wait([first, second]);

    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    expect((await store.load())!.form[PassPlanField.count], '3');
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
