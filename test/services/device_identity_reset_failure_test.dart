import 'dart:async';
import 'dart:convert';
import 'package:cut_list_app/services/chat_service.dart';
import 'package:cut_list_app/services/legal_consent.dart';
import 'package:cut_list_app/services/user_profile.dart';
import 'package:cut_list_app/legal/legal_texts.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:cut_list_app/services/api_client.dart';
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

class DelayedAuthor extends InMemorySharedPreferencesStore {
  DelayedAuthor() : super.empty();
  final entered = Completer<void>(), release = Completer<void>();
  @override
  Future<bool> setValue(String type, String key, Object value) async {
    if (!entered.isCompleted && key == 'flutter.fitter_author_id') {
      entered.complete();
      await release.future;
    }
    return super.setValue(type, key, value);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  tearDown(() => ApiClient.instance.debugSetClient(null));
  for (final clearProfile in [false, true]) {
    test(
        'wycofanie dostępu podczas tworzenia pary blokuje HTTP: profil=$clearProfile',
        () async {
      SharedPreferences.setMockInitialValues({});
      final disk = DelayedCreation();
      await disk.setValue('String', 'flutter.user_profile_v1',
          jsonEncode({'firstName': 'Jan', 'lastName': 'Nowak'}));
      await disk.setValue(
          'String',
          'flutter.legal_consent_v1',
          jsonEncode({
            'version': kLegalVersion,
            'acceptedAt': '2026-10-31T08:00:00.000'
          }));
      SharedPreferencesStorePlatform.instance = disk;
      PremiumService.instance.resetForTest();
      UserProfileService.instance.resetForTest();
      LegalConsent.instance.resetForTest();
      final requests = <http.Request>[];
      ApiClient.instance.debugSetClient(MockClient((request) async {
        requests.add(request);
        return http.Response(
            jsonEncode({'registered': true, 'author_id': 'a_test'}), 201,
            headers: {'content-type': 'application/json'});
      }));
      final registering = ChatService.instance.registerDeviceIfConsented();
      await disk.writeEntered.future;
      if (clearProfile) {
        await UserProfileService.instance.clear();
      } else {
        await LegalConsent.instance.clear();
      }
      disk.writeRelease.complete();
      final result = await registering;
      expect(requests, isEmpty);
      expect(result, isNull);
      if (clearProfile) {
        await UserProfileService.instance
            .save(const UserProfile(firstName: 'Jan', lastName: 'Nowak'));
      } else {
        await LegalConsent.instance.accept();
      }
      expect(await ChatService.instance.registerDeviceIfConsented(),
          DeviceRegistration.registered);
      expect(requests, hasLength(1));
    });
  }

  test('reset czeka na rozpoczęty zapis autora i usuwa go', () async {
    SharedPreferences.setMockInitialValues({});
    final disk = DelayedAuthor();
    await disk.setValue('String', 'flutter.fitter_device_id', id);
    await disk.setValue('String', 'flutter.fitter_install_secret', secret);
    SharedPreferencesStorePlatform.instance = disk;
    ApiClient.instance.debugSetClient(MockClient((_) async => http.Response(
        jsonEncode({'registered': true, 'author_id': 'a_old'}), 201,
        headers: {'content-type': 'application/json'})));
    final service = PremiumService.instance;
    service.resetForTest();
    final registering = service.registerDevice();
    await disk.entered.future;
    final resetting = service.resetIdentity();
    await Future<void>.delayed(Duration.zero);
    disk.release.complete();
    await registering;
    expect(await resetting, isTrue);
    expect(service.authorId, isNull);
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    expect(prefs.getString('fitter_author_id'), isNull);
  });

  test('spóźniona rejestracja nie odtwarza autora po resecie', () async {
    SharedPreferences.setMockInitialValues(
        {'fitter_device_id': id, 'fitter_install_secret': secret});
    final entered = Completer<void>(), response = Completer<http.Response>();
    ApiClient.instance.debugSetClient(MockClient((request) {
      entered.complete();
      return response.future;
    }));
    final service = PremiumService.instance;
    service.resetForTest();
    final registering = service.registerDevice();
    await entered.future;
    expect(await service.resetIdentity(), isTrue);
    response.complete(http.Response(
        jsonEncode({'registered': true, 'author_id': 'a_old'}), 201,
        headers: {'content-type': 'application/json'}));
    await registering;
    expect(service.authorId, isNull);
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    expect(prefs.getString('fitter_author_id'), isNull);
    expect(prefs.getString('fitter_device_id'), isNull);
  });

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
