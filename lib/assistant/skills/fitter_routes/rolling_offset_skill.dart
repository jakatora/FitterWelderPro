import '../../../domain/fitter/rolling_offset.dart';
import '../../../utils/decimal_parse.dart';
import '../../core/skill.dart';
import '../core/skill_words.dart';
import '../core/explain_tool_skill.dart' show explainedTool;
import 'quantities.dart';

const _rise = ['rise', 'wznios', 'wysokosc'];
const _spread = ['spread', 'odsuniecie', 'przesuniecie', 'rozsuniecie'];
Map<String, Object?> _slots(Utterance u) {
  final result = <String, Object?>{};
  final rise = lengthNear(u, _rise);
  final spread = lengthNear(u, _spread);
  if (rise != null) result['rise_mm'] = rise;
  if (spread != null) result['spread_mm'] = spread;
  final angles = <double>{};
  for (var i = 0; i < u.items.length; i++) {
    if (!u.items[i].isNumber) continue;
    final before = i > 0 ? u.items[i - 1].word : '';
    final after = i + 1 < u.items.length ? u.items[i + 1].word : '';
    if (['kat', 'angle', 'elbow', 'kolano'].contains(before) ||
        after.startsWith('stopn') ||
        after.startsWith('degree') ||
        after == 'deg') {
      angles.add(signedQuantity(u, i));
    }
  }
  for (final m in RegExp(r'(-?\d+(?:[.,]\d+)?)\s*°').allMatches(u.raw)) {
    angles.add(parseDecimal(m[1]!)!);
  }
  if (angles.isNotEmpty) {
    result['angle_deg'] = angles.length == 1 ? angles.single : double.nan;
  }
  return result;
}

class RollingOffsetSkill extends AssistantSkill {
  @override
  String get id => 'rolling.offset';
  @override
  String get toolId => 'rolling_offset';
  @override
  AssistantTier get tier => AssistantTier.b;
  @override
  List<SkillExample> get examples => const [
        SkillExample(
            'Rolling offset wznios 300 mm odsunięcie 400 mm kąt 45 stopni',
            'Rolling offset rise 300 mm spread 400 mm angle 45 degrees'),
        SkillExample('Oblicz rolling offset', 'Calculate rolling offset'),
        SkillExample(
            'Rolling offset wznios 30 cm odsunięcie 40 cm kąt 30 stopni',
            'Rolling offset rise 30 cm spread 40 cm angle 30 degrees'),
        SkillExample(
            'Rolling offset wznios 1 metr odsunięcie 2 metry kąt 60 stopni',
            'Rolling offset rise 1 meter spread 2 meters angle 60 degrees'),
        SkillExample(
            'Rolling offset wznios 300 mm odsunięcie 400 mm kąt 90 stopni',
            'Rolling offset rise 300 mm spread 400 mm angle 90 degrees'),
        SkillExample('Rolling offset wznios 150 mm odsunięcie 200 mm',
            'Rolling offset rise 150 mm spread 200 mm'),
      ];
  @override
  List<SkillRejection> get rejections => const [
        SkillRejection('otwórz rolling offset', routesTo: 'tool.open'),
        SkillRejection('spadek rury 1% na 6 metrów', routesTo: 'pipe.slope'),
        SkillRejection('narysuj rurę 300 mm i skręć 45 stopni'),
        SkillRejection('dodaj spoinę 45'),
      ];
  @override
  SkillMatch? match(Utterance u, AssistantContext ctx) {
    if (explainedTool(u) != null) return null;
    if (!u.hasAny(const ['rolling offset']) ||
        RegExp(r'^(?:otworz|pokaz|narysuj|dodaj|zapisz|open|show|draw|add|save)\b')
            .hasMatch(u.folded)) {
      return null;
    }
    final slots = _slots(u);
    final explicitCalculation =
        u.hasStem(const ['oblicz', 'policz', 'calculate', 'compute']);
    return SkillMatch(
        this, slots.isNotEmpty || explicitCalculation ? 0.92 : 0.65,
        slots: slots, utterance: u);
  }

  @override
  Map<String, Object?> slotsFrom(Utterance u, AssistantContext ctx) =>
      _slots(u);
  @override
  Map<String, Object?>? fillSlot(
      String slot, Utterance u, AssistantContext ctx) {
    final s = _slots(u);
    if (s.isNotEmpty) return s;
    if (slot == 'rise_mm' || slot == 'spread_mm') {
      final values = <double>[];
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
    for (final key in ['rise_mm', 'spread_mm', 'angle_deg']) {
      final value = m.slots[key];
      final valid = value is num &&
          value.isFinite &&
          (key == 'angle_deg'
              ? rollingOffsetAngleValid(value.toDouble())
              : value > 0);
      if (valid) continue;
      return AskResult(
          key,
          switch (key) {
            'rise_mm' => const AssistantText(
                'Jaki wznios? Podaj dodatni wymiar z jednostką, np. 300 mm.',
                'What rise? Give a positive dimension with a unit, e.g. 300 mm.'),
            'spread_mm' => const AssistantText(
                'Jakie odsunięcie boczne? Podaj dodatni wymiar z jednostką, np. 400 mm.',
                'What lateral spread? Give a positive dimension with a unit, e.g. 400 mm.'),
            _ => const AssistantText(
                'Jaki kąt kolan? Podaj jeden kąt większy od 5° i mniejszy od 89°, albo dokładnie 90°.',
                'What elbow angle? Give one angle greater than 5° and less than 89°, or exactly 90°.'),
          },
          partial: m);
    }
    final rise = (m.slots['rise_mm'] as num).toDouble();
    final spread = (m.slots['spread_mm'] as num).toDouble();
    final angle = (m.slots['angle_deg'] as num).toDouble();
    final r = rollingOffset(riseMm: rise, spreadMm: spread, angleDeg: angle);
    if (r == null) {
      return const FailedResult(AssistantText(
          'Wynik poza zakresem. Sprawdź wymiary.',
          'Result out of range. Check dimensions.'));
    }
    return AnswerResult(
        AssistantAnswer(
            lines: [
              AnswerLine(
                  const AssistantText('Rzut wzdłuż osi (Run)', 'Axial run'),
                  '${fmt(r.runMm, ctx.lang)} mm'),
              AnswerLine(
                  const AssistantText('Obrót od pionu', 'Roll from vertical'),
                  '${fmt(r.rollFromVerticalDeg, ctx.lang)}°'),
              if (r.multiplierWarning)
                const AnswerLine(AssistantText('Uwaga', 'Warning'),
                    'Travel multiplier > 10'),
            ],
            text: AssistantText(
                'Rzeczywiste odsunięcie: ${fmt(r.trueOffsetMm, ctx.lang)} mm. Odległość między punktami przecięcia osi kolan (Travel): ${fmt(r.travelMm, ctx.lang)} mm. To nie jest długość rury do cięcia.',
                'True offset: ${fmt(r.trueOffsetMm, ctx.lang)} mm. Distance between elbow centerline intersection points (Travel): ${fmt(r.travelMm, ctx.lang)} mm. This is not the pipe cut length.')),
        show: ShowInModule(toolId,
            {'rise_mm': rise, 'spread_mm': spread, 'angle_deg': angle}));
  }
}
