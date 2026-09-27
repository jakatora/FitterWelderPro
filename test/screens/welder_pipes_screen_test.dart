import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:cut_list_app/data/tungsten.dart';
import 'package:cut_list_app/i18n/app_language.dart';
import 'package:cut_list_app/screens/tungsten_screen.dart';
import 'package:cut_list_app/screens/welder_pipes_screen.dart';
import 'package:cut_list_app/services/weld_timer_service.dart';

import '../support/fake_weld_timer_effects.dart';
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

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    // Minutnik purge w zakładce Gazy żyje w serwisie — atrapa skutków
    // ubocznych, bez platformy.
    WeldTimerService.instance =
        WeldTimerService(effects: FakeEffects(), observeLifecycle: false);
  });
  tearDown(() => WeldTimerService.instance.dispose());

  group('Rury spawacza — AMP', () {
    testWidgets(
        'AMP = „Startowe” dla tej samej rury; elektroda i gaz jak ekran Wolfram',
        (tester) async {
      // Domyślnie: OD 60.3 × t 2.0, SS, TIG z drutem. Seed „Startowe”
      // APPROVED_PIPE_TIGWIRE_60_2: SS, TIG z drutem, Ø60,3 × 2,0 → 60 A.
      // Dawniej kalkulator dawał 45 A, a lista 60 A.
      await _pumpTall(tester, const WelderPipesScreen());
      expect(find.text('60 A'), findsOneWidget);
      expect(find.textContaining('From “Starter”: Ø60.3 × 2.00 mm → 60 A'),
          findsOneWidget);

      // lib/data/tungsten.dart: 1.0 mm = 15–80 A DC−; gaz dla 1.0 mm 6–8.
      final fromTable = sizeForCurrent(60)!.diaMm;
      expect(fromTable, 1.0);
      expect(find.text('Ø ${fromTable.toStringAsFixed(1)} mm  (WL20 / WC20)'),
          findsOneWidget);
      final gas = tungstenExtrasFor(fromTable)!;
      expect(find.text('${gas.argonMinLpm}–${gas.argonMaxLpm} L/min  (Ar)'),
          findsOneWidget);

      // Ta sama rura na liście „Startowe”: ten sam prąd, elektroda i gaz.
      await tester.tap(find.text('Starter'));
      for (var i = 0; i < 4; i++) {
        await flushTestDatabase(tester);
        await tester.pump(const Duration(milliseconds: 50));
      }
      await tester.pumpAndSettle();
      await tester.enterText(
          find.widgetWithText(TextField, 'Search starter AMP'), '60.3');
      for (var i = 0; i < 4; i++) {
        await flushTestDatabase(tester);
        await tester.pump(const Duration(milliseconds: 50));
      }
      await tester.pumpAndSettle();
      expect(
          find.textContaining(
              'Amps: 60 A\nElectrode: Ø1.0 | Torch: 6–8 L/min'),
          findsOneWidget);
      expect(find.textContaining('the WPS / project specification is binding'),
          findsOneWidget);

      // Ten sam prąd na ekranie Wolfram → ta sama średnica i gaz.
      await _pumpTall(tester, const TungstenScreen());
      await tester.enterText(_field('Welding current (A, DC-)'), '60');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Ø 1.6 mm'));
      await tester.pumpAndSettle();
      expect(find.textContaining('From table: Ø 1.0 mm'), findsOneWidget);
      expect(find.textContaining('the WPS and the electrode maker'),
          findsOneWidget);
      // Oznaczenia ISO 6848:2015 obok dawnych.
      expect(find.text('WL20 (WLa20)'), findsOneWidget);
      expect(find.text('WZ8 (WZr8)'), findsOneWidget);
    });

    testWidgets('CS dostaje więcej prądu niż SS (ta sama rura)', (tester) async {
      await _pumpTall(tester, const WelderPipesScreen());
      await tester.enterText(_field('Wall thickness t [mm]'), '3');
      await tester.pumpAndSettle();
      // SS, z drutem, Ø60,3 × 3,0 → 110 A (seed); CS → 120 A (seed).
      expect(find.text('110 A'), findsOneWidget);
      await tester.tap(find.text('SS (stainless)'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('CS (carbon steel)').last);
      await tester.pumpAndSettle();
      expect(find.text('120 A'), findsOneWidget);
    });

    testWidgets('poza danymi: brak liczby, nie zgadywanie', (tester) async {
      await _pumpTall(tester, const WelderPipesScreen());
      await tester.enterText(_field('Pipe OD [mm]'), '1000');
      await tester.pumpAndSettle();
      expect(find.textContaining('No starting data'), findsOneWidget);
      expect(find.textContaining(' A'), findsNothing);
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

    // Przegląd G4: „złoty środek” dawał 11 m/s przy progu ostrzeżenia 6 m/s.
    // 2 × Ø2,4 → Q = 1,1 L/min (2 m/s).
    testWidgets('złoty środek nie wywołuje ostrzeżenia o back-pressure',
        (tester) async {
      await _pumpTall(tester, const WelderPipesScreen());
      await _openGasTab(tester);
      await tester.tap(find.text('Set Q (golden middle)'));
      await tester.pumpAndSettle();
      expect(
          tester.widget<TextField>(_field('Internal gas flow Q [L/min]'))
              .controller!
              .text,
          '1.1');
      expect(find.textContaining('Risk of back-pressure'), findsNothing);
      expect(find.textContaining('close to the comfort limit'), findsNothing);
      expect(find.textContaining('outlet velocity (indicator): 2.03 m/s'),
          findsOneWidget);
      expect(find.text('Guidance only — the WPS / project specification is binding.'),
          findsOneWidget);
    });

    testWidgets('minutnik pre-purge → WeldTimerService (alarm), nie lokalny '
        'Timer', (tester) async {
      await _pumpTall(tester, const WelderPipesScreen());
      await _openGasTab(tester);
      await tester.ensureVisible(find.text('Start timer (pre-purge)'));
      await tester.tap(find.text('Start timer (pre-purge)'));
      await tester.pump();
      final t = WeldTimerService.instance;
      expect(t.mode, WeldTimerMode.purge);
      expect(t.running, isTrue);
      // V = π·28,15²·300 mm³ = 0,7469 L; N = 6, Q = 2 → 2,2407 min = 134,4 s.
      expect(t.purgeSeconds, 135);
      t.reset();
      await tester.pump();
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
