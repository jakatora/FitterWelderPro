// Ekran główny: start bez bramki, wyszukiwarka, ostatnio używane, przypięte,
// powitanie imieniem, przełącznik języka i bramka dopiero przed czatem.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:cut_list_app/app.dart';
import 'package:cut_list_app/i18n/app_language.dart';
import 'package:cut_list_app/screens/chat_screen.dart';
import 'package:cut_list_app/screens/consent_screen.dart';
import 'package:cut_list_app/screens/elbow_takeout_screen.dart';
import 'package:cut_list_app/screens/fitter_menu_screen.dart';
import 'package:cut_list_app/screens/help_screen.dart';
import 'package:cut_list_app/screens/home_screen.dart';
import 'package:cut_list_app/screens/onboarding_name_screen.dart';
import 'package:cut_list_app/services/legal_consent.dart';
import 'package:cut_list_app/services/tool_usage.dart';
import 'package:cut_list_app/services/user_profile.dart';

import '../support/test_database.dart';
import '../test_prefs.dart';

void main() {
  useTestDatabase();

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 8; i++) {
      await flushTestDatabase(tester);
      await tester.pump(const Duration(milliseconds: 120));
    }
  }

  Future<void> boot(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1100, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const CutListApp());
    await settle(tester);
  }

  Finder key(String k) => find.byKey(ValueKey(k));

  /// Systemowe „wstecz" — jak przycisk Androida albo gest iOS.
  Future<void> back(WidgetTester tester) async {
    tester.state<NavigatorState>(find.byType(Navigator).first).pop();
    await settle(tester);
  }

  group('start bez bramki', () {
    testWidgets('świeża instalacja: ekran główny od razu, powitanie ogólne',
        (tester) async {
      seedFreshInstall();
      await boot(tester);

      expect(find.byType(HomeScreen), findsOneWidget);
      expect(find.byType(OnboardingNameScreen), findsNothing);
      expect(find.text('Witaj'), findsOneWidget);
      expect(find.textContaining('Spawaczu'), findsNothing);
    });

    testWidgets('powitanie imieniem z profilu', (tester) async {
      seedOnboardedUser(firstName: 'Zbyszek', lastName: 'Hałas');
      await boot(tester);
      expect(find.text('Cześć, Zbyszek'), findsOneWidget);
      expect(find.textContaining('Spawaczu'), findsNothing);
    });

    testWidgets('dawny baner zniknął: bez znaczka „Aktywny" i kafla POMOC',
        (tester) async {
      seedOnboardedUser();
      await boot(tester);
      expect(find.text('Aktywny'), findsNothing);
      expect(find.text('POMOC'), findsNothing);
      // Jedna pomoc: „?" w pasku otwiera bazę wiedzy.
      await tester.tap(find.byTooltip('Pomoc'));
      await settle(tester);
      expect(find.byType(HelpScreen), findsOneWidget);
    });

    testWidgets(
        'podniesione kLegalVersion blokuje tylko czat — narzędzia działają',
        (tester) async {
      seedOutdatedConsent();
      await boot(tester);

      await tester.tap(find.byIcon(Icons.handyman_outlined)); // MONTER
      await settle(tester);
      expect(find.byType(FitterMenuScreen), findsOneWidget);
      await back(tester);

      await tester.tap(find.byIcon(Icons.forum_outlined)); // CZAT
      await settle(tester);
      expect(find.byType(ConsentScreen), findsOneWidget);
      expect(find.textContaining('Zmieniliśmy zasady'), findsOneWidget);
      expect(find.byType(ChatScreen), findsNothing);
    });

    testWidgets('cofnięcie się z kroku imienia nie otwiera czatu',
        (tester) async {
      seedFreshInstall();
      await boot(tester);

      await tester.tap(find.byIcon(Icons.forum_outlined)); // CZAT
      await settle(tester);
      expect(find.byType(OnboardingNameScreen), findsOneWidget);

      await back(tester);

      expect(find.byType(HomeScreen), findsOneWidget);
      expect(find.byType(ChatScreen), findsNothing);
      expect(UserProfileService.instance.current, isNull);
      expect(LegalConsent.instance.isAccepted, isFalse);
    });

    testWidgets('świeża instalacja: czat wymaga imienia, nazwiska i zasad',
        (tester) async {
      seedFreshInstall();
      await boot(tester);

      await tester.tap(find.byIcon(Icons.forum_outlined));
      await settle(tester);

      final fields = find.byType(TextField);
      expect(fields, findsNWidgets(2));
      await tester.enterText(fields.at(0), 'Anna-Maria');
      await tester.enterText(fields.at(1), "O'Brien");
      await settle(tester);
      // Bez zgody dalej nie przejdzie.
      expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
          isNull);
      // Zgoda stuknięciem w TEKST, nie w pole wyboru.
      final consentText = find.textContaining('Mam ukończone');
      await tester.tapAt(tester.getTopLeft(consentText) + const Offset(12, 8));
      await settle(tester);
      await tester.tap(find.byType(FilledButton));
      await settle(tester);

      expect(find.byType(ChatScreen), findsOneWidget);
      expect(UserProfileService.instance.current?.fullName,
          "Anna-Maria O'Brien");
      expect(LegalConsent.instance.isAccepted, isTrue);

      // Domknij żądania czatu (atrapa HTTP odpowiada 400, limit czasu 8 s).
      await tester.pump(const Duration(seconds: 10));
      await tester.pumpWidget(const SizedBox());
    });
  });

  group('szybki dostęp', () {
    testWidgets(
        'szukaj „kolan": wynik otwiera narzędzie, które wraca w ostatnio '
        'używanych', (tester) async {
      seedOnboardedUser();
      await boot(tester);
      expect(find.text('OSTATNIO UŻYWANE'), findsNothing);

      await tester.enterText(key('home-tool-search'), 'kolan');
      await settle(tester);
      expect(key('tool-row-elbow_takeouts'), findsOneWidget);
      // Wyniki zastępują resztę ekranu (kafle działów znikają).
      expect(find.byIcon(Icons.handyman_outlined), findsNothing);

      await tester.tap(key('tool-row-elbow_takeouts'));
      await settle(tester);
      expect(find.byType(ElbowTakeoutScreen), findsOneWidget);

      await back(tester);
      await tester.tap(find.byTooltip('Wyczyść'));
      await settle(tester);

      expect(find.text('OSTATNIO UŻYWANE'), findsOneWidget);
      expect(key('recent-elbow_takeouts'), findsOneWidget);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getStringList(ToolUsageStore.recentKey), ['elbow_takeouts']);
    });

    testWidgets('brak wyniku mówi, co zrobić, i prowadzi do pomocy',
        (tester) async {
      seedOnboardedUser();
      await boot(tester);
      await tester.enterText(key('home-tool-search'), 'xyzqq');
      await settle(tester);
      expect(find.textContaining('Brak narzędzia'), findsOneWidget);
      await tester.tap(find.text('Szukaj w pomocy'));
      await settle(tester);
      expect(find.byType(HelpScreen), findsOneWidget);
    });

    testWidgets('ostatnio używane: najwyżej 4, najnowsze pierwsze',
        (tester) async {
      seedOnboardedUser(extra: {
        ToolUsageStore.recentKey: [
          'dn_mm',
          'pipe_slope',
          'heat_input',
          'unit_converter',
          'bolt_torque',
          'nie-ma-takiego',
        ],
      });
      await boot(tester);
      expect(key('recent-dn_mm'), findsOneWidget);
      expect(key('recent-unit_converter'), findsOneWidget);
      expect(key('recent-bolt_torque'), findsNothing); // piąty
      expect(
        tester.getTopLeft(key('recent-dn_mm')).dy,
        lessThanOrEqualTo(tester.getTopLeft(key('recent-heat_input')).dy),
      );
    });

    testWidgets('długie przytrzymanie przypina i odpina', (tester) async {
      seedOnboardedUser(extra: {
        ToolUsageStore.recentKey: ['dn_mm', 'pipe_slope'],
      });
      await boot(tester);
      expect(find.text('PRZYPIĘTE'), findsNothing);

      await tester.longPress(key('recent-dn_mm'));
      await settle(tester);
      expect(find.text('PRZYPIĘTE'), findsOneWidget);
      expect(key('pinned-dn_mm'), findsOneWidget);
      // Przypięte nie dublują się w ostatnio używanych.
      expect(key('recent-dn_mm'), findsNothing);
      expect(find.textContaining('Przypięto'), findsOneWidget);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getStringList(ToolUsageStore.favoritesKey), ['dn_mm']);

      await tester.longPress(key('pinned-dn_mm'));
      await settle(tester);
      expect(find.text('PRZYPIĘTE'), findsNothing);
      expect(prefs.getStringList(ToolUsageStore.favoritesKey), isEmpty);
    });

    testWidgets('przypięte w menu montera pojawia się na ekranie głównym',
        (tester) async {
      seedOnboardedUser();
      await boot(tester);

      await tester.tap(find.byIcon(Icons.handyman_outlined));
      await settle(tester);
      await tester.longPress(key('tool-row-rolling_offset'));
      await settle(tester);
      expect(find.byIcon(Icons.push_pin), findsOneWidget);

      await back(tester);
      expect(key('pinned-rolling_offset'), findsOneWidget);
    });
  });

  group('język', () {
    testWidgets('przełącznik ma min. 48 dp i zapamiętuje wybór po restarcie',
        (tester) async {
      seedOnboardedUser();
      await boot(tester);

      final size = tester.getSize(key('home-language'));
      expect(size.height, greaterThanOrEqualTo(48));
      expect(size.width, greaterThanOrEqualTo(48));

      await tester.tap(key('home-language'));
      await settle(tester);
      await tester.tap(find.text('English').last);
      await settle(tester);

      expect(find.text('FITTER'), findsOneWidget);
      expect(find.text('WELDER'), findsOneWidget);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(AppLanguageController.prefsKey), 'en');

      // Restart aplikacji na polskim telefonie: zapisany wybór wygrywa.
      await tester.pumpWidget(const SizedBox());
      AppLanguageController.current = AppLanguage.pl;
      await tester.runAsync(() => AppLanguageController.restore(
          deviceLocale: const Locale('pl', 'PL')));
      expect(AppLanguageController.current, AppLanguage.en);
      await tester.pumpWidget(const CutListApp());
      await settle(tester);
      expect(find.text('Hi, Marek'), findsOneWidget);
    });
  });
}
