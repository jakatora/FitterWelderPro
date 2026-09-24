// Po „Utwórz projekt” monter ląduje od razu W projekcie (ekran segmentów),
// a nie z powrotem na liście, gdzie musiałby go jeszcze raz wyszukać i
// otworzyć — z nowym projektem zawsze robi się to samo: dodaje pierwszy
// segment.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cut_list_app/database/project_dao.dart';
import 'package:cut_list_app/i18n/app_language.dart';
import 'package:cut_list_app/screens/fitter_screen.dart';
import 'package:cut_list_app/screens/new_project_screen.dart';

import '../support/test_database.dart';

Object? _listResult;

/// Stands in for the project list: pushes the form and keeps its result, the
/// way ProjectsScreen reloads on `true`.
Widget _host() => AppLanguageScope(
      controller: AppLanguageController(AppLanguage.en),
      child: MaterialApp(
        home: Builder(
          builder: (ctx) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () async {
                  _listResult = await Navigator.push(
                    ctx,
                    MaterialPageRoute(builder: (_) => const NewProjectScreen()),
                  );
                },
                child: const Text('list'),
              ),
            ),
          ),
        ),
      ),
    );

Finder _field(String label) => find.byWidgetPredicate(
      (w) => w is TextField && w.decoration?.labelText == label,
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

  testWidgets('utworzenie projektu otwiera ten projekt', (tester) async {
    tester.view.physicalSize = const Size(1100, 2200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final name = 'Nowy-${DateTime.now().microsecondsSinceEpoch}';
    await tester.pumpWidget(_host());
    await tester.tap(find.text('list'));
    await tester.pumpAndSettle();

    await tester.enterText(_field('Name (optional)'), name);
    await tester.enterText(_field('Pipe diameter (mm)'), '60.3');
    await tester.enterText(_field('Wall thickness (mm)'), '2.77');
    await tester.pump();

    final create = find.text('Create project');
    await tester.ensureVisible(create);
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      await tester.tap(create);
      await tester.pump();
    });
    // The name is also in the form's own text field, so wait for it in the
    // project screen's app bar — that only appears once the project loaded.
    final title = find.descendant(
        of: find.byType(AppBar), matching: find.text(name));
    await _pumpUntil(tester, () => title.evaluate().isNotEmpty);
    await tester.pumpAndSettle();

    expect(find.byType(FitterScreen), findsOneWidget,
        reason: 'a new project should open straight away, not drop the '
            'fitter back on the list');
    expect(title, findsOneWidget,
        reason: 'the project just created, not some other one');
    expect(find.byType(NewProjectScreen), findsNothing,
        reason: 'the form is replaced, so "back" goes to the list');
    expect(_listResult, isTrue,
        reason: 'the list still learns a project was created and reloads');

    final dao = ProjectDao();
    await tester.runAsync(() async {
      final mine = (await dao.listAll()).where((p) => p.name == name);
      for (final p in mine) {
        await dao.deleteById(p.id);
      }
    });
  });
}
