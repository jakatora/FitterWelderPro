// Rury spawacza — „Moje parametry" z wpisami asystenta głosowego:
//  * pola liczbowe NOT NULL, których spawacz nie podyktował, leżą jako 0 —
//    lista pokazuje „—", nie „Ø0.0" ani „0.0 L/min";
//  * metody MAG / MMA / OTHER (obok TIG) mają etykietę, a podgląd/edycja
//    otwiera się bez wyjątku i nie zamienia metody na TIG;
//  * zakładka danych dostarczonych z aplikacją nazywa się „Startowe", nie
//    „Zatwierdzone".

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:cut_list_app/database/db.dart';
import 'package:cut_list_app/database/weld_param_dao.dart';
import 'package:cut_list_app/i18n/app_language.dart';
import 'package:cut_list_app/models/weld_param.dart';
import 'package:cut_list_app/screens/welder_pipes_screen.dart';

import '../support/test_database.dart';

WeldParam _param(String id, String method,
        {double diameter = 0,
        double electrode = 0,
        double torch = 0,
        double purge = 0,
        String material = 'CS'}) =>
    WeldParam(
      id: id,
      method: method,
      baseMaterial: material,
      welderModel: null,
      diameterMm: diameter,
      wallThicknessMm: 5,
      electrodeMm: electrode,
      torchGasLpm: torch,
      nozzleType: null,
      nozzleSize: null,
      purgeLpm: purge,
      amps: 110,
      outletHoles: 0,
      tempo: 'NORMAL',
      note: null,
      createdAt: 1,
      updatedAt: 1,
    );

Future<void> _pump(WidgetTester tester, {AppLanguage lang = AppLanguage.pl}) async {
  tester.view.physicalSize = const Size(1200, 4000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(AppLanguageScope(
    controller: AppLanguageController(lang),
    child: const MaterialApp(home: WelderPipesScreen()),
  ));
  for (var i = 0; i < 3; i++) {
    await flushTestDatabase(tester);
    await tester.pump();
  }
  await tester.pumpAndSettle();
}

Future<void> _openMyParams(WidgetTester tester, String label) async {
  await tester.tap(find.text(label));
  await tester.pump();
  for (var i = 0; i < 4; i++) {
    await flushTestDatabase(tester);
    await tester.pump(const Duration(milliseconds: 50));
  }
  await tester.pumpAndSettle();
}

void main() {
  useTestDatabase();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<void> seed(WidgetTester tester, List<WeldParam> params) =>
      tester.runAsync(() async {
        final db = await AppDatabase.get();
        await db.delete('weld_params');
        for (final p in params) {
          await WeldParamDao().insert(p);
        }
      });

  test('0 = nie podano → „—"; wartość > 0 z jednostką', () {
    expect(weldParamValue(0, 1), '—');
    expect(weldParamValue(0, 1, unit: ' L/min'), '—');
    expect(weldParamValue(8.5, 1, unit: ' L/min'), '8.5 L/min');
    expect(weldParamValue(60.3, 1), '60.3');
  });

  test('etykiety metod — także z asystenta', () {
    expect(weldParamMethodLabel('TIG_WIRE', en: false), 'TIG z drutem');
    expect(weldParamMethodLabel('MAG', en: false), 'MIG/MAG');
    expect(weldParamMethodLabel('MMA', en: false), 'MMA (elektroda otulona)');
    expect(weldParamMethodLabel('OTHER', en: false), 'Inny proces');
    expect(weldParamMethodLabel('OTHER', en: true), 'Other process');
    expect(weldParamMethodLabel('XYZ', en: false), 'XYZ');
  });

  testWidgets(
      'lista „Moje": „—" zamiast 0, etykiety MAG / MMA / OTHER; podgląd '
      'wpisu MMA otwiera się bez wyjątku i zostawia MMA', (tester) async {
    await seed(tester, [
      _param('a', 'MMA'),
      _param('b', 'MAG', diameter: 60.3, torch: 14),
      _param('c', 'OTHER', material: 'DUPLEX'),
    ]);
    await _pump(tester);
    expect(find.text('Startowe'), findsOneWidget);
    expect(find.text('Zatwierdzone'), findsNothing);
    await _openMyParams(tester, 'Moje parametry');

    expect(find.text('MMA (elektroda otulona) | CS | Ø— × t5.00'),
        findsOneWidget);
    expect(find.text('MIG/MAG | CS | Ø60.3 × t5.00'), findsOneWidget);
    expect(find.text('Inny proces | DUPLEX | Ø— × t5.00'), findsOneWidget);
    expect(find.textContaining('Ø0.0'), findsNothing);
    expect(find.textContaining('0.0 L/min'), findsNothing);
    expect(
        find.textContaining(
            'Elektroda: —  |  Palnik: —  |  Purge: —'),
        findsNWidgets(2));
    expect(find.textContaining('Palnik: 14.0 L/min'), findsOneWidget);
    expect(find.textContaining(r'\n'), findsNothing,
        reason: 'bez dosłownego „\\n" w opisie');

    await tester.tap(find.text('MMA (elektroda otulona) | CS | Ø— × t5.00'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('Moje parametry - podgląd/edycja'), findsOneWidget);
    // Metoda w oknie edycji to nadal MMA, nie „TIG z drutem".
    expect(
        find.descendant(
            of: find.byType(AlertDialog),
            matching: find.text('MMA (elektroda otulona)')),
        findsOneWidget);

    // Uzupełnienie średnicy i zapis — metoda i puste gazy zostają.
    await tester.enterText(
        find.descendant(
            of: find.byType(AlertDialog),
            matching: find.byWidgetPredicate((w) =>
                w is TextField &&
                w.decoration?.labelText == 'Średnica rury OD [mm]')),
        '114.3');
    await tester.tap(find.text('Zapisz zmiany'));
    await tester.pump();
    for (var i = 0; i < 6; i++) {
      await flushTestDatabase(tester);
      await tester.pump(const Duration(milliseconds: 50));
    }
    await tester.pumpAndSettle();
    final saved = (await tester.runAsync(() => WeldParamDao().listAll()))!
        .firstWhere((p) => p.id == 'a');
    expect(saved.method, 'MMA');
    expect(saved.diameterMm, 114.3);
    expect(saved.torchGasLpm, 0);
    expect(saved.purgeLpm, 0);
  });
}
