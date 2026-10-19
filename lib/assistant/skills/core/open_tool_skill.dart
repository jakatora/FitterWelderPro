// `tool.open` — fallback: „otwórz / pokaż / włącz X", „gdzie jest X".
//
// Szuka w rejestrze narzędzi (`searchTools`). Dwa narzędzia z tym samym
// wynikiem → pytanie, które otworzyć. Samo „otwórz" → pytanie o nazwę.

import '../../../i18n/app_language.dart';
import '../../../services/help_search.dart' show normalizeForSearch;
import '../../../widgets/tool_registry.dart';
import '../../core/skill.dart';
import '../../core/tool_lookup.dart';
import 'skill_words.dart';

final _whereRe = RegExp(
    r'^(?:(?:a|i|hej|hey|ok|okej|asystencie|asystent)\s+)*'
    r'(?:gdzie (?:jest|sa|znajde|mam|znalezc|szukac)|'
    r'where (?:is|are|do i find|can i find)|how do i (?:find|get to))\b');

/// Słowa ogólne, które nie są częścią nazwy narzędzia.
const Set<String> _generic = {
  'mi', 'me', 'the', 'a', 'an', 'prosze', 'please', 'modul', 'modulu',
  'narzedzie', 'narzedzia', 'ekran', 'kalkulator', 'kalkulatora', 'calculator',
  'tool', 'screen', 'module', 'app', 'okno', 'zakladke', 'zakladka', 'tab',
  'moj', 'moje', 'moja', 'my', 'do', 'na', 'to', 'teraz', 'now', 'szybko',
};

/// Zapytanie po czasowniku „otwórz/gdzie jest", bez słów ogólnych.
String? openQuery(Utterance u) {
  final f = u.folded;
  final m = kOpenVerbAtStartRe.firstMatch(f) ?? _whereRe.firstMatch(f);
  if (m == null) return null;
  final words = f
      .substring(m.end)
      .split(' ')
      .where((w) => w.isNotEmpty && !_generic.contains(w))
      .toList();
  return words.join(' ');
}

class OpenToolSkill extends AssistantSkill {
  @override
  String get id => 'tool.open';
  @override
  String? get toolId => null;
  @override
  AssistantTier get tier => AssistantTier.a;
  @override
  int? get fallbackOrder => 1;

  @override
  List<SkillExample> get examples => const [
        SkillExample('Otwórz heat input', 'Open heat input'),
        SkillExample('Pokaż rolling offset', 'Show rolling offset'),
        SkillExample('Otwórz dziennik spoin', 'Open the weld journal'),
        SkillExample('Włącz tabelę DN', 'Open the DN table'),
        SkillExample('Gdzie jest kalkulator heat input?',
            'Where is the heat input calculator?'),
        SkillExample('Uruchom konwerter jednostek', 'Launch the unit converter'),
      ];

  @override
  List<SkillRejection> get rejections => const [
        SkillRejection('jaka jest średnica dn40', routesTo: 'pipe.od'),
        SkillRejection('pokaż co umiesz', routesTo: 'assistant.capabilities'),
        SkillRejection('pokaż ścianki dn40', routesTo: 'pipe.wall'),
      ];

  @override
  SkillMatch? match(Utterance u, AssistantContext ctx) {
    final q = openQuery(u);
    if (q == null) return null;
    final where = !kOpenVerbAtStartRe.hasMatch(u.folded);
    if (q.isEmpty) {
      return SkillMatch(this, 0.6, missing: const ['tool'], utterance: u);
    }
    final hits = findTools(q, u.lang);
    if (hits.isEmpty) return null;
    final top = hits.first;
    final tied = [
      for (final h in hits.skip(1))
        if (h.score == top.score) h.tool.id,
    ];
    return SkillMatch(this, where ? 0.7 : 0.8,
        slots: {
          'tool': top.tool.id,
          'query': q,
          if (tied.isNotEmpty) 'tied': [top.tool.id, ...tied.take(2)],
        },
        utterance: u);
  }

  @override
  Map<String, Object?>? fillSlot(
      String slot, Utterance u, AssistantContext ctx) {
    if (slot != 'tool') return null;
    final q = openQuery(u) ?? u.folded;
    if (q.isEmpty) return null;
    // Odpowiedź chipem albo pełną nazwą narzędzia.
    final norm = normalizeForSearch(q);
    for (final t in availableTools) {
      if (normalizeForSearch(t.titlePl) == norm ||
          normalizeForSearch(t.titleEn) == norm) {
        return {'tool': t.id, 'tied': null};
      }
    }
    final hits = findTools(q, u.lang);
    if (hits.isEmpty) return null;
    return {'tool': hits.first.tool.id, 'tied': null};
  }

  @override
  Future<SkillResult> run(SkillMatch m, AssistantContext ctx) async {
    final id = m.slots['tool'] as String?;
    final tied = (m.slots['tied'] as List?)?.cast<String>();
    if (id == null) {
      return AskResult(
        'tool',
        const AssistantText('Które narzędzie otworzyć?', 'Which tool should I open?'),
        partial: m,
      );
    }
    if (tied != null && tied.length > 1) {
      final tools = [
        for (final t in tied)
          if (toolById(t) case final spec?) spec,
      ];
      final namesPl = tools.map((t) => '„${t.titlePl}”').join(' czy ');
      final namesEn = tools.map((t) => '"${t.titleEn}"').join(' or ');
      return AskResult(
        'tool',
        AssistantText('Które otworzyć: $namesPl?', 'Which one: $namesEn?'),
        partial: m,
        choices: [
          for (final t in tools) FollowUp(toolTitleText(t), toolTitle(t, ctx.lang)),
        ],
      );
    }
    final tool = toolById(id);
    if (tool == null) {
      return const FailedResult(AssistantText(
          'Tego narzędzia nie ma w tej wersji aplikacji.',
          'This tool is not available in this version.'));
    }
    final en = ctx.lang == AppLanguage.en;
    return AnswerResult(
      AssistantAnswer(
        text: AssistantText('Otwieram „${tool.titlePl}”.',
            'Opening "${tool.titleEn}".'),
      ),
      show: ShowInModule(tool.id),
      followUps: [
        FollowUp(const AssistantText('Do czego służy?', 'What is it for?'),
            en
                ? 'what is ${tool.titleEn} for?'
                : 'do czego służy ${tool.titlePl}?'),
      ],
    );
  }
}
