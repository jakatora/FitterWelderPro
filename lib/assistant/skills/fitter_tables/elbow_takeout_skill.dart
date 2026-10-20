import '../../../data/elbow_takeouts.dart';
import '../../../services/takeout_catalog.dart';
import '../../core/skill.dart';
import '../core/explain_tool_skill.dart' show explainedTool;
import '../core/skill_words.dart';
import '../fitter_routes/quantities.dart';

Map<String, Object?> _slots(Utterance u) {
  final s = <String, Object?>{};
  final dn = u.dn(), nps = u.npsInches(), angle = angleValue(u);
  if (u.mentionsDn) s['dn'] = dn ?? double.nan;
  if (nps != null) s['nps_in'] = nps;
  if (angle != null) s['angle_deg'] = angle;
  final families = <ElbowRadiusType>{};
  if (u.hasAny(const ['lr', 'long radius', 'dlugi promien']) ||
      RegExp(r'\b1[.,]5\s*d\b', caseSensitive: false).hasMatch(u.raw)) {
    families.add(ElbowRadiusType.long15D);
  }
  if (u.hasAny(const ['sr', 'short radius', 'krotki promien']) ||
      RegExp(r'\b1\s*d\b', caseSensitive: false).hasMatch(u.raw)) {
    families.add(ElbowRadiusType.short1D);
  }
  if (RegExp(r'\b3\s*d\b', caseSensitive: false).hasMatch(u.raw)) {
    families.add(ElbowRadiusType.long3D);
  }
  if (families.isNotEmpty) {
    s['family'] = families.length == 1 ? families.single.name : 'ambiguous';
  }
  return s;
}

class ElbowTakeoutSkill extends AssistantSkill {
  @override
  String get id => 'elbow.takeout';
  @override
  String get toolId => 'elbow_takeouts';
  @override
  AssistantTier get tier => AssistantTier.b;
  @override
  List<SkillExample> get examples => const [
        SkillExample('Wymiar kolana DN50 LR kąt 45 stopni',
            'Elbow takeout DN50 LR angle 45 degrees'),
        SkillExample('Wymiar kolana DN50 SR kąt 90 stopni',
            'Elbow takeout DN50 SR angle 90 degrees'),
        SkillExample('Wymiar kolana DN100 3D kąt 45 stopni',
            'Elbow takeout DN100 3D angle 45 degrees'),
        SkillExample('Wymiar kolana 2 cale LR kąt 90 stopni',
            'Elbow takeout 2 inches LR angle 90 degrees'),
        SkillExample('Wymiar kolana DN50 LR kąt 30 stopni',
            'Elbow takeout DN50 LR angle 30 degrees'),
        SkillExample('Oblicz wymiar kolana', 'Calculate elbow takeout'),
      ];
  @override
  List<SkillRejection> get rejections => const [
        SkillRejection('otwórz wymiary kolan', routesTo: 'tool.open'),
        SkillRejection('narysuj kolano DN50 LR 90 stopni'),
        SkillRejection('oblicz cięcie kolana DN50'),
      ];
  @override
  SkillMatch? match(Utterance u, AssistantContext ctx) {
    if (explainedTool(u) != null ||
        RegExp(r'^(?:otworz|pokaz|open|show)\b').hasMatch(u.folded) ||
        kCommandVerbRe.hasMatch(u.folded) ||
        u.hasStem(const ['ciec', 'cieci', 'cut', 'offset'])) {
      return null;
    }
    if (!u.hasStem(const ['kolan', 'elbow']) ||
        (!u.hasStem(const ['wymiar', 'takeout']) &&
            !u.hasAny(const [
              'take out',
              'centre to face',
              'center to face',
              'lr',
              'sr',
              '3d'
            ]))) {
      return null;
    }
    final s = _slots(u);
    return SkillMatch(this,
        s.isNotEmpty || u.hasStem(const ['oblicz', 'calculate']) ? .93 : .65,
        slots: s, utterance: u);
  }

  @override
  Map<String, Object?> slotsFrom(Utterance u, AssistantContext ctx) =>
      _slots(u);
  @override
  Map<String, Object?>? fillSlot(
      String slot, Utterance u, AssistantContext ctx) {
    final s = _slots(u);
    return s.containsKey(slot) || slot == 'dn' && s.containsKey('nps_in')
        ? s
        : null;
  }

  @override
  Future<SkillResult> run(SkillMatch m, AssistantContext ctx) async {
    AskResult ask(String k, String pl, String en) =>
        AskResult(k, AssistantText(pl, en), partial: m);
    final s = m.slots;
    final nps = s['nps_in'] as double?;
    final npsRow = nps == null
        ? null
        : kElbowTakeouts
            .where((r) => (r.npsIn - nps).abs() < .00001)
            .firstOrNull;
    final dn = s.containsKey('dn') ? s['dn'] : npsRow?.dn;
    if (dn is! int || !kElbowTakeouts.any((r) => r.dn == dn)) {
      return ask('dn', 'Jakie DN lub NPS w calach ma kolano?',
          'What elbow DN or NPS in inches?');
    }
    if (nps != null && (npsRow == null || npsRow.dn != dn)) {
      return const FailedResult(AssistantText(
          'DN i NPS są sprzeczne. Podaj jeden poprawny rozmiar.',
          'DN and NPS conflict. Give one correct size.'));
    }
    final family =
        ElbowRadiusType.values.where((v) => v.name == s['family']).firstOrNull;
    if (family == null) {
      return ask('family', 'Jaka rodzina kolana: LR (1,5D), SR (1D) czy 3D?',
          'Which elbow family: LR (1.5D), SR (1D) or 3D?');
    }
    final angle = s['angle_deg'];
    if (angle is! num || !angle.isFinite || angle <= 0 || angle > 90) {
      return ask('angle_deg', 'Jaki kąt kolana w stopniach, powyżej 0 do 90°?',
          'What elbow angle in degrees, greater than 0 up to 90°?');
    }
    final r =
        b169ElbowTakeout(dn: dn, type: family, angleDeg: angle.toDouble());
    if (r == null || !r.mm.isFinite) {
      return const FailedResult(
          AssistantText(
              'Ta rodzina kolana nie występuje dla tego rozmiaru w tabeli ASME B16.9. Wybierz inną rodzinę lub użyj własnych wymiarów z karty elementu.',
              'This elbow family is not listed for this size in ASME B16.9. Choose another family or use dimensions from the component datasheet.'),
          reportMissingCapability: true);
    }
    final table = switch (family) {
      ElbowRadiusType.short1D => '6.1-4',
      ElbowRadiusType.long15D => '6.1-1',
      ElbowRadiusType.long3D => '6.1-6'
    };
    final familyLabel = switch (family) {
      ElbowRadiusType.short1D => 'SR',
      ElbowRadiusType.long15D => 'LR',
      ElbowRadiusType.long3D => '3D'
    };
    final segment = r.basis == TakeoutBasis.segment;
    final dim = r.basis == TakeoutBasis.tableA90 ? 'A' : 'B';
    return AnswerResult(
        AssistantAnswer(
            text: AssistantText(
                'DN$dn $familyLabel, ${fmt(angle.toDouble(), ctx.lang)}°: centre–end ${fmt(r.mm, ctx.lang)} mm. ${segment ? 'To wymiar segmentu kolana 90°: A × tan(θ/2), a nie tablicowy wymiar gotowego kolana.' : 'Wymiar $dim z tabeli normy.'}',
                'DN$dn $familyLabel, ${fmt(angle.toDouble(), ctx.lang)}°: centre-to-end ${fmt(r.mm, ctx.lang)} mm. ${segment ? 'This is a segment of a 90° elbow: A × tan(θ/2), not a tabulated ready-made elbow dimension.' : 'Dimension $dim from the standard table.'}'),
            source: AssistantText.same(
                'ASME B16.9-2018 ${segment ? '§6.2.4' : 'Table $table'}')),
        show: ShowInModule(toolId, {'dn': dn}));
  }
}
