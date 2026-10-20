// Mózg asystenta: kolejność reguł (pytanie w toku → ocena umiejętności →
// kontynuacja → fallbacki → „nie rozumiem"), remis, „anuluj", alternatywy
// N-best, wyjątek w umiejętności i zapis parametru bez zapisu przed
// potwierdzeniem.

import 'package:flutter_test/flutter_test.dart';

import 'package:cut_list_app/assistant/core/brain.dart';
import 'package:cut_list_app/assistant/core/skill.dart';
import 'package:cut_list_app/i18n/app_language.dart';

import '../support/assistant_test_support.dart';

/// Atrapa: trafia, gdy padło [word]; stały wynik; liczy uruchomienia.
class _WordSkill extends AssistantSkill {
  _WordSkill(this.id, this.word, this.score,
      {this.toolId, this.fallbackOrder, this.throws = false, this.ask});

  @override
  final String id;
  final String word;
  final double score;
  @override
  final String? toolId;
  @override
  final int? fallbackOrder;
  final bool throws;

  /// Slot, o który umiejętność pyta, gdy go brak.
  final String? ask;
  int runs = 0;
  SkillMatch? lastRun;

  @override
  AssistantTier get tier => AssistantTier.b;
  @override
  List<SkillExample> get examples => [SkillExample(word, word)];

  @override
  SkillMatch? match(Utterance u, AssistantContext ctx) {
    if (!u.hasAny([word])) return null;
    final n = u.dn();
    return SkillMatch(this, score,
        slots: {if (n != null) 'dn': n}, utterance: u);
  }

  @override
  Map<String, Object?> slotsFrom(Utterance u, AssistantContext ctx) {
    final n = u.dn();
    return {if (n != null) 'dn': n};
  }

  @override
  Future<SkillResult> run(SkillMatch m, AssistantContext ctx) async {
    runs++;
    lastRun = m;
    if (throws) throw StateError('boom');
    if (ask != null && !m.slots.containsKey(ask)) {
      return AskResult(ask!, AssistantText.same('$ask?'), partial: m);
    }
    return AnswerResult(
        AssistantAnswer(text: AssistantText.same('$id ${m.slots}')));
  }
}

class _BrokenMatcher extends _WordSkill {
  _BrokenMatcher() : super('broken', 'rura', .9);
  @override
  SkillMatch? match(Utterance u, AssistantContext ctx) =>
      throw StateError('broken matcher');
}

void main() {
  late DateTime clock;
  late AssistantContext ctx;

  AssistantContext makeCtx({String? active}) => AssistantContext(
        lang: AppLanguage.pl,
        modules: FixedModuleContext(activeToolId: active),
        now: () => clock,
      );

  Utterance pl(String s, {List<String> alt = const []}) =>
      Utterance(s, lang: AppLanguage.pl, alternatives: alt);

  setUp(() {
    clock = DateTime(2026, 10, 19, 12);
    ctx = makeCtx();
  });

  test(
      'calculation preflight tolerates broken matchers, respects threshold and never executes',
      () {
    final valid = _WordSkill('valid', 'rura', .9);
    final brain = AssistantBrain(skills: [_BrokenMatcher(), valid]);
    expect(brain.recognizesCalculation(pl('rura'), ctx), isTrue);
    expect(valid.runs, 0);
    expect(brain.pending, isNull);
    expect(brain.recognizesCalculation(pl('nie obliczaj rury'), ctx), isFalse);
    expect(
        AssistantBrain(skills: [_BrokenMatcher()])
            .recognizesCalculation(pl('rura'), ctx),
        isFalse);
    expect(
        AssistantBrain(skills: [_WordSkill('low', 'rura', .3)])
            .recognizesCalculation(pl('rura'), ctx),
        isFalse);
  });
  group('ocena umiejętności', () {
    test('najwyższy wynik ≥ progu wygrywa', () async {
      final a = _WordSkill('a', 'rura', 0.6, toolId: 'x');
      final b = _WordSkill('b', 'rura', 0.9, toolId: 'y');
      final brain = AssistantBrain(skills: [a, b]);
      final r = await brain.handle(pl('rura'), ctx);
      expect(r.match!.skill.id, 'b');
      expect(b.runs, 1);
      expect(a.runs, 0);
    });

    test('wynik poniżej progu → fallback, a potem „nie rozumiem"', () async {
      final low = _WordSkill('low', 'rura', 0.5);
      final brain = AssistantBrain(skills: [low], suggest: (_) => const []);
      final r = await brain.handle(pl('rura'), ctx);
      expect(r.notUnderstood, isTrue);
      expect(r.result, isA<NotUnderstood>());
      expect(low.runs, 0);
    });

    test('remis różnych modułów → pytanie „Chodzi o … czy …?"', () async {
      final a = _WordSkill('a', 'rura', 0.80, toolId: 'dn_mm');
      final b = _WordSkill('b', 'rura', 0.76, toolId: 'wall_thickness');
      final brain = AssistantBrain(skills: [a, b]);
      final r = await brain.handle(pl('rura'), ctx);
      final ask = r.result as AskResult;
      expect(ask.slot, 'skill');
      expect(ask.choices, hasLength(2));
      expect(brain.pending, isNotNull);
      expect(a.runs + b.runs, 0);
      // wybór drugiej opcji chipem
      final chosen = await brain.handle(pl(ask.choices[1].utterance), ctx);
      expect(chosen.match!.skill.id, 'b');
      expect(b.runs, 1);
      expect(brain.pending, isNull);
    });

    test('remis — wybór słowem „pierwsze"', () async {
      final a = _WordSkill('a', 'rura', 0.80, toolId: 'dn_mm');
      final b = _WordSkill('b', 'rura', 0.78, toolId: 'wall_thickness');
      final brain = AssistantBrain(skills: [a, b]);
      await brain.handle(pl('rura'), ctx);
      final r = await brain.handle(pl('pierwsze'), ctx);
      expect(r.match!.skill.id, 'a');
    });

    test('ten sam moduł to nie remis', () async {
      final a = _WordSkill('a', 'rura', 0.80, toolId: 'dn_mm');
      final b = _WordSkill('b', 'rura', 0.79, toolId: 'dn_mm');
      final brain = AssistantBrain(skills: [a, b]);
      final r = await brain.handle(pl('rura'), ctx);
      expect(r.match!.skill.id, 'a');
    });

    test('premia kontekstu dla bieżącego modułu', () async {
      final a = _WordSkill('a', 'rura', 0.80, toolId: 'dn_mm');
      final b = _WordSkill('b', 'rura', 0.75, toolId: 'wall_thickness');
      final brain = AssistantBrain(skills: [a, b]);
      final r =
          await brain.handle(pl('rura'), makeCtx(active: 'wall_thickness'));
      expect(r.match!.skill.id, 'b');
    });

    test('fallbacki w kolejności, tylko gdy nic nie trafiło', () async {
      final open = _WordSkill('open', 'otworz', 0.8, fallbackOrder: 1);
      final caps = _WordSkill('caps', 'otworz', 0.8, fallbackOrder: 0);
      final main = _WordSkill('main', 'rura', 0.8);
      final brain = AssistantBrain(skills: [open, main, caps]);
      expect((await brain.handle(pl('otwórz'), ctx)).match!.skill.id, 'caps');
      expect(
          (await brain.handle(pl('otwórz rura'), ctx)).match!.skill.id, 'main');
    });

    test('wyjątek w run → FailedResult, mózg działa dalej', () async {
      final bad = _WordSkill('bad', 'rura', 0.9, throws: true);
      final ok = _WordSkill('ok', 'kolano', 0.9);
      final brain = AssistantBrain(skills: [bad, ok]);
      final r = await brain.handle(pl('rura'), ctx);
      expect(r.result, isA<FailedResult>());
      expect(r.match!.skill.id, 'bad');
      final r2 = await brain.handle(pl('kolano'), ctx);
      expect(r2.match!.skill.id, 'ok');
    });

    test('„nie rozumiem" niesie propozycje', () async {
      final brain = AssistantBrain(
          skills: [_WordSkill('a', 'rura', 0.9)],
          suggest: (_) => const [
                FollowUp(AssistantText.same('X'), 'otwórz x'),
              ]);
      final r = await brain.handle(pl('bla bla'), ctx);
      expect(
          (r.result as NotUnderstood).suggestions.single.utterance, 'otwórz x');
    });
  });

  group('pytanie w toku', () {
    test('odpowiedź z wartością slotu → run z dołożonym slotem', () async {
      final s = _WordSkill('s', 'srednica', 0.8, ask: 'dn');
      final brain = AssistantBrain(skills: [s]);
      final r1 = await brain.handle(pl('średnica'), ctx);
      expect((r1.result as AskResult).slot, 'dn');
      final r2 = await brain.handle(pl('dn 50'), ctx);
      expect(r2.result, isA<AnswerResult>());
      expect(s.lastRun!.slots['dn'], 50);
      expect(brain.pending, isNull);
    });

    test('„anuluj" kasuje pytanie', () async {
      final s = _WordSkill('s', 'srednica', 0.8, ask: 'dn');
      final brain = AssistantBrain(skills: [s]);
      await brain.handle(pl('średnica'), ctx);
      final r = await brain.handle(pl('anuluj'), ctx);
      expect(brain.pending, isNull);
      expect(r.result, isA<AnswerResult>());
      expect(s.runs, 1);
    });

    test('inna umiejętność ≥ progu kasuje pytanie', () async {
      final s = _WordSkill('s', 'srednica', 0.8, ask: 'dn');
      final k = _WordSkill('k', 'kolano', 0.8);
      final brain = AssistantBrain(skills: [s, k]);
      await brain.handle(pl('średnica'), ctx);
      final r = await brain.handle(pl('kolano'), ctx);
      expect(r.match!.skill.id, 'k');
      expect(brain.pending, isNull);
    });

    test('bełkot → to samo pytanie jeszcze raz', () async {
      final s = _WordSkill('s', 'srednica', 0.8, ask: 'dn');
      final brain = AssistantBrain(skills: [s], suggest: (_) => const []);
      await brain.handle(pl('średnica'), ctx);
      final r = await brain.handle(pl('eee'), ctx);
      expect((r.result as AskResult).slot, 'dn');
      expect(brain.pending, isNotNull);
    });

    test('cancelPending', () async {
      final s = _WordSkill('s', 'srednica', 0.8, ask: 'dn');
      final brain = AssistantBrain(skills: [s]);
      await brain.handle(pl('średnica'), ctx);
      brain.cancelPending();
      expect(brain.pending, isNull);
    });
  });

  group('kontynuacja i dopowiedzenie', () {
    test('„a dla DN50" po trafieniu → ta sama umiejętność z nowym slotem',
        () async {
      final s = _WordSkill('s', 'srednica', 0.8);
      final brain = AssistantBrain(skills: [s]);
      await brain.handle(pl('średnica dn40'), ctx);
      clock = clock.add(const Duration(seconds: 30));
      final r = await brain.handle(pl('a dla DN50?'), ctx);
      expect(r.match!.skill.id, 's');
      expect(s.lastRun!.slots['dn'], 50);
    });

    test('kontynuacja wygasa po 2 min', () async {
      final s = _WordSkill('s', 'srednica', 0.8);
      final brain = AssistantBrain(skills: [s], suggest: (_) => const []);
      await brain.handle(pl('średnica dn40'), ctx);
      clock = clock.add(const Duration(minutes: 3));
      final r = await brain.handle(pl('a dla DN50?'), ctx);
      expect(r.notUnderstood, isTrue);
    });

    test('dopowiedzenie bez słowa kontynuacji tylko do 8 s', () async {
      final s = _WordSkill('s', 'srednica', 0.8);
      final brain = AssistantBrain(skills: [s], suggest: (_) => const []);
      await brain.handle(pl('średnica dn40'), ctx);
      clock = clock.add(const Duration(seconds: 5));
      final r = await brain.handle(pl('DN50'), ctx);
      expect(r.match!.skill.id, 's');
      expect(s.lastRun!.slots['dn'], 50);
      clock = clock.add(const Duration(seconds: 20));
      final r2 = await brain.handle(pl('DN65'), ctx);
      expect(r2.notUnderstood, isTrue);
    });
  });

  group('alternatywy N-best', () {
    test('wybór alternatywy z najwyższym wynikiem', () async {
      final h = BrainHarness();
      final r = await h.say('ten en 40', alternatives: ['de en 40']);
      expect(r.match!.skill.id, 'pipe.od');
      expect(r.usedAlternative, 'de en 40');
      expect(textOf(r.result), contains('48,3 mm'));
    });

    test('raw wygrywa przy równym wyniku', () async {
      final h = BrainHarness();
      final r = await h.say('dn40 ile mm', alternatives: ['dn 40 ile mm']);
      expect(r.usedAlternative, isNull);
    });
  });

  group('zapis parametru ze starego parsera', () {
    test('→ ConfirmResult, nic nie zapisane przed potwierdzeniem', () async {
      final h = BrainHarness();
      final r =
          await h.say('zapisz TIG nierdzewka ścianka 2 mm 60 A bez drutu');
      expect(r.match!.skill.id, 'legacy.save');
      final confirm = r.result as ConfirmResult;
      expect(h.actions.savedParams, isEmpty);
      final undo = await confirm.perform();
      expect(h.actions.savedParams, hasLength(1));
      await undo!();
      expect(h.actions.savedParams, isEmpty);
      expect(h.actions.undos, 1);
    });

    test('brakujące pole → pytanie, odpowiedź → podsumowanie', () async {
      final h = BrainHarness();
      final r = await h.say('zapisz TIG nierdzewka ścianka 2 mm bez drutu');
      expect((r.result as AskResult).slot, 'current_a');
      final r2 = await h.say('60');
      expect(r2.result, isA<ConfirmResult>());
      expect(h.actions.savedParams, isEmpty);
    });
  });

  test('jedna tura naraz: wyniki w kolejności wywołań', () async {
    final h = BrainHarness();
    final f1 = h.say('dn40');
    final f2 = h.say('a dla DN50?');
    final r1 = await f1;
    final r2 = await f2;
    expect(textOf(r1.result), contains('DN40'));
    expect(textOf(r2.result), contains('DN50'));
  });
}
