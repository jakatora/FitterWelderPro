// Po przywróceniu kopii z nowszej wersji aplikacji część danych mogła nie
// wejść. Profil mówi o tym oknem, które czeka na potwierdzenie — nie
// snackbarem, który znika, zanim monter zdąży przeczytać.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cut_list_app/i18n/app_language.dart';
import 'package:cut_list_app/screens/profile_screen.dart';
import 'package:cut_list_app/services/data_backup.dart';

Future<void> _pumpWithButton(
    WidgetTester tester, RestoreReport report, AppLanguage lang) async {
  final controller = AppLanguageController(lang);
  addTearDown(controller.dispose);
  await tester.pumpWidget(AppLanguageScope(
    controller: controller,
    child: MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => showRestoreWarning(context, report),
            child: const Text('restore'),
          ),
        ),
      ),
    ),
  ));
  await tester.tap(find.text('restore'));
  await tester.pumpAndSettle();
}

void main() {
  final incomplete = RestoreReport(
    createdAt: DateTime(2026, 9, 24),
    databaseCount: 2,
    rowCount: 120,
    photoCount: 3,
    skippedTables: const [
      SkippedTable(database: 'cutlist.db', table: 'weld_map', rowCount: 7),
      SkippedTable(database: 'cutlist.db', table: 'empty_new', rowCount: 0),
    ],
    droppedColumns: const {
      'cutlist.db/segments': ['heat_no'],
    },
  );

  testWidgets('niepełne przywrócenie: okno z listą pominiętych danych (PL)',
      (tester) async {
    expect(incomplete.isComplete, isFalse);
    await _pumpWithButton(tester, incomplete, AppLanguage.pl);

    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.text('Przywrócono, ale nie wszystko'), findsOneWidget);
    expect(find.text(incomplete.warningPl!), findsOneWidget);
    expect(find.textContaining('weld_map (rekordy: 7)'), findsOneWidget);
    // Pusta pominięta tabela niczego nie traci — nie straszymy nią.
    expect(find.textContaining('empty_new'), findsNothing);

    await tester.tap(find.text('Rozumiem'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
  });

  testWidgets('niepełne przywrócenie po angielsku', (tester) async {
    await _pumpWithButton(tester, incomplete, AppLanguage.en);
    expect(find.text('Restored, but not everything'), findsOneWidget);
    expect(find.text(incomplete.warningEn!), findsOneWidget);
  });

  testWidgets('pełne przywrócenie: żadnego okna', (tester) async {
    final complete = RestoreReport(
      createdAt: DateTime(2026, 9, 24),
      databaseCount: 2,
      rowCount: 120,
      photoCount: 3,
    );
    expect(complete.isComplete, isTrue);
    await _pumpWithButton(tester, complete, AppLanguage.pl);
    expect(find.byType(AlertDialog), findsNothing);
  });
}
