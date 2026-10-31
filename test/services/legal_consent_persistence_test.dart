import 'dart:async';
import 'dart:convert';
import 'package:cut_list_app/legal/legal_texts.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';
import 'package:cut_list_app/services/legal_consent.dart';

class FailedDisk extends InMemorySharedPreferencesStore {
  FailedDisk(this.refuse) : super.empty();
  final bool refuse;
  bool fail = false;
  @override
  Future<bool> setValue(String type, String key, Object value) async {
    if (fail && key == 'flutter.legal_consent_v1') return !refuse;
    return super.setValue(type, key, value);
  }

  @override
  Future<bool> remove(String key) async {
    if (fail && key == 'flutter.legal_consent_v1') return !refuse;
    return super.remove(key);
  }
}

class DelayedDisk extends InMemorySharedPreferencesStore {
  DelayedDisk() : super.empty();
  final entered = Completer<void>(), release = Completer<void>();
  @override
  Future<bool> setValue(String type, String key, Object value) async {
    if (!entered.isCompleted && key == 'flutter.legal_consent_v1') {
      entered.complete();
      await release.future;
    }
    return super.setValue(type, key, value);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final consent = LegalConsent.instance;
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    consent.resetForTest();
  });
  test('wycofanie nie przegrywa z opóźnionym zapisem', () async {
    final disk = DelayedDisk();
    SharedPreferencesStorePlatform.instance = disk;
    final accepting = consent.accept();
    await disk.entered.future;
    final clearing = consent.clear();
    expect(consent.isAccepted, isFalse);
    await Future<void>.delayed(Duration.zero);
    disk.release.complete();
    await accepting;
    expect(await clearing, isTrue);
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    expect(prefs.getString('legal_consent_v1'), isNull);
    consent.resetForTest();
    await consent.load();
    expect(consent.isAccepted, isFalse);
  });

  test('nowe potwierdzenie po wycofaniu pozostaje zapisane', () async {
    await consent.accept();
    final clearing = consent.clear();
    final accepting = consent.accept();
    expect(await clearing, isTrue);
    expect(await accepting, isTrue);
    expect(consent.withdrawalPending, isFalse);
    await (await SharedPreferences.getInstance()).reload();
    consent.resetForTest();
    await consent.load();
    expect(consent.isAccepted, isTrue);
  });

  for (final record in [
    {'version': kLegalVersion},
    {'version': kLegalVersion, 'acceptedAt': 'invalid'},
    {'version': kLegalVersion + 0.5, 'acceptedAt': '2026-10-31T08:00:00.000'},
  ]) {
    test('uszkodzony zapis nie potwierdza zgody: $record', () async {
      SharedPreferences.setMockInitialValues(
          {'legal_consent_v1': jsonEncode(record)});
      await consent.load();
      expect(consent.isAccepted, isFalse);
      expect(consent.acceptedAt, isNull);
    });
  }

  for (final refuse in [true, false]) {
    test('clear wykrywa brak usunięcia: $refuse', () async {
      final disk = FailedDisk(refuse);
      SharedPreferencesStorePlatform.instance = disk;
      await consent.accept();
      disk.fail = true;
      expect(await consent.clear(), isFalse);
      expect(consent.isAccepted, isFalse);
      expect(consent.withdrawalPending, isTrue);
      final prefs = await SharedPreferences.getInstance();
      await prefs.reload();
      expect(prefs.getString('legal_consent_v1'), isNotNull);
      disk.fail = false;
      expect(await consent.clear(), isTrue);
      expect(consent.withdrawalPending, isFalse);
    });
    test('accept wykrywa brak zapisu: $refuse', () async {
      final disk = FailedDisk(refuse)..fail = true;
      SharedPreferencesStorePlatform.instance = disk;
      expect(await consent.accept(), isFalse);
      expect(consent.isAccepted, isTrue); // explicit consent for this session
      disk.fail = false;
      expect(await consent.accept(), isTrue);
      await (await SharedPreferences.getInstance()).reload();
      consent.resetForTest();
      await consent.load();
      expect(consent.isAccepted, isTrue);
    });
  }
}
