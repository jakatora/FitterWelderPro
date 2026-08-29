// Zasady, zgoda i filtr treści — trzy rzeczy, których Apple wymaga przy
// treściach tworzonych przez użytkowników (wytyczna 1.2).

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:cut_list_app/i18n/app_language.dart';
import 'package:cut_list_app/legal/legal_texts.dart';
import 'package:cut_list_app/screens/profile_screen.dart';
import 'package:cut_list_app/services/blocked_users.dart';
import 'package:cut_list_app/services/content_filter.dart';
import 'package:cut_list_app/services/legal_consent.dart';
import 'package:cut_list_app/services/user_profile.dart';
import 'package:cut_list_app/services/welder_identity.dart';

void main() {
  group('filtr treści', () {
    test('przepuszcza normalną rozmowę montera', () {
      const ok = [
        'Kto robił P91 25 mm? Jaki preheat trzymacie?',
        'Weź szmatę i przetrzyj rowek przed spawaniem.',
        'Ciężka robota, ale kolano wyszło idealnie.',
        'DN100, ścianka 6 mm, takeout 45° to 64 mm.',
        'Chełm, Kraków, Gdańsk — wszędzie ta sama stal.',
      ];
      for (final t in ok) {
        expect(ContentFilter.isObjectionable(t), isFalse, reason: 'zablokowano: "$t"');
      }
    });

    test('zatrzymuje wyzwiska', () {
      const bad = ['ty debilu', 'kurwa mać', 'chujowa robota', 'fuck this'];
      for (final t in bad) {
        expect(ContentFilter.isObjectionable(t), isTrue, reason: 'przepuszczono: "$t"');
      }
    });

    test('radzi sobie z polskimi znakami i leetspeakiem', () {
      expect(ContentFilter.isObjectionable('pedał'), isTrue);
      expect(ContentFilter.isObjectionable('ch0j'), isFalse); // 0->o daje "choj"
      expect(ContentFilter.isObjectionable('deb1l'), isTrue); // 1->i
      expect(ContentFilter.isObjectionable('f4ck'), isFalse); // 4->a daje "fack"
      expect(ContentFilter.isObjectionable('fu4k'), isFalse);
    });

    test('dopasowuje całe słowa, nie fragmenty', () {
      // „ciotka" nie zawiera zabronionego „ciota".
      expect(ContentFilter.isObjectionable('moja ciotka spawa lepiej'), isFalse);
    });

    test('zwraca dopasowany rdzeń do logu moderacji', () {
      expect(ContentFilter.firstOffense('to jest chujowe'), 'chuj');
      expect(ContentFilter.firstOffense('wszystko gra'), isNull);
    });
  });

  group('zgoda na zasady', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
      LegalConsent.instance.resetForTest();
    });

    test('świeża instalacja nie ma zgody', () async {
      await LegalConsent.instance.load();
      expect(LegalConsent.instance.isAccepted, isFalse);
    });

    test('akceptacja jest trwała', () async {
      await LegalConsent.instance.load();
      await LegalConsent.instance.accept();
      expect(LegalConsent.instance.isAccepted, isTrue);

      LegalConsent.instance.resetForTest();
      await LegalConsent.instance.load();
      expect(LegalConsent.instance.isAccepted, isTrue);
      expect(LegalConsent.instance.acceptedAt, isNotNull);
    });

    test('zgoda na STARSZĄ wersję zasad nie wystarcza', () async {
      // Ktoś zaakceptował dokument, którego już nie ma. Musi zobaczyć nowy.
      SharedPreferences.setMockInitialValues({
        'legal_consent_v1': jsonEncode({
          'version': kLegalVersion - 1,
          'acceptedAt': '2026-01-01T00:00:00.000',
        }),
      });
      LegalConsent.instance.resetForTest();
      await LegalConsent.instance.load();

      expect(LegalConsent.instance.isAccepted, isFalse);
    });

    test('usunięcie danych kasuje zgodę', () async {
      await LegalConsent.instance.load();
      await LegalConsent.instance.accept();
      await LegalConsent.instance.clear();
      expect(LegalConsent.instance.isAccepted, isFalse);
    });
  });

  group('dokumenty', () {
    test('wersja i data są ustawione', () {
      expect(kLegalVersion, greaterThanOrEqualTo(1));
      expect(kLegalUpdated, isNotEmpty);
      expect(kMinimumAge, greaterThanOrEqualTo(13));
    });
  });

  // „Usuń moje dane" kasowało profil, zgodę i listę zablokowanych — ale NIE
  // tożsamość spawacza. Po „usunięciu" na telefonie zostawał stempel, numer
  // WPQR i e-mail, a weld_journal_screen dalej pre-wypełniał nimi pole
  // „spawacz": nowe spoiny podpisywały się człowiekiem, który właśnie kazał
  // się usunąć. To dane osobowe i deklaracja RODO, więc test idzie przez
  // prawdziwy ekran, a nie przez sam serwis — luka była w tym, że ekran
  // istniejącej metody clear() po prostu nie wołał.
  group('usunięcie danych', () {
    // UWAGA dla przyszłych testów w tym pliku: WelderIdentityService jest
    // singletonem BEZ resetForTest — po pierwszej hydratacji `_hydrated`
    // zostaje na true i clear() tego nie cofa. Dlatego tylko JEDEN test w
    // tym pliku może polegać na odczytaniu tożsamości z zasianych
    // preferencji.
    testWidgets('zabiera też stempel spawacza, nie tylko profil',
        (tester) async {
      // Wysoka powierzchnia: cały profil + dialog mieszczą się bez
      // przewijania, więc test nie mierzy layoutu, tylko zachowanie.
      tester.view.physicalSize = const Size(1100, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      SharedPreferences.setMockInitialValues({
        'user_profile_v1':
            jsonEncode({'firstName': 'Marek', 'lastName': 'Kowalczyk'}),
        'legal_consent_v1': jsonEncode({
          'version': kLegalVersion,
          'acceptedAt': '2026-07-09T12:00:00.000',
        }),
        'welder_identity_v1': jsonEncode({
          'stamp': 'JK-014',
          'wpqrNo': 'WPS-2026-014',
          'certBody': 'udt',
          'displayName': 'Jan Kowalski',
          'email': 'jan@example.pl',
          'gdprConsentAt': '2026-06-09T14:32:00.000',
          'qualificationDeclaredAt': '2026-06-09T14:33:00.000',
        }),
      });
      UserProfileService.instance.resetForTest();
      LegalConsent.instance.resetForTest();
      BlockedUsers.instance.resetForTest();

      // Asercja kontrolna: bez niej test przeszedłby również wtedy, gdyby
      // ziarno było złe i stempla nie było tam od początku.
      expect(
        await WelderIdentityService.instance.get(),
        isNotNull,
        reason: 'ziarno preferencji nie wczytało tożsamości — dalsze '
            'asercje byłyby puste',
      );

      await tester.pumpWidget(AppLanguageScope(
        controller: AppLanguageController(AppLanguage.en),
        child: const MaterialApp(home: ProfileScreen()),
      ));
      // Drobne pompy zamiast pumpAndSettle: ekran startuje ze spinnerem na
      // czas ładowania profilu i listy zablokowanych.
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 120));
      }

      await tester.tap(find.text('Delete my data'));
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 120));
      }

      // Dialog musi wprost powiedzieć, co znika. Kasowanie stempla bez
      // uprzedzenia to niespodzianka, a nie zgoda.
      expect(
        find.textContaining('welder identity'),
        findsOneWidget,
        reason: 'okno potwierdzenia nie wymienia tożsamości spawacza',
      );

      await tester.tap(find.text('Delete'));
      for (var i = 0; i < 12; i++) {
        await tester.pump(const Duration(milliseconds: 120));
      }

      expect(
        WelderIdentityService.instance.current,
        isNull,
        reason: 'po „usuń moje dane" w pamięci został stempel spawacza',
      );
      final prefs = await SharedPreferences.getInstance();
      expect(
        prefs.getString('welder_identity_v1'),
        isNull,
        reason: 'stempel, nr WPQR i e-mail zostały na dysku',
      );
      // Kontrola, że nie zepsuliśmy tego, co ekran kasował już wcześniej.
      expect(prefs.getString('user_profile_v1'), isNull);
    });
  });
}
