// ISO notebook → "Utwórz projekt CUT" and "Szczelina spoiny", driven through
// the real screen and real SQLite: the CUT the notebook shows, the CUT it
// writes into the project and the gap it keeps with the sketch.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:cut_list_app/database/db.dart';
import 'package:cut_list_app/database/iso_drawing_dao.dart';
import 'package:cut_list_app/database/project_dao.dart';
import 'package:cut_list_app/database/segment_dao.dart';
import 'package:cut_list_app/i18n/app_language.dart';
import 'package:cut_list_app/screens/fitter_screen.dart';
import 'package:cut_list_app/screens/iso_notebook_screen.dart';
import 'package:cut_list_app/widgets/iso_expression_keys.dart';

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

Map<String, Object?> _elbow(double x) => <String, Object?>{
      'kind': 'comp',
      'tool': 'elbow90',
      'pos': <double>[x, isoRow4],
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
    };

/// One DN100 pipe between two 90° LR elbows, ISO 2000 centre–centre, with a
/// 3 mm weld gap on the sketch: CUT = 2000 − 2×152 − 2×3 = 1690 mm.
Map<String, Object?> _sketch({double gap = 3}) => <String, Object?>{
      'format': gap > 0 ? 2 : 1,
      'name': '4"-CWS-2001',
      if (gap > 0) 'gapMm': gap,
      'items': <Object?>[
        <String, Object?>{
          'kind': 'seg',
          'tool': 'pipe',
          'a': <double>[64.0, isoRow4],
          'b': <double>[192.0, isoRow4],
          'slope': '',
          'insulated': false,
          'calc': <String, Object?>{
            'iso': '2000',
            'ref': 'centreToCentre',
            'deducts': <Object?>[],
          },
        },
        _elbow(64),
        _elbow(192),
      ],
      'takeoutMemory': <String, Object?>{
        'values': <Object?>[],
        'lastDn': <String, Object?>{},
      },
    };

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
    await db.delete('segments');
    await db.delete('projects');
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

  Future<void> openSketchMenu(WidgetTester tester) async {
    await tester.tap(find.byIcon(Icons.folder_open_outlined));
    await tester.pumpAndSettle();
  }

  testWidgets('szczelina ze szkicu odejmuje się raz na każdy spawany koniec',
      (tester) async {
    await boot(tester, _sketch());
    expect(find.text('Suma CUT: 1690.0 mm'), findsOneWidget);

    // Change the gap to 0 → the pre-gap number, 2000 − 304.
    await openSketchMenu(tester);
    await tester.tap(find.text('Szczelina spoiny: 3 mm…'));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byKey(const ValueKey('sketch-gap-field')), '0');
    await tester.tap(find.byKey(const ValueKey('sketch-gap-save')));
    await tester.pumpAndSettle();
    expect(find.text('Suma CUT: 1696.0 mm'), findsOneWidget);

    // …and 2,5 with the Polish comma → 2000 − 304 − 5.
    await openSketchMenu(tester);
    await tester.tap(find.text('Szczelina spoiny: 0 mm…'));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byKey(const ValueKey('sketch-gap-field')), '2,5');
    await tester.tap(find.byKey(const ValueKey('sketch-gap-save')));
    await tester.pumpAndSettle();
    expect(find.text('Suma CUT: 1691.0 mm'), findsOneWidget);

    // The gap is part of the sketch: autosaved with it.
    await tester.pump(const Duration(milliseconds: 600));
    final stored = await IsoDrawingDao().getById('sketch-1');
    final doc = jsonDecode(stored!.json) as Map;
    expect(doc['gapMm'], 2.5);
    expect(doc['format'], 2);

    await tester.pageBack();
    await tester.pumpAndSettle();
  });

  testWidgets(
      'utwórz projekt CUT: segment w bazie ma CUT zeszytu i gap szkicu, '
      'po utworzeniu otwiera się projekt', (tester) async {
    await boot(tester, _sketch());
    expect(find.text('Suma CUT: 1690.0 mm'), findsOneWidget);

    await openSketchMenu(tester);
    await tester.tap(find.text('Utwórz projekt CUT…'));
    await tester.pumpAndSettle();
    expect(find.text('Utwórz projekt CUT ze szkicu'), findsOneWidget);
    expect(find.textContaining('S01 ← R1'), findsOneWidget);
    expect(find.textContaining('CUT 1690.0 mm'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('sketch-project-create')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 500));

    final projects = await ProjectDao().listAll();
    expect(projects, hasLength(1));
    final project = projects.single;
    expect(project.name, '4"-CWS-2001');
    expect(project.gapMm, 3);
    expect(project.diameterMm, 114.3, reason: 'DN100 read off the elbows');
    final segs = await SegmentDao().listForProject(project.id);
    expect(segs, hasLength(1));
    expect(segs.single.cutMm, 1690);
    expect(segs.single.isoExpr, '2000');
    expect(find.byType(FitterScreen), findsOneWidget);
  });

  testWidgets('pole ISO zeszytu: klawiatura liczbowa + pasek operatorów',
      (tester) async {
    await boot(tester, _sketch(gap: 0));
    // Tap the dimensioned pipe (world = canvas-local coordinates at 1:1).
    final canvas = find.byWidgetPredicate((w) =>
        w is Semantics &&
        (w.properties.label?.startsWith('Płótno szkicu izometrycznego') ??
            false));
    await tester.tapAt(tester.getTopLeft(canvas) + Offset(128, isoRow4));
    await tester.pumpAndSettle();
    expect(find.text('Wymiar / cięcie odcinka'), findsOneWidget);

    final isoField = find.byWidgetPredicate((w) =>
        w is TextField && w.controller?.text == '2000');
    expect(isoField, findsOneWidget);
    final tf = tester.widget<TextField>(isoField);
    expect(tf.keyboardType,
        const TextInputType.numberWithOptions(decimal: true));
    expect(find.byType(IsoExpressionKeyBar), findsOneWidget);

    // The + key edits the ISO field; the live CUT follows.
    final ctrl = tf.controller!;
    final field = find.byWidgetPredicate(
        (w) => w is TextField && identical(w.controller, ctrl));
    await tester.tap(find.byKey(const ValueKey('iso-key-+')));
    await tester.pumpAndSettle();
    expect(ctrl.text, '2000+');
    await tester.enterText(field, '2000+100');
    await tester.pumpAndSettle();
    expect(find.text('1796.0 mm'), findsOneWidget);
  });
}
