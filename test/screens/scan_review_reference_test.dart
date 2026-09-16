// Odpowiedź montera „jak zmierzono wymiar” dotyczy KONKRETNEGO elementu na
// końcu odcinka. Po zamianie tego elementu stara odpowiedź nie może dalej
// liczyć cięcia (lib/screens/scan_review_screen.dart).
//
// Wartości policzone ręcznie: DN100, kolano 90° LR wg ASME B16.9 ma take-out
// 152 mm (po zaokrągleniu), więc wymiar 1500 od osi kolana do otwartego
// końca daje CUT = 1500 − 152 = 1348 mm.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import '../support/test_database.dart';

import 'package:cut_list_app/i18n/app_language.dart';
import 'package:cut_list_app/screens/scan_review_screen.dart';
import 'package:cut_list_app/services/iso_scanner_ai.dart';

Widget _wrap(Widget child) {
  return AppLanguageScope(
    controller: AppLanguageController(AppLanguage.pl),
    child: MaterialApp(home: child),
  );
}

/// Kolano 90° → kołnierz, klasa 150, DN100 SS 10S, wymiar 1500.
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
          dimensionMm: 1500,
          rawDimension: '1500',
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

Future<void> _pumpScreen(WidgetTester tester, Widget screen) async {
  tester.view.physicalSize = const Size(1100, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(_wrap(screen));
  await _settle(tester);
}

Finder _saveButton() => find
    .ancestor(
      of: find.text('Zapisz projekt'),
      matching: find.byWidgetPredicate((w) => w is ButtonStyleButton),
    )
    .first;

bool _saveEnabled(WidgetTester tester) =>
    tester.widget<ButtonStyleButton>(_saveButton()).onPressed != null;

/// Monter odpowiada „oś-czoło” dla kołnierza — zapis się odblokowuje.
Future<void> _answerAxisToFace(WidgetTester tester) async {
  expect(find.textContaining('Potwierdź, jak zmierzono'), findsNWidgets(2));
  await tester.tap(find.text('ODNIESIENIE?'));
  await _settle(tester);
  await tester.tap(find.text('oś-czoło'));
  await _settle(tester);
  expect(find.textContaining('Potwierdź, jak zmierzono'), findsNothing);
  expect(find.text('oś-czoło'), findsOneWidget);
  expect(_saveEnabled(tester), isTrue);
}

/// Zamienia kołnierz na końcu odcinka na element wybrany z listy.
Future<void> _replaceFlangeWith(WidgetTester tester, String choice) async {
  await tester.tap(find.text('Kołnierz'));
  await _settle(tester);
  await tester.tap(find.text(choice));
  await _settle(tester);
}

void main() {
  useTestDatabase();

  testWidgets(
      'kołnierz zamieniony na zawór: pytanie o odniesienie wraca i blokuje zapis',
      (tester) async {
    await _pumpScreen(tester, ScanReviewScreen(scan: _elbowToFlange()));
    await _answerAxisToFace(tester);

    await _replaceFlangeWith(tester, 'Zawór zasuwowy');

    // Odpowiedź dotyczyła kołnierza, a zawór ma inną długość zabudowy.
    // Monter musi odpowiedzieć jeszcze raz, zanim cokolwiek się zapisze.
    expect(find.textContaining('Potwierdź, jak zmierzono'), findsNWidgets(2));
    expect(find.text('ODNIESIENIE?'), findsOneWidget);
    expect(find.text('oś-czoło'), findsNothing);
    expect(_saveEnabled(tester), isFalse);
  });

  testWidgets(
      'kołnierz zamieniony na otwarty koniec: stara odpowiedź nie liczy cięcia',
      (tester) async {
    await _pumpScreen(tester, ScanReviewScreen(scan: _elbowToFlange()));
    await _answerAxisToFace(tester);

    await _replaceFlangeWith(tester, 'Otwarty koniec');

    // Przy otwartym końcu odniesienie wynika z samych końców (oś-oś).
    // Stara odpowiedź „oś-czoło” znika z ekranu.
    expect(find.textContaining('Potwierdź, jak zmierzono'), findsNothing);
    expect(find.text('oś-czoło'), findsNothing);
    // 1500 − 152 (take-out kolana DN100 LR) = 1348 mm.
    expect(find.text('CUT 1348.0 mm'), findsOneWidget);
    expect(_saveEnabled(tester), isTrue);
  });
}
