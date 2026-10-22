import '../../../domain/exam/exam_questions.dart';
import '../../core/skill.dart';
import '../core/explain_tool_skill.dart' show explainedTool;
import '../core/skill_guards.dart';

const _letters = ['A', 'B', 'C', 'D', 'E', 'F'];

ExamCategory? _category(Utterance u) {
  final f = u.folded;
  if (RegExp(r'\bproces\w*|4063').hasMatch(f)) return ExamCategory.processes;
  if (RegExp(r'\bniezgodnos\w*|\bwad\w*|6520').hasMatch(f)) {
    return ExamCategory.imperfections;
  }
  if (RegExp(r'\bpozycj\w*|6947').hasMatch(f)) return ExamCategory.positions;
  if (RegExp(r'\buprawnien\w*|9606').hasMatch(f)) {
    return ExamCategory.qualification;
  }
  if (RegExp(r'\bpoziom\w* jakosci|5817').hasMatch(f)) return ExamCategory.quality;
  if (RegExp(r'\belektrod\w*|\bspoiw\w*|\bgaz\w*').hasMatch(f)) {
    return ExamCategory.consumables;
  }
  if (RegExp(r'\bbhp\b|\bbezpieczen\w*|\bsafety').hasMatch(f)) {
    return ExamCategory.safety;
  }
  if (RegExp(r'\bslownict\w*|\bniemieck\w*|\bangielsk\w*|\bvocabular').hasMatch(f)) {
    return ExamCategory.vocabulary;
  }
  return null;
}

/// Odpowiedź: litera („B”, „be”), numer („druga”, „2”) albo treść opcji.
int? _choice(Utterance u, List<String> options) {
  final f = u.folded.trim();
  final letter = RegExp(r'^(?:odpowiedz |answer )?([a-f])$').firstMatch(f);
  if (letter != null) return _letters.indexOf(letter[1]!.toUpperCase());
  const spokenLetters = {'a': 0, 'be': 1, 'ce': 2, 'de': 3};
  if (spokenLetters.containsKey(f)) return spokenLetters[f];
  const ordinals = {
    'pierwsza': 0,
    'druga': 1,
    'trzecia': 2,
    'czwarta': 3,
    'first': 0,
    'second': 1,
    'third': 2,
    'fourth': 3,
  };
  if (ordinals.containsKey(f)) return ordinals[f];
  final n = u.items.where((i) => i.isNumber).toList();
  if (n.length == 1 && u.items.length == 1) {
    final i = n.single.value!.toInt() - 1;
    if (i >= 0 && i < options.length) return i;
  }
  for (var i = 0; i < options.length; i++) {
    if (Utterance(options[i], lang: u.lang).folded == f) return i;
  }
  return null;
}

/// Pytanie z egzaminu spawacza głosem: odpowiedzi A–D jako chipy,
/// sprawdzenie z wyjaśnieniem i źródłem. Pytania z rysunkiem symbolu
/// zostają w module (trzeba je zobaczyć).
class ExamQuestionSkill extends AssistantSkill {
  ExamQuestionSkill({int Function()? seed})
      : _seed = seed ?? (() => DateTime.now().microsecondsSinceEpoch);
  final int Function() _seed;

  @override
  String get id => 'exam.question';
  @override
  String get toolId => 'welder_exam';
  @override
  AssistantTier get tier => AssistantTier.b;
  @override
  bool get readOnly => true;
  @override
  List<SkillExample> get examples => const [
        SkillExample('Zadaj mi pytanie egzaminacyjne', 'Ask me an exam question'),
        SkillExample('Pytanie z egzaminu spawacza o procesy',
            'Welder exam question about processes'),
        SkillExample('Przepytaj mnie z BHP', 'Quiz me on safety'),
        SkillExample('Pytanie egzaminacyjne o pozycje spawania',
            'Exam question about welding positions'),
        SkillExample('Daj mi pytanie z egzaminu', 'Give me an exam question'),
        SkillExample('Przepytaj mnie przed egzaminem', 'Quiz me before the exam'),
      ];
  @override
  List<SkillRejection> get rejections => const [
        SkillRejection('otwórz egzamin spawacza', routesTo: 'tool.open'),
        SkillRejection('do czego służy egzamin spawacza', routesTo: 'tool.explain'),
        SkillRejection('kiedy mi wygasa uprawnienie na 141'),
      ];

  @override
  SkillMatch? match(Utterance u, AssistantContext ctx) {
    if (explainedTool(u) != null ||
        kOpenOrAboutStart.hasMatch(u.folded)) {
      return null;
    }
    final quiz = u.hasStem(const ['przepytaj', 'quiz']) ||
        (u.hasStem(const ['pytani', 'question']) &&
            u.hasStem(const ['egzamin', 'exam']));
    if (!quiz) return null;
    final c = _category(u);
    return SkillMatch(this, .93,
        slots: {if (c != null) 'category': c.name}, utterance: u);
  }

  @override
  Map<String, Object?>? fillSlot(
      String slot, Utterance u, AssistantContext ctx) {
    if (slot != 'answer') return null;
    // Opcje i poprawna odpowiedź są w slotach pytania — fillSlot dostaje
    // tylko wypowiedź, więc odpowiedź liczymy w run.
    return {'answer_text': u.raw};
  }

  @override
  Future<SkillResult> run(SkillMatch m, AssistantContext ctx) async {
    final en = ctx.lang.name == 'en';
    final options = (m.slots['options'] as List?)?.cast<String>();
    if (options == null) {
      final category = ExamCategory.values
          .where((c) => c.name == m.slots['category'])
          .firstOrNull;
      final drawn = drawExamQuestions(
              seed: _seed(), en: en, category: category, count: 10)
          .where((q) => q.glyph == null)
          .toList();
      if (drawn.isEmpty) {
        return const FailedResult(AssistantText(
            'Nie mam teraz pytania bez rysunku — otwórz egzamin w module.',
            'No question without a drawing right now — open the exam in the module.'));
      }
      final q = drawn.first;
      final text = StringBuffer(q.prompt);
      for (var i = 0; i < q.options.length; i++) {
        text.write('\n${_letters[i]}) ${q.options[i]}');
      }
      return AskResult(
          'answer', AssistantText.same(text.toString()),
          partial: m.copyWith(slots: {
            ...m.slots,
            'qid': q.id,
            'options': q.options,
            'correct': q.correctIndex,
            'explanation': q.explanation,
            'source': q.source,
          }),
          choices: [
            for (var i = 0; i < q.options.length; i++)
              FollowUp(AssistantText.same(_letters[i]), _letters[i]),
          ]);
    }
    final correct = m.slots['correct'] as int;
    final picked = _choice(
        Utterance(m.slots['answer_text'] as String? ?? '', lang: ctx.lang),
        options);
    if (picked == null) {
      return AskResult(
          'answer',
          AssistantText(
              'Powiedz literę odpowiedzi: ${_letters.take(options.length).join(', ')}.',
              'Say the answer letter: ${_letters.take(options.length).join(', ')}.'),
          partial: m,
          choices: [
            for (var i = 0; i < options.length; i++)
              FollowUp(AssistantText.same(_letters[i]), _letters[i]),
          ]);
    }
    final ok = picked == correct;
    final right = '${_letters[correct]}) ${options[correct]}';
    final why = '${m.slots['explanation']} (${m.slots['source']})';
    return AnswerResult(
        AssistantAnswer(
            text: AssistantText(
                ok ? 'Dobrze! $right. $why' : 'Niestety nie. Poprawna: $right. $why',
                ok ? 'Correct! $right. $why' : 'Not quite. Correct: $right. $why')),
        show: ShowInModule(toolId));
  }
}
