// Orbital TIG: poza zakresem modelu autogenicznego komunikat zamiast liczby
// (przegląd G4: 168,3 × 6,0 → 308 A); HI z konwencją EN i wartością ASME.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cut_list_app/i18n/app_language.dart';
import 'package:cut_list_app/screens/orbital_tig_screen.dart';

Finder _field(String label) => find.byWidgetPredicate(
      (w) => w is TextField && w.decoration?.labelText == label,
    );

Future<void> _enter(WidgetTester tester, String od, String wall) async {
  await tester.enterText(_field('Tube OD (mm)'), od);
  await tester.enterText(_field('Wall (mm)'), wall);
  await tester.pump(const Duration(milliseconds: 200));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('168,3 × 6,0 → komunikat, bez prądu; 50,8 × 1,65 → wynik',
      (tester) async {
    tester.view.physicalSize = const Size(1200, 3000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(AppLanguageScope(
      controller: AppLanguageController(AppLanguage.en),
      child: const MaterialApp(home: OrbitalTigScreen()),
    ));

    await _enter(tester, '168.3', '6');
    expect(find.textContaining('outside autogenous'), findsOneWidget);
    expect(find.text('308 A'), findsNothing);
    expect(find.text('Sector 1 (start)'), findsNothing);

    await _enter(tester, '50.8', '1.65');
    expect(find.textContaining('outside autogenous'), findsNothing);
    expect(find.text('Sector 1 (start)'), findsOneWidget);
    expect(find.text('Heat input (approx.) — EN 1011-1, η 0.6'), findsOneWidget);
    expect(find.text('0.31 kJ/mm'), findsOneWidget);
    expect(find.text('0.51 kJ/mm'), findsOneWidget);
  });
}
