import 'package:flutter_test/flutter_test.dart';
import 'package:cut_list_app/assistant/core/skill.dart';
import 'package:flutter/material.dart' show Key;
import 'package:cut_list_app/assistant/assistant_ai_client.dart';
import 'package:cut_list_app/assistant/core/tool_bridge.dart';
import 'package:cut_list_app/assistant/skills/fitter_routes/development_height_skill.dart';
import 'package:cut_list_app/domain/fitter/cone_assistant_input.dart';
import 'package:cut_list_app/i18n/app_language.dart';
import '../support/test_database.dart';
import 'development_height_skill_test.dart' show Visible;
import 'ai_chat_execution_test.dart' show mount, FixtureSpeech;
import 'global_pipe_slope_flow_test.dart' show say, settle;
import 'cone_layout_skill_test.dart' as cone;
import 'eccentric_cone_skill_test.dart' as eccentric;
import 'transition_layout_skill_test.dart' as transition;

void main() {
  useTestDatabase();
  final skill = DevelopmentHeightSkill();
  for (final request in [
    ('Zwiększ wysokość o 100 mm', 600.0),
    ('Increase height by 10 cm', 600.0),
    ('Zmniejsz wysokość o 100 mm', 400.0),
    ('Decrease the height by 10 cm', 400.0),
    ('Podwój wysokość', 1000.0),
    ('Double the height', 1000.0),
    ('Zmniejsz wysokość o połowę', 250.0),
    ('Halve height', 250.0)
  ]) {
    test('native relative height: ${request.$1}', () async {
      final ctx = AssistantContext(
          lang: AppLanguage.pl, modules: Visible(cone.payload));
      final u = Utterance(request.$1, lang: AppLanguage.pl);
      final m = skill.match(u, ctx)!;
      final r = await skill.run(m, ctx) as AnswerResult;
      expect(r.show!.fields, {...cone.payload, 'height_mm': request.$2});
    });
  }
  test(
      'relative source guard computes target from live inputs, not model arithmetic',
      () {
    final visible = Visible(cone.payload);
    final ctx = AssistantContext(lang: AppLanguage.pl, modules: visible);
    Utterance u(String s) => Utterance(s, lang: AppLanguage.pl);
    final source = u('Potrzebuję żeby zwiększyć wysokość o 100 mm');
    expect(skill.acceptsProposal(source, u('Zmień wysokość na 600 mm'), ctx),
        true);
    expect(skill.acceptsProposal(source, u('Zmień wysokość na 700 mm'), ctx),
        false);
    expect(
        skill.acceptsProposal(u('Zmniejsz wysokość o połowę'),
            u('Zmień wysokość na 250 mm'), ctx),
        true);
    visible.fields = {...cone.payload, 'height_mm': 800};
    expect(skill.acceptsProposal(source, u('Zmień wysokość na 600 mm'), ctx),
        false);
    expect(skill.acceptsProposal(source, u('Zmień wysokość na 900 mm'), ctx),
        true);
    visible.fields = null;
    expect(skill.acceptsProposal(source, u('Zmień wysokość na 600 mm'), ctx),
        false);
  });
  test(
      'slant/angle relative edits derive actual height through the existing engine',
      () async {
    for (final mode in ['slant', 'halfAngle']) {
      final base = {...cone.payload, 'mode': mode}..remove('height_mm');
      base[mode == 'slant' ? 'slant_mm' : 'half_angle_deg'] =
          mode == 'slant' ? 700 : 30;
      final current = ConeAssistantInput.fromFields(base).result.heightMm;
      final ctx =
          AssistantContext(lang: AppLanguage.pl, modules: Visible(base));
      final m = skill.match(
          Utterance('Zmniejsz wysokość o połowę', lang: AppLanguage.pl), ctx)!;
      final r = await skill.run(m, ctx) as AnswerResult;
      expect(r.show!.fields['height_mm'], current / 2);
      expect(r.show!.fields.containsKey('slant_mm'), false);
      expect(r.show!.fields.containsKey('half_angle_deg'), false);
      expect(r.show!.fields['mode'], 'height');
    }
  });
  for (final bad in [
    'Nie zwiększaj wysokości o 100 mm',
    'Jak zwiększyć wysokość o 100 mm',
    'Zwiększ wysokość o -100 mm',
    'Zwiększ wysokość o minus 100 mm',
    'Zwiększ wysokość o 100',
    'Zwiększ wysokość o 100 mm cm',
    'Zmień wysokość na 500 mm cm',
    'Zwiększ wysokość o 100 mm i średnicę o 20 mm',
    'Przetłumacz podwój wysokość',
    'Podwój wysokość i grubość',
    'Zmniejsz wysokość o połowę 500 mm'
  ]) {
    test('relative parser refuses ambiguous or unrelated scope: $bad', () {
      final ctx = AssistantContext(
          lang: AppLanguage.pl, modules: Visible(cone.payload));
      expect(skill.match(Utterance(bad, lang: AppLanguage.pl), ctx), isNull);
    });
  }
  test('nonpositive and out-of-domain relative results do not emit an update',
      () async {
    final ctx =
        AssistantContext(lang: AppLanguage.pl, modules: Visible(cone.payload));
    for (final text in [
      'Zmniejsz wysokość o 500 mm',
      'Zmniejsz wysokość o 600 mm',
      'Zwiększ wysokość o 100000 mm'
    ]) {
      final m = skill.match(Utterance(text, lang: AppLanguage.pl), ctx)!;
      expect(await skill.run(m, ctx), isA<FailedResult>());
    }
  });
  for (final entry in [
    (cone.command, cone.payload),
    (eccentric.command, eccentric.fields),
    (transition.command, transition.fields)
  ]) {
    testWidgets(
        'actual relative edits use current ${entry.$2['shape']} form and preserve other inputs',
        (t) async {
      await mount(t,
          interpret: (_) async =>
              throw StateError('Literal relative height is native'));
      await say(t, entry.$1);
      final b = ToolBridge.instance, handle = ToolBridge.instance.current!;
      final base = {...entry.$2, 'height_mm': 750, 'thickness_mm': 6};
      expect(await handle.apply(base), isEmpty);
      await settle(t);
      for (final edit in [
        ('Zwiększ wysokość o 10 cm', 850.0),
        ('Zmniejsz wysokość o połowę', 425.0),
        ('Podwój wysokość', 850.0),
        ('Zmniejsz wysokość o 50 mm', 800.0)
      ]) {
        await say(t, edit.$1);
        expect(b.inputFields('cone_layout'), {...base, 'height_mm': edit.$2});
      }
      await say(t, 'Zmniejsz wysokość o 1000 mm');
      expect(b.inputFields('cone_layout'), {...base, 'height_mm': 800.0});
      expect(t.takeException(), isNull);
    });
  }
  testWidgets('mock phone speech applies relative height through the real form',
      (t) async {
    final speech = FixtureSpeech();
    await mount(t,
        speech: speech,
        interpret: (_) async =>
            throw StateError('Literal relative voice is native'));
    await say(t, cone.command);
    await t.tap(find.byKey(const Key('assistant-mic')));
    await settle(t);
    speech.emit('Zwiększ wysokość o 100 mm');
    await settle(t);
    expect(ToolBridge.instance.inputFields('cone_layout'),
        {...cone.payload, 'height_mm': 600.0});
    expect(t.takeException(), isNull);
  });
  for (final wrong in [false, true]) {
    testWidgets(
        'AI relative normalization cannot invent arithmetic: wrong=$wrong',
        (t) async {
      var calls = 0;
      await mount(t, interpret: (_) async {
        calls++;
        return AiCommandPlan(
            'execute',
            [
              AiCommandStep(
                  'development.height',
                  wrong
                      ? 'Zmień wysokość na 700 mm'
                      : 'Zmień wysokość na 600 mm')
            ],
            '');
      });
      await say(t, cone.command);
      await say(t, 'Potrzebuję żeby zwiększyć wysokość o 100 mm');
      expect(calls, 1);
      expect(ToolBridge.instance.inputFields('cone_layout'),
          {...cone.payload, 'height_mm': wrong ? 500.0 : 600.0});
      expect(t.takeException(), isNull);
    });
  }
}
