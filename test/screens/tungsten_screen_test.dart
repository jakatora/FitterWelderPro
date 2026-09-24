import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:cut_list_app/i18n/app_language.dart';
import 'package:cut_list_app/screens/tungsten_screen.dart';

Future<void> _pump(WidgetTester tester, AppLanguage lang) async {
  tester.view.physicalSize = const Size(1200, 4000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(AppLanguageScope(
    controller: AppLanguageController(lang),
    child: const MaterialApp(home: TungstenScreen()),
  ));
  await tester.pumpAndSettle();
}

Finder _ampsField() => find.byWidgetPredicate(
      (w) =>
          w is TextField &&
          (w.decoration?.labelText == 'Welding current (A, DC-)' ||
              w.decoration?.labelText == 'Prąd spawania (A, DC-)'),
      description: 'amps field',
    );

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  // Dobór średnicy to zwykły odczyt z tabeli DC− (lib/data/tungsten.dart),
  // nie model AI — etykieta „AI sugeruje” wprowadzała w błąd.
  testWidgets('EN: override dialog says "From table", not "AI suggests"',
      (tester) async {
    await _pump(tester, AppLanguage.en);
    await tester.enterText(_ampsField(), '90');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ø 2.4 mm'));
    await tester.pumpAndSettle();

    expect(find.textContaining('AI suggests'), findsNothing);
    expect(
        find.text('From table: Ø 1.6 mm — you are picking Ø 2.4 mm.'),
        findsOneWidget);
  });

  testWidgets('PL: okno nadpisania mówi „Z tabeli”, nie „AI sugeruje”',
      (tester) async {
    await _pump(tester, AppLanguage.pl);
    await tester.enterText(_ampsField(), '90');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ø 2.4 mm'));
    await tester.pumpAndSettle();

    expect(find.textContaining('AI sugeruje'), findsNothing);
    expect(find.text('Z tabeli: Ø 1.6 mm — wybierasz Ø 2.4 mm.'),
        findsOneWidget);
  });
}
