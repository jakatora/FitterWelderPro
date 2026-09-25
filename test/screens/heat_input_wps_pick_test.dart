// Heat input ↔ Biblioteka WPS: „Wybierz WPS" wypełnia zakres min–max
// i ustawia normę liczenia z WPS (EN 1011-1 z η albo ASME IX bez η) — zakres
// ma sens tylko w konwencji, w której go zapisano.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:cut_list_app/domain/welding/heat_input.dart';
import 'package:cut_list_app/domain/wps/wps_record.dart';
import 'package:cut_list_app/i18n/app_language.dart';
import 'package:cut_list_app/screens/heat_input_screen.dart';

const WpsRecord _asme = WpsRecord(
  id: 'a',
  wpsNo: 'WPS-111-02',
  revision: 'C',
  processes: '111',
  heatInputMinKjMm: 0.55,
  heatInputMaxKjMm: 0.6,
  heatInputMethod: HeatInputStandard.asmeIx,
  createdAt: 0,
  updatedAt: 0,
);

const WpsRecord _noRange = WpsRecord(
  id: 'b',
  wpsNo: 'WPS-141-09',
  processes: '141',
  createdAt: 0,
  updatedAt: 0,
);

Future<void> _pump(WidgetTester tester) async {
  SharedPreferences.setMockInitialValues({});
  tester.view.physicalSize = const Size(1200, 3400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(AppLanguageScope(
    controller: AppLanguageController(AppLanguage.pl),
    child: MaterialApp(
      home: HeatInputScreen(wpsLoader: () async => const [_asme, _noRange]),
    ),
  ));
  await tester.pumpAndSettle();
}

Finder _field(String label) => find.byWidgetPredicate(
    (w) => w is TextField && w.decoration?.labelText == label);

String _text(WidgetTester tester, String label) =>
    tester.widget<TextField>(_field(label)).controller!.text;

void main() {
  testWidgets(
      '„Wybierz WPS" wypełnia min–max i przełącza na ASME IX; ręczna zmiana '
      'zakresu odpina WPS', (tester) async {
    await _pump(tester);
    expect(_text(tester, 'Min'), isEmpty);
    expect(tester.widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'EN 1011-1')).selected,
        isTrue);

    await tester.ensureVisible(find.text('Wybierz WPS'));
    await tester.tap(find.text('Wybierz WPS'));
    await tester.pumpAndSettle();
    expect(find.text('WPS-111-02 rev. C'), findsOneWidget);
    await tester.tap(find.text('WPS-111-02 rev. C'));
    await tester.pumpAndSettle();

    expect(_text(tester, 'Min'), '0.55');
    expect(_text(tester, 'Max'), '0.6');
    expect(
        tester.widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'ASME IX')).selected,
        isTrue,
        reason: 'norma liczenia z WPS');
    expect(find.text('Zakres i norma liczenia z WPS-111-02 rev. C.'),
        findsOneWidget);
    // SMAW 22 V / 110 A / 200 mm/min wg ASME (bez η): 0,726 kJ/mm > 0,6.
    expect(find.textContaining('POZA zakresem WPS'), findsOneWidget);

    await tester.enterText(_field('Max'), '0.8');
    await tester.pump();
    expect(find.text('Zakres i norma liczenia z WPS-111-02 rev. C.'),
        findsNothing);
  });

  testWidgets('WPS bez zakresu energii — komunikat, pola bez zmian',
      (tester) async {
    await _pump(tester);
    await tester.ensureVisible(find.text('Wybierz WPS'));
    await tester.tap(find.text('Wybierz WPS'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('WPS-141-09'));
    await tester.pumpAndSettle();
    expect(find.textContaining('nie ma zakresu energii liniowej'),
        findsOneWidget);
    expect(_text(tester, 'Min'), isEmpty);
    expect(_text(tester, 'Max'), isEmpty);
  });
}
