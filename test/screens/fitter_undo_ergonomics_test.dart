// Ekran projektu i kreator: Cofnij usunięcia, etykiety ze skanu, cele dotyku.
//
// Było: usunięcie segmentu „nie do cofnięcia”; kształtka ze skanu miała
// etykietę „OPEN END/LOGICAL”; każde przeładowanie zamieniało listę na
// spinner; X na chipie sekwencji to ikona 14 px, paleta ok. 34 dp, etykiety
// diagramu 7–10 px.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cut_list_app/database/project_dao.dart';
import 'package:cut_list_app/database/segment_dao.dart';
import 'package:cut_list_app/i18n/app_language.dart';
import 'package:cut_list_app/models/project.dart';
import 'package:cut_list_app/screens/fitter_screen.dart';
import 'package:cut_list_app/screens/segment_builder_screen.dart';

import '../support/test_database.dart';

Widget _wrap(Widget child) => AppLanguageScope(
      controller: AppLanguageController(AppLanguage.en),
      child: MaterialApp(home: child),
    );

Future<void> _pumpUntil(WidgetTester tester, bool Function() done) async {
  for (var i = 0; i < 150 && !done(); i++) {
    await flushTestDatabase(tester);
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)));
    await tester.pump(const Duration(milliseconds: 50));
  }
}

Map<String, Object?> _scanSeg(String id, int seq) => {
      'id': id,
      'project_id': 'undo-proj',
      'seq_no': seq,
      'diameter_mm': 114.3,
      'wall_thickness_mm': 3.05,
      'start_kind': 'axial',
      'start_library_id': null,
      'start_value_mm': 152.4,
      'end_kind': 'nonAxial',
      'end_library_id': null,
      'end_value_mm': 0.0,
      'iso_ref': 'AXIS|FACE_NEAR',
      'iso_expr': '1000',
      'iso_mm': 1000.0,
      'cut_mm': 847.6,
      'created_at': 1,
      'updated_at': 1,
    };

void main() {
  useTestDatabase();

  testWidgets('segment ze skanu: etykiety kształtek; usunięcie z Cofnij',
      (tester) async {
    tester.view.physicalSize = const Size(1100, 2200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.runAsync(() async {
      await ProjectDao().insert(Project(
        id: 'undo-proj',
        name: 'Undo',
        materialGroup: 'SS',
        diameterMm: 114.3,
        wallThicknessMm: 3.05,
        currentDiameterMm: 114.3,
        stockLengthMm: 6000,
        sawKerfMm: 1,
        gapMm: 0,
        createdAt: 1,
        updatedAt: 1,
      ));
      await SegmentDao().insert(_scanSeg('undo-s1', 1));
      await SegmentDao().insert(_scanSeg('undo-s2', 2));
    });

    await tester.pumpWidget(_wrap(const FitterScreen(projectId: 'undo-proj')));
    await _pumpUntil(
        tester, () => find.textContaining('Seg. 2').evaluate().isNotEmpty);

    expect(find.textContaining('OPEN END'), findsNothing);
    expect(find.textContaining('Fitting (scan) → Component (scan)'),
        findsNWidgets(2));

    await tester.drag(find.textContaining('Seg. 2'), const Offset(-600, 0));
    await tester.pumpAndSettle();
    expect(find.textContaining('You can undo it'), findsOneWidget);
    await tester.tap(find.text('Delete'));
    await _pumpUntil(
        tester, () => find.text('Segment 2 deleted.').evaluate().isNotEmpty);
    expect(find.textContaining('Seg. 2'), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsNothing,
        reason: 'przeładowanie nie zamienia listy na spinner');

    await tester.pump(const Duration(milliseconds: 600)); // snackbar slides in
    await tester.tap(find.text('UNDO'));
    await _pumpUntil(
        tester, () => find.textContaining('Seg. 2').evaluate().isNotEmpty);
    expect(find.textContaining('Seg. 2'), findsOneWidget);
    final segs =
        await tester.runAsync(() => SegmentDao().listForProject('undo-proj'));
    expect(segs!.map((s) => (s.id, s.seqNo)), [('undo-s1', 1), ('undo-s2', 2)]);

    final project =
        await tester.runAsync(() => ProjectDao().getById('undo-proj'));
    expect(project!.updatedAt, greaterThan(1),
        reason: 'praca w projekcie podbija go na liście projektów');

    await tester.runAsync(() => ProjectDao().deleteById('undo-proj'));
    await tester.pump(const Duration(seconds: 7));
  });

  testWidgets('kreator: paleta i X na chipie ≥ 48 dp', (tester) async {
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(_wrap(const SegmentBuilderScreen(
      materialGroup: 'SS',
      currentDiameter: 60.3,
      wallThickness: 2.77,
      gapMm: 0,
    )));
    await tester.pumpAndSettle();

    for (final label in ['Elbow 90', 'Pipe', 'Reducer', 'Open end']) {
      final button = find
          .ancestor(of: find.text(label), matching: find.byType(InkWell))
          .first;
      expect(tester.getSize(button).height, greaterThanOrEqualTo(48),
          reason: label);
    }

    final openEnd = find
        .ancestor(of: find.text('Open end'), matching: find.byType(InkWell))
        .first;
    await tester.tap(openEnd);
    await tester.pumpAndSettle();
    final remove = find.byTooltip('Remove item');
    expect(remove, findsOneWidget);
    expect(tester.getSize(remove).height, greaterThanOrEqualTo(48));
    expect(tester.getSize(remove).width, greaterThanOrEqualTo(48));
  });
}
