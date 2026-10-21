import '../../../domain/welding/electrode_exposure.dart';
import '../../../domain/welding/electrode_reference.dart';
import '../../core/skill.dart';
import '../../core/command_words.dart';
import '../own_data/electrodes_status_skill.dart' show isElectrodeStatusQuery;

String _classText(Utterance u) => u.tokens.join(' ').replaceAllMapped(
    RegExp(r'\be\s+((?:\d\s+){3,4}\d)\b'),
    (m) => 'e${m[1]!.replaceAll(" ", "")}');
String _splitHydrogen(String text) => text
    .replaceAllMapped(
        RegExp(
            r'(\bE?\s*(?:7018|7016|7048|8018|9018|10018|11018))\s+(?:-\s*)?([ABCDW]\d+|NI\d+)\b',
            caseSensitive: false),
        (m) => '${m[1]}-${m[2]}')
    .replaceAllMapped(
        RegExp(
            r'(E?\s*(?:7018|7016|7048|8018|9018|10018|11018)(?:-?(?:1|[A-Z]\d+|M|R|X))?)(H\d+R?)\b',
            caseSensitive: false),
        (m) => '${m[1]} ${m[2]}');

Map<String, Object?> _slots(Utterance u) {
  final s = <String, Object?>{};
  final f = u.tokens.join(' ');
  final classes = <ElectrodeClass>{};
  final plain = u.hasAny(const ['bez r', 'without r', 'non r']);
  final rText = f.replaceAll(RegExp(r'\b(?:bez|without|non)\s+r\b'), ' ');
  final hasR = RegExp(r'h\d+r\b|\br\b|\be?\s*7018r\b').hasMatch(rText);
  final r = !plain && hasR;
  if (plain) s['variant'] = 'plain';
  if (r) s['variant'] = 'r';
  if (plain && hasR) {
    s['variant'] = 'ambiguous';
    s['needs_variant'] = true;
  }
  if (u.hasAny(const ['wariant m', 'variant m'])) s['variant'] = 'm';
  final codePattern = RegExp(
      r'\bE?\s*(7018|7016|7048|8018|9018|10018|11018)(-?1|-?[A-Z]\d+|-?[MRX])?\b',
      caseSensitive: false);
  final matches = codePattern.allMatches(_splitHydrogen(u.raw)).toList();
  if (matches.isEmpty) {
    matches.addAll(codePattern.allMatches(_splitHydrogen(_classText(u))));
  }
  for (final m in matches) {
    final code = m[1]!;
    final rawSuffix = (m[2] ?? '').toUpperCase();
    final suffix = rawSuffix.replaceAll('-', '');
    if (const ['7018', '7016', '7048'].contains(code)) {
      if (code == '7018' && rawSuffix == '-M') {
        classes.addAll([ElectrodeClass.e7018M, ElectrodeClass.e7018X]);
      } else if (suffix == 'M' && rawSuffix != '-M') {
        if (code != '7018') s['unsupported'] = true;
        classes.add(ElectrodeClass.e7018M);
      } else if (suffix.isNotEmpty && !const ['1', 'R'].contains(suffix)) {
        classes.add(ElectrodeClass.e7018X);
        if (r) s['unsupported'] = true;
      } else if (r || suffix == 'R') {
        classes.add(ElectrodeClass.e7018R);
        s['base'] = suffix == '1' ? 'e7018dash1' : 'e7018';
      } else {
        final c =
            suffix == '1' ? ElectrodeClass.e7018dash1 : ElectrodeClass.e7018;
        classes.add(c);
        s['base'] = c.name;
        s['needs_variant'] =
            (plain && hasR) || (!plain && !RegExp(r'\bh\d+\b').hasMatch(f));
      }
    } else {
      if (r || suffix == 'R') s['unsupported'] = true;
      classes.add(switch (code) {
        '8018' => ElectrodeClass.e8018X,
        '9018' => ElectrodeClass.e9018X,
        '10018' => ElectrodeClass.e10018X,
        _ => ElectrodeClass.e11018X,
      });
    }
  }
  if (u.tokens.contains('2560') && u.hasAny(const ['b'])) {
    classes.add(ElectrodeClass.enIso2560B);
  }
  if (u.tokens.contains('18275') && u.hasAny(const ['b'])) {
    if (RegExp(r'\be\s*55\b').hasMatch(f)) {
      classes.add(ElectrodeClass.enIso18275E55);
    }
    if (RegExp(r'\be\s*(?:62|69)\b').hasMatch(f)) {
      classes.add(ElectrodeClass.enIso18275E62);
    }
  }
  final sources = <String>{};
  if (u.hasStem(const ['piecyk', 'piec', 'suszark', 'termos', 'oven'])) {
    sources.add('oven');
  }
  if (u.hasStem(const [
        'hermet',
        'prozni',
        'vacuum',
        'sealed',
        'vacpac',
        'readypack'
      ]) ||
      u.hasAny(const ['fresh pack', 'swieze opakowanie'])) {
    sources.add('hermeticPack');
  }
  if (sources.isNotEmpty) {
    s['origin'] = sources.length == 1 ? sources.single : 'ambiguous';
  }
  if (classes.isNotEmpty) s['classes'] = classes.map((c) => c.name).toList();
  if (u.hasStem(const ['model', 'domysln', 'referenc']) ||
      u.hasAny(const ['2020'])) {
    s['reference'] = true;
  }
  if (RegExp(
          r'\b(?:aws|d\s*1[ .]1|edition|wydani\w*)\s*[: ]\s*(?!2020\b)20\d{2}\b')
      .hasMatch(f)) {
    s['unsupported'] = true;
  }
  if (RegExp(r'\bE?\s*(?:60\d\d|70(?:10|11|13|14)|80(?:10|11))\b',
          caseSensitive: false)
      .hasMatch(u.raw)) {
    s['unsupported'] = true;
  }
  if (RegExp(r'\bd\s*1[ .]5\b|\basme\b').hasMatch(f)) s['unsupported'] = true;
  if (RegExp(r'\bE\s*(\d{3,5})[A-Z0-9-]*\b', caseSensitive: false)
      .allMatches(u.raw)
      .any((m) => !const [
            '7018',
            '7016',
            '7048',
            '8018',
            '9018',
            '10018',
            '11018'
          ].contains(m[1]))) {
    s['unsupported'] = true;
  }
  if (u.hasStem(
      const ['mokre', 'mokry', 'mokrych', 'zawilg', 'wet', 'soaked'])) {
    s['wet'] = true;
  }
  return s;
}

String _choice(ElectrodeClass c) =>
    c == ElectrodeClass.e7018 || c == ElectrodeClass.e7018dash1
        ? '${c.code} bez R'
        : c.code;

class ElectrodesExposureSkill extends AssistantSkill {
  @override
  String get id => 'electrodes.exposure';
  @override
  String get toolId => 'electrode_exposure';
  @override
  bool get answersQuestionsOnly => true;
  @override
  AssistantTier get tier => AssistantTier.b;
  @override
  List<SkillExample> get examples => const [
        SkillExample('Ile E7018 bez R może leżeć poza piecykiem model 2020',
            'E7018 without R exposure out of oven reference 2020'),
        SkillExample('Limit ekspozycji E7018 H4R z piecyka model 2020',
            'E7018 H4R exposure out of oven reference 2020'),
        SkillExample('Limit ekspozycji E8018-B2 z piecyka model 2020',
            'E8018-B2 exposure from oven reference 2020'),
        SkillExample('Limit ekspozycji E9018-B3 z piecyka model 2020',
            'E9018-B3 exposure from oven reference 2020'),
        SkillExample('Limit ekspozycji E10018-D2 z piecyka model 2020',
            'E10018-D2 exposure from oven reference 2020'),
        SkillExample(
            'Ekspozycja EN ISO 2560-A B H5 świeże opakowanie hermetyczne model domyślny',
            'EN ISO 2560-A B H5 exposure fresh sealed pack model reference'),
      ];
  @override
  List<SkillRejection> get rejections => const [
        SkillRejection('Otwórz elektrody zasadowe', routesTo: 'tool.open'),
        SkillRejection(
            'Dobierz elektrodę wolframową TIG DCEN nierdzewna 150 A'),
        SkillRejection('Zapisz MMA 2 mm 80 A stal węglowa'),
      ];
  @override
  SkillMatch? match(Utterance u, AssistantContext ctx) {
    if (isElectrodeStatusQuery(u)) return null;
    if (u.hasStem(const [
          'przetlum',
          'translat',
          'slownik',
          'dictionary',
          'glossary'
        ]) ||
        kCommandVerbRe.hasMatch(u.folded) ||
        isNegatedCommand(u)) {
      return null;
    }
    if (!u.hasStem(const [
      'ekspozyc',
      'powietrz',
      'piecyk',
      'piec',
      'susz',
      'oven',
      'expos',
      'redry',
      'drying',
      'przechow'
    ])) {
      return null;
    }
    if (!u.hasStem(const ['elektrod', 'electrod']) &&
        !RegExp(r'\b(?:e\s*\d{3,5}[a-z0-9-]*|[6-9]\d{3}|10018|11018|2560|18275)\b',
                caseSensitive: false)
            .hasMatch('${u.raw} ${_classText(u)}')) {
      return null;
    }
    if (kOpenVerbAtStartRe.hasMatch(u.folded) &&
        !_slots(u).containsKey('classes')) {
      return null;
    }
    return SkillMatch(this, .96, slots: _slots(u), utterance: u);
  }

  @override
  Map<String, Object?> slotsFrom(Utterance u, AssistantContext ctx) => const {};
  @override
  Map<String, Object?>? fillSlot(
      String slot, Utterance u, AssistantContext ctx) {
    final s = _slots(u);
    if (s['unsupported'] == true || s['wet'] == true) return s;
    if (slot == 'reference' &&
        RegExp(r'^20\d{2}$').hasMatch(u.folded) &&
        u.folded != '2020') {
      return {'unsupported': true};
    }
    if (slot == 'reference' && u.hasAny(const ['tak', 'yes', 'nie', 'no'])) {
      return {
        'reference': u.hasAny(const ['tak', 'yes'])
      };
    }
    if (slot == 'classes' && s.containsKey('classes')) {
      return {
        ...s,
        'needs_variant': s['needs_variant'] ?? false,
        'variant': s['variant'],
        'base': s['base']
      };
    }
    if (slot == 'variant') {
      if (s.containsKey('variant')) {
        return {'variant': s['variant'], 'needs_variant': false};
      }
      if (s.containsKey('classes')) {
        return {...s, 'needs_variant': false, 'variant': null};
      }
      if (u.folded == 'm') return {'variant': 'm', 'needs_variant': false};
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
              'Ta klasyfikacja lub wydanie nie jest objęte tabelą referencyjną aplikacji.',
              'This classification or edition is outside the app reference table.'),
          reportMissingCapability: true);
    }
    if (s['wet'] == true) {
      return const FailedResult(AssistantText(
          'Sam czas referencyjny nie rozstrzyga przydatności zawilgoconych elektrod. Potrzebne są wymagania produktu i procedura projektu.',
          'A reference time does not establish fitness of wet electrodes. Product requirements and the project procedure are needed.'));
    }
    var classes = [
      for (final name in (s['classes'] as List?) ?? [])
        ...ElectrodeClass.values.where((c) => c.name == name)
    ];
    if (classes.length != 1) {
      return _ask(
          m,
          'classes',
          'Podaj pełne oznaczenie klasy elektrody z opakowania.',
          'Give the full electrode classification from its packaging.', [
        for (final c in ElectrodeClass.values)
          FollowUp(AssistantText.same(c.code), _choice(c))
      ]);
    }
    if (s['needs_variant'] == true &&
        (s['variant'] == null || s['variant'] == 'ambiguous')) {
      return _ask(
          m,
          'variant',
          'Czy oznaczenie ma R (np. H4R), M, czy jest bez R?',
          'Does the classification have R (e.g. H4R), M, or no R?', const [
        FollowUp(AssistantText('Bez R', 'No R'), 'bez R'),
        FollowUp(AssistantText('H4R / H8R', 'H4R / H8R'), 'H4R'),
        FollowUp(AssistantText('Wariant M', 'M variant'), 'wariant M')
      ]);
    }
    if (s['variant'] != null && s['base'] != null) {
      classes = [
        s['variant'] == 'r'
            ? ElectrodeClass.e7018R
            : s['variant'] == 'm'
                ? ElectrodeClass.e7018M
                : ElectrodeClass.values.byName(s['base'] as String)
      ];
    }
    final c = classes.single;
    final origin =
        ElectrodeSource.values.where((v) => v.name == s['origin']).firstOrNull;
    if (origin == null) {
      return _ask(
          m,
          'origin',
          'Elektrody wyjęto z piecyka czy właśnie otwarto opakowanie hermetyczne?',
          'Were the electrodes taken from an oven or a freshly opened hermetic pack?',
          const [
            FollowUp(AssistantText('Z piecyka', 'From oven'), 'z piecyka'),
            FollowUp(AssistantText('Świeże opakowanie', 'Fresh pack'),
                'świeże opakowanie hermetyczne')
          ]);
    }
    if (s['reference'] == false) {
      return const AnswerResult(AssistantAnswer(
          text: AssistantText(
              'Podaj wiążącą kartę produktu i wymagania projektu, aby określić właściwy limit partii.',
              'Use the product data sheet and project requirements to determine the batch limit.')));
    }
    if (s['reference'] != true) {
      return _ask(
          m,
          'reference',
          c.family.perManufacturer
              ? 'Dla tej klasy EN limit zależy od producenta. Pokazać wyłącznie ustawienie domyślne modelu, bez oceny partii?'
              : 'Baza aplikacji jest referencją AWS D1.1:2020. Pokazać wartość modelową, bez oceny partii i bez zastępowania wymagań projektu?',
          'Show only the app reference default (AWS D1.1:2020 / manufacturer-based model), without assessing a batch or replacing project requirements?',
          const [
            FollowUp(
                AssistantText('Pokaż referencję', 'Show reference'), 'tak'),
            FollowUp(
                AssistantText('Wymagania produktu', 'Product requirements'),
                'nie')
          ]);
    }
    return AnswerResult(
        AssistantAnswer(
            text: AssistantText(electrodeReferenceText(c, origin, en: false),
                electrodeReferenceText(c, origin, en: true)),
            source: AssistantText.same(c.family.perManufacturer
                ? kElectrodeSources[2]
                : kElectrodeSources[0]),
            spoken: AssistantText(
                'Wartość modelowa ${formatSpan(Duration(minutes: defaultLimitMinutes(c, origin)))}. To referencja, nie ocena partii. Szczegóły i źródła są w odpowiedzi.',
                'Model value ${formatSpan(Duration(minutes: defaultLimitMinutes(c, origin)))}. Reference only, not a batch assessment. Details and sources are in the answer.')),
        show: ShowInModule('electrode_exposure', {
          'electrode_class': c.name,
          'origin': origin.name,
          'reference_only': true
        }));
  }
}
