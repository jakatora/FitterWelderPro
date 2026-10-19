// Zeszyt ISO na prawdziwych szerokościach telefonów: 360×640 przy skali
// tekstu 1,3 i 412×860. Pasek podsumowania i pasek akcji nie mogą się
// przepełniać, przycisk Wstecz musi być trafialny, a każda akcja paska
// dostępna (na wąskim ekranie przez „Więcej”).

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:cut_list_app/database/db.dart';
import 'package:cut_list_app/database/iso_drawing_dao.dart';
import 'package:cut_list_app/i18n/app_language.dart';
import 'package:cut_list_app/screens/iso_notebook_screen.dart';

import '../support/iso_sketch_fixture.dart';

const _openButton = 'Otwórz zeszyt';

Widget _launcher(double textScale) => AppLanguageScope(
      controller: AppLanguageController(),
      child: MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                      builder: (_) => const IsoNotebookScreen()),
                ),
                child: const Text(_openButton),
              ),
            ),
          ),
        ),
      ),
    );

/// Every app-bar action of the notebook, by its tooltip / menu label.
const _actions = [
  'Szkice',
  'Pomoc',
  'Prefiksy notatek',
  'Wprowadź wymiary',
  'Kopiuj zestawienie',
  'Cofnij',
  'Wyłącz blokadę osi (slope)',
  'Pełny ekran',
  'Eksportuj PDF',
  'Pokaż instrukcję',
  'Wyczyść',
  'Widok',
];

/// A long name, a dimensioned run with a five-digit CUT total, and a
/// voice-drawn tail — the busiest summary bar a fitter will see.
Future<IsoNotebookController> _openBusySketch(WidgetTester tester) async {
  await IsoDrawingDao().upsert(IsoDrawingRecord(
    id: 'busy',
    name: '6"-CWS-1234 — linia zażółcona',
    json: jsonEncode(representativeIsoSketch()),
    createdAt: 1000,
    updatedAt: 1000,
  ));
  await tester.tap(find.text(_openButton));
  await tester.pumpAndSettle();
  final c = IsoNotebookController.active!;
  await c.ready;
  final r = await c.draw(const [
    IsoPipe(lengthMm: 12000),
    IsoTurn(toDir: IsoDir.forward),
    IsoPipe(lengthMm: 12000),
    IsoTurn(toDir: IsoDir.right),
    IsoPipe(lengthMm: 12000),
  ], stepDelay: Duration.zero);
  expect(r.problem, isNull);
  await tester.pump(const Duration(milliseconds: 600));
  return c;
}

void main() {
  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfiNoIsolate;
    await AppDatabase.configureForTesting(inMemoryDatabasePath);
  });
  tearDownAll(AppDatabase.clearTestingConfiguration);

  setUp(() async {
    SharedPreferences.setMockInitialValues({'iso_notebook_hint_hidden': true});
    final db = await AppDatabase.get();
    await db.delete(IsoDrawingDao.table);
  });

  for (final (size, scale) in const [
    (Size(360, 640), 1.3),
    (Size(360, 640), 1.0),
    (Size(412, 860), 1.0),
    (Size(412, 860), 1.3),
  ]) {
    final label = '${size.width.toInt()}×${size.height.toInt()}, '
        'tekst $scale';

    testWidgets(
        '$label: bez przepełnienia, Wstecz trafialny, każda akcja dostępna',
        (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      final fatal = WidgetController.hitTestWarningShouldBeFatal;
      WidgetController.hitTestWarningShouldBeFatal = true;
      addTearDown(() => WidgetController.hitTestWarningShouldBeFatal = fatal);

      await tester.pumpWidget(_launcher(scale));
      await tester.pumpAndSettle();
      await _openBusySketch(tester);
      expect(tester.takeException(), isNull, reason: 'no overflow');
      expect(find.textContaining('Suma CUT:'), findsOneWidget);
      expect(find.textContaining('Odcinki:'), findsOneWidget);

      // Every tool's hint (the longest strings in the bar) still fits.
      for (final tool in ['Kolano 90°', 'Trójnik', 'Tekst', 'Podział']) {
        final t = find.text(tool);
        if (t.evaluate().isEmpty) continue;
        await tester.ensureVisible(t.first);
        await tester.tap(t.first);
        await tester.pump();
        expect(tester.takeException(), isNull, reason: 'hint of $tool');
      }

      // Each action: a visible button with that tooltip, or an entry in
      // the overflow menu.
      final screen = Offset.zero & size;
      final more = find.byTooltip('Więcej');
      final inMenu = <String>[];
      for (final a in _actions) {
        final f = find.byTooltip(a);
        if (f.evaluate().isNotEmpty) {
          final r = tester.getRect(f.first);
          expect(screen.contains(r.center), isTrue, reason: '$a on screen');
          final back = tester.getRect(find.byType(BackButton));
          expect(r.overlaps(back), isFalse, reason: '$a covers Back');
        } else {
          inMenu.add(a);
        }
      }
      if (inMenu.isNotEmpty) {
        expect(more, findsOneWidget, reason: 'overflow: $inMenu');
        await tester.tap(more);
        await tester.pumpAndSettle();
        for (final a in inMenu) {
          expect(find.text(a), findsWidgets, reason: '$a in „Więcej”');
        }
        await tester.tapAt(const Offset(4, 300)); // close the menu
        await tester.pumpAndSettle();
      }
      expect(tester.takeException(), isNull);

      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.text(_openButton), findsOneWidget,
          reason: 'Back has to reach the button, not an action over it');
    });
  }

  testWidgets(
      '412×860: akcje z „Więcej” działają jak przyciski '
      '(Widok → Pomniejsz, Szkice → menu, Wyczyść)', (tester) async {
    tester.view.physicalSize = const Size(412, 860);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(_launcher(1.0));
    await tester.pumpAndSettle();
    final c = await _openBusySketch(tester);

    // „Widok” moved into „Więcej” opens the very same view menu.
    final before = c.debugVisibleWorld!;
    await tester.tap(find.byTooltip('Więcej'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Widok'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Pomniejsz'));
    await tester.pumpAndSettle();
    expect(c.debugVisibleWorld!.width, greaterThan(before.width));

    // A sub-menu the bar still shows works from its own button.
    final sketches = find.byTooltip('Szkice');
    if (sketches.evaluate().isNotEmpty) {
      await tester.tap(sketches);
      await tester.pumpAndSettle();
      expect(find.text('Zapisane szkice…'), findsOneWidget);
      await tester.tapAt(const Offset(4, 400));
      await tester.pumpAndSettle();
    }

    await tester.tap(find.byTooltip('Więcej'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Wyczyść'));
    await tester.pumpAndSettle();
    expect(find.text('Wyczyścić rysunek?'), findsOneWidget,
        reason: 'the same confirmation as the app-bar button');
    await tester.tap(find.text('Anuluj'));
    await tester.pumpAndSettle();
    expect(c.hasContent, isTrue);

    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text(_openButton), findsOneWidget);
  });
}
