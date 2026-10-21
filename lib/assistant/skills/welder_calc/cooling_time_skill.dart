import '../../../domain/welding/cooling_time.dart';
import '../../../domain/welding/heat_input.dart';
import '../../core/skill.dart';
import '../core/explain_tool_skill.dart' show explainedTool;
import '../core/skill_words.dart';
import '../fitter_routes/quantities.dart';
import 'heat_input_skill.dart';

Map<String, Object?> _slots(Utterance u, AssistantContext ctx) {
  final s = heatInputQuantities(u);
  final q = <double>{}, temp = <double>{};
  for (var i = 0; i + 1 < u.items.length; i++) {
    if (!u.items[i].isNumber) continue;
    final unit = u.items[i + 1].word;
    if (unit == 'c' || unit.startsWith('cels')) temp.add(signedQuantity(u, i));
    if ((unit.startsWith('stopn') || unit.startsWith('degree')) &&
        i + 2 < u.items.length &&
        (u.items[i + 2].word == 'c' ||
            u.items[i + 2].word.startsWith('cels'))) {
      temp.add(signedQuantity(u, i));
    }
    if (unit == 'kj' ||
        unit.startsWith('kilodz') ||
        unit.startsWith('kilojoule')) {
      var j = i + 2;
      if (j < u.items.length && const ['na', 'per'].contains(u.items[j].word)) {
        j++;
      }
      if (j < u.items.length && lengthUnitScale(u.items[j].word) == 1) {
        q.add(signedQuantity(u, i));
      }
    }
  }
  if (q.isNotEmpty) s['q_kj_mm'] = q.length == 1 ? q.single : double.nan;
  if (temp.isNotEmpty) {
    s['preheat_c'] = temp.length == 1 ? temp.single : double.nan;
  }
  final d = lengthNear(u, const ['grubosc', 'thickness', 'blacha', 'plate']);
  if (d != null) s['thickness_mm'] = d;
  final shapes = <WeldShape>{};
  if (u.hasStem(const ['napawan']) || u.hasAny(const ['bead on plate'])) {
    shapes.add(WeldShape.beadOnPlate);
  }
  if (u.hasStem(const ['wypeln']) ||
      u.hasAny(const ['butt fill', 'butt weld fill run'])) {
    shapes.add(WeldShape.buttFillRun);
  }
  if (u.hasStem(const ['narozn', 'corner'])) shapes.add(WeldShape.filletCorner);
  if (u.hasStem(const ['teowa', 'teowej']) ||
      u.hasAny(const ['t joint', 'tee fillet'])) {
    shapes.add(WeldShape.filletTee);
  }
  if (shapes.isNotEmpty) {
    s['shape'] = shapes.length == 1 ? shapes.single.name : 'ambiguous';
  }
  void windowValue(String key, double value) {
    s[key] = s.containsKey(key) && s[key] != value ? double.nan : value;
  }

  for (var i = 0; i < u.items.length; i++) {
    if (!const ['okno', 'window'].contains(u.items[i].word)) continue;
    var j = i + 1;
    if (j < u.items.length && u.items[j].word == 'wps') j++;
    if (j < u.items.length && const ['od', 'from'].contains(u.items[j].word)) {
      j++;
    }
    if (j + 3 < u.items.length &&
        u.items[j].isNumber &&
        const ['do', 'to'].contains(u.items[j + 1].word) &&
        u.items[j + 2].isNumber &&
        (u.items[j + 3].word == 's' ||
            u.items[j + 3].word.startsWith('sekund') ||
            u.items[j + 3].word.startsWith('second'))) {
      windowValue('window_min_s', signedQuantity(u, j));
      windowValue('window_max_s', signedQuantity(u, j + 2));
    } else {
      windowValue('window_min_s', double.nan);
      windowValue('window_max_s', double.nan);
    }
  }
  for (var i = 0; i + 1 < u.items.length; i++) {
    final word = u.items[i].word;
    if (const ['min', 'minimum', 'max', 'maximum'].contains(word)) {
      var j = i + 1;
      if (j < u.items.length && u.items[j].word == 'minus') j++;
      if (j >= u.items.length) continue;
      if (u.items[j].isNumber &&
          j + 1 < u.items.length &&
          (u.items[j + 1].word == 's' ||
              u.items[j + 1].word.startsWith('sekund') ||
              u.items[j + 1].word.startsWith('second'))) {
        final key = word.startsWith('min') ? 'window_min_s' : 'window_max_s';
        final value = signedQuantity(u, j);
        windowValue(key, value);
      } else if (u.items[j].isNumber) {
        windowValue(word.startsWith('min') ? 'window_min_s' : 'window_max_s',
            double.nan);
      }
    }
  }
  if (u.hasAny(const ['użyj q', 'uzyj q', 'use q'])) s['input_mode'] = 'q';
  if (u
      .hasAny(const ['użyj parametrów', 'uzyj parametrow', 'use parameters'])) {
    s['input_mode'] = 'params';
  }
  return s;
}

class CoolingTimeSkill extends AssistantSkill {
  @override
  bool get currentFormEditsNeedAi => true;

  @override
  String get id => 'cooling.t85';
  @override
  String get toolId => 'cooling_time';
  @override
  AssistantTier get tier => AssistantTier.b;
  @override
  List<SkillExample> get examples => const [
        SkillExample(
            'Oblicz t8/5 Q 1 kJ/mm temperatura 100 C grubość 20 mm wypełnienie czołowej',
            'Calculate t8/5 Q 1 kJ/mm temperature 100 C thickness 20 mm butt fill'),
        SkillExample(
            'Czas stygnięcia Q 1,5 kJ/mm temperatura 20 C grubość 10 mm napawanie',
            'Cooling time Q 1.5 kJ/mm temperature 20 C thickness 10 mm bead on plate'),
        SkillExample(
            'Oblicz t8/5 MAG EN 28 V 250 A 350 mm/min temperatura 100 C grubość 20 mm wypełnienie',
            'Calculate t8/5 MAG EN 28 V 250 A 350 mm/min temperature 100 C thickness 20 mm butt fill'),
        SkillExample(
            't8/5 Q 1 kJ/mm temperatura 100 C grubość 5 mm pachwinowa narożna',
            't8/5 Q 1 kJ/mm temperature 100 C thickness 5 mm single-run corner fillet'),
        SkillExample(
            't8/5 Q 1 kJ/mm temperatura 100 C grubość 5 mm pachwinowa teowa min 5 s max 15 s',
            't8/5 Q 1 kJ/mm temperature 100 C thickness 5 mm tee fillet min 5 s max 15 s'),
        SkillExample('Oblicz t8/5', 'Calculate t8/5'),
      ];
  @override
  List<SkillRejection> get rejections => const [
        SkillRejection('otwórz czas stygnięcia', routesTo: 'tool.open'),
        SkillRejection('energia liniowa TIG EN 12 V 100 A 100 mm/min',
            routesTo: 'heat.input'),
        SkillRejection('oblicz dylatację długość 50 m delta 100 C 304L',
            routesTo: 'thermal.expansion'),
      ];
  @override
  SkillMatch? match(Utterance u, AssistantContext ctx) {
    if (explainedTool(u) != null ||
        kCommandVerbRe.hasMatch(u.folded) ||
        kOpenVerbAtStartRe.hasMatch(u.folded)) {
      return null;
    }
    if (!requestsCoolingTime(u)) {
      return null;
    }
    final s = _slots(u, ctx);
    return SkillMatch(this,
        s.isNotEmpty || u.hasStem(const ['oblicz', 'calculate']) ? .97 : .65,
        slots: s, utterance: u);
  }

  @override
  Map<String, Object?> slotsFrom(Utterance u, AssistantContext ctx) =>
      _slots(u, ctx);
  @override
  Map<String, Object?>? fillSlot(
      String slot, Utterance u, AssistantContext ctx) {
    final s = _slots(u, ctx);
    if (s.containsKey(slot) ||
        slot == 'energy' &&
            s.keys.any((k) => const [
                  'q_kj_mm',
                  'volts',
                  'amps',
                  'travel_mm_min',
                  'process'
                ].contains(k)) ||
        slot == 'window' && s.keys.any((k) => k.startsWith('window_'))) {
      return s;
    }
    if (slot == 'thickness_mm') {
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
    AskResult ask(String k, String pl, String en) =>
        AskResult(k, AssistantText(pl, en), partial: m);
    double? n(String k) => (m.slots[k] as num?)?.toDouble();
    final hasParams =
        ['volts', 'amps', 'travel_mm_min', 'process'].any(m.slots.containsKey);
    final direct = n('q_kj_mm');
    final mode = m.slots['input_mode'];
    if (m.slots['standard'] == HeatInputStandard.asmeIx.name) {
      return ask(
          'standard',
          't8/5 wymaga Q ze sprawnością wg EN 1011-1, nie energii łuku ASME. Potwierdź „EN”.',
          't8/5 requires Q with efficiency per EN 1011-1, not ASME arc energy. Confirm “EN”.');
    }
    if (direct != null && hasParams && mode == null) {
      return ask(
          'input_mode',
          'Podano Q i parametry łuku. Powiedz „użyj Q” albo „użyj parametrów”.',
          'Both Q and arc parameters were given. Say “use Q” or “use parameters”.');
    }
    double? q = mode == 'params' ? null : direct;
    Map<String, Object?>? parameterFields;
    if (q == null && (hasParams || mode == 'params')) {
      final process =
          WeldingProcess.fromCode(m.slots['process'] as String? ?? '');
      final volts = n('volts'),
          amps = n('amps'),
          speed = n('travel_mm_min'),
          eta = n('efficiency');
      if (process == null ||
          [volts, amps, speed].any((v) => v == null || !v.isFinite || v <= 0) ||
          eta != null && (!eta.isFinite || eta <= 0 || eta > 1)) {
        return ask(
            'energy',
            'Podaj proces, napięcie V, prąd A i prędkość mm/min albo gotowe Q wg EN w kJ/mm.',
            'Give process, voltage V, current A and travel speed mm/min, or EN Q in kJ/mm.');
      }
      q = heatInputKJPerMm(
          volts: volts!,
          amps: amps!,
          travelMmPerMin: speed!,
          efficiency: eta ?? process.thermalEfficiency,
          standard: HeatInputStandard.en1011);
      if (eta == null || eta == process.thermalEfficiency) {
        parameterFields = {
          'input_mode': 'parameters',
          'process': process.code,
          'volts': volts,
          'amps': amps,
          'travel_mm_min': speed
        };
      }
    }
    if (q == null || !q.isFinite || q <= 0) {
      return ask(
          'energy',
          'Podaj Q ze sprawnością wg EN 1011-1, z jednostką kJ/mm (np. 1 kJ/mm), albo parametry łuku.',
          'Give Q with efficiency per EN 1011-1 in kJ/mm (e.g. 1 kJ/mm), or arc parameters.');
    }
    if (parameterFields == null &&
        !hasParams &&
        mode != 'q' &&
        hasVisibleFormInputs(ctx.modules, toolId)) {
      final visible = (ctx.modules as FieldModuleContext).inputFields(toolId)!;
      final currentQ = visible['q_kj_mm'];
      if (visible['input_mode'] == 'parameters' &&
          currentQ is num &&
          currentQ.isFinite &&
          (q - currentQ).abs() <= 1e-9 * (q.abs() + 1)) {
        parameterFields = {
          for (final key in const [
            'input_mode',
            'process',
            'volts',
            'amps',
            'travel_mm_min'
          ])
            key: visible[key]
        };
      }
    }
    final t = n('preheat_c'), d = n('thickness_mm');
    if (t == null || !t.isFinite || t <= -273.15 || t >= 500) {
      return ask(
          'preheat_c',
          'Podaj temperaturę podgrzewania / międzyściegową z jednostką C, powyżej −273,15 i poniżej 500°C.',
          'Give preheat / interpass temperature with unit C, above −273.15 and below 500°C.');
    }
    if (d == null || !d.isFinite || d <= 0) {
      return ask('thickness_mm', 'Podaj grubość blachy z jednostką, np. 20 mm.',
          'Give plate thickness with a unit, e.g. 20 mm.');
    }
    final shape =
        WeldShape.values.where((s) => s.name == m.slots['shape']).firstOrNull;
    if (shape == null) {
      return ask(
          'shape',
          'Jaki rodzaj: napawanie, wypełnienie czołowej, jednościegowa pachwinowa narożna czy teowa?',
          'Which shape: bead on plate, butt fill run, single-run corner fillet or tee fillet?');
    }
    final min = n('window_min_s'), max = n('window_max_s');
    final r = coolingTime(
        heatInputKjMm: q, preheatC: t, thicknessMm: d, shape: shape);
    if (r == null) {
      return const FailedResult(AssistantText(
          'Wynik poza zakresem. Sprawdź Q, temperaturę i grubość.',
          'Result out of range. Check Q, temperature and thickness.'));
    }
    final verdict = checkT85Window(r.t85MinS, r.t85MaxS, min: min, max: max);
    if (verdict == T85Verdict.invalidWindow) {
      return ask(
          'window',
          'Popraw okno WPS: dodatnie granice w sekundach, min ≤ max, np. min 5 s max 15 s.',
          'Correct WPS window: positive bounds in seconds, min ≤ max, e.g. min 5 s max 15 s.');
    }
    final status = switch (verdict) {
      T85Verdict.notSet => const AssistantText(
          'Nie podano okna WPS — bez oceny zgodności.',
          'No WPS window provided — no compliance verdict.'),
      T85Verdict.inWindow => const AssistantText(
          'Cały wynik w podanym oknie WPS.',
          'Entire result within the supplied WPS window.'),
      T85Verdict.tooShort => const AssistantText(
          'Poniżej podanego okna WPS.', 'Below the supplied WPS window.'),
      T85Verdict.tooLong => const AssistantText(
          'Powyżej podanego okna WPS.', 'Above the supplied WPS window.'),
      _ => const AssistantText(
          'Przedział wyniku częściowo poza podanym oknem WPS.',
          'Result range partly outside the supplied WPS window.'),
    };
    final value = r.isRange
        ? '${fmt(r.t85MinS, ctx.lang)}–${fmt(r.t85MaxS, ctx.lang)}'
        : fmt(r.t85MinS, ctx.lang);
    final flow = r.flow == HeatFlow.twoD ? '2D' : '3D';
    return AnswerResult(
        AssistantAnswer(
            text: AssistantText(
                't8/5 = $value s, model $flow, Q = ${fmt(q, ctx.lang)} kJ/mm. ${status.pl} Szacunek dla stali C-Mn/niskostopowych i równych grubości; porównaj z własnym WPS.',
                't8/5 = $value s, model $flow, Q = ${fmt(q, ctx.lang)} kJ/mm. ${status.en} Estimate for C-Mn/low-alloy steels and equal thicknesses; compare with your own WPS.'),
            source: const AssistantText.same(
                'EN 1011-2:2001 Annex D (Ovako / MIGAL.CO / Lorch); Q: EN 1011-1')),
        show: ShowInModule(toolId, {
          ...?parameterFields,
          'q_kj_mm': q,
          'preheat_c': t,
          'thickness_mm': d,
          'shape': shape.name,
          if (min != null) 'window_min_s': min,
          if (max != null) 'window_max_s': max
        }));
  }
}
