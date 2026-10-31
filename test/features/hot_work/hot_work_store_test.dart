import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';
import 'package:cut_list_app/domain/hot_work/hot_work_permit.dart';
import 'package:cut_list_app/features/hot_work/hot_work_store.dart';

class _Disk extends InMemorySharedPreferencesStore {
  _Disk() : super.empty();
  String? pretendKey;
  @override
  Future<bool> setValue(String type, String key, Object value) async {
    if (pretendKey == null || pretendKey == key) return true;
    return super.setValue(type, key, value);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final record = HotWorkPermit.blank(id: 'new', now: DateTime(2026, 10, 31))
      .copyWith(location: 'Zbiornik');

  test('pozorny sukces zapisu protokołu nie emituje zmiany historii', () async {
    SharedPreferences.setMockInitialValues({});
    SharedPreferencesStorePlatform.instance = _Disk();
    final before = HotWorkStore.changes.value;
    await expectLater(const HotWorkStore().upsert(record), throwsStateError);
    expect(HotWorkStore.changes.value, before);
  });

  test('nieutrwalona kopia blokuje nadpisanie uszkodzonej historii', () async {
    SharedPreferences.setMockInitialValues({});
    final disk = _Disk()
      ..pretendKey = 'flutter.${HotWorkStore.corruptBackupKey}';
    SharedPreferencesStorePlatform.instance = disk;
    const damaged = '{broken hot work';
    await disk.setValue('String', 'flutter.${HotWorkStore.key}', damaged);
    await expectLater(const HotWorkStore().upsert(record), throwsStateError);
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    expect(prefs.get(HotWorkStore.key), damaged);
  });
}
