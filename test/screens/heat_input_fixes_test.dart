// Heat input + Preheat/CE — poprawki z audytu 2026-09. Każdy test pada na
// starej wersji ekranu:
//  • domyślny zakres WPS 1,0–2,5 kJ/mm → domyślne parametry każdego procesu
//    świeciły „POZA zakresem WPS”;
//  • „pasmo tolerancji ±10 %” — wynik poza WPS był złoty „nadal OK”;
//  • brak trybu ASME IX (QW-409.1 liczy bez η);
//  • FCAW-S η 0,75 (EN 1011-1: 0,8);
//  • A106 B: katalog „10 °C” obok „125 °C” z reguły CE bez wyjaśnienia,
//    notka preheat po polsku w wersji EN.
// Grupa „przeniesione z kalkulatorów spawacza" — testy dawnych zakładek
// Heat Input / Temperatura (WelderToolsScreen), które dublowały ten ekran.
// Liczby — patrz test/domain/welding/*.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:cut_list_app/i18n/app_language.dart';
import 'package:cut_list_app/screens/heat_input_screen.dart';

Widget _app() => AppLanguageScope(
      controller: AppLanguageController(AppLanguage.en),
      child: const MaterialApp(home: HeatInputScreen()),
    );

Future<void> _pump(WidgetTester tester) async {
  SharedPreferences.setMockInitialValues({});
  tester.view.physicalSize = const Size(1200, 3400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(_app());
  await tester.pumpAndSettle();
}

Finder _field(String label) => find.byWidgetPredicate(
      (w) => w is TextField && w.decoration?.labelText == label,
      description: 'TextField "$label"',
    );

Future<void> _enter(WidgetTester tester, String label, String value) async {
  await tester.enterText(_field(label), value);
  await tester.pump();
}

const _disclaimer = 'the WPS / project specification is binding';

void main() {
  group('Heat input', () {
    testWidgets('bez wpisanego zakresu WPS nie ma werdyktu', (tester) async {
      await _pump(tester);

      for (final process in ['SMAW', 'GMAW', 'FCAW-G', 'FCAW-S', 'GTAW', 'SAW']) {
        await tester.tap(find.text(process));
        await tester.pump();
        expect(find.textContaining('OUT of WPS range'), findsNothing,
            reason: process);
        expect(find.textContaining('Within WPS range'), findsNothing,
            reason: process);
      }
      expect(find.textContaining('Enter the WPS range'), findsOneWidget);
      expect(find.textContaining(_disclaimer), findsOneWidget);
    });

    testWidgets('wynik tuż ponad max WPS jest POZA zakresem (bez ±10 %)',
        (tester) async {
      await _pump(tester);
      // SMAW 22 V / 110 A / 200 mm/min → 0,5808 kJ/mm (EN, η 0,8)
      await _enter(tester, 'Min', '0.50');
      await _enter(tester, 'Max', '0.55');

      expect(find.text('0.58'), findsOneWidget);
      expect(find.textContaining('OUT of WPS range'), findsOneWidget);
      expect(find.textContaining('tolerance'), findsNothing);

      await _enter(tester, 'Max', '0.60');
      expect(find.textContaining('Within WPS range'), findsOneWidget);
    });

    testWidgets('przełącznik EN (η) / ASME IX (bez η): 0,48 vs 0,80 kJ/mm',
        (tester) async {
      await _pump(tester);
      await tester.tap(find.text('GTAW')); // 12 V / 100 A / 90 mm/min
      await tester.pump();
      expect(find.text('0.48'), findsOneWidget);

      await tester.tap(find.text('ASME IX'));
      await tester.pump();
      expect(find.text('0.80'), findsOneWidget);
      expect(find.textContaining('QW-409.1'), findsWidgets);

      await tester.tap(find.text('EN 1011-1'));
      await tester.pump();
      expect(find.text('0.48'), findsOneWidget);
    });

    // ASME IX GTAW 12 V / 100 A / 90 mm/min = 0,80 kJ/mm = 20,3 kJ/in
    // = 20 320 J/in; zakres WPS wpisany w kJ/mm przeliczany przy zmianie.
    testWidgets('jednostki kJ/mm ↔ kJ/in ↔ J/in dla wyniku i zakresu WPS',
        (tester) async {
      await _pump(tester);
      await tester.tap(find.text('GTAW'));
      await tester.pump();
      await tester.tap(find.text('ASME IX'));
      await tester.pump();
      await _enter(tester, 'Max', '1');
      expect(find.text('0.80'), findsOneWidget);

      await tester.tap(find.text('J/in'));
      await tester.pump();
      expect(find.text('20320'), findsOneWidget);
      expect(tester.widget<TextField>(_field('Max')).controller!.text, '25400');
      expect(find.textContaining('Within WPS range'), findsOneWidget);

      await tester.tap(find.text('kJ/in'));
      await tester.pump();
      expect(find.text('20.3'), findsOneWidget);
      expect(tester.widget<TextField>(_field('Max')).controller!.text, '25.4');
    });

    // L = 300 mm, t = 90 s → v = 300/90·60 = 200 mm/min.
    testWidgets('v z długości ściegu i czasu jarzenia', (tester) async {
      await _pump(tester);
      await _enter(tester, 'Travel speed', '150');
      await _enter(tester, 'Bead length', '300');
      await _enter(tester, 'Arc time', '90');
      await tester.tap(find.text('Use v = 200 mm/min'));
      await tester.pump();
      expect(tester.widget<TextField>(_field('Travel speed')).controller!.text,
          '200');
      // SMAW 22 V / 110 A / 200 mm/min → 0,58 kJ/mm
      expect(find.text('0.58'), findsOneWidget);
    });

    testWidgets('FCAW-S ma η 0,80 (EN 1011-1), nie 0,75', (tester) async {
      await _pump(tester);
      await tester.tap(find.text('FCAW-S'));
      await tester.pump();
      expect(find.textContaining('Arc efficiency FCAW-S: 80%'), findsOneWidget);
    });
  });

  group('Preheat / CE', () {
    testWidgets('A106 B: metody nazwane, minimum kodowe opisane, bez PL w EN',
        (tester) async {
      await _pump(tester);
      await tester.tap(find.widgetWithText(Tab, 'Preheat / CE'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('A106 B'));
      await tester.pumpAndSettle();

      // t = 15 mm (domyślnie); CE 0,427
      expect(find.text('0.427'), findsOneWidget);
      // reguła orientacyjna CE (pasmo 0,35–0,45)
      expect(find.text('125 °C'), findsOneWidget);
      // Seferian: [C]c 0,3678 · 1,075 → 133 °C
      expect(find.text('133 °C'), findsOneWidget);
      // minimum kodowe ASME B31.3 Tab. 330.1.1, P-No 1, t ≤ 25 mm → 10 °C —
      // w wydaniu ≥ 2014 i w zastąpionym 2012 (dwa wiersze z wydaniem).
      expect(find.text('10 °C'), findsNWidgets(2));
      expect(find.textContaining('B31.3 ≥ 2014'), findsWidgets);
      expect(find.textContaining('B31.3-2012'), findsWidgets);
      expect(find.textContaining('B31.3'), findsWidgets);
      expect(find.textContaining('different questions'), findsOneWidget,
          reason: 'wyjaśnienie, dlaczego liczby się różnią');

      expect(find.textContaining('niski preheat'), findsNothing);
      expect(find.textContaining('Bez preheat'), findsNothing);
      expect(find.textContaining(_disclaimer), findsOneWidget);
    });

    testWidgets('P91 pokazuje P-No 15E', (tester) async {
      await _pump(tester);
      await tester.tap(find.widgetWithText(Tab, 'Preheat / CE'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('P91 / T91'));
      await tester.pumpAndSettle();

      expect(find.textContaining('P-No 15E'), findsWidgets);
      expect(find.textContaining('P-No 5 '), findsNothing);
    });

    // Przegląd G4: P91 (9 % Cr, poniżej progu nierdzewnej) dostawał
    // Seferiana 365 °C i czerwone „CE ≥ 0.45” (CE 2,235) obok minimum 200 °C.
    testWidgets('P91 / P22: bez Seferiana i reguły CE; minimum kodowe i WPS',
        (tester) async {
      await _pump(tester);
      await tester.tap(find.widgetWithText(Tab, 'Preheat / CE'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('P91 / T91'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Seferian ('), findsNothing);
      expect(find.textContaining('CE rule of thumb', findRichText: true),
          findsNothing);
      expect(find.textContaining('CE RULE OF THUMB', findRichText: true),
          findsNothing);
      expect(find.text('365 °C'), findsNothing);
      expect(find.text('2.235'), findsNothing);
      expect(find.textContaining('high risk of cold cracking'), findsNothing);
      expect(find.textContaining('are not meant for it'), findsOneWidget);
      // P-No 15E: 200 °C w obu wydaniach.
      expect(find.text('200 °C'), findsNWidgets(2));
      expect(find.text('Temperature from the WPS'), findsOneWidget);
      // Max interpass z katalogu P91, nie „typowo 250 °C”.
      expect(find.text('250–300 °C'), findsOneWidget);

      // P22 (5A, SMTS 60 ksi), t = 20 mm: aktualne 150 °C, 2012: 175 °C.
      await tester.tap(find.text('P22 / T22'));
      await tester.pumpAndSettle();
      await _enter(tester, 'Thickness', '20');
      expect(find.text('150 °C'), findsOneWidget);
      expect(find.text('175 °C'), findsOneWidget);
      expect(find.textContaining('Seferian ('), findsNothing);
    });

    testWidgets('DN/SCH ustawia grubość do obliczeń', (tester) async {
      SharedPreferences.setMockInitialValues(
          {'heat_input_pipe_dn': 200, 'heat_input_pipe_sch': '80'});
      tester.view.physicalSize = const Size(1200, 3400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(_app());
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(Tab, 'Preheat / CE'));
      await tester.pumpAndSettle();

      // ASME B36.10M DN200 Sch 80: 12,70 mm.
      expect(tester.widget<TextField>(_field('Thickness')).controller!.text,
          '12.7');
      expect(find.textContaining('t = 13 mm'), findsOneWidget);
    });

    testWidgets('wybór gatunku nie wpisuje „typowego” zakresu jako WPS',
        (tester) async {
      await _pump(tester);
      await tester.tap(find.widgetWithText(Tab, 'Preheat / CE'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('A106 B'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(Tab, 'Heat input'));
      await tester.pumpAndSettle();

      expect(find.textContaining('OUT of WPS range'), findsNothing);
      expect(find.textContaining('Within WPS range'), findsNothing);
    });
  });

  // Zakładki „Heat Input" i „Temperatura" w kalkulatorach spawacza dublowały
  // ten ekran i zostały usunięte. Ich testy i funkcje, których tu brakowało
  // (η z WPS, Seferian [C], max interpass, ostrzeżenie CE), są teraz tutaj.
  group('przeniesione z kalkulatorów spawacza', () {
    Future<void> openPreheat(WidgetTester tester) async {
      await tester.tap(find.widgetWithText(Tab, 'Preheat / CE'));
      await tester.pumpAndSettle();
    }

    testWidgets('tytuł jak kafel w menu: „Heat input and CE”', (tester) async {
      await _pump(tester);
      expect(find.text('Heat input and CE'), findsOneWidget);
      expect(find.text('Heat input + Preheat'), findsNothing);
    });

    testWidgets('Seferian: C 0,20 / Mn 1,50 → 129 / 145 / 167 °C, [C] widoczne',
        (tester) async {
      await _pump(tester);
      await openPreheat(tester);
      await _enter(tester, 'Mn', '1.50'); // C 0,20 domyślnie, reszta 0

      for (final (t, tp, totalCe) in [
        ('10', '129 °C', '0.385'),
        ('30', '145 °C', '0.422'),
        ('60', '167 °C', '0.477'),
      ]) {
        await _enter(tester, 'Thickness', t);
        expect(find.text(tp), findsOneWidget, reason: 't = $t mm');
        expect(find.textContaining('[C] with thickness = $totalCe'),
            findsOneWidget,
            reason: 't = $t mm');
      }
      expect(find.text('0.450'), findsOneWidget, reason: 'CE IIW');
      expect(find.textContaining('13916'), findsNothing,
          reason: 'EN ISO 13916 to pomiar temperatury, nie metoda obliczeń');
      expect(find.textContaining('EN 1011-2'), findsWidgets);
      expect(find.textContaining(_disclaimer), findsOneWidget);
      expect(find.textContaining('NaN'), findsNothing);
    });

    testWidgets('CE ≥ 0,45: ostrzeżenie o pękaniu na zimno; typowa max '
        'temp. międzyściegowa', (tester) async {
      await _pump(tester);
      await openPreheat(tester);

      // Domyślnie C 0,20 / Mn 1,00 → CE 0,367 — bez ostrzeżenia.
      expect(find.text('0.367'), findsOneWidget);
      expect(find.textContaining('high risk of cold cracking'), findsNothing);
      expect(find.textContaining('Max. interpass temp. (typical'),
          findsOneWidget);
      expect(find.text('250 °C'), findsOneWidget);

      // C 0,20 / Mn 1,80 → CE 0,500.
      await _enter(tester, 'Mn', '1.80');
      expect(find.text('0.500'), findsOneWidget);
      expect(find.textContaining('high risk of cold cracking'), findsOneWidget);
    });

    testWidgets('stal 316L: zamiast CE komunikat, z typową max interpass',
        (tester) async {
      await _pump(tester);
      await openPreheat(tester);
      await tester.tap(find.text('316 / 316L'));
      await tester.pumpAndSettle();

      expect(find.textContaining('do not apply'), findsOneWidget);
      expect(find.textContaining('150–175 °C'), findsOneWidget);
      // Metody z CE, ostrzeżenie i wiersz „typowo 250 °C” dotyczą stali C-Mn.
      expect(find.textContaining('Seferian ('), findsNothing);
      expect(find.textContaining('high risk of cold cracking'), findsNothing);
      expect(find.textContaining('Max. interpass temp. (typical'), findsNothing);
    });

    testWidgets('η z WPS nadpisuje η procesu; zła wartość nie daje NaN',
        (tester) async {
      await _pump(tester);
      const eta = 'η from WPS (optional)';

      await tester.tap(find.text('GTAW')); // 12 V / 100 A / 90 mm/min
      await tester.pump();
      expect(find.text('0.48'), findsOneWidget, reason: 'η 0,60 (EN 1011-1)');
      expect(find.textContaining('Arc efficiency GTAW: 60%'), findsOneWidget);

      // Energia łuku 12·100·60/90/1000 = 0,80 kJ/mm × η z WPS 0,80 = 0,64.
      // Przecinek — tak wpisuje η polska klawiatura dziesiętna.
      await _enter(tester, eta, '0,8');
      expect(find.text('0.64'), findsOneWidget);
      expect(find.textContaining('η from WPS: 0.80'), findsOneWidget);

      await _enter(tester, eta, '1.5');
      expect(find.text('Value must be ≤ 1'), findsOneWidget);
      expect(find.textContaining('Check η from WPS'), findsOneWidget);
      expect(find.textContaining('NaN'), findsNothing);

      // Litery nie wejdą do pola liczbowego (filtr odrzuca całą edycję), więc
      // „zła wartość" to coś, co da się wystukać na klawiaturze: dwa
      // separatory.
      await _enter(tester, eta, 'abc');
      expect(tester.widget<TextField>(_field(eta)).controller?.text, '1.5');
      await _enter(tester, eta, '0,8,5');
      expect(find.text('Invalid number'), findsOneWidget);
      expect(find.textContaining('NaN'), findsNothing);
      // Brak wyniku to „—”, nie „0.00 kJ/mm”, i nie da się go skopiować.
      expect(find.text('0.00'), findsNothing);
      expect(find.text('—'), findsOneWidget);
      expect(find.textContaining('No result'), findsOneWidget);
      final copy = tester.widget<OutlinedButton>(find.ancestor(
          of: find.text('Copy result'), matching: find.byType(OutlinedButton)));
      expect(copy.onPressed, isNull);

      // ASME IX nie używa η — pola nie ma, wynik bez η.
      await tester.tap(find.text('ASME IX'));
      await tester.pump();
      expect(_field(eta), findsNothing);
      expect(find.text('0.80'), findsOneWidget);
      await tester.tap(find.text('EN 1011-1'));
      await tester.pump();

      // Zmiana procesu czyści η z WPS (dotyczy jednego procesu).
      await tester.tap(find.text('SMAW'));
      await tester.pump();
      expect(tester.widget<TextField>(_field(eta)).controller!.text, isEmpty);
      expect(find.textContaining('Arc efficiency SMAW: 80%'), findsOneWidget);
    });
  });
}
