import '../../../domain/fitter/pipe_slope.dart';
import '../../core/skill.dart';
import '../core/skill_words.dart';
import '../core/explain_tool_skill.dart' show explainedTool;
import 'quantities.dart';
import 'pipe_slope_ratio.dart';

const _lengthLabels = ['dlugosc', 'dlugosci', 'odcinek', 'length', 'run'];
const _riseLabels = ['wznios', 'roznica', 'rise', 'drop'];
Map<String, Object?> _slots(Utterance u) {
  final out = <String, Object?>{};
  final (ratio, dimensionInput) = pipeSlopeRatio(u);
  final length = lengthNear(dimensionInput, _lengthLabels);
  final rise = lengthNear(dimensionInput, _riseLabels);
  if (length != null || u.hasStem(_lengthLabels)) {
    out['length_mm'] = length ?? double.nan;
  }
  if (rise != null || u.hasStem(_riseLabels)) {
    out['rise_mm'] = rise ?? double.nan;
  }
  final explicit = percentValue(u);
  final percentage = ratio == null
      ? explicit
      : explicit != null &&
              (!explicit.isFinite ||
                  (explicit - ratio).abs() > 1e-12 * ratio.abs())
          ? double.nan
          : ratio;
  if (percentage != null) out['slope_pct'] = percentage;
  if (percentage == null &&
      _edit.hasMatch(u.folded) &&
      u.hasStem(const ['nachylen', 'slope', 'procent', 'percent'])) {
    out['slope_pct'] = double.nan;
  }
  // One unlabelled length, e.g. "spadek 1% na 6 metrów". Never choose
  // arbitrarily between two different lengths.
  if (!out.containsKey('length_mm') && !out.containsKey('rise_mm')) {
    final dimensionItems = dimensionInput;
    final dimensions = <double>{};
    for (var i = 0; i + 1 < dimensionItems.items.length; i++) {
      final scale = lengthUnitScale(dimensionItems.items[i + 1].word);
      if (dimensionItems.items[i].isNumber && scale != null) {
        dimensions.add(signedQuantity(dimensionItems, i) * scale);
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
      'draw',
      // Nachylenie czoła kołnierza spoola to tolerancja prefabrykacji.
      'spool',
      'czola',
      'czolo'
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

final _copy = RegExp(r'^(?:(?:prosze|please)\s+)*(?:skopiuj|kopiuj|copy)\b');
final _formula =
    RegExp(r'^(?:(?:prosze|please)\s+)*(?:pokaz|otworz|show|open)\b');
bool _copyWords(Utterance u) => u.items.every((i) => const {
      'prosze',
      'please',
      'mi',
      'me',
      'skopiuj',
      'kopiuj',
      'copy',
      'wynik',
      'wyniki',
      'results',
      'wszystkie',
      'all',
      'do',
      'schowka',
      'to',
      'clipboard',
      'oraz',
      'result',
      'glowny',
      'main',
      'spadek',
      'spadku',
      'rury',
      'pipe',
      'slope',
      'kalkulatora',
      'calculator',
      'the',
      'aktualny',
      'current',
      'wznios',
      'rise',
      'dlugosc',
      'length',
      'run',
      'kat',
      'angle',
      'nachylenia',
      'nachylenie',
      'procent',
      'percentage',
      'percent',
      'mm',
      'na',
      'metr',
      'per',
      'meter',
      'metre',
      'milimetry',
      'i',
      'and',
      'lub',
      'or',
    }.contains(i.word));
bool _formulaWords(Utterance u) => u.items.every((i) => const {
      'prosze',
      'please',
      'mi',
      'me',
      'pokaz',
      'otworz',
      'show',
      'open',
      'wzory',
      'wzor',
      'wzorow',
      'formula',
      'formulas',
      'zrodlo',
      'source',
      'objasnienie',
      'explanation',
      'na',
      'dla',
      'for',
      'spadku',
      'spadek',
      'rury',
      'pipe',
      'slope',
      'the',
      'of',
    }.contains(i.word));
Set<String> _copyFields(Utterance u) {
  final angle = u.hasStem(const ['kat', 'angle']);
  return {
    if (u.hasStem(_riseLabels)) 'rise_mm',
    if (u.hasStem(_lengthLabels)) 'length_mm',
    if (angle) 'angle_deg',
    if (!angle &&
        (u.hasStem(const ['procent', 'percent', 'nachylen']) ||
            u.hasStem(const ['slope']) && !u.hasStem(const ['result'])))
      'slope_pct',
    if (u.hasAny(const [
      'mm na metr',
      'milimetry na metr',
      'mm per meter',
      'mm per metre'
    ]))
      'mm_per_m',
  };
}

String? _requestedPreset(Utterance u, {bool bare = false}) {
  final text = u.folded.replaceFirst(
      RegExp(r'\s+(?:w kalkulatorze spadku rury|for pipe slope)$'), '');
  final prefix = RegExp(
      r'^(?:(?:prosze|please)\s+)*(?:wybierz|ustaw|select|choose)\s+(?:skrot|preset)(?:\s+|$)');
  if (!bare && !prefix.hasMatch(text)) return null;
  final target = u.withRaw(text.replaceFirst(prefix, '').trim());
  final words = target.items
      .map((i) => i.isNumber
          ? i.value.toString().replaceFirst(RegExp(r'\.0$'), '')
          : i.word)
      .join(' ');
  for (final p in pipeSlopePresets) {
    final denominator = p.$2.split(':').last;
    if (words == p.$1 ||
        words == '${p.$1} procent' ||
        words == '${p.$1} percent' ||
        words == '1 $denominator' ||
        words == '1 do $denominator' ||
        words == '1 in $denominator') {
      return p.$1;
    }
  }
  return 'missing';
}

String? _requestedMode(Utterance u) {
  final qualified = u.folded.replaceFirst(
      RegExp(r'\s+(?:w kalkulatorze spadku rury|for pipe slope)$'), '');
  final text = qualified.replaceFirst(
      RegExp(
          r'^(?:(?:prosze|please)\s+)*(?:(?:zmien|ustaw)\s+tryb(?:\s+na)?|(?:change|set)\s+mode(?:\s+to)?|tryb|mode)\s+'),
      '');
  if (text == qualified) return null;
  return switch (text) {
    'dlugosc do wznios' ||
    'dlugosc do wzniosu' ||
    'obliczanie wzniosu' ||
    'length to rise' ||
    'calculate rise' =>
      'length_to_rise',
    'wznios do dlugosci' ||
    'obliczanie dlugosci' ||
    'rise to length' ||
    'calculate length' =>
      'rise_to_length',
    'wyznacz procent' ||
    'wyznacz %' ||
    'obliczanie procentu spadku' ||
    'find slope percent' ||
    'find slope %' ||
    'calculate slope percentage' =>
      'slope_from_lr',
    _ => null,
  };
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
        SkillExample('Oblicz spadek 1:150 na 6 metrów',
            'Calculate pipe slope 1:150 over 6 meters'),
        SkillExample('Spadek jeden do stu na 6 metrów',
            'Pipe slope one in one hundred over 6 meters'),
        SkillExample('Ustaw tryb obliczanie wzniosu w kalkulatorze spadku rury',
            'Set mode to calculate rise for pipe slope'),
        SkillExample(
            'Ustaw tryb obliczanie długości w kalkulatorze spadku rury',
            'Set mode to calculate length for pipe slope'),
        SkillExample('Ustaw tryb wyznacz procent w kalkulatorze spadku rury',
            'Set mode to find slope percent for pipe slope'),
        SkillExample('Pokaż wzory spadku rury', 'Show pipe slope formulas'),
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
      'module_action': null,
      'copy_field': null,
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
    final active = ctx.modules.activeToolId == toolId;
    final topic = _topic(u);
    if (!_foreign(u) && (active || topic)) {
      final preset = _requestedPreset(u);
      if (preset != null) {
        return SkillMatch(this, .98,
            slots: {'module_action': 'preset:$preset'}, utterance: u);
      }
      final mode = _requestedMode(u);
      if (mode != null) {
        return SkillMatch(this, .98,
            slots: {'module_action': 'mode:$mode'}, utterance: u);
      }
      if (_copy.hasMatch(u.folded) && _copyWords(u)) {
        final fields = _copyFields(u);
        return SkillMatch(this, .98,
            slots: {
              'module_action': 'copy',
              'copy_field':
                  u.hasAny(const ['wyniki', 'results', 'wszystkie', 'all'])
                      ? 'ambiguous'
                      : fields.isEmpty
                          ? 'result'
                          : fields.length == 1
                              ? fields.single
                              : 'ambiguous'
            },
            utterance: u);
      }
      if (_formula.hasMatch(u.folded) &&
          _formulaWords(u) &&
          u.hasStem(const ['wzor', 'formula'])) {
        return SkillMatch(this, .98,
            slots: const {'module_action': 'formula'}, utterance: u);
      }
    }
    if (explainedTool(u) != null ||
        _foreign(u) ||
        kOpenVerbAtStartRe.hasMatch(u.folded) ||
        kCommandVerbRe.hasMatch(u.folded)) {
      return null;
    }
    if (_clear.hasMatch(u.folded) &&
        (topic || active && _clearCurrent.hasMatch(u.folded))) {
      return SkillMatch(this, .96,
          slots: const {'native_action': 'clear'}, utterance: u);
    }
    if (active &&
        (_recalculate.contains(u.folded) ||
            topic &&
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
    if (!topic && !(active && _edit.hasMatch(u.folded))) return null;
    final slots = _slots(u);
    if (active && _edit.hasMatch(u.folded) && slots.isNotEmpty) {
      return SkillMatch(this, .96, slots: _intent(u, ctx, slots), utterance: u);
    }
    if (!topic) return null;
    final explicitCalculation =
        u.hasStem(const ['oblicz', 'policz', 'calculate', 'compute']);
    return SkillMatch(
        this, slots.isNotEmpty || explicitCalculation ? 0.91 : 0.65,
        slots: _intent(u, ctx, slots), utterance: u);
  }

  @override
  Map<String, Object?>? fillSlot(
      String slot, Utterance u, AssistantContext ctx) {
    final preset = _requestedPreset(u, bare: slot == 'preset');
    if (preset != null) {
      if (slot == 'preset' && preset == 'missing') return null;
      return {
        'module_action': 'preset:$preset',
        'native_action': null,
        'native_edit': null,
        'copy_field': null,
        'length_mm': null,
        'rise_mm': null,
        'slope_pct': null
      };
    }
    final requestedMode = _requestedMode(u);
    if (requestedMode != null) {
      return {
        'module_action': 'mode:$requestedMode',
        'native_action': null,
        'native_edit': null,
        'copy_field': null,
        'length_mm': null,
        'rise_mm': null,
        'slope_pct': null
      };
    }
    if (_copy.hasMatch(u.folded) && _copyWords(u) ||
        _formula.hasMatch(u.folded) &&
            _formulaWords(u) &&
            u.hasStem(const ['wzor', 'formula'])) {
      return null;
    }
    if (slot == 'copy_field') {
      if (_edit.hasMatch(u.folded) ||
          _copy.hasMatch(u.folded) ||
          _formula.hasMatch(u.folded) ||
          u.items.any((i) => i.isNumber) ||
          u.hasStem(const [
            'oblicz',
            'policz',
            'przelicz',
            'calculate',
            'recalculate'
          ])) {
        return null;
      }
      final fields = _copyFields(u);
      if (fields.length == 1) return {'copy_field': fields.single};
      if (fields.isEmpty && u.hasStem(const ['wynik', 'result'])) {
        return {'copy_field': 'result'};
      }
      return null;
    }
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
    final action = m.slots['module_action'];
    if (action == 'preset:missing') {
      return AskResult(
          'preset',
          const AssistantText(
              'Który dostępny skrót wybrać? 0,67% to zaokrąglony skrót 1:150.',
              'Which available preset should I select? 0.67% is the rounded 1:150 shortcut.'),
          partial: m,
          choices: [
            for (final p in pipeSlopePresets)
              FollowUp(
                  AssistantText.same('${p.$1}% (${p.$2})'),
                  AssistantText(
                          'wybierz skrót ${p.$2}', 'choose preset ${p.$2}')
                      .of(ctx.lang))
          ]);
    }

    if (action == 'copy' ||
        action == 'formula' ||
        action is String &&
            (action.startsWith('mode:') || action.startsWith('preset:'))) {
      final field = m.slots['copy_field'];
      if (action == 'copy' && field == 'ambiguous') {
        return AskResult(
            'copy_field',
            const AssistantText(
                'Który jeden wynik skopiować: wynik główny, kąt nachylenia czy mm na metr?',
                'Which single value should I copy: the main result, slope angle or mm per metre?'),
            partial: m,
            choices: [
              for (final label in const [
                AssistantText('Wynik główny', 'Main result'),
                AssistantText('Kąt', 'Angle'),
                AssistantText('mm na metr', 'mm per metre')
              ])
                FollowUp(label, label.of(ctx.lang)),
            ]);
      }
      if (action is String &&
          action.startsWith('preset:') &&
          ctx.modules.activeToolId != toolId) {
        return AnswerResult(
            const AssistantAnswer(
                text: AssistantText(
                    'Otwieram kalkulator i ustawiam wybrany skrót spadku.',
                    'Opening the calculator and selecting the slope preset.')),
            show: ShowInModule(
                toolId, {'action': 'preset', 'preset': action.substring(7)}));
      }
      if (action is String &&
          action.startsWith('mode:') &&
          ctx.modules.activeToolId != toolId) {
        return AnswerResult(
            const AssistantAnswer(
                text: AssistantText('Otwieram wybrany tryb kalkulatora spadku.',
                    'Opening the selected slope calculator mode.')),
            show: ShowInModule(
                toolId, {'action': 'mode', 'mode': action.substring(5)}));
      }
      if (action == 'formula' && ctx.modules.activeToolId != toolId) {
        return const AnswerResult(
            AssistantAnswer(
                text: AssistantText('Otwieram objaśnienie wzorów spadku rury.',
                    'Opening the pipe-slope formula explanation.')),
            show: ShowInModule('pipe_slope', {'action': 'formula'}));
      }
      final modules = ctx.modules;
      if (modules is! ModuleActionContext) {
        return const FailedResult(
            AssistantText(
                'Otwórz kalkulator spadku, aby wykonać tę czynność na jego aktualnym wyniku.',
                'Open the pipe-slope calculator to perform this action on its current result.'),
            reportMissingCapability: false);
      }
      final r = await (modules as ModuleActionContext).performModuleAction(
          toolId, action as String,
          field: action == 'copy' ? field as String? : null);
      return r.completed
          ? AnswerResult(AssistantAnswer(text: r.message))
          : FailedResult(r.message, reportMissingCapability: false);
    }
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
    var percentDisplay = result.slopePct.toStringAsFixed(6);
    if (!percentDisplay.contains('e') && percentDisplay.contains('.')) {
      percentDisplay = percentDisplay
          .replaceFirst(RegExp(r'0+$'), '')
          .replaceFirst(RegExp(r'\.$'), '');
    }
    if (double.tryParse(percentDisplay) == 0 && result.slopePct > 0) {
      percentDisplay = result.slopePct.toString();
    }
    final approximate = double.tryParse(percentDisplay) != result.slopePct;
    final percentPl =
        '${approximate ? 'około ' : ''}${percentDisplay.replaceAll('.', ',')}';
    final percentEn = '${approximate ? 'about ' : ''}$percentDisplay';
    return AnswerResult(
        AssistantAnswer(
            text: AssistantText(
                'Dla rzutu poziomego ${fmt(result.lengthMm, ctx.lang)} mm spadek $percentPl% daje różnicę wysokości ${fmt(result.riseMm, ctx.lang)} mm. To ${fmt(result.mmPerM, ctx.lang)} mm na metr.',
                'For a horizontal run of ${fmt(result.lengthMm, ctx.lang)} mm, $percentEn% slope gives ${fmt(result.riseMm, ctx.lang)} mm height difference. That is ${fmt(result.mmPerM, ctx.lang)} mm per meter.')),
        show: ShowInModule(toolId, {
          'mode': mode,
          'length_mm': result.lengthMm,
          'rise_mm': result.riseMm,
          'slope_pct': result.slopePct
        }),
        followUps:
            ctx.modules.activeToolId == toolId || ctx.modules.onHomeOrAssistant
                ? [
                    for (final label in [
                      const AssistantText('Kopiuj wynik', 'Copy result'),
                      AssistantText('Kopiuj kąt', 'Copy angle'),
                      AssistantText('Pokaż wzory', 'Show formulas'),
                      if (mode != 'slope_from_lr')
                        AssistantText('Wybierz skrót', 'Choose preset')
                    ])
                      FollowUp(label, label.of(ctx.lang))
                  ]
                : const []);
  }
}
