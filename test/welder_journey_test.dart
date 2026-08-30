// "Welder journey" — walks the real app the way a fitter/welder would on a
// site: first launch, introduce yourself, look at what's on the home screen,
// run a preheat calculation on low-carbon steel, and check the elbow takeout
// reference table.
//
// These drive the actual production widgets (no mocks beyond SharedPreferences
// and the sqflite FFI factory), so they catch what a unit test on the data
// layer cannot: whether the fixes are reachable and correct from the UI.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:cut_list_app/app.dart';
import 'package:cut_list_app/i18n/app_language.dart';
import 'package:cut_list_app/screens/iso_scanner_screen.dart';
import 'package:cut_list_app/services/iso_scanner_ai.dart';
import 'package:cut_list_app/services/premium_service.dart';

import 'test_prefs.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  /// Boot the real app on a phone-sized-but-tall surface so the tool grid and
  /// the calculator forms fit without overflowing.
  Future<void> boot(WidgetTester tester, {required bool withProfile}) async {
    tester.view.physicalSize = const Size(1100, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    // Brama startowa sprawdza profil ORAZ akceptację zasad.
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
      await tester.pump(const Duration(milliseconds: 120));
    }
  }

  /// When the whole suite runs, several test isolates hit the same sqflite
  /// file at once; HomeScreen catches the failure and shows a 4 s SnackBar.
  /// Its Timer would still be pending when the tree is torn down, which the
  /// test binding treats as a failure. Let those timers expire.
  Future<void> drainTimers(WidgetTester tester) async {
    // The failing DB read can land late, so the SnackBar (and its 4 s timer)
    // may only be created after the first pump. Drain in several long steps.
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(seconds: 3));
    }
  }

  testWidgets('pierwsze uruchomienie: monter musi się przedstawić, zanim wejdzie',
      (tester) async {
    await boot(tester, withProfile: false);

    // Brama startowa trzyma go na onboardingu — narzędzi jeszcze nie widać.
    expect(find.text('FITTER'), findsNothing);

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

    // Po przedstawieniu się i akceptacji zasad wchodzi do narzędzi.
    expect(find.text('FITTER'), findsOneWidget);
    await drainTimers(tester);
  });

  testWidgets('ekran główny: czat i skaner ISO są, płatne wciąż ukryte',
      (tester) async {
    await boot(tester, withProfile: true);

    // Widoczne: FITTER, SPAWACZ, POMOC, CZAT (ikony są niezależne od języka).
    expect(find.byIcon(Icons.handyman_outlined), findsOneWidget); // FITTER
    expect(find.byIcon(Icons.waves_outlined), findsOneWidget); // SPAWACZ
    expect(find.byIcon(Icons.forum_outlined), findsOneWidget); // CZAT

    // Skaner ISO jest włączony (kAiScannerEnabled = true), odkąd zdjęcie
    // rysunku prowadzi do gotowej cut listy — kafel ma być widoczny.
    expect(find.byIcon(Icons.document_scanner_outlined), findsOneWidget);

    // Ukryte całkowicie — nie "Wkrótce", ma ich nie być:
    expect(find.text('PREMIUM'), findsNothing);
    expect(find.byIcon(Icons.workspace_premium), findsNothing);
    expect(find.byIcon(Icons.work_outline), findsNothing); // PRACA
    // I żadnego napisu "WKRÓTCE" na kaflach.
    expect(find.text('WKRÓTCE'), findsNothing);
    expect(find.text('SOON'), findsNothing);
    await drainTimers(tester);
  });

  testWidgets(
      'spawacz liczy podgrzewanie dla stali niskowęglowej — zero "NaN" na ekranie',
      (tester) async {
    await boot(tester, withProfile: true);

    // SPAWACZ → Kalkulatory
    await tester.tap(find.byIcon(Icons.waves_outlined));
    await settle(tester);
    expect(find.byIcon(Icons.calculate_outlined), findsOneWidget);
    await tester.tap(find.byIcon(Icons.calculate_outlined));
    await settle(tester);

    // Zakładka "Temperatura" (druga) — kalkulator CEV + podgrzewanie.
    await tester.tap(find.byType(Tab).at(1));
    await settle(tester);

    // Domyślny materiał to CS (stal węglowa) — właśnie ta ścieżka dawała NaN.
    // Wpisujemy chemię niskowęglową: CEV = 0.12 + 0.60/6 = 0.220 (< 0.25).
    final thickness = find.ancestor(
      of: find.textContaining('t (mm)'),
      matching: find.byType(TextField),
    );
    final carbon = find.ancestor(
      of: find.text('C %'),
      matching: find.byType(TextField),
    );
    final manganese = find.ancestor(
      of: find.text('Mn %'),
      matching: find.byType(TextField),
    );

    await tester.enterText(thickness.first, '10');
    await settle(tester);
    await tester.enterText(carbon.first, '0.12');
    await settle(tester);
    await tester.enterText(manganese.first, '0.60');
    await settle(tester);

    // CEV policzone i pokazane…
    expect(find.text('0.220'), findsOneWidget);
    // …a temperatura podgrzewania NIE jest NaN (to był bug: sqrt z ujemnej).
    expect(find.textContaining('NaN'), findsNothing);
    await drainTimers(tester);
  });

  testWidgets('monter sprawdza wymiary kolan; skaner ISO stoi w menu Fitter',
      (tester) async {
    await boot(tester, withProfile: true);

    await tester.tap(find.byIcon(Icons.handyman_outlined)); // FITTER
    await settle(tester);

    // Skaner ISO jest tu widoczny — to wejście do ścieżki
    // „zdjęcie rysunku → przegląd → cut lista".
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
      find.byWidgetPredicate((w) =>
          w is RichText && w.text.toPlainText().contains('DN100')),
      findsOneWidget,
    );
    expect(find.text('152'), findsOneWidget); // LR 90°
    expect(find.text('102'), findsOneWidget); // SR 90°
    // Kluczowe: 45° to 64 mm wg ASME B16.9 — przed naprawą pokazywało 76 mm.
    expect(find.text('64'), findsOneWidget);
    expect(find.text('76'), findsNothing);
    expect(find.textContaining('NaN'), findsNothing);
    await drainTimers(tester);
  });

  testWidgets('skaner ISO bez Premium: monter trafia na bramkę, nie na skan',
      (tester) async {
    await boot(tester, withProfile: true);

    await tester.tap(find.byIcon(Icons.handyman_outlined)); // FITTER
    await settle(tester);

    final scanner = find.byIcon(Icons.document_scanner_outlined);
    await tester.ensureVisible(scanner);
    await settle(tester);
    await tester.tap(scanner);
    await settle(tester);

    // Każdy skan to płatne wywołanie Claude Vision, więc ekran stoi za
    // PremiumGate(alwaysEnforced). Ikony zamiast napisów — asercja ma być
    // niezależna od języka interfejsu.
    expect(find.byIcon(Icons.lock_open_outlined), findsOneWidget);
    await drainTimers(tester);
  });

  testWidgets('z wyniku skanu monter przechodzi do ekranu przeglądu',
      (tester) async {
    tester.view.physicalSize = const Size(1100, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    seedOnboardedUser();

    // Skaner jest płatny; test odblokowuje Premium lokalnie i sprząta po sobie.
    await PremiumService.instance.applyStatus(
      const PremiumStatus(plan: PremiumPlan.lifetime),
    );
    addTearDown(() => PremiumService.instance.applyStatus(PremiumStatus.free()));

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
      tester.widget<IconButton>(find.ancestor(
        of: toProject,
        matching: find.byType(IconButton),
      )).onPressed,
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
    await drainTimers(tester);
  });
}
