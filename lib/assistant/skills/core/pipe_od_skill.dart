// `pipe.od` — średnica zewnętrzna rury z DN albo NPS (moduł „DN ↔ mm").
//
// Liczby i normy WYŁĄCZNIE z lib/domain/fitter/pipe_size_lookup.dart (ta sama
// tabela co ekran). DN bez kontekstu → wartość serii głównej i pozostałe
// serie (spec §3.2). Brak DN, „dn 4 0", dwa różne DN, DN spoza tabeli →
// pytanie. Gdy tabela ścianek (ASME) ma inną OD — podajemy obie, opisane.

import '../../../data/nps_dn_od_r.dart';
import '../../../data/pipe_schedules.dart' show pipeRowForDn;
import '../../../domain/fitter/pipe_size_lookup.dart';
import '../../../i18n/app_language.dart';
import '../../core/skill.dart';
import 'explain_tool_skill.dart' show explainedTool;
import 'skill_words.dart';

const _odStems = ['srednic', 'zewnetrz', 'diamet'];
const _odWords = ['od', 'outside', 'outer', 'fi', 'mm', 'milimetr', 'milimetrow',
  'millimetres', 'millimeters', 'rozmiar', 'size', 'ile ma', 'ile mm', 'in mm', 'w mm'];

const Set<String> _vocabulary = {
  ...kNeutralWords,
  'rura', 'rury', 'rure', 'rurki', 'rurka', 'rurze', 'pipe', 'pipes', 'tube',
  'tubes', 'dn', 'nps', 'cal', 'cala', 'cale', 'cali', 'inch', 'inches',
  'zewnetrzna', 'zewnetrznej', 'outside', 'outer', 'diameter', 'size',
  'rozmiar', 'rozmiaru', 'nominal', 'nominalna', 'nominalnej', 'mm',
  'srednica', 'srednicy', 'srednice', 'dee',
};

/// Seria → etykieta w zdaniu („W szeregu EN 3: …").
AssistantText _seriesPhrase(OdSeries s) => switch (s) {
      OdSeries.asmeAndEn1 => const AssistantText(
          'ASME / EN seria 1', 'ASME / EN series 1'),
      OdSeries.asme => const AssistantText.same('ASME B36.10M'),
      OdSeries.en1 => const AssistantText('W szeregu EN 1', 'EN series 1'),
      OdSeries.en2 => const AssistantText('W szeregu EN 2', 'EN series 2'),
      OdSeries.en3 => const AssistantText('W szeregu EN 3', 'EN series 3'),
      OdSeries.other => const AssistantText('Inne spotykane', 'Other sizes in use'),
    };

/// Seria → etykieta wiersza karty.
AssistantText _seriesLine(OdSeries s) => switch (s) {
      OdSeries.asmeAndEn1 => const AssistantText(
          'ASME / EN seria 1', 'ASME / EN series 1'),
      OdSeries.asme => const AssistantText.same('ASME B36.10M'),
      OdSeries.en1 => const AssistantText('Szereg EN 1', 'EN series 1'),
      OdSeries.en2 => const AssistantText('Szereg EN 2', 'EN series 2'),
      OdSeries.en3 => const AssistantText('Szereg EN 3', 'EN series 3'),
      OdSeries.other => const AssistantText(
          'Inne (sprawdź kartę wyrobu)', 'Other (check the datasheet)'),
    };

/// Norma serii głównej (źródło liczby).
AssistantText _mainSource(OdSeries s) => switch (s) {
      OdSeries.asmeAndEn1 => const AssistantText(kDnOdSourcePl, kDnOdSourceEn),
      OdSeries.asme => const AssistantText.same('ASME B36.10M'),
      OdSeries.en1 => const AssistantText(
          'EN 10220 / ISO 4200 seria 1', 'EN 10220 / ISO 4200 series 1'),
      OdSeries.en2 => const AssistantText('EN 10220 seria 2', 'EN 10220 series 2'),
      OdSeries.en3 => const AssistantText('EN 10220 seria 3', 'EN 10220 series 3'),
      OdSeries.other => const AssistantText(
          'poza normą — sprawdź kartę wyrobu', 'non-standard — check the datasheet'),
    };

class PipeOdSkill extends AssistantSkill {
  @override
  String get id => 'pipe.od';
  @override
  String? get toolId => 'dn_mm';
  @override
  AssistantTier get tier => AssistantTier.b;

  @override
  List<SkillExample> get examples => const [
        SkillExample('Jaka jest średnica rury DN40?', 'What is the OD of DN40?'),
        SkillExample('Średnica zewnętrzna DN 40', 'Outside diameter DN 40'),
        SkillExample('Ile ma de en czterdzieści?', 'How many mm is DN forty?'),
        SkillExample('DN40 ile mm', 'DN40 in mm'),
        SkillExample('Średnica 2 cale', 'Diameter of a 2 inch pipe'),
        SkillExample('Jaka średnica rury półtora cala?',
            'What is the OD of a 1 1/2" pipe?'),
      ];

  @override
  List<SkillRejection> get rejections => const [
        SkillRejection('ścianka dn40 sch40', routesTo: 'pipe.wall'),
        SkillRejection('otwórz tabelę dn', routesTo: 'tool.open'),
        SkillRejection('dodaj zawór kulowy dn50',
            alsoNot: ['legacy.save', 'legacy.journal']),
        SkillRejection('ile waży rura dn50'),
        SkillRejection('narysuj rurę dn50'),
        SkillRejection('do czego służy DN ↔ mm', routesTo: 'tool.explain'),
        SkillRejection('wall thickness DN40 schedule 80',
            routesTo: 'pipe.wall', lang: AppLanguage.en),
      ];

  bool _odWord(Utterance u) => u.hasStem(_odStems) || u.hasAny(_odWords);

  /// Rozmiar z wypowiedzi: (dn, nps) — co najwyżej jedno niepuste.
  (int?, double?) _size(Utterance u) {
    final dn = u.dn();
    if (dn != null) return (dn, null);
    final nps = u.npsInches();
    return (null, nps);
  }

  @override
  SkillMatch? match(Utterance u, AssistantContext ctx) {
    if (kCommandVerbRe.hasMatch(u.folded)) return null;
    if (mentionsWall(u) || mentionsWeight(u) || hasScheduleToken(u)) {
      return null;
    }
    final odWord = _odWord(u);
    if (mentionsFitting(u) && !odWord) return null;
    final (dn, nps) = _size(u);
    final hasSize = dn != null || nps != null;
    final openVerb = kOpenVerbAtStartRe.hasMatch(u.folded);

    double score;
    final slots = <String, Object?>{};
    if (hasSize) {
      slots['dn'] = dn;
      slots['nps'] = nps;
      score = openVerb ? 0.75 : (odWord ? 0.9 : 0.7);
    } else if (u.mentionsDn) {
      if (openVerb) return null; // „otwórz tabelę dn" → otwarcie modułu
      // „do czego służy DN ↔ mm" → opis modułu.
      if (explainedTool(u) != null) return null;
      // „średnica dn50 i dn80" → zapytamy, o który.
      if (u.dnValues.length > 1) slots['dns'] = u.dnValues;
      score = odWord ? 0.65 : 0.6;
    } else if (odWord && u.hasStem(const ['srednic', 'diamet'])) {
      // „a średnica?" po ściance — DN z kontekstu. Tylko krótka
      // kontynuacja ze słownika umiejętności: „jaka średnica drutu 1,2?"
      // to nie pytanie o ostatnią rurę.
      if (openVerb || !_inheritsContext(u)) return null;
      final ctxDn = ctx.recentSlot('dn');
      if (ctxDn is! int) return null;
      slots['dn'] = ctxDn;
      score = 0.85;
    } else {
      return null;
    }
    final unknown =
        unknownWords(u, _vocabulary, stems: const ['srednic', 'zewnetrz']);
    score -= 0.08 * unknown;
    if (score <= 0) return null;
    return SkillMatch(this, score,
        slots: slots,
        missing: [if (slots['dn'] == null && slots['nps'] == null) 'dn'],
        utterance: u);
  }

  /// Rozmiar z kontekstu wolno wziąć tylko dla krótkiej kontynuacji
  /// złożonej ze słownika umiejętności („a średnica?"), bez liczb i bez
  /// innych przedmiotów (drut, blacha, spoina).
  bool _inheritsContext(Utterance u) =>
      !mentionsOtherObject(u) &&
      !u.items.any((i) => i.isNumber) &&
      unknownWords(u, _vocabulary, stems: const ['srednic', 'zewnetrz']) == 0;

  /// Wypowiedź to inny temat niż średnica rury — nie może być ani
  /// kontynuacją, ani odpowiedzią na „Jakie DN?".
  bool _foreign(Utterance u) =>
      looksLikeOtherCommand(u) ||
      mentionsWall(u) ||
      hasScheduleToken(u) ||
      mentionsOtherObject(u);

  @override
  Map<String, Object?> slotsFrom(Utterance u, AssistantContext ctx) {
    // Kontynuacja nie może przejąć polecenia innego modułu („dodaj zawór
    // kulowy dn50" kilka sekund po DN40 to nie pytanie o średnicę, „a
    // ścianka dla DN50" — też nie).
    if (kCommandVerbRe.hasMatch(u.folded) ||
        mentionsWeight(u) ||
        mentionsWall(u) ||
        hasScheduleToken(u) ||
        mentionsOtherObject(u) ||
        (mentionsFitting(u) && !_odWord(u)) ||
        u.dnValues.length > 1) {
      return const {};
    }
    final (dn, nps) = _size(u);
    if (dn != null) return {'dn': dn, 'nps': null};
    if (nps != null) return {'nps': nps, 'dn': null};
    return const {};
  }

  @override
  Map<String, Object?>? fillSlot(
      String slot, Utterance u, AssistantContext ctx) {
    if (slot != 'dn' || _foreign(u)) return null;
    final s = slotsFrom(u, ctx);
    if (s.isNotEmpty) return s;
    // Sama liczba („40", „czterdzieści proszę") w odpowiedzi na „Jakie DN?"
    // — bez jednostki („60 A", „50 mm" to nie DN) i bez obcych słów.
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
    if (unknownWords(u, _vocabulary) > 0) return null;
    final v = it.value!;
    if (v != v.roundToDouble() || v <= 0) return null;
    return {'dn': v.toInt(), 'nps': null};
  }

  @override
  Future<SkillResult> run(SkillMatch m, AssistantContext ctx) async {
    var dn = m.slots['dn'] as int?;
    final nps = (m.slots['nps'] as num?)?.toDouble();
    if (dn == null && nps != null) {
      dn = dnForNps(nps);
      if (dn == null) {
        final pl = fmt(nps, AppLanguage.pl), en = fmt(nps, AppLanguage.en);
        return AskResult(
          'dn',
          AssistantText('Nie mam rozmiaru $pl" w tabeli. Podaj DN, np. „DN 40”.',
              'Size $en" is not in the table. Give the DN, e.g. "DN 40".'),
          partial: m,
        );
      }
    }
    final dns = (m.slots['dns'] as List?)?.cast<int>();
    if (dn == null && dns != null && dns.length > 1) {
      // „średnica dn50 i dn80" — odpowiadamy dla jednego, nie zgadujemy.
      final names = dns.map((d) => 'DN$d');
      return AskResult(
        'dn',
        AssistantText('Dla którego rozmiaru: ${names.join(' czy ')}?',
            'Which size: ${names.join(' or ')}?'),
        partial: m,
        choices: [for (final d in dns) _dnChoice(d, ctx)],
      );
    }
    if (dn == null) {
      // „dn 4 0" — liczby padły, ale rozmiar jest dwuznaczny.
      final unsure = m.utterance?.items.any((i) => i.isNumber) ?? false;
      return AskResult(
        'dn',
        unsure
            ? const AssistantText(
                'Nie jestem pewien rozmiaru. Powiedz DN jeszcze raz, np. '
                    '„DN czterdzieści”.',
                'I am not sure about the size. Say the DN again, e.g. '
                    '"DN forty".')
            : const AssistantText('Jakie DN? Powiedz np. „DN czterdzieści”.',
                'Which DN? Say e.g. "DN forty".'),
        partial: m,
        choices: [for (final d in const [25, 50, 100]) _dnChoice(d, ctx)],
      );
    }
    final series = odSeriesForDn(dn);
    if (series.isEmpty) return _askNearest(dn, m, ctx);
    return _answer(dn, series, askedNps: nps, lang: ctx.lang);
  }

  FollowUp _dnChoice(int dn, AssistantContext ctx) =>
      FollowUp(AssistantText.same('DN$dn'), 'DN$dn');

  SkillResult _askNearest(int dn, SkillMatch m, AssistantContext ctx) {
    final all = knownDns;
    final lower = [for (final d in all) if (d < dn) d];
    final higher = [for (final d in all) if (d > dn) d];
    final near = [
      if (lower.isNotEmpty) lower.last,
      if (higher.isNotEmpty) higher.first,
    ];
    final orPl = near.map((d) => 'DN$d').join(' czy ');
    final orEn = near.map((d) => 'DN$d').join(' or ');
    return AskResult(
      'dn',
      AssistantText('Nie mam DN$dn w tabeli. Chodzi o $orPl?',
          'DN$dn is not in the table. Do you mean $orEn?'),
      partial: m,
      choices: [for (final d in near) _dnChoice(d, ctx)],
    );
  }

  SkillResult _answer(int dn, List<OdOption> series,
      {double? askedNps, required AppLanguage lang}) {
    final main = series.first;
    final npsLabel = npsForDn(dn);
    final headPl = askedNps != null && npsLabel != null
        ? '$npsLabel (DN$dn)'
        : 'DN$dn';
    final src = _mainSource(main.series);

    String sentences(AppLanguage l) {
      final groups = <OdSeries, List<double>>{};
      for (final o in series.skip(1)) {
        (groups[o.series] ??= []).add(o.odMm);
      }
      final and = l == AppLanguage.en ? ' and ' : ' i ';
      return [
        for (final e in groups.entries)
          ' ${_seriesPhrase(e.key).of(l)}: '
              '${e.value.map((v) => fmt(v, l)).join(and)} mm'
              '${e.key == OdSeries.other ? (l == AppLanguage.en ? ' (check the datasheet)' : ' (sprawdź kartę wyrobu)') : ''}.',
      ].join();
    }

    // Tabela ścianek (ASME B36.10M / B36.19M) ma dla kilku DN inną OD niż
    // tabela „DN ↔ mm" (np. DN300 323,8 vs 323,9; DN600 610 vs 609,6). Obie
    // pochodzą z danych aplikacji — podajemy obie, opisane, nigdy jedną
    // po cichu w jednej odpowiedzi, a drugą w drugiej.
    final wallOd = wallTableOdIfDifferent(dn);
    String wallNote(AppLanguage l) => wallOd == null
        ? ''
        : l == AppLanguage.en
            ? ' The wall table (ASME B36.10M / B36.19M) gives OD '
                '${fmt(wallOd, l)} mm.'
            : ' Tabela ścianek (ASME B36.10M / B36.19M) podaje OD '
                '${fmt(wallOd, l)} mm.';

    final odPl = fmt(main.odMm, AppLanguage.pl);
    final odEn = fmt(main.odMm, AppLanguage.en);
    final text = AssistantText(
      '$headPl — średnica zewnętrzna $odPl mm (${src.pl}).'
          '${sentences(AppLanguage.pl)}${wallNote(AppLanguage.pl)}',
      '$headPl — outside diameter $odEn mm (${src.en}).'
          '${sentences(AppLanguage.en)}${wallNote(AppLanguage.en)}',
    );

    String spokenOthers(AppLanguage l) => [
          for (final o in series.skip(1))
            if (o.series != OdSeries.other)
              ' ${_seriesPhrase(o.series).of(l)}: ${fmt(o.odMm, l)} '
                  '${l == AppLanguage.en ? enMillimetres(o.odMm) : plMillimetres(o.odMm)}.',
        ].join();
    final spoken = AssistantText(
      'DN $dn: $odPl ${plMillimetres(main.odMm)} średnicy zewnętrznej.'
          '${spokenOthers(AppLanguage.pl)}',
      'DN $dn: $odEn ${enMillimetres(main.odMm)} outside diameter.'
          '${spokenOthers(AppLanguage.en)}',
    );

    final lines = <AnswerLine>[
      AnswerLine(const AssistantText('Średnica zewnętrzna', 'Outside diameter'),
          '${fmt(main.odMm, lang)} mm'),
      if (npsLabel != null) AnswerLine(const AssistantText.same('NPS'), npsLabel),
      for (final o in series.skip(1))
        AnswerLine(_seriesLine(o.series), '${fmt(o.odMm, lang)} mm'),
      if (wallOd != null)
        AnswerLine(
            const AssistantText('OD w tabeli ścianek (ASME)',
                'OD in the wall table (ASME)'),
            '${fmt(wallOd, lang)} mm'),
    ];

    final all = knownDns;
    final i = all.indexOf(dn);
    final nextDn = i >= 0 && i + 1 < all.length ? all[i + 1] : null;
    final en = lang == AppLanguage.en;
    return AnswerResult(
      AssistantAnswer(text: text, spoken: spoken, lines: lines, source: src),
      show: ShowInModule('dn_mm', {'dn': dn}),
      followUps: [
        FollowUp(const AssistantText('A ścianka?', 'And the wall?'),
            en ? 'and the wall?' : 'a ścianka?'),
        if (nextDn != null)
          FollowUp(AssistantText('A DN$nextDn?', 'And DN$nextDn?'),
              en ? 'and DN$nextDn?' : 'a DN$nextDn?'),
      ],
    );
  }
}

/// Różnica OD między tabelą ścianek a „DN ↔ mm", od której obie wartości
/// są podawane jawnie.
const double kOdMismatchMm = 0.05;

/// OD z tabeli ścianek (`kPipeWalls`, ASME B36.10M/B36.19M), gdy różni się
/// od serii głównej „DN ↔ mm" (`odForDn`) o więcej niż [kOdMismatchMm];
/// inaczej null.
double? wallTableOdIfDifferent(int dn) {
  final row = pipeRowForDn(dn);
  final main = odForDn(dn);
  if (row == null || main == null) return null;
  return (row.od - main).abs() > kOdMismatchMm ? row.od : null;
}

/// OD z tabeli „DN ↔ mm", gdy różni się od OD tabeli ścianek o więcej niż
/// [kOdMismatchMm]; inaczej null.
double? dnTableOdIfDifferent(int dn) {
  final row = pipeRowForDn(dn);
  final main = odForDn(dn);
  if (row == null || main == null) return null;
  return (row.od - main).abs() > kOdMismatchMm ? main : null;
}

/// Token harmonogramu („sch40", „10s", „std", „xs") — wspólny z `pipe.wall`.
bool hasScheduleToken(Utterance u) => parseSchedule(u) != null;

final _schGlued = RegExp(r'^sch(\d+)(s?)$');
final _sSuffix = RegExp(r'^(\d+)s$');

const _schWords = {
  'sch', 'schedule', 'szedul', 'szedzul', 'skedul', 'skedzul', 'szejdul',
};

/// Harmonogram z wypowiedzi jako klucz tabeli `kPipeWalls` („40", „80S",
/// „STD", „XS", „XXS", „10S") albo null. „sch 10" zostaje „10" — tabela go
/// nie ma, umiejętność zapyta.
String? parseSchedule(Utterance u) {
  final items = u.items;
  for (var i = 0; i < items.length; i++) {
    final it = items[i];
    if (it.isNumber) continue;
    final w = it.word;
    final g = _schGlued.firstMatch(w);
    if (g != null) return '${g[1]}${g[2]!.isEmpty ? '' : 'S'}';
    final s = _sSuffix.firstMatch(w);
    if (s != null) return '${s[1]}S';
    if (w == 'std') return 'STD';
    if (w == 'xs') return 'XS';
    if (w == 'xxs') return 'XXS';
    if (_schWords.contains(w) && i + 1 < items.length) {
      final n = items[i + 1];
      if (n.isNumber) {
        final v = n.value!;
        if (v != v.roundToDouble() || v <= 0) return null;
        final suffix = i + 2 < items.length &&
                !items[i + 2].isNumber &&
                items[i + 2].word == 's'
            ? 'S'
            : '';
        return '${v.toInt()}$suffix';
      }
      final nw = n.word;
      if (nw == 'std' || nw == 'standard') return 'STD';
      if (nw == 'xs') return 'XS';
      if (nw == 'xxs') return 'XXS';
      final ns = _sSuffix.firstMatch(nw);
      if (ns != null) return '${ns[1]}S';
    }
  }
  return null;
}
