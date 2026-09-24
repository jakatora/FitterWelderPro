// Heat input + Preheat/CE — poprawki z audytu 2026-09. Każdy test pada na
// starej wersji ekranu:
//  • domyślny zakres WPS 1,0–2,5 kJ/mm → domyślne parametry każdego procesu
//    świeciły „POZA zakresem WPS”;
//  • „pasmo tolerancji ±10 %” — wynik poza WPS był złoty „nadal OK”;
//  • brak trybu ASME IX (QW-409.1 liczy bez η);
//  • FCAW-S η 0,75 (EN 1011-1: 0,8);
//  • A106 B: katalog „10 °C” obok „125 °C” z reguły CE bez wyjaśnienia,
//    notka preheat po polsku w wersji EN.
// Liczby — patrz test/domain/welding/*.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:cut_list_app/i18n/app_language.dart';
import 'package:cut_list_app/screens/heat_input_screen.dart';

Widget _app() => AppLanguageScope(
      controller: AppLanguageController(AppLanguage.en),
      child: const MaterialApp(home: HeatInputScreen()),
    );

Future<void> _pump(WidgetTester tester) async {
  SharedPreferences.setMockInitialValues({});
  tester.view.physicalSize = const Size(1200, 3400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(_app());
  await tester.pumpAndSettle();
}

Finder _field(String label) => find.byWidgetPredicate(
      (w) => w is TextField && w.decoration?.labelText == label,
      description: 'TextField "$label"',
    );

Future<void> _enter(WidgetTester tester, String label, String value) async {
  await tester.enterText(_field(label), value);
  await tester.pump();
}

const _disclaimer = 'the WPS / project specification is binding';

void main() {
  group('Heat input', () {
    testWidgets('bez wpisanego zakresu WPS nie ma werdyktu', (tester) async {
      await _pump(tester);

      for (final process in ['SMAW', 'GMAW', 'FCAW-G', 'FCAW-S', 'GTAW', 'SAW']) {
        await tester.tap(find.text(process));
        await tester.pump();
        expect(find.textContaining('OUT of WPS range'), findsNothing,
            reason: process);
        expect(find.textContaining('Within WPS range'), findsNothing,
            reason: process);
      }
      expect(find.textContaining('Enter the WPS range'), findsOneWidget);
      expect(find.textContaining(_disclaimer), findsOneWidget);
    });

    testWidgets('wynik tuż ponad max WPS jest POZA zakresem (bez ±10 %)',
        (tester) async {
      await _pump(tester);
      // SMAW 22 V / 110 A / 200 mm/min → 0,5808 kJ/mm (EN, η 0,8)
      await _enter(tester, 'Min', '0.50');
      await _enter(tester, 'Max', '0.55');

      expect(find.text('0.58'), findsOneWidget);
      expect(find.textContaining('OUT of WPS range'), findsOneWidget);
      expect(find.textContaining('tolerance'), findsNothing);

      await _enter(tester, 'Max', '0.60');
      expect(find.textContaining('Within WPS range'), findsOneWidget);
    });

    testWidgets('przełącznik EN (η) / ASME IX (bez η): 0,48 vs 0,80 kJ/mm',
        (tester) async {
      await _pump(tester);
      await tester.tap(find.text('GTAW')); // 12 V / 100 A / 90 mm/min
      await tester.pump();
      expect(find.text('0.48'), findsOneWidget);

      await tester.tap(find.text('ASME IX'));
      await tester.pump();
      expect(find.text('0.80'), findsOneWidget);
      expect(find.textContaining('QW-409.1'), findsWidgets);

      await tester.tap(find.text('EN 1011-1'));
      await tester.pump();
      expect(find.text('0.48'), findsOneWidget);
    });

    testWidgets('FCAW-S ma η 0,80 (EN 1011-1), nie 0,75', (tester) async {
      await _pump(tester);
      await tester.tap(find.text('FCAW-S'));
      await tester.pump();
      expect(find.textContaining('Arc efficiency FCAW-S: 80%'), findsOneWidget);
    });
  });

  group('Preheat / CE', () {
    testWidgets('A106 B: metody nazwane, minimum kodowe opisane, bez PL w EN',
        (tester) async {
      await _pump(tester);
      await tester.tap(find.widgetWithText(Tab, 'Preheat / CE'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('A106 B'));
      await tester.pumpAndSettle();

      // t = 15 mm (domyślnie); CE 0,427
      expect(find.text('0.427'), findsOneWidget);
      // reguła orientacyjna CE (pasmo 0,35–0,45)
      expect(find.text('125 °C'), findsOneWidget);
      // Seferian: [C]c 0,3678 · 1,075 → 133 °C
      expect(find.text('133 °C'), findsOneWidget);
      // minimum kodowe ASME B31.3 Tab. 330.1.1, P-No 1, t < 25 mm → 10 °C
      expect(find.text('10 °C'), findsOneWidget);
      expect(find.textContaining('B31.3'), findsWidgets);
      expect(find.textContaining('different questions'), findsOneWidget,
          reason: 'wyjaśnienie, dlaczego liczby się różnią');

      expect(find.textContaining('niski preheat'), findsNothing);
      expect(find.textContaining('Bez preheat'), findsNothing);
      expect(find.textContaining(_disclaimer), findsOneWidget);
    });

    testWidgets('P91 pokazuje P-No 15E', (tester) async {
      await _pump(tester);
      await tester.tap(find.widgetWithText(Tab, 'Preheat / CE'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('P91 / T91'));
      await tester.pumpAndSettle();

      expect(find.textContaining('P-No 15E'), findsWidgets);
      expect(find.textContaining('P-No 5 '), findsNothing);
    });

    testWidgets('wybór gatunku nie wpisuje „typowego” zakresu jako WPS',
        (tester) async {
      await _pump(tester);
      await tester.tap(find.widgetWithText(Tab, 'Preheat / CE'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('A106 B'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(Tab, 'Heat input'));
      await tester.pumpAndSettle();

      expect(find.textContaining('OUT of WPS range'), findsNothing);
      expect(find.textContaining('Within WPS range'), findsNothing);
    });
  });
}
