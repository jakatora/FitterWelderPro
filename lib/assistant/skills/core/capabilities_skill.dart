// `assistant.capabilities` — fallback „co umiesz?" (ogólnie) i „co tu
// zrobię?" (dla modułu na wierzchu). Lista z PRZYKŁADÓW umiejętności
// katalogu — dokumentacja, test i „co umiem" to jedno źródło (spec §4.2).
// Uczciwie (spec §2.2): moduł bez umiejętności liczących — „otworzę
// i opiszę, liczenie głosem jeszcze nie działa".

import '../../../i18n/app_language.dart';
import '../../../widgets/tool_registry.dart';
import '../../core/skill.dart';

final _generalRe = RegExp(
    r'^(?:(?:a|i|hej|hey|ok|okej|asystencie|asystent|powiedz|powiedz mi|'
    r'prosze|please|pokaz|show|tell me|so)\s+)*'
    r'(?:co (?:umiesz|potrafisz|mozesz)|w czym (?:mi )?(?:pomozesz|pomagasz)|'
    r'jak (?:ci|cie) uzywac|jak z (?:toba|ciebie) korzystac|'
    r'jakie (?:masz )?(?:funkcje|komendy|polecenia)|'
    r'what (?:can|do) you do|what can i (?:ask|say)|'
    r'how do i use you|help me|what are your (?:skills|commands))'
    r'(?:\s+(?:zrobic|robic|dla mnie|for me|asystencie|assistant))*$');

final _moduleRe = RegExp(
    r'\b(?:co (?:tu|tutaj) (?:zrobie|zrobisz|moge|mozna|mozesz|zrobic)|'
    r'co (?:moge|mozna|mozesz) (?:tu|tutaj|w tym module) (?:zrobic)?|'
    r'co (?:umiesz|potrafisz) (?:tu|tutaj|w tym module)|'
    r'what can (?:i|you) do here|what can you do (?:in|with) this)\b');

class CapabilitiesSkill extends AssistantSkill {
  CapabilitiesSkill(this._catalog);

  final Iterable<AssistantSkill> Function() _catalog;

  @override
  String get id => 'assistant.capabilities';
  @override
  String? get toolId => 'assistant';
  @override
  AssistantTier get tier => AssistantTier.a;
  @override
  int? get fallbackOrder => 0;

  @override
  List<SkillExample> get examples => const [
        SkillExample('Co umiesz?', 'What can you do?'),
        SkillExample('W czym mi pomożesz?', 'What can I ask?'),
        SkillExample('Jakie masz polecenia?', 'What are your commands?'),
      ];

  @override
  List<SkillRejection> get rejections => const [
        SkillRejection('otwórz heat input', routesTo: 'tool.open'),
        SkillRejection('co to jest heat input', routesTo: 'tool.explain'),
      ];

  @override
  SkillMatch? match(Utterance u, AssistantContext ctx) {
    final f = u.folded;
    if (_moduleRe.hasMatch(f)) {
      final active = ctx.modules.activeToolId;
      if (active != null && toolById(active) != null) {
        return SkillMatch(this, 0.9, slots: {'tool': active}, utterance: u);
      }
      return SkillMatch(this, 0.85, utterance: u);
    }
    if (_generalRe.hasMatch(f)) return SkillMatch(this, 0.9, utterance: u);
    return null;
  }

  @override
  Future<SkillResult> run(SkillMatch m, AssistantContext ctx) async {
    final toolId = m.slots['tool'] as String?;
    final tool = toolId == null ? null : toolById(toolId);
    if (tool != null) return _forModule(tool, ctx.lang);
    return _general(ctx.lang);
  }

  SkillResult _forModule(ToolSpec tool, AppLanguage lang) {
    final en = lang == AppLanguage.en;
    final skills = [
      for (final s in _catalog())
        if (s.toolId == tool.id && s.examples.isNotEmpty) s,
    ];
    final examples = [
      for (final s in skills)
        for (final e in s.examples.take(2)) e,
    ];
    final textPl = skills.isEmpty
        ? '„${tool.titlePl}”: ${tool.subtitlePl}. Ten moduł mogę otworzyć '
            'i opisać, ale liczenie głosem w nim jeszcze nie działa.'
        : '„${tool.titlePl}”: ${tool.subtitlePl}. Zapytaj mnie na przykład:';
    final textEn = skills.isEmpty
        ? '"${tool.titleEn}": ${tool.subtitleEn}. I can open and describe '
            'this module, but voice calculation is not there yet.'
        : '"${tool.titleEn}": ${tool.subtitleEn}. Ask me for example:';
    return AnswerResult(
      AssistantAnswer(
        text: AssistantText(textPl, textEn),
        lines: [
          for (final e in examples)
            AnswerLine(const AssistantText('Powiedz', 'Say'), en ? e.en : e.pl),
        ],
      ),
      followUps: [
        for (final e in examples.take(3))
          FollowUp(AssistantText(e.pl, e.en), en ? e.en : e.pl),
      ],
    );
  }

  SkillResult _general(AppLanguage lang) {
    final en = lang == AppLanguage.en;
    final regular = [
      for (final s in _catalog())
        if (s.fallbackOrder == null && s.examples.isNotEmpty) s,
    ];
    final fallbacks = [
      for (final s in _catalog())
        if (s.fallbackOrder != null && s.examples.isNotEmpty && s != this) s,
    ]..sort((a, b) => a.fallbackOrder!.compareTo(b.fallbackOrder!));
    final shown = [...regular, ...fallbacks];
    AssistantText labelOf(AssistantSkill s) {
      final t = s.toolId == null ? null : toolById(s.toolId!);
      if (t != null) return AssistantText(t.titlePl, t.titleEn);
      return switch (s.fallbackOrder) {
        1 => const AssistantText('Otwieranie narzędzi', 'Opening tools'),
        2 => const AssistantText('Opis narzędzi', 'Tool descriptions'),
        3 => const AssistantText('Pomoc i słownik', 'Help and glossary'),
        _ => AssistantText.same(s.id),
      };
    }

    return AnswerResult(
      AssistantAnswer(
        text: const AssistantText(
          'Liczę z tabel aplikacji, otwieram i opisuję każde narzędzie, '
              'zapisuję parametry spawania i wpisy do dziennika (zawsze po '
              'Twoim potwierdzeniu) i odpowiadam z Pomocy. Spróbuj:',
          'I calculate from the app tables, open and describe every tool, '
              'save welding parameters and journal entries (always after you '
              'confirm) and answer from Help. Try:',
        ),
        spoken: const AssistantText(
          'Liczę z tabel, otwieram narzędzia, zapisuję po potwierdzeniu '
              'i odpowiadam z Pomocy. Przykłady są na ekranie.',
          'I calculate from the tables, open tools, save after you confirm '
              'and answer from Help. Examples are on screen.',
        ),
        lines: [
          for (final s in shown)
            AnswerLine(labelOf(s),
                en ? s.examples.first.en : s.examples.first.pl),
        ],
      ),
      followUps: [
        for (final s in shown.take(3))
          FollowUp(AssistantText(s.examples.first.pl, s.examples.first.en),
              en ? s.examples.first.en : s.examples.first.pl),
      ],
    );
  }
}
