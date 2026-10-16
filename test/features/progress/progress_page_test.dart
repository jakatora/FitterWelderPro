// Ekran „Postęp robót" na prawdziwej bazie testowej: pusty dziennik → jedno
// dotknięcie do dziennika spoin; spoiny wpisane przez DAO → DI dziś /
// w tygodniu, warsztat/obiekt, pakiet, spawacze bez podwójnego liczenia,
// prognoza zapamiętana per projekt, raport tekstem i PDF.

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:cut_list_app/database/db.dart';
import 'package:cut_list_app/database/weld_journal_dao.dart';
import 'package:cut_list_app/domain/progress/progress_filter.dart';
import 'package:cut_list_app/domain/progress/progress_forecast.dart';
import 'package:cut_list_app/domain/progress/progress_report.dart';
import 'package:cut_list_app/domain/progress/weld_progress.dart';
import 'package:cut_list_app/domain/progress/work_calendar.dart';
import 'package:cut_list_app/domain/weld_journal/weld_defaults.dart';
import 'package:cut_list_app/domain/weld_journal/weld_entry.dart';
import 'package:cut_list_app/domain/weld_journal/weld_ndt.dart';
import 'package:cut_list_app/features/progress/progress_page.dart';
import 'package:cut_list_app/features/quotes/quote_widgets.dart'
    show QuoteNumberField;
import 'package:cut_list_app/i18n/app_language.dart';
import 'package:cut_list_app/screens/weld_journal_screen.dart'
    show WeldJournalScreen;
import 'package:cut_list_app/services/progress_export.dart';
import 'package:cut_list_app/services/progress_scope_store.dart';

import '../../support/test_database.dart';
import '../../support/weld_fixtures.dart';

/// Środa 2026-10-14, po południu.
DateTime _clock() => DateTime(2026, 10, 14, 15, 30);

Future<void> _settle(WidgetTester tester, {int rounds = 6}) async {
  for (var i = 0; i < rounds; i++) {
    await flushTestDatabase(tester);
    await tester.pump(const Duration(milliseconds: 50));
  }
}

Future<void> _clear(WidgetTester tester) => tester.runAsync(() async {
      final db = await AppDatabase.get();
      for (final t in [
        'weld_journal',
        'weld_journal_history',
        'weld_repairs',
        'weld_journal_projects',
      ]) {
        await db.delete(t);
      }
    });

Future<void> _pump(WidgetTester tester,
    {double dpr = 1, AppLanguage lang = AppLanguage.pl}) async {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = dpr;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(AppLanguageScope(
    controller: AppLanguageController(lang),
    child: const MaterialApp(home: ProgressPage(clock: _clock)),
  ));
  await _settle(tester);
  await tester.pumpAndSettle();
}

/// Spoiny projektu „Blok 4" (+ jedna innego projektu):
///   a1 dziś, TP-01, obiekt, JK-12 lico + AB-03 grań, 4" → 4 DI
///   a2 dziś, TP-01, obiekt, JK-12, 2" → 2 DI
///   a3 wczoraj, TP-01, obiekt, AB-03, 2", RT NOK → naprawa R1
///   a4 poniedziałek, TP-02, warsztat, JK-12, 6" → 6 DI
///   b1 dziś, projekt „Inny", XX-01
List<WeldEntry> _welds() => [
      weld('a1', date: '2026-10-14', welder: 'JK-12', rootWelder: 'AB-03')
          .copyWith(
              od: '114.3', testPackage: 'TP-01', shopField: WeldLocation.field),
      weld('a2', date: '2026-10-14', welder: 'JK-12')
          .copyWith(testPackage: 'TP-01', shopField: WeldLocation.field),
      weld('a3', date: '2026-10-13', welder: 'AB-03', ndt: {
        NdtMethod.rt: ndtOf(NdtScope.selected, NdtResult.nok, 'RT-7'),
      }).copyWith(testPackage: 'TP-01', shopField: WeldLocation.field),
      weld('a4', date: '2026-10-12', welder: 'JK-12').copyWith(
          od: '168.3', testPackage: 'TP-02', shopField: WeldLocation.shop),
      weld('b1', project: 'Inny', date: '2026-10-14', welder: 'XX-01'),
    ];

Future<void> _seed(WidgetTester tester) => tester.runAsync(() async {
      final dao = WeldJournalDao();
      for (final w in _welds()) {
        await dao.insert(w, by: 'JK-12');
      }
      await dao.addRepair('a3',
          date: '2026-10-14', reason: 'porowatość', by: 'JK-12');
    });

Finder _inTotal(String text) => find.descendant(
    of: find.byKey(const ValueKey('progress-total')),
    matching: find.text(text));

Future<void> _scrollTo(WidgetTester tester, Finder f) =>
    tester.scrollUntilVisible(f, 300,
        scrollable: find
            .descendant(
                of: find.byKey(const ValueKey('progress-list')),
                matching: find.byType(Scrollable))
            .first);

void main() {
  useTestDatabase();

  setUp(() => SharedPreferences.setMockInitialValues({
        kLastWeldProjectPrefsKey: 'Blok 4',
      }));

  testWidgets('pusty dziennik: zachęta i jedno dotknięcie do dziennika spoin',
      (tester) async {
    await _clear(tester);
    await _pump(tester);
    expect(find.text('Dziennik spoin jest pusty'), findsOneWidget);
    expect(find.byKey(const ValueKey('progress-list')), findsNothing);

    await tester.tap(find.byKey(const ValueKey('progress-open-journal')));
    await tester.pump(const Duration(milliseconds: 400));
    await _settle(tester);
    await tester.pumpAndSettle();
    expect(find.byType(WeldJournalScreen), findsOneWidget);

    await tester.pageBack();
    await _settle(tester);
    await tester.pumpAndSettle();
    expect(find.byType(ProgressPage), findsOneWidget);
    expect(find.text('Dziennik spoin jest pusty'), findsOneWidget);
  });

  testWidgets(
      'spoiny z dziennika: DI dziś i w tygodniu, warsztat/obiekt, pakiet, '
      'spawacze bez podwójnego liczenia', (tester) async {
    await _clear(tester);
    await _seed(tester);
    await _pump(tester);

    // Ostatni projekt dziennika wybrany sam; okres „Dziś": a1 + a2.
    expect(find.text('Blok 4'), findsWidgets);
    expect(_inTotal('6'), findsOneWidget);
    expect(
        find.descendant(
            of: find.byKey(const ValueKey('progress-welds')),
            matching: find.text('2')),
        findsOneWidget);
    expect(find.text('Raport dzienny · 2026-10-14 (śr)'), findsOneWidget);

    // Ten tydzień: a1..a4 = 4 + 2 + 2 + 6 DI.
    await tester.tap(find.byKey(const ValueKey('progress-period-week')));
    await tester.pumpAndSettle();
    expect(_inTotal('14'), findsOneWidget);
    // Kafelek „Dziś" przy okresie innym niż dziś.
    expect(
        find.descendant(
            of: find.byKey(const ValueKey('progress-today')),
            matching: find.text('6 DI')),
        findsOneWidget);

    // Warsztat: tylko a4.
    await tester.tap(find.byKey(const ValueKey('progress-loc-shop')));
    await tester.pumpAndSettle();
    expect(_inTotal('6'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('progress-loc-all')));
    await tester.pumpAndSettle();
    expect(_inTotal('14'), findsOneWidget);

    // Spawacze: JK-12 3 spoiny (1 wspólna), DI 2 + 2 + 6; AB-03 2 + 2.
    final crew = find.byKey(const ValueKey('progress-crew'));
    await _scrollTo(tester, crew);
    expect(
        find.descendant(
            of: find.byKey(const ValueKey('progress-welder-JK-12')),
            matching: find.text('10 DI')),
        findsOneWidget);
    expect(
        find.descendant(
            of: find.byKey(const ValueKey('progress-welder-AB-03')),
            matching: find.text('4 DI')),
        findsOneWidget);
    // Brygada: 4 spoiny, nie 5 (a1 ma dwóch spawaczy).
    expect(find.descendant(of: crew, matching: find.text('4 spoiny · 14 DI')),
        findsOneWidget);
    // AB-03: RT NOK sprzed naprawy → 1 z 1 zbadanych.
    expect(
        find.descendant(
            of: find.byKey(const ValueKey('progress-welder-AB-03')),
            matching: find.textContaining('100% (1 z 1 zbadanych RT/UT)')),
        findsOneWidget);

    // Pakiet TP-02 → tylko a4.
    await tester.scrollUntilVisible(
        find.byKey(const ValueKey('progress-package')), -300,
        scrollable: find
            .descendant(
                of: find.byKey(const ValueKey('progress-list')),
                matching: find.byType(Scrollable))
            .first);
    await tester.tap(find.byKey(const ValueKey('progress-package')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('TP-02').last);
    await tester.pumpAndSettle();
    await _settle(tester);
    await tester.pumpAndSettle();
    expect(_inTotal('6'), findsOneWidget);
  });

  testWidgets(
      'prognoza: zakres DI zapamiętany per projekt, % i data końca przy '
      'obecnym tempie', (tester) async {
    await _clear(tester);
    await _seed(tester);
    await _pump(tester);

    final field = find.widgetWithText(TextField, 'Zakres do wykonania');
    await _scrollTo(tester, field);
    await tester.enterText(field, '40');
    await tester.pumpAndSettle();

    // Wykonano cały zakres projektu (niezależnie od okresu „Dziś"): 14 DI.
    expect(
        find.descendant(
            of: find.byKey(const ValueKey('progress-forecast-pct')),
            matching: find.text('35%'),
            matchRoot: true),
        findsOneWidget);
    // Tempo: 14 DI / 3 dni rob. (pn–śr, dziś z wpisami); zostało 26 DI
    // → 6 dni rob. od jutra: czw 15 … czw 22.
    expect(
        find.descendant(
            of: find.byKey(const ValueKey('progress-forecast-finish')),
            matching: find.text('2026-10-22')),
        findsOneWidget);

    final prefs = await SharedPreferences.getInstance();
    final saved = ProgressScope.decode(
        prefs.getString(ProgressScopeStore.keyFor('Blok 4', '')));
    expect(saved.total, 40);
    expect(saved.unit, ScopeUnit.di);

    // Soboty: zapis w tym samym zakresie.
    await _scrollTo(tester, find.byKey(const ValueKey('progress-saturdays')));
    await tester.tap(find.byKey(const ValueKey('progress-saturdays')));
    await tester.pumpAndSettle();
    expect(
        ProgressScope.decode(
                prefs.getString(ProgressScopeStore.keyFor('Blok 4', '')))
            .saturdays,
        isTrue);

    // Ponowne otwarcie ekranu: zakres wraca z pamięci.
    await tester.pumpWidget(const SizedBox());
    await _pump(tester);
    await _scrollTo(tester, find.byKey(const ValueKey('progress-forecast-pct')));
    expect(
        find.descendant(
            of: find.byKey(const ValueKey('progress-forecast-pct')),
            matching: find.text('35%'),
            matchRoot: true),
        findsOneWidget);
  });

  testWidgets(
      'raport tekstem: idzie do udostępniania, a bez niego do schowka',
      (tester) async {
    await _clear(tester);
    await _seed(tester);
    const share = MethodChannel('dev.fluttercommunity.plus/share');
    final messenger = tester.binding.defaultBinaryMessenger;
    String? shared;
    var shareFails = false;
    messenger.setMockMethodCallHandler(share, (call) async {
      if (shareFails) throw PlatformException(code: 'no-share');
      if (call.method == 'share') {
        shared = (call.arguments as Map)['text'] as String?;
      }
      return 'dev.fluttercommunity.plus/share/unavailable';
    });
    String? clip;
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        clip = (call.arguments as Map)['text'] as String?;
      }
      return null;
    });
    addTearDown(() {
      messenger.setMockMethodCallHandler(share, null);
      messenger.setMockMethodCallHandler(SystemChannels.platform, null);
    });

    await _pump(tester);
    final btn = find.byKey(const ValueKey('progress-share-text'));
    await _scrollTo(tester, btn);
    await tester.tap(btn);
    await tester.pumpAndSettle();
    expect(shared, startsWith('RAPORT DZIENNY — 2026-10-14 (śr)'));
    expect(shared, contains('Wykonano: 2 spoiny · 6 DI'));
    expect(shared, contains('Brygada razem: 2 spoiny · 6 DI'));
    expect(clip, isNull);

    // Udostępnianie niedostępne → tekst w schowku i komunikat.
    shareFails = true;
    await tester.tap(btn);
    await tester.pumpAndSettle();
    expect(clip, shared);
    expect(find.text('Skopiowano raport.'), findsOneWidget);
  });

  for (final lang in AppLanguage.values) {
    testWidgets('wąski telefon (360 dp, ${lang.name}): cały ekran bez przepełnień',
        (tester) async {
      await _clear(tester);
      await _seed(tester);
      await _pump(tester, dpr: 3, lang: lang);
      await tester.tap(find.byKey(const ValueKey('progress-period-week')));
      await tester.pumpAndSettle();
      final field = find.descendant(
          of: find.byType(QuoteNumberField), matching: find.byType(TextField));
      await _scrollTo(tester, field);
      await tester.enterText(field, '40');
      await tester.pumpAndSettle();
      await _scrollTo(tester, find.byKey(const ValueKey('progress-share-pdf')));
      expect(tester.takeException(), isNull);
      expect(find.byKey(const ValueKey('progress-forecast-finish')),
          findsOneWidget);
    });
  }

  test('PDF raportu tygodniowego renderuje się (PL i EN)', () async {
    pw.Font font(String f) => pw.Font.ttf(
        ByteData.sublistView(File('assets/fonts/$f').readAsBytesSync()));
    final today = _clock();
    const filter =
        ProgressFilter(project: 'Blok 4', period: ProgressPeriod.week);
    final welds = _welds();
    final scope = filter.scopeOf(welds);
    final pace =
        computePace(scope, today: today, week: const WorkWeek());
    final report = ProgressReport(
      filter: filter,
      range: filter.rangeFor(today),
      summary: summarizeProgress(filter.apply(welds, today)),
      pace: pace,
      forecast: computeForecast(
        unit: ScopeUnit.di,
        done: summarizeProgress(scope).di,
        total: 40,
        pacePerDay: pace!.diPerDay,
        today: today,
        todayLogged: true,
        week: const WorkWeek(),
        due: DateTime(2026, 11, 6),
      ),
      generatedAt: today,
    );
    for (final en in [false, true]) {
      final doc = ProgressExport.buildPdfDocument(
        report: report,
        en: en,
        font: font('Roboto-Regular.ttf'),
        boldFont: font('Roboto-Bold.ttf'),
      );
      final bytes = await doc.save();
      expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
    }
    // Pusty okres też daje PDF (nie wywraca się na braku spoin).
    final empty = ProgressExport.buildPdfDocument(
      report: ProgressReport(
        filter: const ProgressFilter(project: 'Nic'),
        range: null,
        summary: summarizeProgress(const []),
        pace: null,
        forecast: null,
        generatedAt: today,
      ),
      en: false,
      font: font('Roboto-Regular.ttf'),
    );
    expect(utf8.decode((await empty.save()).take(5).toList()), '%PDF-');
  });
}
