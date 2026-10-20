import '../../../domain/fitter/fitter_calcs.dart';
import '../../core/skill.dart';
import '../core/explain_tool_skill.dart' show explainedTool;
import '../core/skill_words.dart';
import 'quantities.dart';

const _fields = {
  'd1_mm': ['duz', 'large', 'd1'],
  'd2_mm': ['mal', 'small', 'd2'],
  'length_mm': ['dlugosc', 'length'],
  'target_mm': ['docelow', 'target', 'cel'],
};
Map<String, Object?> _slots(Utterance u) {
  final clean = u.withRaw(u.raw.replaceAllMapped(
    RegExp(
        r'\b(large|small|target|duża|duże|duzy|duza|duze|mała|małe|mala|male|docelowa|docelowe)\s+od\b',
        caseSensitive: false),
    (m) => m[1]!,
  ));
  return {
    for (final entry in _fields.entries)
      if (lengthNear(clean, entry.value) case final value?) entry.key: value,
  };
}

class ReducerCutSkill extends AssistantSkill {
  @override
  String get id => 'reducer.cut';
  @override
  String get toolId => 'reducer';
  @override
  AssistantTier get tier => AssistantTier.b;
  @override
  List<SkillExample> get examples => const [
        SkillExample(
            'Skróć redukcję duża 114,3 mm mała 60,3 mm długość 102 mm docelowa 88,9 mm',
            'Trim reducer large 114.3 mm small 60.3 mm length 102 mm target 88.9 mm'),
        SkillExample(
            'Oblicz redukcję duża 100 mm mała 50 mm długość 20 cm docelowa 75 mm',
            'Calculate reducer large 100 mm small 50 mm length 20 cm target 75 mm'),
        SkillExample(
            'Cięcie redukcji duża 20 cm mała 10 cm długość 30 cm docelowa 15 cm',
            'Reducer cut large 20 cm small 10 cm length 30 cm target 15 cm'),
        SkillExample(
            'Skrócenie redukcji duża 100 mm mała 50 mm długość 200 mm docelowa 50 mm',
            'Reducer trim large 100 mm small 50 mm length 200 mm target 50 mm'),
        SkillExample(
            'Skrócenie redukcji duża 100 mm mała 50 mm długość 200 mm docelowa 100 mm',
            'Reducer trim large 100 mm small 50 mm length 200 mm target 100 mm'),
        SkillExample('Oblicz skrócenie redukcji', 'Calculate reducer trim'),
      ];
  @override
  List<SkillRejection> get rejections => const [
        SkillRejection('otwórz redukcję', routesTo: 'tool.open'),
        SkillRejection('narysuj redukcję DN100 na DN50'),
        SkillRejection('oblicz rozwinięcie stożka'),
      ];
  @override
  SkillMatch? match(Utterance u, AssistantContext ctx) {
    if (explainedTool(u) != null ||
        kCommandVerbRe.hasMatch(u.folded) ||
        RegExp(r'^(?:otworz|pokaz|open|show)\b').hasMatch(u.folded)) {
      return null;
    }
    if (!u.hasStem(const ['redukc', 'reducer']) ||
        u.hasStem(const ['rozwini', 'layout'])) {
      return null;
    }
    final slots = _slots(u);
    return SkillMatch(
        this,
        slots.isNotEmpty ||
                u.hasStem(const [
                  'oblicz',
                  'policz',
                  'skroc',
                  'ciec',
                  'cieci',
                  'calculate',
                  'trim',
                  'cut'
                ])
            ? .93
            : .65,
        slots: slots,
        utterance: u);
  }

  @override
  Map<String, Object?> slotsFrom(Utterance u, AssistantContext ctx) =>
      _slots(u);
  @override
  Map<String, Object?>? fillSlot(
      String slot, Utterance u, AssistantContext ctx) {
    final slots = _slots(u);
    if (slots.containsKey(slot)) return slots;
    if (u.hasStem(_fields.values.expand((v) => v))) {
      return slots.isEmpty ? null : slots;
    }
    final values = <double>{};
    for (var i = 0; i + 1 < u.items.length; i++) {
      final scale = lengthUnitScale(u.items[i + 1].word);
      if (u.items[i].isNumber && scale != null) {
        values.add(signedQuantity(u, i) * scale);
      }
    }
    return values.length == 1 ? {slot: values.single} : null;
  }

  @override
  Future<SkillResult> run(SkillMatch m, AssistantContext ctx) async {
    AskResult ask(String k, String pl, String en) =>
        AskResult(k, AssistantText(pl, en), partial: m);
    double? n(String key) =>
        m.slots[key] is num ? (m.slots[key] as num).toDouble() : null;
    final a = n('d1_mm'),
        b = n('d2_mm'),
        length = n('length_mm'),
        target = n('target_mm');
    if (a == null || !a.isFinite || a <= 0) {
      return ask(
          'd1_mm',
          'Jakie jest OD dużego końca? Podaj jednostkę, np. duża 114,3 mm.',
          'What is the large-end OD? Include a unit, e.g. large 114.3 mm.');
    }
    if (b == null || !b.isFinite || b <= 0 || b >= a) {
      return ask(
          'd2_mm',
          'Jakie jest OD małego końca? Musi być dodatnie i mniejsze od dużego OD. Podaj jednostkę.',
          'What is the small-end OD? It must be positive and less than the large OD. Include a unit.');
    }
    final overall = m.utterance?.hasAny(const [
          'cala dlugosc',
          'dlugosc calkowita',
          'overall length',
          'total length'
        ]) ??
        false;
    if (length == null || !length.isFinite || length <= 0 || overall) {
      return ask(
          'length_mm',
          'Jaka jest długość samej części stożkowej, bez odcinków walcowych na końcach? Podaj jednostkę.',
          'What is the length of the conical part alone, excluding cylindrical ends? Include a unit.');
    }
    if (target == null || !target.isFinite || target < b || target > a) {
      return ask(
          'target_mm',
          'Podaj docelowe OD pomiędzy ${fmt(b, ctx.lang)} i ${fmt(a, ctx.lang)} mm.',
          'Give target OD between ${fmt(b, ctx.lang)} and ${fmt(a, ctx.lang)} mm.');
    }
    final x = reducerCutFromLargeMm(
        d1Mm: a, d2Mm: b, lengthMm: length, targetMm: target);
    if (x == null || !x.isFinite) {
      return const FailedResult(AssistantText(
          'Wynik poza zakresem. Sprawdź wymiary stożka.',
          'Result out of range. Check cone dimensions.'));
    }
    return AnswerResult(
        AssistantAnswer(
            text: AssistantText(
                'Dla docelowego OD ${fmt(target, ctx.lang)} mm odmierz ${fmt(x, ctx.lang)} mm od dużego końca części stożkowej. Długość stożka ${fmt(length, ctx.lang)} mm; odcinki walcowe nie są wliczone. To model liniowego stożka — sprawdź rzeczywisty element przed cięciem.',
                'For target OD ${fmt(target, ctx.lang)} mm, measure ${fmt(x, ctx.lang)} mm from the large end of the conical part. Cone length is ${fmt(length, ctx.lang)} mm; cylindrical ends are excluded. This is a linear-cone model; check the actual component before cutting.')),
        show: ShowInModule(toolId, {
          'd1_mm': a,
          'd2_mm': b,
          'length_mm': length,
          'target_mm': target
        }));
  }
}
