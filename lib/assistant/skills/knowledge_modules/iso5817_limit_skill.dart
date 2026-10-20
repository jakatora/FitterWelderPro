import '../../../domain/iso5817/iso5817_limits.dart';
import '../../../domain/iso5817/iso5817_table.dart';
import '../../../domain/glossary/glossary.dart' show normalizeGlossary;
import '../../../utils/decimal_parse.dart';
import '../../core/skill.dart';
import '../../core/command_words.dart';

final _itemNames = {
  for (final i in kIso5817Items)
    i.id: normalizeGlossary(
        '${i.namePl} ${i.nameEn} ${i.measurePl} ${i.measureEn}')
};
final _nameHints = {
  for (final text in _itemNames.values)
    for (final word in text.split(' '))
      if (word.length >= 4) word.substring(0, 4)
};

List<Iso5817Item> _byName(String text, RegExp numeric) {
  final q = text.replaceAll(numeric, ' ').replaceAll(
      RegExp(
          r'\b(?:iso|en|poziom\w*|level|quality|klasa|limit\w*|dopuszcz\w*|allowed|permitted|acceptance|sprawdz\w*|ocen\w*|check|assess|jaki\w*|ile|jak|what|is|the|a|an|of|for|na|w|z|ze|spoina|spoiny|spoinie|czolow\w*|pachwin\w*|weld|butt|fillet|krotk\w*|dlug\w*|short|long|edition|wydani\w*|milimetr\w*|millimet\w*|stopni\w*|degrees?|pomiar|measured|measurement|stwierdz\w*|found|present|show|pokaz|wyjasnij|explain|bee|see|dee)\b'),
      ' ');
  final terms = q
      .split(' ')
      .where((v) => v.length >= 3 && RegExp(r'^[a-z]+$').hasMatch(v))
      .toSet();
  if (terms.isEmpty) return [];
  return [
    for (final i in kIso5817Items)
      if (terms.every((v) {
        final hay = _itemNames[i.id]!;
        return hay.contains(v) ||
            (v.length >= 6 && hay.contains(v.substring(0, v.length - 2)));
      }))
        i
  ];
}

Map<String, Object?> _slots(Utterance original) {
  final u = original.withRaw(original.raw
      .replaceAll('°', ' degrees ')
      .replaceAll(RegExp(r'[-−]\s*(?=\d)'), ' minus '));
  final f = u.tokens.join(' ');
  final s = <String, Object?>{};
  final editions = <String>{
    for (final m
        in RegExp(r'\b(?:5817|edition|wydani\w*)\s+(20\d{2})\b').allMatches(f))
      m[1]!,
    for (final m in RegExp(r'\b(?:2014|2023)\b').allMatches(f)) m[0]!,
    if (RegExp(r'^20\d{2}$').hasMatch(f)) f,
  };
  if (editions.isNotEmpty) {
    s['edition'] = editions.length == 1 ? editions.single : 'ambiguous';
  }
  final levels = RegExp(
          r'\b(?:poziom\w*|level|quality|klasa)\s+(b|be|bee|c|ce|see|d|de|dee)\b')
      .allMatches(f)
      .map((m) => m[1] == 'see' ? 'c' : m[1]![0])
      .toSet();
  if (levels.isNotEmpty) {
    s['level'] = levels.length == 1 ? levels.single : 'ambiguous';
  }
  final kinds = <String>{};
  if (RegExp(r'\b(?:czolow\w*|butt)\b').hasMatch(f)) kinds.add('butt');
  if (RegExp(r'\b(?:pachwin\w*|fillet)\b').hasMatch(f)) kinds.add('fillet');
  if (kinds.isNotEmpty) {
    s['kind'] = kinds.length == 1 ? kinds.single : 'ambiguous';
  }
  final numeric = <String, List<double>>{};
  final measuredUnits = <String>{};
  final pattern = RegExp(
      r'\b(t|broot|b root|b grani|a|b|h|d|pomiar|measured|measurement|grubosc|thickness|szerokosc lica|face width|szerokosc grani|root width|kat|angle)\s*(?:=|:)?\s*(minus\s+|[-−])?(\d+(?:[.,]\d+)?)\s*(mm|cm|milimetr\w*|millimet\w*|stopni\w*|degrees?|°)?\b');
  // Raw folded text preserves digit decimals; spoken items supply spoken numbers.
  final text =
      u.tokens.join(' ').replaceAll(RegExp(r'\bpoziom\w* [bcd]\b'), ' ');
  for (final m in pattern.allMatches(text)) {
    final key = switch (m[1]!) {
      't' || 'grubosc' || 'thickness' => 't',
      'a' => 'a',
      'broot' ||
      'b root' ||
      'b grani' ||
      'szerokosc grani' ||
      'root width' =>
        'b_root',
      'b' || 'szerokosc lica' || 'face width' => 'b',
      _ => 'measured',
    };
    var v = parseDecimal(m[3]!) ?? double.nan;
    if (m[2] != null) v = -v;
    if (m[4] == 'cm') v *= 10;
    if (m[4] == null) v = double.nan;
    final angleUnit = RegExp(r'^(?:stopni|degree)').hasMatch(m[4] ?? '');
    if (key != 'measured' && angleUnit) v = double.nan;
    if (key == 'measured') measuredUnits.add(angleUnit ? 'angle' : 'length');
    numeric.putIfAbsent(key, () => []).add(v);
  }
  for (final e in numeric.entries) {
    s[e.key] = e.value.toSet().length == 1 ? e.value.first : double.nan;
  }
  if (measuredUnits.isNotEmpty) {
    s['measured_unit'] =
        measuredUnits.length == 1 ? measuredUnits.single : 'ambiguous';
  }
  final short = u.hasStem(const ['krotk', 'short']);
  final long = RegExp(r'\b(?:dlug(?:a|i|ie|iej|ich)?|long)\b').hasMatch(f);
  if (short || long) s['short'] = short && long ? 'ambiguous' : short;
  if (u.hasStem(const ['sprawdz', 'ocen', 'check', 'assess']) ||
      s.containsKey('measured')) {
    s['assess'] = true;
  }
  if (u.hasStem(const ['stwierdz', 'obecn', 'present', 'found'])) {
    s['present'] = true;
  }
  final itemMatch = RegExp(
          r'\b(?:poz\w*|pozycja|item)\s+(\d+[.,]\d+(?:\s+(?:butt|fillet|pipe|plate))?)\b')
      .firstMatch(f);
  if (itemMatch != null) {
    final id = itemMatch[1]!.replaceAll(',', '.').replaceAll(' ', '-');
    s['items'] = [
      for (final i in kIso5817Items)
        if (i.id == id || i.no == id) i.id
    ];
  } else {
    final codes = RegExp(r'\b(?:[1-6]\d{2,3})\b')
        .allMatches(text.replaceAll(pattern, ' '))
        .map((m) => int.parse(m[0]!))
        .where((v) => v != 5817 && v != 6520 && !editions.contains('$v'))
        .toSet();
    var hits = [
      for (final i in kIso5817Items)
        if (i.codes.any(codes.contains)) i
    ];
    if (codes.isEmpty) {
      final aliases = <String, String>{
        'podtop': 'podtop',
        'undercut': 'podtop',
        'pekn': 'pekn',
        'crack': 'pekn',
        'rozprysk': 'rozprysk',
        'spatter': 'rozprysk',
        'nadlew lica': 'nadlew lica',
        'excess weld metal': 'nadlew lica',
        'przepalen': 'przepalen',
        'burn through': 'przepalen',
        'asymetr': 'asymetr',
        'asymmetry': 'asymetr',
        'kat przejscia': 'kat przejscia',
        'toe angle': 'kat przejscia',
        'por powierzchniowy': 'por powierzchniowy',
        'surface pore': 'por powierzchniowy',
      };
      final terms = aliases.entries
          .where((e) => f.contains(e.key))
          .map((e) => e.value)
          .toSet();
      if (terms.isNotEmpty) s['named'] = true;
      hits = [
        for (final i in kIso5817Items)
          if (terms.any((t) => normalizeGlossary(i.namePl).contains(t))) i
      ];
    }
    if (codes.isEmpty) {
      final names = _byName(text, pattern);
      if (names.isNotEmpty) {
        hits = names;
        s['named'] = true;
      }
    }
    if (hits.isNotEmpty || codes.isNotEmpty) {
      s['items'] = hits.map((i) => i.id).toList();
    }
  }
  if (u.hasStem(const [
        'alumin',
        'laser',
        'beam',
        'czesciow',
        'zmeczeni',
        'fatigue',
        'systematycz',
        'systematic'
      ]) ||
      u.hasAny(const ['partial penetration', 'b90', 'b125'])) {
    s['unsupported'] = true;
  }
  return s;
}

class Iso5817LimitSkill extends AssistantSkill {
  @override
  String get id => 'iso5817.limit';
  @override
  String get toolId => 'iso5817';
  @override
  bool get answersQuestionsOnly => true;
  @override
  AssistantTier get tier => AssistantTier.b;
  @override
  List<SkillExample> get examples => const [
        SkillExample(
            'Limit ISO 5817 2014 podtopienie poziom B t 10 mm spoina czołowa',
            'ISO 5817 2014 limit undercut level B t 10 mm butt weld'),
        SkillExample('Ile podtopienia na poziomie B', 'Undercut limit level B'),
        SkillExample(
            'Limit ISO 5817 2014 5011 poziom C t 2 mm spoina czołowa krótkie',
            'ISO 5817 2014 limit 5011 level C t 2 mm butt short'),
        SkillExample(
            'Limit ISO 5817 2014 rozprysk poziom D t 10 mm spoina czołowa',
            'ISO 5817 2014 spatter limit level D t 10 mm butt'),
        SkillExample(
            'Limit ISO 5817 2014 pozycja 1.9 poziom C t 10 mm b 12 mm spoina czołowa',
            'ISO 5817 2014 item 1.9 limit level C t 10 mm b 12 mm butt'),
        SkillExample(
            'Sprawdź ISO 5817 2014 5011 poziom B t 10 mm pomiar 0,4 mm spoina czołowa',
            'Check ISO 5817 2014 5011 level B t 10 mm measured 0.4 mm butt'),
      ];
  @override
  List<SkillRejection> get rejections => const [
        SkillRejection('Przyczyny podtopienia TIG stal nierdzewna',
            routesTo: 'defects.causes'),
        SkillRejection('Jak jest podtopienie po niemiecku?',
            routesTo: 'glossary.term'),
        SkillRejection('Otwórz odbiór wizualny spoin', routesTo: 'tool.open'),
      ];
  @override
  SkillMatch? match(Utterance u, AssistantContext ctx) {
    if (!u.tokens.contains('5817') &&
        !u.hasStem(const ['poziom', 'level', 'quality']) &&
        !u.tokens.any(
            (v) => v.length >= 4 && _nameHints.contains(v.substring(0, 4)))) {
      return null;
    }

    if (referencesInstruction(u) &&
        u.hasStem(const [
          'sprawdz',
          'check',
          'ocen',
          'assess',
          'poleceni',
          'command'
        ])) {
      return null;
    }
    if (kCommandVerbRe.hasMatch(u.folded) ||
        isNegatedCommand(u) ||
        u.hasStem(const ['przetlum', 'translat', 'przyczyn', 'cause'])) {
      return null;
    }
    final s = _slots(u);
    if (!u.tokens.contains('5817') &&
        !s.containsKey('level') &&
        s['named'] != true) {
      return null;
    }
    final hasIntent = u.hasStem(const [
          'limit',
          'dopuszcz',
          'odbior',
          'accept',
          'sprawdz',
          'check',
          'ocen',
          'assess'
        ]) ||
        u.hasStem(const ['poziom', 'level']) ||
        u.tokens.contains('5817') ||
        (u.hasAny(const ['ile']) && s['named'] == true);
    if (!hasIntent || (!u.tokens.contains('5817') && !s.containsKey('items'))) {
      return null;
    }
    if (kOpenVerbAtStartRe.hasMatch(u.folded) && !s.containsKey('items')) {
      return null;
    }
    return SkillMatch(this, .97, slots: s, utterance: u);
  }

  @override
  Map<String, Object?> slotsFrom(Utterance u, AssistantContext ctx) {
    if (!u.isContinuation ||
        !(u.hasStem(const [
              'pomiar',
              'measur',
              'grubos',
              'thickness',
              'poziom',
              'level',
              'krotk',
              'short',
              'dlug',
              'long'
            ]) ||
            RegExp(r'\b(?:t|b|a)\s+\d').hasMatch(u.tokens.join(' ')))) {
      return const {};
    }
    final slots = _slots(u);
    slots.remove('items');
    slots.remove('named');
    return slots;
  }

  @override
  Map<String, Object?>? fillSlot(
      String slot, Utterance u, AssistantContext ctx) {
    final s = _slots(u);
    if (slot == 'edition' && u.hasAny(const ['tak', 'yes'])) {
      return {'edition': '2014'};
    }
    if (slot == 'short' && u.hasAny(const ['tak', 'yes', 'nie', 'no'])) {
      return {
        'short': u.hasAny(const ['tak', 'yes'])
      };
    }
    if (slot == 'present' && u.hasAny(const ['tak', 'yes', 'nie', 'no'])) {
      return {
        'present': u.hasAny(const ['tak', 'yes']),
        'assess': u.hasAny(const ['tak', 'yes'])
      };
    }
    if (slot == 'measured' && u.hasAny(const ['tylko limit', 'limit only'])) {
      return {'assess': false, 'measured': null};
    }
    if (slot == 'level' &&
        RegExp(r'^(?:b|be|bee|c|ce|see|d|de|dee)$').hasMatch(u.folded)) {
      return {'level': u.folded == 'see' ? 'c' : u.folded[0]};
    }
    if (const ['t', 'b', 'b_root', 'a', 'measured'].contains(slot) &&
        RegExp(r'^(?:minus )?\d+(?:[.,]\d+)? (?:mm|cm|milimetr\w*|millimet\w*|stopni\w*|degrees?)$')
            .hasMatch(u.tokens.join(' '))) {
      final label = slot == 'b_root'
          ? 'b root'
          : slot == 'measured'
              ? 'pomiar'
              : slot;
      return _slots(u.withRaw('$label ${u.raw}'));
    }
    return s.containsKey(slot) ? s : null;
  }

  AskResult _ask(SkillMatch m, String slot, String pl, String en,
          [List<FollowUp> choices = const []]) =>
      AskResult(slot, AssistantText(pl, en), partial: m, choices: choices);
  @override
  Future<SkillResult> run(SkillMatch m, AssistantContext ctx) async {
    final s = m.slots;
    if (s['unsupported'] == true) {
      return const FailedResult(
          AssistantText(
              'Żądanie wykracza poza model tabeli VT z pełnym przetopem i bez oceny zmęczeniowej lub niezgodności systematycznych.',
              'The request is outside the VT table model for full penetration, without fatigue or systematic-imperfection assessment.'),
          reportMissingCapability: true);
    }
    if (s['edition'] == null || s['edition'] == 'ambiguous') {
      return _ask(
          m,
          'edition',
          'Ta tabela liczy wg EN ISO 5817:2014, wycofanego i zastąpionego przez wydanie 2023. Czy projekt wymaga tabeli 2014?',
          'This table uses EN ISO 5817:2014, withdrawn and superseded by 2023. Does the project require the 2014 table?',
          const [
            FollowUp(AssistantText('Tak, 2014', 'Yes, 2014'), '2014'),
            FollowUp(AssistantText('Wymagane 2023', '2023 required'), '2023')
          ]);
    }
    if (s['edition'] != '2014') {
      return const FailedResult(
          AssistantText(
              'Nie mam zweryfikowanej tabeli liczbowej dla tego wydania. Nie użyję zamiast niej limitów 2014.',
              'There is no verified numerical table for this edition. The 2014 limits will not be substituted.'),
          reportMissingCapability: true);
    }
    var hits = [
      for (final id in (s['items'] as List?) ?? [])
        if (iso5817ItemById('$id') != null) iso5817ItemById('$id')!
    ];
    final kind =
        Iso5817WeldKind.values.where((v) => v.name == s['kind']).firstOrNull;
    if (s.containsKey('items') && hits.isEmpty) {
      return const FailedResult(
          AssistantText(
              'Ta niezgodność lub pozycja nie występuje w tabeli VT aplikacji.',
              'This imperfection or item is absent from the app VT table.'),
          reportMissingCapability: true);
    }
    if (kind != null &&
        hits.isNotEmpty &&
        !hits.any((i) => i.appliesTo(kind))) {
      return _ask(
          m,
          'kind',
          'Podany rodzaj spoiny nie pasuje do tej pozycji. Podaj czołową albo pachwinową.',
          'The weld kind does not match this item. Give butt or fillet.');
    }
    if (kind != null) hits = hits.where((i) => i.appliesTo(kind)).toList();
    if (hits.isEmpty) {
      return _ask(
          m,
          'items',
          'Podaj pozycję tablicy 1, numer ISO 6520-1 lub nazwę niezgodności VT.',
          'Give a Table 1 item, ISO 6520-1 number or a VT imperfection name.');
    }
    if (hits.length > 1) {
      return _ask(m, 'items', 'Wybierz dokładną pozycję tablicy.',
          'Choose the exact table item.', [
        for (final i in hits)
          FollowUp(AssistantText('${i.no} ${i.namePl}', '${i.no} ${i.nameEn}'),
              'item ${i.id.replaceAll('-', ' ')}')
      ]);
    }
    final item = hits.single;
    if (kind == null) {
      return _ask(m, 'kind', 'Spoina czołowa czy pachwinowa?',
          'Butt weld or fillet weld?', [
        for (final v in item.kinds)
          FollowUp(
              AssistantText(
                  v == Iso5817WeldKind.butt ? 'Czołowa' : 'Pachwinowa',
                  v == Iso5817WeldKind.butt ? 'Butt' : 'Fillet'),
              v.name)
      ]);
    }
    final level =
        Iso5817Level.values.where((v) => v.name == s['level']).firstOrNull;
    if (level == null) {
      return _ask(m, 'level', 'Jaki poziom jakości: B, C czy D?',
          'Which quality level: B, C or D?', const []);
    }
    for (final key in ['t', 'b', 'b_root', 'a', 'measured']) {
      final v = s[key] as double?;
      if (v != null &&
          (!v.isFinite || v < 0 || (key != 'measured' && v == 0))) {
        return _ask(
            m,
            key,
            'Podaj jedną poprawną wartość $key z etykietą i jednostką.',
            'Give one valid $key value with its label and unit.');
      }
    }
    final input = Iso5817Input(
        t: s['t'] as double?,
        b: s['b'] as double?,
        bRoot: s['b_root'] as double?,
        a: s['a'] as double?);
    final limit = iso5817Limit(item, level, input);
    if (limit.status == Iso5817LimitStatus.needsThickness) {
      return _ask(m, 't', 'Podaj grubość cieńszej ścianki t w mm.',
          'Give the thinner member thickness t in mm.');
    }
    if (limit.status == Iso5817LimitStatus.outOfScope) {
      return const FailedResult(
          AssistantText('t < 0,5 mm jest poza zakresem tej tabeli.',
              't < 0.5 mm is outside this table.'),
          reportMissingCapability: true);
    }
    if (limit.status == Iso5817LimitStatus.needsDimension) {
      final key = limit.missingDim == Iso5817Dim.bRoot
          ? 'b_root'
          : limit.missingDim!.name;
      return _ask(
          m,
          key,
          'Podaj ${iso5817DimName(limit.missingDim!, en: false)} w mm z etykietą.',
          'Give ${iso5817DimName(limit.missingDim!, en: true)} in mm with its label.');
    }
    final all = iso5817Limits(item, input);
    if (all.values.any((v) => v.shortOnly) && s['short'] is! bool) {
      return _ask(
          m,
          'short',
          'Czy niezgodność jest krótka wg rozdz. 3.3/3.4: suma do 25 mm na najgorszych 100 mm spoiny, a przy spoinie krótszej niż 100 mm do 25% jej długości?',
          'Is it short under clauses 3.3/3.4: total up to 25 mm in the worst 100 mm, or up to 25% of a weld shorter than 100 mm?',
          const [
            FollowUp(AssistantText('Krótka', 'Short'), 'short'),
            FollowUp(AssistantText('Długa', 'Long'), 'long')
          ]);
    }
    final assess = s['assess'] == true;
    if (item.measure == Iso5817Measure.presence && s['measured'] != null) {
      return _ask(
          m.copyWith(slots: {...s, 'measured': null}),
          'present',
          'Ta pozycja ocenia obecność, nie wymiar. Czy stwierdzono tę niezgodność?',
          'This item assesses presence, not size. Was this imperfection found?');
    }
    if (item.measure == Iso5817Measure.angleDeg &&
        s['measured'] is double &&
        (s['measured'] as double) > 180) {
      return _ask(m, 'measured', 'Podaj zmierzony kąt od 0 do 180 stopni.',
          'Give a measured angle from 0 to 180 degrees.');
    }
    if (s['measured'] != null &&
        (item.measure == Iso5817Measure.angleDeg
            ? s['measured_unit'] != 'angle'
            : s['measured_unit'] != 'length')) {
      return _ask(
          m,
          'measured',
          item.measure == Iso5817Measure.angleDeg
              ? 'Podaj zmierzony kąt w stopniach, np. kąt 120 stopni.'
              : 'Podaj pomiar w mm, np. pomiar 0,4 mm.',
          'Give the measurement in the correct unit: degrees for an angle, mm for a length.');
    }
    if (assess &&
        item.measure == Iso5817Measure.presence &&
        s['present'] != true) {
      return _ask(
          m,
          'present',
          'Czy stwierdzono obecność tej niezgodności? Powiedz „stwierdzono”.',
          'Was this imperfection found? Say “found”.');
    }
    if (assess &&
        item.measure != Iso5817Measure.presence &&
        s['measured'] == null) {
      return _ask(
          m,
          'measured',
          item.measurePl.isEmpty
              ? 'Podaj pomiar z etykietą i jednostką.'
              : '${item.measurePl}: podaj pomiar z etykietą i jednostką.',
          'Give the measurement with its label and unit.');
    }
    final a = assessIso5817(
        item: item,
        required: level,
        input: input,
        measured: s['measured'] as double?,
        isShort: s['short'] == true);
    String summary(bool en) => limit.shortOnly && s['short'] == false
        ? (en
            ? 'not permitted for a long imperfection'
            : 'niedopuszczalne dla niezgodności długiej')
        : iso5817LimitValueText(limit, en: en);
    String text(bool en) => assess
        ? buildIso5817Report(assessment: a, kind: kind, input: input, en: en)
        : [
            '$kIso5817Edition · ${en ? "Table" : "Tablica"} 1 ${item.no}: ${en ? item.nameEn : item.namePl}',
            '${level.letter}: ${summary(en)}',
            iso5817RuleText(limit.rule!, en: en, symbol: item.symbol),
            iso5817LimitCalc(limit, input, en: en),
            en ? item.remarkEn : item.remarkPl,
            en ? item.note2023En : item.note2023Pl,
            en
                ? 'Limit reference only; no measured imperfection is being assessed.'
                : 'Pokazuję limit; nie oceniam stwierdzonej niezgodności.',
            iso5817Disclaimer(en: en),
          ].where((v) => v.isNotEmpty).join('\n');
    return AnswerResult(
        AssistantAnswer(
            text: AssistantText(text(false), text(true)),
            source: AssistantText.same(
                '$kIso5817Edition, tablica/Table 1 ${item.no}'),
            spoken: AssistantText(
                assess
                    ? iso5817Headline(a, en: false)
                    : 'Poziom ${level.letter}: ${summary(false)}. Szczegóły i warunki w odpowiedzi.',
                assess
                    ? iso5817Headline(a, en: true)
                    : 'Level ${level.letter}: ${summary(true)}. Conditions are in the answer.')),
        show: ShowInModule('iso5817', {
          'item_id': item.id,
          'kind': kind.name,
          'level': level.name,
          't': input.t,
          'b': input.b,
          'b_root': input.bRoot,
          'a': input.a,
          'measured': assess ? s['measured'] : null,
          'short': s['short'] == true,
          'limit_only': !assess
        }));
  }
}
