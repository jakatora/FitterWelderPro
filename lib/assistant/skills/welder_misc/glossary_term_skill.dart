import '../../../data/welding_glossary.dart';
import '../../../domain/glossary/glossary.dart';
import '../../core/skill.dart';
import '../core/knowledge_skill.dart'
    show KnowledgeSkill, glossaryQuery, glossaryTargets;
import '../core/skill_words.dart';

Map<String, Object?> _slots(Utterance u) {
  final targets = glossaryTargets(u.folded);
  return {
    'query': glossaryQuery(u),
    if (targets.isNotEmpty)
      'target': targets.length == 1 ? targets.single.name : 'ambiguous'
  };
}

bool _exact(GlossaryTerm t, String normalized) => [
      t.pl,
      t.en,
      t.de,
      t.nl,
      t.no,
      if (t.code != null) t.code!,
      if (t.iso6520 != null) t.iso6520!,
      if (t.iso4063 != null) t.iso4063!,
      for (final s in t.synonyms.values) ...s
    ].any((v) => normalizeGlossary(v) == normalized);

class GlossaryTermSkill extends AssistantSkill {
  @override
  String get id => 'glossary.term';
  @override
  String get toolId => 'glossary';
  @override
  AssistantTier get tier => AssistantTier.b;
  @override
  List<SkillExample> get examples => const [
        SkillExample('Jak jest podtopienie po niemiecku?',
            'What is undercut in German?'),
        SkillExample('Znajdź w słowniku WPS', 'Find WPS in the dictionary'),
        SkillExample('Słownik podtopienie po angielsku',
            'Dictionary undercut in English'),
        SkillExample('Słownik TIG po norwesku', 'Dictionary TIG in Norwegian'),
        SkillExample('Słownik WPS po holendersku', 'Dictionary WPS in Dutch'),
        SkillExample(
            'Znajdź hasło 5011 w słowniku', 'Find 5011 in the dictionary'),
      ];
  @override
  List<SkillRejection> get rejections => const [
        SkillRejection('otwórz słownik spawalniczy', routesTo: 'tool.open'),
        SkillRejection('dlaczego pojawia się porowatość',
            routesTo: 'defects.causes'),
        SkillRejection('zapisz TIG 100 A ścianka 2 mm'),
      ];
  @override
  SkillMatch? match(Utterance u, AssistantContext ctx) {
    if (kCommandVerbRe.hasMatch(u.folded)) return null;
    final explicit = u.hasStem(const ['slownik', 'glossary', 'dictionary']);
    if (!explicit &&
        glossaryTargets(u.folded).isEmpty &&
        !u.hasStem(const ['przetlum', 'translat']) &&
        !RegExp(r'^(?:co to|co oznacza|czym jest|what is|what are|what does|define)')
            .hasMatch(u.folded)) {
      return null;
    }
    final legacy = explicit ? null : KnowledgeSkill().match(u, ctx);
    final dictionary =
        const ['glossary', 'definition'].contains(legacy?.slots['kind']);
    if (!explicit && !dictionary) return null;
    final s = _slots(u);
    if (explicit &&
        kOpenVerbAtStartRe.hasMatch(u.folded) &&
        (s['query'] == '' || s['query'] == 'welding')) {
      return null;
    }
    s['kind'] = s.containsKey('target') ||
            u.hasStem(const ['przetlum', 'translat']) ||
            legacy?.slots['kind'] == 'glossary'
        ? 'translation'
        : 'definition';
    return SkillMatch(this, .9, slots: s, utterance: u);
  }

  @override
  Map<String, Object?> slotsFrom(Utterance u, AssistantContext ctx) =>
      _slots(u);
  @override
  Map<String, Object?>? fillSlot(
      String slot, Utterance u, AssistantContext ctx) {
    final s = _slots(u);
    if (slot == 'target') {
      final code = GlossaryLang.parse(u.folded.trim());
      if (code != null) return {'target': code.name};
      return s.containsKey('target') ? {'target': s['target']} : null;
    }
    if (slot == 'query') {
      if (kWeldingGlossary.any((t) => _exact(t, normalizeGlossary(u.raw)))) {
        return {'query': u.raw};
      }
      return {
        'query': s['query'],
        if (s.containsKey('target')) 'target': s['target']
      };
    }
    return null;
  }

  @override
  Future<SkillResult> run(SkillMatch m, AssistantContext ctx) async {
    AskResult ask(String k, String pl, String en,
            {List<FollowUp> choices = const []}) =>
        AskResult(k, AssistantText(pl, en), partial: m, choices: choices);
    final query = m.slots['query'];
    if (query is! String || query.trim().isEmpty) {
      return ask('query', 'Jakiego hasła szukasz w słowniku?',
          'Which dictionary term are you looking for?');
    }
    final target = GlossaryLang.parse(m.slots['target'] as String?);
    if (m.slots['target'] == 'ambiguous' ||
        m.slots['kind'] == 'translation' && target == null) {
      return ask(
          'target',
          'Wybierz jeden język: polski, angielski, niemiecki, niderlandzki lub norweski.',
          'Choose one language: Polish, English, German, Dutch or Norwegian.');
    }
    final hits = weldingGlossaryIndex.search(query);
    final normalized = normalizeGlossary(query);
    final exact = hits.where((t) => _exact(t, normalized)).toList();
    final candidates = exact.isNotEmpty ? exact : hits;
    if (candidates.isEmpty) {
      return const FailedResult(
          AssistantText(
              'Tego hasła nie ma w słowniku aplikacji. Nie dopisuję tłumaczenia z domysłu.',
              'This term is missing from the app dictionary. I will not invent a translation.'),
          reportMissingCapability: true);
    }
    if (candidates.length > 1) {
      return ask('query', 'Znalazłem kilka haseł. Wybierz dokładne określenie.',
          'Several entries match. Choose the exact term.',
          choices: [
            for (final t in candidates.take(6))
              FollowUp(AssistantText(t.pl, t.en),
                  ctx.lang.name == 'en' ? t.en : t.pl)
          ]);
    }
    final term = candidates.single;
    final lines = [
      for (final l in GlossaryLang.values)
        AnswerLine(AssistantText(l.namePl, l.nameEn), term.text(l))
    ];
    final translation =
        target == null ? '' : '${target.code}: ${term.text(target)}. ';
    return AnswerResult(
        AssistantAnswer(
            text: AssistantText(
                '„${term.pl}” — $translation${term.defPl ?? ''}',
                '“${term.en}” — $translation${term.defEn ?? ''}'),
            lines: lines,
            source: AssistantText(
                'Słownik spawalniczy${term.isoLabel == null ? '' : ' · ${term.isoLabel}'}',
                'Welding dictionary${term.isoLabel == null ? '' : ' · ${term.isoLabel}'}')),
        show: ShowInModule(toolId, {
          'term_id': term.id,
          if (target != null && GlossaryLang.targets.contains(target))
            'target': target.name
        }));
  }
}
