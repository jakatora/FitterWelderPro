import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';
import 'package:cut_list_app/domain/confined_space/confined_space_record.dart';
import 'package:cut_list_app/features/confined_space/confined_space_store.dart';

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
  final record =
      ConfinedSpaceRecord.blank(id: 'new', now: DateTime(2026, 10, 31))
          .copyWith(location: 'Zbiornik');

  test('pozorny sukces zapisu protokołu nie emituje zmiany historii', () async {
    SharedPreferences.setMockInitialValues({});
    SharedPreferencesStorePlatform.instance = _Disk();
    final before = ConfinedSpaceStore.changes.value;
    await expectLater(
        const ConfinedSpaceStore().upsert(record), throwsStateError);
    expect(ConfinedSpaceStore.changes.value, before);
  });

  test('nieutrwalona kopia blokuje nadpisanie uszkodzonej historii', () async {
    SharedPreferences.setMockInitialValues({});
    final disk = _Disk()
      ..pretendKey = 'flutter.${ConfinedSpaceStore.corruptBackupKey}';
    SharedPreferencesStorePlatform.instance = disk;
    const damaged = '{broken confined space';
    await disk.setValue('String', 'flutter.${ConfinedSpaceStore.key}', damaged);
    await expectLater(
        const ConfinedSpaceStore().upsert(record), throwsStateError);
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    expect(prefs.get(ConfinedSpaceStore.key), damaged);
  });
}
