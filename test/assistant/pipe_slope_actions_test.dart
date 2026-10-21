import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cut_list_app/app_navigator.dart';
import 'package:cut_list_app/assistant/core/skill.dart';
import 'package:cut_list_app/assistant/core/tool_bridge.dart';
import 'package:cut_list_app/i18n/app_language.dart';
import 'support/assistant_test_support.dart';
import 'pipe_slope_current_test.dart' show mount, field;

void main() {
  final copied = <String>[];
  var fail = false;
  setUp(() {
    copied.clear();
    fail = false;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        if (fail) throw PlatformException(code: 'secret-backend-details');
        copied.add((call.arguments as Map)['text'] as String);
      }
      return null;
    });
  });
  tearDown(() => TestDefaultBinaryMessengerBinding
      .instance.defaultBinaryMessenger
      .setMockMethodCallHandler(SystemChannels.platform, null));
  for (final (mode, label, expected) in [
    ('length_to_rise', 'Wznios (Rise)', '60.0'),
    ('rise_to_length', 'Długość rury', '6000.0'),
    ('slope_from_lr', 'Nachylenie', '1.000')
  ]) {
    testWidgets(
        'copy actual primary/angle/mm-per-metre for $mode only after native success',
        (t) async {
      await mount(t);
      final bridge = ToolBridge.instance;
      expect(
          await bridge.current!.apply(
              {'mode': mode, 'length_mm': 6000, 'rise_mm': 60, 'slope_pct': 1}),
          isEmpty);
      await t.pumpAndSettle();
      final before = Map.of(bridge.inputFields('pipe_slope')!);
      final h = BrainHarness();
      addTearDown(h.timer.dispose);
      final ctx = AssistantContext(lang: AppLanguage.pl, modules: bridge);
      Future<SkillResult> say(String s) async => (await h.brain
              .handle(Utterance(s, lang: AppLanguage.pl, byVoice: true), ctx))
          .result;
      final r = await say('skopiuj wynik') as AnswerResult;
      expect(r.answer.text.pl, contains('Skopiowano'));
      expect(copied, [expected]);
      expect(await say('copy slope result to clipboard'), isA<AnswerResult>());
      expect(copied.last, expected);
      expect(t.widget<TextField>(field(label)).controller!.text, expected);
      final angle =
          t.widget<TextField>(field('Kąt nachylenia')).controller!.text;
      expect(await say('skopiuj kąt nachylenia'), isA<AnswerResult>());
      expect(copied.last, angle);
      expect(await say('skopiuj mm na metr'), isA<AnswerResult>());
      expect(copied.last, '10.0');
      expect(bridge.inputFields('pipe_slope'), before);
      final n = copied.length;
      for (final command in [
        'skopiuj wyniki',
        'copy all results',
        'skopiuj wszystkie wyniki'
      ]) {
        expect(await say(command), isA<AskResult>());
        expect(copied.length, n);
      }
      expect(await say('skopiuj wznios i kąt'), isA<AskResult>());
      expect(copied.length, n);
      expect(await say('kąt'), isA<AnswerResult>());
      expect(copied.length, n + 1);
      await say('qwerty asdf');
      expect(copied.length, n + 1);
      await say('skopiuj profil');
      expect(copied.length, n + 1);
      // A later genuine calculation must clear action metadata and never copy.
      final calc = await say('spadek 2% na 6 metrów') as AnswerResult;
      expect(calc.show!.fields['rise_mm'], 120);
      expect(copied.length, n + 1);
      expect(t.takeException(), isNull);
    });
  }
  testWidgets('explicit edits interrupt copy clarification without copying',
      (t) async {
    await mount(t);
    final b = ToolBridge.instance;
    await b.current!
        .apply({'mode': 'length_to_rise', 'length_mm': 6000, 'slope_pct': 1});
    await t.pumpAndSettle();
    final h = BrainHarness();
    addTearDown(h.timer.dispose);
    final ctx = AssistantContext(lang: AppLanguage.pl, modules: b);
    Future<SkillResult> say(String s) async =>
        (await h.brain.handle(Utterance(s, lang: AppLanguage.pl), ctx)).result;
    expect(await say('skopiuj wznios i kąt'), isA<AskResult>());
    final calc = await say('zmień długość na 12 metrów') as AnswerResult;
    expect(calc.show!.fields['rise_mm'], 120);
    expect(copied, isEmpty);
    expect(await say('skopiuj wznios i kąt'), isA<AskResult>());
    final fresh = await say('oblicz spadek 2% na 6 metrów') as AnswerResult;
    expect(fresh.show!.fields['rise_mm'], 120);
    expect(copied, isEmpty);
  });
  testWidgets(
      'empty/stale/input-only result and platform failure never claim success',
      (t) async {
    await mount(t);
    final b = ToolBridge.instance;
    expect(
        (await b.performModuleAction('pipe_slope', 'copy')).completed, false);
    expect(copied, isEmpty);
    await b.current!
        .apply({'mode': 'length_to_rise', 'length_mm': 6000, 'slope_pct': 1});
    await t.pumpAndSettle();
    final input =
        await b.performModuleAction('pipe_slope', 'copy', field: 'length_mm');
    expect(input.completed, false);
    expect(copied, isEmpty);
    fail = true;
    final err = await b.performModuleAction('pipe_slope', 'copy');
    expect(err.completed, false);
    expect(err.message.pl, isNot(contains('secret')));
    expect(copied, isEmpty);
    fail = false;
    await t.enterText(field('Długość rury'), '12000');
    await t.pumpAndSettle();
    final stale = await b.performModuleAction('pipe_slope', 'copy');
    expect(stale.completed, false);
    expect(stale.message.pl, contains('Brak aktualnego'));
    expect(copied, isEmpty);
    expect((await b.performModuleAction('pipe_slope', 'unknown')).completed,
        false);
  });
  testWidgets(
      'ready/current module and popup guards block hidden, wrong-target and unloaded actions',
      (t) async {
    await mount(t);
    final b = ToolBridge.instance;
    final handle = b.current!;
    await handle
        .apply({'mode': 'length_to_rise', 'length_mm': 6000, 'slope_pct': 1});
    await t.pumpAndSettle();
    final route = appRoutes.top;
    b.attach(handle, route: route, ready: false);
    expect(
        (await b.performModuleAction('pipe_slope', 'copy')).completed, false);
    expect(copied, isEmpty);
    b.markReady(handle);
    expect((await b.performModuleAction('account', 'copy')).completed, false);
    final nav = appNavigatorKey.currentState!;
    nav.push(MaterialPageRoute<void>(
        builder: (_) => const Scaffold(body: Text('Other'))));
    await t.pumpAndSettle();
    expect(
        (await b.performModuleAction('pipe_slope', 'copy')).completed, false);
    expect(copied, isEmpty);
    nav.pop();
    await t.pumpAndSettle();
    final opened = await b.performModuleAction('pipe_slope', 'formula');
    await t.pumpAndSettle();
    expect(opened.completed, true);
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.text('Źródło wzorów'), findsOneWidget);
    expect(
        (await b.performModuleAction('pipe_slope', 'copy')).completed, false);
    expect(copied, isEmpty);
    nav.pop();
    await t.pumpAndSettle();
    expect((await b.performModuleAction('pipe_slope', 'copy')).completed, true);
    expect(copied, ['60.0']);
  });
  testWidgets(
      'qualified formula opens actual module and dialog through ShowInModule',
      (t) async {
    await mount(t);
    final nav = appNavigatorKey.currentState!;
    nav.push(MaterialPageRoute<void>(
        builder: (_) => const Scaffold(body: Text('Start'))));
    await t.pumpAndSettle();
    final h = BrainHarness();
    addTearDown(h.timer.dispose);
    final r = (await h.say('pokaż wzory spadku rury')).result as AnswerResult;
    expect(r.show!.fields, {'action': 'formula'});
    final future = showInModule(r.show!, explicit: true);
    await t.pumpAndSettle();
    expect(await future, ShowOutcome.opened);
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(
        find.descendant(
            of: find.byType(AlertDialog),
            matching: find.textContaining('Rise = Długość')),
        findsOneWidget);
  });
  test(
      'copy without action port fails safely; contextual formula belongs only to active slope',
      () async {
    final h = BrainHarness(activeToolId: 'pipe_slope', onHome: false);
    addTearDown(h.timer.dispose);
    final r = (await h.say('skopiuj wynik')).result as FailedResult;
    expect(r.reportMissingCapability, false);
    final other = BrainHarness(activeToolId: 'rolling_offset', onHome: false);
    addTearDown(other.timer.dispose);
    expect((await other.say('show formulas')).match?.skill.id,
        isNot('pipe.slope'));
    expect(
        (await h.say('show formulas for thermal expansion'))
            .match
            ?.slots['module_action'],
        isNot('formula'));
  });
}
