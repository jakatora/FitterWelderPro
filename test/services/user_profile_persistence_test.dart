import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';
import 'package:cut_list_app/services/user_profile.dart';

class FailedDisk extends InMemorySharedPreferencesStore {
  FailedDisk(this.refuse) : super.empty();
  final bool refuse;
  bool fail = false;
  @override
  Future<bool> setValue(String type, String key, Object value) async {
    if (fail && key == 'flutter.user_profile_v1') return !refuse;
    return super.setValue(type, key, value);
  }

  @override
  Future<bool> remove(String key) async {
    if (fail && key == 'flutter.user_profile_v1') return !refuse;
    return super.remove(key);
  }
}

class DelayedDisk extends InMemorySharedPreferencesStore {
  DelayedDisk() : super.empty();
  final entered = Completer<void>(), release = Completer<void>();
  @override
  Future<bool> setValue(String type, String key, Object value) async {
    if (!entered.isCompleted && key == 'flutter.user_profile_v1') {
      entered.complete();
      await release.future;
    }
    return super.setValue(type, key, value);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final service = UserProfileService.instance;
  const old = UserProfile(firstName: 'Jan', lastName: 'Kowalski');
  const next = UserProfile(firstName: 'Anna', lastName: 'Nowak');
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    service.resetForTest();
  });
  test('usunięcie nie przegrywa z opóźnionym zapisem profilu', () async {
    final disk = DelayedDisk();
    SharedPreferencesStorePlatform.instance = disk;
    final saving = service.save(old);
    await disk.entered.future;
    final clearing = service.clear();
    await Future<void>.delayed(Duration.zero);
    disk.release.complete();
    await saving;
    expect(await clearing, isTrue);
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    expect(prefs.getString('user_profile_v1'), isNull);
    expect(service.current, isNull);
  });

  test('odczyt czeka na zapis i zwraca nowy profil', () async {
    final disk = DelayedDisk();
    SharedPreferencesStorePlatform.instance = disk;
    final saving = service.save(next);
    await disk.entered.future;
    final reading = service.get();
    disk.release.complete();
    expect(await saving, isTrue);
    expect((await reading)?.fullName, next.fullName);
  });

  for (final refuse in [true, false]) {
    test('usuwanie wykrywa awarię i pozwala ponowić: $refuse', () async {
      final disk = FailedDisk(refuse);
      SharedPreferencesStorePlatform.instance = disk;
      await service.save(old);
      disk.fail = true;
      expect(await service.clear(), isFalse);
      expect(service.current, isNull);
      final prefs = await SharedPreferences.getInstance();
      await prefs.reload();
      expect(prefs.getString('user_profile_v1'), isNotNull);
      disk.fail = false;
      expect(await service.clear(), isTrue);
      await prefs.reload();
      expect(prefs.getString('user_profile_v1'), isNull);
    });
    test('zapis wykrywa awarię i pozwala ponowić: $refuse', () async {
      final disk = FailedDisk(refuse);
      SharedPreferencesStorePlatform.instance = disk;
      expect(await service.save(old), isTrue);
      disk.fail = true;
      expect(await service.save(next), isFalse);
      expect(service.current?.fullName, old.fullName);
      disk.fail = false;
      expect(await service.save(next), isTrue);
      await (await SharedPreferences.getInstance()).reload();
      service.resetForTest();
      expect((await service.get())?.fullName, next.fullName);
    });
  }
}
