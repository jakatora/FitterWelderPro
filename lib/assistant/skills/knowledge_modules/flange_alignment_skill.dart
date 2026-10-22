import '../../../domain/flange/flange_pcc1.dart';
import '../../core/skill.dart';
import '../core/explain_tool_skill.dart' show explainedTool;
import '../core/skill_words.dart';
import '../fitter_routes/quantities.dart';

Map<String, Object?> _slots(Utterance u) {
  final out = <String, Object?>{};
  final f = u.folded;
  if (RegExp(r'\bosi\b|\bcenterline|high low').hasMatch(f)) {
    out['criterion'] = 'centerline';
  } else if (RegExp(r'\brownoleg\w*|\bparallel|\bszczelin\w* po obwodzie|\bklin\w*')
      .hasMatch(f)) {
    out['criterion'] = 'parallelism';
  } else if (RegExp(r'\bobrot\w*|\botwor\w*|\brotation|\btwo hole').hasMatch(f)) {
    out['criterion'] = 'rotation';
  } else if (RegExp(r'\brozsuniec\w*|\bspacing|\bodstep\w* kolnierzy').hasMatch(f)) {
    out['criterion'] = 'spacing';
  }
  final measured = lengthNear(u, const ['zmierz', 'pomiar', 'measured', 'mam', 'jest', 'wynosi']);
  if (measured != null) out['measured_mm'] = measured;
  final gasket = lengthNear(u, const ['uszczel', 'gasket']);
  if (gasket != null) out['gasket_mm'] = gasket;
  return out;
}

/// Osiowanie kołnierzy przed skręceniem wg ASME PCC-1-2019 zał. E — te same
/// granice co moduł „Odbiór kołnierzy”. Protokół z punktami zostaje w module.
class FlangeAlignmentSkill extends AssistantSkill {
  @override
  String get id => 'flange.alignment';
  @override
  String get toolId => 'flange_check';
  @override
  AssistantTier get tier => AssistantTier.b;
  @override
  bool get readOnly => true;
  @override
  List<SkillExample> get examples => const [
        SkillExample('Jaka tolerancja osiowania kołnierzy', 'What is the flange alignment tolerance'),
        SkillExample('Równoległość kołnierzy zmierzone 1 mm', 'Flange parallelism measured 1 mm'),
        SkillExample('Przesunięcie osi kołnierzy zmierzone 1,2 mm',
            'Flange centerline offset measured 1.2 mm'),
        SkillExample('Tolerancja obrotu otworów kołnierza', 'Flange bolt hole rotation tolerance'),
        SkillExample('Rozsunięcie kołnierzy 7 mm uszczelka 3 mm',
            'Flange spacing 7 mm gasket 3 mm'),
        SkillExample('Odbiór kołnierza przed skręceniem', 'Flange check before bolting up'),
      ];
  @override
  List<SkillRejection> get rejections => const [
        SkillRejection('otwórz odbiór kołnierzy', routesTo: 'tool.open'),
        SkillRejection('do czego służy odbiór kołnierzy', routesTo: 'tool.explain'),
        SkillRejection('jaki moment dokręcenia śruby 3/4 cala B7 na smarze'),
      ];

  @override
  SkillMatch? match(Utterance u, AssistantContext ctx) {
    if (explainedTool(u) != null ||
        RegExp(r'^(?:otworz|do czego)\b').hasMatch(u.folded)) {
      return null;
    }
    if (!u.hasStem(const ['kolnierz', 'flange'])) return null;
    if (u.hasStem(const ['moment', 'torque', 'dokrec', 'szpil', 'stud', 'spool'])) {
      return null;
    }
    final aligned = u.hasStem(const [
      'osiow', 'rownoleg', 'przesunie', 'rozsunie', 'obrot', 'odbior', 'toleranc',
      'alignment', 'parallel', 'centerline', 'spacing', 'rotation', 'check'
    ]);
    if (!aligned) return null;
    return SkillMatch(this, .9, slots: _slots(u), utterance: u);
  }

  @override
  Map<String, Object?> slotsFrom(Utterance u, AssistantContext ctx) =>
      _slots(u);

  @override
  Future<SkillResult> run(SkillMatch m, AssistantContext ctx) async {
    String f(num v) => fmt(v.toDouble(), ctx.lang);
    final c = m.slots['criterion'];
    final measured = m.slots['measured_mm'];
    String verdict(double limit, bool en) {
      if (measured is! num || !measured.isFinite) return '';
      final ok = measured <= limit + 1e-6;
      return en
          ? ' Measured ${f(measured)} mm — ${ok ? 'within' : 'OUT of'} the limit.'
          : ' Zmierzone ${f(measured)} mm — ${ok ? 'w granicy' : 'POZA granicą'}.';
    }

    const tail = (
      ' Pełny protokół (punkty szczeliny, lista montażu) zrobisz w module; zakład może mieć ostrzejsze tolerancje.',
      ' Build the full record (gap points, assembly checklist) in the module; the site may use tighter tolerances.'
    );
    switch (c) {
      case 'centerline':
        final l = kPcc1Centerline.mm;
        return _answer(
            'Przesunięcie osi kołnierzy: najwyżej ${f(l)} mm (1/16″), PCC-1 zał. E-2.4(a).${verdict(l, false)}${tail.$1}',
            'Flange centerline offset: at most ${f(l)} mm (1/16″), PCC-1 Appendix E-2.4(a).${verdict(l, true)}${tail.$2}');
      case 'parallelism':
        final l = kPcc1Parallelism.mm;
        return _answer(
            'Równoległość: różnica największej i najmniejszej szczeliny najwyżej ${f(l)} mm (1/32″), mierzona na zewnętrznej średnicy przylgi, PCC-1 E-2.4(b).${verdict(l, false)}${tail.$1}',
            'Parallelism: max minus min gap at most ${f(l)} mm (1/32″), measured at the gasket face OD, PCC-1 E-2.4(b).${verdict(l, true)}${tail.$2}');
      case 'rotation':
        final l = kPcc1Rotation.mm;
        return _answer(
            'Obrót otworów: śruba wchodzi prostopadle albo otwory w granicy ${f(l)} mm (1/8″), PCC-1 E-2.4(c).${verdict(l, false)}${tail.$1}',
            'Bolt hole rotation: the bolt passes square or holes within ${f(l)} mm (1/8″), PCC-1 E-2.4(c).${verdict(l, true)}${tail.$2}');
      case 'spacing':
        final g = m.slots['gasket_mm'];
        if (g is num && g.isFinite && g > 0) {
          final l = kPcc1GapFactor * g;
          return _answer(
              'Rozsunięcie kołnierzy w spoczynku: najwyżej 2 × grubość uszczelki = ${f(l)} mm, PCC-1 E-2.4(d).${verdict(l.toDouble(), false)}${tail.$1}',
              'Flange spacing at rest: at most 2 × gasket thickness = ${f(l)} mm, PCC-1 E-2.4(d).${verdict(l.toDouble(), true)}${tail.$2}');
        }
        return _answer(
            'Rozsunięcie kołnierzy w spoczynku: najwyżej 2 × grubość uszczelki (PCC-1 E-2.4(d)) — podaj grubość uszczelki, policzę granicę.${tail.$1}',
            'Flange spacing at rest: at most 2 × gasket thickness (PCC-1 E-2.4(d)) — give the gasket thickness to get the limit.${tail.$2}');
    }
    return _answer(
        'PCC-1-2019 zał. E: oś ≤ ${f(kPcc1Centerline.mm)} mm (1/16″), równoległość ≤ ${f(kPcc1Parallelism.mm)} mm (1/32″), obrót otworów ≤ ${f(kPcc1Rotation.mm)} mm (1/8″), rozsunięcie ≤ 2 × grubość uszczelki; zestawienie bez urządzeń < $kPcc1ForceTotalPct % obciążenia śrub.${tail.$1}',
        'PCC-1-2019 Appendix E: centerline ≤ ${f(kPcc1Centerline.mm)} mm (1/16″), parallelism ≤ ${f(kPcc1Parallelism.mm)} mm (1/32″), bolt hole rotation ≤ ${f(kPcc1Rotation.mm)} mm (1/8″), spacing ≤ 2 × gasket thickness; fit-up without devices < $kPcc1ForceTotalPct % of bolt load.${tail.$2}');
  }

  AnswerResult _answer(String pl, String en) => AnswerResult(
      AssistantAnswer(text: AssistantText(pl, en)), show: ShowInModule(toolId));
}
