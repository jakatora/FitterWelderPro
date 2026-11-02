import 'package:cut_list_app/data/database_location_problem.dart';
import 'package:cut_list_app/screens/database_recovery_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('choice requires confirmation and passes the selected database',
      (tester) async {
    String? chosen;
    List<String>? acknowledged;
    await tester.pumpWidget(MaterialApp(
      theme: ThemeData(splashFactory: NoSplash.splashFactory),
      home: DatabaseRecoveryScreen(
        problem: const DatabaseLocationProblem(
            candidates: ['C:/first', 'C:/second']),
        onSelect: (path, candidates) async {
          chosen = path;
          acknowledged = candidates;
        },
      ),
    ));
    await tester.tap(find.text('Użyj tej bazy / Use this database').first);
    await tester.pumpAndSettle();
    expect(chosen, isNull);
    await tester.tap(find.text('Anuluj / Cancel'));
    await tester.pumpAndSettle();
    expect(chosen, isNull);
    await tester.tap(find.text('Użyj tej bazy / Use this database').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Wybierz / Select'));
    await tester.pumpAndSettle();
    expect(chosen, 'C:/second');
    expect(acknowledged, ['C:/first', 'C:/second']);
  });

  testWidgets('a moved database can be located without using a different file',
      (tester) async {
    String? selected;
    var file = r'C:\Moved\unrelated.db';
    await tester.pumpWidget(MaterialApp(
      theme: ThemeData(splashFactory: NoSplash.splashFactory),
      home: DatabaseRecoveryScreen(
        problem:
            const DatabaseLocationProblem(candidates: [], missing: r'C:\Old'),
        pickFile: () async => file,
        onSelect: (path, candidates) async => selected = path,
      ),
    ));
    await tester.tap(find.text('Znajdź plik bazy / Find database file'));
    await tester.pumpAndSettle();
    expect(find.text('Wybierz plik cutlist.db. / Select the cutlist.db file.'),
        findsOneWidget);
    expect(selected, isNull);
    file = r'C:\Moved\cutlist.db';
    await tester.tap(find.text('Znajdź plik bazy / Find database file'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Wybierz / Select'));
    await tester.pumpAndSettle();
    expect(selected, r'C:\Moved');
  });
}
