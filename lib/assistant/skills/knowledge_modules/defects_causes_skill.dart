import '../../../data/weld_defects.dart';
import '../../../domain/defects/defect_advice.dart';
import '../../../domain/glossary/glossary.dart' show normalizeGlossary;
import '../../core/skill.dart';
import '../../../i18n/app_language.dart';
import '../../core/command_words.dart';

final _defectHints = {
  for (final d in kWeldDefects)
    for (final word in normalizeGlossary(
            '${d.title.pl} ${d.title.en} ${d.keywords.join(" ")}')
        .split(' '))
      if (word.length >= 4) word.substring(0, 4)
};
final _defectCodes = {
  for (final d in kWeldDefects)
    for (final code in d.codes) '$code'
};

final _frame = RegExp(
    r'\b(?:wyjasnij|wytlumacz|explain|pokaz|otworz|show|open|dlaczego|czemu|pojawia|pojawiaja|sie|przyczyn\w*|powod\w*|jak|napraw\w*|usunac|wada|wady|spoin\w*|spawania|spawaniu|przy|dla|proces\w*|metod\w*|w|we|i|na|z|ze|mi|mam|jest|wystepuje|what|why|does|do|occur|occurs|appear|appears|cause|causes|of|how|to|fix|repair|weld|welding|defect|defects|in|with|the|a|an|and|process|during)\b');
Map<String, Object?> _slots(Utterance original) {
  var f = original.tokens
      .join(' ')
      .replaceAll(
          RegExp(r'\b\d+(?:[.,]\d+)?\s+(?:a|amps|amper\w*|mm|v)\b'), ' ')
      .replaceAll(RegExp(r'\b(?:iso\s+)?(?:6520\s+1|4063)\b'), ' ');
  final processes = <DefectProcess>{};
  for (final p in DefectProcess.values) {
    final aliases = switch (p) {
      DefectProcess.mma111 => ['mma', 'smaw', '111'],
      DefectProcess.mag135 => ['mag', '135', '138'],
      DefectProcess.fcaw136 => ['136', 'fcaw g'],
      DefectProcess.fcaw114 => ['fcaw s', '114'],
      DefectProcess.tig141 => ['tig', 'gtaw', '141'],
      DefectProcess.saw121 => ['saw', '121', 'luk kryty'],
      DefectProcess.mig131 => ['mig', '131'],
    };
    if (p == DefectProcess.fcaw136 &&
        RegExp(r'\bfcaw s\b').hasMatch(f) &&
        !RegExp(r'\b136\b').hasMatch(f)) {
      continue;
    }
    if (aliases.any((a) => RegExp('\\b$a\\b').hasMatch(f))) processes.add(p);
  }
  if (RegExp(r'\bfcaw\b').hasMatch(f) &&
      !RegExp(r'\b(?:fcaw s|fcaw g|136|114)\b').hasMatch(f)) {
    processes.addAll([DefectProcess.fcaw136, DefectProcess.fcaw114]);
  }
  final materials = <DefectMaterial>{};
  if (RegExp(r'\b(?:nierdz\w*|stainless|304l|316l)\b').hasMatch(f)) {
    materials.add(DefectMaterial.stainless);
  }
  if (RegExp(r'\b(?:weglow\w*|carbon|czarna|czarnej)\b').hasMatch(f)) {
    materials.add(DefectMaterial.carbon);
  }
  if (RegExp(r'\b(?:alumin\w*)\b').hasMatch(f)) {
    materials.add(DefectMaterial.aluminium);
  }
  final positions = <DefectPosition>{};
  for (final p in DefectPosition.values) {
    for (final code in p.code.toLowerCase().replaceAll('-', ' ').split(' / ')) {
      if (RegExp('\\b$code\\b').hasMatch(f)) positions.add(p);
    }
  }
  if (RegExp(r'\bhl045\b').hasMatch(f)) positions.add(DefectPosition.pipeUp);
  if (RegExp(r'\bjl045\b').hasMatch(f)) positions.add(DefectPosition.pipeDown);
  final unsupported = RegExp(
              r'\b(?:laser\w*|plazm\w*|plasma|titan\w*|tytan\w*|duplex|copper|miedz\w*)\b')
          .hasMatch(f) ||
      RegExp(r'\b(?:proces\w*|process)\s+(?!111\b|135\b|138\b|136\b|114\b|141\b|121\b|131\b)\d{3}\b')
          .hasMatch(f);
  f = f
      .replaceAll(RegExp(r'\b(?:proces\w*|process)\s+\d{3}\b'), ' ')
      .replaceAll(
          RegExp(
              r'\b(?:fcaw s|fcaw g|mma|smaw|mag|fcaw|tig|gtaw|saw|mig|111|135|138|136|114|141|121|131|luk kryty)\b'),
          ' ')
      .replaceAll(
          RegExp(
              r'\b(?:stal\w*|steel|nierdz\w*|stainless|304l|316l|weglow\w*|carbon|czarna|czarnej|alumin\w*)\b'),
          ' ')
      .replaceAll(
          RegExp(
              r'\b(?:pozycj\w*|position|pa|pb|pc|pd|pe|pf|pg|ph|pj|h l045|j l045|hl045|jl045)\b'),
          ' ')
      .replaceAll(
          RegExp(
              r'\b(?:laser\w*|plazm\w*|plasma|titan\w*|tytan\w*|duplex|copper|miedz\w*)\b'),
          ' ')
      .replaceAll(_frame, ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  // Inflections are only a search prefix, never a fabricated defect/diagnosis.
  f = f
      .replaceAll(RegExp(r'\bporowatosci\b'), 'porowatosc')
      .replaceAll(RegExp(r'\bpekniec\w*\b'), 'pekn')
      .replaceAll(RegExp(r'\bpodtopien\w*\b'), 'podtop')
      .replaceAll(RegExp(r'\brozprysk\w*\b'), 'rozprysk')
      .replaceAll(RegExp(r'\bcracks\b'), 'crack');
  return {
    if (f.isNotEmpty) 'query': f,
    if (processes.isNotEmpty)
      'process': processes.length == 1 ? processes.single.name : 'ambiguous',
    if (materials.isNotEmpty)
      'material': materials.length == 1 ? materials.single.name : 'ambiguous',
    if (positions.isNotEmpty)
      'position': positions.length == 1 ? positions.single.name : 'ambiguous',
    if (unsupported) 'unsupported': true,
  };
}

List<WeldDefect> _hits(String query) {
  if (normalizeGlossary(query).length < 3) return [];
  final hits = searchDefects(query);
  final q = normalizeGlossary(query);
  final exact = hits
      .where((d) => [
            d.title.pl.split('(').first,
            d.title.en.split('(').first,
            ...d.codes.map((c) => '$c')
          ].any((v) => normalizeGlossary(v) == q))
      .toList();
  return exact.isNotEmpty ? exact : hits;
}

class DefectsCausesSkill extends AssistantSkill {
  @override
  bool get answersQuestionsOnly => true;
  @override
  String get id => 'defects.causes';
  @override
  String get toolId => 'weld_defects';
  @override
  AssistantTier get tier => AssistantTier.b;
  @override
  List<SkillExample> get examples => const [
        SkillExample('Przyczyny porowatości przy MAG stal węglowa',
            'Causes of porosity in MAG carbon steel'),
        SkillExample(
            'Dlaczego pojawia się porowatość?', 'Why does porosity appear?'),
        SkillExample('Jak naprawić podtopienie TIG stal nierdzewna',
            'How to repair undercut TIG stainless steel'),
        SkillExample('Przyczyny rozprysku przy MMA stal węglowa',
            'Causes of spatter MMA carbon steel'),
        SkillExample('Dlaczego cukrowanie przy TIG stal nierdzewna',
            'Why sugaring TIG stainless steel'),
        SkillExample('Przyczyny pęknięć przy MAG', 'Causes of cracks in MAG'),
      ];
  @override
  List<SkillRejection> get rejections => const [
        SkillRejection('Jak jest podtopienie po niemiecku?',
            routesTo: 'glossary.term'),
        SkillRejection('Otwórz wady spoin', routesTo: 'tool.open'),
        SkillRejection('Ile podtopienia na poziomie B'),
        SkillRejection('zapisz TIG 2 mm 60 A'),
      ];
  @override
  SkillMatch? match(Utterance u, AssistantContext ctx) {
    if (isNegatedCommand(u) || kCommandVerbRe.hasMatch(u.folded)) {
      return null;
    }
    if (u.hasStem(const [
          'slownik',
          'dictionary',
          'glossary',
          'przetlum',
          'translat'
        ]) ||
        u.hasAny(const [
          'po niemiecku',
          'po angielsku',
          'in german',
          'in english'
        ])) {
      return null;
    }
    final intent = u.hasStem(const [
      'przyczyn',
      'dlaczego',
      'czemu',
      'napraw',
      'cause',
      'why',
      'repair',
      'fix'
    ]);
    final hasDefectHint = u.tokens.any((v) =>
        _defectCodes.contains(v) ||
        (v.length >= 4 && _defectHints.contains(v.substring(0, 4))));
    if (!intent &&
        !hasDefectHint &&
        !(u.hasStem(const ['wad', 'defect']) &&
            u.hasStem(const ['spoin', 'weld']))) {
      return null;
    }
    if (!intent &&
        !u.tokens.any(const [
          'mma',
          'smaw',
          'mag',
          'fcaw',
          'tig',
          'gtaw',
          'saw',
          'mig',
          '111',
          '135',
          '138',
          '136',
          '114',
          '141',
          '121',
          '131'
        ].contains)) {
      return null;
    }
    final s = _slots(u);
    // A defect with process/amps is a request for help, not a parameter
    // record merely because the legacy parser sees TIG and 60 A.
    if (!intent &&
        !(s.containsKey('process') &&
            _hits(s['query'] as String? ?? '').isNotEmpty)) {
      return null;
    }
    if (kOpenVerbAtStartRe.hasMatch(u.folded) &&
        _hits(s['query'] as String? ?? '').isEmpty) {
      return null;
    }
    if (_hits(s['query'] as String? ?? '').isEmpty &&
        !(u.hasStem(const ['wad', 'defect']) &&
            u.hasStem(const ['spoin', 'weld']))) {
      return null;
    }
    return SkillMatch(this, .94, slots: s, utterance: u);
  }

  // Do not silently replace defect/process based on an unrelated bare number.
  @override
  Map<String, Object?> slotsFrom(Utterance u, AssistantContext ctx) => const {};
  @override
  Map<String, Object?>? fillSlot(
      String slot, Utterance u, AssistantContext ctx) {
    final s = _slots(u);
    if (slot == 'query') return s.containsKey('query') ? s : null;
    return s.containsKey(slot) ? s : null;
  }

  AskResult _ask(SkillMatch m, String slot, String pl, String en,
          List<FollowUp> choices) =>
      AskResult(slot, AssistantText(pl, en), partial: m, choices: choices);
  @override
  Future<SkillResult> run(SkillMatch m, AssistantContext ctx) async {
    final s = m.slots;
    if (s['unsupported'] == true) {
      return const FailedResult(
          AssistantText(
              'Ta baza przyczyn nie obejmuje wskazanego procesu lub materiału.',
              'This causes database does not cover the requested process or material.'),
          reportMissingCapability: true);
    }
    final q = s['query'] as String? ?? '';
    final hits = _hits(q);
    if (hits.isEmpty) {
      if (q.isNotEmpty) {
        return const FailedResult(
            AssistantText(
                'Nie znalazłem tej wady w bazie przyczyn. Podaj nazwę lub numer ISO 6520-1.',
                'This defect is missing from the causes database. Give a name or ISO 6520-1 number.'),
            reportMissingCapability: true);
      }
      return _ask(
          m,
          'query',
          'Jaką wadę widzisz? Podaj nazwę lub numer ISO 6520-1.',
          'Which defect do you see? Give its name or ISO 6520-1 number.',
          const []);
    }
    if (hits.length > 1) {
      return _ask(m, 'query', 'Którą wadę masz na myśli?',
          'Which defect do you mean?', [
        for (final d in hits.take(8))
          FollowUp(AssistantText(d.title.pl, d.title.en),
              ctx.lang == AppLanguage.pl ? d.title.pl : d.title.en)
      ]);
    }
    final d = hits.single;
    final process =
        DefectProcess.values.where((p) => p.name == s['process']).firstOrNull;
    if (process == null) {
      return _ask(m, 'process', 'Jakim procesem spawasz?',
          'Which welding process are you using?', [
        for (final p in d.processes)
          FollowUp(AssistantText.same(p.label), p.codes.first)
      ]);
    }
    if (!d.processes.contains(process)) {
      return const FailedResult(
          AssistantText(
              'Baza nie zawiera przyczyn tej wady dla podanego procesu.',
              'The database has no causes for this defect with the requested process.'),
          reportMissingCapability: true);
    }
    final allowed = d.materialsFor(process);
    final material =
        DefectMaterial.values.where((v) => v.name == s['material']).firstOrNull;
    if (material != null && !allowed.contains(material)) {
      return const FailedResult(
          AssistantText(
              'Baza nie obejmuje tej wady dla wskazanego procesu i materiału. Nie zmieniam podanego materiału.',
              'The database does not cover this defect for the supplied process and material. The supplied material is kept.'),
          reportMissingCapability: true);
    }
    if (material == null) {
      return _ask(
          m,
          'material',
          'Jaki materiał spawasz?',
          'Which material are you welding?',
          [for (final v in allowed) FollowUp(AssistantText(v.pl, v.en), v.en)]);
    }
    final effective = material;
    if (s['position'] == 'ambiguous') {
      return _ask(m, 'position', 'Podaj jedną pozycję spawania.',
          'Give one welding position.', [
        for (final v in DefectPosition.values)
          FollowUp(AssistantText.same(v.code), v.code.split(' / ').first)
      ]);
    }
    final pos =
        DefectPosition.values.where((v) => v.name == s['position']).firstOrNull;
    final a = defectAdvice(d, process, material: effective, position: pos)!;
    final sources = <String>{
      for (final c in a.causes) ...c.sources,
      ...d.repairSources
    };
    if (a.causes.isEmpty) {
      return const FailedResult(
          AssistantText('W bazie nie ma przyczyn dla tego zestawu filtrów.',
              'No causes are available for this combination of filters.'),
          reportMissingCapability: true);
    }
    final sourceText =
        'ISO 6520-1 (${d.codesLabel}) · ${defectSourceLabel(sources.toList())}';
    return AnswerResult(
        AssistantAnswer(
          text: AssistantText(buildDefectShareText(a, en: false),
              buildDefectShareText(a, en: true)),
          spoken: AssistantText(
              '${d.title.pl}. Możliwe przyczyny i kroki sprawdzenia dla procesu ${process.label} są w odpowiedzi. Wiążące są WPS i procedura naprawy.',
              '${d.title.en}. Possible causes and checks for ${process.label} are in the answer. The WPS and repair procedure are binding.'),
          source: AssistantText.same(sourceText),
          lines: [
            if (pos == null && a.causes.any((c) => c.positions.isNotEmpty))
              AnswerLine(
                  const AssistantText(
                      'Pozycja niepodana', 'Position not supplied'),
                  ctx.lang == AppLanguage.pl
                      ? 'Wskazówki zależne od pozycji są oznaczone poniżej.'
                      : 'Position-dependent hints are identified below.'),
            for (final c in a.causes)
              if (c.positions.isNotEmpty)
                AnswerLine(
                    const AssistantText(
                        'Dotyczy pozycji', 'Applies to positions'),
                    '${c.positions.map((v) => v.code).join(", ")}: ${c.cause.of(en: ctx.lang == AppLanguage.en)}'),
            for (final key in sources)
              if (kDefectSources[key] != null)
                AnswerLine(AssistantText.same(kDefectSources[key]!.short),
                    '${kDefectSources[key]!.title} — ${kDefectSources[key]!.url}')
          ],
        ),
        show: ShowInModule('weld_defects', {
          'defect_id': d.id,
          'process': process.name,
          'material': effective.name,
          'position': pos?.name
        }));
  }
}
