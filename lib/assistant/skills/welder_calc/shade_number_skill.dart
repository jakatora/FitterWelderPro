import '../../../domain/welding/shade_number.dart';
import '../../../utils/decimal_parse.dart';
import '../../core/skill.dart';
import '../core/explain_tool_skill.dart' show explainedTool;
import '../core/skill_words.dart';
import '../fitter_routes/quantities.dart';

Map<String, Object?> _slots(Utterance original) {
  final u = original.withRaw(original.raw.replaceAllMapped(
      RegExp(
          r'(?<![\d.,])[-−]?\d{1,3}(?:[ \u00a0]\d{3})+(?:[.,]\d+)?(?=\s*(?:l\b|litr\w*|liter\w*|litre\w*)\s*(?:/|na\b|per\b))',
          caseSensitive: false),
      (m) => (parseDecimal(m[0]) ?? double.nan).toString()));
  final s = <String, Object?>{};
  final processes = <ShadeProcess>{};
  void alias(ShadeProcess p, List<String> words) {
    if (words.any((w) => RegExp(r'^\d+$').hasMatch(w)
        ? RegExp('\\b(?:proces|process|metoda)\\s+$w\\b').hasMatch(u.folded)
        : u.hasAny([w]))) {
      processes.add(p);
    }
  }

  alias(ShadeProcess.mma, const ['mma', 'smaw', '111']);
  alias(ShadeProcess.mag, const ['mag', 'fcaw', '135', '136', '138']);
  alias(ShadeProcess.tig, const ['tig', 'gtaw', '141']);
  alias(ShadeProcess.arcGouging, const ['żłobienie', 'zlobienie', 'gouging']);
  alias(ShadeProcess.plasmaCutting, const [
    'pac',
    '83',
    'cięcie plazmowe',
    'ciecie plazmowe',
    'plasma cutting'
  ]);
  alias(ShadeProcess.plasmaWelding, const [
    'paw',
    '15',
    'spawanie plazmowe',
    'plasma welding',
    'mikroplazma'
  ]);
  alias(ShadeProcess.gasWelding,
      const ['311', 'ofw', 'spawanie gazowe', 'gas welding']);
  alias(ShadeProcess.oxyCutting, const [
    '81',
    'cięcie tlenowe',
    'ciecie tlenowe',
    'oxy cutting',
    'oxy-fuel cutting'
  ]);
  if (u.hasAny(const ['mig', '131', 'gmaw'])) {
    final light = u.hasStem(const ['alum', 'lekk', 'light']);
    final heavy =
        u.hasStem(const ['stal', 'steel', 'miedz', 'copper', 'ciezk', 'heavy']);
    if (light == heavy) {
      s['process'] = 'migAmbiguous';
    } else {
      processes.add(light ? ShadeProcess.migLight : ShadeProcess.migHeavy);
    }
  }
  if (processes.isNotEmpty) {
    s['process'] = processes.length == 1 && !s.containsKey('process')
        ? processes.single.name
        : 'ambiguous';
  }
  final currents = <double>{};
  for (var i = 1; i < u.items.length; i++) {
    if (u.items[i - 1].isNumber &&
        const ['a', 'amp', 'amps', 'amper', 'ampery', 'amperow']
            .contains(u.items[i].word)) {
      currents.add(signedQuantity(u, i - 1));
    }
  }
  if (currents.isNotEmpty) {
    s['current_a'] = currents.length == 1 ? currents.single : double.nan;
  }
  final flows = <double>{};
  for (var i = 0; i + 1 < u.items.length; i++) {
    if (!u.items[i].isNumber) continue;
    final unit = u.items[i + 1].word;
    if (unit == 'lpm') {
      flows.add(signedQuantity(u, i) * 60);
    } else if (unit == 'l' ||
        unit.startsWith('litr') ||
        unit.startsWith('liter')) {
      var j = i + 2;
      if (j < u.items.length && const ['na', 'per'].contains(u.items[j].word)) {
        j++;
      }
      if (j < u.items.length) {
        final time = u.items[j].word;
        if (time == 'h' ||
            time.startsWith('godzin') ||
            time.startsWith('hour')) {
          flows.add(signedQuantity(u, i));
        }
        if (time.startsWith('min')) flows.add(signedQuantity(u, i) * 60);
      }
    }
  }
  // Time units are mandatory: a bare volume is not a flow rate.
  for (final m in RegExp(
          r'(-?\d+(?:[.,]\d+)?)\s*(?:l|liters?|litres?|litrow|litrów|litry)\s*(?:/|na\s+|per\s+)(h\b|godzin\w*|hours?\b|min\w*)',
          caseSensitive: false)
      .allMatches(u.raw)) {
    var v = parseDecimal(m[1]!) ?? double.nan;
    if (RegExp(r'minus\s*$', caseSensitive: false)
        .hasMatch(u.raw.substring(0, m.start))) {
      v = -v.abs();
    }
    if (m[2]!.toLowerCase().startsWith('min')) v *= 60;
    flows.add(v);
  }
  if (flows.isNotEmpty) {
    s['flow_lh'] = flows.length == 1 ? flows.single : double.nan;
  }
  final thickness = lengthNear(u, const ['grubosc', 'thickness']);
  if (thickness != null) s['thickness_mm'] = thickness;
  return s;
}

class ShadeNumberSkill extends AssistantSkill {
  @override
  String get id => 'shade.number';
  @override
  String get toolId => 'shade';
  @override
  AssistantTier get tier => AssistantTier.b;
  @override
  List<SkillExample> get examples => const [
        SkillExample('Dobierz filtr przyłbicy TIG 100 A',
            'Calculate lens shade TIG 100 A'),
        SkillExample('Zaciemnienie MMA 160 A', 'Shade number MMA 160 A'),
        SkillExample('Stopień filtra MAG 250 A', 'Lens shade MAG 250 A'),
        SkillExample(
            'Filtr MIG aluminium 200 A', 'Lens shade MIG aluminium 200 A'),
        SkillExample('Filtr cięcie tlenowe przepływ 1500 l/h grubość 20 mm',
            'Lens shade oxy cutting flow 1500 l/h thickness 20 mm'),
        SkillExample('Oblicz zaciemnienie', 'Calculate shade number'),
      ];
  @override
  List<SkillRejection> get rejections => const [
        SkillRejection('otwórz filtr przyłbicy', routesTo: 'tool.open'),
        SkillRejection('energia liniowa TIG 100 A 12 V 100 mm/min',
            routesTo: 'heat.input'),
        SkillRejection('zapisz TIG 100 A ścianka 2 mm'),
      ];
  @override
  SkillMatch? match(Utterance u, AssistantContext ctx) {
    if (explainedTool(u) != null ||
        kCommandVerbRe.hasMatch(u.folded) ||
        kOpenVerbAtStartRe.hasMatch(u.folded)) {
      return null;
    }
    if (!u.hasStem(const ['zaciemn', 'przylbic', 'shade']) &&
        !u.hasAny(const ['filtr', 'filtra', 'lens'])) {
      return null;
    }
    final s = _slots(u);
    return SkillMatch(
        this,
        s.isNotEmpty || u.hasStem(const ['oblicz', 'dobierz', 'calculate'])
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
    if (slot == 'mig_material' && !s.containsKey('process')) {
      final light = u.hasStem(const ['alum', 'lekk', 'light']);
      final heavy = u.hasStem(
          const ['stal', 'steel', 'miedz', 'copper', 'ciezk', 'heavy']);
      if (light != heavy) {
        return {
          'process':
              light ? ShadeProcess.migLight.name : ShadeProcess.migHeavy.name
        };
      }
    }
    if (s.containsKey(slot) ||
        slot == 'mig_material' && s.containsKey('process') ||
        slot == 'gas_input' &&
            (s.containsKey('flow_lh') || s.containsKey('thickness_mm'))) {
      return s;
    }
    return null;
  }

  @override
  Future<SkillResult> run(SkillMatch m, AssistantContext ctx) async {
    AskResult ask(String k, String pl, String en) =>
        AskResult(k, AssistantText(pl, en), partial: m);
    final p = ShadeProcess.values
        .where((p) => p.name == m.slots['process'])
        .firstOrNull;
    if (p == null) {
      if (m.slots['process'] == 'migAmbiguous') {
        return ask(
            'mig_material',
            'MIG: spawasz stal/miedź czy aluminium (stopy lekkie)?',
            'MIG: are you welding steel/copper or aluminium (light alloys)?');
      }
      return ask(
          'process',
          'Jaki proces: MMA, MAG, TIG, MIG (stal/miedź czy aluminium), żłobienie, cięcie/spawanie plazmowe, spawanie gazowe lub cięcie tlenowe?',
          'Which process: MMA, MAG, TIG, MIG (steel/copper or aluminium), gouging, plasma cutting/welding, gas welding or oxy cutting?');
    }
    double? n(String k) => (m.slots[k] as num?)?.toDouble();
    final current = n('current_a'),
        flow = n('flow_lh'),
        thickness = n('thickness_mm');
    bool valid(double? v, double max) =>
        v != null && v.isFinite && v > 0 && v <= max;
    final fields = <String, Object?>{'process': p.name};
    if (!p.isGas) {
      if (!valid(current, kShadeMaxCurrentA)) {
        return ask(
            'current_a',
            'Podaj prąd z jednostką A, większy od 0 i nie większy niż 2000 A.',
            'Give current with unit A, greater than 0 and no more than 2000 A.');
      }
      fields['current_a'] = current;
    } else {
      if (flow != null && !valid(flow, kShadeMaxFlowLh)) {
        return ask(
            'flow_lh',
            'Popraw przepływ: powyżej 0 do 100000 l/h. Podaj jednostkę l/h lub l/min.',
            'Correct flow: greater than 0 up to 100000 l/h. Include l/h or l/min.');
      }
      if (thickness != null && !valid(thickness, kShadeMaxThicknessMm)) {
        return ask(
            'thickness_mm',
            'Popraw grubość: powyżej 0 do 2000 mm, z jednostką.',
            'Correct thickness: greater than 0 up to 2000 mm, with a unit.');
      }
      if (flow == null && thickness == null) {
        return ask(
            'gas_input',
            p == ShadeProcess.oxyCutting
                ? 'Podaj przepływ tlenu tnącego w l/h (EN 169) albo grubość materiału (ANSI/OSHA), np. grubość 20 mm.'
                : 'Podaj przepływ acetylenu w l/h (EN 169) albo grubość materiału (ANSI/OSHA), np. grubość 5 mm.',
            'Give cutting oxygen / welding acetylene flow in l/h (EN 169) or material thickness (ANSI/OSHA), e.g. thickness 20 mm.');
      }
      if (flow != null) fields['flow_lh'] = flow;
      if (thickness != null) fields['thickness_mm'] = thickness;
    }
    final advice = computeShade(ShadeInput(
        process: p,
        currentA: current,
        gasFlowLh: flow,
        thicknessMm: thickness));
    if (advice == null) {
      return const FailedResult(AssistantText(
          'Nie można dobrać filtra dla tych danych.',
          'Cannot select a shade for these inputs.'));
    }
    return AnswerResult(
        AssistantAnswer(
            text: AssistantText(shadeShareText(advice, en: false),
                shadeShareText(advice, en: true)),
            source: const AssistantText(
                'Tabele aplikacji: EN 169:2002 (wycofana; zastąpiona przez EN ISO 16321), ANSI Z49.1:2005 / OSHA.',
                'App tables: EN 169:2002 (withdrawn; replaced by EN ISO 16321), ANSI Z49.1:2005 / OSHA.')),
        show: ShowInModule(toolId, fields));
  }
}
