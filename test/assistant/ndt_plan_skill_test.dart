import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cut_list_app/assistant/core/skill.dart';
import 'package:cut_list_app/assistant/skills/own_data/ndt_plan_skill.dart';
import 'package:cut_list_app/domain/ndt/ndt_plan.dart';
import 'package:cut_list_app/domain/weld_journal/weld_entry.dart';
import 'package:cut_list_app/domain/weld_journal/weld_ndt.dart';
import 'package:cut_list_app/features/ndt_plan/ndt_plan_store.dart';
import 'package:cut_list_app/i18n/app_language.dart';
import '../support/weld_fixtures.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  final welds = [
    for (var i = 1; i <= 20; i++) weld('$i', status: 'OK'),
    weld('x1', project: 'Alfa', status: 'OK'),
  ];
  Future<SkillResult> say(String text, {List<WeldEntry>? data}) async {
    final s = NdtPlanSkill(
        loadWelds: () async => data ?? welds,
        loadLastProject: () async => 'Blok 4');
    final u = Utterance(text, lang: AppLanguage.pl);
    final ctx = AssistantContext(
        lang: AppLanguage.pl, modules: const FixedModuleContext());
    final m = s.match(u, ctx);
    expect(m, isNotNull, reason: text);
    return s.run(m!, ctx);
  }

  test('same plan as the module for the saved project rules', () async {
    final set = NdtRuleSet(
        preset: NdtPreset.b313, rules: ndtPresetRules(NdtPreset.b313));
    await const NdtPlanStore().save('Blok 4', set);
    final r = await say('Ile spoin trzeba zlecić do badań') as AnswerResult;
    final plan = computeNdtPlan(welds, rules: set.rules, project: 'Blok 4');
    expect(r.answer.text.pl, contains('Projekt „Blok 4”: ${plan.welds} spoin'));
    for (final e in plan.toOrder.entries) {
      expect(r.answer.text.pl, contains('${e.key.code} ${e.value.length}'));
    }
    expect(r.show!.fields, {'project': 'Blok 4'});
  });

  test('named project without rules asks to pick a set in the module',
      () async {
    final r = await say('Plan badań NDT w projekcie Alfa') as AnswerResult;
    expect(r.answer.text.pl, contains('nie ma jeszcze reguł'));
    expect(r.show!.fields, {'project': 'Alfa'});
    expect(await say('plan badań NDT w projekcie Omega'), isA<FailedResult>());
  });
}
