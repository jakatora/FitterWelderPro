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
      find.text('8 bolts × 134 N·m, rounds per ASME PCC-1'),
      findsOneWidget,
    );
    // PCC-1-2019 tab. 1: 20–30 % / 50–70 % / 100 % z 134,07 N·m:
    //  26,8–40,2 → „27–40” N·m (19,8–29,7 → „20–30” ft·lb);
    //  67,0–93,8 → „67–94” N·m (49,4–69,2 → „49–69” ft·lb); 100 % → 134 (99).
    expect(find.text('Round 1: 20–30 % → 27–40 N·m (20–30 ft·lb)'),
        findsOneWidget);
    expect(find.text('Round 2: 50–70 % → 67–94 N·m (49–69 ft·lb)'),
        findsOneWidget);
    expect(find.text('Round 3: 100 % → 134 N·m (99 ft·lb)'), findsOneWidget);
    // Runda 5 po min. 4 h (PCC-1), nie „20 min – 4 h”.
    expect(find.textContaining('minimum of 4 h'), findsOneWidget);
    expect(find.textContaining('20 min'), findsNothing);
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

  // ASME B16.5 — śruby (wermac.org, „Stud Bolts”, WN Class 600/900/1500):
  //  Class 600: ½" 4×½, ¾" 4×⅝, 1" 4×⅝, 1¼" 4×⅝, 1½" 4×¾, 2" 8×⅝, 2½" 8×¾
  //  Class 900 = 1500 dla NPS ½–2½: ½" 4×¾, ¾" 4×¾, 1" 4×⅞, 1¼" 4×⅞,
  //    1½" 4×1, 2" 8×⅞, 2½" 8×1
  //  Dawniej DN15 × Class 1500 było „brak w B16.5” — nieprawda.
  test('katalog B16.5: Class 600/900/1500 dla DN15–65', () {
    const expected = <(int, int), (int, String)>{
      (15, 600): (4, '1/2'),
      (20, 600): (4, '5/8'),
      (25, 600): (4, '5/8'),
      (32, 600): (4, '5/8'),
      (40, 600): (4, '3/4'),
      (50, 600): (8, '5/8'),
      (65, 600): (8, '3/4'),
      (15, 900): (4, '3/4'),
      (20, 900): (4, '3/4'),
      (25, 900): (4, '7/8'),
      (32, 900): (4, '7/8'),
      (40, 900): (4, '1'),
      (50, 900): (8, '7/8'),
      (65, 900): (8, '1'),
      (15, 1500): (4, '3/4'),
      (20, 1500): (4, '3/4'),
      (25, 1500): (4, '7/8'),
      (32, 1500): (4, '7/8'),
      (40, 1500): (4, '1'),
      (50, 1500): (8, '7/8'),
      (65, 1500): (8, '1'),
    };
    for (final e in expected.entries) {
      final b = FlangeCatalog.lookup(e.key.$1, e.key.$2);
      expect(b, isNotNull, reason: 'DN${e.key.$1} × #${e.key.$2}');
      expect((b!.boltCount, b.boltSize), e.value,
          reason: 'DN${e.key.$1} × #${e.key.$2}');
    }
    // Pełna siatka DN × klasa z listy wyboru — żadnej dziury.
    for (final dn in FlangeCatalog.dns) {
      for (final cls in FlangeCatalog.classes) {
        expect(FlangeCatalog.lookup(dn, cls), isNotNull, reason: 'DN$dn × #$cls');
      }
    }
    final dn100 = FlangeCatalog.lookup(100, 150);
    expect(dn100, isNotNull);
    expect(dn100!.boltCount, 8);
    expect(dn100.boltSize, '5/8');
  });
}
