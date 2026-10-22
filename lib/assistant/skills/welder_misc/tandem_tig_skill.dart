import '../../../domain/welding/tandem_currents.dart';
import '../../../services/tandem_tig_estimate.dart';
import '../../core/skill.dart';
import '../core/explain_tool_skill.dart' show explainedTool;
import '../core/labelled_numbers.dart';
import '../core/skill_words.dart';
import '../fitter_routes/quantities.dart';

/// Grubości ścianek: „blacha 4 mm” → 4/4, „4 i 6 mm” / „4 mm i 6 mm” → 4/6.
(double, double)? _thicknesses(Utterance u) {
  final items = u.items;
  final values = <double>[];
  for (var i = 0; i < items.length; i++) {
    if (!items[i].isNumber) continue;
    final next = i + 1 < items.length ? items[i + 1].word : '';
    final scale = lengthUnitScale(next);
    // „4 i 6 mm”: liczba, spójnik, liczba z jednostką.
    final pairUnit = i + 3 < items.length &&
        const {'i', 'and', 'oraz', 'na'}.contains(next) &&
        items[i + 2].isNumber &&
        lengthUnitScale(items[i + 3].word) == 1;
    final before = i > 0 ? items[i - 1].word : '';
    if ((scale == 1 || pairUnit) &&
        !before.startsWith('szczelin') &&
        !before.startsWith('gap') &&
        !before.startsWith('land') &&
        !before.startsWith('prog') &&
        !before.startsWith('faz')) {
      values.add(items[i].value!);
    }
  }
  if (values.isEmpty) return null;
  if (values.length == 1) return (values.single, values.single);
  if (values.length == 2) return (values[0], values[1]);
  return (double.nan, double.nan);
}

Map<String, Object?> _slots(Utterance u) {
  final out = <String, Object?>{};
  final t = _thicknesses(u);
  if (t != null) {
    out['t1_mm'] = t.$1;
    out['t2_mm'] = t.$2;
  }
  final vertical = u.hasStem(const ['pion', 'vertical']);
  final horizontal = u.hasStem(const ['poziom', 'horizontal']);
  if (vertical != horizontal) {
    out['position'] = vertical ? 'VERTICAL' : 'HORIZONTAL';
  }
  final joints = {
    if (u.hasAny(const ['na styk', 'butt', 'bez szczeliny'])) 'BUTT',
    if (u.hasStem(const ['szczelin']) && !u.hasAny(const ['bez szczeliny']) ||
        u.hasAny(const ['gap']))
      'GAP',
    if (u.hasStem(const ['fazow', 'land', 'bevel', 'ukos'])) 'BEVEL',
  };
  if (joints.length == 1) out['joint_type'] = joints.single;
  final gap = numberAfterLabel(
      u, (w) => w.startsWith('szczelin') || w == 'gap',
      unit: (w) => w == 'mm');
  if (gap != null) out['gap_mm'] = gap;
  final land = numberAfterLabel(
      u, (w) => w == 'land' || w.startsWith('prog'),
      unit: (w) => w == 'mm');
  if (land != null) out['land_mm'] = land;
  return out;
}

class TandemTigSkill extends AssistantSkill {
  @override
  String get id => 'tandem.tig';
  @override
  String get toolId => 'welder_tanks';
  @override
  AssistantTier get tier => AssistantTier.b;
  @override
  List<SkillExample> get examples => const [
        SkillExample('Tandem TIG zbiornik pion blacha 3 mm na styk',
            'Tandem TIG tank vertical plate 3 mm butt joint'),
        SkillExample('Prąd tandem TIG poziom 4 i 5 mm szczelina 3 mm',
            'Tandem TIG current horizontal 4 and 5 mm gap 3 mm'),
        SkillExample('Tandem TIG poziom 6 mm fazowane land 2 mm',
            'Tandem TIG horizontal 6 mm bevelled land 2 mm'),
        SkillExample('Jaki prąd na tandem przy zbiorniku pion 3 mm na styk',
            'What current for tandem on a tank vertical 3 mm butt joint'),
        SkillExample('Parametry tandem TIG blacha 4 mm poziom na styk',
            'Tandem TIG parameters plate 4 mm horizontal butt joint'),
        SkillExample('Policz prąd tandem TIG', 'Calculate tandem TIG current'),
      ];
  @override
  List<SkillRejection> get rejections => const [
        SkillRejection('otwórz parametry zbiorniki', routesTo: 'tool.open'),
        SkillRejection('do czego służą parametry zbiorniki',
            routesTo: 'tool.explain'),
        SkillRejection('jaki prąd TIG do rury 60 na 2 mm'),
      ];

  @override
  SkillMatch? match(Utterance u, AssistantContext ctx) {
    if (explainedTool(u) != null ||
        RegExp(r'^(?:otworz|pokaz|open|show|do czego)\b').hasMatch(u.folded)) {
      return null;
    }
    if (!u.hasStem(const ['tandem'])) return null;
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
    if (slot == 't1_mm' && s.containsKey('t1_mm')) {
      return {'t1_mm': s['t1_mm'], 't2_mm': s['t2_mm']};
    }
    if (s.containsKey(slot)) return {slot: s[slot]};
    final numbers = u.items.where((i) => i.isNumber).toList();
    if (numbers.length != 1) return null;
    final v = numbers.single.value!;
    return switch (slot) {
      't1_mm' => {'t1_mm': v, 't2_mm': v},
      'gap_mm' || 'land_mm' => {slot: v},
      _ => null,
    };
  }

  @override
  Future<SkillResult> run(SkillMatch m, AssistantContext ctx) async {
    AskResult ask(String key, String pl, String en) =>
        AskResult(key, AssistantText(pl, en), partial: m);
    final t1 = m.slots['t1_mm'], t2 = m.slots['t2_mm'];
    if (t1 is! num || t2 is! num || !t1.isFinite || !t2.isFinite ||
        t1 <= 0 || t2 <= 0) {
      return ask('t1_mm', 'Jakie grubości ścianek w mm (np. 3 mm albo 4 i 5 mm)?',
          'Which wall thicknesses in mm (e.g. 3 mm or 4 and 5 mm)?');
    }
    final position = m.slots['position'];
    if (position != 'HORIZONTAL' && position != 'VERTICAL') {
      return ask('position', 'Pozycja: poziom czy pion?',
          'Position: horizontal or vertical?');
    }
    final joint = m.slots['joint_type'];
    if (joint != 'BUTT' && joint != 'GAP' && joint != 'BEVEL') {
      return ask('joint_type', 'Złącze: na styk, na szczelinę czy fazowane?',
          'Joint: butt, gap or bevelled?');
    }
    final gap = m.slots['gap_mm'];
    if (joint == 'GAP' && (gap is! num || !gap.isFinite || gap <= 0)) {
      return ask('gap_mm', 'Jaka szczelina w mm?', 'What gap in mm?');
    }
    final land = m.slots['land_mm'];
    if (joint == 'BEVEL' && (land is! num || !const [1, 2, 3].contains(land))) {
      return ask('land_mm', 'Jaki land (próg): 1, 2 czy 3 mm?',
          'Which land: 1, 2 or 3 mm?');
    }
    final est = await estimateTandemFromApproved(
        t1: t1.toDouble(),
        t2: t2.toDouble(),
        position: position as String,
        jointType: joint as String,
        landMm: joint == 'BEVEL' ? (land as num).toDouble() : null,
        gapMm: joint == 'BUTT' ? 0 : (gap as num?)?.toDouble() ?? 0);
    String f(num v) => fmt(v.toDouble(), ctx.lang);
    final fields = <String, Object?>{
      't1_mm': t1.toDouble(),
      't2_mm': t2.toDouble(),
      'position': position,
      'joint_type': joint,
      if (joint == 'GAP') 'gap_mm': (gap as num).toDouble(),
      if (joint == 'BEVEL') 'land_mm': (land as num).toDouble(),
    };
    final where = '${position == 'VERTICAL' ? 'pion' : 'poziom'}, '
        '${f(t1)}/${f(t2)} mm';
    final whereEn = '${position == 'VERTICAL' ? 'vertical' : 'horizontal'}, '
        '${f(t1)}/${f(t2)} mm';
    if (!est.hasResult) {
      final out = est.status == TandemStatus.outOfRange;
      return AnswerResult(
          AssistantAnswer(
              text: AssistantText(
                  out
                      ? 'Brak punktów startowych dla t = ${f(est.effMm)} mm ($where). Aplikacja nie ekstrapoluje — ustal prąd na próbce i wpisz do WPS.'
                      : 'Brak danych tandemu dla tej pozycji i złącza ($where). Aplikacja nie zgaduje prądu — ustal go na próbce.',
                  out
                      ? 'No starting points for t = ${f(est.effMm)} mm ($whereEn). The app does not extrapolate — set the current on a test piece and record it in the WPS.'
                      : 'No tandem data for this position and joint ($whereEn). The app does not guess the current — set it on a test piece.')),
          show: ShowInModule(toolId, fields));
    }
    final how = switch (est.status) {
      TandemStatus.exact => ('punkt startowy dla tej pary', 'starting point for this pair'),
      TandemStatus.sameEffective => (
          'punkt o tej samej grubości efektywnej',
          'point with the same effective thickness'
        ),
      TandemStatus.interpolated => (
          'interpolacja między punktami startowymi',
          'interpolation between starting points'
        ),
      TandemStatus.scaledFromHorizontal => (
          'pion przeskalowany z poziomu',
          'vertical scaled from horizontal'
        ),
      _ => ('', ''),
    };
    final warn = est.nonMonotonic || est.conflicting;
    return AnswerResult(
        AssistantAnswer(
            text: AssistantText(
                'Tandem TIG ($where): zewnętrzny z drutem ${est.outsideA!.round()} A, wewnętrzny bez drutu ${est.insideA!.round()} A — ${how.$1}.${warn ? ' Uwaga: punkty startowe są niespójne — sprawdź na próbce.' : ''} To wartości startowe: wiąże WPS i próbka.',
                'Tandem TIG ($whereEn): outside with wire ${est.outsideA!.round()} A, inside without wire ${est.insideA!.round()} A — ${how.$2}.${warn ? ' Warning: the starting points are inconsistent — check on a test piece.' : ''} These are starting values: the WPS and a test piece decide.')),
        show: ShowInModule(toolId, fields));
  }
}
