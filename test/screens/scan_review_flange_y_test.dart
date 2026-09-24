// Przegląd skanu pokazuje, że kołnierz WN jest odejmowany długością Y, i
// proponuje odniesienie do przylgi kołnierza (przez korpus) — ale nie liczy
// cięcia, dopóki monter tego nie potwierdzi.
//
// Policzone ręcznie, DN100 Class 150: kolano 90° LR A = 152 (ASME B16.9),
// kołnierz WN Y = 76 (ASME B16.5). Wymiar 1000 od osi kolana do przylgi
// kołnierza → CUT = 1000 − 152 − 76 = 772 mm.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cut_list_app/i18n/app_language.dart';
import 'package:cut_list_app/screens/scan_review_screen.dart';
import 'package:cut_list_app/services/iso_scanner_ai.dart';

import '../support/test_database.dart';

AiScanResult _elbowToFlange() => AiScanResult(
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
          dimensionMm: 1000,
          rawDimension: '1000',
          fromId: 'c1',
          toId: 'c2',
          confidence: AiConfidence.high,
        ),
      ],
      components: [
        AiComponent(id: 'c1', type: 'elbow90', confidence: AiConfidence.high),
        AiComponent(id: 'c2', type: 'flange', confidence: AiConfidence.high),
      ],
    );

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 5; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  useTestDatabase();

  testWidgets('kołnierz: −Y 76 mm widoczne, propozycja oś-koniec → 772',
      (tester) async {
    tester.view.physicalSize = const Size(1100, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(AppLanguageScope(
      controller: AppLanguageController(AppLanguage.pl),
      child: MaterialApp(home: ScanReviewScreen(scan: _elbowToFlange())),
    ));
    await _settle(tester);

    // Przy kołnierzu widać, co zostanie odjęte i skąd to wiadomo.
    expect(find.textContaining('−Y 76 mm'), findsWidgets);
    // Propozycja nie jest potwierdzeniem: cięcia jeszcze nie ma.
    expect(find.text('CUT — brak'), findsOneWidget);
    expect(find.text('ODNIESIENIE?'), findsOneWidget);

    await tester.tap(find.text('ODNIESIENIE?'));
    await _settle(tester);
    // Propozycja jest pierwsza i zaznaczona; przy niej CUT 772.
    expect(find.text('CUT 772.0 mm'), findsOneWidget);
    await tester.tap(find.text('oś-koniec'));
    await _settle(tester);

    expect(find.text('CUT 772.0 mm'), findsOneWidget);
    expect(find.text('oś-koniec'), findsOneWidget);
  });
}
