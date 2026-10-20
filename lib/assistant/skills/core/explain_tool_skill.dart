// `tool.explain` — fallback: „do czego służy X", „co to jest X", „jak działa
// X", „what is X for". Opis z rejestru (grupa + podtytuł) i przykłady
// głosowe umiejętności tego narzędzia. Nic nie otwiera — proponuje chip.

import '../../../i18n/app_language.dart';
import '../../../services/help_search.dart' show normalizeForSearch;
import '../../../widgets/tool_registry.dart';
import '../../core/skill.dart';
import '../../core/tool_lookup.dart';

final _explainRe = RegExp(
    r'^(?:(?:a|i|hej|hey|ok|okej|asystencie|asystent|powiedz|powiedz mi|'
    r'prosze|please|tell me|and)\s+)*'
    r'(?:do czego (?:sluzy|sluza|jest|sa|uzywa sie|uzywac|przyda sie|sie przyda)|'
    r'po co (?:jest |mi |sa )?|co (?:robi|robia)|co to (?:jest|za)|czym jest|'
    r'jak (?:dziala|dzialaja|uzywac|uzyc)|wyjasnij(?: mi)?|objasnij(?: mi)?|'
    r'opisz(?: mi)?|what (?:is|are|does)|explain|describe|how does|'
    r'how do i use)\s+');

final _trailRe = RegExp(r'\s+(?:for|do|work|works|used for|tool)$');

const Set<String> _generic = {
  'the', 'a', 'an', 'narzedzie', 'modul', 'kalkulator', 'kalkulatora',
  'calculator', 'tool', 'module', 'screen', 'ekran', 'ten', 'to',
};

/// Narzędzie, o które pyta wypowiedź — tylko gdy zapytanie to (prawie)
/// tytuł narzędzia, PL albo EN. Słowa kluczowe nie wystarczą („co to jest
/// porowatość" to pytanie o wiedzę, nie o moduł wad spoin).
ToolSpec? explainedTool(Utterance u) {
  final m = _explainRe.firstMatch(u.folded);
  if (m == null) return null;
  var q = u.folded.substring(m.end);
  q = q.replaceFirst(_trailRe, '');
  final terms = [
    for (final w in q.split(' '))
      if (w.isNotEmpty && !_generic.contains(w)) w,
  ];
  if (terms.isEmpty) return null;
  final hits = findTools(terms.join(' '), u.lang);
  for (final h in hits.take(3)) {
    if (_coversTitle(terms, h.tool)) return h.tool;
  }
  return null;
}

bool _coversTitle(List<String> terms, ToolSpec t) {
  for (final title in [t.titlePl, t.titleEn]) {
    final words = normalizeForSearch(title).split(' ');
    final ok = terms.every((term) {
      final stems = {
        term,
        if (term.length >= 6) term.substring(0, term.length - 2),
        if (term.length >= 5) term.substring(0, term.length - 1),
      };
      return words.any((w) => stems.any((s) => s.length >= 2 && w.startsWith(s)));
    });
    if (ok) return true;
  }
  return false;
}

class ExplainToolSkill extends AssistantSkill {
  ExplainToolSkill(this._catalog);

  final Iterable<AssistantSkill> Function() _catalog;

  @override
  String get id => 'tool.explain';
  @override
  String? get toolId => null;
  @override
  AssistantTier get tier => AssistantTier.a;
  @override
  int? get fallbackOrder => 2;

  @override
  List<SkillExample> get examples => const [
        SkillExample('Do czego służy rolling offset?', 'What is rolling offset for?'),
        SkillExample('Co to jest heat input?', 'What does heat input do?'),
        SkillExample('Jak działa zeszyt ISO?', 'How does the ISO notebook work?'),
        SkillExample('Wyjaśnij dylatację', 'Explain thermal expansion'),
      ];

  @override
  List<SkillRejection> get rejections => const [
        SkillRejection('otwórz rolling offset', routesTo: 'tool.open'),
        SkillRejection('dlaczego pojawia się porowatość', routesTo: 'defects.causes'),
        SkillRejection('jaka jest średnica dn40', routesTo: 'pipe.od'),
      ];

  @override
  SkillMatch? match(Utterance u, AssistantContext ctx) {
    final t = explainedTool(u);
    if (t == null) return null;
    return SkillMatch(this, 0.75, slots: {'tool': t.id}, utterance: u);
  }

  @override
  Future<SkillResult> run(SkillMatch m, AssistantContext ctx) async {
    final tool = toolById(m.slots['tool'] as String);
    if (tool == null) {
      return const FailedResult(AssistantText(
          'Tego narzędzia nie ma w tej wersji aplikacji.',
          'This tool is not available in this version.'));
    }
    final skills = [
      for (final s in _catalog())
        if (s.toolId == tool.id && s.examples.isNotEmpty) s,
    ];
    final section = tool.section == ToolSection.fitter
        ? const AssistantText('Monter', 'Fitter')
        : const AssistantText('Spawacz', 'Welder');
    final voicePl = skills.isEmpty
        ? ' Mogę go otworzyć i opisać; liczenie głosem w nim jeszcze nie działa.'
        : ' Głosem: „${skills.first.examples.first.pl}”.';
    final voiceEn = skills.isEmpty
        ? ' I can open and describe it; voice calculation is not there yet.'
        : ' By voice: "${skills.first.examples.first.en}".';
    final en = ctx.lang == AppLanguage.en;
    return AnswerResult(
      AssistantAnswer(
        text: AssistantText(
          '„${tool.titlePl}” (${section.pl} · ${tool.group.titlePl}) — '
              '${tool.subtitlePl}.$voicePl',
          '"${tool.titleEn}" (${section.en} · ${tool.group.titleEn}) — '
              '${tool.subtitleEn}.$voiceEn',
        ),
        lines: [
          for (final s in skills)
            AnswerLine(const AssistantText('Zapytaj', 'Ask'),
                en ? s.examples.first.en : s.examples.first.pl),
        ],
      ),
      followUps: [
        openFollowUp(tool, ctx.lang),
        for (final s in skills.take(2))
          FollowUp(AssistantText(s.examples.first.pl, s.examples.first.en),
              en ? s.examples.first.en : s.examples.first.pl),
      ],
    );
  }
}
