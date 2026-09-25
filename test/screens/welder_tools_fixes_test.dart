// Kalkulatory spawacza (4 zakładki: gaz, formowanie, timer, ciśnienie) —
// poprawki z audytu 2026-09.
//
// Zakładki „Heat Input" i „Temperatura" dublowały ekran „Heat input i CE"
// i zostały usunięte; ich testy (Seferian 129/145/167 °C, 316L bez CEV,
// k/η z procesu, EN vs ASME) są teraz w heat_input_fixes_test.dart.
//
// Każdy test pada na starej wersji ekranu:
//  • Gaz: 1050 L / „50 L gazu” = 21 butli (prawda: ~0,1 butli 50 L/200 bar).
//  • Purge: cel 0 ppm → wyjątek w build().
//  • Timer: pole „Temp. max” niczego nie robiło.
// Liczby oczekiwane — patrz test/domain/welding/*.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:cut_list_app/i18n/app_language.dart';
import 'package:cut_list_app/screens/welder_tools_screen.dart';
import 'package:cut_list_app/services/weld_timer_service.dart';
import 'package:cut_list_app/widgets/tool_registry.dart';

import '../support/fake_weld_timer_effects.dart';

Widget _app({Widget home = const WelderToolsScreen()}) => AppLanguageScope(
      controller: AppLanguageController(AppLanguage.en),
      child: MaterialApp(home: home),
    );

Future<void> _pump(WidgetTester tester,
    {Widget home = const WelderToolsScreen()}) async {
  tester.view.physicalSize = const Size(1200, 3200);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  // Nowa aplikacja za każdym razem — MaterialApp nie podmienia `home`
  // w już zbudowanym Navigatorze.
  await tester.pumpWidget(const SizedBox());
  await tester.pumpWidget(_app(home: home));
  await tester.pumpAndSettle();
}

int _selectedTab(WidgetTester tester) =>
    DefaultTabController.of(tester.element(find.byType(TabBar))).index;

Future<void> _openTab(WidgetTester tester, String label) async {
  await tester.tap(find.widgetWithText(Tab, label));
  await tester.pumpAndSettle();
}

Finder _field(String label) => find.byWidgetPredicate(
      (w) => w is TextField && w.decoration?.labelText == label,
      description: 'TextField "$label"',
    );

String _text(WidgetTester tester, String label) =>
    tester.widget<TextField>(_field(label)).controller!.text;

Future<void> _enter(WidgetTester tester, String label, String value) async {
  await tester.enterText(_field(label), value);
  await tester.pump();
}

const _disclaimer = 'the WPS / project specification is binding';

void main() {
  // Timer to serwis-singleton: świeży na każdy test, bez platformy
  // (wibracja, wakelock, powiadomienia) — patrz weld_timer_screen_test.dart.
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    WeldTimerService.instance =
        WeldTimerService(effects: FakeEffects(), observeLifecycle: false);
  });
  tearDown(() => WeldTimerService.instance.dispose());

  group('bez duplikatów heat input / podgrzewania', () {
    testWidgets('tylko 4 zakładki: gaz, formowanie, timer, ciśnienie',
        (tester) async {
      await _pump(tester);
      expect(find.byType(Tab), findsNWidgets(4));
      for (final gone in ['Heat Input', 'Preheat', 'Temperatura']) {
        expect(find.widgetWithText(Tab, gone), findsNothing, reason: gone);
      }
      // Pól heat input / CEV nie ma nigdzie na ekranie.
      expect(find.textContaining('Thermal efficiency'), findsNothing);
      expect(find.textContaining('CEV'), findsNothing);
    });

    testWidgets('initialTab otwiera wskazaną zakładkę', (tester) async {
      for (final (tab, visibleField) in [
        (WelderToolsScreen.tabGas, 'Number of welds'),
        (WelderToolsScreen.tabPurge, 'Section length to purge (mm)'),
        (WelderToolsScreen.tabPressure, 'Value'),
      ]) {
        await _pump(tester, home: WelderToolsScreen(initialTab: tab));
        expect(_selectedTab(tester), tab);
        expect(_field(visibleField), findsOneWidget, reason: 'tab $tab');
      }
      // Timer nie ma pól w trybie „spawanie” — sprawdzamy przyciski trybu.
      await _pump(tester,
          home: const WelderToolsScreen(initialTab: WelderToolsScreen.tabTimer));
      expect(_selectedTab(tester), WelderToolsScreen.tabTimer);
      expect(find.text('Cooldown'), findsOneWidget);
      // Indeks spoza zakresu nie wywraca ekranu.
      await _pump(tester, home: const WelderToolsScreen(initialTab: 99));
      expect(_selectedTab(tester), WelderToolsScreen.tabCount - 1);
    });

    testWidgets('kafel „Gaz, formowanie i timer” otwiera zakładkę Gaz',
        (tester) async {
      final spec = kToolRegistry.firstWhere((t) => t.id == 'welder_calculators');
      late Widget built;
      await tester.pumpWidget(Builder(builder: (context) {
        built = spec.builder(context);
        return const SizedBox();
      }));
      expect(built, isA<WelderToolsScreen>());
      expect((built as WelderToolsScreen).initialTab, WelderToolsScreen.tabGas);

      await _pump(tester, home: built);
      expect(_selectedTab(tester), WelderToolsScreen.tabGas);
      expect(_field('Number of welds'), findsOneWidget);
    });
  });

  group('Gaz', () {
    testWidgets('1050 L przy butli 50 L × 200 bar to ~0,1 butli, nie 21',
        (tester) async {
      await _pump(tester);
      await _openTab(tester, 'Gas');

      expect(_text(tester, 'Cylinder water capacity'), '50');
      expect(_text(tester, 'Fill pressure'), '200');

      await _enter(tester, 'Number of welds', '20');
      await _enter(tester, 'Time per weld (min)', '5');

      expect(find.text('1050 L'), findsOneWidget);
      expect(find.text('10000 L'), findsOneWidget);
      expect(find.text('1 pcs'), findsOneWidget);
      expect(find.textContaining('21.0'), findsNothing);
      expect(find.textContaining('szt.'), findsNothing,
          reason: 'EN: „pcs”, nie „szt.”');

      await _enter(tester, 'Residual reserve', '10');
      expect(find.text('9500 L'), findsOneWidget);
      expect(find.textContaining(_disclaimer), findsOneWidget);
    });
  });

  group('O₂ purge', () {
    testWidgets('cel 0 ppm i cel ≥ C₀: komunikat zamiast wyjątku',
        (tester) async {
      await _pump(tester);
      await _openTab(tester, 'O₂ Purge');

      await _enter(tester, 'OD (mm)', '60,3');
      await _enter(tester, 't (mm)', '2');
      await _enter(tester, 'Section length to purge (mm)', '1000');
      await _enter(tester, 'Gas flow Q (L/min)', '10');

      await _enter(tester, 'Target (ppm O₂)', '0');
      expect(tester.takeException(), isNull);
      expect(find.textContaining('Target must be > 0'), findsOneWidget);

      await _enter(tester, 'Target (ppm O₂)', '300000');
      expect(tester.takeException(), isNull);
      expect(find.textContaining('lower than the initial'), findsOneWidget);

      await _enter(tester, 'Target (ppm O₂)', '20');
      // 138,3 s — patrz shielding_gas_purge_test.dart
      expect(find.text('2m 18s'), findsOneWidget);
      expect(find.textContaining('O₂ analyser'), findsOneWidget);
      expect(find.textContaining(_disclaimer), findsOneWidget);
    });
  });

  group('Timer', () {
    testWidgets('temp. max z WPS jest przypomnieniem po czasie chłodzenia',
        (tester) async {
      await _pump(tester);
      await _openTab(tester, 'Timer');
      await tester.tap(find.text('Cooldown'));
      await tester.pumpAndSettle();

      await _enter(tester, 'Max. interpass temp. from WPS (°C)', '150');
      await _enter(tester, 'Cool time (min)', '0,05'); // 3 s
      await tester.tap(find.text('Start'));
      await tester.pump(const Duration(seconds: 4));

      expect(find.textContaining('≤ 150 °C'), findsOneWidget);
      await tester.tap(find.text('Reset'));
      await tester.pump();
    });
  });

  test('źródło bez mojibake (â‰, âš, â•)', () {
    final src = File('lib/screens/welder_tools_screen.dart').readAsStringSync();
    for (final bad in ['â‰', 'âš', 'â•']) {
      expect(src.contains(bad), isFalse, reason: 'znaleziono "$bad"');
    }
  });

  testWidgets('każda z 4 zakładek ma zdanie „wiąże WPS”', (tester) async {
    await _pump(tester);
    for (final tab in ['Gas', 'O₂ Purge', 'Timer', 'Pressure']) {
      await _openTab(tester, tab);
      expect(find.textContaining(_disclaimer), findsOneWidget, reason: tab);
    }
  });
}
