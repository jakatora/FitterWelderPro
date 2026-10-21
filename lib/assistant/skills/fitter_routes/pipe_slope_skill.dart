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
  if (length != null || u.hasStem(_lengthLabels)) {
    out['length_mm'] = length ?? double.nan;
  }
  if (rise != null || u.hasStem(_riseLabels)) {
    out['rise_mm'] = rise ?? double.nan;
  }
  final percentage = percentValue(u);
  if (percentage != null) out['slope_pct'] = percentage;
  if (percentage == null &&
      _edit.hasMatch(u.folded) &&
      u.hasStem(const ['nachylen', 'slope', 'procent', 'percent'])) {
    out['slope_pct'] = double.nan;
  }
  // One unlabelled length, e.g. "spadek 1% na 6 metrów". Never choose
  // arbitrarily between two different lengths.
  if (!out.containsKey('length_mm') && !out.containsKey('rise_mm')) {
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

final _edit = RegExp(
    r'^(?:(?:a|and|prosze|please|teraz|now)\s+)*(?:zmien|ustaw|change|set)\b');
final _clear =
    RegExp(r'^(?:(?:prosze|please)\s+)*(?:wyczysc|wyzeruj|clear|reset)\b');
final _clearCurrent = RegExp(
    r'^(?:(?:prosze|please)\s+)*(?:wyczysc|wyzeruj|clear|reset)(?:\s+(?:pola|dane|inputs|fields))?$');
const _recalculate = {
  'oblicz',
  'policz',
  'przelicz',
  'calculate',
  'recalculate',
  'oblicz to',
  'oblicz aktualny spadek',
  'przelicz spadek',
  'calculate current slope',
  'recalculate slope'
};
bool _topic(Utterance u) =>
    u.hasStem(const ['spad', 'nachylen', 'gradient']) ||
    u.hasAny(const ['pipe slope']);
bool _foreign(Utterance u) =>
    u.hasStem(const [
      'ciec',
      'cieci',
      'cut',
      'pila',
      'saw',
      'rolling',
      'tras',
      'route',
      'ukos',
      'bevel',
      'narys',
      'draw'
    ]) ||
    mentionsWeight(u);

// Include only the two independent inputs of the current mode. Editing its
// computed quantity selects an appropriate inverse calculation, never combines
// a fresh input with a stale derived result.
Map<String, Object?> _currentEdit(
    Map<String, Object?> current, Map<String, Object?> patch) {
  final mode = current['mode'];
  final s = <String, Object?>{
    if (mode != 'rise_to_length') 'length_mm': current['length_mm'],
    if (mode != 'length_to_rise') 'rise_mm': current['rise_mm'],
    if (mode != 'slope_from_lr') 'slope_pct': current['slope_pct'],
    ...patch,
  };
  String target = mode is String ? mode : 'length_to_rise';
  if (patch.length >= 2) {
    if (patch.containsKey('length_mm') && patch.containsKey('rise_mm')) {
      target = 'slope_from_lr';
    } else if (patch.containsKey('length_mm') &&
        patch.containsKey('slope_pct')) {
      target = 'length_to_rise';
    } else if (patch.containsKey('rise_mm') && patch.containsKey('slope_pct')) {
      target = 'rise_to_length';
    }
  } else if (mode == 'length_to_rise' && patch.containsKey('rise_mm') ||
      mode == 'rise_to_length' && patch.containsKey('length_mm')) {
    target = 'slope_from_lr';
  } else if (mode == 'slope_from_lr' && patch.containsKey('slope_pct')) {
    target = 'length_to_rise';
  }
  final derived = target == 'length_to_rise'
      ? 'rise_mm'
      : target == 'rise_to_length'
          ? 'length_mm'
          : 'slope_pct';
  if (patch.length < 3) {
    s.remove(derived);
  }
  s['native_mode'] = target;
  return s;
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
  Map<String, Object?> _intent(
      Utterance u, AssistantContext ctx, Map<String, Object?> slots) {
    if (slots.isEmpty) return slots;
    return {
      ...slots,
      'native_action': null,
      'native_edit': ctx.modules.activeToolId == toolId &&
              (_edit.hasMatch(u.folded) || u.isContinuation)
          ? Map<String, Object?>.unmodifiable(slots)
          : null,
    };
  }

  @override
  Map<String, Object?> slotsFrom(Utterance u, AssistantContext ctx) =>
      _foreign(u) ? const {} : _intent(u, ctx, _slots(u));
  @override
  SkillMatch? match(Utterance u, AssistantContext ctx) {
    if (explainedTool(u) != null ||
        _foreign(u) ||
        kOpenVerbAtStartRe.hasMatch(u.folded) ||
        kCommandVerbRe.hasMatch(u.folded)) {
      return null;
    }
    final active = ctx.modules.activeToolId == toolId;
    if (_clear.hasMatch(u.folded) &&
        (_topic(u) || active && _clearCurrent.hasMatch(u.folded))) {
      return SkillMatch(this, .96,
          slots: const {'native_action': 'clear'}, utterance: u);
    }
    if (active &&
        (_recalculate.contains(u.folded) ||
            _topic(u) &&
                _slots(u).isEmpty &&
                u.hasStem(const [
                  'oblicz',
                  'policz',
                  'przelicz',
                  'calculate',
                  'recalculate'
                ]))) {
      return SkillMatch(this, .96,
          slots: const {'native_edit': <String, Object?>{}}, utterance: u);
    }
    final slots = _slots(u);
    if (active && _edit.hasMatch(u.folded) && slots.isNotEmpty) {
      return SkillMatch(this, .96, slots: _intent(u, ctx, slots), utterance: u);
    }
    if (!_topic(u)) return null;
    final explicitCalculation =
        u.hasStem(const ['oblicz', 'policz', 'calculate', 'compute']);
    return SkillMatch(
        this, slots.isNotEmpty || explicitCalculation ? 0.91 : 0.65,
        slots: _intent(u, ctx, slots), utterance: u);
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
    if (m.slots['native_action'] == 'clear') {
      return const AnswerResult(
          AssistantAnswer(
              text: AssistantText(
                  'Wyczyszczono dane i wynik kalkulatora spadku.',
                  'Slope calculator inputs and result cleared.')),
          show: ShowInModule('pipe_slope', {'action': 'clear'}));
    }
    final patch = m.slots['native_edit'];
    if (patch is Map<String, Object?>) {
      final modules = ctx.modules;
      final current = modules is FieldModuleContext
          ? (modules as FieldModuleContext).inputFields(toolId)
          : null;
      if (current == null) {
        return const FailedResult(
            AssistantText(
                'Nie mogę odczytać bieżących danych spadku. Otwórz moduł i poczekaj na wczytanie.',
                'I cannot read the current slope inputs. Open the module and wait for it to load.'),
            reportMissingCapability: false);
      }
      m = m.copyWith(slots: _currentEdit(current, patch));
    }
    final s = m.slots;
    final nativeMode = s['native_mode'];
    if (nativeMode != null &&
        ['length_mm', 'rise_mm', 'slope_pct'].where((k) => s[k] is num).length <
            2) {
      final required = nativeMode == 'length_to_rise'
          ? ['length_mm', 'slope_pct']
          : nativeMode == 'rise_to_length'
              ? ['rise_mm', 'slope_pct']
              : ['length_mm', 'rise_mm'];
      for (final key in required) {
        if (s[key] is! num) {
          return AskResult(
              key,
              key == 'slope_pct'
                  ? const AssistantText(
                      'Podaj procent spadku.', 'Give the slope percentage.')
                  : key == 'rise_mm'
                      ? const AssistantText(
                          'Podaj wznios z jednostką, np. 60 mm.',
                          'Give the rise with a unit, e.g. 60 mm.')
                      : const AssistantText(
                          'Podaj długość w rzucie poziomym z jednostką, np. 6 m.',
                          'Give the horizontal run with a unit, e.g. 6 m.'),
              partial: m);
        }
      }
    }
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
