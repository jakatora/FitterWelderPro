// "Welder journey" — walks the real app the way a fitter/welder would on a
// site: first launch straight into the tools, introduce yourself only when
// opening the chat, look at what's on the home screen, run a preheat
// calculation on low-carbon steel, and check the elbow takeout reference
// table.
//
// These drive the actual production widgets (no mocks beyond SharedPreferences
// and the sqflite FFI factory), so they catch what a unit test on the data
// layer cannot: whether the fixes are reachable and correct from the UI.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'support/test_database.dart';

import 'package:cut_list_app/app.dart';
import 'package:cut_list_app/config/feature_flags.dart';
import 'package:cut_list_app/i18n/app_language.dart';
import 'package:cut_list_app/screens/chat_screen.dart';
import 'package:cut_list_app/screens/iso_scanner_screen.dart';
import 'package:cut_list_app/screens/onboarding_name_screen.dart';
import 'package:cut_list_app/screens/premium_screen.dart';
import 'package:cut_list_app/services/iso_scanner_ai.dart';
import 'package:cut_list_app/services/legal_consent.dart';
import 'package:cut_list_app/services/premium_service.dart';
import 'package:cut_list_app/services/user_profile.dart';
import 'package:cut_list_app/widgets/premium_gate.dart';
import 'package:cut_list_app/widgets/tool_registry.dart';

import 'test_prefs.dart';

void main() {
  useTestDatabase();

  /// Boot the real app on a phone-sized-but-tall surface so the tool grid and
  /// the calculator forms fit without overflowing.
  Future<void> boot(WidgetTester tester, {required bool withProfile}) async {
    tester.view.physicalSize = const Size(1100, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    // Profil i zgoda są potrzebne dopiero na czacie; ziarno decyduje, czy
    // bramka czatu o nie zapyta.
    if (withProfile) {
      seedOnboardedUser();
    } else {
      seedFreshInstall();
    }

    await tester.pumpWidget(const CutListApp());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }

  /// Discrete pumps rather than pumpAndSettle: the home screen keeps an
  /// indeterminate spinner / RefreshIndicator alive, which would make
  /// pumpAndSettle time out. Enough frames to cover a 300 ms route transition
  /// even when the suite runs several test isolates in parallel.
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 8; i++) {
      await flushTestDatabase(tester);
      await tester.pump(const Duration(milliseconds: 120));
    }
  }

  testWidgets(
      'pierwsze uruchomienie: narzędzia od razu, przedstawia się dopiero przy '
      'czacie', (tester) async {
    await boot(tester, withProfile: false);
    await settle(tester);

    // Kalkulatory działają offline i bez konta — ekran główny od razu.
    expect(find.byIcon(Icons.handyman_outlined), findsOneWidget); // MONTER
    expect(find.byType(OnboardingNameScreen), findsNothing);

    // Dopiero czat pyta o imię, nazwisko i zasady.
    await tester.tap(find.byIcon(Icons.forum_outlined)); // CZAT
    await settle(tester);
    expect(find.byType(OnboardingNameScreen), findsOneWidget);

    final fields = find.byType(TextField);
    expect(fields, findsNWidgets(2));
    await tester.enterText(fields.at(0), 'Marek');
    await tester.enterText(fields.at(1), 'Kowalczyk');
    await settle(tester);

    // Samo imię nie wystarczy — trzeba jeszcze zaakceptować zasady.
    expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull);
    await tester.tap(find.byType(Checkbox));
    await settle(tester);

    await tester.tap(find.byType(FilledButton));
    await settle(tester);

    // Po przedstawieniu się i akceptacji zasad wchodzi na czat.
    expect(find.byType(ChatScreen), findsOneWidget);
    expect(UserProfileService.instance.current?.fullName, 'Marek Kowalczyk');
    expect(LegalConsent.instance.isAccepted, isTrue);

    // Domknij żądania czatu (atrapa HTTP odpowiada 400, limit czasu 8 s).
    await tester.pump(const Duration(seconds: 10));
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('ekran główny: czat i skaner są, płatne ukryte',
      (tester) async {
    await boot(tester, withProfile: true);

    // Widoczne: MONTER, SPAWACZ, CZAT (ikony są niezależne od języka).
    // Kafla POMOC nie ma — pomoc jest pod ikoną „?" w pasku.
    expect(find.byIcon(Icons.handyman_outlined), findsOneWidget); // MONTER
    expect(find.byIcon(Icons.waves_outlined), findsOneWidget); // SPAWACZ
    expect(find.byIcon(Icons.forum_outlined), findsOneWidget); // CZAT

    // Skaner działa w darmowym trybie z dziennym limitem — kafel jest.
    expect(kAiScannerReachable, isTrue);
    expect(find.byIcon(Icons.document_scanner_outlined), findsOneWidget);

    // Ukryte całkowicie — nie "Wkrótce", ma ich nie być:
    expect(find.text('PREMIUM'), findsNothing);
    expect(find.byIcon(Icons.workspace_premium), findsNothing);
    expect(find.byIcon(Icons.work_outline), findsNothing); // PRACA
    // I żadnego napisu "WKRÓTCE" na kaflach.
    expect(find.text('WKRÓTCE'), findsNothing);
    expect(find.text('SOON'), findsNothing);
  });

  testWidgets('kafel skanera prowadzi do skanu, nie do bramki ani ceny',
      (tester) async {
    await boot(tester, withProfile: false);
    await settle(tester);

    await tester.tap(find.byIcon(Icons.document_scanner_outlined));
    await settle(tester);

    // Prosto na ekran skanera — bez imienia, bez bramki Premium.
    expect(find.byType(IsoScannerScreen), findsOneWidget);
    expect(find.byType(OnboardingNameScreen), findsNothing);
    expect(find.byIcon(Icons.lock_open_outlined), findsNothing);
    expect(find.byType(PremiumScreen), findsNothing);
    // Żadnej ceny na ekranie, na który prowadzi kafel.
    expect(find.textContaining('PLN'), findsNothing);
    expect(find.textContaining('zł'), findsNothing);
    // Monter od razu może wybrać zdjęcie i widzi, ile skanów zostało.
    expect(find.byIcon(Icons.photo_camera_outlined), findsOneWidget);
    expect(find.textContaining('Pozostało dziś'), findsOneWidget);
  });

  testWidgets('żadne dostępne narzędzie nie otwiera ekranu z ceną',
      (tester) async {
    seedOnboardedUser();
    late BuildContext ctx;
    await tester.pumpWidget(MaterialApp(home: Builder(builder: (c) {
      ctx = c;
      return const SizedBox();
    })));
    for (final tool in availableTools) {
      final screen = tool.builder(ctx);
      expect(screen, isNot(isA<PremiumScreen>()), reason: tool.id);
      expect(screen, isNot(isA<PremiumGate>()), reason: tool.id);
    }
  });

  testWidgets(
      'spawacz liczy podgrzewanie dla stali niskowęglowej — zero "NaN" na ekranie',
      (tester) async {
    await boot(tester, withProfile: true);

    // SPAWACZ → „Heat input i CE" — jedyne wejście do podgrzewania (dawna
    // zakładka „Temperatura" w kalkulatorach spawacza dublowała ten ekran).
    await tester.tap(find.byIcon(Icons.waves_outlined));
    await settle(tester);
    final heatInput = find.byIcon(Icons.local_fire_department_outlined);
    expect(heatInput, findsOneWidget);
    await tester.ensureVisible(heatInput);
    await settle(tester);
    await tester.tap(heatInput);
    await settle(tester);

    // Zakładka „Preheat / CE" (druga) — CE + metody podgrzewania.
    await tester.tap(find.byType(Tab).at(1));
    await settle(tester);

    // Stal węglowa bez gatunku z listy — właśnie ta ścieżka dawała NaN.
    // Wpisujemy chemię niskowęglową: CE = 0.12 + 0.60/6 = 0.220 (< 0.25),
    // więc Seferian ma [C] ≤ 0.25 (dawniej √ z liczby ujemnej).
    Finder field(Set<String> labels) => find.byWidgetPredicate(
          (w) => w is TextField && labels.contains(w.decoration?.labelText),
          description: 'TextField $labels',
        );
    final thickness = field({'Grubość', 'Thickness'});
    final carbon = field({'C'});
    final manganese = field({'Mn'});

    await tester.enterText(thickness.first, '10');
    await settle(tester);
    await tester.enterText(carbon.first, '0.12');
    await settle(tester);
    await tester.enterText(manganese.first, '0.60');
    await settle(tester);

    // CE policzone i pokazane…
    expect(find.text('0.220'), findsOneWidget);
    // …Seferian daje 0 °C (niskowęglowa — bez podgrzewania)…
    expect(find.text('0 °C'), findsWidgets);
    // …a temperatura podgrzewania NIE jest NaN (to był bug: sqrt z ujemnej).
    expect(find.textContaining('NaN'), findsNothing);
  });

  testWidgets('monter sprawdza wymiary kolan; skaner jest w menu MONTER',
      (tester) async {
    await boot(tester, withProfile: true);

    await tester.tap(find.byIcon(Icons.handyman_outlined)); // MONTER
    await settle(tester);

    // Kafel skanera jest — darmowy tryb z dziennym limitem.
    expect(find.byIcon(Icons.document_scanner_outlined), findsOneWidget);

    // "Wymiary kolan" — tabela takeoutów.
    final elbows = find.byIcon(Icons.table_rows_outlined);
    expect(elbows, findsOneWidget);
    await tester.ensureVisible(elbows);
    await settle(tester);
    await tester.tap(elbows);
    await settle(tester);

    // Monter szuka swojego rozmiaru: wpisuje "100" w wyszukiwarkę.
    await tester.enterText(find.byType(TextField).first, '100');
    await settle(tester);

    // Zostaje jeden wiersz: DN100. Nagłówek wiersza to RichText ("DN100 · 4\""),
    // którego find.textContaining nie przeszukuje — stąd predykat.
    expect(
      find.byWidgetPredicate(
          (w) => w is RichText && w.text.toPlainText().contains('DN100')),
      findsOneWidget,
    );
    expect(find.text('152'), findsOneWidget); // LR 90°
    expect(find.text('102'), findsOneWidget); // SR 90°
    // Kluczowe: 45° to 64 mm wg ASME B16.9 — przed naprawą pokazywało 76 mm.
    expect(find.text('64'), findsOneWidget);
    expect(find.text('76'), findsNothing);
    expect(find.textContaining('NaN'), findsNothing);
  });

  testWidgets(
      'skaner ISO bez Premium (darmowy tryb): ekran prowadzi do skanu, mówi '
      'co się stanie ze zdjęciem', (tester) async {
    tester.view.physicalSize = const Size(1100, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    seedOnboardedUser();

    await tester.pumpWidget(AppLanguageScope(
      controller: AppLanguageController(AppLanguage.pl),
      child: const MaterialApp(home: IsoScannerScreen()),
    ));
    await settle(tester);

    // Darmowy tryb: bez bramki Premium (kłódka to jej ikona).
    expect(find.byIcon(Icons.lock_open_outlined), findsNothing);
    expect(find.byIcon(Icons.photo_camera_outlined), findsOneWidget);
    // Przed skanem: dokąd idzie zdjęcie i że wynik trzeba sprawdzić.
    expect(find.textContaining('Anthropic'), findsWidgets);
    expect(find.textContaining('niepewne wartości'), findsWidgets);
    // Ile skanów zostało dziś (bezpiecznik po stronie telefonu).
    expect(find.textContaining('Pozostało dziś: $kAiScanDailyLimitPerDevice'),
        findsOneWidget);
  });

  testWidgets('z wyniku skanu monter przechodzi do ekranu przeglądu',
      (tester) async {
    tester.view.physicalSize = const Size(1100, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    seedOnboardedUser();

    // Darmowy tryb: bez Premium — droga do przeglądu działa bez zakupu.
    expect(PremiumService.instance.status.isActive, isFalse);

    // Wynik skanu wstrzyknięty zamiast wywołania sieciowego — chodzi o drogę
    // z gotowego odczytu do przeglądu, nie o samo rozpoznawanie rysunku.
    final scan = AiScanResult(
      sizeNotation: 'DN',
      titleBlock: AiTitleBlock(
        lineNumber: 'DN100-CWS-1234',
        material: 'A312 TP304L',
        schedule: '10S',
      ),
      segments: [
        AiSegment(
          id: 's1',
          dimensionMm: 1500,
          rawDimension: '1500',
          toId: 'c1',
          confidence: AiConfidence.high,
        ),
      ],
      components: [
        AiComponent(id: 'c1', type: 'elbow90', confidence: AiConfidence.high),
      ],
    );

    await tester.pumpWidget(AppLanguageScope(
      controller: AppLanguageController(AppLanguage.pl),
      child: MaterialApp(home: IsoScannerScreen(initialScan: scan)),
    ));
    await settle(tester);

    // Skan to jedyna funkcja w apce wymagająca sieci — ekran mówi to wprost.
    expect(find.textContaining('wymaga internetu'), findsWidgets);

    final toProject = find.byIcon(Icons.playlist_add_check_circle_outlined);
    expect(toProject, findsOneWidget);
    expect(
      tester
          .widget<IconButton>(find.ancestor(
            of: toProject,
            matching: find.byType(IconButton),
          ))
          .onPressed,
      isNotNull,
      reason: 'po udanej analizie przycisk ma być aktywny',
    );

    await tester.tap(toProject);
    await settle(tester);

    // Ekran przeglądu: plan projektu z rysunku, z policzonym cięciem
    // (1500 − 152 mm take-outu kolana DN100 LR).
    expect(find.text('Sprawdź skan'), findsOneWidget);
    expect(find.text('114.3'), findsOneWidget);
    expect(find.textContaining('CUT 1348'), findsOneWidget);
  });
}
