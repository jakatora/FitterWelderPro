import 'package:flutter_test/flutter_test.dart';
import 'package:cut_list_app/assistant/assistant_ai_client.dart';
import 'package:cut_list_app/assistant/core/skill.dart';
import 'package:cut_list_app/assistant/core/brain.dart';
import 'package:cut_list_app/i18n/app_language.dart';
import 'support/assistant_test_support.dart';

class ActionTrap extends AssistantSkill {
  int runs = 0;
  @override
  String get id => 'test.trap';
  @override
  String? get toolId => null;
  @override
  AssistantTier get tier => AssistantTier.b;
  @override
  List<SkillExample> get examples => const [SkillExample('begin', 'begin')];
  @override
  SkillMatch? match(Utterance u, AssistantContext c) =>
      u.raw == 'begin' ? SkillMatch(this, .99, utterance: u) : null;
  @override
  Map<String, Object?>? fillSlot(
          String slot, Utterance u, AssistantContext c) =>
      {'module_action': 'clear'};
  @override
  Future<SkillResult> run(SkillMatch m, AssistantContext c) async {
    runs++;
    return AskResult('inputs', const AssistantText('Dane?', 'Inputs?'),
        partial: m);
  }
}

void main() {
  late BrainHarness h;
  setUp(() {
    h = BrainHarness();
  });
  tearDown(() => h.timer.dispose());
  Utterance u(String s) => Utterance(s, lang: AppLanguage.pl);
  Future<AskResult> begin() async =>
      (await h.say('Zapisz TIG nierdzewka 60 A bez drutu')).result as AskResult;
  test('simple scalar stays local while a relation needs AI', () async {
    await begin();
    expect(h.brain.canAnswerPendingDirectly(u('dwa milimetry'), h.ctx), isTrue);
    expect(
        h.brain
            .canAnswerPendingDirectly(u('Połowa czterech milimetrów'), h.ctx),
        isFalse);
  });
  test('process name without ISO suffix remains a direct native choice',
      () async {
    await h.say('Oblicz heat input 24 V 230 A 150 mm/min');
    expect(h.brain.pending!.slot, 'process');
    expect(h.brain.canAnswerPendingDirectly(u('TIG'), h.ctx), isTrue);
  });
  test(
      'AI scalar reply cannot overwrite another validated field or save without confirmation',
      () async {
    final p = await begin();
    final result = await h.brain.answerProposal(
        expected: p,
        skillId: 'legacy.save',
        command: u('2 mm prąd 200 A'),
        original: u('Połowa czterech milimetrów'),
        context: h.ctx);
    expect(result.result, isA<ConfirmResult>());
    expect(h.actions.savedParams, isEmpty);
    await (result.result as ConfirmResult).perform();
    expect(h.actions.savedParams.single.wallMm, 2);
    expect(h.actions.savedParams.single.currentA, 60);
  });
  test('a stale or switched reply target cannot resume a different question',
      () async {
    final p = await begin();
    final wrong = await h.brain.answerProposal(
        expected: p,
        skillId: 'rolling.offset',
        command: u('2 mm'),
        original: u('Połowa czterech milimetrów'),
        context: h.ctx);
    expect(wrong.result, isA<FailedResult>());
    expect(identical(h.brain.pending, p), isTrue);
    await h.say('anuluj');
    final stale = await h.brain.answerProposal(
        expected: p,
        skillId: 'legacy.save',
        command: u('2 mm'),
        original: u('Połowa czterech milimetrów'),
        context: h.ctx);
    expect(stale.result, isA<FailedResult>());
    expect(h.actions.savedParams, isEmpty);
  });
  test('out-of-range model value keeps native pending fields for correction',
      () async {
    final p = await begin();
    final r = await h.brain.answerProposal(
        expected: p,
        skillId: 'legacy.save',
        command: u('2000 mm'),
        original: u('Dużo grubsza ścianka'),
        context: h.ctx);
    expect(r.result, isA<AskResult>());
    expect(h.brain.pending!.slot, 'wall_mm');
    expect(h.actions.savedParams, isEmpty);
    final corrected = await h.say('2 mm');
    expect(corrected.result, isA<ConfirmResult>());
    await (corrected.result as ConfirmResult).perform();
    expect(h.actions.savedParams.single.wallMm, 2);
    expect(h.actions.savedParams.single.currentA, 60);
  });
  test(
      'pending context exposes only descriptor and choices, not native partial payload',
      () async {
    final p = await begin();
    final r = assistantAiRequest(
        text: 'Połowa czterech milimetrów',
        context: h.ctx,
        skills: h.brain.skills,
        pendingReply: p,
        pendingQuestion: p.question.pl);
    expect((r['context'] as Map)['pending_reply'],
        {'skill_id': 'legacy.save', 'slot': 'wall_mm', 'choices': []});
  });
  test('reply envelope requires exactly one canonical step and empty message',
      () {
    final good = {
      'kind': 'reply',
      'steps': [
        {'skill_id': 'legacy.save', 'command': '2 mm'}
      ],
      'message': ''
    };
    expect(AiCommandPlan.fromJson(good, {'legacy.save'}).kind, 'reply');
    for (final bad in [
      {...good, 'steps': []},
      {
        ...good,
        'steps': [...(good['steps'] as List), ...(good['steps'] as List)]
      },
      {...good, 'message': 'Saved'}
    ]) {
      expect(() => AiCommandPlan.fromJson(bad, {'legacy.save'}),
          throwsFormatException);
    }
  });
  test(
      'literal safety-form prose remains native even when it contains relational words',
      () async {
    await h.say('przygotuj protokół przestrzeni zamkniętej');
    await h.say('Zbiornik A');
    expect(h.brain.pending!.slot, 'description');
    expect(
        h.brain.canAnswerPendingDirectly(
            u('Spawanie podpory dwa razy po trzy godziny'), h.ctx),
        isTrue);
  });
  test(
      'native mode change can answer a pending calculator before its page opens',
      () async {
    await h.say('oblicz spadek rury');
    expect(h.brain.pending, isNotNull);
    expect(
        h.brain.canAnswerPendingDirectly(
            u('ustaw tryb obliczanie długości'), h.ctx),
        isTrue);
  });
  test(
      'AI composite reply cannot turn field completion into a native clear action',
      () async {
    final trap = ActionTrap();
    final brain = AssistantBrain(skills: [trap]);
    await brain.handle(u('begin'), h.ctx);
    final pending = brain.pending!;
    final r = await brain.answerProposal(
        expected: pending,
        skillId: trap.id,
        command: u('clear'),
        original: u('opisz te dane'),
        context: h.ctx);
    expect(r.result, same(pending));
    expect(trap.runs, 1);
  });
}
