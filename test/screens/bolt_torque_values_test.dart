// Pierwsza część kroku „Zamknąć kolejkę P0 audytu” — moduł bolt-torque.
//
// Wartości oczekiwane policzone ręcznie (ASME PCC-1: T = K·F·d, F = frac·SMYS·A_s).
// Pole przekroju czynnego wg ASME B1.1 dla gwintu calowego UN:
//   A_s = 0,7854·(d − 0,9743/n)² [in²], 1 in² = 645,16 mm².
// Szereg gwintu wg ASME B16.5: UNC do 1" włącznie, 8UN powyżej 1".
//
//   5/8"-11 UNC: A_s = 0,7854·(0,625 − 0,088573)² = 0,22600 in² = 145,81 mm²
//   B7, 50% SMYS: σ = 362 MPa → F = 52 782 N (52,8 kN)
//   pasta Cu, K = 0,16: T = 0,16 · 52 782 · 0,015875 = 134,07 N·m → „134”
//   ft·lb: 134,07 / 1,3558 = 98,9 → „99”
//   B8M (207 MPa): σ = 103,5 → F = 15 091 N → T = 38,33 → „38”
//   sucho, K = 0,20: T = 167,58 → „168”
//
// Przed poprawką (wzór metryczny 0,9382·p, d = 15,88 mm) było:
//   147,70 mm², 53,5 kN, 136 N·m, 100 ft·lb; B8M 39; sucho 170.
//
// Śruby > 1" (8UN, 8 zw./cal), B7, 50% SMYS, K = 0,16:
//   1-1/8": A_s = 0,79046 in² = 509,97 mm² → T = 844,03 N·m (było 824 przy 7 zw./cal)
//   1-1/2": A_s = 1,49183 in² = 962,48 mm² → T = 2123,95 N·m (było 2019 przy 6 zw./cal)
//   2":     A_s = 2,77064 in² = 1787,51 mm² → T = 5259,45 N·m (było 4647 przy 4 zw./cal)

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:cut_list_app/i18n/app_language.dart';
import 'package:cut_list_app/screens/bolt_torque_screen.dart';
import 'package:cut_list_app/services/flange_catalog.dart';

Widget _wrap(Widget child) {
  return AppLanguageScope(
    controller: AppLanguageController(AppLanguage.en),
    child: MaterialApp(home: child),
  );
}

Future<void> _pumpScreen(WidgetTester tester) async {
  // Wysoki ekran, żeby karta wyniku była zbudowana bez przewijania.
  tester.view.physicalSize = const Size(1080, 4000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(_wrap(const BoltTorqueScreen()));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('domyślnie 5/8" B7, pasta Cu, 50% SMYS daje 134 N·m',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    await _pumpScreen(tester);

    expect(find.text('134'), findsOneWidget);
    expect(find.text('99 ft·lb'), findsOneWidget);
    expect(find.text('Preload: 52.8 kN'), findsOneWidget);
    expect(find.text('50 %'), findsOneWidget);
  });

  testWidgets('B8M z zapisanych ustawień daje 38 N·m, nie wartość B7',
      (tester) async {
    SharedPreferences.setMockInitialValues({'bolt_torque.grade': 'B8M'});
    await _pumpScreen(tester);

    expect(find.text('38'), findsOneWidget);
    expect(find.text('134'), findsNothing);
  });

  testWidgets('smar suchy (K = 0,20) daje 168 N·m', (tester) async {
    SharedPreferences.setMockInitialValues({'bolt_torque.lube': 'dry'});
    await _pumpScreen(tester);

    expect(find.text('168'), findsOneWidget);
    expect(find.text('134'), findsNothing);
  });

  testWidgets('preset DN100 × Class 150 pokazuje 8 śrub 5/8" i 134 N·m',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      'bolt_torque.flange_dn': 100,
      'bolt_torque.flange_class': 150,
    });
    await _pumpScreen(tester);

    expect(find.text('8 × 5/8" bolts'), findsOneWidget);
    expect(find.text('134'), findsOneWidget);
    expect(
      find.text('8 bolts × 134 N·m, star 25/50/75/100%'),
      findsOneWidget,
    );
  });

  // Śruby > 1": gwint 8UN wg ASME B16.5, A_s wg ASME B1.1.
  for (final (size, torque, oldTorque) in const [
    ('1-1/8', '844', '824'),
    ('1-1/2', '2124', '2019'),
    ('2', '5259', '4647'),
  ]) {
    testWidgets('$size" B7 50% SMYS pasta Cu daje $torque N·m (było $oldTorque)',
        (tester) async {
      SharedPreferences.setMockInitialValues({'bolt_torque.bolt_size': size});
      await _pumpScreen(tester);

      expect(find.text(torque), findsOneWidget);
      expect(find.text(oldTorque), findsNothing);
    });
  }

  testWidgets('preset DN300 × Class 300 (16 × 1-1/8") liczy gwint 8UN',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      'bolt_torque.flange_dn': 300,
      'bolt_torque.flange_class': 300,
    });
    await _pumpScreen(tester);

    expect(find.text('16 × 1-1/8" bolts'), findsOneWidget);
    expect(find.text('844'), findsOneWidget);
  });

  test('katalog B16.5 odrzuca DN15 × Class 1500', () {
    expect(FlangeCatalog.lookup(15, 1500), isNull);
    final dn100 = FlangeCatalog.lookup(100, 150);
    expect(dn100, isNotNull);
    expect(dn100!.boltCount, 8);
    expect(dn100.boltSize, '5/8');
  });
}
