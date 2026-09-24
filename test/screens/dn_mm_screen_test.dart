// Ekran DN-MM: DN100 musi pokazywać OD 114,3 mm (ASME B36.10M NPS 4 =
// 4.500 in; EN 10220 seria 1 = 114,3). Wcześniej tabela miała dla DN100
// tylko 104,0 i 108,0.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cut_list_app/i18n/app_language.dart';
import 'package:cut_list_app/screens/dn_mm_screen.dart';

void main() {
  testWidgets('DN100 → wiersz OD 114.30 z R 152.40 i serią ASME / EN s.1',
      (tester) async {
    tester.view.physicalSize = const Size(900, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(AppLanguageScope(
      controller: AppLanguageController(AppLanguage.pl),
      child: const MaterialApp(home: DnMmScreen()),
    ));
    await tester.enterText(find.byType(TextField).first, '100');
    await tester.pumpAndSettle();

    expect(find.text('114.30'), findsOneWidget);
    expect(find.text('152.40'), findsOneWidget);
    expect(find.text('ASME / EN s.1'), findsOneWidget);
    // Pozostałe OD dla DN100 zostają, z oznaczoną serią.
    expect(find.text('104'), findsOneWidget);
    expect(find.text('108'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('OD 101,6 (NPS 3 1/2") to DN90', (tester) async {
    tester.view.physicalSize = const Size(900, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(AppLanguageScope(
      controller: AppLanguageController(AppLanguage.pl),
      child: const MaterialApp(home: DnMmScreen()),
    ));
    await tester.enterText(find.byType(TextField).at(1), '101,6');
    await tester.pumpAndSettle();
    expect(find.text('3 1/2"'), findsOneWidget);
    expect(find.text('90'), findsOneWidget);
  });
}
