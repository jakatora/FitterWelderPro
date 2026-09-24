// Ustawienia projektu z listy projektów: przycisk „Ustawienia projektu” →
// dialog → zapis. Zmiana gapu 0 → 3 przelicza CUT zapisanego segmentu
// (kolano 152 → wolny koniec, ISO 1000): 1000 − 152 − 3 × 1 = 845.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cut_list_app/database/project_dao.dart';
import 'package:cut_list_app/database/segment_dao.dart';
import 'package:cut_list_app/i18n/app_language.dart';
import 'package:cut_list_app/models/project.dart';
import 'package:cut_list_app/screens/projects_screen.dart';

import '../support/test_database.dart';

Widget _wrap(Widget child) => AppLanguageScope(
      controller: AppLanguageController(AppLanguage.pl),
      child: MaterialApp(home: child),
    );

Future<void> _pumpUntil(WidgetTester tester, bool Function() done) async {
  for (var i = 0; i < 80 && !done(); i++) {
    await flushTestDatabase(tester);
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)));
    await tester.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  useTestDatabase();

  testWidgets('lista projektów → Ustawienia projektu → gap 3 przelicza CUT',
      (tester) async {
    tester.view.physicalSize = const Size(1100, 2200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final projects = ProjectDao();
    final segments = SegmentDao();
    const id = 'dialog-proj';
    await tester.runAsync(() async {
      await projects.insert(Project(
        id: id,
        name: 'Linia 12',
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
      await segments.insert({
        'id': 'dialog-seg',
        'project_id': id,
        'seq_no': 1,
        'diameter_mm': 114.3,
        'wall_thickness_mm': 3.05,
        'start_kind': 'axial',
        'start_library_id': 'lib-elb',
        'start_value_mm': 152.0,
        'end_kind': 'logical',
        'end_library_id': null,
        'end_value_mm': 0.0,
        'iso_ref': 'AXIS|OPEN',
        'iso_expr': '1000',
        'iso_mm': 1000.0,
        'cut_mm': 848.0,
        'created_at': 1,
        'updated_at': 1,
      });
    });

    await tester.pumpWidget(_wrap(const ProjectsScreen()));
    await _pumpUntil(tester, () => find.text('Linia 12').evaluate().isNotEmpty);
    expect(find.text('Linia 12'), findsOneWidget);

    await tester.tap(find.byTooltip('Ustawienia projektu'));
    await tester.pumpAndSettle();

    final gapField = find.widgetWithText(TextField, 'Gap (mm na spoinę)');
    expect(gapField, findsOneWidget);
    expect(tester.widget<TextField>(gapField).controller!.text, '0');
    expect(
        tester
            .widget<TextField>(
                find.widgetWithText(TextField, 'Długość sztangi (mm)'))
            .controller!
            .text,
        '6000');

    await tester.enterText(gapField, '3');
    await tester.pump();
    expect(find.textContaining('przeliczy CUT wszystkich segmentów'),
        findsOneWidget,
        reason: 'the fitter is told before saving what a gap change does');

    await tester.tap(find.text('Zapisz'));
    await _pumpUntil(
        tester, () => find.text('Ustawienia projektu').evaluate().isEmpty);

    final after = await tester.runAsync(() async => (
          project: await projects.getById(id),
          segs: await segments.listForProject(id),
        ));
    expect(after!.project!.gapMm, 3);
    expect(after.segs.single.cutMm, 845, reason: '1000 − 152 − 3 × 1');
    expect(find.textContaining('przeliczono CUT 1 segmentów'), findsOneWidget);

    await tester.runAsync(() => projects.deleteById(id));
    await tester.pump(const Duration(seconds: 7));
  });
}
