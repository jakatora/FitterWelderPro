import 'dart:async';
import 'package:flutter/material.dart' show Key, TextField;
import 'package:flutter_test/flutter_test.dart';
import 'package:cut_list_app/assistant/assistant_ai_client.dart';
import 'package:cut_list_app/assistant/core/skill.dart';
import 'package:cut_list_app/assistant/core/tool_bridge.dart';
import 'package:cut_list_app/screens/welder_tools_screen.dart';
import 'package:cut_list_app/services/weld_timer_service.dart';
import '../support/test_database.dart';
import 'ai_chat_execution_test.dart' show mount, FixtureSpeech;
import 'global_pipe_slope_flow_test.dart' show say, settle;
import 'support/assistant_test_support.dart';

const screen = WelderToolsScreen(initialTab: WelderToolsScreen.tabTimer);
const relative = 'Ustaw timer chłodzenia na połowę obecnego czasu';
const setHalf = AiCommandPlan('execute',
    [AiCommandStep('timer.set', 'Ustaw timer chłodzenia 2 minuty')], '');
Finder coolField() => find.byWidgetPredicate(
    (w) => w is TextField && w.decoration?.labelText == 'Czas chłodz. (min)');
BrainHarness timerFixture() {
  final h = BrainHarness();
  h.timer.setMode(WeldTimerMode.cool);
  h.timer.setCoolTime(const Duration(minutes: 4));
  h.timer.setMaxInterpass(175);
  WeldTimerService.instance = h.timer;
  addTearDown(h.timer.dispose);
  return h;
}

Map<String, Object?> inputs() =>
    ToolBridge.instance.inputFields('welder_calculators')!;
Future<void> submit(WidgetTester t, String text) async {
  await t.enterText(find.byKey(const Key('assistant-command')), text);
  await t.tap(find.byKey(const Key('assistant-go')));
  await t.pump(const Duration(milliseconds: 200));
}

void main() {
  useTestDatabase();
  test('literal English keep rejects replacement without interpretation',
      () async {
    final h = BrainHarness();
    addTearDown(h.timer.dispose);
    await h.say('Uruchom chłodzenie 4 minuty');
    h.wait(const Duration(seconds: 10));
    expect((await h.say('Ustaw timer chłodzenia 2 minuty')).result,
        isA<AskResult>());
    final r = (await h.say('keep')).result as AnswerResult;
    expect(r.actionCompleted, isFalse);
    expect(h.timer.target!.inSeconds, 240);
    expect(h.timer.running, isTrue);
  });
  testWidgets(
      'generic start preserves precise native duration and WPS despite rounded fields',
      (t) async {
    final h = timerFixture();
    h.timer.setCoolTime(const Duration(milliseconds: 200001));
    h.timer.setMaxInterpass(175.125);
    await mount(t,
        home: screen, interpret: (_) async => throw StateError('Native start'));
    expect(inputs()['cool_minutes'], 3.33);
    expect(inputs()['max_c'], 175.13);
    expect(inputs()['configured_max_c'], 175.125);
    await say(t, 'Uruchom timer');
    expect(h.timer.target!.inMilliseconds, 200001);
    expect(h.timer.maxInterpassC, 175.125);
    expect(h.timer.running, isTrue);
  });
  testWidgets(
      'background welding narrative cannot change the timer mode inferred from its form',
      (t) async {
    final h = timerFixture();
    await mount(t,
        home: screen,
        interpret: (_) async => const AiCommandPlan(
            'execute', [AiCommandStep('timer.start', 'Uruchom timer')], ''));
    await say(t, 'Spawanie skończone, potem uruchom timer');
    expect(h.timer.mode, WeldTimerMode.cool);
    expect(h.timer.target!.inSeconds, 240);
    expect(h.timer.running, isTrue);
  });
  testWidgets(
      'unparsed relative modifier goes to AI instead of discarding its meaning',
      (t) async {
    final h = timerFixture();
    var calls = 0;
    await mount(t, home: screen, interpret: (_) async {
      calls++;
      return const AiCommandPlan(
          'execute',
          [
            AiCommandStep(
                'timer.set', 'Ustaw timer chłodzenia 4 minuty 20 sekund')
          ],
          '');
    });
    await say(t, 'Zmień timer chłodzenia o 20 sekund dłużej');
    expect(calls, 1);
    expect(h.timer.target!.inSeconds, 260);
    expect(h.timer.running, isFalse);
  });
  test('reset naming a different mode cannot reset the active countdown',
      () async {
    final h = BrainHarness();
    addTearDown(h.timer.dispose);
    await h.say('Uruchom chłodzenie 2 minuty');
    h.wait(const Duration(seconds: 10));
    expect(
        (await h.say('Wyzeruj stoper spawania')).result, isA<FailedResult>());
    expect(h.timer.running, isTrue);
    expect(h.timer.elapsed.inSeconds, 10);
  });
  for (final proposal in [
    (
      'timer.cool',
      'Uruchom timer formowania na połowę 10 minut',
      'Uruchom chłodzenie 5 minut'
    ),
    ('timer.cool', 'Wznów timer', 'Uruchom chłodzenie 4 minuty'),
    ('timer.stop', 'Zatrzymaj timer', 'Wyzeruj timer'),
    ('timer.stop', 'Wyzeruj timer', 'Zatrzymaj timer'),
  ]) {
    test('AI preserves explicit mode and control kind: ${proposal.$2}',
        () async {
      final h = BrainHarness();
      addTearDown(h.timer.dispose);
      await h.say('Uruchom chłodzenie 4 minuty');
      h.wait(const Duration(seconds: 10));
      final revision = h.timer.controlRevision;
      final r = await h.brain.executeProposal(
          skillId: proposal.$1,
          command: Utterance(proposal.$3, lang: h.lang),
          original: Utterance(proposal.$2, lang: h.lang),
          context: h.ctx);
      expect(r.result, isA<FailedResult>());
      expect(h.timer.controlRevision, revision);
      expect(h.timer.target!.inSeconds, 240);
      expect(h.timer.elapsed.inSeconds, 10);
      expect(h.timer.running, isTrue);
    });
  }
  test('a delayed-stop request cannot become an immediate pause', () async {
    final h = BrainHarness();
    addTearDown(h.timer.dispose);
    await h.say('Uruchom chłodzenie 2 minuty');
    expect((await h.say('Zatrzymaj timer za 10 sekund')).result,
        isNot(isA<AnswerResult>()));
    expect(h.timer.running, isTrue);
    final r = await h.brain.executeProposal(
        skillId: 'timer.stop',
        command: Utterance('Zatrzymaj timer', lang: h.lang),
        original: Utterance('Zatrzymaj timer za 10 sekund', lang: h.lang),
        context: h.ctx);
    expect(r.result, isA<FailedResult>());
    expect(h.timer.running, isTrue);
  });
  test('an explicit different timer mode cannot pause the active countdown',
      () async {
    final h = BrainHarness();
    addTearDown(h.timer.dispose);
    await h.say('Uruchom timer formowania 90 sekund');
    expect(
        (await h.say('Zatrzymaj stoper spawania')).result, isA<FailedResult>());
    expect(h.timer.running, isTrue);
    await h.say('Zatrzymaj timer');
    expect(h.timer.running, isFalse);
  });
  testWidgets('declining timer replacement drops the queued start', (t) async {
    final h = timerFixture();
    h.timer.start();
    h.wait(const Duration(seconds: 10));
    await mount(t,
        home: screen,
        interpret: (_) async => const AiCommandPlan(
            'execute',
            [
              AiCommandStep('timer.set', 'Ustaw timer chłodzenia 1 minuta'),
              AiCommandStep('timer.start', 'Uruchom timer')
            ],
            ''));
    await say(t, 'Ustaw timer chłodzenia 1 minuta, potem uruchom timer');
    await say(t, 'zostaw');
    expect(h.timer.target!.inSeconds, 240);
    expect(h.timer.elapsed.inSeconds, 10);
    expect(h.timer.running, isTrue);
    expect(find.textContaining('Obecny timer ma postęp'), findsNothing);
    expect(find.textContaining('Zostawiam obecny timer'), findsOneWidget);
  });
  testWidgets(
      'snapshot exposes only controls belonging to the selected timer mode',
      (t) async {
    final h = timerFixture();
    await mount(t,
        home: screen, interpret: (_) async => throw StateError('Native mode'));
    expect(inputs(), containsPair('cool_minutes', 4));
    expect(inputs(), isNot(contains('purge_seconds')));
    await t.tap(find.text('Purge').hitTestable());
    await settle(t);
    expect(inputs(), containsPair('mode', 'purge'));
    expect(inputs(), containsPair('purge_seconds', 90));
    expect(inputs(), isNot(contains('cool_minutes')));
    expect(inputs(), isNot(contains('max_c')));
    await say(t, 'Uruchom timer');
    expect(h.timer.mode, WeldTimerMode.purge);
    expect(h.timer.target!.inSeconds, 90);
    expect(h.timer.running, isTrue);
  });
  for (final command in [
    'Ustaw timer chłodzenia 2 minuty',
    'Set purge timer 90 seconds',
    'Ustaw stoper spawania'
  ]) {
    test('configuration does not start counting: $command', () async {
      final h = BrainHarness();
      addTearDown(h.timer.dispose);
      final r = await h.say(command);
      expect(r.match!.skill.id, 'timer.set');
      expect(r.result, isA<AnswerResult>());
      expect(h.timer.running, isFalse);
      expect(h.timer.elapsed, Duration.zero);
    });
  }
  test(
      'configuration replacing progress requires confirmation and stays stopped',
      () async {
    final h = BrainHarness();
    addTearDown(h.timer.dispose);
    await h.say('Uruchom chłodzenie 4 minuty limit 175 C');
    h.wait(const Duration(seconds: 10));
    final r = await h.say('Ustaw timer chłodzenia 2 minuty');
    expect((r.result as AskResult).slot, 'replace');
    expect(h.timer.target!.inSeconds, 240);
    await h.say('tak zastąp timer');
    expect(h.timer.target!.inSeconds, 120);
    expect(h.timer.maxInterpassC, 175);
    expect(h.timer.running, isFalse);
  });
  test(
      'model cannot turn explicit configuration into starting or erase its pending question',
      () async {
    final h = BrainHarness();
    addTearDown(h.timer.dispose);
    await h.say('Uruchom chłodzenie');
    final pending = h.brain.pending;
    final r = await h.brain.executeProposal(
        skillId: 'timer.cool',
        command: Utterance('Uruchom chłodzenie 2 minuty', lang: h.lang),
        original: Utterance(relative, lang: h.lang),
        context: h.ctx);
    expect(r.result, isA<FailedResult>());
    expect(h.brain.pending, same(pending));
    expect(h.timer.running, isFalse);
  });
  testWidgets('generic start uses visible duration and optional WPS limit',
      (t) async {
    final h = timerFixture();
    await mount(t,
        home: screen,
        interpret: (_) async => throw StateError('Literal native start'));
    await t.enterText(coolField(), '3.5');
    await settle(t);
    await say(t, 'Uruchom timer');
    expect(h.timer.target!.inSeconds, 210);
    expect(h.timer.maxInterpassC, 175);
    expect(h.timer.running, isTrue);
    expect(inputs()['cool_minutes'], 3.5);
  });
  testWidgets('relative AI configuration sees manual input and never starts',
      (t) async {
    final h = timerFixture();
    var calls = 0;
    await mount(t, home: screen, interpret: (r) async {
      calls++;
      expect((r['context'] as Map)['inputs'], containsPair('cool_minutes', 6));
      expect((r['context'] as Map)['inputs'], containsPair('max_c', 175));
      return const AiCommandPlan('execute',
          [AiCommandStep('timer.set', 'Ustaw timer chłodzenia 3 minuty')], '');
    });
    await t.enterText(coolField(), '6');
    await settle(t);
    await say(t, relative);
    expect(calls, 1);
    expect(h.timer.target!.inSeconds, 180);
    expect(h.timer.maxInterpassC, 175);
    expect(h.timer.running, isFalse);
    expect(inputs()['cool_minutes'], 3);
  });
  testWidgets('wrong model action cannot start a configuration request',
      (t) async {
    final h = timerFixture();
    await mount(t,
        home: screen,
        interpret: (_) async => const AiCommandPlan('execute',
            [AiCommandStep('timer.cool', 'Uruchom chłodzenie 2 minuty')], ''));
    await say(t, relative);
    expect(h.timer.running, isFalse);
    expect(h.timer.target!.inSeconds, 240);
    expect(find.textContaining('zmienia rodzaj polecenia'), findsOneWidget);
  });
  testWidgets('manual input change invalidates delayed AI configuration',
      (t) async {
    final h = timerFixture();
    final pending = Completer<AiCommandPlan>();
    await mount(t, home: screen, interpret: (_) => pending.future);
    await submit(t, relative);
    await t.enterText(coolField(), '5');
    pending.complete(setHalf);
    await settle(t);
    expect(h.timer.target!.inSeconds, 300);
    expect(h.timer.running, isFalse);
    expect(find.textContaining('dane zmieniły się'), findsOneWidget);
  });
  testWidgets(
      'normal ticks keep AI snapshot stable and replacement stays explicit',
      (t) async {
    final h = timerFixture();
    h.timer.start();
    final pending = Completer<AiCommandPlan>();
    await mount(t, home: screen, interpret: (_) => pending.future);
    final before = inputs();
    await submit(t, relative);
    h.wait(const Duration(seconds: 10));
    h.timer.tick();
    expect(inputs(), before);
    expect(inputs(), isNot(contains('elapsed_seconds')));
    pending.complete(setHalf);
    await settle(t);
    expect(h.timer.target!.inSeconds, 240);
    expect(h.timer.running, isTrue);
    await say(t, 'tak zastąp timer');
    expect(h.timer.target!.inSeconds, 120);
    expect(h.timer.running, isFalse);
  });
  testWidgets(
      'editing a blank field invalidates confirmation even without service revision change',
      (t) async {
    final h = timerFixture();
    h.timer.start();
    await mount(t, home: screen, interpret: (_) async => setHalf);
    await say(t, relative);
    final revision = h.timer.controlRevision;
    await t.enterText(coolField(), '');
    await settle(t);
    expect(h.timer.controlRevision, revision);
    await say(t, 'tak zastąp timer');
    expect(h.timer.target!.inSeconds, 240);
    expect(h.timer.running, isTrue);
    expect(
        find.textContaining('Ustawienia timera zmieniły się'), findsOneWidget);
  });
  testWidgets('setting then starting executes both ordered native actions',
      (t) async {
    final h = timerFixture();
    var calls = 0;
    await mount(t, home: screen, interpret: (_) async {
      calls++;
      return const AiCommandPlan(
          'execute',
          [
            AiCommandStep('timer.set', 'Ustaw timer chłodzenia 1 minuta'),
            AiCommandStep('timer.start', 'Uruchom timer')
          ],
          '');
    });
    await say(t, 'Ustaw timer chłodzenia 1 minuta, potem uruchom timer');
    expect(calls, 1);
    expect(h.timer.target!.inSeconds, 60);
    expect(h.timer.running, isTrue);
  });
  testWidgets(
      'no consent cannot execute a partial relative or compound command',
      (t) async {
    final h = timerFixture();
    await mount(t,
        home: screen,
        consent: false,
        interpret: (_) async => throw StateError('No consent'));
    await say(t, 'Uruchom timer chłodzenia na połowę 10 minut');
    expect(h.timer.target!.inSeconds, 240);
    expect(h.timer.running, isFalse);
    await say(t, 'Ustaw timer chłodzenia 1 minuta, potem uruchom timer');
    expect(h.timer.target!.inSeconds, 240);
    expect(h.timer.running, isFalse);
  });
  testWidgets(
      'invalid visible duration is not replaced by the clamped service value',
      (t) async {
    final h = timerFixture();
    await mount(t,
        home: screen, interpret: (_) async => throw StateError('Native start'));
    await t.enterText(coolField(), '999');
    await settle(t);
    expect(h.timer.target!.inSeconds, 36000);
    await say(t, 'Uruchom timer');
    expect(h.timer.running, isFalse);
    expect(find.textContaining('Podaj czas z jednostką'), findsOneWidget);
  });
  testWidgets('mock speech performs interpreted configuration on native timer',
      (t) async {
    final h = timerFixture();
    final speech = FixtureSpeech();
    var calls = 0;
    await mount(t, home: screen, speech: speech, interpret: (_) async {
      calls++;
      return setHalf;
    });
    await t.tap(find.byKey(const Key('assistant-mic')));
    await t.pump();
    speech.emit(relative);
    await settle(t);
    expect(calls, 1);
    expect(h.timer.target!.inSeconds, 120);
    expect(h.timer.running, isFalse);
  });
}
