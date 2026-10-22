import '../../../domain/pwht/pwht_plan.dart';
import '../../core/skill.dart';
import '../core/explain_tool_skill.dart' show explainedTool;
import '../core/skill_words.dart';
import '../fitter_routes/quantities.dart';
import '../core/skill_guards.dart';

PwhtMaterial? _material(Utterance u) {
  final f = u.folded;
  final found = <PwhtMaterial>{
    if (RegExp(r'\bp ?no ?1\b|\bp1\b(?! ?5)|\ba106\b|\ba105\b|\bwpb\b|\bp235|\bp265|\bweglow')
        .hasMatch(f))
      PwhtMaterial.p1,
    if (RegExp(r'\bp ?no ?3\b|\b16mo3\b|\bf1\b|\bpol ?molibden').hasMatch(f))
      PwhtMaterial.p3,
    if (RegExp(r'\bp ?no ?4\b|\bp1[12]\b|\bf1[12]\b|\b13crmo').hasMatch(f))
      PwhtMaterial.p4,
    if (RegExp(r'\bp ?no ?5 ?a\b|\bp22\b|\bf22\b|\b10crmo9').hasMatch(f))
      PwhtMaterial.p5a,
    if (RegExp(r'\bp ?no ?15 ?e\b|\bp91\b|\bf91\b|\bwp91\b|\bx10crmovnb')
        .hasMatch(f))
      PwhtMaterial.p15e,
    if (RegExp(r'\bp ?no ?8\b|\b30[4]l?\b|\b316l?\b|\bnierdzew|\baustenit')
        .hasMatch(f))
      PwhtMaterial.p8,
  };
  return found.length == 1 ? found.single : null;
}

PwhtCode? _code(Utterance u) {
  final f = u.folded;
  final b313 = RegExp(r'\bb ?31 ?3\b|\bb31\.3\b|\bprocesow').hasMatch(f);
  final b311 = RegExp(r'\bb ?31 ?1\b|\bb31\.1\b|\benergetyczn|\bpower piping')
      .hasMatch(f);
  if (b313 == b311) return null;
  return b313 ? PwhtCode.asmeB313 : PwhtCode.asmeB311;
}

Map<String, Object?> _slots(Utterance u) {
  final out = <String, Object?>{};
  final code = _code(u);
  if (code != null) out['code'] = code.name;
  final material = _material(u);
  if (material != null) out['material'] = material.name;
  final t = lengthNear(u, const ['grubos', 'scian', 'thickness', 'wall', 't']);
  if (t != null) out['thickness_mm'] = t;
  final od = lengthNear(u, const ['od', 'srednic', 'diameter']);
  if (od != null) out['od_mm'] = od;
  final ww = lengthNear(u, const ['szerokos', 'lico', 'width']);
  if (ww != null) out['weld_width_mm'] = ww;
  return out;
}

class PwhtPlanSkill extends AssistantSkill {
  @override
  String get id => 'pwht.plan';
  @override
  String get toolId => 'pwht_planner';
  @override
  AssistantTier get tier => AssistantTier.b;
  @override
  List<SkillExample> get examples => const [
        SkillExample('Czy potrzebne PWHT B31.3 P-No 1 grubość 25 mm',
            'Is PWHT required B31.3 P-No 1 thickness 25 mm'),
        SkillExample('Plan PWHT B31.1 P91 grubość 30 mm',
            'PWHT plan B31.1 P91 thickness 30 mm'),
        SkillExample('Wyżarzanie odprężające B31.3 13CrMo4-5 grubość 15 mm OD 168,3 mm',
            'Stress relief B31.3 13CrMo4-5 thickness 15 mm OD 168.3 mm'),
        SkillExample('Ile trzymać w PWHT B31.3 P22 grubość 40 mm',
            'How long to hold PWHT B31.3 P22 thickness 40 mm'),
        SkillExample('PWHT B31.1 stal węglowa grubość 19 mm',
            'PWHT B31.1 carbon steel thickness 19 mm'),
        SkillExample('Zaplanuj obróbkę cieplną PWHT', 'Plan PWHT heat treatment'),
      ];
  @override
  List<SkillRejection> get rejections => const [
        SkillRejection('otwórz obróbkę cieplną po spawaniu', routesTo: 'tool.open'),
        SkillRejection('do czego służy obróbka cieplna po spawaniu',
            routesTo: 'tool.explain'),
        SkillRejection('jakie podgrzewanie wstępne dla P91'),
      ];

  @override
  SkillMatch? match(Utterance u, AssistantContext ctx) {
    if (explainedTool(u) != null ||
        kOpenOrAboutStart.hasMatch(u.folded)) {
      return null;
    }
    if (u.hasStem(const ['podgrzew', 'preheat']) && !u.hasStem(const ['pwht'])) {
      return null;
    }
    if (!u.hasStem(const ['pwht', 'wyzarz', 'odprez', 'stress reliev']) &&
        !u.hasAny(const ['obrobka cieplna', 'obrobke cieplna', 'heat treatment',
          'stress relief'])) {
      return null;
    }
    final s = _slots(u);
    return SkillMatch(this, s.isNotEmpty ? .93 : .75, slots: s, utterance: u);
  }

  @override
  Map<String, Object?> slotsFrom(Utterance u, AssistantContext ctx) =>
      _slots(u);

  @override
  Map<String, Object?>? fillSlot(
      String slot, Utterance u, AssistantContext ctx) {
    final s = _slots(u);
    if (s.containsKey(slot)) return {slot: s[slot]};
    if (slot == 'thickness_mm') {
      final n = u.items.where((i) => i.isNumber).toList();
      if (n.length == 1) return {slot: n.single.value};
    }
    return null;
  }

  @override
  Future<SkillResult> run(SkillMatch m, AssistantContext ctx) async {
    AskResult ask(String key, String pl, String en) =>
        AskResult(key, AssistantText(pl, en), partial: m);
    final code = PwhtCode.values.where((c) => c.name == m.slots['code']).firstOrNull;
    if (code == null) {
      return ask('code', 'Wg jakiej normy: ASME B31.3 czy B31.1?',
          'Which code: ASME B31.3 or B31.1?');
    }
    final material =
        PwhtMaterial.values.where((p) => p.name == m.slots['material']).firstOrNull;
    if (material == null) {
      return ask(
          'material',
          'Jaka grupa materiału: P-No 1 (węglowa), 3, 4 (P11/P12), 5A (P22), 15E (P91) czy 8 (nierdzewna)?',
          'Which material group: P-No 1 (carbon), 3, 4 (P11/P12), 5A (P22), 15E (P91) or 8 (stainless)?');
    }
    final t = m.slots['thickness_mm'];
    if (t is! num || !t.isFinite || t <= 0) {
      return ask('thickness_mm', 'Jaka grubość kontrolna złącza w mm?',
          'What is the governing joint thickness in mm?');
    }
    double? opt(String key) {
      final v = m.slots[key];
      return v is num && v.isFinite && v > 0 ? v.toDouble() : null;
    }

    final plan = planPwht(PwhtInput(
        code: code,
        material: material,
        thicknessMm: t.toDouble(),
        outsideDiameterMm: opt('od_mm'),
        weldWidthMm: opt('weld_width_mm')));
    if (plan == null) {
      return const FailedResult(AssistantText(
          'Aplikacja nie ma sprawdzonych danych dla tej normy i grupy.',
          'The app has no verified data for this code and group.'));
    }
    String f(num v) => fmt(v.toDouble(), ctx.lang);
    final info = pwhtMaterialInfo(material);
    final (headPl, headEn) = switch (plan.verdict) {
      PwhtVerdict.required => ('PWHT wymagane', 'PWHT required'),
      PwhtVerdict.exemptIfConditionsMet => (
          'zwolnienie z PWHT tylko po spełnieniu warunków tabeli',
          'exempt from PWHT only if the table conditions are met'
        ),
      PwhtVerdict.exempt => ('tabela zwalnia z PWHT', 'the table exempts from PWHT'),
      PwhtVerdict.notRequiredByTable => (
          'tabela nie wymaga PWHT (chyba że WPS / specyfikacja)',
          'the table does not require PWHT (unless the WPS / specification does)'
        ),
    };
    var pl = '${code.label}, ${info.pNo}, grubość ${f(t)} mm: $headPl.';
    var en = '${code.label}, ${info.pNo}, thickness ${f(t)} mm: $headEn.';
    final range = plan.entry.holdRange;
    if (range != null && plan.holdMinutes != null) {
      pl += ' Wytrzymanie ${range.minC}–${range.maxC} °C, min. ${plan.holdMinutes} min';
      en += ' Hold ${range.minC}–${range.maxC} °C, min. ${plan.holdMinutes} min';
      if (plan.heatingRateCPerH != null && plan.coolingRateCPerH != null) {
        pl += '; nagrzewanie maks. ${f(plan.heatingRateCPerH!)} °C/h, '
            'chłodzenie maks. ${f(plan.coolingRateCPerH!)} °C/h';
        en += '; heating max ${f(plan.heatingRateCPerH!)} °C/h, '
            'cooling max ${f(plan.coolingRateCPerH!)} °C/h';
      }
      final cycle = plan.cycle;
      if (cycle != null) {
        pl += '; część kontrolowana cyklu ok. ${f(cycle.totalHours)} h';
        en += '; controlled part of the cycle approx. ${f(cycle.totalHours)} h';
      }
      pl += '.';
      en += '.';
    }
    pl += ' Wiążą WPS, procedura PWHT i specyfikacja projektu.';
    en += ' The WPS, PWHT procedure and project specification govern.';
    return AnswerResult(
        AssistantAnswer(text: AssistantText(pl, en)),
        show: ShowInModule(toolId, {
          'code': code.name,
          'material': material.name,
          'thickness_mm': t.toDouble(),
          if (opt('od_mm') != null) 'od_mm': opt('od_mm'),
          if (opt('weld_width_mm') != null) 'weld_width_mm': opt('weld_width_mm'),
        }));
  }
}
