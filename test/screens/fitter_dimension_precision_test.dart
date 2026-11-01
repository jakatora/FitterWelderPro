import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cut_list_app/database/db.dart';
import 'package:cut_list_app/i18n/app_language.dart';
import 'package:cut_list_app/screens/fitter_screen.dart';
import '../support/test_account.dart';
import '../support/test_database.dart';

void main() {
  useTestDatabase();
  useGuestAccount();
  for (final lang in AppLanguage.values) {
    testWidgets('stored pipe dimensions are not rounded in titles: $lang',
        (tester) async {
      await tester.runAsync(() async {
        final db = await AppDatabase.get();
        await db.delete('segments');
        await db.delete('projects');
        await insertTestProject('precision');
        await db.update(
            'projects',
            {
              'diameter_mm': 60.325,
              'current_diameter_mm': 60.325,
              'wall_thickness_mm': 2.77,
              'gap_mm': 0.25,
            },
            where: 'id = ?',
            whereArgs: ['precision']);
        await db.insert('segments', {
          'id': 'precise-segment',
          'project_id': 'precision',
          'seq_no': 1,
          'diameter_mm': 60.325,
          'wall_thickness_mm': 2.77,
          'start_kind': 'logical',
          'start_value_mm': 0,
          'end_kind': 'logical',
          'end_value_mm': 0,
          'iso_ref': 'OPEN|FACE_NEAR',
          'iso_expr': '1000',
          'iso_mm': 1000,
          'cut_mm': 1000,
          'created_at': 1,
          'updated_at': 1,
        });
      });
      await tester.pumpWidget(AppLanguageScope(
        controller: AppLanguageController(lang),
        child: const MaterialApp(home: FitterScreen(projectId: 'precision')),
      ));
      for (var i = 0; i < 12; i++) {
        await flushTestDatabase(tester);
        await tester.pump(const Duration(milliseconds: 50));
      }
      await tester.pumpAndSettle();
      expect(find.text('Ø60.325 | t=2.77 | gap 0.25'), findsOneWidget);
      expect(find.textContaining('Ø60.325 × t 2.77'), findsOneWidget);
      expect(find.textContaining('Ø60.325 × t2.77'), findsOneWidget);
      expect(find.textContaining('t=2.8'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });
  }
}
