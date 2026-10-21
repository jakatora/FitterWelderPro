import '../../../domain/fume/fume_hazards.dart';
import '../../../domain/fume/fume_reference.dart';
import '../../core/skill.dart';
import '../../core/command_words.dart';

const _agentStems = <FumeAgent, List<String>>{
  FumeAgent.mn: ['mangan'],
  FumeAgent.ni: ['nikl', 'nikiel', 'nickel'],
  FumeAgent.pb: ['olow', 'lead'],
  FumeAgent.cd: ['kadm', 'cadmium'],
  FumeAgent.o3: ['ozon', 'ozone'],
  FumeAgent.fluorides: ['fluork', 'fluoride'],
  FumeAgent.al: ['glin', 'aluminium', 'aluminum'],
  FumeAgent.cu: ['miedz', 'copper'],
  FumeAgent.coatingOrganics: ['powlok', 'coating'],
  FumeAgent.dust: ['pyl', 'dust'],
};
Map<String, Object?> _slots(Utterance u) {
  final spoken = Utterance(u.tokens.join(' '), lang: u.lang);
  final agents = <FumeAgent>{
    for (final e in _agentStems.entries)
      if (u.hasStem(e.value)) e.key,
    for (final a in FumeAgent.values)
      if (u.folded == 'skladnik ${a.name.toLowerCase()}' ||
          (a != FumeAgent.co && u.folded == a.name.toLowerCase()))
        a,
    if ((u.hasStem(const ['tlenk']) && u.hasStem(const ['zelaz'])) ||
        u.hasAny(
            const ['tlenki zelaza', 'iron oxide', 'iron oxides', 'fe oxide']))
      FumeAgent.feOx,
    if ((u.hasStem(const ['tlenk']) && u.hasStem(const ['cynk'])) ||
        u.hasAny(const ['tlenek cynku', 'zinc oxide', 'zno']))
      FumeAgent.znO,
    if (spoken.hasAny(const ['chromu 6', 'chrom 6', 'chromium 6']) ||
        u.hasAny(const [
          'cr vi',
          'crvi',
          'chrom vi',
          'chromu vi',
          'chrom 6',
          'chromu 6',
          'chromium vi',
          'chromium 6'
        ]) ||
        u.hasStem(const ['szesciowartosciow', 'hexavalent']))
      FumeAgent.crVI,
    if ((u.hasStem(const ['tlenk', 'ditlenk', 'dwutlenk']) &&
            u.hasStem(const ['azot'])) ||
        RegExp(r'\bNO\b').hasMatch(u.raw) ||
        u.hasAny(const [
          'tlenki azotu',
          'tlenek azotu',
          'ditlenek azotu',
          'dwutlenek azotu',
          'nitrogen oxide',
          'nitrogen oxides',
          'nitrogen dioxide',
          'nitric oxide',
          'no2'
        ]))
      FumeAgent.nox,
    if ((u.hasStem(const ['tlenk']) && u.hasStem(const ['wegl'])) ||
        u.hasAny(const ['tlenek wegla', 'carbon monoxide']) ||
        RegExp(r'\bCO\b').hasMatch(u.raw))
      FumeAgent.co,
  };
  final chemicalAmbiguous = (u.hasStem(const ['chrom']) &&
          !agents.contains(FumeAgent.crVI)) ||
      (u.hasStem(const ['cynk', 'zinc']) && !agents.contains(FumeAgent.znO)) ||
      (u.hasStem(const ['zelaz', 'iron']) && !agents.contains(FumeAgent.feOx));
  return {
    if (agents.isNotEmpty)
      'agent': agents.length == 1 ? agents.single.name : 'ambiguous',
    if (chemicalAmbiguous) 'agent': 'ambiguous',
    if ((u.hasStem(const ['metalicz', 'metallic']) &&
            u.hasStem(const ['nikl', 'nikiel', 'nickel', 'chrom'])) ||
        u.hasStem(const [
          'beryl',
          'beryllium',
          'rtec',
          'mercury',
          'azbest',
          'asbestos',
          'aceton',
          'acetone',
          'krzemion',
          'silica'
        ]) ||
        u.hasAny(const [
          'nikiel metaliczny',
          'metallic nickel',
          'chrom metaliczny',
          'chromium metal',
          'cr iii',
          'cr ii',
          'chrom iii',
          'chrom ii',
          'inne',
          'inny',
          'other',
          'not listed',
          'spoza tabeli'
        ]))
      'outside': true,
    if (u.hasStem(const ['gornictw', 'gornicz', 'mining', 'tunel', 'tunnel']) ||
        u.hasAny(const [
          'osha',
          'niosh',
          'acgih',
          'tlv',
          'pel',
          'usa',
          'us',
          'uk',
          'wielkiej brytanii',
          'niemiecki',
          'niemieckie',
          'germany',
          'holandii',
          'netherlands',
          'ue',
          'eu',
          'european',
          'unijne',
          'unijny'
        ]))
      'jurisdiction': 'outside',
    if (u.hasAny(const ['historical', 'historyczny', 'dawniej', 'wczesniej']) ||
        RegExp(r'\b(?:19\d{2}|20(?:0\d|1\d|2[0-5]|2[7-9]|[3-9]\d))\b')
            .hasMatch(u.folded))
      'historical': true,
    if (u.hasStem(
            const ['pomiar', 'zmierz', 'measured', 'porownaj', 'compare']) ||
        u.hasAny(const ['czy bezpiecznie', 'czy moge', 'can i', 'is it safe']))
      'assessment': true,
  };
}

class FumeOelSkill extends AssistantSkill {
  @override
  String get id => 'fume.oel';
  @override
  String get toolId => 'fume';
  @override
  AssistantTier get tier => AssistantTier.b;
  @override
  bool get answersQuestionsOnly => true;
  @override
  List<SkillExample> get examples => const [
        SkillExample('NDS manganu', 'Polish OEL for manganese'),
        SkillExample('NDSCh tlenku cynku', 'Polish STEL for zinc oxide'),
        SkillExample('NDS związków niklu', 'Polish OEL for nickel compounds'),
        SkillExample('NDS kadmu', 'Polish OEL for cadmium'),
        SkillExample('Pokaż NDS Cr(VI)', 'Show Polish OEL Cr(VI)'),
        SkillExample('NDS tlenku węgla', 'Polish OEL carbon monoxide'),
      ];
  @override
  List<SkillRejection> get rejections => const [
        SkillRejection('Otwórz dymy spawalnicze i odciąg',
            routesTo: 'tool.open'),
        SkillRejection('zapisz TIG 2 mm 60 A'),
        SkillRejection('spoiwo 316L ten sam TIG', routesTo: 'filler.pick'),
      ];
  @override
  SkillMatch? match(Utterance u, AssistantContext ctx) {
    if (!u.hasAny(const ['nds', 'ndsch', 'oel', 'stel', 'tlv', 'pel']) &&
        !(u.hasStem(const ['dopuszczaln']) &&
            u.hasStem(const ['stez', 'concentration']))) {
      return null;
    }
    if (isNegatedCommand(u) ||
        kCommandVerbRe.hasMatch(u.folded) ||
        u.hasStem(const ['przetlum', 'translat'])) {
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
    if (s['outside'] == true ||
        s['jurisdiction'] != null ||
        s['assessment'] == true ||
        s['historical'] == true) {
      return {...s, slot: 'unsupported'};
    }
    return s.containsKey(slot) ? s : null;
  }

  @override
  Future<SkillResult> run(SkillMatch m, AssistantContext ctx) async {
    final s = m.slots;
    if (s['outside'] == true ||
        s['jurisdiction'] != null ||
        s['historical'] == true) {
      return const FailedResult(
          AssistantText(
              'Ta tabela obejmuje wymienione składniki dymu i polski wykaz NDS opisany datą w aplikacji. Nie zastępuję innej substancji, kraju ani historycznego wydania tymi wartościami.',
              'This table covers the listed fume agents and the dated Polish OEL list in the app. These values cannot substitute another substance, jurisdiction or historical edition.'),
          reportMissingCapability: true);
    }
    if (s['assessment'] == true) {
      return const FailedResult(
          AssistantText(
              'Pytanie o pomiar lub bezpieczeństwo stanowiska wymaga osobnej oceny narażenia: substancji, frakcji, czasu i metody pobrania próbki. Sama tabela NDS tego nie potwierdza.',
              'Measurement or workplace safety questions require a separate exposure assessment: substance, fraction, averaging period and sampling method. The OEL table alone does not confirm safety.'),
          reportMissingCapability: true);
    }
    final a = FumeAgent.values.where((v) => v.name == s['agent']).firstOrNull;
    if (a == null) {
      return AskResult(
          'agent',
          const AssistantText(
              'Który dokładnie składnik? Rozróżnij np. Cr(VI) od chromu metalicznego i tlenek cynku od cynku. Wybierz składnik z tabeli.',
              'Which exact agent? Distinguish Cr(VI) from chromium metal and zinc oxide from zinc. Choose a table entry.'),
          partial: m,
          choices: [
            for (final v in FumeAgent.values)
              FollowUp(AssistantText(v.namePl, v.nameEn), 'skladnik ${v.name}'),
          ]);
    }
    if (a.nds == null) {
      return FailedResult(
          AssistantText(
              fumeOelReference(a, en: false), fumeOelReference(a, en: true)),
          reportMissingCapability: true);
    }
    return AnswerResult(
        AssistantAnswer(
            text: AssistantText(
                fumeOelReference(a, en: false), fumeOelReference(a, en: true)),
            source: const AssistantText(
                'Dz.U.2018 poz.1286; Dz.U.2026 poz.447; przepisy przejściowe Dz.U.2020 poz.61',
                'Polish regulations: Dz.U.2018 item1286; Dz.U.2026 item447; transitional provisions Dz.U.2020 item61')),
        show: ShowInModule(toolId, {'reference_agent': a.name}));
  }
}
