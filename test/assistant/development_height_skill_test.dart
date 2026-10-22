import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:cut_list_app/assistant/assistant_ai_client.dart';
import 'package:cut_list_app/assistant/core/skill.dart';
import 'package:cut_list_app/assistant/core/tool_bridge.dart';
import 'package:cut_list_app/assistant/skills/fitter_routes/development_height_skill.dart';
import 'package:cut_list_app/i18n/app_language.dart';
import '../support/test_database.dart';
import 'ai_chat_execution_test.dart' show mount;
import 'global_pipe_slope_flow_test.dart' show say, settle;
import 'cone_layout_skill_test.dart' as cone;
import 'eccentric_cone_skill_test.dart' as eccentric;
import 'transition_layout_skill_test.dart' as transition;

class Visible extends ModuleContext implements FieldModuleContext {
  Visible(this.fields);
  Map<String, Object?>? fields;
  @override
  String? get activeToolId => 'cone_layout';
  @override
  bool get onHomeOrAssistant => false;
  @override
  Map<String, Object?>? inputFields(String id) => fields;
}

void main() {
  useTestDatabase();
  test('source guard preserves number and accepts natural directive only', () {
    final s = DevelopmentHeightSkill();
    final ctx =
        AssistantContext(lang: AppLanguage.pl, modules: Visible(cone.payload));
    Utterance u(String t) => Utterance(t, lang: AppLanguage.pl);
    final proposed = u('Zmień tylko wysokość na 500 mm');
    expect(
        s.acceptsProposal(
            u('Niech wysokość wynosi 500 mm resztę zostaw bez zmian'),
            proposed,
            ctx),
        true);
    for (final text in [
      'Zmień wysokość na 600 mm',
      'Jak zmienić wysokość na 500 mm',
      'Nie zmieniaj wysokości na 500 mm',
      'Zmień wysokość na -500 mm',
      'Zmień tylko średnicę na 500 mm',
      'Zmień wysokość na 500 mm i średnicę na 300 mm',
      'Przetłumacz zmień wysokość na 500 mm',
      'Niech wysokość wynosi połowę 500 mm'
    ]) {
      expect(s.acceptsProposal(u(text), proposed, ctx), false, reason: text);
    }
  });
  test('angle/slant mode switches to height without carrying a second size',
      () async {
    final s = DevelopmentHeightSkill();
    for (final mode in ['halfAngle', 'slant']) {
      final base = {...cone.payload, 'mode': mode}..remove('height_mm');
      base[mode == 'halfAngle' ? 'half_angle_deg' : 'slant_mm'] =
          mode == 'halfAngle' ? 30 : 700;
      final ctx =
          AssistantContext(lang: AppLanguage.pl, modules: Visible(base));
      final match = s.match(
          Utterance('Zmień wysokość na 500 mm', lang: AppLanguage.pl), ctx)!;
      final r = await s.run(match, ctx) as AnswerResult;
      expect(r.show!.fields, cone.payload);
    }
  });
  test('invalid or unavailable live form cannot borrow past values', () async {
    final s = DevelopmentHeightSkill();
    final visible = Visible({...cone.payload, 'thickness_mm': -1});
    final ctx = AssistantContext(lang: AppLanguage.pl, modules: visible);
    final m = s.match(
        Utterance('Zmień wysokość na 500 mm', lang: AppLanguage.pl), ctx)!;
    expect(await s.run(m, ctx), isA<FailedResult>());
    visible.fields = null;
    final r = await s.run(m, ctx) as AnswerResult;
    expect(r.actionCompleted, false);
    expect(r.show, isNull);
    expect(
        s.match(
            Utterance('Zmień wysokość na 500 mm', lang: AppLanguage.pl),
            AssistantContext(
                lang: AppLanguage.pl,
                modules: const FixedModuleContext(activeToolId: 'heat_input'))),
        isNull);
  });
  for (final entry in [
    (cone.command, cone.payload),
    (eccentric.command, eccentric.fields),
    (transition.command, transition.fields)
  ]) {
    testWidgets(
        'native height edit preserves manually changed visible ${entry.$2['shape']} inputs',
        (t) async {
      await mount(t,
          interpret: (_) async =>
              throw StateError('Exact height edit is native'));
      await say(t, entry.$1);
      final b = ToolBridge.instance;
      final handle = b.current!;
      final base = {...entry.$2, 'thickness_mm': 6, 'height_mm': 750};
      expect(await handle.apply(base), isEmpty);
      await settle(t);
      await say(t, 'Zmień tylko wysokość na 600 mm');
      expect(b.current, same(handle));
      expect(b.inputFields('cone_layout'), {...base, 'height_mm': 600});
      expect(t.takeException(), isNull);
    });
  }
  for (final changed in [false, true]) {
    testWidgets(
        'AI natural height request uses live form and discards changed snapshot: changed=$changed',
        (t) async {
      final pending = Completer<AiCommandPlan>();
      var calls = 0;
      await mount(t, interpret: (_) {
        calls++;
        return pending.future;
      });
      await say(t, transition.command);
      final b = ToolBridge.instance;
      final handle = b.current!;
      await say(t, 'Niech wysokość wynosi 600 mm resztę zostaw bez zmian');
      expect(calls, 1);
      final base = {...transition.fields};
      if (changed) {
        base['offset_x_mm'] = -80;
        expect(await handle.apply(base), isEmpty);
        await settle(t);
      }
      pending.complete(const AiCommandPlan(
          'execute',
          [
            AiCommandStep(
                'development.height', 'Zmień tylko wysokość na 600 mm')
          ],
          ''));
      await settle(t);
      expect(b.inputFields('cone_layout'),
          {...base, if (!changed) 'height_mm': 600});
      expect(t.takeException(), isNull);
    });
  }
}
