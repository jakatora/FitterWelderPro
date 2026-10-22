import '../../../services/saddle_geometry.dart';
import '../../core/skill.dart';
import '../core/explain_tool_skill.dart' show explainedTool;
import '../core/skill_words.dart';
import 'quantities.dart';
import 'saddle_cut_skill.dart' show saddleDiameterSlots;
import '../core/skill_guards.dart';

Map<String, Object?> _slots(Utterance u) {
  final out = saddleDiameterSlots(u);
  final angle = angleValue(u);
  if (angle != null) out['angle_deg'] = angle;
  return out;
}

class SaddleTemplateSkill extends AssistantSkill {
  @override
  String get id => 'saddle.template';
  @override
  String get toolId => 'saddle_template';
  @override
  AssistantTier get tier => AssistantTier.b;
  @override
  List<SkillExample> get examples => const [
        SkillExample(
            'Szablon siodła rura główna 168,3 mm odgałęzienie 114,3 mm kąt 45 stopni',
            'Saddle template header 168.3 mm branch 114.3 mm angle 45 degrees'),
        SkillExample('Szablon siodła DN50 na DN100 kąt 60 stopni',
            'Saddle template DN50 on DN100 angle 60 degrees'),
        SkillExample('Siodło pod kątem 30 stopni 60,3 mm na 114,3 mm',
            'Saddle at 30 degrees 60.3 mm on 114.3 mm'),
        SkillExample('Szablon do wydruku siodło 48,3 mm na 88,9 mm kąt 90 stopni',
            'Printable saddle template 48.3 mm on 88.9 mm angle 90 degrees'),
        SkillExample('Odgałęzienie ukośne DN80 na DN150 kąt 45 stopni szablon',
            'Angled branch DN80 on DN150 angle 45 degrees template'),
        SkillExample('Zrób szablon siodła', 'Make a saddle template'),
      ];
  @override
  List<SkillRejection> get rejections => const [
        SkillRejection('otwórz szablon siodła do druku', routesTo: 'tool.open'),
        SkillRejection('do czego służy szablon siodła do druku',
            routesTo: 'tool.explain'),
        SkillRejection('siodło 90 stopni rura główna 100 mm odgałęzienie 60 mm',
            routesTo: 'saddle.cut'),
      ];

  @override
  SkillMatch? match(Utterance u, AssistantContext ctx) {
    if (explainedTool(u) != null ||
        kOpenOrAboutStart.hasMatch(u.folded)) {
      return null;
    }
    final saddle = u.hasStem(const ['siodl', 'siodel', 'wcink', 'saddle']) ||
        u.hasAny(const ['fish mouth', 'odgalezienie ukosne', 'angled branch']);
    if (!saddle) return null;
    // Szablon albo kąt inny niż sama tabela 90° — inaczej to „Siodło 90°”.
    final angle = angleValue(u);
    if (!u.hasStem(const ['szablon', 'template', 'druk', 'print', 'pdf']) &&
        (angle == null || angle == 90) &&
        !u.hasAny(const ['odgalezienie ukosne', 'angled branch'])) {
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
    if (slot == 'angle_deg') {
      final n = u.items.where((i) => i.isNumber).toList();
      if (n.length == 1) return {slot: n.single.value};
    }
    final single = s['header_od_mm'];
    if (single is num && s.length == 1) return {slot: single};
    return null;
  }

  @override
  Future<SkillResult> run(SkillMatch m, AssistantContext ctx) async {
    AskResult ask(String key, String pl, String en) =>
        AskResult(key, AssistantText(pl, en), partial: m);
    final header = m.slots['header_od_mm'];
    if (header is! num || !header.isFinite || header <= 0 || header > 2000) {
      return ask(
          'header_od_mm',
          'Jaka jest średnica zewnętrzna rury głównej? Podaj mm albo DN.',
          'What is the header outside diameter? Give mm or DN.');
    }
    final branch = m.slots['branch_od_mm'];
    if (branch is! num || !branch.isFinite || branch <= 0) {
      return ask('branch_od_mm',
          'Jaka jest średnica zewnętrzna odgałęzienia? Podaj mm albo DN.',
          'What is the branch outside diameter? Give mm or DN.');
    }
    final angle = m.slots['angle_deg'];
    if (angle is! num || !angle.isFinite) {
      return ask('angle_deg', 'Pod jakim kątem odgałęzienie (15–90°)?',
          'At what angle is the branch (15–90°)?');
    }
    if (branch > header) {
      return const FailedResult(AssistantText(
          'Odgałęzienie nie może być większe od rury głównej.',
          'The branch cannot be larger than the header.'));
    }
    if (angle < 15 || angle > 90) {
      return const FailedResult(AssistantText(
          'Szablon obsługuje kąty od 15 do 90°.',
          'The template supports angles from 15 to 90°.'));
    }
    final g = SaddleGeometry(
        headerOdMm: header.toDouble(),
        branchOdMm: branch.toDouble(),
        angleDeg: angle.toDouble());
    String f(num v) => fmt(v.toDouble(), ctx.lang);
    return AnswerResult(
        AssistantAnswer(
            text: AssistantText(
                'Szablon siodła: rura główna ${f(header)} mm, odgałęzienie ${f(branch)} mm, kąt ${f(angle)}°. Długość paska do owinięcia π·d = ${f(g.stripLengthMm)} mm, największa głębokość wycięcia ${f(g.maxDepthMm)} mm. Wydruk PDF 1:1 jest w module — sprawdź skalę linijką przed cięciem.',
                'Saddle template: header ${f(header)} mm, branch ${f(branch)} mm, angle ${f(angle)}°. Wrap strip length π·d = ${f(g.stripLengthMm)} mm, maximum cut depth ${f(g.maxDepthMm)} mm. The 1:1 PDF print is in the module — check the scale with a ruler before cutting.')),
        show: ShowInModule(toolId, {
          'header_od_mm': header.toDouble(),
          'branch_od_mm': branch.toDouble(),
          'angle_deg': angle.toDouble(),
        }));
  }
}
