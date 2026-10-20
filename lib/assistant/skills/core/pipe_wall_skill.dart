// `pipe.wall` — grubość ścianki rury z harmonogramu (moduł „Grubości
// ścianek").
//
// Liczby WYŁĄCZNIE z lib/data/pipe_schedules.dart (ASME B36.10M dla stali
// węglowej, B36.19M dla nierdzewnej — harmonogramy „S"). DN z wypowiedzi
// albo z kontekstu („a ścianka?" po DN40). Bez harmonogramu → lista ścianek
// danego DN (nie zgadujemy, który); harmonogram spoza tabeli → pytanie.

import '../../../data/pipe_schedules.dart';
import '../../../domain/fitter/pipe_size_lookup.dart';
import '../../../i18n/app_language.dart';
import '../../core/skill.dart';
import 'explain_tool_skill.dart' show explainedTool;
import 'pipe_od_skill.dart' show parseSchedule;
import 'skill_words.dart';

const Set<String> _vocabulary = {
  ...kNeutralWords,
  'rura', 'rury', 'rure', 'rurki', 'rurka', 'pipe', 'pipes', 'tube', 'dn',
  'nps', 'cal', 'cala', 'cale', 'cali', 'inch', 'inches', 'wall', 'walls',
  'thickness', 'sch', 'schedule', 'std', 'standard', 'xs', 'xxs', 'mm',
  'dee', 'jakich', 'harmonogram',
};

/// Kolejność harmonogramów na liście (węglowe B36.10M, potem nierdzewne
/// B36.19M).
const List<String> _order = [
  'STD', '40', '80', '160', 'XS', 'XXS', '5S', '10S', '40S', '80S',
];

bool _stainless(String schedule) => schedule.endsWith('S') && schedule != 'XXS' &&
    schedule != 'XS';

String _schLabel(String s) => 'Sch $s';

AssistantText _source(String schedule) => _stainless(schedule)
    ? const AssistantText.same('ASME B36.19M')
    : const AssistantText.same('ASME B36.10M');

String _odDescription(PipeRow row, AppLanguage lang) {
  final reference = odForDn(row.dn);
  final od = fmt(row.od, lang);
  final differs = reference != null && (reference - row.od).abs() > 0.001;
  if (lang == AppLanguage.en) {
    return 'OD $od mm per ASME${differs ? '; DN ↔ mm table: ${fmt(reference, lang)} mm' : ''}';
  }
  return 'OD $od mm wg ASME${differs ? '; w tabeli DN ↔ mm: ${fmt(reference, lang)} mm' : ''}';
}

class PipeWallSkill extends AssistantSkill {
  @override
  String get id => 'pipe.wall';
  @override
  String? get toolId => 'wall_thickness';
  @override
  AssistantTier get tier => AssistantTier.b;

  @override
  List<SkillExample> get examples => const [
        SkillExample('Jaka ścianka DN40 Sch 40?',
            'What is the wall of DN40 schedule 40?'),
        SkillExample('ścianka dn50 sch 80', 'wall thickness DN50 sch 80'),
        SkillExample('grubość ścianki rury 2 cale schedule 40',
            'wall thickness of a 2 inch pipe sch 40'),
        SkillExample('DN100 sch 10S ile ścianki', 'DN100 10S wall'),
        SkillExample('ścianka DN 25 STD', 'DN25 STD wall thickness'),
        SkillExample('jakie ścianki ma DN80', 'what walls does DN80 have'),
      ];

  @override
  List<SkillRejection> get rejections => const [
        SkillRejection('jaka jest średnica rury dn40', routesTo: 'pipe.od'),
        SkillRejection('zapisz TIG nierdzewka ścianka 2 mm 60 A bez drutu',
            routesTo: 'legacy.save'),
        SkillRejection('dodaj rurę 2 metry',
            alsoNot: ['legacy.save', 'legacy.journal']),
        SkillRejection('ile waży rura dn50 sch 40'),
        SkillRejection('jaka grubość ścianki na TIG 60 amper'),
        SkillRejection('otwórz grubości ścianek', routesTo: 'tool.open'),
        SkillRejection('do czego służą grubości ścianek',
            routesTo: 'tool.explain'),
        SkillRejection('what is the OD of DN40',
            routesTo: 'pipe.od', lang: AppLanguage.en),
      ];

  (int?, double?) _size(Utterance u) {
    final dn = u.dn();
    if (dn != null) return (dn, null);
    return (null, u.npsInches());
  }

  /// „ścianka 2 mm" — podana wartość ścianki (zdanie o parametrze spawania),
  /// a nie pytanie o tabelę.
  bool _givesWallValue(Utterance u) {
    final items = u.items;
    for (var i = 0; i + 1 < items.length; i++) {
      if (!items[i].isNumber) continue;
      final unit = items[i + 1];
      if (!unit.isNumber && (unit.word == 'mm' || unit.word.startsWith('milimetr'))) {
        return true;
      }
    }
    return false;
  }

  @override
  SkillMatch? match(Utterance u, AssistantContext ctx) {
    if (kCommandVerbRe.hasMatch(u.folded)) return null;
    if (mentionsWeight(u)) return null;
    final wallWord = mentionsWall(u);
    final schedule = parseSchedule(u);
    if (!wallWord && schedule == null) return null;
    if (_givesWallValue(u)) return null;
    final (dn, nps) = _size(u);
    final hasSize = dn != null || nps != null;
    if (!hasSize && (mentionsWelding(u) || mentionsOtherObject(u))) {
      // „jaka grubość blachy / spoiny", „ścianka na TIG 60 A" — to nie tabela
      // rur.
      return null;
    }
    // Liczby bez DN, cali i harmonogramu („ścianka dwa sześćdziesiąt") to
    // podana wartość, nie pytanie o tabelę.
    if (!hasSize && !u.mentionsDn && _bareNumbers(u)) return null;
    final openVerb = kOpenVerbAtStartRe.hasMatch(u.folded);

    final slots = <String, Object?>{if (schedule != null) 'schedule': schedule};
    double score;
    if (hasSize) {
      slots['dn'] = dn;
      slots['nps'] = nps;
      score = 0.9;
    } else {
      if (openVerb) return null; // „otwórz grubości ścianek" → otwarcie
      // „do czego służy grubość ścianek" → opis modułu, nie tabela.
      if (explainedTool(u) != null) return null;
      final ctxDn = ctx.recentSlot('dn');
      if (u.dnValues.length > 1) slots['dns'] = u.dnValues;
      // DN z kontekstu tylko dla krótkiej kontynuacji („a ścianka?", „a sch
      // 80?"). Gdy rozmiar padł, ale jest niejasny („ścianka dn 4 0 sch 80"),
      // NIE podstawiamy poprzedniego DN — pytamy.
      if (ctxDn is int && !u.mentionsDn && _inheritsContext(u)) {
        slots['dn'] = ctxDn;
        score = 0.85;
      } else {
        score = 0.6;
      }
    }
    score -= 0.08 * unknownWords(u, _vocabulary, stems: _wallStems);
    if (score <= 0) return null;
    return SkillMatch(this, score,
        slots: slots,
        missing: [if (slots['dn'] == null && slots['nps'] == null) 'dn'],
        utterance: u);
  }

  static const _wallStems = ['sciank', 'grubos', 'schedul', 'szedul', 'szedzul'];

  bool _isScheduleWord(String w) =>
      w == 'sch' || w.startsWith('schedul') || w.startsWith('szedul') ||
      w.startsWith('szedzul') || w.startsWith('skedul');

  /// Liczby, które nie są numerem harmonogramu („sch 80" → 80 jest).
  bool _bareNumbers(Utterance u) {
    final items = u.items;
    for (var i = 0; i < items.length; i++) {
      if (!items[i].isNumber) continue;
      final prev = i > 0 ? items[i - 1] : null;
      if (prev != null && !prev.isNumber && _isScheduleWord(prev.word)) continue;
      return true;
    }
    return false;
  }

  /// Kontynuacja tylko ze słownika umiejętności, bez obcych przedmiotów.
  bool _inheritsContext(Utterance u) =>
      !mentionsOtherObject(u) &&
      !_bareNumbers(u) &&
      unknownWords(u, _vocabulary, stems: _wallStems) == 0;

  /// Słowa średnicy — „a średnica dla DN50" po ściance to pytanie o OD.
  bool _odWord(Utterance u) =>
      u.hasStem(const ['srednic', 'zewnetrz', 'diamet']) ||
      u.hasAny(const ['od', 'outside']);

  @override
  Map<String, Object?> slotsFrom(Utterance u, AssistantContext ctx) {
    // Kontynuacja nie może przejąć polecenia innego modułu ani pytania
    // o średnicę.
    if (looksLikeOtherCommand(u) ||
        mentionsOtherObject(u) ||
        _odWord(u) ||
        u.dnValues.length > 1) {
      return const {};
    }
    final out = <String, Object?>{};
    final (dn, nps) = _size(u);
    if (dn != null) {
      out['dn'] = dn;
      out['nps'] = null;
    } else if (nps != null) {
      out['nps'] = nps;
      out['dn'] = null;
    }
    final schedule = parseSchedule(u);
    if (schedule != null) out['schedule'] = schedule;
    return out;
  }

  @override
  Map<String, Object?>? fillSlot(
      String slot, Utterance u, AssistantContext ctx) {
    final s = slotsFrom(u, ctx);
    if (s.isEmpty && (looksLikeOtherCommand(u) || _odWord(u))) return null;
    if (slot == 'dn' && !s.containsKey('dn')) {
      // Sama liczba („50") w odpowiedzi na „Dla jakiego DN?" — bez
      // jednostki i bez obcych słów.
      final items = u.items;
      final idx = [
        for (var i = 0; i < items.length; i++)
          if (items[i].isNumber) i,
      ];
      if (idx.length != 1) return null;
      final it = items[idx.single];
      if (it.fraction) return null;
      final after = idx.single + 1 < items.length ? items[idx.single + 1] : null;
      if (after != null && !kNeutralWords.contains(after.word)) return null;
      if (unknownWords(u, _vocabulary, stems: _wallStems) > 0) return null;
      final v = it.value!;
      if (v != v.roundToDouble() || v <= 0) return null;
      return {...s, 'dn': v.toInt(), 'nps': null};
    }
    return s.containsKey(slot) ? s : null;
  }

  @override
  Future<SkillResult> run(SkillMatch m, AssistantContext ctx) async {
    var dn = m.slots['dn'] as int?;
    final nps = (m.slots['nps'] as num?)?.toDouble();
    if (dn == null && nps != null) dn = dnForNps(nps);
    if (dn == null) {
      return AskResult(
        'dn',
        const AssistantText('Dla jakiego DN? Powiedz np. „DN 50”.',
            'For which DN? Say e.g. "DN 50".'),
        partial: m,
        choices: [
          for (final d in const [25, 50, 100])
            FollowUp(AssistantText.same('DN$d'), 'DN$d'),
        ],
      );
    }
    final row = pipeRowForDn(dn);
    if (row == null) return _askNearest(dn, m);
    final schedule = m.slots['schedule'] as String?;
    if (schedule == null) return _list(row, ctx.lang);
    if (!row.walls.containsKey(schedule)) return _askSchedule(row, schedule, m);
    final wall = row.walls[schedule];
    if (wall == null) {
      return AnswerResult(
        AssistantAnswer(
          text: AssistantText(
              'DN$dn ${_schLabel(schedule)} — w tym rozmiarze się nie produkuje '
                  '(${_source(schedule).pl}).',
              'DN$dn ${_schLabel(schedule)} — not made in this size '
                  '(${_source(schedule).en}).'),
          lines: _lines(row, ctx.lang),
          source: _source(schedule),
        ),
        show: ShowInModule('wall_thickness', {'dn': dn}),
      );
    }
    return _single(row, schedule, wall, ctx.lang);
  }

  SkillResult _single(PipeRow row, String schedule, double wall, AppLanguage lang) {
    final dn = row.dn;
    final id = insideDiameterMm(row, schedule)!;
    final stainless = _stainless(schedule);
    final mass = massPerMeter(row, schedule, stainless: stainless);
    final src = _source(schedule);
    String t(AppLanguage l) {
      final w = fmt(wall, l), inner = fmt(id, l);
      final od = _odDescription(row, l);
      return l == AppLanguage.en
          ? 'DN$dn ${_schLabel(schedule)} — wall $w mm (${src.en}). '
              '$od, inside diameter $inner mm.'
          : 'DN$dn ${_schLabel(schedule)} — ścianka $w mm (${src.pl}). '
              '$od, średnica wewnętrzna $inner mm.';
    }

    final spoken = AssistantText(
      'DN $dn, schedule $schedule: ścianka ${fmt(wall, AppLanguage.pl)} '
          '${plMillimetres(wall)}.',
      'DN $dn, schedule $schedule: wall ${fmt(wall, AppLanguage.en)} '
          '${enMillimetres(wall)}.',
    );
    final en = lang == AppLanguage.en;
    final other = schedule == '40' ? '80' : '40';
    final all = knownDns;
    final i = all.indexOf(dn);
    final nextDn = [
      for (final d in all.skip(i + 1))
        if (pipeRowForDn(d) != null) d,
    ].firstOrNull;
    return AnswerResult(
      AssistantAnswer(
        text: AssistantText(t(AppLanguage.pl), t(AppLanguage.en)),
        spoken: spoken,
        source: src,
        lines: [
          AnswerLine(const AssistantText('Ścianka', 'Wall'), '${fmt(wall, lang)} mm'),
          AnswerLine(const AssistantText.same('OD'), '${fmt(row.od, lang)} mm'),
          AnswerLine(const AssistantText('Średnica wewnętrzna', 'Inside diameter'),
              '${fmt(id, lang)} mm'),
          if (mass != null)
            AnswerLine(
                stainless
                    ? const AssistantText(
                        'Masa (nierdzewna)', 'Mass (stainless)')
                    : const AssistantText(
                        'Masa (stal węglowa)', 'Mass (carbon steel)'),
                '${fmt(mass, lang)} kg/m'),
        ],
      ),
      show: ShowInModule('wall_thickness', {'dn': dn, 'schedule': schedule}),
      followUps: [
        FollowUp(AssistantText('A Sch $other?', 'And Sch $other?'),
            en ? 'and sch $other?' : 'a sch $other?'),
        if (nextDn != null)
          FollowUp(AssistantText('A DN$nextDn?', 'And DN$nextDn?'),
              en ? 'and DN$nextDn?' : 'a DN$nextDn?'),
        FollowUp(const AssistantText('A średnica?', 'And the OD?'),
            en ? 'and the diameter?' : 'a średnica?'),
      ],
    );
  }

  List<AnswerLine> _lines(PipeRow row, AppLanguage lang) => [
        for (final s in _order)
          if (row.walls[s] case final w?)
            AnswerLine(AssistantText.same(_schLabel(s)), '${fmt(w, lang)} mm'),
      ];

  SkillResult _list(PipeRow row, AppLanguage lang) {
    final dn = row.dn;
    final main = [
      for (final s in const ['10S', '40', '80'])
        if (row.walls[s] case final w?) (s, w),
    ];
    String t(AppLanguage l) {
      final list =
          main.map((e) => '${_schLabel(e.$1)} ${fmt(e.$2, l)} mm').join(', ');
      return l == AppLanguage.en
          ? 'DN$dn (${_odDescription(row, l)}) — walls per ASME B36.10M / '
              'B36.19M: $list. Say a schedule, e.g. "sch 80", or see the table.'
          : 'DN$dn (${_odDescription(row, l)}) — ścianki wg ASME B36.10M / '
              'B36.19M: $list. Powiedz harmonogram, np. „sch 80”, albo zobacz '
              'tabelę.';
    }

    String spoken(AppLanguage l) {
      final parts = main.map((e) => l == AppLanguage.en
          ? 'schedule ${e.$1}: ${fmt(e.$2, l)}'
          : 'schedule ${e.$1}: ${fmt(e.$2, l)}');
      return l == AppLanguage.en
          ? 'DN $dn — ${parts.join(', ')} millimetres. The rest is on screen.'
          : 'DN $dn — ${parts.join(', ')} milimetra. Reszta na ekranie.';
    }

    final en = lang == AppLanguage.en;
    return AnswerResult(
      AssistantAnswer(
        text: AssistantText(t(AppLanguage.pl), t(AppLanguage.en)),
        spoken: AssistantText(spoken(AppLanguage.pl), spoken(AppLanguage.en)),
        lines: _lines(row, lang),
        source: const AssistantText.same('ASME B36.10M / B36.19M'),
      ),
      show: ShowInModule('wall_thickness', {'dn': dn}),
      followUps: [
        for (final s in const ['40', '80', '10S'])
          if (row.walls[s] != null)
            FollowUp(AssistantText('A Sch $s?', 'And Sch $s?'),
                en ? 'and sch $s?' : 'a sch $s?'),
      ],
    );
  }

  SkillResult _askSchedule(PipeRow row, String schedule, SkillMatch m) {
    // „sch 10" → najbliższe z tabeli: 10S; zawsze też 40 i 80.
    final picks = <String>[
      if (row.walls.containsKey('${schedule}S')) '${schedule}S',
      for (final s in const ['40', '80'])
        if (s != schedule && row.walls[s] != null) s,
    ];
    final orPl = picks.map(_schLabel).join(', ');
    return AskResult(
      'schedule',
      AssistantText(
          'Nie mam ${_schLabel(schedule)} w tabeli dla DN${row.dn}. '
              'Który: $orPl?',
          '${_schLabel(schedule)} is not in the table for DN${row.dn}. '
              'Which one: $orPl?'),
      partial: m,
      choices: [
        for (final s in picks)
          FollowUp(AssistantText.same(_schLabel(s)), 'sch $s'),
      ],
    );
  }

  SkillResult _askNearest(int dn, SkillMatch m) {
    final all = [for (final r in kPipeWalls) r.dn];
    final lower = [for (final d in all) if (d < dn) d];
    final higher = [for (final d in all) if (d > dn) d];
    final near = [
      if (lower.isNotEmpty) lower.last,
      if (higher.isNotEmpty) higher.first,
    ];
    return AskResult(
      'dn',
      AssistantText(
          'Nie mam DN$dn w tabeli ścianek. Chodzi o '
              '${near.map((d) => 'DN$d').join(' czy ')}?',
          'DN$dn is not in the wall table. Do you mean '
              '${near.map((d) => 'DN$d').join(' or ')}?'),
      partial: m,
      choices: [
        for (final d in near) FollowUp(AssistantText.same('DN$d'), 'DN$d'),
      ],
    );
  }
}
