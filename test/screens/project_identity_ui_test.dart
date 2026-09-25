// Identyfikacja projektu (schemat v22) w UI: lista projektów pokazuje nr
// linii / ISO pod nazwą i ma wyszukiwarkę; okno „Ustawienia projektu”
// i formularz nowego projektu zapisują linię, ISO, rewizję, klienta, klasę.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cut_list_app/database/project_dao.dart';
import 'package:cut_list_app/i18n/app_language.dart';
import 'package:cut_list_app/models/project.dart';
import 'package:cut_list_app/screens/projects_screen.dart';

import '../support/test_database.dart';

Widget _wrap(Widget child) => AppLanguageScope(
      controller: AppLanguageController(AppLanguage.pl),
      child: MaterialApp(home: child),
    );

Future<void> _pumpUntil(WidgetTester tester, bool Function() done) async {
  for (var i = 0; i < 100 && !done(); i++) {
    await flushTestDatabase(tester);
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)));
    await tester.pump(const Duration(milliseconds: 50));
  }
}

Project _project(String id, String name,
        {String? line, String? iso, String? rev, String? client}) =>
    Project(
      id: id,
      name: name,
      materialGroup: 'SS',
      diameterMm: 60.3,
      wallThicknessMm: 2,
      currentDiameterMm: 60.3,
      stockLengthMm: 6000,
      sawKerfMm: 1,
      gapMm: 0,
      createdAt: 1,
      updatedAt: 1,
      lineNo: line,
      isoNo: iso,
      isoRev: rev,
      client: client,
    );

Finder _field(String label) => find.byWidgetPredicate(
      (w) => w is TextField && w.decoration?.labelText == label,
      description: 'TextField "$label"',
    );

void main() {
  useTestDatabase();

  void tall(WidgetTester tester) {
    tester.view.physicalSize = const Size(1100, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
  }

  testWidgets('lista: linia / ISO pod nazwą, wyszukiwarka po linii, ISO, kliencie',
      (tester) async {
    tall(tester);
    final dao = ProjectDao();
    await tester.runAsync(() async {
      await dao.insert(_project('ui-a', 'Hala A',
          line: 'DN100-CWS-1234', iso: 'ISO-7', rev: 'B', client: 'Orlen'));
      await dao.insert(_project('ui-b', 'Hala B', line: 'DN50-STM-0001'));
      await dao.insert(_project('ui-c', 'Rack bez rysunku'));
    });

    await tester.pumpWidget(_wrap(const ProjectsScreen()));
    await _pumpUntil(tester, () => find.text('Hala A').evaluate().isNotEmpty);

    expect(find.textContaining('DN100-CWS-1234 · ISO-7 rew. B'), findsOneWidget);
    expect(find.textContaining('DN50-STM-0001'), findsOneWidget);

    final search = find.byKey(const ValueKey('projects-search'));
    await tester.enterText(search, 'cws-1234');
    await tester.pump();
    expect(find.text('Hala A'), findsOneWidget);
    expect(find.text('Hala B'), findsNothing);
    expect(find.text('Rack bez rysunku'), findsNothing);

    await tester.enterText(search, 'ISO-7');
    await tester.pump();
    expect(find.text('Hala A'), findsOneWidget);
    expect(find.text('Hala B'), findsNothing);

    await tester.enterText(search, 'orlen');
    await tester.pump();
    expect(find.text('Hala A'), findsOneWidget);

    await tester.enterText(search, 'rack');
    await tester.pump();
    expect(find.text('Rack bez rysunku'), findsOneWidget);
    expect(find.text('Hala A'), findsNothing);

    await tester.enterText(search, 'nic-takiego');
    await tester.pump();
    expect(find.textContaining('Brak projektów pasujących'), findsOneWidget);

    await tester.tap(find.byTooltip('Wyczyść'));
    await tester.pump();
    expect(find.text('Hala A'), findsOneWidget);
    expect(find.text('Hala B'), findsOneWidget);

    await tester.runAsync(() async {
      for (final id in ['ui-a', 'ui-b', 'ui-c']) {
        await dao.deleteById(id);
      }
    });
  });

  testWidgets('Ustawienia projektu: linia, ISO, rewizja, klient, klasa',
      (tester) async {
    tall(tester);
    final dao = ProjectDao();
    await tester.runAsync(() => dao.insert(
        _project('ui-set', 'Linia 7', line: 'L-7', iso: 'ISO-1', rev: 'A')));

    await tester.pumpWidget(_wrap(const ProjectsScreen()));
    await _pumpUntil(tester, () => find.text('Linia 7').evaluate().isNotEmpty);

    await tester.tap(find.byTooltip('Ustawienia projektu'));
    await tester.pumpAndSettle();

    expect(tester.widget<TextField>(_field('Nr linii')).controller!.text, 'L-7');
    expect(tester.widget<TextField>(_field('Nr ISO (rysunku)')).controller!.text,
        'ISO-1');
    expect(tester.widget<TextField>(_field('Rewizja')).controller!.text, 'A');

    await tester.enterText(_field('Rewizja'), 'B');
    await tester.enterText(_field('Klient'), ' Orlen ');
    await tester.enterText(_field('Klasa rurociągu'), 'A1B');
    await tester.enterText(_field('Nr linii'), '');

    await tester.tap(find.text('Zapisz'));
    await _pumpUntil(
        tester, () => find.text('Ustawienia projektu').evaluate().isEmpty);

    final p = await tester.runAsync(() => dao.getById('ui-set'));
    expect(p!.isoRev, 'B');
    expect(p.client, 'Orlen');
    expect(p.spec, 'A1B');
    expect(p.isoNo, 'ISO-1');
    expect(p.lineNo, isNull, reason: 'cleared in the dialog');

    await tester.runAsync(() => dao.deleteById('ui-set'));
    await tester.pump(const Duration(seconds: 7));
  });

  testWidgets('nowy projekt zapisuje identyfikację z rysunku', (tester) async {
    tall(tester);
    await tester.pumpWidget(_wrap(const ProjectsScreen()));
    await _pumpUntil(tester, () => find.byTooltip('Nowy projekt').evaluate().isNotEmpty);
    await tester.tap(find.byTooltip('Nowy projekt').first);
    await tester.pumpAndSettle();

    final name = 'UI-NEW-${DateTime.now().microsecondsSinceEpoch}';
    await tester.enterText(_field('Nazwa (opcjonalnie)'), name);
    await tester.enterText(_field('Nr linii'), 'DN80-W-0042');
    await tester.enterText(_field('Nr ISO (rysunku)'), 'ISO-42');
    await tester.enterText(_field('Rewizja'), 'C');
    await tester.enterText(_field('Klient'), 'Grupa Azoty');
    await tester.enterText(_field('Klasa rurociągu'), 'B2');
    await tester.enterText(_field('Średnica rury (mm)'), '88.9');
    await tester.enterText(_field('Grubość ścianki (mm)'), '3,2');

    final create = find.text('Utwórz projekt');
    await tester.ensureVisible(create);
    await tester.pumpAndSettle();
    await tester.tap(create);

    Project? saved;
    for (var i = 0; i < 100 && saved == null; i++) {
      await flushTestDatabase(tester);
      saved = await tester.runAsync<Project?>(() async =>
          (await ProjectDao().listAll())
              .where((p) => p.name == name)
              .firstOrNull);
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(saved, isNotNull);
    expect(
        saved!.identity,
        const ProjectIdentity(
          lineNo: 'DN80-W-0042',
          isoNo: 'ISO-42',
          isoRev: 'C',
          client: 'Grupa Azoty',
          spec: 'B2',
        ));
    expect(saved.wallThicknessMm, 3.2);

    await tester.runAsync(() => ProjectDao().deleteById(saved!.id));
    await _pumpUntil(tester, () => false);
  });
}
