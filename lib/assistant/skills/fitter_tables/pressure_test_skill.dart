import 'dart:math' as math;

import '../../../domain/pressure_test/test_pressure.dart';
import '../../core/skill.dart';
import '../core/explain_tool_skill.dart' show explainedTool;
import '../core/labelled_numbers.dart';
import '../core/skill_words.dart';
import '../fitter_routes/quantities.dart';

PressureTestPreset? _preset(Utterance u) {
  final f = u.folded;
  final pneumatic = u.hasStem(const ['pneumat', 'powietrz', 'azot', 'nitrogen', 'air']);
  final found = <PressureTestPreset>{
    if (RegExp(r'\bb ?31[ .]?3\b').hasMatch(f))
      pneumatic ? PressureTestPreset.b313Pneumatic : PressureTestPreset.b313Hydro,
    if (RegExp(r'\bb ?31[ .]?1\b').hasMatch(f)) PressureTestPreset.b311Hydro,
    if (RegExp(r'\b13480\b|\bped\b|\ben 13480').hasMatch(f))
      PressureTestPreset.en13480Hydro,
    if (RegExp(r'\bviii ?1\b|\bviii\b|\bug ?99\b|\bzbiornik\w* cisnieniow')
        .hasMatch(f))
      PressureTestPreset.asmeVIII1Hydro,
  };
  return found.length == 1 ? found.single : null;
}

/// Ciśnienie obliczeniowe w barach: „16 bar”, „1,6 MPa”, „230 psi”.
double? _designBar(Utterance u) {
  final found = <double>{};
  final items = u.items;
  for (var i = 0; i + 1 < items.length; i++) {
    if (!items[i].isNumber) continue;
    final unit = items[i + 1].word;
    final v = items[i].value!;
    if (unit == 'bar' || unit.startsWith('barow') || unit == 'bary') {
      found.add(v);
    } else if (unit == 'mpa') {
      found.add(v * 10);
    } else if (unit == 'psi') {
      found.add(v / 14.5038);
    }
  }
  return found.length > 1 ? double.nan : found.singleOrNull;
}

Map<String, Object?> _slots(Utterance u) {
  final out = <String, Object?>{};
  final preset = _preset(u);
  if (preset != null) out['preset'] = preset.id;
  final design = _designBar(u);
  if (design != null) out['design_bar'] = design;
  final ratio = numberAfterLabel(
      u, (w) => w == 'st' || w == 'lsr' || w.startsWith('stosun') || w == 'ratio',
      skip: const {'s', 'naprezen'});
  if (ratio != null) out['ratio'] = ratio;
  final od = lengthNear(u, const ['od', 'srednic', 'diameter']);
  if (od != null) out['od_mm'] = od;
  final wall = lengthNear(u, const ['scian', 'wall']);
  if (wall != null) out['wall_mm'] = wall;
  final length = lengthNear(u, const ['dlugos', 'odcin', 'length', 'run']);
  if (length != null) out['length_m'] = length / 1000;
  return out;
}

class PressureTestSkill extends AssistantSkill {
  @override
  String get id => 'pressure.test';
  @override
  String get toolId => 'hydrotest';
  @override
  AssistantTier get tier => AssistantTier.b;
  @override
  List<SkillExample> get examples => const [
        SkillExample('Ciśnienie próby B31.3 hydro ciśnienie projektowe 16 bar',
            'Test pressure B31.3 hydro design pressure 16 bar'),
        SkillExample('Próba pneumatyczna B31.3 projektowe 10 bar',
            'Pneumatic test B31.3 design 10 bar'),
        SkillExample('Próba ciśnieniowa EN 13480 PS 25 bar',
            'Pressure test EN 13480 PS 25 bar'),
        SkillExample(
            'Próba wodna B31.3 projektowe 40 bar OD 114,3 mm ścianka 6,02 mm długość 120 m',
            'Hydrotest B31.3 design 40 bar OD 114.3 mm wall 6.02 mm length 120 m'),
        SkillExample('Ciśnienie próby B31.1 projektowe 1,6 MPa',
            'Test pressure B31.1 design 1.6 MPa'),
        SkillExample('Policz ciśnienie próby', 'Calculate the test pressure'),
      ];
  @override
  List<SkillRejection> get rejections => const [
        SkillRejection('otwórz próbę ciśnieniową', routesTo: 'tool.open'),
        SkillRejection('do czego służy próba ciśnieniowa',
            routesTo: 'tool.explain'),
        SkillRejection('przelicz 16 bar na psi'),
      ];

  @override
  SkillMatch? match(Utterance u, AssistantContext ctx) {
    if (explainedTool(u) != null ||
        RegExp(r'^(?:otworz|pokaz|open|show|do czego)\b').hasMatch(u.folded)) {
      return null;
    }
    if (u.hasStem(const ['przelicz', 'zamien', 'convert'])) return null;
    // Sama „próba/próbka” to też próbka spawalnicza — potrzebny kontekst
    // ciśnienia albo normy próby.
    final test = u.hasStem(const ['hydrotest', 'hydro']) ||
        (u.hasStem(const ['prob']) &&
            (u.hasStem(const ['cisnien', 'wodn', 'pneumat', 'szczelnos']) ||
                _preset(u) != null)) ||
        u.hasAny(const ['test pressure', 'pressure test', 'pneumatic test']);
    if (!test) return null;
    final s = _slots(u);
    return SkillMatch(this, s.isNotEmpty ? .92 : .7, slots: s, utterance: u);
  }

  @override
  Map<String, Object?> slotsFrom(Utterance u, AssistantContext ctx) =>
      _slots(u);

  @override
  Map<String, Object?>? fillSlot(
      String slot, Utterance u, AssistantContext ctx) {
    final s = _slots(u);
    if (s.containsKey(slot)) return {slot: s[slot]};
    if (slot == 'design_bar') {
      final n = u.items.where((i) => i.isNumber).toList();
      if (n.length == 1 && u.items.length == 1) return {slot: n.single.value};
    }
    return null;
  }

  @override
  Future<SkillResult> run(SkillMatch m, AssistantContext ctx) async {
    AskResult ask(String key, String pl, String en) =>
        AskResult(key, AssistantText(pl, en), partial: m);
    final preset = PressureTestPreset.values
        .where((p) => p.id == m.slots['preset'])
        .firstOrNull;
    if (preset == null) {
      return ask(
          'preset',
          'Wg czego próba: B31.3 wodna, B31.3 pneumatyczna, B31.1, EN 13480 czy ASME VIII-1?',
          'Which test: B31.3 hydro, B31.3 pneumatic, B31.1, EN 13480 or ASME VIII-1?');
    }
    final design = m.slots['design_bar'];
    if (design is! num || !design.isFinite || design <= 0 || design > 2000) {
      return ask('design_bar',
          'Jakie ciśnienie obliczeniowe (bar, MPa albo psi)?',
          'What is the design pressure (bar, MPa or psi)?');
    }
    final ratioSlot = m.slots['ratio'];
    final ratioGiven = ratioSlot is num && ratioSlot.isFinite && ratioSlot > 0;
    final r = computeTestPressure(
        preset: preset,
        designBar: design.toDouble(),
        stressRatio: ratioGiven ? ratioSlot.toDouble() : 1.0);
    String f(num v) => fmt(v.toDouble(), ctx.lang);
    // Ciśnienie próby w GÓRĘ do 0,1 bar — minimum nie może spaść przez
    // zaokrąglenie.
    final pt = (r.testPressureBar * 10 - 1e-9).ceilToDouble() / 10;
    final method = preset.method == PressureTestMethod.pneumatic;
    var pl = '${preset.code} ${preset.clause}: minimalne ciśnienie próby '
        '${f(pt)} bar (${method ? 'pneumatyczna' : 'wodna'}, P = ${f(design)} bar).';
    var en = '${preset.code} ${preset.clause}: minimum test pressure '
        '${f(pt)} bar (${method ? 'pneumatic' : 'hydrostatic'}, P = ${f(design)} bar).';
    if (preset.ratioSymbol != null) {
      pl += ratioGiven
          ? ' ${preset.ratioSymbol} = ${f(r.ratioApplied)}${r.ratioCapped ? ' (ograniczone)' : ''}.'
          : ' Przyjąłem ${preset.ratioSymbol} = 1 — podaj, jeśli temperatura projektowa to zmienia.';
      en += ratioGiven
          ? ' ${preset.ratioSymbol} = ${f(r.ratioApplied)}${r.ratioCapped ? ' (capped)' : ''}.'
          : ' Assumed ${preset.ratioSymbol} = 1 — give it if the design temperature changes it.';
    }
    if (r.maxTestPressureBar != null) {
      pl += ' Nie przekraczaj ${f(r.maxTestPressureBar!)} bar.';
      en += ' Do not exceed ${f(r.maxTestPressureBar!)} bar.';
    }
    if (preset.minHoldMinutes != null) {
      pl += ' Wytrzymanie min. ${f(preset.minHoldMinutes!)} min (${preset.holdClause}).';
      en += ' Hold at least ${f(preset.minHoldMinutes!)} min (${preset.holdClause}).';
    }
    final fields = <String, Object?>{
      'preset': preset.id,
      'design_bar': design.toDouble(),
      if (ratioGiven) 'ratio': ratioSlot.toDouble(),
    };
    final od = m.slots['od_mm'], wall = m.slots['wall_mm'], len = m.slots['length_m'];
    if (od is num && wall is num && len is num &&
        od > 0 && wall > 0 && wall * 2 < od && len > 0) {
      final id = od - 2 * wall;
      final litres = math.pi * id * id / 4 * len * 1000 * 1e-6;
      fields.addAll({
        'od_mm': od.toDouble(),
        'wall_mm': wall.toDouble(),
        'length_m': len.toDouble()
      });
      pl += ' Woda do napełnienia: ok. ${f(litres.ceilToDouble())} l.';
      en += ' Water to fill: approx. ${f(litres.ceilToDouble())} L.';
    }
    pl += ' Wiąże procedura próby i specyfikacja projektu.';
    en += ' The test procedure and project specification govern.';
    return AnswerResult(AssistantAnswer(text: AssistantText(pl, en)),
        show: ShowInModule(toolId, fields));
  }
}
