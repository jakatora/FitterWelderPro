import '../../../domain/qualification/iso9606_range.dart';
import '../../core/skill.dart';
import '../core/explain_tool_skill.dart' show explainedTool;
import '../fitter_routes/quantities.dart';

Map<String, Object?> _slots(Utterance u) {
  final out = <String, Object?>{};
  var t = lengthNear(
      u, const ['grubos', 'scian', 'blach', 'blasz', 'thickness', 'wall', 's', 't']);
  final d = lengthNear(u, const ['srednic', 'rur', 'od', 'diameter', 'pipe', 'd']);
  // „2 mm plate” / „próbka 8 mm” — jedyna długość bez etykiety to grubość.
  if (t == null && d == null) {
    final values = <double>{};
    for (var i = 0; i + 1 < u.items.length; i++) {
      final scale = lengthUnitScale(u.items[i + 1].word);
      if (u.items[i].isNumber && scale != null) {
        values.add(u.items[i].value! * scale);
      }
    }
    if (values.length == 1) t = values.single;
  }
  if (t != null) out['thickness_mm'] = t;
  if (d != null) out['diameter_mm'] = d;
  final fillet = u.hasStem(const ['pachwin', 'fillet']) || u.hasAny(const ['fw']);
  final butt = u.hasStem(const ['czolow', 'butt']) || u.hasAny(const ['bw']);
  if (fillet != butt) out['weld_type'] = fillet ? 'fw' : 'bw';
  if (RegExp(r'\b311\b|\bgazow|\bacetylen').hasMatch(u.folded)) {
    out['oxyacetylene'] = true;
  }
  return out;
}

/// Zakres grubości i średnic z próbki egzaminacyjnej (ISO 9606-1 tab. 6–8).
/// Pełna ocena (proces, spoiwo, pozycje, grupa materiału) zostaje w module.
class QualificationRangeSkill extends AssistantSkill {
  @override
  String get id => 'qualification.range';
  @override
  String get toolId => 'qualification_range';
  @override
  AssistantTier get tier => AssistantTier.b;
  @override
  List<SkillExample> get examples => const [
        SkillExample('Jaki zakres grubości daje próbka spoina czołowa 8 mm',
            'What thickness range does an 8 mm butt weld test piece give'),
        SkillExample('Zakres średnic z próbki rura 60,3 mm',
            'Diameter range from a test piece pipe 60.3 mm'),
        SkillExample(
            'Zakres uprawnień próbka spoina czołowa grubość 10 mm rura 114,3 mm',
            'Qualification range test piece butt weld thickness 10 mm pipe 114.3 mm'),
        SkillExample('Zakres grubości spoina pachwinowa próbka 5 mm',
            'Thickness range fillet weld test piece 5 mm'),
        SkillExample('Co obejmuje egzamin na blasze 2 mm spoina czołowa',
            'Range covered by a 2 mm plate butt weld exam'),
        SkillExample('Policz zakres uprawnień z próbki',
            'Calculate the qualification range from a test piece'),
      ];
  @override
  List<SkillRejection> get rejections => const [
        SkillRejection('otwórz zakres uprawnień z próbki', routesTo: 'tool.open'),
        SkillRejection('do czego służy zakres uprawnień z próbki',
            routesTo: 'tool.explain'),
        SkillRejection('kiedy mi wygasa uprawnienie na 141'),
      ];

  @override
  SkillMatch? match(Utterance u, AssistantContext ctx) {
    if (explainedTool(u) != null ||
        RegExp(r'^(?:otworz|pokaz|open|show|do czego)\b').hasMatch(u.folded)) {
      return null;
    }
    if (u.hasStem(const ['wygas', 'expir', 'przedluz', 'waznos'])) return null;
    final range = u.hasStem(const ['zakres', 'obejmuj', 'range', 'cover']);
    final piece = u.hasStem(const ['probk', 'egzamin', 'uprawnien', 'test piece', 'exam']) ||
        u.hasAny(const ['test piece', 'qualification']);
    if (!range || !piece) return null;
    final s = _slots(u);
    return SkillMatch(this, s.isNotEmpty ? .92 : .72, slots: s, utterance: u);
  }

  @override
  Map<String, Object?> slotsFrom(Utterance u, AssistantContext ctx) =>
      _slots(u);

  @override
  Map<String, Object?>? fillSlot(
      String slot, Utterance u, AssistantContext ctx) {
    final s = _slots(u);
    if (s.containsKey(slot)) return {slot: s[slot]};
    final n = u.items.where((i) => i.isNumber).toList();
    if (slot == 'thickness_mm' && n.length == 1) return {slot: n.single.value};
    return null;
  }

  @override
  Future<SkillResult> run(SkillMatch m, AssistantContext ctx) async {
    final t = m.slots['thickness_mm'];
    final d = m.slots['diameter_mm'];
    final hasT = t is num && t.isFinite && t > 0 && t < 1000;
    final hasD = d is num && d.isFinite && d > 0 && d < 10000;
    if (!hasT && !hasD) {
      return AskResult(
          'thickness_mm',
          const AssistantText(
              'Jaka grubość próbki w mm (dla rury podaj też średnicę)?',
              'What is the test piece thickness in mm (for a pipe also the diameter)?'),
          partial: m);
    }
    final fillet = m.slots['weld_type'] == 'fw';
    final oxy = m.slots['oxyacetylene'] == true;
    final parts = <(String, String)>[];
    if (hasT) {
      final r = fillet
          ? iso9606FilletThickness(t.toDouble())
          : iso9606ButtThickness(t.toDouble(), oxyacetylene: oxy);
      parts.add((
        '${fillet ? 'spoina pachwinowa' : 'spoina czołowa'} ${iso9606Mm(t.toDouble(), en: false)} mm → grubość ${iso9606RangeText(r, en: false)} (tab. ${fillet ? 8 : 6})',
        '${fillet ? 'fillet weld' : 'butt weld'} ${iso9606Mm(t.toDouble(), en: true)} mm → thickness ${iso9606RangeText(r, en: true)} (table ${fillet ? 8 : 6})'
      ));
    }
    if (hasD) {
      final r = iso9606Diameter(d.toDouble());
      parts.add((
        'rura D ${iso9606Mm(d.toDouble(), en: false)} mm → średnice ${iso9606RangeText(r, en: false)} (tab. 7)',
        'pipe D ${iso9606Mm(d.toDouble(), en: true)} mm → diameters ${iso9606RangeText(r, en: true)} (table 7)'
      ));
    }
    final thick = hasT && !fillet && t >= 12;
    return AnswerResult(
        AssistantAnswer(
            text: AssistantText(
                'ISO 9606-1: ${parts.map((p) => p.$1).join('; ')}.${thick ? ' Przy s ≥ 12 mm próbka musi mieć co najmniej 3 warstwy.' : ''} Proces, spoiwo, pozycje i grupę materiału sprawdzisz w module — wiąże certyfikat.',
                'ISO 9606-1: ${parts.map((p) => p.$2).join('; ')}.${thick ? ' For s ≥ 12 mm the test piece needs at least 3 layers.' : ''} Check process, filler, positions and material group in the module — the certificate governs.')),
        show: ShowInModule(toolId, {
          'weld_type': fillet ? 'fw' : 'bw',
          if (hasT) 'thickness_mm': t.toDouble(),
          if (hasD) 'diameter_mm': d.toDouble(),
        }));
  }
}
