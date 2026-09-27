// Timer spawalniczy pod przyłbicą — ekran (zakładka Timer + pełnoekranowy
// komunikat końca).
//
// Na starej wersji:
//  • stan żył w zakładce — zmiana zakładki / wyjście z ekranu zerowały timer;
//  • koniec odliczania = tylko zmiana koloru (bez wibracji, dźwięku,
//    komunikatu, ekran gasł w trakcie).
//
// Serwis ma atrapę skutków ubocznych; czas to czas testu (`clock`).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:cut_list_app/i18n/app_language.dart';
import 'package:cut_list_app/screens/welder_tools_screen.dart';
import 'package:cut_list_app/services/weld_timer_service.dart';
import 'package:cut_list_app/widgets/weld_timer_alarm_overlay.dart';

import '../support/fake_weld_timer_effects.dart';

final _navKey = GlobalKey<NavigatorState>();

Widget _app(AppLanguage lang) => AppLanguageScope(
      controller: AppLanguageController(lang),
      child: MaterialApp(
        navigatorKey: _navKey,
        // Jak w app.dart: komunikat nad całym nawigatorem.
        builder: (context, child) => WeldTimerAlarmOverlay(child: child!),
        home: const Scaffold(body: Center(child: Text('home'))),
      ),
    );

Future<void> _openTimer(WidgetTester tester) async {
  _navKey.currentState!.push(MaterialPageRoute<void>(
    builder: (_) =>
        const WelderToolsScreen(initialTab: WelderToolsScreen.tabTimer),
  ));
  await tester.pumpAndSettle();
}

String _display(WidgetTester tester) => tester
    .widget<Text>(find.byKey(const ValueKey('weld-timer-display')))
    .data!;

final _anyButton =
    find.byWidgetPredicate((w) => w is ButtonStyleButton, description: 'button');

Finder _field(String label) => find.byWidgetPredicate(
      (w) => w is TextField && w.decoration?.labelText == label,
    );

void main() {
  late FakeEffects fx;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    fx = FakeEffects();
    WeldTimerService.instance =
        WeldTimerService(effects: fx, observeLifecycle: false);
  });
  tearDown(() => WeldTimerService.instance.dispose());

  Future<void> pumpApp(WidgetTester tester,
      {AppLanguage lang = AppLanguage.en}) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.5;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(_app(lang));
    await _openTimer(tester);
  }

  testWidgets('timer liczy dalej po zmianie zakładki', (tester) async {
    await pumpApp(tester);
    await tester.tap(find.text('Cooldown'));
    await tester.pump();
    await tester.enterText(_field('Cool time (min)'), '5');
    await tester.pump();
    await tester.tap(find.text('Start'));
    await tester.pump(const Duration(seconds: 20));

    await tester.tap(find.widgetWithText(Tab, 'Gas'));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 40));
    await tester.tap(find.widgetWithText(Tab, 'Timer'));
    await tester.pumpAndSettle();

    expect(WeldTimerService.instance.running, isTrue);
    // 5:00 − ~1:00 (+ animacje zakładek) — nie 5:00 od nowa.
    final shown = _display(tester);
    expect(shown.startsWith('03:5') || shown.startsWith('04:0'), isTrue,
        reason: 'pokazano $shown');
    expect(_field('Cool time (min)'), findsOneWidget);
    expect(tester.widget<TextField>(_field('Cool time (min)')).controller!.text,
        '5', reason: 'ustawienie przeżywa zakładkę');

    WeldTimerService.instance.reset();
  });

  testWidgets('timer liczy dalej po wyjściu z ekranu, koniec = pełny ekran '
      'na innym ekranie', (tester) async {
    await pumpApp(tester);
    await tester.tap(find.text('Purge'));
    await tester.pump();
    await tester.enterText(_field('Purge time (s)'), '30');
    await tester.pump();
    await tester.tap(find.text('Start'));
    await tester.pump(const Duration(seconds: 5));
    expect(fx.keepsScreenOn, isTrue, reason: 'ekran nie gaśnie w trakcie');

    // Wyjście z ekranu do „home”.
    _navKey.currentState!.pop();
    await tester.pumpAndSettle();
    expect(find.byType(WelderToolsScreen), findsNothing);
    expect(WeldTimerService.instance.running, isTrue);

    await tester.pump(const Duration(seconds: 30));
    expect(find.byKey(const ValueKey('weld-timer-alarm')), findsOneWidget);
    expect(find.text('PURGE TIME OVER'), findsOneWidget);
    expect(find.text('home'), findsOneWidget, reason: 'komunikat nad ekranem');
    expect(fx.alarms, hasLength(1), reason: 'wibracja + dźwięk');
    expect(fx.keepsScreenOn, isFalse);

    await tester.tap(find.text('OK'));
    await tester.pump();
    expect(find.byKey(const ValueKey('weld-timer-alarm')), findsNothing);
  });

  testWidgets('koniec chłodzenia: przypomnienie z WPS, „kolejny ścieg” '
      'startuje od nowa (PL)', (tester) async {
    await pumpApp(tester, lang: AppLanguage.pl);
    await tester.tap(find.text('Chłodzenie'));
    await tester.pump();
    await tester.enterText(
        _field('Maks. temp. międzyściegowa z WPS (°C)'), '175');
    await tester.enterText(_field('Czas chłodz. (min)'), '0,5');
    await tester.pump();
    await tester.tap(find.text('Start'));
    await tester.pump(const Duration(seconds: 31));

    final alarm = find.byKey(const ValueKey('weld-timer-alarm'));
    expect(alarm, findsOneWidget);
    expect(find.descendant(of: alarm, matching: find.text('KONIEC CHŁODZENIA')),
        findsOneWidget);
    expect(
        find.descendant(
            of: alarm, matching: find.textContaining('≤ 175 °C (WPS)')),
        findsOneWidget);
    expect(fx.alarms.single.maxInterpassC, 175);

    // Przyciski pod rękawice.
    for (final label in ['OK', 'Kolejny ścieg — chłodzenie od nowa']) {
      final button = find.ancestor(
          of: find.text(label), matching: _anyButton);
      expect(tester.getSize(button.first).height, greaterThanOrEqualTo(64),
          reason: label);
    }

    await tester.tap(find.text('Kolejny ścieg — chłodzenie od nowa'));
    await tester.pump();
    expect(alarm, findsNothing);
    expect(WeldTimerService.instance.running, isTrue);
    expect(_display(tester), '00:30');

    WeldTimerService.instance.reset();
    await tester.pump();
  });

  testWidgets('przyciski timera i trybów mają ≥ 64 dp', (tester) async {
    await pumpApp(tester);
    for (final label in ['Start', 'Reset']) {
      final button = find.ancestor(
          of: find.text(label), matching: _anyButton);
      expect(tester.getSize(button.first).height, greaterThanOrEqualTo(64),
          reason: label);
    }
    for (final label in ['Welding', 'Cooldown', 'Purge']) {
      final tap = find.ancestor(of: find.text(label), matching: find.byType(InkWell));
      expect(tester.getSize(tap.first).height, greaterThanOrEqualTo(64),
          reason: label);
    }
  });

  testWidgets('stoper spawania: bez alarmu i bez pytania o powiadomienia',
      (tester) async {
    await pumpApp(tester);
    await tester.tap(find.text('Start'));
    await tester.pump(const Duration(minutes: 3, seconds: 5));
    expect(_display(tester), '03:05');
    expect(fx.alarms, isEmpty);
    expect(fx.permissionRequests, 0);
    await tester.tap(find.text('Pause'));
    await tester.pump(const Duration(minutes: 1));
    expect(_display(tester), '03:05');
    expect(fx.keepsScreenOn, isFalse);
  });

  // Przegląd G4: dotknięcie „Purge” w trakcie chłodzenia kasowało odliczanie
  // bez pytania.
  testWidgets('zmiana trybu przy biegnącym odliczaniu pyta o potwierdzenie',
      (tester) async {
    await pumpApp(tester);
    await tester.tap(find.text('Cooldown'));
    await tester.pump();
    await tester.enterText(_field('Cool time (min)'), '8');
    await tester.pump();
    await tester.tap(find.text('Start'));
    await tester.pump(const Duration(seconds: 10));

    await tester.tap(find.text('Purge'));
    await tester.pumpAndSettle();
    expect(find.text('Stop the countdown?'), findsOneWidget);
    await tester.tap(find.text('No, keep it'));
    await tester.pumpAndSettle();
    expect(WeldTimerService.instance.mode, WeldTimerMode.cool);
    expect(WeldTimerService.instance.running, isTrue);

    await tester.tap(find.text('Purge'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Stop it'));
    await tester.pumpAndSettle();
    expect(WeldTimerService.instance.mode, WeldTimerMode.purge);
    expect(WeldTimerService.instance.running, isFalse);
  });

  testWidgets('bez odliczania zmiana trybu nie pyta', (tester) async {
    await pumpApp(tester);
    await tester.tap(find.text('Cooldown'));
    await tester.pumpAndSettle();
    expect(find.text('Stop the countdown?'), findsNothing);
    expect(WeldTimerService.instance.mode, WeldTimerMode.cool);
  });

  // O₂ Purge: 60,3 × 2, L = 1000 mm, Q = 10 L/min, cel 20 ppm → 138 s
  // („2m 18s”); przycisk startuje odliczanie w serwisie (alarm jak Timer).
  testWidgets('O₂ Purge: „Start timera purge” uruchamia serwis', (tester) async {
    await pumpApp(tester);
    await tester.tap(find.widgetWithText(Tab, 'O₂ Purge'));
    await tester.pumpAndSettle();
    await tester.enterText(_field('OD (mm)'), '60.3');
    await tester.enterText(_field('t (mm)'), '2');
    await tester.enterText(_field('Section length to purge (mm)'), '1000');
    await tester.enterText(_field('Gas flow Q (L/min)'), '10');
    await tester.pump();
    await tester.ensureVisible(find.text('Start purge timer (2m 18s)'));
    await tester.tap(find.text('Start purge timer (2m 18s)'));
    await tester.pump();
    final t = WeldTimerService.instance;
    expect(t.mode, WeldTimerMode.purge);
    expect(t.running, isTrue);
    expect(t.purgeSeconds, 139); // 138,3 s w górę
    t.reset();
    await tester.pump();
  });

  testWidgets('pierwszy start odliczania prosi o zgodę na powiadomienia',
      (tester) async {
    await pumpApp(tester);
    await tester.tap(find.text('Cooldown'));
    await tester.pump();
    await tester.tap(find.text('Start'));
    await tester.pump(const Duration(seconds: 1));
    expect(fx.permissionRequests, 1);
    WeldTimerService.instance.reset();
    await tester.pump();
  });
}
