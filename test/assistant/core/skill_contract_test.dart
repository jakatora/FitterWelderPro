// Kontrakt umiejętności na atrapie: domyślne wartości, sloty do kontynuacji
// i odpowiedzi na pytanie, kontekst z zegarem, potwierdzenie bez zapisu
// przed `perform`.

import 'package:flutter_test/flutter_test.dart';

import 'package:cut_list_app/assistant/core/skill.dart';
import 'package:cut_list_app/i18n/app_language.dart';

/// Atrapa: „echo dn" — odpowiada samym DN, bez DN pyta.
class _EchoDnSkill extends AssistantSkill {
  int runs = 0;

  @override
  String get id => 'test.echo_dn';
  @override
  String? get toolId => 'dn_mm';
  @override
  AssistantTier get tier => AssistantTier.b;
  @override
  List<SkillExample> get examples =>
      const [SkillExample('echo dn40', 'echo dn40')];

  @override
  SkillMatch? match(Utterance u, AssistantContext ctx) {
    if (!u.hasAny(['echo'])) return null;
    final dn = u.dn();
    return SkillMatch(this, 0.8,
        slots: {if (dn != null) 'dn': dn},
        missing: [if (dn == null) 'dn'],
        utterance: u);
  }

  @override
  Map<String, Object?> slotsFrom(Utterance u, AssistantContext ctx) {
    final dn = u.dn();
    return {if (dn != null) 'dn': dn};
  }

  @override
  Future<SkillResult> run(SkillMatch m, AssistantContext ctx) async {
    runs++;
    final dn = m.slots['dn'];
    if (dn == null) {
      return AskResult('dn', const AssistantText('Jakie DN?', 'Which DN?'),
          partial: m);
    }
    return AnswerResult(AssistantAnswer(text: AssistantText.same('DN$dn')),
        show: ShowInModule('dn_mm', {'dn': dn}));
  }
}

/// Atrapa zapisu: liczy wywołania zapisu i cofnięcia.
class _SaveSkill extends AssistantSkill {
  int saves = 0;
  int undos = 0;

  @override
  String get id => 'test.save';
  @override
  String? get toolId => null;
  @override
  AssistantTier get tier => AssistantTier.c;
  @override
  List<SkillExample> get examples => const [SkillExample('zapisz', 'save')];
  @override
  bool get readOnly => false;
  @override
  bool get safetyCritical => true;

  @override
  SkillMatch? match(Utterance u, AssistantContext ctx) =>
      u.hasAny(['zapisz']) ? SkillMatch(this, 0.9, utterance: u) : null;

  @override
  Future<SkillResult> run(SkillMatch m, AssistantContext ctx) async =>
      ConfirmResult(
        const AssistantAnswer(text: AssistantText('Zapisać?', 'Save?')),
        () async {
          saves++;
          return () async => undos++;
        },
        touchOnly: safetyCritical,
      );
}

String describe(SkillResult r) => switch (r) {
      AnswerResult(:final answer) => 'answer:${answer.text.pl}',
      AskResult(:final slot) => 'ask:$slot',
      ConfirmResult() => 'confirm',
      NotUnderstood() => 'not_understood',
      FailedResult() => 'failed',
    };

void main() {
  late DateTime clock;
  AssistantContext ctx() => AssistantContext(
        lang: AppLanguage.pl,
        modules: const FixedModuleContext(),
        now: () => clock,
      );

  setUp(() => clock = DateTime(2026, 10, 19, 12));

  test('AssistantText wybiera język', () {
    const t = AssistantText('Średnica', 'Diameter');
    expect(t.of(AppLanguage.pl), 'Średnica');
    expect(t.of(AppLanguage.en), 'Diameter');
    expect(const AssistantText.same('DN40').of(AppLanguage.en), 'DN40');
  });

  test('wartości domyślne kontraktu', () {
    final s = _EchoDnSkill();
    expect(s.readOnly, isTrue);
    expect(s.safetyCritical, isFalse);
    expect(s.rejections, isEmpty);
    expect(s.fallbackOrder, isNull);
  });

  test('match → run → AnswerResult z pokazaniem w module', () async {
    final s = _EchoDnSkill();
    final c = ctx();
    final m = s.match(Utterance('echo dn40', lang: AppLanguage.pl), c)!;
    expect(m.score, 0.8);
    expect(m.slots, {'dn': 40});
    final r = await s.run(m, c);
    expect(describe(r), 'answer:DN40');
    expect((r as AnswerResult).show!.fields, {'dn': 40});
  });

  test('brak slotu → AskResult z częściowym trafieniem', () async {
    final s = _EchoDnSkill();
    final c = ctx();
    final m = s.match(Utterance('echo', lang: AppLanguage.pl), c)!;
    expect(m.missing, ['dn']);
    final r = await s.run(m, c) as AskResult;
    expect(r.slot, 'dn');
    expect(identical(r.partial, m), isTrue);
  });

  test('fillSlot: odpowiedź z wartością slotu i bez', () {
    final s = _EchoDnSkill();
    final c = ctx();
    expect(s.fillSlot('dn', Utterance('dn 50', lang: AppLanguage.pl), c),
        {'dn': 50});
    expect(s.fillSlot('dn', Utterance('nie wiem', lang: AppLanguage.pl), c),
        isNull);
  });

  test('copyWith zmienia tylko podane pola', () {
    final s = _EchoDnSkill();
    final m = SkillMatch(s, 0.6, slots: const {'dn': 40});
    final m2 = m.copyWith(slots: {'dn': 50});
    expect(m2.skill, s);
    expect(m2.score, 0.6);
    expect(m2.slots, {'dn': 50});
  });

  test('ConfirmResult nic nie zapisuje przed perform; Cofnij działa',
      () async {
    final s = _SaveSkill();
    final c = ctx();
    final r = await s.run(
        s.match(Utterance('zapisz', lang: AppLanguage.pl), c)!, c);
    expect(r, isA<ConfirmResult>());
    expect(s.saves, 0);
    final confirm = r as ConfirmResult;
    expect(confirm.touchOnly, isTrue);
    final undo = await confirm.perform();
    expect(s.saves, 1);
    await undo!();
    expect(s.undos, 1);
  });

  group('kontekst: ostatnie trafienie i okna czasu', () {
    test('recentSlot w oknie 2 min, potem null', () {
      final s = _EchoDnSkill();
      final c = ctx();
      c.remember(SkillMatch(s, 0.8, slots: const {'dn': 40}));
      expect(c.lastAt, clock);
      clock = clock.add(const Duration(minutes: 1, seconds: 59));
      expect(c.recentSlot('dn'), 40);
      clock = clock.add(const Duration(seconds: 2));
      expect(c.recentSlot('dn'), isNull);
    });
    test('okno dopowiedzenia 8 s', () {
      final s = _EchoDnSkill();
      final c = ctx();
      c.remember(SkillMatch(s, 0.8));
      clock = clock.add(const Duration(seconds: 7));
      expect(c.recentMatch(within: kAppendWindow), isNotNull);
      clock = clock.add(const Duration(seconds: 2));
      expect(c.recentMatch(within: kAppendWindow), isNull);
    });
    test('bez trafienia → null', () {
      expect(ctx().recentSlot('dn'), isNull);
    });
  });

  test('FixedModuleContext', () {
    const m = FixedModuleContext(activeToolId: 'heat_input',
        onHomeOrAssistant: false);
    expect(m.activeToolId, 'heat_input');
    expect(m.onHomeOrAssistant, isFalse);
    expect(const FixedModuleContext().onHomeOrAssistant, isTrue);
  });

  test('wszystkie rodzaje wyniku są obsłużone (sealed)', () {
    final s = _EchoDnSkill();
    final results = <SkillResult>[
      const AnswerResult(AssistantAnswer(text: AssistantText.same('x'))),
      AskResult('dn', const AssistantText.same('?'),
          partial: SkillMatch(s, 0.5)),
      ConfirmResult(const AssistantAnswer(text: AssistantText.same('x')),
          () async => null),
      const NotUnderstood([]),
      const FailedResult(AssistantText.same('x')),
    ];
    expect(results.map(describe).toList(), [
      'answer:x',
      'ask:dn',
      'confirm',
      'not_understood',
      'failed',
    ]);
  });
}
