import 'package:flutter_test/flutter_test.dart';
import 'package:cut_list_app/assistant/core/skill.dart';
import 'package:cut_list_app/assistant/core/brain.dart';
import 'package:cut_list_app/i18n/app_language.dart';

class Echo extends AssistantSkill {
  Echo(this.resolved);
  final Map<String, Object?>? resolved;
  @override
  String get id => 'test.resolved';
  @override
  String get toolId => 'rolling_offset';
  @override
  AssistantTier get tier => AssistantTier.b;
  @override
  List<SkillExample> get examples => const [SkillExample('echo', 'echo')];
  @override
  SkillMatch? match(Utterance u, AssistantContext ctx) => u.folded == 'echo'
      ? SkillMatch(this, .95,
          slots: const {'dn': 100, 'transient': true}, utterance: u)
      : null;
  @override
  Future<SkillResult> run(SkillMatch m, AssistantContext ctx) async =>
      AnswerResult(const AssistantAnswer(text: AssistantText.same('Done')),
          contextSlots: resolved);
}

void main() {
  test(
      'actual input slots replace request metadata and are frozen in reply and context',
      () async {
    final resolved = <String, Object?>{'dn': 50};
    final brain = AssistantBrain(skills: [Echo(resolved)]);
    final ctx = AssistantContext(
        lang: AppLanguage.pl, modules: const FixedModuleContext());
    final r = await brain.handle(Utterance('echo', lang: AppLanguage.pl), ctx);
    expect(r.match!.slots, {'dn': 50});
    expect(ctx.recentSlot('dn'), 50);
    resolved['dn'] = 75;
    expect(r.match!.slots, {'dn': 50});
    expect(ctx.recentSlot('dn'), 50);
    expect(() => r.match!.slots['dn'] = 75, throwsUnsupportedError);
  });
  test('empty actual inputs deliberately clear old request slots', () async {
    final brain = AssistantBrain(skills: [Echo({})]);
    final ctx = AssistantContext(
        lang: AppLanguage.pl, modules: const FixedModuleContext());
    final r = await brain.handle(Utterance('echo', lang: AppLanguage.pl), ctx);
    expect(r.match!.slots, isEmpty);
    expect(ctx.recentSlot('dn'), isNull);
  });
  test('unopted skills retain their existing request context', () async {
    final brain = AssistantBrain(skills: [Echo(null)]);
    final ctx = AssistantContext(
        lang: AppLanguage.pl, modules: const FixedModuleContext());
    final r = await brain.handle(Utterance('echo', lang: AppLanguage.pl), ctx);
    expect(r.match!.slots, {'dn': 100, 'transient': true});
    expect(ctx.recentSlot('dn'), 100);
  });
}
