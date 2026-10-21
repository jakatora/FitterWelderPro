import '../../../i18n/app_language.dart';
import '../../core/skill.dart';
import '../../core/command_words.dart' show pendingReplyNeedsInterpretation;
import '../core/skill_words.dart' show fmt;
import '../fitter_routes/quantities.dart' show signedQuantity, lengthUnitScale;
import '../../../domain/welding/welder_calculator_input.dart';

const _names = <String, (String, String)>{
  'welds': ('liczbę spoin', 'number of welds'),
  'weld_minutes': ('czas spawania jednej spoiny', 'weld time per joint'),
  'torch_lpm': ('przepływ palnika', 'torch flow'),
  'pre_flow_s': ('czas wypływu wstępnego', 'pre-flow duration'),
  'post_flow_s': ('czas wypływu końcowego', 'post-flow duration'),
  'purge_lpm': ('przepływ gazu formującego', 'purge flow'),
  'purge_minutes': ('czas formowania jednej spoiny', 'purge time per joint'),
  'water_l': ('pojemność wodną butli', 'cylinder water capacity'),
  'fill_bar': ('ciśnienie napełnienia', 'fill pressure'),
  'reserve_bar': ('rezerwę ciśnienia', 'reserve pressure'),
  'current_bar': (
    'aktualne wskazanie manometru',
    'current cylinder gauge pressure'
  ),
  'od_mm': ('średnicę zewnętrzną', 'outside diameter'),
  'wall_mm': ('grubość ścianki', 'wall thickness'),
  'length_mm': ('długość odcinka', 'section length'),
  'flow_lpm': ('przepływ gazu formującego', 'purge flow'),
  'initial_ppm': ('początkowe stężenie O₂', 'initial O₂ concentration'),
  'target_ppm': (
    'docelowe stężenie O₂ z WPS/specyfikacji',
    'O₂ target from the WPS/specification'
  ),
};

enum _Unit { count, minutes, seconds, flow, litres, bar, ppm, length }

typedef _Field = ({List<String> labels, _Unit unit});
const _gasFields = <String, _Field>{
  'welds': (labels: ['spoiny', 'spoin', 'welds', 'joints'], unit: _Unit.count),
  'weld_minutes': (labels: ['spawanie', 'weldtime'], unit: _Unit.minutes),
  'torch_lpm': (labels: ['palnik', 'torch'], unit: _Unit.flow),
  'pre_flow_s': (labels: ['preflow'], unit: _Unit.seconds),
  'post_flow_s': (labels: ['postflow'], unit: _Unit.seconds),
  'purge_lpm': (labels: ['purgeflow'], unit: _Unit.flow),
  'purge_minutes': (labels: ['purgetime'], unit: _Unit.minutes),
  'water_l': (labels: ['butla', 'cylinder'], unit: _Unit.litres),
  'fill_bar': (labels: ['napelnienie', 'fill'], unit: _Unit.bar),
  'reserve_bar': (labels: ['rezerwa', 'reserve'], unit: _Unit.bar),
  'current_bar': (labels: ['manometr', 'gauge'], unit: _Unit.bar),
};
const _purgeFields = <String, _Field>{
  'od_mm': (labels: ['od'], unit: _Unit.length),
  'wall_mm': (labels: ['scianka', 'wall'], unit: _Unit.length),
  'length_mm': (labels: ['dlugosc', 'length'], unit: _Unit.length),
  'flow_lpm': (labels: ['przeplyw', 'flow'], unit: _Unit.flow),
  'initial_ppm': (labels: ['start', 'initial'], unit: _Unit.ppm),
  'target_ppm': (labels: ['cel', 'target'], unit: _Unit.ppm),
};
final _quantityLabels = {
  for (final f in [..._gasFields.values, ..._purgeFields.values]) ...f.labels
};
double? _scale(_Unit kind, String word) {
  final seconds =
      word == 's' || word.startsWith('sek') || word.startsWith('sec');
  final minutes = word.startsWith('min');
  final hours =
      word == 'h' || word.startsWith('hour') || word.startsWith('godz');
  return switch (kind) {
    _Unit.count => word.isEmpty ||
            _quantityLabels.contains(word) ||
            const {'szt', 'sztuk', 'pcs', 'spoine'}.contains(word)
        ? 1
        : null,
    _Unit.minutes => seconds
        ? 1 / 60
        : minutes
            ? 1
            : hours
                ? 60
                : null,
    _Unit.seconds => seconds
        ? 1
        : minutes
            ? 60
            : hours
                ? 3600
                : null,
    _Unit.flow => word == 'lpm' ? 1 : null,
    _Unit.litres =>
      word == 'l' || word.startsWith('litr') || word.startsWith('liter')
          ? 1
          : null,
    _Unit.bar => word == 'bar' || word == 'barg' ? 1 : null,
    _Unit.ppm => word == 'ppm' ? 1 : null,
    _Unit.length => lengthUnitScale(word),
  };
}

double? _flowScale(Utterance u, int number) {
  if (number + 1 >= u.items.length) return null;
  final volume = u.items[number + 1].word;
  if (volume == 'lpm') return 1;
  final litres = _scale(_Unit.litres, volume) != null
      ? 1.0
      : volume == 'ml' ||
              volume.startsWith('mililitr') ||
              volume.startsWith('millilitr') ||
              volume.startsWith('milliliter')
          ? 0.001
          : null;
  if (litres == null) return null;
  var denominator = number + 2;
  if (denominator < u.items.length &&
      const {'na', 'per', 'a'}.contains(u.items[denominator].word)) {
    denominator++;
  }
  if (denominator >= u.items.length || u.items[denominator].isNumber) {
    return null;
  }
  final minutes = _scale(_Unit.minutes, u.items[denominator].word);
  return minutes == null ? null : litres / minutes;
}

// A labelled quantity we do not understand is different from two competing
// values for one field. Preserve the former for AI; reject the latter locally.
bool _unparsedClause(Utterance u, int index) {
  if (index + 1 >= u.items.length ||
      u.items[index].isNumber ||
      !u.items[index + 1].isNumber) {
    return false;
  }
  final word = u.items[index].word;
  if (_quantityLabels.contains(word) ||
      const {
        'albo',
        'lub',
        'or',
        'and',
        'i',
        'zamiast',
        'rather',
        'than',
        'minus',
        'kg',
        'g',
        't',
        'a',
        'v'
      }.contains(word)) {
    return false;
  }
  return !_Unit.values
      .where((k) => k != _Unit.count)
      .any((k) => _scale(k, word) != null);
}

bool _requiresInterpretation(Utterance u, Map<String, Object?> slots) =>
    pendingReplyNeedsInterpretation(u) ||
    (slots.values.every((v) => v is num && v.isFinite) &&
        u.items.where((i) => i.isNumber).length > slots.length);

double? _number(Utterance u, _Field field) {
  final found = <double>{};
  for (var i = 0; i < u.items.length; i++) {
    if (u.items[i].isNumber || !field.labels.contains(u.items[i].word)) {
      continue;
    }
    var j = i + 1;
    if (field.unit == _Unit.count && i > 0 && u.items[i - 1].isNumber) {
      if (j < u.items.length && u.items[j].isNumber) {
        found.add(double.nan);
        continue;
      }
      j = i - 1;
    }
    while (j < u.items.length &&
        const {
          'na',
          'of',
          'is',
          'wynosi',
          'minus',
          'ma',
          'to',
          'po',
          'przez',
          'for'
        }.contains(u.items[j].word)) {
      j++;
    }
    if (j >= u.items.length || !u.items[j].isNumber) {
      if (field.unit == _Unit.count && i > 0 && u.items[i - 1].isNumber) {
        j = i - 1;
      } else {
        found.add(double.nan);
        continue;
      }
    }
    final unit = j + 1 < u.items.length ? u.items[j + 1].word : '';
    final rate = _flowScale(u, j);
    final nextClause = _unparsedClause(u, j + 1);
    final factor = field.unit == _Unit.flow
        ? rate
        : field.unit == _Unit.litres && rate != null
            ? null
            : field.unit == _Unit.count && nextClause
                ? 1.0
                : _scale(field.unit, unit);
    var extraNumber =
        field.unit == _Unit.count && j > i && i > 0 && u.items[i - 1].isNumber;
    if (!_quantityLabels.contains(unit) && !nextClause) {
      for (var k = j + 2; k < u.items.length; k++) {
        if (_quantityLabels.contains(u.items[k].word) ||
            _unparsedClause(u, k)) {
          break;
        }
        if (u.items[k].isNumber) {
          extraNumber = true;
          break;
        }
      }
    }
    found.add(factor == null ||
            extraNumber ||
            (j + 1 < u.items.length && u.items[j + 1].isNumber)
        ? double.nan
        : signedQuantity(u, j) * factor);
  }
  return found.isEmpty
      ? null
      : found.length == 1
          ? found.single
          : double.nan;
}

Map<String, Object?> _parse(
    Utterance original, Map<String, _Field> definitions) {
  final u = original
      .withRaw(original.raw.replaceAll(RegExp(r'[-−]\s*(?=\d)'), ' minus '));
  return {
    for (final e in definitions.entries)
      if (_number(u, e.value) case final value?) e.key: value
  };
}

bool _calculate(Utterance u) =>
    u.hasStem(const ['oblicz', 'policz', 'oszacuj', 'calculate', 'estimate']);
final _explainOrOpenRe = RegExp(
    r'^(?:otworz|pokaz|open|show|wyjasnij|explain|jak|how|co to|what is)\b');
bool _explainOrOpen(Utterance u) => _explainOrOpenRe.hasMatch(u.folded);

abstract class _WelderGasCalculation extends AssistantSkill {
  Map<String, _Field> get _definitions;
  @override
  String get toolId => 'welder_calculators';
  @override
  AssistantTier get tier => AssistantTier.b;
  @override
  bool get contextualEditsNeedAi => true;
  @override
  bool requiresInterpretationFor(Utterance u, Map<String, Object?> supplied) =>
      _requiresInterpretation(u, supplied);
  @override
  Map<String, Object?>? fillProposalSlot(String slot, Utterance command,
      Utterance original, AssistantContext ctx) {
    final values = fillSlot(slot, command, ctx);
    if (values == null) return null;
    if (!pendingReplyNeedsInterpretation(original) &&
        _requiresInterpretation(original, {slot: values[slot]})) {
      return null;
    }
    return values;
  }

  @override
  Map<String, Object?> slotsFrom(Utterance u, AssistantContext ctx) =>
      _parse(u, _definitions);
  @override
  Map<String, Object?>? fillSlot(
      String slot, Utterance u, AssistantContext ctx) {
    final fields = slotsFrom(u, ctx);
    if (fields.containsKey(slot)) return fields;
    final definition = _definitions[slot];
    if (definition == null) return null;
    final answer = _parse(
        u.withRaw('${definition.labels.first} ${u.raw}'), {slot: definition});
    final value = answer[slot];
    return value is num && value.isFinite ? answer : null;
  }

  AskResult ask(SkillMatch m, String slot, String pl, String en) =>
      AskResult(slot, AssistantText(pl, en), partial: m);
}

class GasConsumptionSkill extends _WelderGasCalculation {
  @override
  String get id => 'gas.consumption';
  @override
  Map<String, _Field> get _definitions => _gasFields;
  @override
  List<SkillExample> get examples => const [
        SkillExample(
            'Oblicz zużycie gazu spoiny 10 spawanie 2 min palnik 10 L/min',
            'Calculate gas consumption welds 10 weldtime 2 min torch 10 L/min'),
        SkillExample(
            'Oblicz zużycie gazu spoiny 10 spawanie 2 min palnik 10 L/min preflow 5 s postflow 10 s purgeflow 8 L/min purgetime 1 min butla 50 L napełnienie 200 bar rezerwa 10 bar',
            'Calculate gas consumption welds 10 weldtime 2 min torch 10 L/min preflow 5 s postflow 10 s purgeflow 8 L/min purgetime 1 min cylinder 50 L fill 200 bar reserve 10 bar'),
        SkillExample(
            'Oblicz zużycie gazu spoiny 10 spawanie 2 min palnik 10 L/min butla 50 L napełnienie 200 bar rezerwa 10 bar manometr 60 bar',
            'Calculate gas consumption welds 10 weldtime 2 min torch 10 L/min cylinder 50 L fill 200 bar reserve 10 bar gauge 60 bar'),
        SkillExample(
            'Oblicz zużycie gazu spoiny 4 spawanie 90 s palnik 8 L/min preflow 2 s postflow 6 s',
            'Calculate gas consumption welds 4 weldtime 90 s torch 8 L/min preflow 2 s postflow 6 s'),
        SkillExample(
            'Oblicz zużycie gazu spoiny dziesięć spawanie dwie minuty palnik dziesięć L/min',
            'Calculate gas consumption welds ten weldtime two minutes torch ten L/min'),
        SkillExample('Oblicz zużycie gazu', 'Calculate gas consumption'),
      ];
  @override
  List<SkillRejection> get rejections => const [
        SkillRejection('Jaki przepływ gazu ustawić?'),
        SkillRejection('Start purge timer 90 seconds',
            routesTo: 'timer.start', lang: AppLanguage.en),
        SkillRejection('Oblicz czas formowania', routesTo: 'purge.estimate'),
      ];
  @override
  SkillMatch? match(Utterance u, AssistantContext ctx) {
    if (_explainOrOpen(u) ||
        !u.hasAny(const [
          'zuzycie gazu',
          'zapotrzebowanie gazu',
          'gas consumption',
          'gas demand'
        ])) {
      return null;
    }
    final slots = slotsFrom(u, ctx);
    return _calculate(u) || slots.isNotEmpty
        ? SkillMatch(this, .94,
            slots: slots,
            utterance: u,
            requiresAiInterpretation: _requiresInterpretation(u, slots))
        : null;
  }

  @override
  Future<SkillResult> run(SkillMatch m, AssistantContext ctx) async {
    final values = <String, Object?>{
      ...GasCalculatorInput.defaults,
      ...m.slots
    };
    for (final key in _gasFields.keys) {
      if (key == 'current_bar' && !values.containsKey(key)) continue;
      final value = values[key];
      final zeroAllowed = const {
        'pre_flow_s',
        'post_flow_s',
        'purge_lpm',
        'purge_minutes',
        'reserve_bar'
      }.contains(key);
      if (value is! num ||
          !value.isFinite ||
          (zeroAllowed ? value < 0 : value <= 0)) {
        final unit = switch (_gasFields[key]!.unit) {
          _Unit.count => 'szt.',
          _Unit.minutes => 'min',
          _Unit.seconds => 's',
          _Unit.flow => 'L/min',
          _Unit.litres => 'L',
          _ => 'bar'
        };
        return ask(
            m,
            key,
            'Podaj ${_names[key]!.$1} w $unit. Liczba musi być ${zeroAllowed ? ">= 0" : "> 0"}.',
            'Give ${_names[key]!.$2} in ${unit == 'szt.' ? 'pcs' : unit}. Value must be ${zeroAllowed ? ">= 0" : "> 0"}.');
      }
    }
    if (((values['purge_lpm'] as num) > 0) !=
        ((values['purge_minutes'] as num) > 0)) {
      final key =
          (values['purge_lpm'] as num) > 0 ? 'purge_minutes' : 'purge_lpm';
      return ask(
          m,
          key,
          'Podaj przepływ purge w L/min oraz czas na spoinę w min; aby pominąć purge, podaj 0 dla obu.',
          'Give both purge flow in L/min and time per weld in min; use 0 for both to omit purge.');
    }
    if ((values['reserve_bar'] as num) >= (values['fill_bar'] as num)) {
      return ask(
          m,
          'reserve_bar',
          'Podaj rezerwę w bar mniejszą od napełnienia.',
          'Give reserve in bar below fill pressure.');
    }
    if (values['current_bar'] is num &&
        (values['current_bar'] as num) <= (values['reserve_bar'] as num)) {
      return ask(m, 'current_bar', 'Podaj manometr w bar powyżej rezerwy.',
          'Give gauge pressure in bar above reserve.');
    }
    try {
      final input = GasCalculatorInput.fromFields({'tab': 'gas', ...values});
      final g = input.consumption;
      return AnswerResult(
          AssistantAnswer(
              text: AssistantText(
                  'Zużycie gazu: ${fmt(g.totalL, ctx.lang)} L. Palnik ${fmt(g.torchL, ctx.lang)} L, pre/post-flow ${fmt(g.prePostFlowL, ctx.lang)} L, purge ${fmt(g.purgeL, ctx.lang)} L. Butle: ${fmt(input.bottles, ctx.lang)} (zaokrąglij w górę). Ustawienia kalkulatora: preflow ${values['pre_flow_s']} s, postflow ${values['post_flow_s']} s, butla ${values['water_l']} L / ${values['fill_bar']} bar, rezerwa ${values['reserve_bar']} bar.',
                  'Gas consumption: ${fmt(g.totalL, ctx.lang)} L. Torch ${fmt(g.torchL, ctx.lang)} L, pre/post-flow ${fmt(g.prePostFlowL, ctx.lang)} L, purge ${fmt(g.purgeL, ctx.lang)} L. Cylinders: ${fmt(input.bottles, ctx.lang)} (round up). Calculator settings: preflow ${values['pre_flow_s']} s, postflow ${values['post_flow_s']} s, cylinder ${values['water_l']} L / ${values['fill_bar']} bar, reserve ${values['reserve_bar']} bar.'),
              source: const AssistantText(
                  'Przybliżenie gazu doskonałego; sprawdź parametry butli i procedurę spawania.',
                  'Ideal-gas estimate; verify cylinder data and the welding procedure.')),
          show: ShowInModule(toolId, input.fields));
    } on FormatException {
      return const FailedResult(
          AssistantText('Nie obliczyłem zużycia. Sprawdź zakres danych.',
              'Could not calculate consumption. Check input ranges.'),
          reportMissingCapability: false);
    }
  }
}

class PurgeEstimateSkill extends _WelderGasCalculation {
  @override
  String get id => 'purge.estimate';
  @override
  bool get safetyCritical => true;
  @override
  Map<String, _Field> get _definitions => _purgeFields;
  @override
  List<SkillExample> get examples => const [
        SkillExample(
            'Oblicz czas formowania OD 60,3 mm ścianka 2 mm długość 1 m przepływ 10 L/min start 210000 ppm cel 20 ppm',
            'Estimate purge time OD 60.3 mm wall 2 mm length 1 m flow 10 L/min initial 210000 ppm target 20 ppm'),
        SkillExample('Oblicz czas formowania', 'Calculate purge time'),
        SkillExample(
            'Oblicz czas formowania OD 6,03 cm ścianka 2 mm długość 100 cm przepływ 6 L/min cel 50 ppm',
            'Calculate purge time OD 6.03 cm wall 2 mm length 100 cm flow 6 L/min target 50 ppm'),
        SkillExample(
            'Oblicz czas formowania OD 100 mm ścianka 3 mm długość 2 m przepływ 5 L/min start 1000 ppm cel 100 ppm',
            'Calculate purge time OD 100 mm wall 3 mm length 2 m flow 5 L/min initial 1000 ppm target 100 ppm'),
        SkillExample(
            'Oblicz czas formowania OD 60,3 mm ścianka dwa mm długość jeden m przepływ osiem L/min cel dwadzieścia ppm',
            'Calculate purge time OD 60.3 mm wall two mm length one m flow eight L/min target twenty ppm'),
        SkillExample(
            'Oblicz czas formowania OD 60,3 mm ścianka 2 mm długość 1 m przepływ 10 L/min',
            'Calculate purge time OD 60.3 mm wall 2 mm length 1 m flow 10 L/min'),
      ];
  @override
  List<SkillRejection> get rejections => const [
        SkillRejection('Start purge timer 90 seconds',
            routesTo: 'timer.start', lang: AppLanguage.en),
        SkillRejection('Ile czasu powinien trwać back purge?'),
        SkillRejection('Oblicz zużycie gazu', routesTo: 'gas.consumption'),
      ];
  @override
  SkillMatch? match(Utterance u, AssistantContext ctx) {
    if (_explainOrOpen(u) ||
        !(u.hasStem(const ['formowan']) || u.hasAny(const ['purge'])) ||
        !_calculate(u)) {
      return null;
    }
    final slots = slotsFrom(u, ctx);
    return SkillMatch(this, .94,
        slots: slots,
        utterance: u,
        requiresAiInterpretation: _requiresInterpretation(u, slots));
  }

  @override
  Future<SkillResult> run(SkillMatch m, AssistantContext ctx) async {
    final values = <String, Object?>{'initial_ppm': 210000.0, ...m.slots};
    for (final key in _purgeFields.keys) {
      final value = values[key];
      if (value is! num || !value.isFinite || value <= 0) {
        final unit = switch (_purgeFields[key]!.unit) {
          _Unit.length => 'mm',
          _Unit.flow => 'L/min',
          _ => 'ppm'
        };
        return ask(
            m,
            key,
            'Podaj $key w $unit, wartość większą od 0. Cel O₂ musi wynikać z WPS/specyfikacji.',
            'Give $key in $unit, above 0. The O₂ target must come from the WPS/specification.');
      }
    }
    if ((values['wall_mm'] as num) * 2 >= (values['od_mm'] as num)) {
      return ask(m, 'wall_mm', 'Podaj ściankę w mm mniejszą niż połowa OD.',
          'Give wall thickness in mm below half the OD.');
    }
    if ((values['target_ppm'] as num) >= (values['initial_ppm'] as num)) {
      return ask(
          m,
          'target_ppm',
          'Podaj cel w ppm mniejszy od stężenia początkowego.',
          'Give target ppm below the initial concentration.');
    }
    try {
      final input =
          PurgeCalculatorInput.fromFields({'tab': 'purge', ...values});
      final r = input.estimate;
      return AnswerResult(
          AssistantAnswer(
              text: AssistantText(
                  'Szacowany czas formowania: ${fmt(r.timeSec, ctx.lang)} s; objętość ${fmt(r.volumeL, ctx.lang)} L. Start ${fmt((values['initial_ppm'] as num).toDouble(), ctx.lang)} ppm, cel ${fmt((values['target_ppm'] as num).toDouble(), ctx.lang)} ppm. Timera nie uruchomiono.',
                  'Estimated purge time: ${fmt(r.timeSec, ctx.lang)} s; volume ${fmt(r.volumeL, ctx.lang)} L. Initial ${fmt((values['initial_ppm'] as num).toDouble(), ctx.lang)} ppm, target ${fmt((values['target_ppm'] as num).toDouble(), ctx.lang)} ppm. Timer has not been started.'),
              source: const AssistantText(
                  'Model idealnego wymieszania. Potwierdź wynik analizatorem O₂ i wymaganiami WPS; obliczenie nie potwierdza bezpieczeństwa przestrzeni zamkniętej.',
                  'Ideal mixing model. Verify with an O₂ analyser and WPS requirements; calculation does not establish confined-space safety.')),
          show: ShowInModule(toolId, input.fields));
    } on FormatException {
      return const FailedResult(
          AssistantText('Nie obliczyłem formowania. Sprawdź zakres danych.',
              'Could not calculate purge time. Check input ranges.'),
          reportMissingCapability: false);
    }
  }
}
