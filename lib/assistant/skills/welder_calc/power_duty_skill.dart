import '../../../domain/welding/power_source.dart';
import '../../core/skill.dart';
import '../core/explain_tool_skill.dart' show explainedTool;
import '../core/skill_words.dart';
import '../fitter_routes/quantities.dart';

bool _amp(String w) =>
    const ['a', 'amper', 'ampery', 'amperow', 'amp', 'amps'].contains(w);
Map<String, Object?> _slots(Utterance original) {
  final u = original.withRaw(original.raw.replaceAll('%', ' procent '));
  final s = <String, Object?>{};
  final plate = <Map<String, Object?>>[];
  final usedAmps = <int>{}, usedPercent = <int>{};
  final pointAmps = <int>[], pointPercent = <int>[], targetAmps = <int>{};
  for (var i = 0; i + 3 < u.items.length; i++) {
    if (!u.items[i].isNumber || !_amp(u.items[i + 1].word)) continue;
    var j = i + 2;
    while (j < u.items.length &&
        j <= i + 4 &&
        const ['przy', 'at', 'cykl', 'duty', 'cycle', 'na']
            .contains(u.items[j].word)) {
      j++;
    }
    if (j + 1 < u.items.length &&
        u.items[j].isNumber &&
        (u.items[j + 1].word.startsWith('procent') ||
            u.items[j + 1].word.startsWith('percent'))) {
      plate.add({
        'current_a': signedQuantity(u, i),
        'duty_pct': signedQuantity(u, j)
      });
      usedAmps.add(i + 1);
      usedPercent.add(j + 1);
      pointAmps.add(i + 1);
      pointPercent.add(j + 1);
    }
  }
  final currents = <double>{};
  for (var i = 0; i < u.items.length; i++) {
    if (!const [
      'spawania',
      'roboczy',
      'roboczego',
      'welding',
      'working',
      'target'
    ].contains(u.items[i].word)) {
      continue;
    }
    var j = i + 1;
    while (j < u.items.length &&
        j <= i + 3 &&
        const ['current', 'prad', 'is', 'wynosi', 'minus']
            .contains(u.items[j].word)) {
      j++;
    }
    if (j + 1 < u.items.length &&
        u.items[j].isNumber &&
        _amp(u.items[j + 1].word)) {
      currents.add(signedQuantity(u, j));
      usedAmps.add(j + 1);
      targetAmps.add(j + 1);
    }
  }
  if (currents.isNotEmpty) {
    s['weld_current_a'] = currents.length == 1 ? currents.single : double.nan;
  }
  for (var k = plate.length - 1; k >= 0; k--) {
    if (targetAmps.contains(pointAmps[k])) {
      plate.removeAt(k);
      usedPercent.remove(pointPercent[k]);
    }
  }
  if (plate.isNotEmpty) s['plate'] = plate;
  for (var i = 1; i < u.items.length; i++) {
    if (!u.items[i - 1].isNumber) continue;
    final w = u.items[i].word;
    if (_amp(w) && !usedAmps.contains(i) ||
        (w.startsWith('procent') || w.startsWith('percent')) &&
            !usedPercent.contains(i)) {
      s['plate_invalid'] = true;
    }
  }
  return s;
}

class PowerDutySkill extends AssistantSkill {
  @override
  bool get currentFormEditsNeedAi => true;

  @override
  String get id => 'power.duty';
  @override
  String get toolId => 'power_source';
  @override
  AssistantTier get tier => AssistantTier.b;
  @override
  List<SkillExample> get examples => const [
        SkillExample(
            'Oblicz cykl pracy tabliczka 200 A 60% prąd spawania 150 A',
            'Calculate duty cycle plate 200 A 60% welding current 150 A'),
        SkillExample(
            'Cykl pracy tabliczka 200 A 35% 160 A 60% 130 A 100% prąd spawania 150 A',
            'Duty cycle plate 200 A 35% 160 A 60% 130 A 100% welding current 150 A'),
        SkillExample(
            'Oblicz cykl pracy spawarki', 'Calculate welder duty cycle'),
        SkillExample('Cykl pracy 200 A 60 procent prąd spawania 200 A',
            'Duty cycle 200 A 60 percent welding current 200 A'),
        SkillExample('Cykl pracy 200 A 60% prąd spawania 250 A',
            'Duty cycle 200 A 60% welding current 250 A'),
        SkillExample('Cykl pracy 200 A 60% prąd spawania 100 A',
            'Duty cycle 200 A 60% welding current 100 A'),
      ];
  @override
  List<SkillRejection> get rejections => const [
        SkillRejection('otwórz spawarka i przewody', routesTo: 'tool.open'),
        SkillRejection('energia liniowa TIG EN 12 V 100 A 100 mm/min',
            routesTo: 'heat.input'),
        SkillRejection(
            'oblicz t8/5 Q 1 kJ/mm temperatura 100 C grubość 20 mm wypełnienie',
            routesTo: 'cooling.t85'),
      ];
  @override
  SkillMatch? match(Utterance u, AssistantContext ctx) {
    if (explainedTool(u) != null ||
        requestsWeldingCables(u) ||
        kCommandVerbRe.hasMatch(u.folded) ||
        kOpenVerbAtStartRe.hasMatch(u.folded)) {
      return null;
    }
    if (!u.hasAny(const ['cykl pracy', 'cyklu pracy', 'duty cycle'])) {
      return null;
    }
    final s = _slots(u);
    return SkillMatch(this,
        s.isNotEmpty || u.hasStem(const ['oblicz', 'calculate']) ? .96 : .65,
        slots: s, utterance: u);
  }

  @override
  Map<String, Object?> slotsFrom(Utterance u, AssistantContext ctx) =>
      _slots(u);
  @override
  Map<String, Object?>? fillSlot(
      String slot, Utterance u, AssistantContext ctx) {
    final s = _slots(u);
    if (s.containsKey(slot)) {
      return slot == 'plate' ? {'plate_invalid': null, ...s} : s;
    }
    if (slot == 'weld_current_a') {
      final values = <double>{};
      for (var i = 0; i + 1 < u.items.length; i++) {
        if (u.items[i].isNumber && _amp(u.items[i + 1].word)) {
          values.add(signedQuantity(u, i));
        }
      }
      if (values.length == 1 && !s.containsKey('plate')) {
        return {slot: values.single};
      }
    }
    return null;
  }

  @override
  Future<SkillResult> run(SkillMatch m, AssistantContext ctx) async {
    AskResult ask(String k, String pl, String en) =>
        AskResult(k, AssistantText(pl, en), partial: m);
    final list = m.slots['plate'];
    final rows = <PlateRowInput>[];
    if (list is List) {
      for (var i = 0; i < list.length; i++) {
        final p = list[i];
        if (p is Map && p['current_a'] is num && p['duty_pct'] is num) {
          rows.add(PlateRowInput(
              row: i + 1,
              currentA: (p['current_a'] as num).toDouble(),
              dutyPct: (p['duty_pct'] as num).toDouble()));
        }
      }
    }
    final current = m.slots['weld_current_a'];
    final problems = dutyProblems(DutyCycleInput(
        rows: rows,
        weldCurrentA: current is num ? current.toDouble() : double.nan));
    if (m.slots['plate_invalid'] == true ||
        rows.isEmpty ||
        rows.length > kPlateRows ||
        problems.any((p) => p.kind != DutyProblemKind.weldCurrent)) {
      return ask(
          'plate',
          'Podaj od 1 do 3 punktów z tabliczki, każdy jako prąd A i cykl 1–100%, np. 200 A 60%. Prądy nie mogą się powtarzać; wyższy prąd nie może mieć wyższego cyklu.',
          'Give 1 to 3 rating plate points, each as current A and duty 1–100%, e.g. 200 A 60%. Currents must be unique; higher current cannot have higher duty.');
    }
    if (current is! num ||
        !current.isFinite ||
        current <= 0 ||
        current > kMaxCurrentA) {
      return ask(
          'weld_current_a',
          'Jaki prąd spawania chcesz sprawdzić? Podaj A, powyżej 0 do 1500 A.',
          'What welding current do you want to check? Give A, greater than 0 up to 1500 A.');
    }
    final r = computeDutyCycle(
        DutyCycleInput(rows: rows, weldCurrentA: current.toDouble()));
    if (r == null) {
      return const FailedResult(AssistantText(
          'Nie można obliczyć cyklu dla tych danych.',
          'Cannot calculate duty cycle for these inputs.'));
    }
    return AnswerResult(
        AssistantAnswer(
            text: AssistantText(
                '${powerSourceShareText(en: false, duty: r)}\n${dutyAmbientNote(en: false)}',
                '${powerSourceShareText(en: true, duty: r)}\n${dutyAmbientNote(en: true)}'),
            source: const AssistantText.same(
                'Rating plate; AWS Welding Handbook 9th ed. vol. 2; IEC 60974-1 / Lincoln / Miller')),
        show: ShowInModule(toolId, {
          if (hasVisibleFormInputs(ctx.modules, toolId))
            'preserve_other_inputs': true,
          'plate': [
            for (final row in rows)
              {'current_a': row.currentA, 'duty_pct': row.dutyPct}
          ],
          'weld_current_a': current.toDouble()
        }));
  }
}
