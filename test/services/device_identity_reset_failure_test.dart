import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';
import 'package:cut_list_app/services/premium_service.dart';

const id = '0123456789abcdef0123456789abcdef';
const secret = 'AbCdEfGhIjKlMnOpQrStUvWxYz0123456789-_AbCdE';

class FailedDisk extends InMemorySharedPreferencesStore {
  FailedDisk(this.refuse, {this.target}) : super.empty();
  final String? target;
  final bool refuse;
  @override
  Future<bool> remove(String key) async {
    if (key.startsWith('flutter.fitter_') &&
        (target == null || key == 'flutter.$target')) {
      return !refuse;
    }
    return super.remove(key);
  }
}

class DelayedRemoval extends InMemorySharedPreferencesStore {
  DelayedRemoval() : super.empty();
  final entered = Completer<void>(), release = Completer<void>();
  @override
  Future<bool> remove(String key) async {
    if (!entered.isCompleted && key == 'flutter.fitter_device_id') {
      entered.complete();
      await release.future;
    }
    return super.remove(key);
  }
}

class DelayedStartup extends DelayedRemoval {
  final readEntered = Completer<void>(), readRelease = Completer<void>();
  @override
  Future<Map<String, Object>> getAll() async {
    if (!readEntered.isCompleted) {
      readEntered.complete();
      await readRelease.future;
    }
    return super.getAll();
  }
}

class DelayedCreation extends DelayedRemoval {
  final writeEntered = Completer<void>(), writeRelease = Completer<void>();
  @override
  Future<bool> setValue(String type, String key, Object value) async {
    if (!writeEntered.isCompleted && key == 'flutter.fitter_device_id') {
      writeEntered.complete();
      await writeRelease.future;
    }
    return super.setValue(type, key, value);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('reset podczas tworzenia pary nie przepuszcza usuwanych nagłówków',
      () async {
    SharedPreferences.setMockInitialValues({});
    final disk = DelayedCreation();
    SharedPreferencesStorePlatform.instance = disk;
    final service = PremiumService.instance;
    service.resetForTest();
    var completed = false;
    final headers = service.authHeaders().then((value) {
      completed = true;
      return value;
    });
    await disk.writeEntered.future;
    final oldId = service.deviceId;
    final resetting = service.resetIdentity();
    disk.writeRelease.complete();
    await disk.entered.future;
    await Future<void>.delayed(Duration.zero);
    final completedDuringReset = completed;
    disk.release.complete();
    expect(await resetting, isTrue);
    final result = await headers;
    expect(completedDuringReset, isFalse);
    expect(result.values, isNot(contains(oldId)));
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    expect(prefs.getString('fitter_device_id'), service.deviceId);
    expect(prefs.getString('fitter_install_secret'), service.installSecret);
  });

  test('reset rozpoczęty podczas init też blokuje stare nagłówki', () async {
    SharedPreferences.setMockInitialValues({});
    final disk = DelayedStartup();
    await disk.setValue('String', 'flutter.fitter_device_id', id);
    await disk.setValue('String', 'flutter.fitter_install_secret', secret);
    SharedPreferencesStorePlatform.instance = disk;
    final service = PremiumService.instance;
    service.resetForTest();
    var completed = false;
    final headers = service.authHeaders().then((value) {
      completed = true;
      return value;
    });
    await disk.readEntered.future;
    final resetting = service.resetIdentity();
    disk.readRelease.complete();
    await disk.entered.future;
    await Future<void>.delayed(Duration.zero);
    final completedDuringReset = completed;
    disk.release.complete();
    expect(await resetting, isTrue);
    final result = await headers;
    expect(completedDuringReset, isFalse);
    expect(result.values, isNot(contains(id)));
    expect(result.values, isNot(contains(secret)));
  });

  test('nagłówki czekają na reset zamiast wysyłać starą parę', () async {
    SharedPreferences.setMockInitialValues({});
    final disk = DelayedRemoval();
    await disk.setValue('String', 'flutter.fitter_device_id', id);
    await disk.setValue('String', 'flutter.fitter_install_secret', secret);
    SharedPreferencesStorePlatform.instance = disk;
    final service = PremiumService.instance;
    service.resetForTest();
    await service.init();
    final resetting = service.resetIdentity();
    await disk.entered.future;
    final alsoResetting = service.resetIdentity();
    expect(identical(alsoResetting, resetting), isTrue);
    var completed = false;
    final headers = service.authHeaders().then((value) {
      completed = true;
      return value;
    });
    await Future<void>.delayed(Duration.zero);
    final completedDuringReset = completed;
    disk.release.complete();
    expect(await resetting, isTrue);
    final result = await headers;
    expect(completedDuringReset, isFalse);
    expect(result.values, isNot(contains(id)));
    expect(result.values, isNot(contains(secret)));
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    expect(prefs.getString('fitter_device_id'), service.deviceId);
    expect(prefs.getString('fitter_install_secret'), service.installSecret);
  });

  for (final target in ['fitter_install_secret', 'fitter_author_id']) {
    test('częściowe usunięcie przywraca starą parę: $target', () async {
      SharedPreferences.setMockInitialValues({});
      final disk = FailedDisk(false, target: target);
      for (final entry in {
        'fitter_device_id': id,
        'fitter_install_secret': secret,
        'fitter_author_id': 'a_test'
      }.entries) {
        await disk.setValue('String', 'flutter.${entry.key}', entry.value);
      }
      SharedPreferencesStorePlatform.instance = disk;
      final service = PremiumService.instance;
      service.resetForTest();
      expect(await service.resetIdentity(), isFalse);
      service.resetForTest();
      await service.init();
      expect(service.deviceId, id);
      expect(service.installSecret, secret);
      expect(service.authorId, 'a_test');
    });
  }
  for (final refuse in [true, false]) {
    test('reset nie gubi pamięci przy nieusuniętej parze: $refuse', () async {
      SharedPreferences.setMockInitialValues({});
      final disk = FailedDisk(refuse);
      await disk.setValue('String', 'flutter.fitter_device_id', id);
      await disk.setValue('String', 'flutter.fitter_install_secret', secret);
      SharedPreferencesStorePlatform.instance = disk;
      final service = PremiumService.instance;
      service.resetForTest();
      await service.init();
      expect(await service.resetIdentity(), isFalse);
      expect(service.installSecret, secret);
      expect(service.deviceId, id);
      final prefs = await SharedPreferences.getInstance();
      await prefs.reload();
      expect(prefs.getString('fitter_device_id'), id);
      expect(prefs.getString('fitter_install_secret'), secret);
    });
  }
}
