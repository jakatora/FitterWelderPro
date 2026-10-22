import '../../../data/heat_tint.dart';
import '../../core/skill.dart';
import '../core/explain_tool_skill.dart' show explainedTool;
import '../core/labelled_numbers.dart';

/// Kolor → poziom wzorca AWS D18.2. Kolejność ma znaczenie: „czerwono-
/// fioletowy” przed „fioletowy”, „szaroniebieski” przed „niebieski”/„szary”.
int? _levelFromColour(Utterance u) {
  final f = u.folded;
  if (RegExp(r'czerwono ?fiolet|red ?purple').hasMatch(f)) return 5;
  if (RegExp(r'szaro ?niebiesk|grey ?blue|gray ?blue').hasMatch(f)) return 8;
  if (RegExp(r'\bczarn|\bblack|\bluska|\bscale\b').hasMatch(f)) return 10;
  if (RegExp(r'\bniebiesk|\bblue\b').hasMatch(f)) return 7;
  if (RegExp(r'\bfiolet|\bpurple').hasMatch(f)) return 6;
  if (RegExp(r'\bszar|\bgrey\b|\bgray\b').hasMatch(f)) return 9;
  if (RegExp(r'\bbraz|\bbronze').hasMatch(f)) return 4;
  if (RegExp(r'ciemno ?zlot|\bzlot|\bgold').hasMatch(f)) return 3;
  if (RegExp(r'\bslomk|\bstraw').hasMatch(f)) return 2;
  if (RegExp(r'\bsrebrn|\bsilver|bez przebarwien|no tint').hasMatch(f)) {
    return 1;
  }
  return null;
}

Map<String, Object?> _slots(Utterance u) {
  final out = <String, Object?>{};
  final level = numberAfterLabel(
      u,
      (w) =>
          w.startsWith('poziom') ||
          w.startsWith('wzor') ||
          w == 'level' ||
          w == 'sample' ||
          w == 'nr' ||
          w == 'numer');
  final ppm = numberBeforeUnit(u, (w) => w == 'ppm');
  final colour = _levelFromColour(u);
  final levels = {
    if (level != null) level,
    if (ppm != null && ppm > 0) heatTintLevelForO2Ppm(ppm).level.toDouble(),
    if (colour != null) colour.toDouble(),
  };
  if (levels.isNotEmpty) {
    out['level'] = levels.length == 1 ? levels.single : double.nan;
  }
  if (ppm != null) out['o2_ppm'] = ppm;
  return out;
}

class HeatTintCheckSkill extends AssistantSkill {
  @override
  String get id => 'heat_tint.check';
  @override
  String get toolId => 'heat_tint';
  @override
  AssistantTier get tier => AssistantTier.b;
  @override
  List<SkillExample> get examples => const [
        SkillExample('Przebarwienie spoiny słomkowe czy przejdzie',
            'Light straw weld tint will it pass'),
        SkillExample('Nalot od środka niebieski co z tym',
            'Inside tint is blue what now'),
        SkillExample('Przebarwienia poziom 5 wzorca', 'Heat tint sample level 5'),
        SkillExample('Kolor spoiny brąz czy ok na spożywczy',
            'Weld colour bronze is it ok for food'),
        SkillExample('Przebarwienie przy 200 ppm tlenu',
            'Heat tint at 200 ppm oxygen'),
        SkillExample('Jaki poziom przebarwienia od środka rury',
            'Which heat tint level inside the pipe'),
      ];
  @override
  List<SkillRejection> get rejections => const [
        SkillRejection('otwórz przebarwienia', routesTo: 'tool.open'),
        SkillRejection('do czego służą przebarwienia', routesTo: 'tool.explain'),
        SkillRejection('jaki filtr przyłbicy do TIG 100 amper'),
      ];

  @override
  SkillMatch? match(Utterance u, AssistantContext ctx) {
    if (explainedTool(u) != null ||
        RegExp(r'^(?:otworz|pokaz|open|show|do czego)\b').hasMatch(u.folded)) {
      return null;
    }
    final tint = u.hasStem(const ['przebarw', 'nalot', 'tint', 'discolo']) ||
        (u.hasAny(const ['kolor spoiny', 'weld colour', 'weld color']));
    if (!tint) return null;
    final s = _slots(u);
    return SkillMatch(this, s.isNotEmpty ? .93 : .75, slots: s, utterance: u);
  }

  @override
  Map<String, Object?> slotsFrom(Utterance u, AssistantContext ctx) =>
      _slots(u);

  @override
  Map<String, Object?>? fillSlot(
      String slot, Utterance u, AssistantContext ctx) {
    final s = _slots(u);
    if (s.containsKey(slot)) return {slot: s[slot]};
    if (slot == 'level') {
      final n = u.items.where((i) => i.isNumber).toList();
      if (n.length == 1 && u.items.length <= 2) return {slot: n.single.value};
    }
    return null;
  }

  @override
  Future<SkillResult> run(SkillMatch m, AssistantContext ctx) async {
    final level = m.slots['level'];
    if (level is! num ||
        !level.isFinite ||
        level != level.roundToDouble() ||
        level < 1 ||
        level > 10) {
      return AskResult(
          'level',
          const AssistantText(
              'Jaki kolor od środka spoiny: srebrny, słomkowy, złoty, brąz, czerwono-fioletowy, fioletowy, niebieski, szaroniebieski, szary czy czarny? Albo numer wzorca 1–10.',
              'What colour inside the weld: silver, straw, gold, bronze, red-purple, purple, blue, grey-blue, grey or black? Or sample number 1–10.'),
          partial: m);
    }
    final l = kHeatTintLevels[level.toInt() - 1];
    var limit = kDefaultHeatTintLimit;
    try {
      limit = await loadHeatTintLimit();
    } catch (_) {}
    final (vPl, vEn) = switch (l.verdict) {
      HeatTintVerdict.pharma => ('typowo OK dla pharma', 'typically OK for pharma'),
      HeatTintVerdict.food => ('typowo OK dla spożywczego', 'typically OK for food'),
      HeatTintVerdict.marginal => ('graniczne', 'marginal'),
      HeatTintVerdict.reject => ('typowo odrzut', 'typically rejected'),
    };
    final within = l.level <= limit;
    return AnswerResult(
        AssistantAnswer(
            text: AssistantText(
                'Wzorzec ${l.level} — ${l.namePl} (${l.approxO2} O₂ w gazie formującym): $vPl. '
                '${within ? 'Mieści się w limicie projektu (do poziomu $limit).' : 'Powyżej limitu projektu (do poziomu $limit) — do wyjaśnienia z kontrolą.'} '
                'Oceniaj po numerze wzorca AWS D18.2; wiąże specyfikacja projektu / WPS.',
                'Sample ${l.level} — ${l.nameEn} (${l.approxO2} O₂ in the backing gas): $vEn. '
                '${within ? 'Within the project limit (up to level $limit).' : 'Above the project limit (up to level $limit) — clear it with inspection.'} '
                'Judge by the AWS D18.2 sample number; the project spec / WPS governs.')),
        show: ShowInModule(toolId, {'level': l.level}));
  }
}
