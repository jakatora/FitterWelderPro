// Manifesty prywatności muszą zgadzać się z polityką i z deklaracjami w
// sklepach (docs/store/deklaracje-prywatnosci.md).
//
// iOS: PrivacyInfo.xcprivacy był pusty, a aplikacja zbiera imię i nazwisko
// (czat), treści użytkownika (wiadomości, pytania do asystenta), identyfikator
// instalacji i zdjęcia rysunków (skaner) — i używa API z listy „Required
// Reason" (UserDefaults przez shared_preferences, znaczniki czasu plików przez
// SQLite i dart:io).
//
// Android: bez android:allowBackup domyślny Auto Backup odtwarzał
// SharedPreferences — w tym identyfikator i SEKRET instalacji — na nowym
// telefonie (klon tożsamości na dwa urządzenia), a polityka mówiła, że dane
// „usuwają się razem z odinstalowaniem".

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _read(String path) => File(path).readAsStringSync();

/// Wartości <key>…</key><…> w obrębie jednego słownika typu danych.
List<String> _collectedTypes(String plist) => RegExp(
      r'<key>NSPrivacyCollectedDataType</key>\s*<string>(\w+)</string>',
    ).allMatches(plist).map((m) => m.group(1)!).toList();

String _typeBlock(String plist, String type) {
  final start = plist.indexOf('<string>$type</string>');
  expect(start, isNot(-1), reason: 'brak $type');
  final end = plist.indexOf('</dict>', start);
  return plist.substring(start, end);
}

void main() {
  group('iOS PrivacyInfo.xcprivacy', () {
    final plist = _read('ios/Runner/PrivacyInfo.xcprivacy');

    test('bez śledzenia', () {
      expect(
        RegExp(r'<key>NSPrivacyTracking</key>\s*<false/>').hasMatch(plist),
        isTrue,
      );
    });

    test('zbierane dane jak w deklaracji App Store', () {
      expect(
        _collectedTypes(plist).toSet(),
        {
          'NSPrivacyCollectedDataTypeName',
          'NSPrivacyCollectedDataTypeOtherUserContent',
          'NSPrivacyCollectedDataTypeUserID',
          'NSPrivacyCollectedDataTypePhotosorVideos',
        },
      );
    });

    test('powiązanie z użytkownikiem jak w deklaracji; cel: funkcje aplikacji',
        () {
      for (final linked in [
        'NSPrivacyCollectedDataTypeName',
        'NSPrivacyCollectedDataTypeOtherUserContent',
        'NSPrivacyCollectedDataTypeUserID',
      ]) {
        final block = _typeBlock(plist, linked);
        expect(
            RegExp(r'<key>NSPrivacyCollectedDataTypeLinked</key>\s*<true/>')
                .hasMatch(block),
            isTrue,
            reason: linked);
      }
      final photos =
          _typeBlock(plist, 'NSPrivacyCollectedDataTypePhotosorVideos');
      expect(
          RegExp(r'<key>NSPrivacyCollectedDataTypeLinked</key>\s*<false/>')
              .hasMatch(photos),
          isTrue);
      for (final type in _collectedTypes(plist)) {
        final block = _typeBlock(plist, type);
        expect(
            RegExp(r'<key>NSPrivacyCollectedDataTypeTracking</key>\s*<false/>')
                .hasMatch(block),
            isTrue,
            reason: type);
        expect(block,
            contains('NSPrivacyCollectedDataTypePurposeAppFunctionality'),
            reason: type);
      }
    });

    test('Required Reason API: UserDefaults CA92.1, znaczniki czasu C617.1',
        () {
      final userDefaults = plist.indexOf('NSPrivacyAccessedAPICategoryUserDefaults');
      expect(userDefaults, isNot(-1));
      expect(plist.substring(userDefaults, plist.indexOf('</dict>', userDefaults)),
          contains('CA92.1'));
      final timestamps = plist.indexOf('NSPrivacyAccessedAPICategoryFileTimestamp');
      expect(timestamps, isNot(-1));
      expect(plist.substring(timestamps, plist.indexOf('</dict>', timestamps)),
          contains('C617.1'));
    });

    test('końce linii CRLF zostają (jak w Info.plist)', () {
      final raw = File('ios/Runner/PrivacyInfo.xcprivacy').readAsBytesSync();
      final text = String.fromCharCodes(raw);
      expect(text.contains('\r\n'), isTrue);
      expect(RegExp(r'[^\r]\n').hasMatch(text), isFalse);
    });
  });

  group('Android: kopia zapasowa bez tożsamości instalacji', () {
    final manifest = _read('android/app/src/main/AndroidManifest.xml');

    test('allowBackup jawnie + reguły dla Androida ≤ 11 i 12+', () {
      expect(manifest, contains('android:allowBackup="true"'));
      expect(manifest,
          contains('android:fullBackupContent="@xml/backup_rules"'));
      expect(manifest,
          contains('android:dataExtractionRules="@xml/data_extraction_rules"'));
    });

    test('Android ≤ 11: SharedPreferences poza kopią', () {
      final rules = _read('android/app/src/main/res/xml/backup_rules.xml');
      expect(rules, contains('<full-backup-content>'));
      expect(rules,
          contains('domain="sharedpref" path="FlutterSharedPreferences.xml"'));
    });

    test('Android 12+: SharedPreferences poza kopią w chmurze i przy '
        'przenosinach', () {
      final rules =
          _read('android/app/src/main/res/xml/data_extraction_rules.xml');
      for (final section in ['cloud-backup', 'device-transfer']) {
        final start = rules.indexOf('<$section');
        final end = rules.indexOf('</$section>');
        expect(start, isNot(-1), reason: section);
        expect(
            rules.substring(start, end),
            contains(
                'domain="sharedpref" path="FlutterSharedPreferences.xml"'),
            reason: section);
      }
    });
  });
}
