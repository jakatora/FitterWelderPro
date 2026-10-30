// Magazyn historii protokołów: uszkodzony zapis nie ginie przy nadpisaniu.

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

import 'package:cut_list_app/domain/flange/flange_check.dart';
import 'package:cut_list_app/features/flange_check/flange_check_store.dart';

const _store = FlangeCheckStore();
const _one = FlangeCheck(id: 'n1', joint: FlangeJoint(tag: 'N-1'));

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

class _FlakyStore extends FlangeCheckStore {
  var reads = 0;

  @override
  Future<Object?> readRaw() async {
    if (reads++ == 0) throw StateError('chwilowy błąd odczytu');
    return super.readRaw();
  }
}

Future<SharedPreferences> _prefs(Map<String, Object> initial) async {
  SharedPreferences.setMockInitialValues(initial);
  return SharedPreferences.getInstance();
}

void main() {
  test('uszkodzony JSON: kopia pod flange_checks_v1_corrupt przed nadpisaniem',
      () async {
    const raw = '{"v":1,"checks":[{';
    final prefs = await _prefs({FlangeCheckStore.key: raw});
    final loaded = await _store.loadWithStatus();
    expect(loaded.checks, isEmpty);
    expect(loaded.damaged, isTrue);
    await _store.save([_one]);
    expect(prefs.getString(FlangeCheckStore.corruptKey), raw);
    expect(decodeFlangeChecks(prefs.getString(FlangeCheckStore.key)).single.id,
        'n1');
  });

  test(
      'wartość innego typu (liczba) — pusta lista bez wyjątku, kopia przy '
      'zapisie', () async {
    final prefs = await _prefs({FlangeCheckStore.key: 42});
    expect(await _store.load(), isEmpty);
    expect((await _store.loadWithStatus()).damaged, isTrue);
    await _store.save([_one]);
    expect(prefs.getString(FlangeCheckStore.corruptKey), '42');
    expect(await _store.load(), hasLength(1));
  });

  test('druga uszkodzona historia dostaje osobną kopię', () async {
    final prefs = await _prefs({
      FlangeCheckStore.key: 'zepsute-2',
      FlangeCheckStore.corruptKey: 'zepsute-1',
    });
    await _store.save([_one]);
    expect(prefs.getString(FlangeCheckStore.corruptKey), 'zepsute-1');
    expect(prefs.getString('${FlangeCheckStore.corruptKey}_2'), 'zepsute-2');
  });

  test('dwie pełne kopie blokują nadpisanie trzeciego uszkodzenia', () async {
    final prefs = await _prefs({
      FlangeCheckStore.key: 'zepsute-3',
      FlangeCheckStore.corruptKey: 'zepsute-1',
      '${FlangeCheckStore.corruptKey}_2': 'zepsute-2',
    });
    await expectLater(_store.save([_one]), throwsA(isA<StateError>()));
    expect(prefs.getString(FlangeCheckStore.key), 'zepsute-3');
  });

  test('odmowa kopii nie pozwala nadpisać uszkodzonej historii', () async {
    SharedPreferences.setMockInitialValues({});
    final disk = _ControlledPreferences();
    SharedPreferencesStorePlatform.instance = disk;
    await disk.setValue('String', 'flutter.${FlangeCheckStore.key}', 'zepsute');
    disk.refusedKey = 'flutter.${FlangeCheckStore.corruptKey}';
    expect((await _store.loadWithStatus()).damaged, isTrue);
    await expectLater(_store.save([_one]), throwsA(isA<StateError>()));
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    expect(prefs.getString(FlangeCheckStore.key), 'zepsute');
  });

  test('pozorny zapis kopii nie pozwala nadpisać historii', () async {
    SharedPreferences.setMockInitialValues({});
    final disk = _ControlledPreferences();
    SharedPreferencesStorePlatform.instance = disk;
    await disk.setValue('String', 'flutter.${FlangeCheckStore.key}', 'zepsute');
    disk.unpersistedKey = 'flutter.${FlangeCheckStore.corruptKey}';
    await expectLater(_store.save([_one]), throwsA(isA<StateError>()));
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    expect(prefs.getString(FlangeCheckStore.key), 'zepsute');
  });

  test('odmowa głównego zapisu pozostawia starą historię przy odczycie',
      () async {
    SharedPreferences.setMockInitialValues({});
    final disk = _ControlledPreferences();
    SharedPreferencesStorePlatform.instance = disk;
    await disk.setValue('String', 'flutter.${FlangeCheckStore.key}',
        encodeFlangeChecks([_one]));
    disk.refusedKey = 'flutter.${FlangeCheckStore.key}';
    await expectLater(_store.save([]), throwsA(isA<StateError>()));
    expect((await _store.load()).single.id, 'n1');
  });

  test('pozorny sukces głównego zapisu jest wykrywany po przeładowaniu',
      () async {
    SharedPreferences.setMockInitialValues({});
    final disk = _ControlledPreferences();
    SharedPreferencesStorePlatform.instance = disk;
    await disk.setValue('String', 'flutter.${FlangeCheckStore.key}',
        encodeFlangeChecks([_one]));
    disk.unpersistedKey = 'flutter.${FlangeCheckStore.key}';
    await expectLater(_store.save([]), throwsA(isA<StateError>()));
    expect((await _store.load()).single.id, 'n1');
  });

  test('po błędzie odczytu zapis zachowuje nawet poprawną starą historię',
      () async {
    final original = encodeFlangeChecks([_one]);
    final prefs = await _prefs({FlangeCheckStore.key: original});
    final store = _FlakyStore();
    final loaded = await store.loadWithStatus();
    expect(loaded.readFailed, isTrue);
    expect(loaded.checks, isEmpty);
    await store.save([const FlangeCheck(id: 'n2')], afterFailedRead: true);
    expect(prefs.getString(FlangeCheckStore.corruptKey), original);
    expect((await store.load()).single.id, 'n2');
  });

  test('po błędzie odczytu pełne kopie chronią poprawną starą historię',
      () async {
    final original = encodeFlangeChecks([_one]);
    final prefs = await _prefs({
      FlangeCheckStore.key: original,
      FlangeCheckStore.corruptKey: 'pierwsza kopia',
      '${FlangeCheckStore.corruptKey}_2': 'druga kopia',
    });
    final store = _FlakyStore();
    expect((await store.loadWithStatus()).readFailed, isTrue);
    await expectLater(
        store.save([const FlangeCheck(id: 'n2')], afterFailedRead: true),
        throwsA(isA<StateError>()));
    expect(prefs.getString(FlangeCheckStore.key), original);
  });

  test('częściowo uszkodzony: dobre wpisy zostają, surowy zapis w kopii',
      () async {
    final good = encodeFlangeChecks([_one]);
    final raw = good.replaceFirst(']}', ',{"noId":true}]}');
    final prefs = await _prefs({FlangeCheckStore.key: raw});
    final loaded = await _store.loadWithStatus();
    expect(loaded.checks.single.id, 'n1');
    expect(loaded.damaged, isTrue);
    await _store.save(loaded.checks);
    expect(prefs.getString(FlangeCheckStore.corruptKey), raw);
  });

  test('nienaruszony zapis — bez kopii', () async {
    final prefs = await _prefs({
      FlangeCheckStore.key: encodeFlangeChecks([_one])
    });
    expect((await _store.loadWithStatus()).damaged, isFalse);
    await _store.save([_one, const FlangeCheck(id: 'n2')]);
    expect(prefs.containsKey(FlangeCheckStore.corruptKey), isFalse);
    expect(await _store.load(), hasLength(2));
  });
}
