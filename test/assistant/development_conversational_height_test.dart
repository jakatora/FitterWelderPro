import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cut_list_app/assistant/assistant_ai_client.dart';
import 'package:cut_list_app/assistant/core/skill.dart';
import 'package:cut_list_app/assistant/core/tool_bridge.dart';
import 'package:cut_list_app/assistant/skills/fitter_routes/development_height_skill.dart';
import 'package:cut_list_app/i18n/app_language.dart';
import '../support/test_database.dart';
import 'ai_chat_execution_test.dart' show mount, FixtureSpeech;
import 'global_pipe_slope_flow_test.dart' show say, settle;
import 'development_height_skill_test.dart' show Visible;
import 'cone_layout_skill_test.dart' as cone;
import 'eccentric_cone_skill_test.dart' as eccentric;
import 'transition_layout_skill_test.dart' as transition;

void main() {
  useTestDatabase();
  final skill = DevelopmentHeightSkill();
  final ctx =
      AssistantContext(lang: AppLanguage.pl, modules: Visible(cone.payload));
  Utterance u(String s) => Utterance(s, lang: AppLanguage.pl);
  for (final source in [
    'Zrob go wyzszego o 10 cm',
    'Make it taller by 10 cm'
  ]) {
    test('AI normalizes conversational amount: $source', () {
      expect(skill.match(u(source), ctx), isNull);
      expect(
          skill.acceptsProposal(u(source), u('Zwieksz wysokosc o 100 mm'), ctx),
          true);
      expect(
          skill.acceptsProposal(u(source), u('Zwieksz wysokosc o 200 mm'), ctx),
          false);
      expect(
          skill.acceptsProposal(
              u(source), u('Zmniejsz wysokosc o 100 mm'), ctx),
          false);
    });
  }
  test('vague amount can ask but never authorize a guessed value', () {
    for (final source in [
      'Zrob go troche wyzszego',
      'Make it a little taller'
    ]) {
      expect(
          skill.acceptsProposal(u(source), u('Zwieksz wysokosc'), ctx), true);
      expect(
          skill.acceptsProposal(u(source), u('Zwieksz wysokosc o 10 mm'), ctx),
          false);
      expect(
          skill.acceptsProposal(u(source), u('Zmniejsz wysokosc'), ctx), false);
    }
    for (final source in [
      'Nie zrob go wyzszego o 10 cm',
      'Jak zrobic go wyzszego o 10 cm',
      'Zrob go wyzszego o -10 cm',
      'Zrob go wyzszego o 10 cm i szerszego o 20 cm',
      'Przetlumacz make it taller by 10 cm'
    ]) {
      expect(
          skill.acceptsProposal(u(source), u('Zwieksz wysokosc o 100 mm'), ctx),
          false,
          reason: source);
    }
    for (final answer in [
      '100',
      '-100 mm',
      'minus 100 mm',
      '100 mm cm',
      '100 mm i 200 mm'
    ]) {
      expect(skill.fillSlot('amount', u(answer), ctx), isNull, reason: answer);
    }
    expect(
        skill.fillProposalSlot('amount', u('200 mm'), u('10 cm'), ctx), isNull);
    expect(skill.fillProposalSlot('amount', u('100 mm'), u('10 cm'), ctx),
        {'amount': 100.0});
  });
  for (final fixture in [
    (cone.command, cone.payload),
    (eccentric.command, eccentric.fields),
    (transition.command, transition.fields)
  ]) {
    testWidgets(
        'AI asks then changes actual ${fixture.$2['shape']} without guessing',
        (t) async {
      var calls = 0;
      await mount(t, interpret: (_) async {
        calls++;
        return const AiCommandPlan('execute',
            [AiCommandStep('development.height', 'Zwieksz wysokosc')], '');
      });
      await say(t, fixture.$1);
      await say(t, 'Zrob go troche wyzszego');
      expect(calls, 1);
      expect(ToolBridge.instance.inputFields('cone_layout'), fixture.$2);
      expect(find.textContaining('O ile zwiększyć wysokość?'), findsWidgets);
      await say(t, '10 cm');
      expect(calls, 1);
      expect(ToolBridge.instance.inputFields('cone_layout'),
          {...fixture.$2, 'height_mm': (fixture.$2['height_mm'] as num) + 100});
      expect(t.takeException(), isNull);
    });
  }
  testWidgets('manual change while answering prevents stale relative change',
      (t) async {
    await mount(t,
        interpret: (_) async => const AiCommandPlan('execute',
            [AiCommandStep('development.height', 'Zwieksz wysokosc')], ''));
    await say(t, cone.command);
    await say(t, 'Zrob go troche wyzszego');
    final b = ToolBridge.instance;
    final edited = {...cone.payload, 'large_dia_mm': 900.0};
    await b.current!.apply(edited);
    await settle(t);
    await say(t, '10 cm');
    expect(b.inputFields('cone_layout'), edited);
    expect(t.takeException(), isNull);
  });
  for (final wrong in [false, true]) {
    testWidgets(
        'spoken natural request uses AI but verifies dimensions: wrong=$wrong',
        (t) async {
      var calls = 0;
      final speech = FixtureSpeech();
      await mount(t, speech: speech, interpret: (_) async {
        calls++;
        return AiCommandPlan(
            'execute',
            [
              AiCommandStep(
                  'development.height',
                  wrong
                      ? 'Zmniejsz wysokosc o 200 mm'
                      : 'Zmniejsz wysokosc o 100 mm')
            ],
            '');
      });
      await say(t, cone.command);
      await t.tap(find.byKey(const Key('assistant-mic')));
      await settle(t);
      speech.emit('Zrob go nizszego o 10 cm');
      await settle(t);
      expect(calls, 1);
      expect(ToolBridge.instance.inputFields('cone_layout'),
          {...cone.payload, 'height_mm': wrong ? 500.0 : 400.0});
      expect(t.takeException(), isNull);
    });
  }
  testWidgets('missing-unit reply asks again; cancel never applies amount',
      (t) async {
    await mount(t, interpret: (_) async {
      return const AiCommandPlan('execute',
          [AiCommandStep('development.height', 'Zwieksz wysokosc')], '');
    });
    await say(t, cone.command);
    await say(t, 'Zrob go troche wyzszego');
    await say(t, '100');
    expect(ToolBridge.instance.inputFields('cone_layout'), cone.payload);
    await say(t, 'Anuluj');
    expect(ToolBridge.instance.inputFields('cone_layout'), cone.payload);
    expect(t.takeException(), isNull);
  });
}
