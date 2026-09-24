import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:cut_list_app/data/tungsten.dart';
import 'package:cut_list_app/i18n/app_language.dart';
import 'package:cut_list_app/screens/tungsten_screen.dart';
import 'package:cut_list_app/screens/welder_pipes_screen.dart';

import '../support/test_database.dart';

Widget _app(Widget child, {AppLanguage lang = AppLanguage.en}) =>
    AppLanguageScope(
      controller: AppLanguageController(lang),
      child: MaterialApp(home: child),
    );

Future<void> _pumpTall(WidgetTester tester, Widget child,
    {AppLanguage lang = AppLanguage.en}) async {
  tester.view.physicalSize = const Size(1200, 4000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(_app(child, lang: lang));
  for (var i = 0; i < 3; i++) {
    await flushTestDatabase(tester);
    await tester.pump();
  }
  await tester.pumpAndSettle();
}

Finder _field(String label) => find.byWidgetPredicate(
      (widget) => widget is TextField && widget.decoration?.labelText == label,
      description: 'TextField labelled $label',
    );

Future<void> _openGasTab(WidgetTester tester) async {
  await tester.tap(find.text('Gases'));
  await tester.pumpAndSettle();
}

/// Purge advice paragraph shown in both tabs (AMP and Gases).
String _purgeAdviceText(WidgetTester tester) {
  final texts = tester
      .widgetList<Text>(find.byType(Text))
      .map((t) => t.data ?? '')
      .where((s) => s.startsWith('Backing gas (purge): pre-purge'))
      .toList();
  expect(texts, hasLength(1), reason: 'exactly one purge advice paragraph');
  return texts.single;
}

void main() {
  useTestDatabase();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('Rury spawacza — AMP', () {
    testWidgets(
        '45 A: elektroda z tej samej tabeli co ekran Wolfram (Ø 1.0 mm)',
        (tester) async {
      // Domyślnie: OD 60.3 × t 2.0, SS, TIG z drutem → punkt startowy 45 A
      // (tabela t=2.0 → 45 A, współczynnik OD ≈ 1.0).
      await _pumpTall(tester, const WelderPipesScreen());
      expect(find.text('45 A'), findsOneWidget);

      // lib/data/tungsten.dart: 1.0 mm = 15–80 A DC−, 1.6 mm = 70–150 A.
      final fromTable = sizeForCurrent(45)!.diaMm;
      expect(fromTable, 1.0);
      expect(find.text('Ø ${fromTable.toStringAsFixed(1)} mm  (WL20 / WC20)'),
          findsOneWidget);
      expect(find.text('Ø 1.6 mm  (WL20 / WC20)'), findsNothing);

      // Ten sam prąd na ekranie Wolfram → ta sama średnica.
      await _pumpTall(tester, const TungstenScreen());
      await tester.enterText(_field('Welding current (A, DC-)'), '45');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Ø 1.6 mm'));
      await tester.pumpAndSettle();
      expect(find.textContaining('From table: Ø 1.0 mm'), findsOneWidget);
    });

    testWidgets('pokazuje, że wiąże WPS / specyfikacja projektu',
        (tester) async {
      await _pumpTall(tester, const WelderPipesScreen());
      expect(
          find.text(
              'Guidance only — the WPS / project specification is binding.'),
          findsOneWidget);
    });

    testWidgets('PL: zdanie o WPS po polsku', (tester) async {
      await _pumpTall(tester, const WelderPipesScreen(),
          lang: AppLanguage.pl);
      expect(
          find.text('Wynik pomocniczy — wiąże WPS / specyfikacja projektu.'),
          findsOneWidget);
    });

    testWidgets('aluminium: WZ8 biała, WP zielona (ISO 6848)',
        (tester) async {
      await _pumpTall(tester, const WelderPipesScreen());
      await tester.tap(find.text('SS (stainless)'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Aluminum').last);
      await tester.pumpAndSettle();

      expect(find.textContaining('WZ8 (green)'), findsNothing);
      expect(find.textContaining('WZ8 zirconiated (white)'), findsOneWidget);
      expect(find.textContaining('WP pure tungsten (green)'), findsOneWidget);
    });

    testWidgets(
        'purge: duży przepływ tylko na przedmuch, podczas spawania ≤ 5 L/min',
        (tester) async {
      await _pumpTall(tester, const WelderPipesScreen());

      // Stara wersja pokazywała jedną wartość 12–25 L/min bez rozróżnienia
      // faz — przy cienkiej rurze to grozi wklęsłą granią podczas spawania.
      expect(find.text('Backing gas (purge)'), findsNothing);
      expect(find.text('Backing gas — pre-purge'), findsOneWidget);
      expect(find.text('15–20 L/min'), findsOneWidget);
      expect(find.text('Backing gas — while welding'), findsOneWidget);
      expect(find.text('≤ 5 L/min'), findsOneWidget);

      final ampAdvice = _purgeAdviceText(tester);
      expect(ampAdvice, contains('15–20 L/min'));
      expect(ampAdvice, contains('5 L/min or less'));
      expect(ampAdvice, contains('concave root'));

      await _openGasTab(tester);
      expect(_purgeAdviceText(tester), ampAdvice,
          reason: 'AMP i Gazy muszą mówić to samo o przepływie purge');
    });
  });

  group('Rury spawacza — Gazy', () {
    testWidgets('N = 6 → ≈ 521 ppm O₂ i ostrzeżenie o analizatorze',
        (tester) async {
      await _pumpTall(tester, const WelderPipesScreen());
      await _openGasTab(tester);

      // Model z zakładki O₂ (welder_tools_screen.dart): C = C₀·e^(−N),
      // C₀ = 210 000 ppm → 210 000·e^−6 = 520.5 ppm.
      final expected = 210000 * math.exp(-6);
      expect(expected.toStringAsFixed(0), '521');
      expect(find.textContaining('≈ 521 ppm'), findsOneWidget);
      expect(find.textContaining('AWS D18.2 sample: level 6 (500 ppm)'),
          findsOneWidget);
      expect(
          find.text('Time is indicative — verify with an O₂ analyser.'),
          findsOneWidget);

      await tester.enterText(_field('Volume changes N'), '10');
      await tester.pumpAndSettle();
      expect(find.textContaining('≈ 9.5 ppm'), findsOneWidget);
      expect(find.textContaining('AWS D18.2 sample: level 1 (10 ppm)'),
          findsOneWidget);
    });

    testWidgets('PL: czas orientacyjny — zweryfikuj analizatorem O₂',
        (tester) async {
      await _pumpTall(tester, const WelderPipesScreen(),
          lang: AppLanguage.pl);
      await tester.tap(find.text('Gazy'));
      await tester.pumpAndSettle();
      expect(find.text('Czas orientacyjny — zweryfikuj analizatorem O₂.'),
          findsOneWidget);
    });

    testWidgets('etykieta wylotów pokazuje wpisaną średnicę otworu',
        (tester) async {
      await _pumpTall(tester, const WelderPipesScreen());
      await _openGasTab(tester);

      // Domyślnie 2 × Ø2.4 mm — a nie zaszyte „Ø1.2 mm”.
      expect(find.textContaining('Outlets: 2×Ø2.4 mm | outlet velocity'),
          findsOneWidget);
      expect(find.textContaining('Ø1.2 mm'), findsNothing);

      await tester.enterText(_field('Outlet hole diameter [mm]'), '3');
      await tester.pumpAndSettle();
      expect(find.textContaining('Outlets: 2×Ø3.0 mm'), findsOneWidget);
    });
  });
}
