// Ekran przeglądu skanu — wyniki „wszystko" (etap 4): zakładki cięć, spoin,
// materiałów i spooli; zapis częściowy (blokada tylko swojego cięcia, z
// potwierdzeniem, co NIE zostanie zapisane); „Utwórz wpisy w dzienniku
// spoin" przez WeldJournalDao, powiązane z projektem, status Oczekuje.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:cut_list_app/database/project_dao.dart';
import 'package:cut_list_app/database/segment_dao.dart';
import 'package:cut_list_app/database/weld_journal_dao.dart';
import 'package:cut_list_app/domain/weld_journal/weld_entry.dart';
import 'package:cut_list_app/i18n/app_language.dart';
import 'package:cut_list_app/screens/scan_review_screen.dart';
import 'package:cut_list_app/services/iso_scanner_ai.dart';

import '../support/test_database.dart';

Widget _wrap(Widget child) => AppLanguageScope(
      controller: AppLanguageController(AppLanguage.pl),
      child: MaterialApp(home: child),
    );

AiScanResult _scan({AiConfidence s2 = AiConfidence.high, String? drawing}) =>
    AiScanResult(
      schemaVersion: 2,
      sizeNotation: 'DN',
      titleBlock: AiTitleBlock(
        drawingNumber: drawing,
        lineNumber: 'DN100-CWS-1234',
        material: 'A312 TP304L',
        schedule: '10S',
      ),
      segments: [
        AiSegment(
          id: 's1',
          dimensionMm: 1500,
          rawDimension: '1500',
          toId: 'c1',
          confidence: AiConfidence.high,
        ),
        AiSegment(
          id: 's2',
          dimensionMm: 900,
          rawDimension: '900',
          fromId: 'c1',
          confidence: s2,
        ),
      ],
      components: [
        AiComponent(
          id: 'c1',
          type: 'elbow90',
          label: 'ELBOW 90 LR',
          confidence: AiConfidence.high,
        ),
      ],
      billOfMaterials: [
        AiBomItem(item: '1', description: 'PIPE', quantity: 2.3, unit: 'M',
            size: 'DN100'),
        AiBomItem(item: '2', description: 'ELBOW 90 LR', quantity: 1,
            size: 'DN100'),
      ],
    );

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 5; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> _pump(WidgetTester tester, Widget screen) async {
  tester.view.physicalSize = const Size(1100, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(_wrap(screen));
  await _settle(tester);
}

Finder _button(String text) => find
    .ancestor(
      of: find.text(text),
      matching: find.byWidgetPredicate((w) => w is ButtonStyleButton),
    )
    .first;

bool _enabled(WidgetTester tester, String text) =>
    tester.widget<ButtonStyleButton>(_button(text)).onPressed != null;

/// Taps [finder] with the database's real event loop available.
Future<void> _tapAsync(WidgetTester tester, Finder finder) async {
  await tester.runAsync(() async {
    await tester.tap(finder);
    await tester.pump();
    await Future<void>.delayed(const Duration(milliseconds: 300));
  });
  await _settle(tester);
}

Future<void> _drainCutList(WidgetTester tester) async {
  for (var i = 0; i < 40 && find.text('CUT LIST').evaluate().isEmpty; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
  for (var i = 0; i < 5; i++) {
    await tester.pump(const Duration(seconds: 3));
  }
}

void main() {
  useTestDatabase();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('zakładki: cięcia, spoiny, materiały, spoole', (tester) async {
    await _pump(tester, ScanReviewScreen(scan: _scan()));
    expect(find.text('Cięcia (2)'), findsOneWidget);
    expect(find.text('Spoiny (2)'), findsOneWidget);
    expect(find.text('Materiały'), findsOneWidget);
    expect(find.text('Spoole'), findsOneWidget);

    await tester.tap(find.text('Spoiny (2)'));
    await _settle(tester);
    expect(find.text('W-001'), findsOneWidget);
    expect(find.text('W-002'), findsOneWidget);
    expect(find.textContaining('OD 114.3 × 3.05'), findsWidgets);
    expect(_enabled(tester, 'Utwórz wpisy w dzienniku spoin'), isTrue);

    await tester.tap(find.text('Materiały'));
    await _settle(tester);
    expect(find.textContaining('Kolano 90°'), findsOneWidget);
    expect(find.textContaining('Rura'), findsOneWidget);

    await tester.tap(find.text('Spoole'));
    await _settle(tester);
    expect(find.textContaining('nie dzieli trasy na spoole'), findsOneWidget);
  });

  testWidgets('niepewne cięcie nie blokuje reszty: zapis 1 z 2 po potwierdzeniu',
      (tester) async {
    final name = 'SKAN-PART-${DateTime.now().microsecondsSinceEpoch}';
    await _pump(tester,
        ScanReviewScreen(scan: _scan(s2: AiConfidence.low), suggestedName: name));
    expect(find.textContaining('Te cięcia czekają na decyzję (1)'),
        findsOneWidget);
    expect(find.text('Zapiszę 1 z 2 cięć'), findsOneWidget);
    expect(_enabled(tester, 'Zapisz projekt'), isTrue);

    await tester.tap(_button('Zapisz projekt'));
    await _settle(tester);
    expect(find.text('Zapisać projekt?'), findsOneWidget);
    expect(find.textContaining('NIE zapiszę'), findsOneWidget);

    await _tapAsync(
        tester,
        find.descendant(
            of: find.byType(AlertDialog),
            matching: find.widgetWithText(FilledButton, 'Zapisz')));

    final saved = await tester.runAsync(() async {
      for (var i = 0; i < 60; i++) {
        final mine = (await ProjectDao().listAll())
            .where((p) => p.name == name)
            .toList();
        if (mine.isNotEmpty) {
          final segs = await SegmentDao().listForProject(mine.first.id);
          if (segs.isNotEmpty) return (id: mine.first.id, segments: segs);
        }
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
      return null;
    });
    expect(saved, isNotNull, reason: 'projekt nie został zapisany');
    expect(saved!.segments, hasLength(1));
    expect(saved.segments.single.seqNo, 1);
    expect(saved.segments.single.isoMm, 1500,
        reason: 'zapisane jest pewne cięcie, niepewne czeka');
    await _drainCutList(tester);
  });

  testWidgets('„Utwórz wpisy w dzienniku spoin": projekt + wpisy Oczekuje',
      (tester) async {
    final name = 'SKAN-WELD-${DateTime.now().microsecondsSinceEpoch}';
    final drawing = 'ISO-$name';
    await _pump(
        tester, ScanReviewScreen(scan: _scan(drawing: drawing), suggestedName: name));
    await tester.tap(find.text('Spoiny (2)'));
    await _settle(tester);

    await _tapAsync(tester, _button('Utwórz wpisy w dzienniku spoin'));
    expect(find.text('Zapisać projekt?'), findsOneWidget);
    expect(find.textContaining('Dziennik spoin: 2 nowych wpisów'),
        findsOneWidget);

    await _tapAsync(
        tester,
        find.descendant(
            of: find.byType(AlertDialog),
            matching: find.widgetWithText(FilledButton, 'Zapisz')));

    final entries = await tester.runAsync(() async {
      for (var i = 0; i < 60; i++) {
        final mine = (await WeldJournalDao().listAll())
            .where((e) => e.isoDrawing == drawing)
            .toList();
        if (mine.length == 2) return mine;
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
      return null;
    });
    expect(entries, isNotNull, reason: 'wpisy dziennika nie powstały');
    final project = await tester.runAsync(() async =>
        (await ProjectDao().listAll()).singleWhere((p) => p.name == name));
    for (final e in entries!) {
      expect(e.status, WeldStatus.pending);
      expect(e.projectId, project!.id);
      expect(e.projectName, name);
      expect(e.od, '114.3');
    }
    expect(entries.map((e) => e.weldNo).toSet(), {'W-001', 'W-002'});
    await _drainCutList(tester);
  });

  testWidgets(
      'v22: skan → zapis → linia / ISO / rewizja / klasa w projekcie, '
      'oznaczenia i spoole w segmentach', (tester) async {
    final name = 'SKAN-ID-${DateTime.now().microsecondsSinceEpoch}';
    final scan = AiScanResult(
      schemaVersion: 2,
      sizeNotation: 'DN',
      titleBlock: AiTitleBlock(
        drawingNumber: 'ISO-$name',
        revision: 'B',
        lineNumber: 'DN100-CWS-1234',
        pipeClass: 'A1B',
        material: 'A312 TP304L',
        schedule: '10S',
      ),
      segments: [
        AiSegment(
          id: 's1',
          dimensionMm: 1500,
          rawDimension: '1500',
          toId: 'c1',
          spoolId: 'SP2',
          confidence: AiConfidence.high,
        ),
        AiSegment(
          id: 's2',
          dimensionMm: 900,
          rawDimension: '900',
          fromId: 'c1',
          spoolId: 'SP2',
          confidence: AiConfidence.high,
        ),
      ],
      components: [
        AiComponent(
          id: 'c1',
          type: 'elbow90',
          label: 'ELBOW 90 LR',
          confidence: AiConfidence.high,
        ),
      ],
      spools: [AiSpool(id: 'SP2', label: 'SP02')],
    );
    await _pump(tester, ScanReviewScreen(scan: scan, suggestedName: name));

    // Folded to one line, prefilled from the title block.
    expect(
        find.text('Linia: DN100-CWS-1234 · ISO: ISO-$name rew. B · '
            'Klasa: A1B'),
        findsOneWidget);
    // The fitter adds the client, which no title block carries.
    await tester.tap(find.text('Identyfikacja z rysunku'));
    await _settle(tester);
    await tester.enterText(
        find.byWidgetPredicate((w) =>
            w is TextField && w.decoration?.labelText == 'Klient'),
        'Orlen');
    await _settle(tester);

    await _tapAsync(tester, _button('Zapisz projekt'));

    final saved = await tester.runAsync(() async {
      for (var i = 0; i < 60; i++) {
        final mine = (await ProjectDao().listAll())
            .where((p) => p.name == name)
            .toList();
        if (mine.isNotEmpty) {
          final segs = await SegmentDao().listForProject(mine.first.id);
          if (segs.length == 2) return (project: mine.first, segments: segs);
        }
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
      return null;
    });
    expect(saved, isNotNull, reason: 'projekt nie został zapisany');
    final p = saved!.project;
    expect(p.lineNo, 'DN100-CWS-1234');
    expect(p.isoNo, 'ISO-$name');
    expect(p.isoRev, 'B');
    expect(p.spec, 'A1B');
    expect(p.client, 'Orlen');
    expect(saved.segments.map((s) => s.label), ['SP02/1', 'SP02/2']);
    expect(saved.segments.map((s) => s.spoolId), ['SP02', 'SP02']);
    await _drainCutList(tester);
  });
}
