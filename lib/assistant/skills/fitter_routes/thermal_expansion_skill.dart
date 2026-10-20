import '../../../domain/fitter/fitter_calcs.dart';
import '../../core/skill.dart';
import '../core/explain_tool_skill.dart' show explainedTool;
import '../core/skill_words.dart';
import 'quantities.dart';

double? _temperature(Utterance u, List<String> labels) {
  final found = <double>{};
  for (var i = 0; i < u.items.length; i++) {
    if (!labels.any((s) => u.items[i].word.startsWith(s))) continue;
    for (var j = i + 1; j < u.items.length && j <= i + 4; j++) {
      final item = u.items[j];
      if (!item.isNumber) {
        if (!const [
          't',
          'temperatur',
          'temperature',
          'temperatury',
          'temperaturze',
          'wynosi',
          'is',
          'minus',
          'o'
        ].contains(item.word)) {
          break;
        }
        continue;
      }
      var end = j + 1;
      while (end < u.items.length &&
          (u.items[end].word.startsWith('stopn') ||
              u.items[end].word.startsWith('degree'))) {
        end++;
      }
      if (end < u.items.length) {
        final unit = u.items[end].word;
        final v = signedQuantity(u, j);
        if (unit == 'c' || unit.startsWith('cels')) found.add(v);
        if (unit == 'k' || unit.startsWith('kel')) found.add(v);
      }
      break;
    }
  }
  return found.length > 1 ? double.nan : found.singleOrNull;
}

Map<String, Object?> _slots(Utterance u) {
  final out = <String, Object?>{};
  final length = lengthNear(u, const ['dlugosc', 'length']);
  if (length != null) out['length_m'] = length / 1000;
  final delta = _temperature(u, const ['delta', 'dt', 'roznic', 'difference']);
  if (delta != null) out['delta_k'] = delta;
  final materials = <ExpansionMaterial>{};
  if (RegExp(r'\b316\s*l?\b').hasMatch(u.folded)) {
    materials.add(ExpansionMaterial.ss316L);
  }
  if (RegExp(r'\b304\s*l?\b').hasMatch(u.folded)) {
    materials.add(ExpansionMaterial.ss304L);
  }
  if (u.hasStem(const ['weglow', 'carbon']) || u.hasAny(const ['cs'])) {
    materials.add(ExpansionMaterial.cs);
  }
  if (u.hasStem(const ['alumin'])) materials.add(ExpansionMaterial.al);
  if (u.hasAny(const ['cuni', 'cu ni'])) materials.add(ExpansionMaterial.cuNi);
  if (materials.isNotEmpty) {
    out['material'] =
        materials.length == 1 ? materials.single.name : 'ambiguous';
  }
  return out;
}

class ThermalExpansionSkill extends AssistantSkill {
  @override
  String get id => 'thermal.expansion';
  @override
  String get toolId => 'thermal_expansion';
  @override
  AssistantTier get tier => AssistantTier.b;
  @override
  List<SkillExample> get examples => const [
        SkillExample('Oblicz dylatację długość 50 m delta 100 C materiał 304L',
            'Calculate thermal expansion length 50 m delta 100 C material 304L'),
        SkillExample(
            'Dylatacja długość 10 metrów różnica temperatur 80 C stal węglowa',
            'Thermal expansion length 10 meters temperature difference 80 C carbon steel'),
        SkillExample('Dylatacja długość 5 m delta 50 K aluminium',
            'Thermal expansion length 5 m delta 50 K aluminium'),
        SkillExample('Dylatacja długość 200 cm delta 20 C 316L',
            'Thermal expansion length 200 cm delta 20 C 316L'),
        SkillExample('Dylatacja długość 1000 mm delta 10 K CuNi',
            'Thermal expansion length 1000 mm delta 10 K CuNi'),
        SkillExample('Oblicz dylatację', 'Calculate thermal expansion'),
      ];
  @override
  List<SkillRejection> get rejections => const [
        SkillRejection('otwórz dylatację', routesTo: 'tool.open'),
        SkillRejection('do czego służy dylatacja', routesTo: 'tool.explain'),
        SkillRejection('oblicz spadek 1% na 6 m'),
      ];
  @override
  SkillMatch? match(Utterance u, AssistantContext ctx) {
    if (explainedTool(u) != null ||
        RegExp(r'^(?:otworz|pokaz|open|show)\b').hasMatch(u.folded)) {
      return null;
    }
    if (!u.hasStem(const ['dylatac', 'rozszerzaln']) &&
        !u.hasAny(const ['thermal expansion'])) {
      return null;
    }
    final s = _slots(u);
    return SkillMatch(
        this,
        s.isNotEmpty || u.hasStem(const ['oblicz', 'policz', 'calculate'])
            ? .92
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
    if (s.containsKey(slot)) return s;
    if (slot == 'length_m') {
      final lengths = <double>{};
      for (var i = 0; i + 1 < u.items.length; i++) {
        final scale = lengthUnitScale(u.items[i + 1].word);
        if (u.items[i].isNumber && scale != null) {
          lengths.add(signedQuantity(u, i) * scale / 1000);
        }
      }
      if (lengths.length == 1) return {slot: lengths.single};
    }
    if (slot == 'delta_k') {
      final prefixed = Utterance('delta ${u.raw}', lang: ctx.lang);
      final v = _temperature(prefixed, const ['delta']);
      if (v != null) return {slot: v};
    }
    return null;
  }

  @override
  Future<SkillResult> run(SkillMatch m, AssistantContext ctx) async {
    AskResult ask(String key, String pl, String en) =>
        AskResult(key, AssistantText(pl, en), partial: m);
    final length = m.slots['length_m'];
    if (length is! num || !length.isFinite || length <= 0) {
      return ask(
          'length_m',
          'Jaka jest długość rurociągu? Podaj jednostkę, np. 50 metrów.',
          'What is the pipeline length? Include a unit, e.g. 50 meters.');
    }
    final delta = m.slots['delta_k'];
    if (delta is! num || !delta.isFinite || delta < 0) {
      return ask(
          'delta_k',
          'Jaka jest różnica temperatur? Podaj ΔT w °C lub K (np. 80 C).',
          'What is the temperature difference? Give ΔT in °C or K (e.g. 80 C).');
    }
    final material = ExpansionMaterial.values
        .where((v) => v.name == m.slots['material'])
        .firstOrNull;
    if (material == null) {
      return ask(
          'material',
          'Jaki materiał: 304L, 316L, stal węglowa, aluminium czy CuNi?',
          'Which material: 304L, 316L, carbon steel, aluminium or CuNi?');
    }
    final result = thermalExpansionMm(
        kExpansionAlpha[material]!, length.toDouble(), delta.toDouble());
    if (!result.isFinite) {
      return const FailedResult(AssistantText(
          'Wynik poza zakresem. Sprawdź długość i różnicę temperatur.',
          'Result out of range. Check length and temperature difference.'));
    }
    return AnswerResult(
        AssistantAnswer(
            text: AssistantText(
                'Zmiana długości wynosi ${fmt(result, ctx.lang)} mm dla ${fmt(length.toDouble(), ctx.lang)} m i różnicy ${fmt(delta.toDouble(), ctx.lang)} K. To przybliżenie ze średniego współczynnika 20–100 °C; przy wyższych temperaturach współczynnik rośnie. Wynik nie potwierdza doboru kompensacji trasy.',
                'Length change is ${fmt(result, ctx.lang)} mm for ${fmt(length.toDouble(), ctx.lang)} m and a ${fmt(delta.toDouble(), ctx.lang)} K difference. This is an estimate using a mean coefficient for 20–100 °C; the coefficient rises at higher temperatures. The result does not verify the route compensation design.')),
        show: ShowInModule(toolId,
            {'length_m': length, 'delta_k': delta, 'material': material.name}));
  }
}
