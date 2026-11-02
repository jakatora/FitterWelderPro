// Po „Utwórz projekt” monter ląduje od razu W projekcie (ekran segmentów),
// a nie z powrotem na liście, gdzie musiałby go jeszcze raz wyszukać i
// otworzyć — z nowym projektem zawsze robi się to samo: dodaje pierwszy
// segment.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cut_list_app/database/project_dao.dart';
import 'package:cut_list_app/i18n/app_language.dart';
import 'package:cut_list_app/models/project.dart';
import 'package:cut_list_app/screens/fitter_screen.dart';
import 'package:cut_list_app/screens/new_project_screen.dart';

import '../support/test_database.dart';

Object? _listResult;

/// Stands in for the project list: pushes the form and keeps its result, the
/// way ProjectsScreen reloads on `true`.
Widget _host({Future<void> Function(Project)? onCreate}) => AppLanguageScope(
      controller: AppLanguageController(AppLanguage.en),
      child: MaterialApp(
        home: Builder(
          builder: (ctx) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () async {
                  _listResult = await Navigator.push(
                    ctx,
                    MaterialPageRoute(
                        builder: (_) => NewProjectScreen(onCreate: onCreate)),
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
    await tester
        .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
    await tester.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  useTestDatabase();

  testWidgets('pending project save prevents editing or leaving the form',
      (tester) async {
    tester.view.physicalSize = const Size(1100, 2200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final release = Completer<void>();
    await tester.pumpWidget(_host(onCreate: (_) => release.future));
    await tester.tap(find.text('list'));
    await tester.pumpAndSettle();
    await tester.enterText(_field('Name (optional)'), 'Pending project');
    await tester.enterText(_field('Pipe diameter (mm)'), '60.3');
    await tester.enterText(_field('Wall thickness (mm)'), '2.77');
    addTearDown(() async {
      if (!release.isCompleted) release.complete();
    });
    await tester.ensureVisible(find.text('Create project'));
    await tester.tap(find.text('Create project'));
    await tester.pump();
    expect(find.text('Saving...'), findsOneWidget);
    expect(tester.widget<TextField>(_field('Pipe diameter (mm)')).enabled,
        isFalse);
    await tester.binding.handlePopRoute();
    await tester.pump();
    expect(find.byType(NewProjectScreen), findsOneWidget);
    release.complete();
    await _pumpUntil(
        tester, () => find.byType(FitterScreen).evaluate().isNotEmpty);
    expect(find.byType(FitterScreen), findsOneWidget);
  });

  testWidgets('failed project save restores editable draft', (tester) async {
    tester.view.physicalSize = const Size(1100, 2200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final pending = Completer<void>();
    await tester.pumpWidget(_host(onCreate: (_) => pending.future));
    await tester.tap(find.text('list'));
    await tester.pumpAndSettle();
    await tester.enterText(_field('Name (optional)'), 'Saved draft');
    await tester.enterText(_field('Pipe diameter (mm)'), '60.3');
    await tester.enterText(_field('Wall thickness (mm)'), '2.77');
    await tester.ensureVisible(find.text('Create project'));
    await tester.tap(find.text('Create project'));
    await tester.pump();
    pending.completeError(Exception('fixture failure'));
    await tester.pumpAndSettle();
    expect(find.byType(NewProjectScreen), findsOneWidget);
    expect(
        tester.widget<TextField>(_field('Pipe diameter (mm)')).enabled, isTrue);
    expect(tester.widget<TextField>(_field('Name (optional)')).controller!.text,
        'Saved draft');
    expect(
        tester
            .widget<TextField>(_field('Wall thickness (mm)'))
            .controller!
            .text,
        '2.77');
    expect(find.text('Could not save the project. Please try again.'),
        findsWidgets);
  });

  for (final wall in ['30.15', '40']) {
    testWidgets(
        'invalid pipe wall is not persisted and can be corrected: $wall',
        (tester) async {
      tester.view.physicalSize = const Size(1100, 2200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final name = 'Geometry-$wall-${DateTime.now().microsecondsSinceEpoch}';
      await tester.pumpWidget(_host());
      await tester.tap(find.text('list'));
      await tester.pumpAndSettle();
      await tester.enterText(_field('Name (optional)'), name);
      await tester.enterText(_field('Pipe diameter (mm)'), '60.3');
      await tester.enterText(_field('Wall thickness (mm)'), wall);
      final create = find.text('Create project');
      await tester.ensureVisible(create);
      await tester.runAsync(() async {
        await tester.tap(create);
        await tester.pump();
      });
      const error = 'Wall thickness must be less than half the pipe diameter.';
      await _pumpUntil(
          tester,
          () =>
              find.text(error).evaluate().isNotEmpty ||
              find.byType(FitterScreen).evaluate().isNotEmpty);
      final rows = await tester.runAsync(() => ProjectDao().listAll());
      expect(rows!.where((p) => p.name == name), isEmpty,
          reason: 'An impossible pipe must not be saved');
      expect(find.text(error), findsOneWidget);
      expect(
          tester.widget<TextField>(_field('Name (optional)')).controller!.text,
          name);
      expect(
          tester
              .widget<TextField>(_field('Pipe diameter (mm)'))
              .controller!
              .text,
          '60.3');
      await tester.enterText(_field('Wall thickness (mm)'), '2.77');
      await tester.ensureVisible(create);
      await tester.runAsync(() async {
        await tester.tap(create);
        await tester.pump();
      });
      await _pumpUntil(
          tester, () => find.byType(FitterScreen).evaluate().isNotEmpty);
      expect(find.byType(FitterScreen), findsOneWidget);
      final saved = await tester.runAsync(() => ProjectDao().listAll());
      final mine = saved!.where((p) => p.name == name).single;
      expect(mine.diameterMm, 60.3);
      expect(mine.wallThicknessMm, 2.77);
      await tester.runAsync(() => ProjectDao().deleteById(mine.id));
      await tester.pumpWidget(const SizedBox());
      expect(tester.takeException(), isNull);
    });
  }

  for (final submissions in [1, 2]) {
    testWidgets(
        'creation persists and opens one project: $submissions submissions',
        (tester) async {
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
      final submit = tester
          .widget<ElevatedButton>(
              find.ancestor(of: create, matching: find.byType(ElevatedButton)))
          .onPressed!;
      await tester.runAsync(() async {
        // A second callback can arrive before the disabled button rebuilds.
        for (var i = 0; i < submissions; i++) {
          submit();
        }
        await tester.pump();
      });
      // The name is also in the form's own text field, so wait for it in the
      // project screen's app bar — that only appears once the project loaded.
      final title =
          find.descendant(of: find.byType(AppBar), matching: find.text(name));
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
        final mine =
            (await dao.listAll()).where((p) => p.name == name).toList();
        expect(mine, hasLength(1),
            reason: 'Repeated clicks must not duplicate projects');
        for (final p in mine) {
          await dao.deleteById(p.id);
        }
      });
    });
  }
}
