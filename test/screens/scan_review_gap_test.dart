// Szczelina pod spoinę (gap) w projekcie zapisanym ze skanu.
//
// Ekran przeglądu skanu zapisywał każdy projekt z `gapMm: 0` na sztywno i
// liczył CUT bez szczeliny. Ten sam odcinek zbudowany ręcznie w kreatorze
// (który odejmuje gap × liczba spoin) wychodził krótszy o szczelinę na każdej
// spoinie — dwa ekrany, dwie długości, nic na żadnym nie mówi, która jest
// dobra. Teraz gap wpisuje się na ekranie przeglądu, trafia do projektu i do
// CUT tą samą regułą co w kreatorze.
//
// Rysunek: DN100, 10S, SS. s1: wolny koniec → kolano LR (take-out 152, ASME
// B16.9), 1500. s2: kolano → wolny koniec, 900. Każdy odcinek ma JEDNĄ spoinę
// (wolny koniec nie ma żadnej). Ręcznie, gap 3:
//   s1: 1500 − 152 − 3 × 1 = 1345
//   s2:  900 − 152 − 3 × 1 =  745

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cut_list_app/database/project_dao.dart';
import 'package:cut_list_app/database/segment_dao.dart';
import 'package:cut_list_app/i18n/app_language.dart';
import 'package:cut_list_app/screens/scan_review_screen.dart';
import 'package:cut_list_app/services/iso_scanner_ai.dart';

import '../support/test_database.dart';

Widget _wrap(Widget child) {
  return AppLanguageScope(
    controller: AppLanguageController(AppLanguage.pl),
    child: MaterialApp(home: child),
  );
}

AiScanResult _goodScan() => AiScanResult(
      sizeNotation: 'DN',
      titleBlock: AiTitleBlock(
        lineNumber: 'DN100-CWS-7777',
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

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 5; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> _pumpScreen(WidgetTester tester, Widget screen) async {
  tester.view.physicalSize = const Size(1100, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(_wrap(screen));
  await _settle(tester);
}

Finder _gapField() => find.widgetWithText(TextField, 'Gap (mm na spoinę)');

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

  testWidgets('gap domyślnie 0 — jak w formularzu nowego projektu',
      (tester) async {
    await _pumpScreen(tester, ScanReviewScreen(scan: _goodScan()));

    expect(_gapField(), findsOneWidget);
    expect(tester.widget<TextField>(_gapField()).controller!.text, '0');
    // gap 0: 1500 − 152 = 1348, 900 − 152 = 748.
    expect(find.text('CUT 1348.0 mm'), findsOneWidget);
    expect(find.text('CUT 748.0 mm'), findsOneWidget);
  });

  testWidgets('gap 3 odejmuje się raz na każdą spoinę, jak w kreatorze',
      (tester) async {
    await _pumpScreen(tester, ScanReviewScreen(scan: _goodScan()));

    await tester.enterText(_gapField(), '3');
    await _settle(tester);

    expect(find.text('CUT 1345.0 mm'), findsOneWidget,
        reason: '1500 − 152 − 3 × 1');
    expect(find.text('CUT 745.0 mm'), findsOneWidget,
        reason: '900 − 152 − 3 × 1');
    expect(_saveEnabled(tester), isTrue);
  });

  testWidgets('nieprawidłowy gap blokuje zapis zamiast liczyć z zerem',
      (tester) async {
    await _pumpScreen(tester, ScanReviewScreen(scan: _goodScan()));

    await tester.enterText(_gapField(), '');
    await _settle(tester);

    expect(_saveEnabled(tester), isFalse,
        reason: 'an empty gap is not "no gap" — the fitter has to say it');
  });

  testWidgets('zapis: projekt ma gap 3, segmenty mają CUT z gapem',
      (tester) async {
    final projectDao = ProjectDao();
    final segmentDao = SegmentDao();
    final name = 'SKAN-GAP-${DateTime.now().microsecondsSinceEpoch}';

    await _pumpScreen(
        tester, ScanReviewScreen(scan: _goodScan(), suggestedName: name));
    await tester.enterText(_gapField(), '3');
    await _settle(tester);
    expect(_saveEnabled(tester), isTrue);

    await tester.runAsync(() async {
      await tester.tap(_saveButton());
      await tester.pump();
    });
    await _settle(tester);

    final saved = await tester.runAsync(() async {
      for (var i = 0; i < 60; i++) {
        final mine =
            (await projectDao.listAll()).where((p) => p.name == name).toList();
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
    expect(saved!.project.gapMm, 3,
        reason: 'the builder reads the project gap when a segment is edited');
    expect(saved.segments[0].cutMm, 1345);
    expect(saved.segments[1].cutMm, 745);

    // Let the cut list that replaced this screen settle, then clean up.
    for (var i = 0; i < 40 && find.text('CUT LIST').evaluate().isEmpty; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.runAsync(() async {
      await segmentDao.deleteAllForProject(saved.project.id);
      await projectDao.deleteById(saved.project.id);
    });
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(seconds: 3));
    }
  });
}
