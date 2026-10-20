import '../../../domain/welding/power_source.dart';
import '../../core/skill.dart';
import '../core/explain_tool_skill.dart' show explainedTool;
import '../core/skill_words.dart';
import '../fitter_routes/quantities.dart';

Map<String, Object?> _slots(Utterance original) {
  final u = original.withRaw(original.raw
      .replaceAll(RegExp(r'mm\s*(?:²|2|\^2)', caseSensitive: false), 'mmkw')
      .replaceAllMapped(
          RegExp(r'\b(weld|return|earth|ground|torch)\s+(?:lead|cable)\b',
              caseSensitive: false),
          (m) => m[1]!));
  final s = <String, Object?>{};
  final currents = <double>{},
      volts = <double>{},
      temperatures = <double>{},
      sections = <double>{};
  for (var i = 0; i + 1 < u.items.length; i++) {
    if (!u.items[i].isNumber) continue;
    final v = signedQuantity(u, i), unit = u.items[i + 1].word;
    if (const ['a', 'amp', 'amps', 'amper', 'ampery', 'amperow']
        .contains(unit)) {
      currents.add(v);
    }
    if (const ['v', 'volt', 'volts', 'wolt', 'wolty', 'woltow']
        .contains(unit)) {
      volts.add(v);
    }
    if (unit == 'c' || unit.startsWith('cels')) temperatures.add(v);
    if ((unit.startsWith('stopn') || unit.startsWith('degree')) &&
        i + 2 < u.items.length &&
        (u.items[i + 2].word == 'c' ||
            u.items[i + 2].word.startsWith('cels'))) {
      temperatures.add(v);
    }
    if (unit == 'mmkw' ||
        unit.startsWith('milimetr') &&
            i + 2 < u.items.length &&
            u.items[i + 2].word.startsWith('kwadrat') ||
        unit == 'square' &&
            i + 2 < u.items.length &&
            u.items[i + 2].word.startsWith('millimet')) {
      sections.add(v);
    }
  }
  void put(String k, Set<double> values) {
    if (values.isNotEmpty) {
      s[k] = values.length == 1 ? values.single : double.nan;
    }
  }

  put('weld_current_a', currents);
  put('drop_limit_v', volts);
  put('ambient_c', temperatures);
  put('section_mm2', sections);
  final weld = lengthNear(u, const ['spawalnicz', 'uchwyt', 'weld', 'torch']),
      ret = lengthNear(
          u, const ['masow', 'powrotn', 'return', 'earth', 'ground']);
  if (weld != null) s['weld_lead_m'] = weld / 1000;
  if (ret != null) s['return_lead_m'] = ret / 1000;
  final duty = percentValue(u);
  if (duty != null) s['duty_pct'] = duty;
  final check = u.hasStem(const ['sprawdz', 'check', 'ocen']);
  final size = u.hasStem(const ['dobierz', 'select', 'size', 'pick']);
  if (check || size) {
    s['cable_mode'] = check && size
        ? 'ambiguous'
        : check
            ? 'check'
            : 'size';
  }
  final aluminiumWorkpiece = u.hasAny(const [
    'spawam aluminium',
    'spawanie aluminium',
    'welding aluminium',
    'welding aluminum'
  ]);
  if (u.hasStem(const ['aluminiow']) ||
      !aluminiumWorkpiece && u.hasAny(const ['aluminium', 'aluminum'])) {
    s['unsupported_material'] = true;
  }
  if (u.hasAny(const [
    'ac',
    'prąd przemienny',
    'prad przemienny',
    'alternating current',
    'h07rn f'
  ])) {
    s['unsupported_model'] = true;
  }
  return s;
}

class PowerCableSkill extends AssistantSkill {
  @override
  String get id => 'power.cable';
  @override
  String get toolId => 'power_source';
  @override
  AssistantTier get tier => AssistantTier.b;
  @override
  List<SkillExample> get examples => const [
        SkillExample(
            'Sprawdź przewody spawalniczy 25 m masowy 25 m 200 A 60% otoczenie 30 C próg 4 V przekrój 35 mm²',
            'Check welding cables weld lead 25 m return lead 25 m 200 A 60% ambient 30 C limit 4 V section 35 mm²'),
        SkillExample(
            'Dobierz przewody spawalniczy 25 m masowy 25 m 200 A 60% otoczenie 30 C próg 4 V',
            'Size welding cables weld lead 25 m return lead 25 m 200 A 60% ambient 30 C limit 4 V'),
        SkillExample('Dobierz przewody spawalnicze', 'Size welding cables'),
        SkillExample(
            'Sprawdź kabel spawalniczy 10 m masowy 10 m 100 A 100% otoczenie 25 C próg 2 V przekrój 25 mm2',
            'Check welding cable weld lead 10 m return lead 10 m 100 A 100% ambient 25 C limit 2 V section 25 mm2'),
        SkillExample(
            'Dobierz przewód spawalniczy 50 m masowy 20 m 300 A 40% otoczenie 40 C próg 4 V',
            'Size welding cable weld lead 50 m return lead 20 m 300 A 40% ambient 40 C limit 4 V'),
        SkillExample(
            'Sprawdź przewody spawalniczy 2 m masowy 3 m 50 A 20% otoczenie 25 C próg 1 V przekrój 16 mm²',
            'Check welding cables weld lead 2 m return lead 3 m 50 A 20% ambient 25 C limit 1 V section 16 mm²'),
      ];
  @override
  List<SkillRejection> get rejections => const [
        SkillRejection('otwórz spawarka i przewody', routesTo: 'tool.open'),
        SkillRejection('oblicz cykl pracy 200 A 60% prąd spawania 150 A',
            routesTo: 'power.duty'),
        SkillRejection('oblicz CE C 0,2 Mn 1 pozostałe zero grubość 15 mm',
            routesTo: 'preheat.ce'),
      ];
  @override
  SkillMatch? match(Utterance u, AssistantContext ctx) {
    if (explainedTool(u) != null ||
        kCommandVerbRe.hasMatch(u.folded) ||
        kOpenVerbAtStartRe.hasMatch(u.folded)) {
      return null;
    }
    if (!requestsWeldingCables(u)) {
      return null;
    }
    final s = _slots(u);
    return SkillMatch(this, s.isNotEmpty ? .98 : .65, slots: s, utterance: u);
  }

  @override
  Map<String, Object?> slotsFrom(Utterance u, AssistantContext ctx) =>
      _slots(u);
  @override
  Map<String, Object?>? fillSlot(
      String slot, Utterance u, AssistantContext ctx) {
    final s = _slots(u);
    if (s.containsKey(slot)) return s;
    if (slot == 'weld_lead_m' || slot == 'return_lead_m') {
      final values = <double>{};
      for (var i = 0; i + 1 < u.items.length; i++) {
        final scale = lengthUnitScale(u.items[i + 1].word);
        if (u.items[i].isNumber && scale != null) {
          values.add(signedQuantity(u, i) * scale / 1000);
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
    if (m.slots['unsupported_material'] == true) {
      return const FailedResult(
          AssistantText(
              'Tabela dotyczy miedzianych przewodów H01N2-D / H01N2-E, nie aluminium. Brak modelu aluminium.',
              'The table is for copper H01N2-D / H01N2-E leads, not aluminium. No aluminium model is available.'),
          reportMissingCapability: true);
    }
    if (m.slots['unsupported_model'] == true) {
      return const FailedResult(
          AssistantText(
              'Ten model liczy opór DC przewodów spawalniczych H01N2-D / H01N2-E. Dla AC lub innego typu przewodu potrzebne są inne dane; aplikacja ich nie ma.',
              'This model uses DC resistance for H01N2-D / H01N2-E welding leads. AC or another cable type needs other data unavailable in the app.'),
          reportMissingCapability: true);
    }
    double? n(String k) => (m.slots[k] as num?)?.toDouble();
    final mode = m.slots['cable_mode'] ??
        (m.slots.containsKey('section_mm2') ? 'check' : 'size');
    if (!const ['check', 'size'].contains(mode)) {
      return ask(
          'cable_mode',
          'Chcesz „sprawdź” istniejący przekrój czy „dobierz” najmniejszy?',
          'Do you want to “check” an existing size or “size” the smallest cable?');
    }
    final current = n('weld_current_a'),
        weld = n('weld_lead_m'),
        ret = n('return_lead_m'),
        duty = n('duty_pct'),
        temp = n('ambient_c'),
        limit = n('drop_limit_v'),
        section = n('section_mm2');
    if (current == null ||
        !current.isFinite ||
        current <= 0 ||
        current > kMaxCurrentA) {
      return ask(
          'weld_current_a',
          'Podaj prąd z jednostką A, powyżej 0 do 1500 A.',
          'Give current with unit A, greater than 0 up to 1500 A.');
    }
    if (weld == null || !weld.isFinite || weld < 0 || weld > kMaxLeadM) {
      return ask(
          'weld_lead_m',
          'Podaj długość przewodu spawalniczego do uchwytu z jednostką, od 0 do 500 m.',
          'Give welding lead length to the torch with a unit, from 0 to 500 m.');
    }
    if (ret == null || !ret.isFinite || ret < 0 || ret > kMaxLeadM) {
      return ask(
          'return_lead_m',
          'Podaj długość przewodu masowego/powrotnego z jednostką, od 0 do 500 m. Nie dzielę podanej pętli na pół.',
          'Give return/earth lead length with a unit, from 0 to 500 m. I do not split a loop length in half.');
    }
    if (weld + ret <= 0) {
      return ask(
          'weld_lead_m',
          'Suma długości przewodów musi być większa od zera.',
          'The sum of lead lengths must be greater than zero.');
    }
    if (duty == null || !duty.isFinite || duty < 1 || duty > 100) {
      return ask(
          'duty_pct',
          'Jaki cykl pracy przewodów: 1–100% czasu łuku na każde 10 minut?',
          'What cable duty cycle: 1–100% arc time in each 10 minutes?');
    }
    if (temp == null || !temp.isFinite || temp <= -273.15 || temp > 50) {
      return ask(
          'ambient_c',
          'Podaj temperaturę otoczenia z jednostką C, nie więcej niż 50°C.',
          'Give ambient temperature with unit C, no more than 50°C.');
    }
    final ambient = kCableAmbientFactors.firstWhere((f) => f.$1 >= temp).$1;
    if (limit == null ||
        !limit.isFinite ||
        limit < kMinDropLimitV ||
        limit > kMaxDropLimitV) {
      return ask(
          'drop_limit_v',
          'Podaj dopuszczalny spadek napięcia 0,5–20 V. Przykład 4 V to wytyczna producenta, nie uniwersalny wymóg normy.',
          'Give allowable voltage drop 0.5–20 V. Example 4 V is a manufacturer guideline, not a universal standard requirement.');
    }
    if (mode == 'check' &&
        (section == null ||
            !section.isFinite ||
            section != section.roundToDouble() ||
            !kCableSectionsMm2.contains(section.toInt()))) {
      return ask(
          'section_mm2',
          'Podaj przekrój z jednostką mm²: 16, 25, 35, 50, 70 lub 95 mm².',
          'Give section with unit mm²: 16, 25, 35, 50, 70 or 95 mm².');
    }
    final input = CableInput(
        currentA: current,
        weldLeadM: weld,
        returnLeadM: ret,
        sectionMm2: mode == 'check' ? section!.toInt() : 0,
        dutyPct: duty,
        ambientC: ambient,
        dropLimitV: limit);
    final sizing = mode == 'size' ? sizeCable(input) : null,
        check = mode == 'check' ? checkCable(input) : sizing?.check;
    if (mode == 'size' && sizing == null || mode == 'check' && check == null) {
      return const FailedResult(AssistantText(
          'Nie można obliczyć przewodów dla tych danych.',
          'Cannot calculate cables for these inputs.'));
    }
    final note = temp != ambient
        ? AssistantText(
            'Zastosowano przedział temperatury do $ambient°C dla podanych ${fmt(temp, ctx.lang)}°C.',
            'Used ambient band up to $ambient°C for supplied ${fmt(temp, ctx.lang)}°C.')
        : const AssistantText.same('');
    return AnswerResult(
        AssistantAnswer(
            text: AssistantText(
                '${powerSourceShareText(en: false, cable: check, sizing: sizing)}\n${note.pl}',
                '${powerSourceShareText(en: true, cable: check, sizing: sizing)}\n${note.en}'),
            source: const AssistantText.same(
                'Copper H01N2-D/H01N2-E; HD 516 / EN 50565-1 Annex D; Top Cable / HVJ / Miller')),
        show: ShowInModule(toolId, {
          'cable_mode': mode,
          'weld_current_a': current,
          'weld_lead_m': weld,
          'return_lead_m': ret,
          'duty_pct': duty,
          'ambient_c': ambient,
          'drop_limit_v': limit,
          if (mode == 'check') 'section_mm2': section!.toInt()
        }));
  }
}
