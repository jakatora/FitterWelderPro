import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:cut_list_app/services/account_service.dart';
// Zeszyt ISO na prawdziwym ekranie: okno wymiaru przy kołnierzu (punkt
// odniesienia widoczny i opisany słowami, domyślnie jak w kreatorze),
// nieczytelny wiersz odliczenia blokuje OK, pinch-zoom na płótnie i pasek
// narzędzi 48 dp. Przypadki z przeglądu G3 (sondy A i G).

import 'dart:convert';

import 'package:flutter/gestures.dart';
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

/// DN100 elbow (CTE 152) at x = 64, weld-neck flange (Y 76) at x = 192, one
/// pipe between them: ISO 1000, gap 3 — a dimension typed before the
/// per-end choice existed, with the old default "centre–centre".
Map<String, Object?> _sketch({List<Object?> deducts = const []}) =>
    <String, Object?>{
      'format': 2,
      'name': 'WN-1',
      'gapMm': 3,
      'items': <Object?>[
        <String, Object?>{
          'kind': 'seg',
          'tool': 'pipe',
          'a': <double>[64.0, isoRow4],
          'b': <double>[192.0, isoRow4],
          'slope': '',
          'insulated': false,
          'calc': <String, Object?>{
            'iso': '1000',
            'ref': 'centreToCentre',
            'deducts': deducts,
          },
        },
        <String, Object?>{
          'kind': 'comp',
          'tool': 'elbow90',
          'pos': <double>[64.0, isoRow4],
          'dir': 0,
          'dir2': 4,
          'label': '',
          'dn': 100,
          'elbowSubtype': 'lr90',
          'cteMm': 152,
          'physicalLengthMm': null,
          'dnOut': null,
          'endA': null,
          'endB': null,
        },
        <String, Object?>{
          'kind': 'comp',
          'tool': 'flange',
          'pos': <double>[192.0, isoRow4],
          'dir': 0,
          'dir2': null,
          'label': 'DN100 · WN',
          'dn': 100,
          'elbowSubtype': null,
          'cteMm': null,
          'physicalLengthMm': 76,
          'dnOut': null,
          'endA': 'weldNeck',
          'endB': 'none',
        },
      ],
      'takeoutMemory': <String, Object?>{
        'values': <Object?>[],
        'lastDn': <String, Object?>{},
      },
    };

void main() {
  setUpAll(() async {
    // Resolve the guest identity outside the widget fake-async clock.
    FlutterSecureStorage.setMockInitialValues({});
    await AccountService.instance.load();
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

  Future<void> boot(WidgetTester tester, Map<String, Object?> sketch) async {
    await IsoDrawingDao().upsert(IsoDrawingRecord(
      id: 'sketch-1',
      name: sketch['name']! as String,
      json: jsonEncode(sketch),
      createdAt: 1000,
      updatedAt: 1000,
    ));
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(_launcher());
    await tester.pumpAndSettle();
    await tester.tap(find.text(_openButton));
    await tester.pumpAndSettle();
  }

  Finder canvas() => find.byWidgetPredicate((w) =>
      w is Semantics &&
      (w.properties.label?.startsWith('Płótno szkicu izometrycznego') ??
          false));

  Future<void> openDimension(WidgetTester tester) async {
    await tester.tapAt(tester.getTopLeft(canvas()) + Offset(128, isoRow4));
    await tester.pumpAndSettle();
    expect(find.text('Wymiar / cięcie odcinka'), findsOneWidget);
  }

  testWidgets(
      'kolano → kołnierz WN: stary wymiar „oś-oś” jest oznaczony, okno '
      'proponuje przylgę (−Y) słowami, OK daje 1000 − 152 − 76 − 6 = 766',
      (tester) async {
    await boot(tester, _sketch());
    // Before: the old default, 76 mm long, and flagged as unconfirmed.
    expect(find.text('Suma CUT: 842.0 mm'), findsOneWidget);

    await openDimension(tester);
    expect(find.byKey(const ValueKey('iso-stop-picker')), findsOneWidget,
        reason: 'wybór widoczny, nie w „Opcjach zaawansowanych”');
    expect(find.text('Dokąd biegnie wymiar z rysunku?'), findsOneWidget);
    expect(find.textContaining('nie miał wybranego punktu odniesienia'),
        findsOneWidget);
    expect(find.text('do przylgi kołnierza (odejmuje szyjkę Y)'),
        findsOneWidget);
    expect(find.text('do spoiny kołnierza (koniec szyjki, bez Y)'),
        findsOneWidget);
    // No bare codes any more.
    expect(find.text('CTE'), findsNothing);
    expect(find.text('CTC'), findsNothing);
    // Each choice shows its CUT (the chosen one on both ends); the live
    // headline is the default's.
    expect(find.text('CUT 766.0'), findsNWidgets(2));
    expect(find.text('CUT 842.0'), findsOneWidget);
    expect(find.text('CUT 918.0'), findsOneWidget,
        reason: 'kolano do końca zamiast do osi: +152');
    expect(find.text('do osi kształtki'), findsOneWidget);
    expect(find.text('766.0 mm'), findsOneWidget);

    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect(find.text('Suma CUT: 766.0 mm'), findsOneWidget);

    // Saved with the stops (format 3).
    await tester.pump(const Duration(milliseconds: 600));
    final doc =
        jsonDecode((await IsoDrawingDao().getById('sketch-1'))!.json) as Map;
    expect(doc['format'], 3);
    final calc = ((doc['items'] as List).first as Map)['calc'] as Map;
    expect(calc['stopA'], 'centre');
    expect(calc['stopB'], 'end');
    expect(calc['ref'], 'centreToEnd');
  });

  testWidgets('„do spoiny kołnierza” wybrane świadomie: 842', (tester) async {
    await boot(tester, _sketch());
    await openDimension(tester);
    await tester.tap(find.text('do spoiny kołnierza (koniec szyjki, bez Y)'));
    await tester.pumpAndSettle();
    expect(find.text('842.0 mm'), findsOneWidget);
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect(find.text('Suma CUT: 842.0 mm'), findsOneWidget);
  });

  testWidgets(
      'nieczytelny wiersz odliczenia „3+” blokuje OK i nie daje cięcia '
      '(sonda A)', (tester) async {
    await boot(
        tester,
        _sketch(deducts: <Object?>[
          <String, Object?>{'name': 'Uszczelka', 'value': '3'},
        ]));
    await openDimension(tester);
    final byText = find.byWidgetPredicate(
        (w) => w is TextField && w.controller?.text == '3');
    expect(byText, findsOneWidget);
    final ctrl = tester.widget<TextField>(byText).controller!;
    final row = find.byWidgetPredicate(
        (w) => w is TextField && identical(w.controller, ctrl));
    await tester.enterText(row, '3+');
    await tester.pumpAndSettle();
    expect(find.text('nieczytelne'), findsOneWidget);
    expect(find.textContaining('Nieczytelny wiersz odliczenia'),
        findsOneWidget);
    final ok = tester.widget<ElevatedButton>(
        find.widgetWithText(ElevatedButton, 'OK'));
    expect(ok.onPressed, isNull, reason: 'nie wolno zapisać wiersza po cichu');

    // Fixed → OK again: 1000 − 152 − 76 − 6 − 3 = 763.
    await tester.enterText(row, '3');
    await tester.pumpAndSettle();
    expect(find.text('763.0 mm'), findsOneWidget);
    expect(
        tester
            .widget<ElevatedButton>(find.widgetWithText(ElevatedButton, 'OK'))
            .onPressed,
        isNotNull);
  });

  testWidgets('pasek narzędzi: każdy przycisk ma co najmniej 48 dp',
      (tester) async {
    await boot(tester, _sketch());
    for (final label in ['Rura', 'Kolano 90°', 'Trójnik', 'Kołnierz']) {
      final chip = find.byWidgetPredicate((w) =>
          w is Semantics &&
          w.properties.label == label &&
          (w.properties.button ?? false));
      expect(chip, findsOneWidget, reason: label);
      expect(tester.getSize(chip).height, greaterThanOrEqualTo(48),
          reason: label);
    }
  });

  testWidgets('pinch dwoma palcami przybliża płótno i nie rysuje linii',
      (tester) async {
    await boot(tester, _sketch());
    double scale() {
      final paint = tester.widget<CustomPaint>(find
          .descendant(of: canvas(), matching: find.byType(CustomPaint))
          .first);
      return (paint.painter as dynamic).viewScale as double;
    }

    expect(scale(), 1.0);
    final centre = tester.getCenter(canvas());
    final g1 = await tester.startGesture(centre - const Offset(40, 0),
        pointer: 7, kind: PointerDeviceKind.touch);
    final g2 = await tester.startGesture(centre + const Offset(40, 0),
        pointer: 8, kind: PointerDeviceKind.touch);
    for (var i = 1; i <= 10; i++) {
      await g1.moveBy(const Offset(-8, 0));
      await g2.moveBy(const Offset(8, 0));
      await tester.pump();
    }
    await g1.up();
    await g2.up();
    await tester.pumpAndSettle();
    expect(scale(), greaterThan(1.5));
    // Still exactly one pipe on the sheet — the pinch drew nothing.
    expect(find.textContaining('Suma CUT'), findsOneWidget);
  });
}
