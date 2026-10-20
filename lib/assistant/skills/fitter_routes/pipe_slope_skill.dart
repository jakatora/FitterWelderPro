import '../../../domain/fitter/pipe_slope.dart';
import '../../core/skill.dart';
import '../core/skill_words.dart';
import '../core/explain_tool_skill.dart' show explainedTool;
import 'quantities.dart';

const _lengthLabels = ['dlugosc', 'dlugosci', 'odcinek', 'length', 'run'];
const _riseLabels = ['wznios', 'roznica', 'rise', 'drop'];
Map<String, Object?> _slots(Utterance u) {
  final out = <String, Object?>{};
  final length = lengthNear(u, _lengthLabels);
  final rise = lengthNear(u, _riseLabels);
  if (length != null) out['length_mm'] = length;
  if (rise != null) out['rise_mm'] = rise;
  final percentage = percentValue(u);
  if (percentage != null) out['slope_pct'] = percentage;
  // One unlabelled length, e.g. "spadek 1% na 6 metrów". Never choose
  // arbitrarily between two different lengths.
  if (length == null && rise == null) {
    final dimensions = <double>{};
    for (var i = 0; i + 1 < u.items.length; i++) {
      final scale = lengthUnitScale(u.items[i + 1].word);
      if (u.items[i].isNumber && scale != null) {
        dimensions.add(signedQuantity(u, i) * scale);
      }
    }
    if (dimensions.length == 1) out['length_mm'] = dimensions.single;
    if (dimensions.length > 1) out['length_mm'] = double.nan;
  }
  return out;
}

class PipeSlopeSkill extends AssistantSkill {
  @override
  String get id => 'pipe.slope';
  @override
  String get toolId => 'pipe_slope';
  @override
  AssistantTier get tier => AssistantTier.b;
  @override
  List<SkillExample> get examples => const [
        SkillExample('Oblicz spadek 1% na 6 metrów',
            'Calculate pipe slope 1% over 6 meters'),
        SkillExample('Spadek rury długość 6000 mm wznios 60 mm',
            'Pipe slope length 6000 mm rise 60 mm'),
        SkillExample(
            'Spadek rury wznios 60 mm i 1%', 'Pipe slope rise 60 mm and 1%'),
        SkillExample('Nachylenie rury długość 2 metry i 2%',
            'Pipe gradient length 2 meters and 2%'),
        SkillExample('Spadek rury długość 1,5 metra wznios 15 mm',
            'Pipe slope length 1.5 meters rise 15 mm'),
        SkillExample('Oblicz spadek rury', 'Calculate pipe slope'),
      ];
  @override
  List<SkillRejection> get rejections => const [
        SkillRejection('narysuj rurę 6 metrów'),
        SkillRejection('oblicz rolling offset 300 400'),
        SkillRejection('ile waży rura DN50'),
        SkillRejection('otwórz kalkulator spadku', routesTo: 'tool.open'),
      ];
  @override
  Map<String, Object?> slotsFrom(Utterance u, AssistantContext ctx) =>
      _slots(u);
  @override
  SkillMatch? match(Utterance u, AssistantContext ctx) {
    if (explainedTool(u) != null ||
        u.hasStem(const ['ciec', 'cieci', 'cut', 'pila', 'saw'])) {
      return null;
    }
    if (RegExp(r'^(?:otworz|pokaz|open|show)\b').hasMatch(u.folded)) {
      return null;
    }
    if (!u.hasStem(const ['spadek', 'nachylen', 'gradient']) &&
        !u.hasAny(const ['pipe slope'])) {
      return null;
    }
    final slots = _slots(u);
    final explicitCalculation =
        u.hasStem(const ['oblicz', 'policz', 'calculate', 'compute']);
    return SkillMatch(
        this, slots.isNotEmpty || explicitCalculation ? 0.91 : 0.65,
        slots: slots, utterance: u);
  }

  @override
  Map<String, Object?>? fillSlot(
      String slot, Utterance u, AssistantContext ctx) {
    final slots = _slots(u);
    if (slots.containsKey(slot)) return slots;
    if (u.hasStem([..._lengthLabels, ..._riseLabels]) || slot == 'slope_pct') {
      return slots.isEmpty ? null : slots;
    }
    if (slot == 'length_mm' || slot == 'rise_mm') {
      final lengths = <double>[];
      for (var i = 0; i + 1 < u.items.length; i++) {
        final scale = lengthUnitScale(u.items[i + 1].word);
        if (u.items[i].isNumber && scale != null) {
          lengths.add(signedQuantity(u, i) * scale);
        }
      }
      if (lengths.length == 1) return {slot: lengths.single};
    }
    return null;
  }

  @override
  Future<SkillResult> run(SkillMatch m, AssistantContext ctx) async {
    final s = m.slots;
    for (final key in ['length_mm', 'rise_mm', 'slope_pct']) {
      final value = s[key];
      if (value is num && (!value.isFinite || value <= 0)) {
        return AskResult(
            key,
            const AssistantText(
                'Podaj jedną dodatnią wartość z jednostką (mm, cm, m lub procent).',
                'Give one positive value with its unit (mm, cm, m or percent).'),
            partial: m);
      }
    }
    final length = (s['length_mm'] as num?)?.toDouble();
    final rise = (s['rise_mm'] as num?)?.toDouble();
    final slope = (s['slope_pct'] as num?)?.toDouble();
    final PipeSlopeResult? result;
    final String mode;
    if (length != null && rise != null) {
      result = slopeFromLengthAndRise(lengthMm: length, riseMm: rise);
      mode = 'slope_from_lr';
      if (slope != null &&
          result != null &&
          (result.slopePct - slope).abs() > 0.000001) {
        return const FailedResult(AssistantText(
            'Długość, wznios i procent spadku są ze sobą sprzeczne. Popraw dane.',
            'Length, rise and slope percentage conflict. Correct the inputs.'));
      }
    } else if (length != null && slope != null) {
      result = slopeRiseFromLength(lengthMm: length, slopePct: slope);
      mode = 'length_to_rise';
    } else if (rise != null && slope != null) {
      result = slopeLengthFromRise(riseMm: rise, slopePct: slope);
      mode = 'rise_to_length';
    } else {
      final key = length == null && rise == null ? 'length_mm' : 'slope_pct';
      return AskResult(
          key,
          key == 'length_mm'
              ? const AssistantText(
                  'Jaka jest długość w rzucie poziomym? Podaj jednostkę, np. 6 metrów.',
                  'What is the horizontal run? Include a unit, e.g. 6 meters.')
              : const AssistantText(
                  'Jaki procent spadku? Możesz też podać wznios, np. „wznios 60 mm”.',
                  'What slope percentage? You can also provide the rise, e.g. "rise 60 mm".'),
          partial: m);
    }
    if (result == null) {
      return const FailedResult(AssistantText(
          'Wynik poza zakresem. Sprawdź jednostki.',
          'Result out of range. Check the units.'));
    }
    return AnswerResult(
        AssistantAnswer(
            text: AssistantText(
                'Dla rzutu poziomego ${fmt(result.lengthMm, ctx.lang)} mm spadek ${fmt(result.slopePct, ctx.lang)}% daje różnicę wysokości ${fmt(result.riseMm, ctx.lang)} mm. To ${fmt(result.mmPerM, ctx.lang)} mm na metr.',
                'For a horizontal run of ${fmt(result.lengthMm, ctx.lang)} mm, ${fmt(result.slopePct, ctx.lang)}% slope gives ${fmt(result.riseMm, ctx.lang)} mm height difference. That is ${fmt(result.mmPerM, ctx.lang)} mm per meter.')),
        show: ShowInModule(toolId, {
          'mode': mode,
          'length_mm': result.lengthMm,
          'rise_mm': result.riseMm,
          'slope_pct': result.slopePct
        }));
  }
}
