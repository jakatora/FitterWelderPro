// Kalkulatory spawacza (6 zakładek) — poprawki z audytu 2026-09.
//
// Każdy test pada na starej wersji ekranu:
//  • Heat input: domyślne k=0,80 przy TIG; MMA k=1,00; brak ASME; werdykt
//    „za mała — brak wtopienia” dla 0,19 kJ/mm (orbitalny TIG cienkich rur).
//  • Temperatura: „Seferian” liczony innym wzorem (132 zamiast 129 °C dla
//    C 0,20 / Mn 1,50 / t 10); CEV 5,063 dużą liczbą dla stali 316L.
//  • Gaz: 1050 L / „50 L gazu” = 21 butli (prawda: ~0,1 butli 50 L/200 bar).
//  • Purge: cel 0 ppm → wyjątek w build().
//  • Timer: pole „Temp. max” niczego nie robiło.
// Liczby oczekiwane — patrz test/domain/welding/*.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cut_list_app/i18n/app_language.dart';
import 'package:cut_list_app/screens/welder_tools_screen.dart';

Widget _app() => AppLanguageScope(
      controller: AppLanguageController(AppLanguage.en),
      child: const MaterialApp(home: WelderToolsScreen()),
    );

Future<void> _pump(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1200, 3200);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(_app());
  await tester.pumpAndSettle();
}

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
  group('Heat input', () {
    testWidgets('k wynika z procesu: TIG 0,60, MMA 0,80 (nie 1,00)',
        (tester) async {
      await _pump(tester);

      expect(_text(tester, 'Thermal efficiency k'), '0.60',
          reason: 'zakładka startuje na TIG 141 → k = 0,6 (EN 1011-1)');

      await tester.tap(find.text('MMA 111'));
      await tester.pump();
      expect(_text(tester, 'Thermal efficiency k'), '0.80');

      await tester.tap(find.text('SAW 121'));
      await tester.pump();
      expect(_text(tester, 'Thermal efficiency k'), '1.00');
    });

    testWidgets('EN 0,480 vs ASME IX 0,800 kJ/mm dla 12 V/100 A/90 mm/min',
        (tester) async {
      await _pump(tester);

      await _enter(tester, 'Voltage U', '12');
      await _enter(tester, 'Current I', '100');
      await _enter(tester, 'Welding speed v', '90');
      expect(find.text('0.480 kJ/mm'), findsOneWidget);

      await tester.tap(find.text('ASME IX'));
      await tester.pump();
      expect(find.text('0.800 kJ/mm'), findsOneWidget);
      expect(find.text('0.480 kJ/mm'), findsNothing);
    });

    testWidgets('0,16 kJ/mm (orbitalny TIG) nie jest oznaczane jako błąd',
        (tester) async {
      await _pump(tester);

      await _enter(tester, 'Voltage U', '10');
      await _enter(tester, 'Current I', '80');
      await _enter(tester, 'Welding speed v', '180');
      // 10·80·60/180 = 266,67 J/mm · 0,6 = 160 J/mm = 0,160 kJ/mm
      expect(find.text('0.160 kJ/mm'), findsOneWidget);
      expect(find.textContaining('lack of fusion'), findsNothing);
      expect(find.textContaining(_disclaimer), findsOneWidget);
    });
  });

  group('Temperatura podgrzewania', () {
    testWidgets('Seferian: C 0,20 / Mn 1,50 → 129 / 145 / 167 °C',
        (tester) async {
      await _pump(tester);
      await _openTab(tester, 'Preheat');
      await tester.tap(find.text('CS (example)'));
      await tester.pump();

      for (final (t, tp) in [('10', '129 °C'), ('30', '145 °C'), ('60', '167 °C')]) {
        await _enter(tester, 'Wall thickness t (mm)', t);
        expect(find.text(tp), findsOneWidget, reason: 't = $t mm');
      }
      expect(find.text('0.450'), findsOneWidget, reason: 'CEV IIW');
      expect(find.textContaining('13916'), findsNothing,
          reason: 'EN ISO 13916 to pomiar temperatury, nie metoda obliczeń');
      expect(find.textContaining('EN 1011-2'), findsWidgets);
      expect(find.textContaining(_disclaimer), findsOneWidget);
    });

    testWidgets('stal 316L: zamiast „CEV 5,063” komunikat', (tester) async {
      await _pump(tester);
      await _openTab(tester, 'Preheat');
      await _enter(tester, 'Wall thickness t (mm)', '3');
      await tester.tap(find.text('SS 316L'));
      await tester.pump();

      expect(find.text('5.063'), findsNothing);
      expect(find.textContaining('do not apply to stainless'), findsOneWidget);
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

      await _enter(tester, 'OD (mm)', '60.3');
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
      await _enter(tester, 'Cool time (min)', '0.05'); // 3 s
      await tester.tap(find.text('Start'));
      await tester.pump(const Duration(seconds: 4));

      expect(find.textContaining('≤ 150 °C'), findsOneWidget);
      await tester.tap(find.text('Pause'));
      await tester.pump();
    });
  });

  test('źródło bez mojibake (â‰, âš, â•)', () {
    final src = File('lib/screens/welder_tools_screen.dart').readAsStringSync();
    for (final bad in ['â‰', 'âš', 'â•']) {
      expect(src.contains(bad), isFalse, reason: 'znaleziono "$bad"');
    }
  });

  testWidgets('każda z 6 zakładek ma zdanie „wiąże WPS”', (tester) async {
    await _pump(tester);
    for (final tab in ['Heat Input', 'Preheat', 'O₂ Purge', 'Gas', 'Timer', 'Pressure']) {
      await _openTab(tester, tab);
      expect(find.textContaining(_disclaimer), findsOneWidget, reason: tab);
    }
  });
}
