import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cut_list_app/database/db.dart';
import 'package:cut_list_app/database/project_dao.dart';
import 'package:cut_list_app/database/segment_dao.dart';
import 'package:cut_list_app/i18n/app_language.dart';
import 'package:cut_list_app/models/project.dart';
import 'package:cut_list_app/screens/fitter_screen.dart';
import 'package:cut_list_app/screens/segment_builder_screen.dart';
import '../support/test_database.dart';

Future<void> waitFor(WidgetTester t, bool Function() ready) async {
  for (var i = 0; i < 100 && !ready(); i++) {
    await flushTestDatabase(t);
    await t
        .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
    await t.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  useTestDatabase();
  for (final edit in [false, true]) {
    for (final failTouch in [false, true]) {
      testWidgets('failed save retains data: edit=$edit touch=$failTouch',
          (t) async {
        t.view.physicalSize = const Size(1200, 2400);
        t.view.devicePixelRatio = 1;
        addTearDown(t.view.reset);
        await t.runAsync(() async {
          await ProjectDao().insert(Project(
              id: 'recover-$edit-$failTouch',
              name: 'Recovery',
              materialGroup: 'SS',
              diameterMm: 60.3,
              wallThicknessMm: 2.77,
              currentDiameterMm: 60.3,
              stockLengthMm: 6000,
              sawKerfMm: 1,
              gapMm: 0,
              createdAt: 1,
              updatedAt: 1));
          if (edit) {
            await SegmentDao().insert({
              'id': 'recover-$edit-$failTouch-s1',
              'project_id': 'recover-$edit-$failTouch',
              'seq_no': 1,
              'diameter_mm': 60.3,
              'wall_thickness_mm': 2.77,
              'start_kind': 'logical',
              'start_library_id': null,
              'start_value_mm': 0,
              'end_kind': 'logical',
              'end_library_id': null,
              'end_value_mm': 0,
              'iso_ref': 'OPEN|OPEN',
              'iso_expr': '1000',
              'iso_mm': 1000,
              'cut_mm': 1000,
              'created_at': 1,
              'updated_at': 1
            });
          }
          final db = await AppDatabase.get();
          await db.execute(
              "CREATE TRIGGER fail_segment_save BEFORE ${failTouch ? 'UPDATE ON projects' : edit ? 'UPDATE ON segments' : 'INSERT ON segments'} BEGIN SELECT RAISE(FAIL, 'fixture save failed'); END");
        });
        addTearDown(() async {
          final db = await AppDatabase.get();
          await db.execute('DROP TRIGGER IF EXISTS fail_segment_save');
        });
        await t.pumpWidget(AppLanguageScope(
            controller: AppLanguageController(AppLanguage.en),
            child: MaterialApp(
                home: FitterScreen(projectId: 'recover-$edit-$failTouch'))));
        await waitFor(t,
            () => find.textContaining('Current route').evaluate().isNotEmpty);
        await t.tap(
            edit ? find.textContaining('Seg. 1') : find.text('Add segment'));
        await t.pumpAndSettle();
        if (!edit) {
          for (final label in ['Open end', 'Pipe', 'Open end']) {
            final button = find
                .ancestor(of: find.text(label), matching: find.byType(InkWell))
                .first;
            await t.ensureVisible(button);
            await t.tap(button);
            await t.pumpAndSettle();
          }
        }
        final saveLabel = edit ? 'Save changes' : 'Save segment';
        await t.enterText(find.byType(TextField), '1250');
        await t.pump();
        await t.ensureVisible(find.text(saveLabel));
        await t.tap(find.text(saveLabel));
        const error =
            'Could not save the segment. Your measurements are still here. Try again.';
        await waitFor(
            t,
            () =>
                find.text(error).evaluate().isNotEmpty ||
                find.byType(SegmentBuilderScreen).evaluate().isEmpty);
        expect(find.byType(SegmentBuilderScreen), findsOneWidget);
        expect(find.text(error), findsOneWidget);
        expect(t.widget<TextField>(find.byType(TextField)).controller!.text,
            '1250');
        final old = await t.runAsync(
            () => SegmentDao().listForProject('recover-$edit-$failTouch'));
        expect(old, hasLength(edit ? 1 : 0));
        if (edit) expect(old!.single.cutMm, 1000);
        await t.runAsync(() async {
          final db = await AppDatabase.get();
          await db.execute('DROP TRIGGER fail_segment_save');
        });
        await t.tap(find.text(saveLabel));
        await waitFor(
            t, () => find.byType(SegmentBuilderScreen).evaluate().isEmpty);
        expect(find.byType(SegmentBuilderScreen), findsNothing);
        final saved = await t.runAsync(
            () => SegmentDao().listForProject('recover-$edit-$failTouch'));
        expect(saved, hasLength(1));
        expect(saved!.single.cutMm, 1250);
        expect(
            (await t.runAsync(
                    () => ProjectDao().getById('recover-$edit-$failTouch')))!
                .updatedAt,
            greaterThan(1));
        await t.pumpWidget(const SizedBox());
        expect(t.takeException(), isNull);
      });
    }
  }
}
