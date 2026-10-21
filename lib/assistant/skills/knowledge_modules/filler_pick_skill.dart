import '../../../domain/filler/filler_catalog.dart';
import '../../../domain/filler/filler_reference.dart';
import '../../../domain/filler/filler_selector.dart';
import '../../core/skill.dart';
import '../../core/command_words.dart';

const _aliases = <BaseMaterial, List<String>>{
  BaseMaterial.carbonSteel: [
    'stal weglowa',
    'carbon steel',
    'mild steel',
    'c mn',
    's235',
    's355',
    'p235gh',
    'p265gh',
    'l245',
    'l360',
    'a106 b'
  ],
  BaseMaterial.lowTempSteel: [
    'stal niskotemperaturowa',
    'low temperature steel',
    'p355nl1',
    'p275nl1',
    'a333 gr 6',
    'a350 lf2'
  ],
  BaseMaterial.mo05: ['16mo3', 'a335 p1'],
  BaseMaterial.crMo1: ['p11', 'p12', '13crmo4 5'],
  BaseMaterial.crMo2: ['p22', '10crmo9 10'],
  BaseMaterial.p91: ['p91', 't91', 'x10crmovnb9 1'],
  BaseMaterial.ss304L: ['304l', '304', '1.4307', '1.4301'],
  BaseMaterial.ss316L: ['316l', '316', '1.4404', '1.4401'],
  BaseMaterial.ss321: ['321', '1.4541'],
  BaseMaterial.duplex2205: ['2205', '1.4462', 's31803', 's32205'],
  BaseMaterial.superDuplex2507: ['2507', '1.4410', 's32750'],
  BaseMaterial.al5083: ['5083'],
  BaseMaterial.al6xxx: ['6061', '6082'],
  BaseMaterial.cuNi9010: ['cuni 90 10', 'cuni10fe1mn', 'cw352h', 'c70600'],
};
List<BaseMaterial> _materials(Utterance u) {
  int position(BaseMaterial m) {
    var first = u.folded.length;
    for (final a in [m.name, ..._aliases[m]!]) {
      final pattern = Utterance(a, lang: u.lang).folded;
      final index = ' ${u.folded} '.indexOf(' $pattern ');
      if (index >= 0 && index < first) first = index;
    }
    return first;
  }

  return [
    for (final m in BaseMaterial.values)
      if (u.hasAny([m.name, ..._aliases[m]!])) m,
  ]..sort((a, b) => position(a).compareTo(position(b)));
}

int _occurrences(Utterance u, BaseMaterial m) {
  final patterns = {
    for (final a in [m.name, ..._aliases[m]!])
      RegExp.escape(Utterance(a, lang: u.lang).folded)
  }.toList()
    ..sort((a, b) => b.length.compareTo(a.length));
  return RegExp('\\b(?:${patterns.join("|")})\\b').allMatches(u.folded).length;
}

bool _unsupportedMaterial(Utterance u) {
  if (u.hasAny(const ['cast iron']) ||
      u.hasStem(const [
        'tytan',
        'titanium',
        'zeliw',
        'cast iron',
        'hastelloy',
        'inconel'
      ])) {
    return true;
  }
  final codes = RegExp(
          r'\b(?:s\d{3}[a-z0-9]*|p\d{2,3}[a-z0-9]*|t\d{2}[a-z0-9]*|\d{3,4}[a-z]+|1[.,]\d{4}|c\d{5}|cw\d{3}[a-z]+)\b')
      .allMatches(u.folded);
  return codes.any((c) => !_aliases.values.any(
      (list) => list.any((a) => Utterance(a, lang: u.lang).folded == c[0])));
}

Map<String, Object?> _slots(Utterance u) {
  final cleaned = Utterance(
      u.tokens
          .join(' ')
          .replaceAll(
              RegExp(r'\b\d+(?:[.,]\d+)?\s+(?:a|amps|amper\w*|mm|v)\b'), ' ')
          .replaceAllMapped(RegExp(r'\b(304|316)\s+l\b'), (m) => '${m[1]}l'),
      lang: u.lang);
  final materials =
      <BaseMaterial>{..._materials(cleaned), ..._materials(u)}.toList();
  final same = u.hasAny(
      const ['ten sam', 'taki sam', 'same material', 'same', 'jednoimienne']);
  final processes = <FillerProcess>{
    if (cleaned.hasAny(const ['tig', 'gtaw', '141'])) FillerProcess.tig,
    if (cleaned.hasAny(const ['mig', 'mag', 'gmaw', '131', '135', 'mig mag']))
      FillerProcess.mig,
    if (cleaned.hasAny(const ['mma', 'smaw', '111', 'stick']))
      FillerProcess.mma,
    if (cleaned.hasAny(const ['136', 'fcaw g'])) FillerProcess.fcaw,
  };
  return {
    if (_unsupportedMaterial(u) || _unsupportedMaterial(cleaned))
      'unsupported_material': true,
    if (materials.isNotEmpty) 'a': materials.first.name,
    if (materials.length == 2) 'b': materials.last.name,
    if (materials.length == 1 &&
        (_occurrences(u, materials.single) > 1 ||
            _occurrences(cleaned, materials.single) > 1))
      'b': materials.single.name,
    if (materials.length > 2) 'too_many': true,
    if (materials.length == 2 && same) 'conflicting_same': true,
    if (u.hasAny(
        const ['ten sam', 'taki sam', 'same material', 'same', 'jednoimienne']))
      'same': true,
    if (processes.isNotEmpty)
      'process': processes.length == 1 ? processes.single.name : 'ambiguous',
    if (cleaned.hasAny(const [
      '114',
      '121',
      '138',
      'fcaw s',
      'samooslonowy',
      'self shielded',
      'saw'
    ]))
      'outside_process': true,
  };
}

class FillerPickSkill extends AssistantSkill {
  @override
  String get id => 'filler.pick';
  @override
  String get toolId => 'filler_selector';
  @override
  AssistantTier get tier => AssistantTier.b;
  @override
  bool get answersQuestionsOnly => true;
  @override
  List<SkillExample> get examples => const [
        SkillExample('Spoiwo do 316L', 'Filler for 316L'),
        SkillExample(
            'Jakie spoiwo 5083 z 6061 TIG', 'Which filler 5083 to 6061 TIG'),
        SkillExample('Dobierz spoiwo 304L i 316L TIG',
            'Select filler 304L and 316L TIG'),
        SkillExample('Spoiwo S355 z 304L MAG', 'Filler S355 to 304L MAG'),
        SkillExample('Spoiwo P91 i S355 MMA', 'Filler P91 and S355 MMA'),
        SkillExample('Pokaż dobór spoiwa 2205 i 2507 TIG',
            'Show filler selection 2205 and 2507 TIG'),
      ];
  @override
  List<SkillRejection> get rejections => const [
        SkillRejection('Otwórz dobór spoiwa', routesTo: 'tool.open'),
        SkillRejection('zapisz TIG 2 mm 60 A'),
        SkillRejection('TIG with filler stainless wall 2.77 mm 90 A',
            routesTo: 'legacy.save'),
        SkillRejection('Czerwony pasek na tarczy', routesTo: 'grinding.stripe'),
      ];
  @override
  SkillMatch? match(Utterance u, AssistantContext ctx) {
    if (!u.hasStem(const ['spoiw', 'filler', 'consumable'])) {
      return null;
    }
    if (u.hasAny(const ['with filler', 'ze spoiwem', 'z dodatkiem spoiwa'])) {
      return null;
    }
    if (isNegatedCommand(u) ||
        kCommandVerbRe.hasMatch(u.folded) ||
        u.hasStem(const ['przetlum', 'translat'])) {
      return null;
    }
    final s = _slots(u);
    if (kOpenVerbAtStartRe.hasMatch(u.folded) && !s.containsKey('a')) {
      return null;
    }
    return SkillMatch(this, .96, slots: s, utterance: u);
  }

  @override
  Map<String, Object?> slotsFrom(Utterance u, AssistantContext ctx) => const {};
  @override
  Map<String, Object?>? fillSlot(
      String slot, Utterance u, AssistantContext ctx) {
    final s = _slots(u);
    if (s['unsupported_material'] == true ||
        s['outside_process'] == true ||
        s['too_many'] == true) {
      return {...s, slot: 'unsupported'};
    }
    if (slot == 'b') {
      if (s['same'] == true) return {'same': true};
      if (s['a'] != null && s['b'] == null) {
        return {
          for (final e in s.entries)
            if (e.key != 'a') e.key: e.value,
          'b': s['a']
        };
      }
    }
    if (s.containsKey(slot)) return s;
    return null;
  }

  AskResult _ask(String slot, SkillMatch m) => AskResult(
          slot,
          switch (slot) {
            'a' => const AssistantText(
                'Jaki dokładnie materiał A? Podaj gatunek.',
                'What is material A? Give the grade.'),
            'b' => const AssistantText(
                'Jaki materiał po drugiej stronie? Możesz wybrać „ten sam”.',
                'What is the other material? You can choose “same material”.'),
            _ => const AssistantText(
                'Jaki proces: TIG, MIG/MAG, MMA czy FCAW 136?',
                'Which process: TIG, MIG/MAG, MMA or FCAW 136?'),
          },
          partial: m,
          choices: [
            if (slot == 'b')
              const FollowUp(
                  AssistantText('Ten sam', 'Same material'), 'same material'),
            if (slot == 'a' || slot == 'b')
              for (final mat in BaseMaterial.values)
                FollowUp(AssistantText(mat.label.pl, mat.label.en), mat.name),
            if (slot == 'process')
              for (final p in FillerProcess.values)
                FollowUp(AssistantText.same(p.label),
                    p == FillerProcess.fcaw ? '136' : p.name3),
          ]);
  @override
  Future<SkillResult> run(SkillMatch m, AssistantContext ctx) async {
    final s = m.slots;
    if (s['unsupported_material'] == true) {
      return const FailedResult(
          AssistantText(
              'Tego gatunku nie ma w katalogu doboru aplikacji. Nie zastępuję go podobnym gatunkiem; dobór wymaga WPS lub technologa.',
              'This grade is absent from the app selection catalogue. I cannot substitute a similar grade; consult the WPS or welding engineer.'),
          reportMissingCapability: true);
    }
    if (s['outside_process'] == true || s['too_many'] == true) {
      return const FailedResult(
          AssistantText(
              'Katalog obejmuje parę materiałów i procesy 141, 131/135, 111 oraz 136. Ten zakres wymaga osobnego doboru.',
              'The catalogue covers a material pair and processes 141, 131/135, 111 and 136. This request needs a separate selection.'),
          reportMissingCapability: true);
    }
    if (s['conflicting_same'] == true) {
      return _ask(
          'b',
          m.copyWith(slots: {
            ...s,
            'b': null,
            'same': false,
            'conflicting_same': false
          }));
    }
    final a = BaseMaterial.values.where((v) => v.name == s['a']).firstOrNull;
    if (a == null) return _ask('a', m);
    final b = s['same'] == true
        ? a
        : BaseMaterial.values.where((v) => v.name == s['b']).firstOrNull;
    if (b == null) return _ask('b', m);
    final p =
        FillerProcess.values.where((v) => v.name == s['process']).firstOrNull;
    if (p == null) return _ask('process', m);
    final r = selectFiller(a, b);
    final text = AssistantText(fillerReference(a, b, p, en: false),
        fillerReference(a, b, p, en: true));
    if (r.verdict == FillerVerdict.typical && r.forProcess(p) == null) {
      return FailedResult(text, reportMissingCapability: true);
    }
    return AnswerResult(
        AssistantAnswer(
            text: text,
            source: const AssistantText(
                'Katalog doboru aplikacji · EN ISO / AWS; IMOA wyd.3 tab.16 dla połączeń dupleks',
                'App selection catalogue · EN ISO / AWS; IMOA ed.3 table16 for duplex joints')),
        show: ShowInModule(toolId,
            {'material_a': a.name, 'material_b': b.name, 'process': p.name}));
  }
}
