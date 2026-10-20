import '../../../data/tungsten.dart';
import '../../core/skill.dart';
import '../core/explain_tool_skill.dart' show explainedTool;
import '../core/skill_words.dart';
import '../fitter_routes/quantities.dart';

Map<String, Object?> _slots(Utterance u) {
  final s = <String, Object?>{};
  if (u.hasAny(const ['mig', 'mag', 'mma', 'smaw', 'fcaw', 'saw'])) {
    s['other_process'] = true;
  }
  final currents = <double>{};
  for (var i = 0; i + 1 < u.items.length; i++) {
    if (u.items[i].isNumber &&
        const ['a', 'amp', 'amps', 'amper', 'ampery', 'amperow']
            .contains(u.items[i + 1].word)) {
      currents.add(signedQuantity(u, i));
    }
  }
  if (currents.isNotEmpty) {
    s['amps'] = currents.length == 1 ? currents.single : double.nan;
  }
  final polarities = <String>{};
  if (RegExp(r'\bdc\s*[-−–](?!\w)', caseSensitive: false).hasMatch(u.raw) ||
      u.hasAny(const [
        'dcen',
        'dc minus',
        'elektroda ujemna',
        'electrode negative',
        'minus na elektrodzie'
      ])) {
    polarities.add('dcen');
  }
  if (RegExp(r'\bdc\s*\+(?!\w)', caseSensitive: false).hasMatch(u.raw) ||
      u.hasAny(const [
        'dcep',
        'dc plus',
        'elektroda dodatnia',
        'electrode positive',
        'plus na elektrodzie'
      ])) {
    polarities.add('dcep');
  }
  if (u.hasAny(const [
    'ac',
    'prąd przemienny',
    'prad przemienny',
    'alternating current'
  ])) {
    polarities.add('ac');
  }
  if (polarities.isNotEmpty) {
    s['polarity'] = polarities.length == 1 ? polarities.single : 'ambiguous';
  }
  final materials = <String>{};
  if (u.hasStem(const ['nierdz', 'stainless', 'kwasow']) ||
      u.hasAny(const ['304l', '316l']) ||
      RegExp(r'\b(?:304|316|321|347)\b(?![.,]\d)(?!\s*(?:a\b|amp))',
              caseSensitive: false)
          .hasMatch(u.raw)) {
    materials.add('stainless');
  }
  if (u.hasStem(const ['alum', 'miedz', 'copper', 'tytan', 'titanium']) ||
      u.hasAny(const ['stal węglowa', 'stal weglowa', 'carbon steel'])) {
    materials.add('other');
  }
  if (materials.isNotEmpty) {
    s['material'] = materials.length == 1 ? materials.single : 'ambiguous';
  }
  final types = <String>{};
  for (final t in kTungstenTypes) {
    if (u.hasAny([
      t.code,
      t.isoCode,
      tungstenTipColor(t, english: false),
      tungstenTipColor(t, english: true)
    ])) {
      types.add(t.code);
    }
  }
  if (types.isNotEmpty) {
    s['electrode_type'] = types.length == 1 ? types.single : 'ambiguous';
  }
  for (final match
      in RegExp(r'\b(?:wla?|wce?|wth?|wzr?)\d+\b', caseSensitive: false)
          .allMatches(u.raw)) {
    if (!kTungstenTypes.any((t) =>
        t.code.toLowerCase() == match[0]!.toLowerCase() ||
        t.isoCode.toLowerCase() == match[0]!.toLowerCase())) {
      s['electrode_type'] = 'unknown';
    }
  }
  return s;
}

class TungstenPickSkill extends AssistantSkill {
  @override
  String get id => 'tungsten.pick';
  @override
  String get toolId => 'tungsten';
  @override
  AssistantTier get tier => AssistantTier.b;
  @override
  List<SkillExample> get examples => const [
        SkillExample('Dobierz wolfram TIG DC- nierdzewna 100 A',
            'Select tungsten TIG DCEN stainless 100 A'),
        SkillExample(
            'Dobierz wolfram DCEN 316L 75 A', 'Select tungsten DCEN 316L 75 A'),
        SkillExample('Oblicz średnicę wolframu', 'Calculate tungsten diameter'),
        SkillExample('Wolfram DC minus nierdzewka 150 A',
            'Tungsten DC minus stainless 150 A'),
        SkillExample('Dobierz wolfram DC- nierdzewna 250 A WT20',
            'Select tungsten DCEN stainless 250 A WT20'),
        SkillExample(
            'Wolfram DC- nierdzewna 400 A', 'Tungsten DCEN stainless 400 A'),
      ];
  @override
  List<SkillRejection> get rejections => const [
        SkillRejection('otwórz wolfram', routesTo: 'tool.open'),
        SkillRejection('dobierz filtr przyłbicy TIG 100 A',
            routesTo: 'shade.number'),
        SkillRejection('oblicz CE C 0,2 Mn 1 pozostałe zero grubość 15 mm',
            routesTo: 'preheat.ce'),
      ];
  @override
  SkillMatch? match(Utterance u, AssistantContext ctx) {
    if (explainedTool(u) != null ||
        kCommandVerbRe.hasMatch(u.folded) ||
        kOpenVerbAtStartRe.hasMatch(u.folded)) {
      return null;
    }
    if (!u.hasStem(const ['wolfram', 'tungsten'])) return null;
    if (u.hasAny(const ['kolor', 'colour', 'color']) &&
        !u.hasStem(const ['dobierz', 'select', 'pick'])) {
      return null;
    }
    final s = _slots(u);
    return SkillMatch(
        this,
        s.isNotEmpty ||
                u.hasStem(
                    const ['dobierz', 'oblicz', 'calculate', 'select', 'pick'])
            ? .96
            : .65,
        slots: s,
        utterance: u);
  }

  @override
  Map<String, Object?> slotsFrom(Utterance u, AssistantContext ctx) =>
      _slots(u);
  @override
  Map<String, Object?>? fillSlot(
      String slot, Utterance u, AssistantContext ctx) {
    final s = _slots(u);
    if (s.containsKey(slot)) return s;
    if (slot == 'electrode_type' &&
        u.hasAny(const ['pomiń', 'pomin', 'omit', 'default', 'domyślny'])) {
      return {slot: null};
    }
    if (slot == 'polarity' &&
        const ['minus', 'ujemna', 'negative'].contains(u.folded)) {
      return {'polarity': 'dcen'};
    }
    return null;
  }

  @override
  Future<SkillResult> run(SkillMatch m, AssistantContext ctx) async {
    AskResult ask(String k, String pl, String en) =>
        AskResult(k, AssistantText(pl, en), partial: m);
    final polarity = m.slots['polarity'], material = m.slots['material'];
    if (m.slots['other_process'] == true) {
      return const FailedResult(AssistantText(
          'Ten dobór dotyczy elektrody wolframowej TIG. Podany inny proces nie korzysta z tego kalkulatora.',
          'This selection is for a TIG tungsten electrode. The other supplied process does not use this calculator.'));
    }
    if (polarity == 'ac' || polarity == 'dcep') {
      return const FailedResult(
          AssistantText(
              'Tabela średnic w aplikacji dotyczy TIG DC−, elektroda ujemna. Nie ma tu tabeli doboru średnicy dla AC ani DC+.',
              'The app diameter table is for TIG DC−, electrode negative. It has no AC or DC+ diameter selection table.'),
          reportMissingCapability: true);
    }
    if (polarity != 'dcen') {
      return ask(
          'polarity',
          'Jaki rodzaj prądu i biegunowość? Tabela jest dla TIG DC− (elektroda ujemna). Samo „DC” nie określa biegunowości.',
          'What current type and polarity? The table is for TIG DC− (electrode negative). “DC” alone does not specify polarity.');
    }
    if (material == 'other') {
      return const FailedResult(
          AssistantText(
              'Ta tabela średnic dotyczy stali nierdzewnej DC−. Brak osobnej tabeli dla podanego materiału.',
              'This diameter table is for stainless steel DC−. No separate table for the supplied material is available.'),
          reportMissingCapability: true);
    }
    if (material != 'stainless') {
      return ask(
          'material',
          'Jaki materiał spawasz? Ta tabela dotyczy stali nierdzewnej (np. 304L lub 316L).',
          'What material are you welding? This table is for stainless steel (e.g. 304L or 316L).');
    }
    final amps = m.slots['amps'];
    if (amps is! num || !amps.isFinite || amps <= 0) {
      return ask('amps', 'Podaj prąd spawania z jednostką A, np. 100 A.',
          'Give welding current with unit A, e.g. 100 A.');
    }
    if (amps < kTungstenSizes.first.minA || amps > kTungstenSizes.last.maxA) {
      return const FailedResult(
          AssistantText(
              'Prąd jest poza tabelą 15–400 A. Nie dobieram średnicy przez przedłużenie skrajnego wiersza.',
              'Current is outside the 15–400 A table. I will not select a diameter by extending an end row.'),
          reportMissingCapability: true);
    }
    final typeName = m.slots['electrode_type'];
    if (typeName == 'unknown') {
      return const FailedResult(
          AssistantText(
              'Tego typu elektrody nie ma w danych aplikacji. Nie zastępuję go domyślnym typem.',
              'This electrode type is missing from the app data. I will not replace it with a default type.'),
          reportMissingCapability: true);
    }
    if (typeName == 'ambiguous') {
      return ask(
          'electrode_type',
          'Podaj jeden typ elektrody albo pomiń wybór typu.',
          'Give one electrode type or omit the type choice.');
    }
    if (typeName == 'WP' || typeName == 'WZ8') {
      return const FailedResult(AssistantText(
          'WP/WZ8 są w tej aplikacji opisane dla AC; nie używam ich jako doboru do nierdzewnej DC−.',
          'WP/WZ8 are listed for AC in this app; I will not select them for stainless DC−.'));
    }
    if (typeName == 'WC20') {
      return const FailedResult(
          AssistantText(
              'WC20 ma opis w aplikacji, ale ta tabela prądowa dotyczy elektrod lantanowanych/torowanych. Brak osobnej tabeli średnic WC20.',
              'WC20 has a description in the app, but this current table covers lanthanated/thoriated electrodes. A separate WC20 diameter table is unavailable.'),
          reportMissingCapability: true);
    }
    final pick = sizeForCurrent(amps.toDouble())!;
    final extras = tungstenExtrasFor(pick.diaMm)!;
    final type = tungstenTypeByCode(typeName as String? ?? 'WL20')!;
    return AnswerResult(
        AssistantAnswer(
            text: AssistantText(
                'TIG DC−, nierdzewna, ${fmt(amps.toDouble(), ctx.lang)} A: wolfram Ø ${fmt(pick.diaMm, ctx.lang)} mm (pasmo ${pick.minA}–${pick.maxA} A). ${type.code} / ${type.isoCode}: ${type.notePl} Punkt startowy: dysza ${extras.cup}, argon ${extras.argonFlow}, szlif ${extras.tipAngle}. Zweryfikuj z kartą elektrody i WPS; przepływ dotyczy palnika, nie podpurki.',
                'TIG DC−, stainless, ${fmt(amps.toDouble(), ctx.lang)} A: tungsten Ø ${fmt(pick.diaMm, ctx.lang)} mm (band ${pick.minA}–${pick.maxA} A). ${type.code} / ${type.isoCode}: ${type.noteEn} Starting point: cup ${extras.cup}, argon ${extras.argonFlow}, tip ${extras.tipAngle}. Verify against the electrode datasheet and WPS; flow is for the torch, not back purging.'),
            source: const AssistantText(
                'Tabela DC− stali nierdzewnej w aplikacji; ISO 6848:2015: oznaczenia typów, nie źródło pasm prądu.',
                'App stainless DC− table; ISO 6848:2015: electrode designations, not the source of current bands.')),
        show: ShowInModule(toolId, {'amps': amps.toDouble()}));
  }
}
