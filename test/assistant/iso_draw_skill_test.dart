import 'package:flutter_test/flutter_test.dart';
import 'package:cut_list_app/assistant/core/skill.dart';
import 'package:cut_list_app/assistant/skills/iso/iso_draw_skill.dart';
import 'package:cut_list_app/i18n/app_language.dart';
import 'support/assistant_test_support.dart';

void main() {
  test('matching never executes or opens the drawing port', () async {
    final port = FakeIsoDrawingPort();
    final skill = IsoDrawSkill(port);
    final ctx = AssistantContext(
        lang: AppLanguage.pl, modules: const FixedModuleContext());
    final u = Utterance('narysuj rura metr w prawo', lang: AppLanguage.pl);
    final m = skill.match(u, ctx)!;
    expect(port.calls, isEmpty);
    expect(skill.tier, AssistantTier.d);
    expect(skill.readOnly, false);
    final result = await skill.run(m, ctx);
    expect(result, isA<AnswerResult>());
    expect(port.calls.single.raw, u.raw);
  });
  test('bare sequences require notebook context, explicit drawing does not',
      () {
    final port = FakeIsoDrawingPort();
    final skill = IsoDrawSkill(port);
    AssistantContext ctx(String? tool) => AssistantContext(
        lang: AppLanguage.pl, modules: FixedModuleContext(activeToolId: tool));
    final bare = Utterance('rura kolano rura', lang: AppLanguage.pl);
    expect(skill.match(bare, ctx(null)), isNull);
    expect(skill.match(bare, ctx('iso_notebook')), isNotNull);
    expect(
        skill.match(Utterance('narysuj rura kolano rura', lang: AppLanguage.pl),
            ctx(null)),
        isNotNull);
    expect(port.calls, isEmpty);
  });
  test(
      'pending drawing question yields to opening, capabilities and domain questions',
      () async {
    final port = FakeIsoDrawingPort()..hasPendingQuestion = true;
    for (final entry in {
      'otwórz heat input': 'tool.open',
      'co umiesz': 'assistant.capabilities',
      'NDS manganu': 'fume.oel'
    }.entries) {
      final h = BrainHarness(iso: port);
      final result = await h.say(entry.key);
      expect(result.match?.skill.id, entry.value);
      expect(port.calls, isEmpty);
    }
  });
  test(
      'pending valve answers route through ISO instead of legacy parameter saving',
      () async {
    final port = FakeIsoDrawingPort()..hasPendingQuestion = true;
    final h = BrainHarness(iso: port);
    final result = await h.say('dodaj zawór zwrotny');
    expect(result.match?.skill.id, 'iso.draw');
    expect(port.calls.single.raw, 'dodaj zawór zwrotny');
    expect(h.actions.savedParams, isEmpty);
  });
  test('negated and quoted commands never execute the port', () async {
    final port = FakeIsoDrawingPort();
    final h = BrainHarness(iso: port);
    await h.say('nie rysuj rura metr w prawo');
    await h.say('wyjaśnij polecenie narysuj rura kolano rura');
    expect(port.calls, isEmpty);
  });
  test('winning speech alternative reaches the port once with the chosen text',
      () async {
    final port = FakeIsoDrawingPort();
    final h = BrainHarness(iso: port);
    final result = await h.say('qwerty',
        alternatives: ['narysuj rura metr w prawo'], byVoice: true);
    expect(result.match?.skill.id, 'iso.draw');
    expect(result.usedAlternative, 'narysuj rura metr w prawo');
    expect(port.calls.single.raw, 'narysuj rura metr w prawo');
    expect(port.calls.single.byVoice, true);
  });
}
