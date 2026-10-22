import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cut_list_app/assistant/assistant_ai_client.dart';
import 'package:cut_list_app/assistant/core/skill.dart';
import 'package:cut_list_app/assistant/core/tool_bridge.dart';
import 'package:cut_list_app/assistant/skills/fitter_routes/development_summary_skill.dart';
import 'package:cut_list_app/assistant/assistant_validator.dart'
    show assistantNumber;
import 'package:cut_list_app/domain/fitter/cone_assistant_input.dart';
import 'package:cut_list_app/features/cone_layout/cone_layout_page.dart';
import 'package:cut_list_app/i18n/app_language.dart';
import '../support/test_database.dart';
import 'ai_chat_execution_test.dart' show mount, FixtureSpeech;
import 'development_height_skill_test.dart' show Visible;
import 'global_pipe_slope_flow_test.dart' show say, settle;
import 'cone_layout_skill_test.dart' as cone;
import 'eccentric_cone_skill_test.dart' as eccentric;
import 'transition_layout_skill_test.dart' as transition;

void main() {
  useTestDatabase();
  test(
      'height question derives actual angle-mode height, not stale hidden field',
      () async {
    final base = {...cone.payload, 'mode': 'halfAngle', 'half_angle_deg': 30}
      ..remove('height_mm');
    final expected = ConeAssistantInput.fromFields(base).result.heightMm;
    final skill = DevelopmentSummarySkill();
    final ctx = AssistantContext(lang: AppLanguage.pl, modules: Visible(base));
    final m = skill.match(
        Utterance('Jaka jest aktualna wysokość', lang: AppLanguage.pl), ctx)!;
    final r = await skill.run(m, ctx) as AnswerResult;
    expect(r.answer.text.pl,
        contains('${assistantNumber(expected, AppLanguage.pl)} mm'));
    expect(r.show, isNull);
  });
  test('summary refuses invalid, missing or wrong module inputs', () async {
    final skill = DevelopmentSummarySkill(),
        visible = Visible({...cone.payload, 'thickness_mm': -1});
    final ctx = AssistantContext(lang: AppLanguage.pl, modules: visible);
    final u = Utterance('Podsumuj bieżące rozwinięcie', lang: AppLanguage.pl);
    final m = skill.match(u, ctx)!;
    expect(await skill.run(m, ctx), isA<FailedResult>());
    visible.fields = null;
    final missing = await skill.run(m, ctx) as AnswerResult;
    expect(missing.actionCompleted, false);
    expect(
        skill.match(
            u,
            AssistantContext(
                lang: AppLanguage.pl,
                modules:
                    const FixedModuleContext(activeToolId: 'iso_notebook'))),
        isNull);
  });
  test('model cannot turn advice, translation or a change request into a read',
      () {
    final s = DevelopmentSummarySkill();
    final ctx =
        AssistantContext(lang: AppLanguage.pl, modules: Visible(cone.payload));
    Utterance u(String text) => Utterance(text, lang: AppLanguage.pl);
    final summary = u('Podsumuj ten stożek');
    expect(
        s.acceptsProposal(
            u('Zrób zestawienie aktualnego stożka'), summary, ctx),
        true);
    for (final text in [
      'Przetłumacz podsumuj ten stożek',
      'Nie podsumowuj tego stożka',
      'Zrób zestawienie nowego stożka',
      'Zmień wysokość stożka na 500 mm',
      'Zrób zestawienie aktualnego stożka i zmień wysokość',
      'Jaka jest aktualna wysokość'
    ]) {
      expect(s.acceptsProposal(u(text), summary, ctx), false, reason: text);
    }
  });
  for (final entry in [
    (cone.command, cone.payload),
    (eccentric.command, eccentric.fields),
    (transition.command, transition.fields)
  ]) {
    testWidgets(
        'read ${entry.$2['shape']} uses manually changed form and never writes',
        (t) async {
      await mount(t,
          interpret: (_) async => throw StateError('Exact summary is local'));
      await say(t, entry.$1);
      final b = ToolBridge.instance, handle = ToolBridge.instance.current!;
      final base = {...entry.$2, 'height_mm': 750, 'thickness_mm': 6};
      expect(await handle.apply(base), isEmpty);
      await settle(t);
      await say(t, 'Jaka jest aktualna wysokość');
      expect(find.textContaining('Bieżąca wysokość wynosi 750 mm'),
          findsOneWidget);
      expect(b.inputFields('cone_layout'), base);
      await say(t, 'Podsumuj bieżące rozwinięcie');
      expect(find.text('750 mm'), findsWidgets);
      expect(b.inputFields('cone_layout'), base);
      expect(b.current, same(handle));
      final context = t.element(find.byType(ConeLayoutPage));
      final dialog = showDialog<void>(
          context: context,
          builder: (_) => const AlertDialog(content: Text('Hold')));
      await t.pumpAndSettle();
      final skill = DevelopmentSummarySkill();
      final ctx = AssistantContext(lang: AppLanguage.pl, modules: b);
      final m = SkillMatch(skill, .99, slots: const {'query': 'summary'});
      final r = await skill.run(m, ctx) as AnswerResult;
      expect(r.actionCompleted, false);
      Navigator.of(context).pop();
      await dialog;
      await settle(t);
      expect(b.inputFields('cone_layout'), base);
      expect(t.takeException(), isNull);
    });
  }
  testWidgets('mocked speech reads current transition without interpretation',
      (t) async {
    final speech = FixtureSpeech();
    await mount(t,
        speech: speech,
        interpret: (_) async => throw StateError('Exact read is native'));
    await say(t, transition.command);
    final before = ToolBridge.instance.inputFields('cone_layout');
    await t.tap(find.byKey(const Key('assistant-mic')));
    await settle(t);
    speech.emit('Jaka jest aktualna wysokość');
    await settle(t);
    expect(
        find.textContaining('Bieżąca wysokość wynosi 400 mm'), findsOneWidget);
    expect(ToolBridge.instance.inputFields('cone_layout'), before);
    expect(t.takeException(), isNull);
  });
  testWidgets(
      'AI natural summary routes to a native read of the same foreground form',
      (t) async {
    var calls = 0;
    await mount(t, interpret: (_) async {
      calls++;
      return const AiCommandPlan('execute',
          [AiCommandStep('development.summary', 'Podsumuj ten stożek')], '');
    });
    await say(t, cone.command);
    final before = ToolBridge.instance.inputFields('cone_layout');
    await say(t, 'Zrób zestawienie aktualnego stożka');
    expect(calls, 1);
    expect(find.textContaining('Bieżący stożek współosiowy'), findsOneWidget);
    expect(ToolBridge.instance.inputFields('cone_layout'), before);
    expect(t.takeException(), isNull);
  });
}
