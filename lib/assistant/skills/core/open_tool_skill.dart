import 'calculator_action_skill.dart' show calculatorNavigationPrerequisite;
// `tool.open` — fallback: „otwórz / pokaż / włącz X", „gdzie jest X".
//
// Szuka w rejestrze narzędzi (`searchTools`). Dwa narzędzia z tym samym
// wynikiem → pytanie, które otworzyć. Samo „otwórz" → pytanie o nazwę.

import '../../../i18n/app_language.dart';
import '../../../services/help_search.dart' show normalizeForSearch;
import '../../../widgets/tool_registry.dart';
import '../../core/skill.dart';
import '../../core/tool_lookup.dart';
import '../../knowledge_question.dart' show withoutPolishVoiceFillers;
import 'skill_words.dart';

final _whereRe = RegExp(r'^(?:(?:a|i|hej|hey|ok|okej|asystencie|asystent)\s+)*'
    r'(?:gdzie (?:jest|sa|znajde|mam|znalezc|szukac)|'
    r'where (?:is|are|do i find|can i find)|how do i (?:find|get to))\b');

/// Słowa ogólne, które nie są częścią nazwy narzędzia.
const Set<String> _generic = {
  'mi',
  'me',
  'the',
  'a',
  'an',
  'prosze',
  'please',
  'modul',
  'modulu',
  'narzedzie',
  'narzedzia',
  'ekran',
  'kalkulator',
  'kalkulatora',
  'calculator',
  'tool',
  'screen',
  'module',
  'grupa',
  'grupe',
  'grupy',
  'group',
  'app',
  'okno',
  'zakladke',
  'zakladka',
  'tab',
  'moj',
  'moje',
  'moja',
  'my',
  'do',
  'na',
  'to',
  'teraz',
  'now',
  'szybko',
};

/// Zapytanie po czasowniku „otwórz/gdzie jest", bez słów ogólnych.
String? openQuery(Utterance u) {
  final f = withoutPolishVoiceFillers(u);
  final m = kOpenVerbAtStartRe.firstMatch(f) ?? _whereRe.firstMatch(f);
  if (m == null) return null;
  final words = f
      .substring(m.end)
      .split(' ')
      .where((w) => w.isNotEmpty && !_generic.contains(w))
      .toList();
  return words.join(' ');
}

String? _navigationQuery(Utterance u) {
  final normalized = u.withRaw(withoutPolishVoiceFillers(u));
  if (referencesInstruction(normalized) || isNegatedCommand(normalized)) return null;
  final direct = openQuery(u);
  if (direct != null) return direct;
  final natural = RegExp(
          r'^(?:(?:prosze|please|hej|hey) )?(?:przejdzmy (?:teraz )?do|wejdzmy (?:teraz )?(?:do|w)|przenies mnie (?:teraz )?do|chce (?:teraz )?(?:przejsc do|wejsc w|otworzyc)|(?:czy )?mozesz (?:mi )?(?:otworzyc|pokazac)|let s (?:now )?go to|take me (?:now )?to|i (?:want|would like) to (?:open|go to)|(?:could|can|would) you (?:please )?(?:open|show)) (.+)$')
      .firstMatch(normalized.folded);
  return natural == null ? null : openQuery(u.withRaw('open ${natural[1]}'));
}

ToolSpec? _uniqueNavigationTarget(String? query, AppLanguage lang) {
  if (query == null || query.isEmpty) return null;
  // A group is not a request for whichever tool happens to score highest.
  if (_exactGroup(query, lang) != null) return null;
  final hits = findTools(query, lang);
  if (hits.isEmpty || hits.length > 1 && hits[1].score == hits.first.score) {
    return null;
  }
  return hits.first.tool;
}

ToolGroup? _exactGroup(String? query, AppLanguage lang) {
  if (query == null || query.isEmpty) return null;
  final folded = normalizeForSearch(query);
  if (lang == AppLanguage.pl) {
    final inflected = switch (folded) {
      'bezpieczenstwa pracy' => ToolGroup.safety,
      'ciecia i projektow' => ToolGroup.cutProjects,
      'kolan i ksztaltek' => ToolGroup.elbowsFittings,
      'odgalezien i siodel' => ToolGroup.branches,
      'dokumentacje i uprawnienia' => ToolGroup.documentation,
      'dokumentacji i uprawnien' => ToolGroup.documentation,
      'kontrole i badania' => ToolGroup.inspection,
      'kontroli i badan' => ToolGroup.inspection,
      'trase i spadki' => ToolGroup.routeSlope,
      'trasy i spadkow' => ToolGroup.routeSlope,
      'tabel i przelicznikow' => ToolGroup.tables,
      'podpor i kolnierzy' => ToolGroup.supportsFlanges,
      'parametrow spawania' => ToolGroup.weldParams,
      'kalkulatorow' => ToolGroup.weldCalculators,
      'wykonczenia nierdzewki' => ToolGroup.stainlessFinish,
      'wycen i kosztow' => ToolGroup.costing,
      _ => null,
    };
    if (inflected != null && toolsInGroup(inflected).isNotEmpty) return inflected;
  }
  return ToolGroup.values.where((group) =>
      toolsInGroup(group).isNotEmpty &&
      normalizeForSearch(lang == AppLanguage.en ? group.titleEn : group.titlePl) == folded)
      .firstOrNull;
}

class OpenToolSkill extends AssistantSkill {
  @override
  bool get canInterruptPendingWithAi => true;
  @override
  Iterable<String> aiTaskSwitchCommands(
      Utterance source, AssistantContext ctx) {
    final target =
        _uniqueNavigationTarget(_navigationQuery(source), source.lang);
    return target == null
        ? const []
        : [
            ctx.lang == AppLanguage.en
                ? 'open ${target.titleEn}'
                : 'otwórz ${target.titlePl}'
          ];
  }

  @override
  bool acceptsProposal(
      Utterance original, Utterance command, AssistantContext context) {
    final source =
        _uniqueNavigationTarget(_navigationQuery(original), original.lang);
    final prerequisite = calculatorNavigationPrerequisite(original);
    final target = _uniqueNavigationTarget(openQuery(command), command.lang);
    return target != null &&
        (source?.id ?? prerequisite?.toolId) == target.id &&
        !referencesInstruction(command) &&
        !isNegatedCommand(command);
  }

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
        SkillExample(
            'Uruchom konwerter jednostek', 'Launch the unit converter'),
      ];

  @override
  List<SkillRejection> get rejections => const [
        SkillRejection('jaka jest średnica dn40', routesTo: 'pipe.od'),
        SkillRejection('pokaż co umiesz', routesTo: 'assistant.capabilities'),
        SkillRejection('pokaż ścianki dn40', routesTo: 'pipe.wall'),
      ];

  @override
  SkillMatch? match(Utterance u, AssistantContext ctx) {
    final group = _exactGroup(_navigationQuery(u), u.lang);
    if (group != null) {
      return SkillMatch(this, 0.9, slots: {'group': group.name}, utterance: u);
    }
    final q = openQuery(u);
    if (q == null) return null;
    final where = !kOpenVerbAtStartRe.hasMatch(withoutPolishVoiceFillers(u));
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
    return SkillMatch(this, where && tied.isNotEmpty ? 0.7 : 0.8,
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
    final target = _uniqueNavigationTarget(q, u.lang);
    return target == null ? null : {'tool': target.id, 'tied': null};
  }

  @override
  Map<String, Object?>? fillProposalSlot(String slot, Utterance command,
      Utterance original, AssistantContext ctx) {
    if (slot != 'tool' ||
        referencesInstruction(original) ||
        isNegatedCommand(original) ||
        referencesInstruction(command) ||
        isNegatedCommand(command)) {
      return null;
    }
    final source = _uniqueNavigationTarget(
        _navigationQuery(original) ?? original.folded, original.lang);
    final target = _uniqueNavigationTarget(
        openQuery(command) ?? command.folded, command.lang);
    return source != null && target != null && source.id == target.id
        ? {'tool': target.id, 'tied': null}
        : null;
  }

  @override
  Future<SkillResult> run(SkillMatch m, AssistantContext ctx) async {
    final groupName = m.slots['group'];
    if (groupName is String) {
      final group = toolGroupForNavigationId('tool_group:$groupName');
      if (group == null) {
        return const FailedResult(AssistantText('Ta grupa jest niedostępna.', 'This group is unavailable.'));
      }
      return AnswerResult(
        AssistantAnswer(text: AssistantText(
            'Otwieram grupę „${group.titlePl}”.', 'Opening the "${group.titleEn}" group.')),
        show: ShowInModule(toolGroupNavigationId(group)),
      );
    }
    final id = m.slots['tool'] as String?;
    final tied = (m.slots['tied'] as List?)?.cast<String>();
    if (id == null) {
      return AskResult(
        'tool',
        const AssistantText(
            'Które narzędzie otworzyć?', 'Which tool should I open?'),
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
          for (final t in tools)
            FollowUp(toolTitleText(t), toolTitle(t, ctx.lang)),
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
        text: AssistantText(
            'Otwieram „${tool.titlePl}”.', 'Opening "${tool.titleEn}".'),
      ),
      show: ShowInModule(tool.id),
      followUps: [
        FollowUp(
            const AssistantText('Do czego służy?', 'What is it for?'),
            en
                ? 'what is ${tool.titleEn} for?'
                : 'do czego służy ${tool.titlePl}?'),
      ],
    );
  }
}
