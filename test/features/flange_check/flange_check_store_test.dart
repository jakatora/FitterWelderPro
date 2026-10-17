// Magazyn historii protokołów: uszkodzony zapis nie ginie przy nadpisaniu.

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:cut_list_app/domain/flange/flange_check.dart';
import 'package:cut_list_app/features/flange_check/flange_check_store.dart';

const _store = FlangeCheckStore();
const _one = FlangeCheck(id: 'n1', joint: FlangeJoint(tag: 'N-1'));

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

  test('istniejąca kopia nie jest nadpisywana', () async {
    final prefs = await _prefs({
      FlangeCheckStore.key: 'zepsute-2',
      FlangeCheckStore.corruptKey: 'zepsute-1',
    });
    await _store.save([_one]);
    expect(prefs.getString(FlangeCheckStore.corruptKey), 'zepsute-1');
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
