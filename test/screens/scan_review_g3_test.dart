// Przegląd skanu po przeglądzie G3: kołnierz bez typu opisany słowami (Y
// dopiero po potwierdzeniu), pewność „medium” wyróżniona, zdjęcie rysunku
// nad cięciami.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cut_list_app/i18n/app_language.dart';
import 'package:cut_list_app/screens/scan_review_screen.dart';
import 'package:cut_list_app/services/iso_scanner_ai.dart';

import '../support/test_database.dart';

Widget _wrap(Widget child) => AppLanguageScope(
      controller: AppLanguageController(AppLanguage.pl),
      child: MaterialApp(home: child),
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

AiTitleBlock _tb() => AiTitleBlock(
      lineNumber: 'DN100-CWS-1234',
      material: 'A312 TP304L',
      schedule: '10S',
      pipeClass: 'CL150',
    );

void main() {
  useTestDatabase();

  testWidgets(
      'kołnierz bez typu: FACE z rysunku nie wystarcza, opcje opisane słowami',
      (tester) async {
    final scan = AiScanResult(
      sizeNotation: 'DN',
      titleBlock: _tb(),
      segments: [
        AiSegment(
          id: 's1',
          dimensionMm: 1000,
          rawDimension: '1000',
          fromId: 'e1',
          toId: 'f1',
          refFrom: 'CL',
          refTo: 'FACE',
          confidence: AiConfidence.high,
        ),
      ],
      components: [
        AiComponent(id: 'e1', type: 'elbow90', confidence: AiConfidence.high),
        AiComponent(
            id: 'f1',
            type: 'flange',
            label: 'FLG RF 150#',
            confidence: AiConfidence.high),
      ],
    );
    await _pump(tester, ScanReviewScreen(scan: scan));

    expect(find.textContaining('bez typu na rysunku'), findsOneWidget);
    expect(find.text('ODNIESIENIE?'), findsOneWidget,
        reason: 'Y nie odejmuje się bez potwierdzenia');
    expect(find.textContaining('CUT 772'), findsNothing);

    await tester.tap(find.text('ODNIESIENIE?'));
    await _settle(tester);
    expect(find.textContaining('do przylgi (−Y 76 mm)'), findsWidgets);
    expect(find.textContaining('do spoiny (bez Y)'), findsWidgets);
    expect(find.textContaining('CUT 772.0 mm'), findsOneWidget);
    expect(find.textContaining('CUT 848.0 mm'), findsWidgets);
  });

  testWidgets('wymiar „medium”: wyróżniony na karcie i zliczony do rzutu oka',
      (tester) async {
    final scan = AiScanResult(
      sizeNotation: 'DN',
      titleBlock: _tb(),
      segments: [
        AiSegment(
          id: 's1',
          dimensionMm: 1200,
          rawDimension: '1200',
          fromId: 'e1',
          toId: 'e2',
          confidence: AiConfidence.medium,
        ),
      ],
      components: [
        AiComponent(id: 'e1', type: 'elbow90', confidence: AiConfidence.high),
        AiComponent(id: 'e2', type: 'elbow90', confidence: AiConfidence.high),
      ],
    );
    await _pump(tester, ScanReviewScreen(scan: scan));

    expect(find.textContaining('Do rzutu oka (1)'), findsOneWidget);
    expect(find.text('? ISO 1200'), findsOneWidget);
    expect(find.textContaining('Średnio pewny odczyt'), findsOneWidget);
    expect(find.textContaining('CUT 896.0 mm'), findsOneWidget,
        reason: 'medium nie blokuje');
  });

  testWidgets('zdjęcie rysunku jest nad cięciami (albo informacja, że go nie ma)',
      (tester) async {
    final scan = AiScanResult(
      sizeNotation: 'DN',
      titleBlock: _tb(),
      segments: [
        AiSegment(
            id: 's1',
            dimensionMm: 1500,
            rawDimension: '1500',
            toId: 'e1',
            confidence: AiConfidence.high),
      ],
      components: [
        AiComponent(id: 'e1', type: 'elbow90', confidence: AiConfidence.high),
      ],
    );
    await _pump(tester,
        ScanReviewScreen(scan: scan, imagePath: '/nie/ma/takiego/pliku.jpg'));
    expect(find.byKey(const ValueKey('scan-review-drawing')), findsOneWidget);
    expect(find.text('Rysunek — zdjęcie ze skanu'), findsOneWidget);
    expect(find.text('Zdjęcia nie ma już w telefonie.'), findsOneWidget);

    await _pump(tester, ScanReviewScreen(scan: scan));
    expect(find.byKey(const ValueKey('scan-review-drawing')), findsNothing);
  });
}
