// Pierwsza część kroku „Zamknąć kolejkę P0 audytu” — moduł bolt-torque.
//
// Wartości oczekiwane policzone ręcznie według wzorów z nagłówka ekranu
// (ASME PCC-1, gwint UNC):
//   5/8": d = 15,88 mm, 11 TPI → p = 25,4/11 = 2,30909 mm
//   d_eff = 15,88 − 0,9382·p = 13,71361 mm
//   A_s   = π/4 · d_eff² = 147,704 mm²
//   B7, 50% SMYS: σ = 362 MPa → F = 53 469 N (53,5 kN)
//   pasta Cu, K = 0,16: T = 0,16 · 53 469 · 0,01588 = 135,85 N·m → „136”
//   ft·lb: 135,85 / 1,3558 = 100,2 → „100”
//   B8M (207 MPa): σ = 103,5 → F = 15 287 N → T = 38,84 → „39”
//   sucho, K = 0,20: T = 169,82 → „170”

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
  testWidgets('domyślnie 5/8" B7, pasta Cu, 50% SMYS daje 136 N·m',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    await _pumpScreen(tester);

    expect(find.text('136'), findsOneWidget);
    expect(find.text('100 ft·lb'), findsOneWidget);
    expect(find.text('Preload: 53.5 kN'), findsOneWidget);
    expect(find.text('50 %'), findsOneWidget);
  });

  testWidgets('B8M z zapisanych ustawień daje 39 N·m, nie wartość B7',
      (tester) async {
    SharedPreferences.setMockInitialValues({'bolt_torque.grade': 'B8M'});
    await _pumpScreen(tester);

    expect(find.text('39'), findsOneWidget);
    expect(find.text('136'), findsNothing);
  });

  testWidgets('smar suchy (K = 0,20) daje 170 N·m', (tester) async {
    SharedPreferences.setMockInitialValues({'bolt_torque.lube': 'dry'});
    await _pumpScreen(tester);

    expect(find.text('170'), findsOneWidget);
    expect(find.text('136'), findsNothing);
  });

  testWidgets('preset DN100 × Class 150 pokazuje 8 śrub 5/8" i 136 N·m',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      'bolt_torque.flange_dn': 100,
      'bolt_torque.flange_class': 150,
    });
    await _pumpScreen(tester);

    expect(find.text('8 × 5/8" bolts'), findsOneWidget);
    expect(find.text('136'), findsOneWidget);
    expect(
      find.text('8 bolts × 136 N·m, star 25/50/75/100%'),
      findsOneWidget,
    );
  });

  test('katalog B16.5 odrzuca DN15 × Class 1500', () {
    expect(FlangeCatalog.lookup(15, 1500), isNull);
    final dn100 = FlangeCatalog.lookup(100, 150);
    expect(dn100, isNotNull);
    expect(dn100!.boltCount, 8);
    expect(dn100.boltSize, '5/8');
  });
}
