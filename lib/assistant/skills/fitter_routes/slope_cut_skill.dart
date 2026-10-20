import '../../../domain/fitter/fitter_calcs.dart';
import '../../../domain/fitter/pipe_size_lookup.dart'
    show odForDn, kDnOdSourcePl, kDnOdSourceEn;
import '../../core/skill.dart';
import '../core/explain_tool_skill.dart' show explainedTool;
import '../core/skill_words.dart';
import 'quantities.dart';

Map<String, Object?> _slots(Utterance u) {
  final od = lengthNear(u, const ['od', 'srednic', 'diameter']);
  final pct = percentValue(u);
  return {
    if (od != null) 'od_mm': od,
    if (pct != null) 'slope_pct': pct,
    if (u.dn() != null) 'dn': u.dn()
  };
}

class SlopeCutSkill extends AssistantSkill {
  @override
  String get id => 'slope.cut';
  @override
  String get toolId => 'slope_cut';
  @override
  AssistantTier get tier => AssistantTier.b;
  @override
  List<SkillExample> get examples => const [
        SkillExample('Oblicz cięcie pod spadek 2% OD 100 mm',
            'Calculate slope cut 2% OD 100 mm'),
        SkillExample('Cięcie pod spadek 1 procent średnica 60,3 mm',
            'Slope cut 1 percent diameter 60.3 mm'),
        SkillExample('Ustawienie piły na spadek 3% OD 200 mm',
            'Saw angle for slope 3% OD 200 mm'),
        SkillExample('Cięcie pod spadek 0% OD 50 mm', 'Slope cut 0% OD 50 mm'),
        SkillExample('Cięcie pod spadek 2% DN50', 'Slope cut 2% DN50'),
        SkillExample('Oblicz cięcie pod spadek', 'Calculate slope cut'),
      ];
  @override
  List<SkillRejection> get rejections => const [
        SkillRejection('otwórz cięcie pod spadek', routesTo: 'tool.open'),
        SkillRejection('do czego służy cięcie pod spadek',
            routesTo: 'tool.explain'),
        SkillRejection('spadek 1% na 6 metrów', routesTo: 'pipe.slope'),
      ];
  @override
  SkillMatch? match(Utterance u, AssistantContext ctx) {
    if (explainedTool(u) != null ||
        RegExp(r'^(?:otworz|pokaz|open|show)\b').hasMatch(u.folded)) {
      return null;
    }
    if (!u.hasStem(const ['spad', 'slope', 'gradient']) ||
        !u.hasStem(const ['ciec', 'cieci', 'cut', 'pil', 'saw'])) {
      return null;
    }
    final s = _slots(u);
    return SkillMatch(
        this,
        s.isNotEmpty || u.hasStem(const ['oblicz', 'policz', 'calculate'])
            ? .94
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
    if (s.containsKey(slot) || slot == 'od_mm' && s.containsKey('dn')) return s;
    if (slot == 'od_mm') {
      final values = <double>{};
      for (var i = 0; i + 1 < u.items.length; i++) {
        final scale = lengthUnitScale(u.items[i + 1].word);
        if (u.items[i].isNumber && scale != null) {
          values.add(signedQuantity(u, i) * scale);
        }
      }
      if (values.length == 1) return {slot: values.single};
    }
    return null;
  }

  @override
  Future<SkillResult> run(SkillMatch m, AssistantContext ctx) async {
    AskResult ask(String key, String pl, String en) =>
        AskResult(key, AssistantText(pl, en), partial: m);
    final dn = m.slots['dn'] as int?;
    final tableOd = dn == null ? null : odForDn(dn);
    final od = (m.slots['od_mm'] as num?)?.toDouble() ?? tableOd;
    if (od == null || !od.isFinite || od <= 0) {
      return ask(
          'od_mm',
          'Podaj średnicę zewnętrzną z jednostką, np. OD 100 mm, lub DN z tabeli.',
          'Give outside diameter with a unit, e.g. OD 100 mm, or a DN from the table.');
    }
    if (dn != null && (tableOd == null || (tableOd - od).abs() > 0.00001)) {
      return const FailedResult(AssistantText(
          'Podane DN i OD nie pasują do głównej serii tabeli. Podaj samo rzeczywiste OD z karty rury.',
          'DN and OD disagree with the main table series. Give only the actual pipe OD from its datasheet.'));
    }
    final pct = (m.slots['slope_pct'] as num?)?.toDouble();
    if (pct == null || !pct.isFinite || pct < 0) {
      return ask('slope_pct', 'Jaki spadek w procentach, np. 2%?',
          'What slope percentage, e.g. 2%?');
    }
    final angles = slopeSawAngles(pct);
    final delta = slopeCutDeltaMm(od, pct);
    if (!delta.isFinite) {
      return const FailedResult(AssistantText(
          'Wynik poza zakresem. Sprawdź dane.',
          'Result out of range. Check inputs.'));
    }
    return AnswerResult(
        AssistantAnswer(
            text: AssistantText(
                'Dla OD ${fmt(od, ctx.lang)} mm i spadku ${fmt(pct, ctx.lang)}% różnica góra–dół na przekroju wynosi ${fmt(delta, ctx.lang)} mm. Odchyl piłę o ${fmt(angles.fromSquareDeg, ctx.lang)}° od cięcia prostopadłego (skala 0° = prosto). Na skali 90° = prosto ustaw ${fmt(angles.scale90Deg, ctx.lang)}°.',
                'For OD ${fmt(od, ctx.lang)} mm and ${fmt(pct, ctx.lang)}% slope, top-to-bottom axial difference across the pipe is ${fmt(delta, ctx.lang)} mm. Tilt the saw ${fmt(angles.fromSquareDeg, ctx.lang)}° off square (scale 0° = square). On a scale where 90° = square, set ${fmt(angles.scale90Deg, ctx.lang)}°.'),
            source: dn == null
                ? null
                : const AssistantText(kDnOdSourcePl, kDnOdSourceEn)),
        show: ShowInModule(toolId, {'od_mm': od, 'slope_pct': pct}));
  }
}
