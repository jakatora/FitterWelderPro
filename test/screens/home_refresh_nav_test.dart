// Ekran główny i pomoc (przegląd G6):
//   • po powrocie z menu (albo z narzędzia) lista „Ostatnie projekty" i
//     liczniki są świeże — wcześniej projekt założony przez Monter → Lista
//     cięć pojawiał się dopiero po pociągnięciu w dół;
//   • wyszukiwarka znajduje ekrany konta i pomocy (Czat, Profil, Usuń moje
//     dane, Zasady) — wcześniej „czat" i „profil" dawały „Brak narzędzia";
//   • filtry pomocy mają cel dotyku ≥ 48 dp i rolę przełącznika dla czytnika.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cut_list_app/app.dart';
import 'package:cut_list_app/data/help_entries.dart';
import 'package:cut_list_app/database/project_dao.dart';
import 'package:cut_list_app/i18n/app_language.dart';
import 'package:cut_list_app/models/project.dart';
import 'package:cut_list_app/screens/chat_screen.dart';
import 'package:cut_list_app/screens/fitter_menu_screen.dart';
import 'package:cut_list_app/screens/help_screen.dart';
import 'package:cut_list_app/screens/home_screen.dart';
import 'package:cut_list_app/screens/legal_screen.dart';
import 'package:cut_list_app/screens/onboarding_name_screen.dart';
import 'package:cut_list_app/screens/profile_screen.dart';
import 'package:cut_list_app/theme/app_theme.dart';
import 'package:cut_list_app/widgets/tool_registry.dart';

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

  Future<void> back(WidgetTester tester) async {
    tester.state<NavigatorState>(find.byType(Navigator).first).pop();
    await settle(tester);
  }

  Future<void> search(WidgetTester tester, String q) async {
    await tester.enterText(find.byKey(const ValueKey('home-tool-search')), q);
    await tester.pump(const Duration(milliseconds: 120));
  }

  group('odświeżenie po powrocie', () {
    testWidgets('projekt założony „w menu" widać po powrocie na ekran główny',
        (tester) async {
      seedFreshInstall();
      await boot(tester);
      expect(find.text('Projekty: 0  ·  Segmenty: 0'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.handyman_outlined)); // MONTER
      await settle(tester);
      expect(find.byType(FitterMenuScreen), findsOneWidget);

      // Monter → Lista cięć → nowy projekt (zapis prosto do bazy).
      final now = DateTime.now().millisecondsSinceEpoch;
      await tester.runAsync(() => ProjectDao().insert(Project(
            id: 'p-refresh',
            name: 'Linia 12 — odświeżenie',
            materialGroup: 'SS',
            diameterMm: 60.3,
            wallThicknessMm: 2.77,
            currentDiameterMm: 60.3,
            stockLengthMm: 6000,
            sawKerfMm: 2,
            gapMm: 0,
            createdAt: now,
            updatedAt: now,
          )));

      await back(tester);
      expect(find.byType(HomeScreen), findsOneWidget);
      expect(find.text('Linia 12 — odświeżenie'), findsOneWidget,
          reason: 'lista projektów nie odświeżyła się po powrocie z menu');
      expect(find.text('Projekty: 1  ·  Segmenty: 0'), findsOneWidget);
    });
  });

  group('wyszukiwarka: ekrany konta i pomocy', () {
    testWidgets('„czat" → Czat (przez bramkę imienia i zasad)',
        (tester) async {
      seedFreshInstall();
      await boot(tester);
      await search(tester, 'czat');
      final chat = find.byKey(const ValueKey('nav-chat'));
      expect(chat, findsOneWidget);
      expect(find.textContaining('Brak narzędzia'), findsNothing);
      expect(tester.getSize(chat).height, greaterThanOrEqualTo(kMinTapTarget));
      await tester.tap(chat);
      await settle(tester);
      // Świeża instalacja: bramka pyta o imię i zasady, czat się nie otwiera.
      expect(find.byType(OnboardingNameScreen), findsOneWidget);
      expect(find.byType(ChatScreen), findsNothing);
    });

    testWidgets('„profil" → Twój profil', (tester) async {
      seedOnboardedUser();
      await boot(tester);
      await search(tester, 'profil');
      await tester.tap(find.byKey(const ValueKey('nav-profile')));
      await settle(tester);
      expect(find.byType(ProfileScreen), findsOneWidget);
    });

    testWidgets('„usuń dane" → profil z oknem „Usunąć moje dane?"',
        (tester) async {
      seedOnboardedUser();
      await boot(tester);
      await search(tester, 'usuń dane');
      await tester.tap(find.byKey(const ValueKey('nav-delete_data')));
      await settle(tester);
      expect(find.byType(ProfileScreen), findsOneWidget);
      expect(find.text('Usunąć moje dane?'), findsOneWidget);
      // Nic nie znika bez potwierdzenia.
      await tester.tap(find.text('Anuluj'));
      await settle(tester);
      expect(find.byType(ProfileScreen), findsOneWidget);
    });

    testWidgets('„zasady" → Regulamin i Polityka prywatności', (tester) async {
      seedFreshInstall();
      await boot(tester);
      await search(tester, 'zasady');
      expect(find.byKey(const ValueKey('nav-terms')), findsOneWidget);
      expect(find.byKey(const ValueKey('nav-privacy')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('nav-terms')));
      await settle(tester);
      expect(find.byType(LegalScreen), findsOneWidget);
    });

    testWidgets('„pomoc" → Pomoc', (tester) async {
      seedFreshInstall();
      await boot(tester);
      await search(tester, 'pomoc');
      await tester.tap(find.byKey(const ValueKey('nav-help')));
      await settle(tester);
      expect(find.byType(HelpScreen), findsOneWidget);
    });

    test('wpisy nawigacyjne mają unikalne id i oba języki', () {
      final ids = kNavEntries.map((e) => e.id).toList();
      expect(ids.toSet(), hasLength(ids.length));
      for (final e in kNavEntries) {
        expect(e.titlePl, isNotEmpty);
        expect(e.titleEn, isNotEmpty);
        // Nie kolidują z identyfikatorami narzędzi (ostatnio używane).
        expect(kToolRegistry.any((t) => t.id == e.id), isFalse, reason: e.id);
      }
      expect(
          ids,
          containsAll(
              ['chat', 'profile', 'delete_data', 'terms', 'privacy', 'help']));
    });

    test('szukanie po angielsku i bez polskich znaków', () {
      expect(searchNavEntries('delete data', AppLanguage.en).first.id,
          'delete_data');
      expect(searchNavEntries('usun moje dane', AppLanguage.pl).first.id,
          'delete_data');
      expect(searchNavEntries('privacy', AppLanguage.en).first.id, 'privacy');
      expect(searchNavEntries('', AppLanguage.pl), isEmpty);
    });
  });

  group('pomoc: filtry i kategoria o aplikacji', () {
    Future<void> pumpHelp(WidgetTester tester) async {
      tester.view.physicalSize = const Size(1100, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(AppLanguageScope(
        controller: AppLanguageController(AppLanguage.pl),
        child: const MaterialApp(home: HelpScreen()),
      ));
      await tester.pump(const Duration(milliseconds: 100));
    }

    testWidgets('filtry kategorii mają cel dotyku ≥ 48 dp i stan „wybrany"',
        (tester) async {
      final handle = tester.ensureSemantics();
      await pumpHelp(tester);
      final all = find.byKey(const ValueKey('help-filter-all'));
      expect(all, findsOneWidget);
      expect(tester.getSize(all).height, greaterThanOrEqualTo(kMinTapTarget));
      expect(tester.getSemantics(all),
          isSemantics(isButton: true, isSelected: true));

      final first = find.byKey(ValueKey('help-filter-${kHelpCategories.first.id}'));
      expect(tester.getSize(first).height,
          greaterThanOrEqualTo(kMinTapTarget));
      expect(tester.getSemantics(first),
          isSemantics(isButton: true, isSelected: false));
      await tester.tap(first);
      await tester.pump(const Duration(milliseconds: 100));
      expect(tester.getSemantics(first), isSemantics(isSelected: true));
      handle.dispose();
    });

    testWidgets('„wyczyść" w wyszukiwarce ma etykietę', (tester) async {
      await pumpHelp(tester);
      await tester.enterText(find.byType(TextField), 'wps');
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byTooltip('Wyczyść'), findsOneWidget);
    });

    test('kategoria „Aplikacja i konto": czat, dane, skaner, asystent, '
        'kopia, kontakt', () {
      final app = kHelpCategories.firstWhere((c) => c.id == 'app-account');
      expect(app.title(AppLanguage.pl), 'Aplikacja i konto');
      final tags = app.entries.expand((e) => e.tags).toSet();
      expect(tags, containsAll(
          ['czat', 'zgloszenie', 'usun-dane', 'skaner', 'asystent', 'kopia',
           'kontakt']));
      for (final e in app.entries) {
        expect(e.question(AppLanguage.pl), isNotEmpty);
        expect(e.answer(AppLanguage.en), isNotEmpty);
      }
    });
  });
}
