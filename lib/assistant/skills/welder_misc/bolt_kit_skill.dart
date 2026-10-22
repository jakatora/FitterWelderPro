import '../../../domain/bolting/stud_length.dart';
import '../../../services/flange_catalog.dart';
import '../../core/skill.dart';
import '../core/explain_tool_skill.dart' show explainedTool;
import '../core/labelled_numbers.dart';
import '../core/skill_words.dart';
import '../core/skill_guards.dart';

Map<String, Object?> _slots(Utterance u) {
  final out = <String, Object?>{};
  if (u.mentionsDn) out['dn'] = u.dn() ?? double.nan;
  final cls = numberAfterLabel(
      u, (w) => w.startsWith('klas') || w == 'class' || w == 'cl');
  if (cls != null) out['class'] = cls;
  final rf = u.hasAny(const ['rf', 'raised face', 'przylgowa', 'z przylga']);
  final rtj = u.hasAny(const ['rtj', 'ring joint', 'pierscieniowa']);
  if (rf != rtj) out['facing'] = rf ? 'rf' : 'rtj';
  final joints = numberBeforeUnit(
      u,
      (w) =>
          w.startsWith('polaczen') ||
          w.startsWith('kolnierz') ||
          w.startsWith('joint') ||
          w.startsWith('flange'));
  if (joints != null) out['joints'] = joints;
  return out;
}

class BoltKitSkill extends AssistantSkill {
  @override
  String get id => 'bolt.kit';
  @override
  String get toolId => 'bolt_kit';
  @override
  AssistantTier get tier => AssistantTier.b;
  @override
  List<SkillExample> get examples => const [
        SkillExample('Długość szpilek DN100 klasa 300 RF',
            'Stud length DN100 class 300 RF'),
        SkillExample('Jakie szpilki do kołnierza DN150 klasa 150 RF',
            'Which studs for a DN150 class 150 RF flange'),
        SkillExample('Komplet śrub na 4 połączenia DN80 klasa 600 RTJ',
            'Bolt kit for 4 joints DN80 class 600 RTJ'),
        SkillExample('Ile szpilek i nakrętek DN200 klasa 300 RF na 2 kołnierze',
            'How many studs and nuts DN200 class 300 RF for 2 flanges'),
        SkillExample('Długość szpilki DN50 klasa 1500 RTJ',
            'Stud length DN50 class 1500 RTJ'),
        SkillExample('Policz śruby do kołnierzy', 'Calculate flange bolts'),
      ];
  @override
  List<SkillRejection> get rejections => const [
        SkillRejection('otwórz śruby do kołnierzy', routesTo: 'tool.open'),
        SkillRejection('do czego służą śruby do kołnierzy',
            routesTo: 'tool.explain'),
        SkillRejection('jaki moment dokręcenia śruby 3/4 cala B7 na smarze'),
      ];

  @override
  SkillMatch? match(Utterance u, AssistantContext ctx) {
    if (explainedTool(u) != null ||
        kOpenOrAboutStart.hasMatch(u.folded)) {
      return null;
    }
    if (u.hasStem(const ['moment', 'torque', 'dokrec', 'napiec'])) return null;
    final studs = u.hasStem(const ['szpil', 'stud']);
    final kit = u.hasStem(const ['sruby', 'srub', 'bolt']) &&
        u.hasStem(const ['kolnierz', 'flange', 'komplet', 'kit', 'polaczen']);
    if (!studs && !kit) return null;
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
    final numbers = u.items.where((i) => i.isNumber).toList();
    if (numbers.length == 1 && (slot == 'class' || slot == 'dn')) {
      return {slot: numbers.single.value};
    }
    return null;
  }

  @override
  Future<SkillResult> run(SkillMatch m, AssistantContext ctx) async {
    AskResult ask(String key, String pl, String en) =>
        AskResult(key, AssistantText(pl, en), partial: m);
    final dn = m.slots['dn'];
    if (dn is! num || !dn.isFinite) {
      return ask('dn', 'Jaka średnica kołnierza DN?', 'Which flange size DN?');
    }
    final cls = m.slots['class'];
    if (cls is! num || !cls.isFinite) {
      return ask('class', 'Jaka klasa kołnierza: 150, 300, 600, 900 czy 1500?',
          'Which flange class: 150, 300, 600, 900 or 1500?');
    }
    final facing = m.slots['facing'];
    if (facing != 'rf' && facing != 'rtj') {
      return ask('facing', 'Przylga RF czy RTJ?', 'RF or RTJ facing?');
    }
    final face = facing == 'rf' ? FlangeFacing.rf : FlangeFacing.rtj;
    final lookup = lookupAsmeStud(dn.toInt(), cls.toInt(), face);
    if (lookup is StudNotFound) {
      return FailedResult(lookup.problem == StudLookupProblem.noRtj
          ? const AssistantText(
              'ASME B16.5 nie przewiduje RTJ dla Class 150 NPS ½ i ¾.',
              'ASME B16.5 has no RTJ for Class 150 NPS ½ and ¾.')
          : AssistantText(
              'Tabela obejmuje DN ${FlangeCatalog.dns.join(', ')} i klasy ${FlangeCatalog.classes.join(', ')}.',
              'The table covers DN ${FlangeCatalog.dns.join(', ')} and classes ${FlangeCatalog.classes.join(', ')}.'));
    }
    final stud = (lookup as StudFound).stud;
    final joints = m.slots['joints'];
    final n = joints is num && joints.isFinite && joints >= 1
        ? joints.round()
        : 1;
    final mm = fmt(stud.lengthMm, ctx.lang);
    final design = studDesignation(stud.size, stud.lengthQuarterIn);
    var pl = 'DN${stud.dn} Class ${stud.cls} ${facingLabel(face)}: '
        '${stud.boltCount} szpilek $design (≈ $mm mm) '
        'i ${stud.nutCount} nakrętek na połączenie — ASME B16.5.';
    var en = 'DN${stud.dn} Class ${stud.cls} ${facingLabel(face)}: '
        '${stud.boltCount} studs $design (≈ $mm mm) '
        'and ${stud.nutCount} nuts per joint — ASME B16.5.';
    final fields = <String, Object?>{
      'dn': stud.dn,
      'class': stud.cls,
      'facing': facing,
    };
    if (n > 1) {
      fields['joints'] = n;
      pl += ' Na $n połączeń: ${stud.boltCount * n} szpilek, '
          '${stud.nutCount * n} nakrętek, $n uszczelek (bez zapasu).';
      en += ' For $n joints: ${stud.boltCount * n} studs, '
          '${stud.nutCount * n} nuts, $n gaskets (no spares).';
    }
    return AnswerResult(AssistantAnswer(text: AssistantText(pl, en)),
        show: ShowInModule(toolId, fields));
  }
}
