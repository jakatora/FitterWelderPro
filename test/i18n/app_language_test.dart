// Język interfejsu: zapamiętany wybór, a bez niego język telefonu.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:cut_list_app/i18n/app_language.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    AppLanguageController.current = AppLanguage.pl;
  });

  group('pierwsze uruchomienie (brak zapisanego wyboru)', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    test('polski telefon → PL', () async {
      expect(
        await AppLanguageController.restore(
            deviceLocale: const Locale('pl', 'PL')),
        AppLanguage.pl,
      );
      expect(AppLanguageController.current, AppLanguage.pl);
    });

    test('angielski telefon → EN, i ustawia current przed runApp', () async {
      expect(
        await AppLanguageController.restore(
            deviceLocale: const Locale('en', 'US')),
        AppLanguage.en,
      );
      expect(AppLanguageController.current, AppLanguage.en);
      expect(AppLanguageController.isEnglish, isTrue);
    });

    test('każdy inny język (np. niemiecki, ukraiński) → EN', () async {
      for (final code in ['de', 'uk', 'es']) {
        expect(
          await AppLanguageController.restore(deviceLocale: Locale(code)),
          AppLanguage.en,
          reason: code,
        );
      }
    });

    test('sam język telefonu nie jest zapisywany', () async {
      await AppLanguageController.restore(deviceLocale: const Locale('de'));
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(AppLanguageController.prefsKey), isNull);
    });
  });

  group('zapisany wybór wygrywa z językiem telefonu', () {
    test('EN zapisany, telefon po polsku → EN', () async {
      SharedPreferences.setMockInitialValues(
          {AppLanguageController.prefsKey: 'en'});
      expect(
        await AppLanguageController.restore(deviceLocale: const Locale('pl')),
        AppLanguage.en,
      );
    });

    test('PL zapisany, telefon po angielsku → PL', () async {
      SharedPreferences.setMockInitialValues(
          {AppLanguageController.prefsKey: 'pl'});
      expect(
        await AppLanguageController.restore(deviceLocale: const Locale('en')),
        AppLanguage.pl,
      );
    });

    test('śmieci w zapisie → język telefonu', () async {
      SharedPreferences.setMockInitialValues(
          {AppLanguageController.prefsKey: 'klingon'});
      expect(
        await AppLanguageController.restore(deviceLocale: const Locale('pl')),
        AppLanguage.pl,
      );
    });
  });

  group('zapis wyboru', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    test('kontroler aplikacji zapisuje każdą zmianę', () async {
      final c = AppLanguageController.persistent(AppLanguage.pl);
      addTearDown(c.dispose);
      c.setLanguage(AppLanguage.en);
      await Future<void>.delayed(Duration.zero);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(AppLanguageController.prefsKey), 'en');
      expect(AppLanguageController.current, AppLanguage.en);

      c.toggle();
      await Future<void>.delayed(Duration.zero);
      expect(prefs.getString(AppLanguageController.prefsKey), 'pl');
    });

    test('kontroler testowy (bez zapisu) nie rusza preferencji', () async {
      final c = AppLanguageController(AppLanguage.pl);
      addTearDown(c.dispose);
      c.setLanguage(AppLanguage.en);
      await Future<void>.delayed(Duration.zero);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(AppLanguageController.prefsKey), isNull);
      expect(AppLanguageController.current, AppLanguage.en);
    });

    test('wybór przeżywa restart', () async {
      final c = AppLanguageController.persistent(AppLanguage.pl);
      addTearDown(c.dispose);
      c.setLanguage(AppLanguage.en);
      await Future<void>.delayed(Duration.zero);

      AppLanguageController.current = AppLanguage.pl; // „nowy proces"
      expect(
        await AppLanguageController.restore(deviceLocale: const Locale('pl')),
        AppLanguage.en,
      );
    });
  });
}
