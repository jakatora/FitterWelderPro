// Zbiorniki → Tandem na prawdziwej bazie z seedem `tandem_tig_params`
// (poziom na styk: 3/3 → 140/72, 4/4 → 190/100, 3/5 → 180/90).
//  * 3/3 → 140/72 A (punkt startowy);
//  * 1,5/1,5 → „brak danych dla tej grubości”, bez liczby (dawniej 140/72 A
//    opisane jako „wyliczone z zatwierdzonych”);
//  * 4,5/4,5 → 185/95 A z ostrzeżeniem, bo 5 mm ma w danych mniej prądu niż 4 mm;
//  * zdanie o WPS przy wyniku; zakładka „Startowe”, nie „Zatwierdzone”.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:cut_list_app/i18n/app_language.dart';
import 'package:cut_list_app/screens/welder_tanks_screen.dart';

import '../support/test_database.dart';

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 4; i++) {
    await flushTestDatabase(tester);
    await tester.pump(const Duration(milliseconds: 50));
  }
  await tester.pumpAndSettle();
}

Future<void> _pump(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1200, 3000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(AppLanguageScope(
    controller: AppLanguageController(AppLanguage.pl),
    child: const MaterialApp(home: WelderTanksScreen()),
  ));
  await _settle(tester);
}

Future<void> _setWalls(WidgetTester tester, String t1, String t2) async {
  await tester.enterText(find.widgetWithText(TextField, 'Ścianka 1 (t1) [mm]'), t1);
  await tester.enterText(find.widgetWithText(TextField, 'Ścianka 2 (t2) [mm]'), t2);
  await _settle(tester);
}

void main() {
  useTestDatabase();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('3/3 → punkt startowy 140/72 A i zdanie o WPS', (tester) async {
    await _pump(tester);
    expect(find.text('Startowe'), findsOneWidget);
    expect(find.text('Zatwierdzone'), findsNothing);
    expect(find.text('Zewnętrzny: 140 A   |   Wewnętrzny: 72 A'), findsOneWidget);
    expect(find.textContaining('Wiąże WPS'), findsOneWidget);
  });

  testWidgets('1,5/1,5 poza zakresem danych → brak liczby', (tester) async {
    await _pump(tester);
    await _setWalls(tester, '1,5', '1,5');
    expect(find.text('Zewnętrzny: —   |   Wewnętrzny: —'), findsOneWidget);
    expect(find.textContaining('Brak danych dla tej grubości'), findsOneWidget);
    expect(find.textContaining('140 A'), findsNothing);
  });

  testWidgets('4,5/4,5 → 185/95 A z ostrzeżeniem o niemonotoniczności',
      (tester) async {
    await _pump(tester);
    await _setWalls(tester, '4,5', '4,5');
    expect(find.text('Zewnętrzny: 185 A   |   Wewnętrzny: 95 A'), findsOneWidget);
    expect(find.textContaining('prąd maleje przy rosnącej grubości'),
        findsOneWidget);
  });

  testWidgets('pion 3,5/3,5 → poziom 165/86 × (70/140, 40/72)', (tester) async {
    await _pump(tester);
    await tester.tap(find.text('Pion'));
    await _settle(tester);
    await _setWalls(tester, '3,5', '3,5');
    // 165·70/140 = 82,5 → „83”; 86·40/72 = 47,8 → „48”
    expect(find.text('Zewnętrzny: 83 A   |   Wewnętrzny: 48 A'), findsOneWidget);
  });
}
