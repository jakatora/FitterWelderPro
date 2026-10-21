// ISO notebook autosave, driven through the real screen and real SQLite.
//
// The drawing used to live only in RAM; leaving the screen threw it away.
// These tests draw / open / leave / reopen the actual IsoNotebookScreen and
// look at what comes back — and at what landed in `iso_drawings`.
//
// SQLite runs through `databaseFactoryFfiNoIsolate`: every database call
// completes inside the widget test's fake-async microtask queue, so a pump
// is enough for a save to land and there is no real-time race to paper over
// with arbitrary delays.

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
import '../support/iso_spatial_fixture.dart';

const _openButton = 'Otwórz zeszyt';

Widget _launcher() => AppLanguageScope(
      controller: AppLanguageController(),
      child: MaterialApp(
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

Future<void> _openNotebook(WidgetTester tester) async {
  await tester.tap(find.text(_openButton));
  await tester.pumpAndSettle();
}

/// The drawing canvas, found by its accessibility label.
Finder get _canvas => find.byWidgetPredicate((w) =>
    w is Semantics &&
    (w.properties.label?.startsWith('Płótno szkicu izometrycznego') ?? false));

Future<void> _drawPipe(WidgetTester tester) async {
  // Pipe tool and axis lock are the defaults: a horizontal drag lands on
  // iso axis I and snaps to whole grid steps.
  await tester.dragFrom(
    tester.getCenter(_canvas) - const Offset(64, 0),
    const Offset(160, 0),
  );
  await tester.pump();
}

Future<void> _leaveNotebook(WidgetTester tester) async {
  await tester.pageBack();
  await tester.pumpAndSettle();
  expect(find.text(_openButton), findsOneWidget,
      reason: 'the notebook route must be gone');
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

  Future<void> bootLauncher(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(_launcher());
    await tester.pumpAndSettle();
  }

  testWidgets(
      'spatial drawing renders and survives a real edit, autosave and reopen',
      (tester) async {
    final original = spatialSketch();
    await IsoDrawingDao().upsert(IsoDrawingRecord(
      id: 'spatial-sketch',
      name: 'Spatial',
      json: jsonEncode(original),
      createdAt: 1000,
      updatedAt: 1000,
    ));
    await bootLauncher(tester);
    await _openNotebook(tester);
    expect(tester.takeException(), isNull);
    expect(find.text('Odcinki: 1/1'), findsOneWidget);
    // A real canvas edit forces the screen to serialize its loaded model.
    await _drawPipe(tester);
    await _leaveNotebook(tester);
    final saved =
        jsonDecode((await IsoDrawingDao().getById('spatial-sketch'))!.json)
            as Map;
    expect(saved['format'], 4);
    final oldItems = original['items'] as List;
    final newItems = saved['items'] as List;
    expect(newItems.length, greaterThan(oldItems.length));
    expect(newItems.take(oldItems.length).toList(), oldItems);
    await _openNotebook(tester);
    expect(tester.takeException(), isNull);
    await _leaveNotebook(tester);
    expect(jsonDecode((await IsoDrawingDao().getById('spatial-sketch'))!.json),
        saved);
  });

  testWidgets(
      'narysowana rura wraca po zamknięciu i ponownym otwarciu zeszytu — '
      'nawet gdy wyjście nastąpiło przed autozapisem', (tester) async {
    await bootLauncher(tester);
    await _openNotebook(tester);
    expect(find.textContaining('Odcinki:'), findsNothing,
        reason: 'first ever open: empty sheet');

    await _drawPipe(tester);
    expect(find.text('Odcinki: 0/1'), findsOneWidget);

    // Straight back out, inside the 500 ms debounce: leaving has to flush.
    // No "leave without saving?" question any more — nothing is at risk.
    await _leaveNotebook(tester);
    expect(find.byType(AlertDialog), findsNothing);

    await _openNotebook(tester);
    expect(find.text('Odcinki: 0/1'), findsOneWidget,
        reason: 'the pipe drawn before leaving must come back');
  });

  testWidgets('autozapis po zmianie trafia do bazy bez wychodzenia z ekranu',
      (tester) async {
    await bootLauncher(tester);
    await _openNotebook(tester);
    await _drawPipe(tester);

    // Nothing written yet — the debounce is still running…
    expect(await IsoDrawingDao().latest(), isNull);
    // …and 500 ms after the last change the sketch is in the database.
    await tester.pump(const Duration(milliseconds: 600));
    final stored = await IsoDrawingDao().latest();
    expect(stored, isNotNull);
    final items = (jsonDecode(stored!.json) as Map)['items'] as List;
    expect(items.where((i) => (i as Map)['kind'] == 'seg'), hasLength(1));

    await _leaveNotebook(tester);
  });

  testWidgets('przejście aplikacji w tło zapisuje od razu', (tester) async {
    await bootLauncher(tester);
    await _openNotebook(tester);
    await _drawPipe(tester);
    expect(await IsoDrawingDao().latest(), isNull);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump();
    expect(await IsoDrawingDao().latest(), isNotNull,
        reason: 'the OS may kill a backgrounded app without another callback');

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    await _leaveNotebook(tester);
  });

  testWidgets(
      'zapisany szkic z wymiarem i kalkulatorem CUT wraca z tym samym CUT; '
      '„Nowy szkic” czyści, a stary da się otworzyć z listy', (tester) async {
    await IsoDrawingDao().upsert(IsoDrawingRecord(
      id: 'stored-sketch',
      name: '6"-CWS-1234 — linia zażółcona',
      json: jsonEncode(representativeIsoSketch()),
      createdAt: 1000,
      updatedAt: 1000,
    ));

    await bootLauncher(tester);
    await _openNotebook(tester);
    final cutText =
        'Suma CUT: ${kRepresentativeIsoSketchCutMm.toStringAsFixed(1)} mm';
    expect(find.text('Odcinki: 1/1'), findsOneWidget);
    expect(find.text(cutText), findsOneWidget);
    expect(find.text('6"-CWS-1234 — linia zażółcona'), findsOneWidget,
        reason: 'the drawing name is part of the sketch');

    // „Nowy szkic” — asks first, then clears.
    await tester.tap(find.byIcon(Icons.folder_open_outlined));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Nowy szkic'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, 'Nowy szkic'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Odcinki:'), findsNothing);
    expect(find.text(cutText), findsNothing);

    // Reopening shows the NEW (empty) sketch, not the previous one…
    await _leaveNotebook(tester);
    await _openNotebook(tester);
    expect(find.textContaining('Odcinki:'), findsNothing);

    // …and the previous one is one tap away, intact.
    await tester.tap(find.byIcon(Icons.folder_open_outlined));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Zapisane szkice…'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('6"-CWS-1234 — linia zażółcona').last);
    await tester.pumpAndSettle();
    expect(find.text('Odcinki: 1/1'), findsOneWidget);
    expect(find.text(cutText), findsOneWidget);

    // The stored original was never rewritten along the way.
    final original = await IsoDrawingDao().getById('stored-sketch');
    expect(jsonDecode(original!.json), representativeIsoSketch());

    await _leaveNotebook(tester);
  });
}
