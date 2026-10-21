import 'package:flutter_test/flutter_test.dart';
import 'package:cut_list_app/assistant/assistant_ai_client.dart';
import 'package:cut_list_app/assistant/core/skill.dart';
import 'package:cut_list_app/assistant/core/tool_bridge.dart';
import 'package:cut_list_app/screens/welder_tools_screen.dart';
import 'package:cut_list_app/screens/iso_notebook_screen.dart';
import '../support/test_database.dart';
import 'ai_chat_execution_test.dart' show mount, FixtureSpeech;
import 'global_pipe_slope_flow_test.dart' show say, settle;
import 'welder_gas_execution_test.dart' show gasFields, purge;
import 'ai_iso_pending_reply_test.dart' show isoStart, drawPlan;
import 'package:flutter/material.dart' show Key, TextField;
import 'package:cut_list_app/assistant/core/assistant_panel_controller.dart';
import 'support/assistant_test_support.dart';

const naturalReserve =
    'Oblicz zużycie gazu spoiny 10 spawanie 2 min palnik 10 L/min zapas 15 bar';
const canonicalReserve =
    'Oblicz zużycie gazu spoiny 10 spawanie 2 min palnik 10 L/min rezerwa 15 bar';
void main() {
  useTestDatabase();
  testWidgets(
      'relational wording in an otherwise recognized command goes to AI rather than another literal question',
      (t) async {
    var calls = 0;
    await mount(t, interpret: (r) async {
      calls++;
      expect((r['context'] as Map)['pending_reply'], isNull);
      return const AiCommandPlan(
          'execute',
          [
            AiCommandStep('gas.consumption',
                'Oblicz zużycie gazu spoiny 10 spawanie 2 min palnik 10 L/min')
          ],
          '');
    });
    await say(t,
        'Oblicz zużycie gazu spoiny 10 spawanie 2 min palnik połowa 20 L/min');
    expect(calls, 1);
    expect(find.text('225 L'), findsOneWidget);
  });
  testWidgets(
      'contextual edit uses AI and the current manually changed form instead of stale chat values',
      (t) async {
    var calls = 0;
    await mount(t, interpret: (r) async {
      calls++;
      expect((r['context'] as Map)['inputs']['welds'], 20);
      expect((r['context'] as Map)['inputs']['weld_minutes'], 3);
      return const AiCommandPlan(
          'execute',
          [
            AiCommandStep('gas.consumption',
                'Oblicz zużycie gazu spoiny 20 spawanie 3 min palnik 12 L/min')
          ],
          '');
    });
    await say(
        t, 'Oblicz zużycie gazu spoiny 10 spawanie 2 min palnik 10 L/min');
    expect(calls, 0);
    AssistantPanelController.instance.setExpanded(false);
    await settle(t);
    for (final (label, value) in [
      ('Liczba spoin', '20'),
      ('Czas na spoinę (min)', '3')
    ]) {
      final field = find.byWidgetPredicate(
          (w) => w is TextField && w.decoration?.labelText == label);
      await t.enterText(field, value);
    }
    await settle(t);
    AssistantPanelController.instance.setExpanded(true);
    await settle(t);
    await say(t, 'a palnik 12 L/min');
    expect(calls, 1);
    expect(find.text('780 L'), findsOneWidget);
    expect(ToolBridge.instance.inputFields('welder_calculators')!['welds'], 20);
  });

  testWidgets(
      'contextual edit without AI cannot apply only the recognized half',
      (t) async {
    await mount(t,
        consent: false, interpret: (_) async => throw StateError('No consent'));
    await say(
        t, 'Oblicz zużycie gazu spoiny 10 spawanie 2 min palnik 10 L/min');
    final before = ToolBridge.instance.inputFields('welder_calculators');
    await say(t, 'a palnik 12 L/min zapas 15 bar');
    expect(ToolBridge.instance.inputFields('welder_calculators'), before);
    expect(find.text('225 L'), findsOneWidget);
  });

  test('unparsed native pending answer keeps its validated draft', () async {
    final h = BrainHarness();
    addTearDown(h.timer.dispose);
    await h.say('Oblicz zużycie gazu spoiny 10 spawanie 2 min');
    final pending = h.brain.pending;
    final r = await h.say('palnik 12 L/min zapas 15 bar');
    expect(r.result, isA<FailedResult>());
    expect(h.brain.pending, same(pending));
    expect(h.ctx.lastMatch, isNull);
  });

  testWidgets(
      'single-field AI reply cannot discard a second unparsed requested field',
      (t) async {
    var calls = 0;
    await mount(t, interpret: (_) async {
      calls++;
      return const AiCommandPlan(
          'reply', [AiCommandStep('gas.consumption', '12 L/min')], '');
    });
    await say(t, 'Oblicz zużycie gazu spoiny 10 spawanie 2 min');
    await say(t, 'palnik 12 L/min zapas 15 bar');
    expect(calls, 1);
    expect(find.byType(WelderToolsScreen), findsNothing);
    await say(t, 'palnik 12 L/min rezerwa 15 bar');
    expect(calls, 1);
    expect(
        ToolBridge.instance.inputFields('welder_calculators')!['reserve_bar'],
        15);
    expect(find.text('270 L'), findsOneWidget);
  });
  test(
      'recognized gas topic with an unparsed quantity must not bypass interpretation',
      () {
    final h = BrainHarness();
    addTearDown(h.timer.dispose);
    expect(
        h.brain.recognizesLocalRequest(
            Utterance(naturalReserve, lang: h.lang), h.ctx),
        isFalse);
    final reply = h.brain.skills
        .firstWhere((s) => s.id == 'gas.consumption')
        .match(Utterance(naturalReserve, lang: h.lang), h.ctx)!;
    expect(reply.requiresAiInterpretation, isTrue);
    expect(reply.copyWith(score: 1).requiresAiInterpretation, isTrue);
  });
  testWidgets(
      'without AI consent an unparsed quantity cannot be silently omitted from a calculation',
      (t) async {
    await mount(t,
        consent: false, interpret: (_) async => throw StateError('No consent'));
    await say(t, naturalReserve);
    expect(find.byType(WelderToolsScreen), findsNothing);
    expect(find.text('225 L'), findsNothing);
    expect(find.textContaining('Nie rozpoznałem wszystkich parametrów'),
        findsOneWidget);
  });

  testWidgets(
      'AI normalizes an unparsed reserve instead of asking again for the given torch flow',
      (t) async {
    var calls = 0;
    await mount(t, interpret: (r) async {
      calls++;
      expect((r['context'] as Map)['pending_reply'], isNull);
      return const AiCommandPlan(
          'execute', [AiCommandStep('gas.consumption', canonicalReserve)], '');
    });
    await say(t, naturalReserve);
    expect(calls, 1);
    expect(
        ToolBridge.instance.inputFields('welder_calculators')!['reserve_bar'],
        15);
    expect(find.text('225 L'), findsOneWidget);
    expect(find.text('9250 L'), findsOneWidget);
  });

  testWidgets(
      'AI handles a naturally phrased time which the local parser did not assign',
      (t) async {
    var calls = 0;
    await mount(t, interpret: (_) async {
      calls++;
      return const AiCommandPlan(
          'execute',
          [
            AiCommandStep('gas.consumption',
                'Oblicz zużycie gazu spoiny 10 spawanie 2 min palnik 10 L/min')
          ],
          '');
    });
    await say(t, 'Oblicz zużycie gazu 10 spoin po 2 min palnik 10 L/min');
    expect(calls, 1);
    expect(find.text('225 L'), findsOneWidget);
  });

  testWidgets(
      'an unavailable interpreter cannot replace existing gas fields with a partial calculation',
      (t) async {
    await mount(t,
        home: const WelderToolsScreen(),
        interpret: (_) async => throw const AssistantAiUnavailable(503));
    expect(await ToolBridge.instance.current!.apply(gasFields), isEmpty);
    await settle(t);
    await say(t, naturalReserve);
    expect(ToolBridge.instance.inputFields('welder_calculators'),
        {...gasFields, 'current_bar': null});
    expect(find.text('305 L'), findsOneWidget);
  });

  testWidgets(
      'model echoing an unparsed command is rejected before native execution',
      (t) async {
    await mount(t,
        interpret: (_) async => const AiCommandPlan(
            'execute', [AiCommandStep('gas.consumption', naturalReserve)], ''));
    await say(t, naturalReserve);
    expect(find.byType(WelderToolsScreen), findsNothing);
    expect(find.text('225 L'), findsNothing);
  });

  test('rejected canonical proposal preserves an existing question', () async {
    final h = BrainHarness();
    addTearDown(h.timer.dispose);
    await h.say('Oblicz czas formowania');
    final pending = h.brain.pending;
    final r = await h.brain.executeProposal(
        skillId: 'gas.consumption',
        command: Utterance(naturalReserve, lang: h.lang),
        original: Utterance(naturalReserve, lang: h.lang),
        context: h.ctx);
    expect(r.result, isA<FailedResult>());
    expect((r.result as FailedResult).reportMissingCapability, isFalse);
    expect(h.brain.pending, same(pending));
  });

  for (final oldQuestion in ['iso', 'gas']) {
    testWidgets(
        'new interpreted gas command supersedes $oldQuestion question and its old queue',
        (t) async {
      var calls = 0;
      await mount(t, interpret: (r) async {
        calls++;
        if (oldQuestion == 'iso' && calls == 1) return drawPlan;
        expect((r['context'] as Map)['pending_reply'], isNull);
        expect((r['capabilities'] as List).length, greaterThan(1));
        return const AiCommandPlan('execute',
            [AiCommandStep('gas.consumption', canonicalReserve)], '');
      });
      await say(t, oldQuestion == 'iso' ? isoStart : 'Oblicz zużycie gazu');
      await say(t, naturalReserve);
      expect(calls, oldQuestion == 'iso' ? 2 : 1);
      expect(IsoNotebookController.active, isNull);
      expect(
          ToolBridge.instance.inputFields('welder_calculators')!['reserve_bar'],
          15);
    });
  }

  for (final (rate, expected) in [
    ('600 litrów na godzinę', 10.0),
    ('10 litrów na minutę', 10.0),
    ('0,2 litra na sekundę', 12.0),
    ('10000 mililitrów na minutę', 10.0),
    ('600 L/h', 10.0),
    ('600 litres per hour', 10.0)
  ]) {
    test('spoken flow $rate is normalized without model interpretation',
        () async {
      final h = BrainHarness();
      addTearDown(h.timer.dispose);
      final r = await h
          .say('Oblicz zużycie gazu spoiny 10 spawanie 2 min palnik $rate');
      expect(r.result, isA<AnswerResult>());
      expect((r.result as AnswerResult).show!.fields['torch_lpm'],
          closeTo(expected, 1e-12));
      expect(r.match!.requiresAiInterpretation, isFalse);
      final p = await h.say(purge.replaceFirst('10 L/min', rate));
      expect((p.result as AnswerResult).show!.fields['flow_lpm'],
          closeTo(expected, 1e-12));
    });
  }

  test(
      'flow alternatives and a rate used as cylinder volume are rejected locally',
      () async {
    final h = BrainHarness();
    addTearDown(h.timer.dispose);
    var r = await h.say(
        'Oblicz zużycie gazu spoiny 10 spawanie 2 min palnik 10 litrów na minutę albo 12 litrów na minutę');
    expect((r.result as AskResult).slot, 'torch_lpm');
    r = await h.say(
        'Oblicz zużycie gazu spoiny 10 spawanie 2 min palnik 10 L/min butla 50 litrów na godzinę');
    expect((r.result as AskResult).slot, 'water_l');
  });

  testWidgets(
      'mock microphone transcription with spoken units stays offline and computes the native result',
      (t) async {
    final speech = FixtureSpeech();
    await mount(t,
        speech: speech,
        interpret: (_) async => throw StateError('Recognized flow is offline'));
    await t.tap(find.byKey(const Key('assistant-mic')));
    await t.pump();
    speech.emit(
        'Oblicz zużycie gazu spoiny dziesięć spawanie dwie minuty palnik sześćset litrów na godzinę');
    await settle(t);
    expect(find.text('225 L'), findsOneWidget);
    expect(ToolBridge.instance.inputFields('welder_calculators')!['torch_lpm'],
        10);
  });
}
