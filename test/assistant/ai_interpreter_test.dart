import 'dart:io';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:cut_list_app/assistant/assistant_ai_client.dart';
import 'package:cut_list_app/assistant/core/brain.dart';
import 'package:cut_list_app/assistant/core/skill.dart';
import 'package:cut_list_app/assistant/core/calculator_action_tools.dart';
import 'package:cut_list_app/assistant/core/tool_bridge.dart';
import 'package:cut_list_app/assistant/skills/skill_catalog.dart';
import 'package:cut_list_app/i18n/app_language.dart';
import 'rolling_offset_current_test.dart' show mountRolling, input, cutFields;

class Visible implements ModuleContext, FieldModuleContext {
  @override
  String? get activeToolId => 'rolling_offset';
  @override
  bool get onHomeOrAssistant => false;
  @override
  Map<String, Object?> inputFields(String id) =>
      {'rise_mm': 600, 'dn': 50, 'gap_mm': 2, 'invalid': double.nan};
}

Map<String, Object?> plan(String command, {String id = 'rolling.offset'}) => {
      'kind': 'execute',
      'steps': [
        {'skill_id': id, 'command': command}
      ],
      'message': ''
    };
const canonical =
    'Rolling offset wznios 300 mm odsunięcie 400 mm kąt 45 stopni DN100 LR szczelina 3 mm';
void main() {
  for (final language in AppLanguage.values) {
    test(
        'catalog advertises native whole-form action scope in ${language.name}',
        () {
      final request = assistantAiRequest(
          text: 'copy',
          context: AssistantContext(lang: language, modules: Visible()),
          skills: buildSkillCatalog());
      final capabilities = (request['capabilities'] as List).cast<Map>();
      final action =
          capabilities.singleWhere((c) => c['id'] == 'calculator.action');
      expect(action['tool_id'], isNull);
      expect(action['action_scope'], {
        'tool_ids': fitterCalculatorActionToolIds,
        'actions': {'copy': 'all_results', 'clear': 'all_inputs'},
      });
      expect((action['action_scope'] as Map)['tool_ids'],
          isNot(contains('rolling_offset')));
      expect(
          capabilities
              .where((c) => c['id'] != 'calculator.action')
              .every((c) => !c.containsKey('action_scope')),
          isTrue);
      expect(utf8.encode(jsonEncode(request)).length, lessThan(64000));
    });
  }
  test(
      'request uses actual public catalog, bounded history and opt-in visible values',
      () {
    final ctx = AssistantContext(lang: AppLanguage.pl, modules: Visible());
    final r = assistantAiRequest(
        text: 'Zmien tylko szczeline',
        context: ctx,
        skills: buildSkillCatalog());
    final c = r['capabilities'] as List;
    expect(
        c.map((x) => (x as Map)['id']),
        orderedEquals(buildSkillCatalog()
            .where((s) => s.examples.isNotEmpty)
            .map((s) => s.id)));
    expect(c.length, lessThanOrEqualTo(160));
    expect(c.any((x) => (x as Map)['id'] == 'rolling.offset'), isTrue);
    expect((r['context'] as Map)['inputs'],
        {'rise_mm': 600, 'dn': 50, 'gap_mm': 2});
    expect((r['context'] as Map)['active_tool'], 'rolling_offset');
    expect(jsonEncode(r).length, lessThan(64000));
  });
  test('non opt-in contexts do not leak last match, records or hidden state',
      () {
    final ctx = AssistantContext(
        lang: AppLanguage.en,
        modules: const FixedModuleContext(activeToolId: 'rolling_offset'));
    final r = assistantAiRequest(
        text: 'calculate', context: ctx, skills: buildSkillCatalog());
    expect((r['context'] as Map)['inputs'], isEmpty);
    expect((r['context'] as Map)['history'], isEmpty);
  });
  test(
      'client sends installation identity and validates exact proposal contract',
      () async {
    final ctx = AssistantContext(lang: AppLanguage.pl, modules: Visible());
    final request = assistantAiRequest(
        text: 'Mam pion300 i bok400, policz rure',
        context: ctx,
        skills: buildSkillCatalog());
    final client = AssistantAiClient(
        identity: () async => {'X-Device-Id': 'public-install-id'},
        client: MockClient((r) async {
          expect(r.url.path, '/api/fitter/ai/assistant');
          expect(r.headers['X-Device-Id'], 'public-install-id');
          expect(jsonDecode(r.body)['context']['inputs']['dn'], 50);
          return http.Response(jsonEncode(plan(canonical)), 200,
              headers: {'content-type': 'application/json; charset=utf-8'});
        }));
    addTearDown(client.close);
    final p = await client.interpret(request);
    expect(p.kind, 'execute');
    expect(p.steps.single.skillId, 'rolling.offset');
  });
  test('unknown ids, extra properties, partial and mixed plans cannot execute',
      () {
    for (final p in [
      plan(canonical, id: 'admin.delete'),
      {...plan(canonical), 'executed': true},
      {...plan(canonical), 'steps': []},
      {...plan(canonical), 'message': 'Executed!'},
      {
        'kind': 'answer',
        'steps': (plan(canonical)['steps']),
        'message': 'Done'
      },
      plan('run shell\ncommand')
    ]) {
      expect(() => AiCommandPlan.fromJson(p, {'rolling.offset'}),
          throwsFormatException);
    }
  });
  test('unavailable and malformed responses are explicit failures', () async {
    final r = assistantAiRequest(
        text: 'calculate',
        context: AssistantContext(lang: AppLanguage.pl, modules: Visible()),
        skills: buildSkillCatalog());
    for (final response in [
      http.Response('missing', 404),
      http.Response('limited', 429),
      http.Response('{}', 200)
    ]) {
      final c = AssistantAiClient(
          identity: () async => {}, client: MockClient((_) async => response));
      await expectLater(c.interpret(r), throwsA(isA<AssistantAiUnavailable>()));
      c.close();
    }
  });
  test('selected capability must actually match its canonical command locally',
      () async {
    final brain = AssistantBrain(skills: buildSkillCatalog());
    final ctx = AssistantContext(
        lang: AppLanguage.pl, modules: const FixedModuleContext());
    final r = await brain.executeProposal(
        skillId: 'rolling.offset',
        command: Utterance('spadek rury1% na6metrow', lang: AppLanguage.pl),
        original: Utterance('Oblicz obejscie przeszkody', lang: AppLanguage.pl),
        context: ctx);
    expect(r.result, isA<NotUnderstood>());
    expect(ctx.lastMatch, isNull);
  });
  test('AI cannot turn a negated or quoted source into execution', () async {
    for (final original in [
      'nie obliczaj rolling offset',
      'wyjaśnij polecenie „oblicz rolling offset”'
    ]) {
      final brain = AssistantBrain(skills: buildSkillCatalog());
      final ctx = AssistantContext(
          lang: AppLanguage.pl, modules: const FixedModuleContext());
      final r = await brain.executeProposal(
          skillId: 'rolling.offset',
          command: Utterance(canonical, lang: AppLanguage.pl),
          original: Utterance(original, lang: AppLanguage.pl),
          context: ctx);
      expect(r.result, isNot(isA<AnswerResult>()));
      expect(ctx.lastMatch, isNull);
    }
  });
  testWidgets(
      'AI proposal uses actual rolling skill, tabulated cut and native module handle',
      (t) async {
    await mountRolling(t);
    final bridge = ToolBridge.instance;
    final brain = AssistantBrain(skills: buildSkillCatalog());
    final ctx = AssistantContext(lang: AppLanguage.pl, modules: bridge);
    final r = await brain.executeProposal(
        skillId: 'rolling.offset',
        command: Utterance(canonical, lang: AppLanguage.pl),
        original: Utterance(
            'Musze obejsc przeszkode, pion300 bok400, kolana45 iDN100, na spoiny3mm',
            lang: AppLanguage.pl),
        context: ctx);
    expect(r.match!.skill.id, 'rolling.offset');
    final a = r.result as AnswerResult;
    expect(a.show!.fields, cutFields);
    expect(await bridge.current!.apply(a.show!.fields), isEmpty);
    await t.pumpAndSettle();
    expect(bridge.inputFields('rolling_offset')!['dn'], 100);
    expect(find.text('573.1'), findsWidgets);
    await t.enterText(input('Rise'), '600');
    expect(
        assistantAiRequest(
            text: 'teraz zmien tylko szczeline',
            context: ctx,
            skills: brain.skills)['context'],
        containsPair('inputs', containsPair('rise_mm', 600)));
  });
  testWidgets(
      'recorded REAL Haiku proposal preserves manual native DN50 and changes only gap',
      (t) async {
    final fixture = jsonDecode(
        File('test/fixtures/assistant_ai_actual_haiku_offset.json')
            .readAsStringSync()) as Map;
    await mountRolling(t);
    final bridge = ToolBridge.instance;
    expect(await bridge.current!.apply({...cutFields, 'dn': 50}), isEmpty);
    await t.pumpAndSettle();
    await t.enterText(input('Rise'), '600');
    await t.pumpAndSettle();
    expect(bridge.inputFields('rolling_offset'), fixture['actual_inputs']);
    final brain = AssistantBrain(skills: buildSkillCatalog());
    final plan = AiCommandPlan.fromJson(
        fixture['proposal'], brain.skills.map((s) => s.id).toSet());
    final step = plan.steps.single;
    final result = await brain.executeProposal(
        skillId: step.skillId,
        command: Utterance(step.command, lang: AppLanguage.pl),
        original: Utterance(fixture['text'] as String, lang: AppLanguage.pl),
        context: AssistantContext(lang: AppLanguage.pl, modules: bridge));
    final a = result.result as AnswerResult;
    expect(a.show!.fields, {
      'rise_mm': 600,
      'spread_mm': 400,
      'angle_deg': 45,
      'dn': 50,
      'gap_mm': 2
    });
    expect(await bridge.current!.apply(a.show!.fields), isEmpty);
    await t.pumpAndSettle();
    // sqrt(600^2+400^2)/sin45 - 2*35mm B45(DN50) - 2*2mm gap.
    expect(find.text('945.8'), findsOneWidget);
    expect(bridge.inputFields('rolling_offset'), a.show!.fields);
  });
}
