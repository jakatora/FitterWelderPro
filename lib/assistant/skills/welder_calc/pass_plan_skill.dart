import '../../../data/pipe_schedules.dart';
import '../../../domain/pass_plan/pass_plan.dart';
import '../../../domain/pass_plan/pass_plan_form.dart';
import '../../../features/pass_plan/pass_plan_store.dart';
import '../../core/skill.dart';
import '../core/explain_tool_skill.dart' show explainedTool;
import '../core/labelled_numbers.dart';
import '../core/skill_words.dart';

/// Schedule po słowie „sch/schedule/szedziul”: „40”, „80”, „STD”, „XS”.
String? _schedule(Utterance u) {
  final m = RegExp(r'\b(?:sch|schedule|szedziul\w*|harmonogram)\s*(std|xs|xxs|\d+s?)\b')
      .firstMatch(u.folded);
  return m?[1]?.toUpperCase();
}

Map<String, Object?> _slots(Utterance u) {
  final out = <String, Object?>{};
  if (u.mentionsDn) out['dn'] = u.dn() ?? double.nan;
  final sch = _schedule(u);
  if (sch != null) out['sch'] = sch;
  final count = numberBeforeUnit(
          u,
          (w) =>
              w.startsWith('zlacz') ||
              w.startsWith('spoin') ||
              w.startsWith('joint') ||
              w.startsWith('weld') ||
              w.startsWith('styk')) ??
      numberAfterLabel(u, (w) => w.startsWith('zlacz') || w == 'joints');
  if (count != null) out['count'] = count;
  return out;
}

String _consumable(PassConsumable c, bool en) => switch (c) {
      PassConsumable.tig => en ? 'TIG rod' : 'pręt TIG',
      PassConsumable.mag => en ? 'MAG wire' : 'drut MAG',
      _ => en
          ? 'electrode Ø${c.electrodeMm}'
          : 'elektroda Ø${c.electrodeMm.toString().replaceAll('.', ',')}',
    };

/// „Ile ściegów i elektrod” — rura z typoszeregu na zapisanym planie modułu
/// (spoiwa warstw, rowek, zapas); asystent zmienia DN, Sch i liczbę złączy.
class PassPlanSkill extends AssistantSkill {
  PassPlanSkill({PassPlanStore store = const PassPlanStore()}) : _store = store;
  final PassPlanStore _store;

  @override
  String get id => 'pass.plan';
  @override
  String get toolId => 'pass_plan';
  @override
  AssistantTier get tier => AssistantTier.b;
  @override
  List<SkillExample> get examples => const [
        SkillExample('Ile ściegów i elektrod na 8 złączy DN150 Sch 40',
            'How many passes and electrodes for 8 joints DN150 Sch 40'),
        SkillExample('Plan ściegów DN100 Sch 80 4 złącza',
            'Pass plan DN100 Sch 80 4 joints'),
        SkillExample('Ile elektrod na 6 spoin DN200 Sch 40',
            'How many electrodes for 6 welds DN200 Sch 40'),
        SkillExample('Ile ściegów na rurę DN80 Sch 40 2 złącza',
            'How many passes for a DN80 Sch 40 pipe 2 joints'),
        SkillExample('Plan ściegów i elektrod DN250 Sch 20 10 złączy',
            'Pass and electrode plan DN250 Sch 20 10 joints'),
        SkillExample('Zrób plan ściegów', 'Make a pass plan'),
      ];
  @override
  List<SkillRejection> get rejections => const [
        SkillRejection('otwórz plan ściegów i elektrod', routesTo: 'tool.open'),
        SkillRejection('do czego służy plan ściegów i elektrod',
            routesTo: 'tool.explain'),
        SkillRejection('jak długo elektroda zasadowa może leżeć poza piecykiem'),
      ];

  @override
  SkillMatch? match(Utterance u, AssistantContext ctx) {
    if (explainedTool(u) != null ||
        RegExp(r'^(?:otworz|pokaz|open|show|do czego)\b').hasMatch(u.folded)) {
      return null;
    }
    if (u.hasStem(const ['moze lezec', 'poza piec', 'poza suszar', 'ekspozyc'])) {
      return null;
    }
    final passes = u.hasStem(const ['sciegow', 'sciegi', 'scieg', 'passes', 'pass']);
    final rods = u.hasStem(const ['elektrod', 'electrode']) &&
        (u.hasStem(const ['ile', 'how many', 'wziac', 'suszar', 'oven']) ||
            u.mentionsDn);
    if (!passes && !rods) return null;
    if (!passes && !u.mentionsDn) return null;
    final s = _slots(u);
    return SkillMatch(this, s.isNotEmpty ? .9 : .72, slots: s, utterance: u);
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
    if (n.length == 1 && slot == 'count') return {slot: n.single.value};
    if (slot == 'sch') {
      final m = RegExp(r'^(std|xs|xxs|\d+s?)$').firstMatch(u.folded.trim());
      if (m != null) return {slot: m[1]!.toUpperCase()};
    }
    return null;
  }

  @override
  Future<SkillResult> run(SkillMatch m, AssistantContext ctx) async {
    AskResult ask(String key, String pl, String en) =>
        AskResult(key, AssistantText(pl, en), partial: m);
    final dn = m.slots['dn'];
    if (dn is! num || !dn.isFinite) {
      return ask('dn', 'Jaka średnica rury DN?', 'Which pipe size DN?');
    }
    final row = kPipeWalls.where((r) => r.dn == dn).firstOrNull;
    if (row == null) {
      return const FailedResult(AssistantText(
          'Nie znam tej średnicy w tabeli rur.', 'This size is not in the pipe table.'));
    }
    final sch = m.slots['sch'];
    if (sch is! String || row.walls[sch] == null) {
      final list =
          kSchedulesCarbon.where((s) => row.walls[s] != null).join(', ');
      return ask('sch', 'Jaki Schedule dla DN${row.dn}: $list?',
          'Which schedule for DN${row.dn}: $list?');
    }
    final count = m.slots['count'];
    if (count is! num ||
        !count.isFinite ||
        count < 1 ||
        count != count.roundToDouble()) {
      return ask('count', 'Ile złączy?', 'How many joints?');
    }
    Map<String, String> form;
    try {
      form = (await _store.load())?.form ?? passPlanDefaultForm();
    } catch (_) {
      form = passPlanDefaultForm();
    }
    form = {
      ...form,
      PassPlanField.kind: kPassPlanJointKinds.first.code,
      PassPlanField.dn: '${row.dn}',
      PassPlanField.sch: sch,
      PassPlanField.od: '${row.od}',
      PassPlanField.wall: '${row.walls[sch]}',
      PassPlanField.count: '${count.toInt()}',
    };
    final input = passPlanInputFromForm(form);
    final plan = planPasses(input);
    if (plan == null) {
      return const FailedResult(AssistantText(
          'Plan się nie liczy dla zapisanych założeń modułu (rowek, szczelina, spoiwa) — sprawdź je na ekranie.',
          'The plan does not compute for the saved module assumptions (groove, gap, consumables) — check them on screen.'));
    }
    String f(num v) => fmt(v.toDouble(), ctx.lang);
    String supplies(bool en) => [
          for (final s in plan.supplies)
            if (s.countsUnits)
              '${_consumable(s.consumable, en)}: ${s.unitsJobWithReserve} ${en ? 'pcs' : 'szt.'}'
            else
              '${_consumable(s.consumable, en)}: ${f(s.fillerGPerJoint * s.jointCount / 1000)} kg'
        ].join(', ');
    final wall = row.walls[sch]!;
    return AnswerResult(
        AssistantAnswer(
            text: AssistantText(
                'DN${row.dn} Sch $sch (${f(row.od)} × ${f(wall)} mm), ${count.toInt()} złączy: ${plan.passesPerJoint} ściegów na złącze. Spoiwo z zapasem: ${supplies(false)}. Łuk ok. ${f(plan.arcMinJob.ceilToDouble())} min, praca ok. ${f(plan.workMinJob.ceilToDouble())} min. Spoiwa warstw, rowek i zapas wziąłem z zapisanego planu modułu.',
                'DN${row.dn} Sch $sch (${f(row.od)} × ${f(wall)} mm), ${count.toInt()} joints: ${plan.passesPerJoint} passes per joint. Filler with reserve: ${supplies(true)}. Arc approx. ${f(plan.arcMinJob.ceilToDouble())} min, work approx. ${f(plan.workMinJob.ceilToDouble())} min. Layer consumables, groove and reserve come from the saved module plan.')),
        show: ShowInModule(toolId, {
          'dn': row.dn,
          'sch': sch,
          'count': count.toInt(),
        }));
  }
}
