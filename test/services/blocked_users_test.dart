import 'package:cut_list_app/services/blocked_users.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

class _FailedBlockedWrite extends InMemorySharedPreferencesStore {
  _FailedBlockedWrite(this.refuse) : super.empty();
  final bool refuse;
  bool fail = true;
  @override
  Future<bool> setValue(String type, String key, Object value) async {
    if (fail) return !refuse;
    return super.setValue(type, key, value);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    SharedPreferences.setMockInitialValues(
        {'blocked_authors_v1': '{"old":"Starszy","keep":"Zostaje"}'});
    BlockedUsers.instance.resetForTest();
  });
  for (final raw in ['{broken', '["old"]', '{"old":"Starszy","bad":42}']) {
    test('blokowanie nie nadpisuje nieczytelnej listy: $raw', () async {
      SharedPreferences.setMockInitialValues({'blocked_authors_v1': raw});
      final store = BlockedUsers.instance;
      await store.block('new', 'Nowy');
      expect(store.isBlocked('new'), isTrue);
      final prefs = await SharedPreferences.getInstance();
      await prefs.reload();
      expect(prefs.getString('blocked_authors_v1'), raw);
    });
  }

  for (final refuse in [true, false]) {
    test('blokada wykrywa nietrwały zapis i można ją ponowić: $refuse',
        () async {
      final disk = _FailedBlockedWrite(refuse);
      SharedPreferencesStorePlatform.instance = disk;
      final store = BlockedUsers.instance;
      expect(await store.block('new', 'Nowy'), isFalse);
      expect(store.isBlocked('new'), isTrue);
      disk.fail = false;
      expect(await store.block('new', 'Nowy'), isTrue);
      await (await SharedPreferences.getInstance()).reload();
      store.resetForTest();
      await store.load();
      expect(store.isBlocked('new'), isTrue);
      disk.fail = true;
      expect(await store.unblock('new'), isFalse);
      expect(store.isBlocked('new'), isFalse);
      disk.fail = false;
      expect(await store.unblock('new'), isTrue);
      await (await SharedPreferences.getInstance()).reload();
      store.resetForTest();
      await store.load();
      expect(store.isBlocked('new'), isFalse);
    });
  }

  test('clear usuwa uszkodzoną listę i przywraca trwałe blokowanie', () async {
    SharedPreferences.setMockInitialValues({'blocked_authors_v1': '{broken'});
    final store = BlockedUsers.instance;
    await store.block('old', 'Stary');
    expect(await store.clear(), isTrue);
    expect(await store.block('new', 'Nowy'), isTrue);
    await (await SharedPreferences.getInstance()).reload();
    store.resetForTest();
    await store.load();
    expect(store.isBlocked('old'), isFalse);
    expect(store.isBlocked('new'), isTrue);
  });

  test('nowa blokada bez load zachowuje poprzednich autorów', () async {
    final store = BlockedUsers.instance;
    await store.block('new', 'Nowy');
    await (await SharedPreferences.getInstance()).reload();
    store.resetForTest();
    await store.load();
    expect(store.all.map((user) => user.deviceId),
        containsAll(['old', 'keep', 'new']));
  });
  test('odblokowanie bez load usuwa tylko wskazanego autora', () async {
    final store = BlockedUsers.instance;
    await store.unblock('old');
    await (await SharedPreferences.getInstance()).reload();
    store.resetForTest();
    await store.load();
    expect(store.isBlocked('old'), isFalse);
    expect(store.isBlocked('keep'), isTrue);
  });
}
