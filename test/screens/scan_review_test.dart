// The screen that stands between a photographed drawing and a pipe someone
// actually cuts (`lib/screens/scan_review_screen.dart`).
//
// Four things have to hold there, and all four are about not cutting steel to
// a number nobody checked:
//
//   1. what the AI could not read BLOCKS the save, in plain words,
//   2. what the AI was unsure about is on screen in colour, not hidden,
//   3. the fitter can correct it in place and the block clears,
//   4. a save writes the project AND every segment, or nothing at all.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import '../support/test_database.dart';

import 'package:cut_list_app/database/project_dao.dart';
import 'package:cut_list_app/database/segment_dao.dart';
import 'package:cut_list_app/i18n/app_language.dart';
import 'package:cut_list_app/screens/scan_review_screen.dart';
import 'package:cut_list_app/services/iso_scanner_ai.dart';

/// ScanReviewScreen calls `context.tr`, which needs AppLanguageScope in the
/// tree — mirror the app's main() setup. Polish, because that is what the
/// fitter this screen was written for reads.
Widget _wrap(Widget child) {
  return AppLanguageScope(
    controller: AppLanguageController(AppLanguage.pl),
    child: MaterialApp(home: child),
  );
}

/// A readable drawing: DN100 stainless, schedule 10S, two runs between three
/// long-radius elbows. Everything the planner needs is on it.
AiScanResult _goodScan() => AiScanResult(
      sizeNotation: 'DN',
      titleBlock: AiTitleBlock(
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
    );

/// The same drawing with the title block unreadable: no size, no schedule, no
/// material. Every project column is a gap.
AiScanResult _headerlessScan() => AiScanResult(
      segments: [
        AiSegment(
          id: 's1',
          dimensionMm: 1500,
          rawDimension: '1500',
          confidence: AiConfidence.high,
        ),
      ],
    );

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 5; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// Pumps the screen on a phone-sized-but-tall surface.
///
/// The default 800×600 test window cuts the segment list off below the fold,
/// and a ListView does not build what it cannot show — the segment cards
/// would be missing from the tree rather than merely off-screen.
Future<void> _pumpScreen(WidgetTester tester, Widget screen) async {
  tester.view.physicalSize = const Size(1100, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(_wrap(screen));
  await _settle(tester);
}

/// The save button, found by its label.
///
/// `FilledButton.icon` builds a private subclass, which `find.byType` (exact
/// runtime type) would not match — hence the predicate on the base class.
Finder _saveButton() => find
    .ancestor(
      of: find.text('Zapisz projekt'),
      matching: find.byWidgetPredicate((w) => w is ButtonStyleButton),
    )
    .first;

bool _saveEnabled(WidgetTester tester) =>
    tester.widget<ButtonStyleButton>(_saveButton()).onPressed != null;

void main() {
  useTestDatabase();

  testWidgets('nieczytelna tabelka blokuje zapis i mówi, czego brakuje',
      (tester) async {
    await _pumpScreen(tester, ScanReviewScreen(scan: _headerlessScan()));

    // The blocks are named at the top, each saying what to do about it.
    expect(find.textContaining('Bez tego nie zapiszę'), findsOneWidget);
    expect(find.textContaining('Podaj średnicę rury'), findsOneWidget);
    expect(find.textContaining('Podaj grubość ścianki'), findsOneWidget);
    expect(find.textContaining('Wskaż grupę materiału'), findsOneWidget);

    // And the button is dead, not merely discouraged.
    expect(_saveEnabled(tester), isFalse);
  });

  testWidgets('monter uzupełnia średnicę, ściankę i materiał — zapis rusza',
      (tester) async {
    await _pumpScreen(tester, ScanReviewScreen(scan: _headerlessScan()));
    expect(_saveEnabled(tester), isFalse);

    await tester.enterText(
        find.widgetWithText(TextField, 'Średnica OD (mm)'), '114.3');
    await _settle(tester);
    await tester.enterText(
        find.widgetWithText(TextField, 'Ścianka (mm)'), '3.05');
    await _settle(tester);

    // Still blocked: nobody said whether it is stainless or carbon.
    expect(_saveEnabled(tester), isFalse);

    await tester.tap(find.widgetWithText(ChoiceChip, 'SS — nierdzewna'));
    await _settle(tester);

    expect(find.textContaining('Bez tego nie zapiszę'), findsNothing);
    expect(_saveEnabled(tester), isTrue);
  });

  testWidgets('czytelny rysunek: średnica i ścianka wchodzą z tabelki',
      (tester) async {
    await _pumpScreen(tester, ScanReviewScreen(scan: _goodScan()));

    // DN100 → OD 114.3, schedule 10S → 3.05 mm, both straight out of the
    // ASME tables the app already ships.
    expect(find.widgetWithText(TextField, 'Średnica OD (mm)'), findsOneWidget);
    expect(find.text('114.3'), findsOneWidget);
    expect(find.text('3.05'), findsOneWidget);
    expect(_saveEnabled(tester), isTrue);
  });

  testWidgets('niepewny odczyt jest widoczny, a nie schowany drobnym drukiem',
      (tester) async {
    final scan = AiScanResult(
      sizeNotation: 'DN',
      titleBlock: AiTitleBlock(
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
          // This is the point of the test: the model itself said it is not
          // sure about this number.
          confidence: AiConfidence.low,
        ),
      ],
      components: [
        AiComponent(id: 'c1', type: 'elbow90', confidence: AiConfidence.high),
      ],
      uncertainty: const ['Wymiar 1500 częściowo zasłonięty przez wymiarówkę'],
    );

    await _pumpScreen(tester, ScanReviewScreen(scan: scan));

    // The drawing-wide doubt is quoted verbatim…
    expect(find.textContaining('AI nie jest pewna'), findsOneWidget);
    expect(find.textContaining('częściowo zasłonięty'), findsOneWidget);
    // …and the doubt about the number is listed at the top AND next to it.
    expect(find.textContaining('Niepewny odczyt wymiaru 1500'),
        findsNWidgets(2));

    // Spec §9 rule 6: an uncertain value never becomes a cut silently. The
    // cut is shown, but nothing is saved until the fitter confirms the number.
    expect(find.textContaining('CUT 1348'), findsOneWidget);
    expect(_saveEnabled(tester), isFalse);

    // He checks the drawing and confirms the number as read.
    await tester.tap(find.text('ISO 1500'));
    await _settle(tester);
    await tester.tap(find.widgetWithText(FilledButton, 'Zapisz'));
    await _settle(tester);

    expect(find.textContaining('Niepewny odczyt wymiaru'), findsNothing);
    expect(find.textContaining('CUT 1348'), findsOneWidget);
    expect(_saveEnabled(tester), isTrue);
  });

  testWidgets('brakujący wymiar blokuje, dopisanie go odblokowuje segment',
      (tester) async {
    final scan = AiScanResult(
      sizeNotation: 'DN',
      titleBlock: AiTitleBlock(
        lineNumber: 'DN100-CWS-1234',
        material: 'A312 TP304L',
        schedule: '10S',
      ),
      segments: [
        // No dimension at all — the tape measure figure was out of frame.
        AiSegment(id: 's1', toId: 'c1', confidence: AiConfidence.low),
      ],
      components: [
        AiComponent(id: 'c1', type: 'elbow90', confidence: AiConfidence.high),
      ],
    );

    await _pumpScreen(tester, ScanReviewScreen(scan: scan));

    // Twice on purpose: in the blocking list at the top AND on the segment
    // card itself, so it cannot be missed either way round.
    expect(find.textContaining('nie ma wymiaru'), findsNWidgets(2));
    expect(find.text('WPISZ WYMIAR'), findsOneWidget);
    expect(_saveEnabled(tester), isFalse);

    await tester.tap(find.text('WPISZ WYMIAR'));
    await _settle(tester);
    await tester.enterText(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(TextField),
      ),
      '1500',
    );
    await _settle(tester);
    await tester.tap(find.widgetWithText(FilledButton, 'Zapisz'));
    await _settle(tester);

    // The gap is gone, a cut length exists, and it is shorter than the ISO
    // dimension by the elbow's take-out — the engine did the arithmetic.
    expect(find.textContaining('nie ma wymiaru'), findsNothing);
    expect(find.textContaining('CUT 1348'), findsOneWidget);
    expect(_saveEnabled(tester), isTrue);
  });

  testWidgets('kołnierz na końcu: monter musi potwierdzić, jak zmierzono',
      (tester) async {
    final scan = AiScanResult(
      sizeNotation: 'DN',
      titleBlock: AiTitleBlock(
        lineNumber: 'DN100-CWS-1234',
        material: 'A312 TP304L',
        schedule: '10S',
        pipeClass: 'CL150',
      ),
      segments: [
        AiSegment(
          id: 's1',
          dimensionMm: 1500,
          rawDimension: '1500',
          fromId: 'c1',
          toId: 'c2',
          confidence: AiConfidence.high,
        ),
      ],
      components: [
        AiComponent(id: 'c1', type: 'elbow90', confidence: AiConfidence.high),
        // A body of its own: a photo cannot say whether 1500 runs to its
        // face or to its far end, and the two differ by the flange length.
        AiComponent(id: 'c2', type: 'flange', confidence: AiConfidence.high),
      ],
    );

    await _pumpScreen(tester, ScanReviewScreen(scan: scan));

    expect(find.textContaining('Potwierdź, jak zmierzono'), findsNWidgets(2));
    expect(find.text('ODNIESIENIE?'), findsOneWidget);
    expect(_saveEnabled(tester), isFalse);

    await tester.tap(find.text('ODNIESIENIE?'));
    await _settle(tester);

    // The sheet shows every option WITH the cut it produces, so the choice
    // is made on numbers rather than on vocabulary.
    expect(find.textContaining('CUT '), findsWidgets);
    await tester.tap(find.text('oś-czoło'));
    await _settle(tester);

    expect(find.textContaining('Potwierdź, jak zmierzono'), findsNothing);
    expect(_saveEnabled(tester), isTrue);
  });

  testWidgets('zapis tworzy projekt z KOMPLETEM segmentów', (tester) async {
    final projectDao = ProjectDao();
    final segmentDao = SegmentDao();

    await _pumpScreen(
      tester,
      ScanReviewScreen(
        scan: _goodScan(),
        suggestedName: 'SKAN-TEST-${DateTime.now().microsecondsSinceEpoch}',
      ),
    );
    expect(_saveEnabled(tester), isTrue);

    final name = tester
        .widget<TextField>(find.widgetWithText(TextField, 'Nazwa / nr linii'))
        .controller!
        .text;

    // sqflite runs on a real event loop; the widget test's fake-async zone
    // would never let those futures complete.
    await tester.runAsync(() async {
      await tester.tap(_saveButton());
      await tester.pump();
    });
    await _settle(tester);

    // Odpytujemy baze, zamiast czekac stale 500 ms: przy uruchomieniu calej
    // suity (wspoldzielona baza sqflite_ffi) lancuch insertow potrafi trwac
    // dluzej i test stawal sie losowy.
    final saved = await tester.runAsync(() async {
      for (var i = 0; i < 60; i++) {
        final projects = await projectDao.listAll();
        final mine = projects.where((p) => p.name == name).toList();
        if (mine.isNotEmpty) {
          final segments = await segmentDao.listForProject(mine.first.id);
          if (segments.length == 2) {
            return (project: mine.first, segments: segments);
          }
        }
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
      return null;
    });

    expect(saved, isNotNull, reason: 'projekt nie został zapisany');
    expect(saved!.project.diameterMm, closeTo(114.3, 0.01));
    expect(saved.project.wallThicknessMm, closeTo(3.05, 0.01));
    expect(saved.project.materialGroup, 'SS');

    // Both runs off the drawing, in route order, each with a real cut.
    expect(saved.segments.length, 2);
    expect(saved.segments[0].seqNo, 1);
    expect(saved.segments[1].seqNo, 2);
    for (final s in saved.segments) {
      expect(s.cutMm, greaterThan(0));
      expect(s.cutMm, lessThan(s.isoMm),
          reason: 'CUT musi być krótszy od wymiaru ISO o take-outy');
      expect(s.diameterMm, closeTo(114.3, 0.01));
    }

    // Monter ma wyladowac na cut liscie, a nie zostac na ekranie przegladu.
    // Sprawdzamy OBECNOSC cut listy, bo to jest wlasciwy wynik; brak ekranu
    // przegladu docieramy dopiero po doliczeniu animacji przejscia — w trakcie
    // niej oba ekrany sa w drzewie i asercja "findsNothing" lapala poprzedni.
    // Czekamy, az cut lista sie pojawi, zamiast zakladac stale opoznienie:
    // pod obciazeniem calej suity (wspoldzielona baza sqflite_ffi) przejscie
    // trwa dluzej niz przy uruchomieniu tego pliku osobno.
    for (var i = 0; i < 40 && find.text('CUT LIST').evaluate().isEmpty; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.text('CUT LIST'), findsOneWidget,
        reason: 'monter mial wyladowac na cut liscie po zapisie');
    await _settle(tester);
    expect(find.text('Sprawdź skan'), findsNothing);

    await tester.runAsync(() async {
      await segmentDao.deleteAllForProject(saved.project.id);
      await projectDao.deleteById(saved.project.id);
    });

    // The cut-list screen shows a SnackBar with its own timer when a shared
    // test DB read loses the race; let those expire before the tree goes.
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(seconds: 3));
    }
  });
}
