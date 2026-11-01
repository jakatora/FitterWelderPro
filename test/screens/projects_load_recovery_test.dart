import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cut_list_app/database/db.dart';
import 'package:cut_list_app/i18n/app_language.dart';
import 'package:cut_list_app/screens/projects_screen.dart';
import '../support/test_database.dart';
import '../support/test_account.dart';

Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await flushTestDatabase(tester);
    await tester.pump(const Duration(milliseconds: 50));
  }
  await tester.pumpAndSettle();
}

void main() {
  useTestDatabase();
  useGuestAccount();
  for (final lang in AppLanguage.values) {
    testWidgets(
        'project read failure can be retried without losing data: $lang',
        (tester) async {
      var renamed = false;
      final id = 'recovery-${lang.name}';
      final retry = lang == AppLanguage.pl ? 'Ponów' : 'Retry';
      await tester.runAsync(() async {
        final db = await AppDatabase.get();
        await db.delete('projects');
        await insertTestProject(id);
        await db.execute('ALTER TABLE projects RENAME TO fixture_projects');
        renamed = true;
      });
      try {
        await tester.pumpWidget(AppLanguageScope(
          controller: AppLanguageController(lang),
          child: const MaterialApp(home: ProjectsScreen()),
        ));
        await settle(tester);
        expect(tester.takeException(), isNull);
        expect(find.text(retry), findsOneWidget);
        expect(find.textContaining('no such table'), findsNothing);
        // A second failure remains recoverable; it cannot become an empty list.
        await tester.tap(find.text(retry));
        await settle(tester);
        expect(tester.takeException(), isNull);
        expect(find.text(retry), findsOneWidget);
        await tester.runAsync(() async {
          await (await AppDatabase.get())
              .execute('ALTER TABLE fixture_projects RENAME TO projects');
          renamed = false;
        });
        await tester.tap(find.text(retry));
        await settle(tester);
        expect(find.text('Test $id'), findsOneWidget);
        expect(find.text(retry), findsNothing);
        expect(tester.takeException(), isNull);
      } finally {
        if (renamed) {
          await tester.runAsync(() async {
            await (await AppDatabase.get())
                .execute('ALTER TABLE fixture_projects RENAME TO projects');
          });
        }
        await tester.pumpWidget(const SizedBox.shrink());
        await settle(tester);
      }
    });
  }
}
