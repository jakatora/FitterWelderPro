// Ekran „Konfiguracja podpór”: wynik = tabela MSS SP-58 Tab. 4 / B31.1
// Tab. 121.5 bez ukrytej obniżki; zapas własny tylko jawnie włączony.
//   DN50 ciecz 3000 mm (10 ft); zapas 10 %: 3000 × 0,9 = 2700.
//   DN50 gaz 4000 mm (13 ft).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cut_list_app/i18n/app_language.dart';
import 'package:cut_list_app/screens/support_config_screen.dart';

Widget _app() => AppLanguageScope(
      controller: AppLanguageController(AppLanguage.pl),
      child: const MaterialApp(home: SupportConfigScreen()),
    );

void main() {
  testWidgets('DN50 ciecz 3000 mm, bez izolacyjnego −12 %', (tester) async {
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();
    expect(find.text('3000'), findsOneWidget);
    expect(find.textContaining('Izolacja ≥ 50'), findsNothing);
    expect(find.textContaining('SP-58'), findsOneWidget);
  });

  testWidgets('zapas własny −10 % jawnie włączony → 2700', (tester) async {
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('Własny zapas'));
    await tester.pumpAndSettle();
    expect(find.text('2700'), findsOneWidget);
  });

  testWidgets('gaz / para DN50 → 4000', (tester) async {
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();
    await tester.tap(find.text('Gaz / para'));
    await tester.pumpAndSettle();
    expect(find.text('4000'), findsOneWidget);
  });
}
