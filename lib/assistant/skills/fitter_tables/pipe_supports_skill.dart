import '../../../data/support_spacing.dart';
import '../../core/skill.dart';
import '../core/explain_tool_skill.dart' show explainedTool;
import '../core/skill_words.dart';
import '../fitter_routes/quantities.dart';

String? _service(Utterance u) {
  final water = u.hasStem(const [
    'wod',
    'ciecz',
    'wypelnion',
    'pelna',
    'water',
    'liquid',
    'filled'
  ]);
  final vapor = u.hasStem(const [
    'gaz',
    'par',
    'powietrz',
    'pust',
    'steam',
    'gas',
    'air',
    'vapo',
    'empty'
  ]);
  if (water == vapor) return water ? 'ambiguous' : null;
  return water ? 'water' : 'vapor';
}

/// Długość odcinka: liczba z jednostką długości, która nie jest DN.
double? _runM(Utterance u) {
  final found = <double>{};
  final items = u.items;
  for (var i = 0; i + 1 < items.length; i++) {
    final scale = lengthUnitScale(items[i + 1].word);
    if (items[i].isNumber && scale != null) {
      found.add(items[i].value! * scale / 1000);
    }
  }
  return found.length > 1 ? double.nan : found.singleOrNull;
}

Map<String, Object?> _slots(Utterance u) {
  final out = <String, Object?>{};
  if (u.mentionsDn) {
    final dn = u.dn();
    out['dn'] = dn ?? double.nan;
  }
  final service = _service(u);
  if (service != null) out['service'] = service;
  final run = _runM(u);
  if (run != null) out['run_m'] = run;
  return out;
}

class PipeSupportsSkill extends AssistantSkill {
  @override
  String get id => 'pipe.supports';
  @override
  String get toolId => 'pipe_supports';
  @override
  AssistantTier get tier => AssistantTier.b;
  @override
  List<SkillExample> get examples => const [
        SkillExample('Rozstaw podpór DN100 woda', 'Support spacing DN100 water'),
        SkillExample('Ile podpór na odcinku 24 m DN50 gaz',
            'How many supports on a 24 m run DN50 gas'),
        SkillExample('Maksymalny rozstaw podpór DN200 para',
            'Maximum support spacing DN200 steam'),
        SkillExample('Co ile podpora rura DN80 z wodą',
            'How often to support a DN80 pipe with water'),
        SkillExample('Ile podpór 12 m DN25 powietrze',
            'How many supports 12 m DN25 air'),
        SkillExample('Policz rozstaw podpór', 'Calculate support spacing'),
      ];
  @override
  List<SkillRejection> get rejections => const [
        SkillRejection('otwórz podpory rur', routesTo: 'tool.open'),
        SkillRejection('do czego służą podpory rur', routesTo: 'tool.explain'),
        SkillRejection('jaki ciężar rury DN100 6 m'),
      ];

  @override
  SkillMatch? match(Utterance u, AssistantContext ctx) {
    if (explainedTool(u) != null ||
        RegExp(r'^(?:otworz|pokaz|open|show|do czego)\b').hasMatch(u.folded)) {
      return null;
    }
    if (!u.hasStem(const ['podpor', 'podpar', 'wieszak', 'support', 'hanger'])) {
      return null;
    }
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
    if (slot == 'dn') {
      final n = u.items.where((i) => i.isNumber).toList();
      if (n.length == 1 && u.items.length == 1) return {slot: n.single.value};
    }
    return null;
  }

  @override
  Future<SkillResult> run(SkillMatch m, AssistantContext ctx) async {
    AskResult ask(String key, String pl, String en) =>
        AskResult(key, AssistantText(pl, en), partial: m);
    final dn = m.slots['dn'];
    if (dn is! num || !dn.isFinite) {
      return ask('dn', 'Jaka średnica nominalna DN?', 'Which nominal size DN?');
    }
    final span = supportSpanForDn(dn.toInt());
    if (span == null || dn != dn.roundToDouble()) {
      return FailedResult(AssistantText(
          'Tabela MSS SP-58 nie ma DN${fmt(dn.toDouble(), ctx.lang)}. Dostępne: ${kSupportSpans.map((s) => s.dn).join(', ')}.',
          'The MSS SP-58 table has no DN${fmt(dn.toDouble(), ctx.lang)}. Available: ${kSupportSpans.map((s) => s.dn).join(', ')}.'));
    }
    final service = m.slots['service'];
    if (service != 'water' && service != 'vapor') {
      return ask('service', 'Rura z wodą (cieczą) czy z gazem, parą albo powietrzem?',
          'Is the pipe filled with water (liquid), or gas, steam or air?');
    }
    final water = service == 'water';
    final spacing = maxSupportSpacingMm(span.dn, liquidFilled: water);
    final fields = <String, Object?>{'dn': span.dn, 'service': service};
    final spacingM = fmt(spacing / 1000, ctx.lang);
    var pl = 'DN${span.dn} (NPS ${span.nps}"), ${water ? 'woda' : 'gaz/para'}: '
        'maksymalny rozstaw podpór $spacingM m (MSS SP-58 tab. 4 / ASME B31.1 tab. 121.5).';
    var en = 'DN${span.dn} (NPS ${span.nps}"), ${water ? 'water' : 'gas/steam'}: '
        'maximum support spacing $spacingM m (MSS SP-58 table 4 / ASME B31.1 table 121.5).';
    final run = m.slots['run_m'];
    if (run is num) {
      final runMm = run.isFinite ? (run * 1000).round() : 0;
      final count = runMm > 0 && runMm <= 500000
          ? supportsOnRun(runMm, spacing)
          : null;
      if (count == null) {
        return const FailedResult(AssistantText(
            'Długość odcinka musi być większa od zera i najwyżej 500 m.',
            'The run length must be above zero and at most 500 m.'));
      }
      fields['run_m'] = run.toDouble();
      pl += ' Na ${fmt(run.toDouble(), ctx.lang)} m prostego odcinka: $count podpór (z pierwszą).';
      en += ' On a ${fmt(run.toDouble(), ctx.lang)} m straight run: $count supports (including the first).';
    }
    pl += ' Zawory i kołnierze między podporami wymagają dodatkowych — rozstaw na projekcie ustala projektant.';
    en += ' Valves and flanges between supports need extra ones — the project stress engineer sets the actual spacing.';
    return AnswerResult(AssistantAnswer(text: AssistantText(pl, en)),
        show: ShowInModule(toolId, fields));
  }
}
