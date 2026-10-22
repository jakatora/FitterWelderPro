import 'package:cut_list_app/features/cone_layout/cone_layout_page.dart';
import 'package:cut_list_app/domain/fitter/cone_assistant_input.dart';
import 'package:cut_list_app/services/wrap_template_pdf.dart';
import 'package:cut_list_app/assistant/core/skill.dart';
import 'package:cut_list_app/assistant/skills/fitter_routes/development_height_skill.dart';
import 'package:cut_list_app/i18n/app_language.dart';
import 'development_height_skill_test.dart' show Visible;
import 'package:flutter_test/flutter_test.dart';
import 'package:cut_list_app/assistant/assistant_ai_client.dart';
import 'package:cut_list_app/assistant/core/tool_bridge.dart';
import '../support/test_database.dart';
import 'ai_chat_execution_test.dart' show mount;
import 'global_pipe_slope_flow_test.dart' show say;
import 'cone_layout_skill_test.dart' as cone;

void main() {
  useTestDatabase();
  for (final answer in [
    'Jednak 10 cm',
    'Nie 20 cm tylko 10 cm',
    '10 cm zamiast 20 cm',
    'I mean 10 cm',
    'Not 20 cm but 10 cm',
    '10 cm instead of 20 cm',
    'Polowa 20 cm',
    'Half of 20 cm',
    'Polowa dwudziestu centymetrow',
    'Nie dwadziescia centymetrow tylko dziesiec centymetrow',
    '0,1 m zamiast 0,2 m'
  ]) {
    testWidgets('AI corrects owned height amount: $answer', (t) async {
      var calls = 0;
      await mount(t, interpret: (request) async {
        calls++;
        expect((request['context'] as Map)['pending_reply'], {
          'skill_id': 'development.height',
          'slot': 'amount',
          'choices': []
        });
        return const AiCommandPlan(
            'reply', [AiCommandStep('development.height', '100 mm')], '');
      });
      await say(t, cone.command);
      await say(t, 'Zwieksz wysokosc');
      await say(t, answer);
      expect(calls, 1);
      expect(ToolBridge.instance.inputFields('cone_layout'),
          {...cone.payload, 'height_mm': 600.0});
      expect(t.takeException(), isNull);
    });
  }
  testWidgets(
      'wrong model correction preserves question and allows exact retry',
      (t) async {
    var calls = 0;
    await mount(t, interpret: (_) async {
      calls++;
      return const AiCommandPlan(
          'reply', [AiCommandStep('development.height', '200 mm')], '');
    });
    await say(t, cone.command);
    await say(t, 'Zwieksz wysokosc');
    await say(t, 'Nie 20 cm tylko 10 cm');
    expect(calls, 1);
    expect(ToolBridge.instance.inputFields('cone_layout'), cone.payload);
    await say(t, '10 cm');
    expect(calls, 1);
    expect(ToolBridge.instance.inputFields('cone_layout'),
        {...cone.payload, 'height_mm': 600.0});
  });
  test(
      'correction guard rejects ambiguous operands and invented units or arithmetic',
      () {
    final skill = DevelopmentHeightSkill();
    final ctx =
        AssistantContext(lang: AppLanguage.pl, modules: Visible(cone.payload));
    Utterance u(String s) => Utterance(s, lang: AppLanguage.pl);
    for (final source in [
      'Nie 20 tylko 10 cm',
      '10 zamiast 20 cm',
      '10 cm zamiast 20',
      '10 cm zamiast -20 cm',
      'Jednak minus 10 cm',
      'Nie 20 cm tylko 10 cm i srednica 30 cm',
      'Jednak 10 cm mm',
      'Polowa 0 cm',
      'Polowa 20 cm i 30 cm',
      'Jak zmienic 20 cm na 10 cm',
      'Przetlumacz not 20 cm but 10 cm',
      '20 cm 10 cm',
      '10 cm lub 20 cm'
    ]) {
      expect(
          skill.fillProposalSlot('amount', u('100 mm'), u(source), ctx), isNull,
          reason: source);
    }
    expect(
        skill.fillProposalSlot(
            'height_mm', u('100 mm'), u('Jednak 10 cm'), ctx),
        isNull);
    expect(skill.fillProposalSlot('amount', u('10'), u('Jednak 10 cm'), ctx),
        isNull);
  });
  testWidgets(
      'AI outage preserves pending correction and accepts explicit retry',
      (t) async {
    var calls = 0;
    await mount(t, interpret: (_) async {
      calls++;
      throw const AssistantAiUnavailable(503);
    });
    await say(t, cone.command);
    await say(t, 'Zmniejsz wysokosc');
    await say(t, '10 cm zamiast 20 cm');
    expect(calls, 1);
    expect(ToolBridge.instance.inputFields('cone_layout'), cone.payload);
    await say(t, '10 cm');
    expect(calls, 1);
    expect(ToolBridge.instance.inputFields('cone_layout'),
        {...cone.payload, 'height_mm': 400.0});
    expect(t.takeException(), isNull);
  });
  for (final wrong in [false, true]) {
    testWidgets(
        'ordered workflow waits for corrected height before PDF: wrong=$wrong',
        (t) async {
      var calls = 0;
      final exports = <FlatTemplateSpec>[];
      await mount(t, home: ConeLayoutPage(sharePdf: (spec, name, en) async {
        exports.add(spec);
      }), interpret: (_) async {
        if (++calls == 1) {
          return const AiCommandPlan(
              'execute',
              [
                AiCommandStep('development.height', 'Zwieksz wysokosc'),
                AiCommandStep(
                    'development.export', 'Przygotuj PDF biezacego rozwiniecia')
              ],
              '');
        }
        return AiCommandPlan(
            'reply',
            [AiCommandStep('development.height', wrong ? '200 mm' : '100 mm')],
            '');
      });
      await say(t, cone.command);
      await say(t,
          'Zrob go troche wyzszego a nastepnie przygotuj PDF biezacego rozwiniecia.');
      expect(exports, isEmpty);
      expect(ToolBridge.instance.inputFields('cone_layout'), cone.payload);
      await say(t, 'Nie 20 cm tylko 10 cm');
      if (wrong) {
        expect(exports, isEmpty);
        expect(ToolBridge.instance.inputFields('cone_layout'), cone.payload);
        await say(t, '10 cm');
      }
      expect(calls, 2);
      final updated = {...cone.payload, 'height_mm': 600.0};
      expect(ToolBridge.instance.inputFields('cone_layout'), updated);
      expect(exports, hasLength(1));
      final pattern =
          ConeAssistantInput.fromFields(updated).result.part.pattern();
      expect(
          exports.single.shapes.first.widthMm, closeTo(pattern.widthMm, 1e-9));
      expect(t.takeException(), isNull);
    });
  }
  testWidgets(
      'AI outage never performs only the first half of height and PDF request',
      (t) async {
    var calls = 0, exports = 0;
    await mount(t, home: ConeLayoutPage(sharePdf: (_, name, en) async {
      exports++;
    }), interpret: (_) async {
      calls++;
      throw const AssistantAiUnavailable(503);
    });
    await say(t, cone.command);
    await say(t, 'Ustaw wysokosc na 600 mm i eksportuj szablon PDF');
    expect(calls, 1);
    expect(exports, 0);
    expect(ToolBridge.instance.inputFields('cone_layout'), cone.payload);
    expect(t.takeException(), isNull);
  });
}
