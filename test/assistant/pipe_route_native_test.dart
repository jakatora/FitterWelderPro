import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cut_list_app/app_navigator.dart';
import 'package:cut_list_app/assistant/core/skill.dart';
import 'package:cut_list_app/assistant/core/tool_bridge.dart';
import 'package:cut_list_app/screens/pipe_route_calculator_screen.dart';
import 'package:cut_list_app/i18n/app_language.dart';
import 'support/assistant_test_support.dart';
import 'pipe_route_skill_test.dart' show command;

Finder f(String label) => find.byWidgetPredicate(
    (w) => w is TextField && w.decoration?.labelText == label);
String text(WidgetTester t, String label) =>
    t.widget<TextField>(f(label)).controller!.text;
Future<void> mount(WidgetTester t,
    {Widget home = const Scaffold(body: Text('Start'))}) async {
  ToolBridge.reset();
  t.view.physicalSize = const Size(1000, 4000);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  addTearDown(() async {
    await t.pumpWidget(const SizedBox.shrink());
    await t.pumpAndSettle();
  });
  await t.pumpWidget(AppLanguageScope(
      controller: AppLanguageController(AppLanguage.pl),
      child: MaterialApp(
          navigatorKey: appNavigatorKey,
          navigatorObservers: [appRoutes],
          home: home)));
  await t.pumpAndSettle();
}

Future<ShowInModule> calc() async {
  final h = BrainHarness();
  addTearDown(h.timer.dispose);
  return ((await h.say(command)).result as AnswerResult).show!;
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  testWidgets(
      'actual route bridge applies, persists and rejects partial or mismatched updates atomically',
      (t) async {
    await mount(t);
    final show = await calc();
    final open = showInModule(show, explicit: true);
    await t.pumpAndSettle();
    expect(await open, ShowOutcome.opened);
    final handle = ToolBridge.instance.current!;
    expect(handle.toolId, 'pipe_route');
    expect(ToolBridge.instance.isReady(handle), true);
    expect(find.text('2680,0 mm'), findsOneWidget);
    expect(text(t, 'R – takeout kolanka 90° (C-F)'), '152');
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('pipe_route.x'), '1000.0');
    expect(prefs.getInt('pipe_route.dn'), 100);
    for (final patch in <Map<String, Object?>>[
      {'x_mm': 0},
      {'r_mm': 999},
      {'end_welds': 'no'},
      {'dn': 50},
      {'h1_mm': double.infinity},
      {'action': 'clear'}
    ]) {
      expect(await handle.apply({...show.fields, ...patch}), isNotEmpty);
      await t.pumpAndSettle();
      expect(text(t, 'X – bieg poziomy 1'), '1000.0');
      expect(prefs.getString('pipe_route.x'), '1000.0');
      expect(find.text('2680,0 mm'), findsOneWidget);
    }
    expect(await handle.apply({'x_mm': 2000}), isNotEmpty);
    expect(await handle.apply({...show.fields, 'end_welds': true}), isEmpty);
    await t.pumpAndSettle();
    expect(find.text('2674,0 mm'), findsOneWidget);
    expect(await handle.apply({'action': 'clear'}), isEmpty);
    await t.pumpAndSettle();
    expect(text(t, 'H1 – wys. startu'), '');
    expect(prefs.getString('pipe_route.x'), '');
    expect(prefs.getInt('pipe_route.dn'), isNull);
    expect(t.takeException(), isNull);
  });
  testWidgets(
      'SR and 3D reach the actual custom-R field with no false LR badge',
      (t) async {
    await mount(t);
    final b = BrainHarness();
    addTearDown(b.timer.dispose);
    final a = (await b.say(command.replaceFirst('DN100', 'DN100 SR'))).result
        as AnswerResult;
    final opening = showInModule(a.show!, explicit: true);
    await t.pumpAndSettle();
    expect(await opening, ShowOutcome.opened);
    expect(text(t, 'R – takeout kolanka 90° (C-F)'), '102');
    expect(find.text('2880,0 mm'), findsOneWidget);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getInt('pipe_route.dn'), isNull);
    final c = (await b.say(command.replaceFirst('DN100', 'DN100 3D'))).result
        as AnswerResult;
    expect(await ToolBridge.instance.current!.apply(c.show!.fields), isEmpty);
    await t.pumpAndSettle();
    expect(text(t, 'R – takeout kolanka 90° (C-F)'), '305');
    expect(find.text('2068,0 mm'), findsOneWidget);
  });
  testWidgets(
      'only an explicit zero takeout survives reopen; legacy zero remains unset',
      (t) async {
    SharedPreferences.setMockInitialValues({'pipe_route.r': '0'});
    await mount(t, home: const PipeRouteCalculatorScreen());
    expect(text(t, 'R – takeout kolanka 90° (C-F)'), '');
    final show = await calc();
    expect(
        await ToolBridge.instance.current!
            .apply({...show.fields, 'r_mm': 0.0, 'dn': null}),
        isEmpty);
    await t.pumpAndSettle();
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('pipe_route.explicit_zero_r'), true);
    appNavigatorKey.currentState!.pushReplacement(MaterialPageRoute<void>(
        builder: (_) => const PipeRouteCalculatorScreen()));
    await t.pumpAndSettle();
    expect(text(t, 'R – takeout kolanka 90° (C-F)'), '0.0');
    expect(ToolBridge.instance.inputFields('pipe_route')!['r_mm'], 0);
    await t.tap(find.text('OBLICZ'));
    await t.pumpAndSettle();
    expect(find.textContaining('R = 0 →'), findsOneWidget);
    expect(t.takeException(), isNull);
  });
  testWidgets(
      'readiness waits for stored values and manual edits before load win',
      (t) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('pipe_route.h1', '9000');
    await prefs.setString('pipe_route.r', '999');
    final gate = Completer<SharedPreferences>();
    await mount(t,
        home: PipeRouteCalculatorScreen(loadPreferences: () => gate.future));
    final handle = ToolBridge.instance.current!;
    expect(ToolBridge.instance.isReady(handle), false);
    expect(ToolBridge.instance.inputFields('pipe_route'), isNull);
    final show = await calc();
    expect(await handle.apply(show.fields), isNotEmpty);
    await t.enterText(f('H1 – wys. startu'), '-500');
    gate.complete(prefs);
    await t.pumpAndSettle();
    expect(text(t, 'H1 – wys. startu'), '-500');
    expect(ToolBridge.instance.isReady(handle), true);
    expect(prefs.getString('pipe_route.h1'), '-500');
    expect(await handle.apply(show.fields), isEmpty);
    await t.pumpAndSettle();
    expect(text(t, 'H1 – wys. startu'), '2000.0');
    expect(text(t, 'R – takeout kolanka 90° (C-F)'), '152');
  });
  for (final width in [320.0, 360.0, 432.0]) {
    for (final lang in AppLanguage.values) {
      testWidgets('native result fits $width ${lang.name} text1.3', (t) async {
        ToolBridge.reset();
        t.view.physicalSize = Size(width, 900);
        t.view.devicePixelRatio = 1;
        addTearDown(t.view.reset);
        addTearDown(() async {
          await t.pumpWidget(const SizedBox.shrink());
          await t.pumpAndSettle();
        });
        await t.pumpWidget(AppLanguageScope(
            controller: AppLanguageController(lang),
            child: MaterialApp(
                navigatorKey: appNavigatorKey,
                navigatorObservers: [appRoutes],
                builder: (ctx, child) => MediaQuery(
                    data: MediaQuery.of(ctx)
                        .copyWith(textScaler: const TextScaler.linear(1.3)),
                    child: child!),
                home: const PipeRouteCalculatorScreen())));
        await t.pumpAndSettle();
        final show = await calc();
        expect(await ToolBridge.instance.current!.apply(show.fields), isEmpty);
        await t.pumpAndSettle();
        expect(t.takeException(), isNull);
      });
    }
  }
  testWidgets(
      'queued saves use immutable full snapshots and latest update wins',
      (t) async {
    await mount(t, home: const PipeRouteCalculatorScreen());
    final show = await calc();
    final handle = ToolBridge.instance.current!;
    final first = handle.apply(show.fields);
    final second =
        handle.apply({...show.fields, 'x_mm': 2000.0, 'end_welds': true});
    expect(await first, isEmpty);
    expect(await second, isEmpty);
    await t.pumpAndSettle();
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('pipe_route.x'), '2000.0');
    expect(prefs.getBool('pipe_route.end_welds'), true);
    expect(find.text('3674,0 mm'), findsOneWidget);
    expect(t.takeException(), isNull);
  });
}
