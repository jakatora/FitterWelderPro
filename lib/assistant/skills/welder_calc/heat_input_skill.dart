import '../../../domain/welding/heat_input.dart';
import '../../core/skill.dart';
import '../../core/spoken_numbers.dart' show parseSpokenNumber;
import '../core/skill_words.dart';
import '../core/explain_tool_skill.dart' show explainedTool;

bool heatInputRequested(Utterance u) =>
    !kCommandVerbRe.hasMatch(u.folded) &&
    (u.hasAny(const [
      'heat input',
      'energia liniowa',
      'energie liniowa',
      'energii liniowej',
      'energię liniową',
      'arc energy'
    ]));

/// Parse quantities only beside their units. Never take the next voltage
/// as amperage merely because it follows the letter A in the sentence.
double? _quantity(Utterance u, Set<String> units, {bool speed = false}) {
  final values = <double>{};
  for (var i = 1; i < u.items.length; i++) {
    final item = u.items[i];
    if (item.isNumber || !units.contains(item.word)) continue;
    if (speed) {
      final suffix = u.items
          .skip(i + 1)
          .take(2)
          .where((t) => !t.isNumber)
          .map((t) => t.word);
      if (!suffix.any((w) => w.startsWith('min'))) continue;
    }
    final previous = u.items[i - 1];
    if (previous.isNumber) {
      var value = previous.value!;
      if (i > 1 && !u.items[i - 2].isNumber && u.items[i - 2].word == 'minus') {
        value = -value.abs();
      }
      values.add(value);
    }
  }
  return values.length > 1 ? double.nan : values.singleOrNull;
}

Map<String, Object?> _slots(Utterance u) {
  final slots = <String, Object?>{};
  final amps = _quantity(u, {'a', 'amper', 'ampery', 'amperow', 'amp', 'amps'});
  final volts = _quantity(u, {'v', 'volt', 'volts', 'wolt', 'wolty', 'woltow'});
  final speed = _quantity(u, {'mm'}, speed: true);
  if (amps != null) slots['amps'] = amps;
  if (volts != null) slots['volts'] = volts;
  if (speed != null) slots['travel_mm_min'] = speed;
  for (var i = 0; i < u.items.length; i++) {
    final item = u.items[i];
    if (item.isNumber ||
        !(item.word == 'eta' ||
            item.word == 'η' ||
            item.word.startsWith('sprawnos') ||
            item.word.startsWith('efficien'))) {
      continue;
    }
    double? eta;
    if (i > 0 && u.items[i - 1].isNumber) {
      eta = u.items[i - 1].value;
    } else if (i + 1 < u.items.length && u.items[i + 1].isNumber) {
      eta = u.items[i + 1].value;
    }
    if (eta != null &&
        (u.raw.contains('%') || u.hasStem(const ['procent', 'percent']))) {
      eta /= 100;
    }
    slots['efficiency'] = eta ?? double.nan;
  }

  final processes = <WeldingProcess>[];
  for (final p in WeldingProcess.values) {
    final aliases = switch (p) {
      WeldingProcess.gtaw => ['tig', 'gtaw'],
      WeldingProcess.smaw => ['mma', 'smaw'],
      WeldingProcess.gmaw => ['mig', 'mag', 'gmaw'],
      WeldingProcess.fcawG => ['fcaw-g'],
      WeldingProcess.fcawS => ['fcaw-s'],
      WeldingProcess.saw => ['saw'],
    };
    if (u.hasAny(aliases)) processes.add(p);
  }
  if (processes.length == 1) slots['process'] = processes.single.code;
  if (u.hasAny(const ['asme'])) {
    slots['standard'] = HeatInputStandard.asmeIx.name;
  }
  if (u.hasAny(const ['en', 'en1011'])) {
    if (slots.containsKey('standard')) {
      slots.remove('standard');
    } else {
      slots['standard'] = HeatInputStandard.en1011.name;
    }
  }
  return slots;
}

/// Unit-tagged quantities only; other calculators must not inherit the active
/// heat-input form or its continuation metadata.
Map<String, Object?> heatInputQuantities(Utterance u) => _slots(u);

class HeatInputSkill extends AssistantSkill {
  Map<String, Object?>? _current(AssistantContext ctx) {
    final modules = ctx.modules;
    if (modules.activeToolId != toolId || modules is! FieldModuleContext) {
      return null;
    }
    final fields = (modules as FieldModuleContext).inputFields(toolId);
    return fields != null &&
            fields.containsKey('amps') &&
            fields.containsKey('volts')
        ? fields
        : null;
  }

  @override
  String get id => 'heat.input';
  @override
  String get toolId => 'heat_input';
  @override
  AssistantTier get tier => AssistantTier.b;
  @override
  List<SkillExample> get examples => const [
        SkillExample('Oblicz energię liniową TIG EN 24 V 230 A 150 mm/min',
            'Calculate heat input TIG EN 24 V 230 A 150 mm/min'),
        SkillExample('Oblicz heat input MMA EN 22 V 110 A 200 mm/min',
            'Calculate heat input MMA EN 22 V 110 A 200 mm/min'),
        SkillExample('Oblicz heat input TIG ASME 12 V 100 A 90 mm/min',
            'Calculate heat input TIG ASME 12 V 100 A 90 mm/min'),
        SkillExample('Energia liniowa 24 V 230 A', 'Heat input 24 V 230 A'),
        SkillExample('Oblicz energię liniową', 'Calculate heat input'),
        SkillExample('Ustaw heat input 24 V 230 A 150 mm/min',
            'Set heat input 24 V 230 A 150 mm/min'),
      ];
  @override
  List<SkillRejection> get rejections => const [
        SkillRejection('zapisz TIG nierdzewka ścianka 2 mm 60 A bez drutu',
            routesTo: 'legacy.save'),
        SkillRejection('otwórz heat input', routesTo: 'tool.open'),
        SkillRejection('Jaka średnica DN40?', routesTo: 'pipe.od'),
      ];
  @override
  SkillMatch? match(Utterance u, AssistantContext ctx) {
    if (kCommandVerbRe.hasMatch(u.folded) ||
        requestsCoolingTime(u) ||
        kOpenVerbAtStartRe.hasMatch(u.folded) ||
        u.hasAny(const ['gdzie', 'where']) ||
        explainedTool(u) != null) {
      return null;
    }
    final fields = _slots(u);
    final set = u.hasAny(const ['ustaw', 'wpisz', 'zmien', 'set', 'change']);
    final explicit = heatInputRequested(u);
    final current = _current(ctx);
    final recalculate = current != null &&
        const {
          'przelicz',
          'przelicz to',
          'oblicz to',
          'policz to',
          'recalculate',
          'calculate this',
          'calculate these'
        }.contains(u.folded);
    if (!explicit &&
        !recalculate &&
        !(set && ctx.modules.activeToolId == toolId && fields.isNotEmpty)) {
      return null;
    }
    if (u.hasAny(const ['do czego', 'sluzy', 'what is it', 'explain'])) {
      return null;
    }
    return SkillMatch(this, 0.95,
        slots: {
          if (!set && current != null) 'native_edit': fields else ...fields,
          'mode': set ? 'set' : 'calculate'
        },
        utterance: u);
  }

  @override
  Map<String, Object?> slotsFrom(Utterance u, AssistantContext ctx) {
    final fields = _slots(u);
    if (fields.isEmpty) return const {};
    return _current(ctx) == null
        ? fields
        : {'native_edit': fields, 'mode': 'calculate'};
  }

  @override
  Map<String, Object?>? fillSlot(
      String slot, Utterance u, AssistantContext ctx) {
    final values = _slots(u);
    if (const {'amps', 'volts', 'travel_mm_min', 'efficiency'}.contains(slot) &&
        values.isEmpty &&
        u.items.length == 1 &&
        u.items.single.isNumber) {
      var value = parseSpokenNumber(u.raw);
      if (value != null) {
        if (slot == 'efficiency' && u.raw.contains('%')) {
          value /= 100;
        }
        return {slot: value};
      }
    }
    return values.containsKey(slot) || (slot == 'inputs' && values.isNotEmpty)
        ? values
        : null;
  }

  AskResult _ask(SkillMatch m, String slot, AssistantText question,
          {List<FollowUp> choices = const []}) =>
      AskResult(slot, question, partial: m, choices: choices);
  @override
  Future<SkillResult> run(SkillMatch m, AssistantContext ctx) async {
    if (m.slots['native_edit'] case final Map<String, Object?> edits) {
      final current = _current(ctx);
      if (current == null) {
        return const FailedResult(
            AssistantText(
                'Otwórz kartę Heat input i poczekaj na wczytanie danych.',
                'Open the Heat input tab and wait for inputs to load.'),
            reportMissingCapability: false);
      }
      final merged = {...current, ...edits};
      if (edits.containsKey('process') &&
          edits['process'] != current['process'] &&
          !edits.containsKey('efficiency')) {
        merged.remove('efficiency');
      }
      m = m
          .copyWith(slots: {...merged, 'mode': m.slots['mode'] ?? 'calculate'});
    }
    final fields = <String, Object?>{
      for (final e in m.slots.entries)
        if (e.key != 'mode') e.key: e.value
    };
    if (fields.isEmpty) {
      return _ask(
          m,
          'inputs',
          const AssistantText(
              'Podaj parametry z jednostkami, np. 230 A, 24 V i 150 mm/min.',
              'Give parameters with units, e.g. 230 A, 24 V and 150 mm/min.'));
    }
    for (final key in const ['amps', 'volts', 'travel_mm_min', 'efficiency']) {
      if (fields.containsKey(key)) {
        final value = fields[key];
        if (value is! num ||
            !value.isFinite ||
            value <= 0 ||
            (key == 'efficiency' && value > 1)) {
          return _ask(
              m,
              key,
              key == 'efficiency'
                  ? const AssistantText(
                      'Podaj sprawność z WPS większą od 0 i nie większą niż 1, np. 0,8.',
                      'Give the WPS efficiency above 0 and at most 1, e.g. 0.8.')
                  : const AssistantText('Podaj dodatnią wartość z jednostką.',
                      'Give a positive value with its unit.'));
        }
      }
    }
    if (m.slots['mode'] == 'set') {
      final labels = <String, String>{
        'amps': 'A',
        'volts': 'V',
        'travel_mm_min': 'mm/min',
        'efficiency': 'η'
      };
      final values = fields.entries.map((e) {
        if (e.key == 'process') {
          return WeldingProcess.fromCode(e.value as String)!.euLabel;
        }
        if (e.key == 'standard') {
          return e.value == HeatInputStandard.en1011.name
              ? 'EN 1011-1'
              : 'ASME IX';
        }
        return '${fmt((e.value as num).toDouble(), ctx.lang)} ${labels[e.key]}';
      }).join(', ');
      return AnswerResult(
          AssistantAnswer(
              text: AssistantText(
                  'Ustawiam parametry kalkulatora: $values. Wynik przeliczy moduł. Niczego nie zapisuję do dziennika.',
                  'Setting calculator parameters: $values. The module recalculates. Nothing is saved to the journal.')),
          show: ShowInModule(toolId, fields));
    }
    for (final key in const [
      'amps',
      'volts',
      'travel_mm_min',
      'process',
      'standard'
    ]) {
      if (fields.containsKey(key)) continue;
      if (key == 'process') {
        return _ask(
            m,
            key,
            const AssistantText(
                'Jaki proces spawania?', 'Which welding process?'),
            choices: [
              for (final p in WeldingProcess.values)
                FollowUp(AssistantText.same(p.euLabel), p.code)
            ]);
      }
      if (key == 'standard') {
        return _ask(
            m,
            key,
            const AssistantText(
                'Liczyć wg EN 1011-1 (ze sprawnością) czy ASME IX (bez sprawności)?',
                'EN 1011-1 (with efficiency) or ASME IX (without efficiency)?'),
            choices: const [
              FollowUp(AssistantText.same('EN 1011-1'), 'EN'),
              FollowUp(AssistantText.same('ASME IX'), 'ASME')
            ]);
      }
      final label =
          switch (key) { 'amps' => 'A', 'volts' => 'V', _ => 'mm/min' };
      return _ask(
          m,
          key,
          AssistantText(
              'Podaj wartość w $label.', 'Give the value in $label.'));
    }
    final process = WeldingProcess.fromCode(fields['process'] as String)!;
    final standard =
        HeatInputStandard.values.byName(fields['standard'] as String);
    final efficiency =
        (fields['efficiency'] as num?)?.toDouble() ?? process.thermalEfficiency;
    final result = heatInputKJPerMm(
        volts: (fields['volts'] as num).toDouble(),
        amps: (fields['amps'] as num).toDouble(),
        travelMmPerMin: (fields['travel_mm_min'] as num).toDouble(),
        standard: standard,
        efficiency: efficiency)!;
    final source =
        standard == HeatInputStandard.en1011 ? 'EN 1011-1' : 'ASME IX QW-409.1';
    return AnswerResult(
        AssistantAnswer(
            text: AssistantText(
                'Energia liniowa ${process.euName}: ${fmt(result, ctx.lang)} kJ/mm ($source). Porównaj z własnym WPS.',
                'Heat input ${process.euName}: ${fmt(result, ctx.lang)} kJ/mm ($source). Compare with your WPS.'),
            source: AssistantText.same(source)),
        show: ShowInModule(toolId, fields),
        contextSlots: Map.unmodifiable(fields));
  }
}
