import '../../../domain/fitter/fitter_calcs.dart';
import '../../core/skill.dart';
import '../core/explain_tool_skill.dart' show explainedTool;
import '../core/skill_words.dart';
import 'quantities.dart';

Map<String, Object?> _slots(Utterance u) {
  final od = lengthNear(u, const ['od', 'srednic', 'diameter']);
  final circumference = lengthNear(u, const ['obwod', 'circumference']);
  final degrees = angleValue(u), percent = percentValue(u);
  return {
    if (od != null) 'od_mm': od,
    if (circumference != null) 'circumference_mm': circumference,
    if (degrees != null) 'degrees': degrees,
    if (percent != null) 'percent': percent,
  };
}

class ElbowRotationSkill extends AssistantSkill {
  @override
  String get id => 'elbow.rotation';
  @override
  String get toolId => 'elbow_rotation';
  @override
  AssistantTier get tier => AssistantTier.b;
  @override
  List<SkillExample> get examples => const [
        SkillExample('Oblicz obrót kolanka OD 100 mm kąt 90 stopni',
            'Calculate elbow rotation OD 100 mm angle 90 degrees'),
        SkillExample('Obrót kolana obwód 400 mm 25%',
            'Elbow rotation circumference 400 mm 25%'),
        SkillExample('Oblicz obrót kolanka', 'Calculate elbow rotation'),
        SkillExample('Obrót kolana OD 10 cm 50 procent',
            'Elbow rotation OD 10 cm 50 percent'),
        SkillExample('Obrót kolanka obwód 300 mm kąt 60 stopni',
            'Elbow rotation circumference 300 mm angle 60 degrees'),
        SkillExample('Obrót kolanka OD 60,3 mm kąt 45 stopni',
            'Elbow rotation OD 60.3 mm angle 45 degrees'),
      ];
  @override
  List<SkillRejection> get rejections => const [
        SkillRejection('otwórz obrót kolanka', routesTo: 'tool.open'),
        SkillRejection('narysuj kolano w górę'),
        SkillRejection(
            'cięcie kolanka baza 90 extrados 180 mm intrados 90 mm docelowy 45',
            routesTo: 'elbow.cut'),
      ];
  @override
  SkillMatch? match(Utterance u, AssistantContext ctx) {
    if (explainedTool(u) != null ||
        kCommandVerbRe.hasMatch(u.folded) ||
        RegExp(r'^(?:otworz|pokaz|open|show)\b').hasMatch(u.folded)) {
      return null;
    }
    if (!u.hasStem(const ['kolan', 'elbow']) ||
        !u.hasStem(const ['obrot', 'rotac', 'rotation', 'rotate'])) {
      return null;
    }
    final s = _slots(u);
    return SkillMatch(
        this,
        s.isNotEmpty || u.hasStem(const ['oblicz', 'policz', 'calculate'])
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
    if (slot == 'size' &&
        (s.containsKey('od_mm') || s.containsKey('circumference_mm'))) {
      return {'od_mm': null, 'circumference_mm': null, ...s};
    }
    if (slot == 'rotation' &&
        (s.containsKey('degrees') || s.containsKey('percent'))) {
      return {'degrees': null, 'percent': null, ...s};
    }
    return null;
  }

  @override
  Future<SkillResult> run(SkillMatch m, AssistantContext ctx) async {
    AskResult ask(String slot, String pl, String en) =>
        AskResult(slot, AssistantText(pl, en), partial: m);
    double? n(String k) => (m.slots[k] as num?)?.toDouble();
    final od = n('od_mm'),
        circ = n('circumference_mm'),
        deg = n('degrees'),
        pct = n('percent');
    if ((od == null) == (circ == null) ||
        od != null && (!od.isFinite || od <= 0) ||
        circ != null && (!circ.isFinite || circ <= 0)) {
      return ask(
          'size',
          'Podaj jeden wymiar: średnicę zewnętrzną OD albo zmierzony obwód, z jednostką (np. obwód 400 mm).',
          'Give one size: outside diameter OD or measured circumference, with a unit (e.g. circumference 400 mm).');
    }
    if ((deg == null) == (pct == null) ||
        deg != null && (!deg.isFinite || deg <= 0 || deg > 360) ||
        pct != null && (!pct.isFinite || pct <= 0 || pct > 100)) {
      return ask(
          'rotation',
          'Podaj obrót jako kąt większy od 0 do 360 stopni albo procent większy od 0 do 100%. Użyj jednej jednostki.',
          'Give rotation as an angle greater than 0 up to 360 degrees or a percentage greater than 0 up to 100%. Use one unit.');
    }
    final r =
        rotationArc(odMm: od, circumferenceMm: circ, degrees: deg, percent: pct)
            .arc;
    if (r == null || !r.arcMm.isFinite || !r.circumferenceMm.isFinite) {
      return const FailedResult(AssistantText(
          'Wynik poza zakresem. Sprawdź wymiary.',
          'Result out of range. Check dimensions.'));
    }
    return AnswerResult(
        AssistantAnswer(
            text: AssistantText(
                'Obrót ${fmt(r.degrees, ctx.lang)}° odpowiada ${fmt(r.arcMm, ctx.lang)} mm po obwodzie ${fmt(r.circumferenceMm, ctx.lang)} mm. Odmierz łuk na obwodzie od linii odniesienia; kierunek wybierz zgodnie z montażem.',
                'Rotation ${fmt(r.degrees, ctx.lang)}° corresponds to ${fmt(r.arcMm, ctx.lang)} mm along circumference ${fmt(r.circumferenceMm, ctx.lang)} mm. Measure the arc from the reference line; choose direction for the installation.')),
        show: ShowInModule(toolId, {
          if (od != null) 'od_mm': od,
          if (circ != null) 'circumference_mm': circ,
          if (deg != null) 'degrees': deg,
          if (pct != null) 'percent': pct
        }));
  }
}
