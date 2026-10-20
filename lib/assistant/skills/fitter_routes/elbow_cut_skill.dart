import '../../../domain/fitter/fitter_calcs.dart';
import '../../core/skill.dart';
import '../core/explain_tool_skill.dart' show explainedTool;
import '../core/skill_words.dart';
import 'quantities.dart';

double? _angle(Utterance u, List<String> labels) {
  final values = <double>{};
  for (var i = 0; i < u.items.length; i++) {
    if (!labels.any((l) => u.items[i].word.startsWith(l))) continue;
    for (var j = i + 1; j < u.items.length && j <= i + 3; j++) {
      if (u.items[j].isNumber) {
        values.add(j + 1 < u.items.length &&
                lengthUnitScale(u.items[j + 1].word) != null
            ? double.nan
            : signedQuantity(u, j));
        break;
      }
      if (!const ['kat', 'angle', 'is', 'ma', 'minus']
          .contains(u.items[j].word)) {
        break;
      }
    }
  }
  return values.length > 1 ? double.nan : values.singleOrNull;
}

Map<String, Object?> _slots(Utterance u) {
  final s = <String, Object?>{};
  final base = _angle(u, const ['baz', 'base']),
      target = _angle(u, const ['docelow', 'target']);
  if (base != null) s['base_angle_deg'] = base;
  if (target != null) s['target_angle_deg'] = target;
  final clean = u.withRaw(u.raw.replaceAllMapped(
      RegExp(r'\b(długi|dlugi|krótki|krotki|long|short)\s+(?:bok|side|arc)\b',
          caseSensitive: false),
      (m) => m[1]!));
  final l = lengthNear(clean, const ['extrados', 'zewnetrzn', 'dlugi', 'long']),
      short =
          lengthNear(clean, const ['intrados', 'wewnetrzn', 'krotki', 'short']);
  if (l != null) s['extrados_mm'] = l;
  if (short != null) s['intrados_mm'] = short;
  return s;
}

class ElbowCutSkill extends AssistantSkill {
  @override
  String get id => 'elbow.cut';
  @override
  String get toolId => 'elbow_cut';
  @override
  AssistantTier get tier => AssistantTier.b;
  @override
  List<SkillExample> get examples => const [
        SkillExample(
            'Cięcie kolanka baza 90 extrados 180 mm intrados 90 mm docelowy 45',
            'Elbow cut base 90 extrados 180 mm intrados 90 mm target 45'),
        SkillExample(
            'Przytnij kolano baza 90 długi bok 180 mm krótki bok 90 mm docelowy 30',
            'Trim elbow base 90 long side 180 mm short side 90 mm target 30'),
        SkillExample(
            'Cięcie kolana baza 45 extrados 90 mm intrados 45 mm docelowy 30',
            'Elbow cut base 45 extrados 90 mm intrados 45 mm target 30'),
        SkillExample(
            'Cięcie kolana baza 90 extrados 18 cm intrados 9 cm docelowy 60',
            'Elbow cut base 90 extrados 18 cm intrados 9 cm target 60'),
        SkillExample('Oblicz cięcie kolanka', 'Calculate elbow cut'),
        SkillExample(
            'Cięcie kolanka baza 90 extrados 166,74 mm intrados 72,02 mm docelowy 60',
            'Elbow cut base 90 extrados 166.74 mm intrados 72.02 mm target 60'),
      ];
  @override
  List<SkillRejection> get rejections => const [
        SkillRejection('otwórz cięcie kolanka', routesTo: 'tool.open'),
        SkillRejection('wymiar kolana DN50 LR kąt 45 stopni',
            routesTo: 'elbow.takeout'),
        SkillRejection('narysuj kolano w górę'),
      ];
  @override
  SkillMatch? match(Utterance u, AssistantContext ctx) {
    if (explainedTool(u) != null ||
        kCommandVerbRe.hasMatch(u.folded) ||
        RegExp(r'^(?:otworz|pokaz|open|show)\b').hasMatch(u.folded)) {
      return null;
    }
    if (!u.hasStem(const ['kolan', 'elbow']) ||
        !u.hasStem(const ['ciec', 'cieci', 'przytn', 'cut', 'trim'])) {
      return null;
    }
    final slots = _slots(u);
    return SkillMatch(
        this,
        slots.isNotEmpty ||
                u.hasStem(
                    const ['oblicz', 'policz', 'calculate', 'przytn', 'trim'])
            ? .94
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
    final s = _slots(u);
    if (s.containsKey(slot)) return s;
    if (slot.endsWith('_deg')) {
      final value = angleValue(u);
      if (value != null) return {slot: value};
      final numbers = [
        for (var i = 0; i < u.items.length; i++)
          if (u.items[i].isNumber) signedQuantity(u, i)
      ];
      if (numbers.length == 1 &&
          u.items.every((i) => i.isNumber || i.word == 'minus')) {
        return {slot: numbers.single};
      }
    } else {
      final values = <double>{};
      for (var i = 0; i + 1 < u.items.length; i++) {
        final scale = lengthUnitScale(u.items[i + 1].word);
        if (u.items[i].isNumber && scale != null) {
          values.add(signedQuantity(u, i) * scale);
        }
      }
      if (values.length == 1) return {slot: values.single};
    }
    return null;
  }

  @override
  Future<SkillResult> run(SkillMatch m, AssistantContext ctx) async {
    AskResult ask(String k, String pl, String en) =>
        AskResult(k, AssistantText(pl, en), partial: m);
    double? n(String k) =>
        m.slots[k] is num ? (m.slots[k] as num).toDouble() : null;
    final base = n('base_angle_deg'),
        l = n('extrados_mm'),
        s = n('intrados_mm'),
        target = n('target_angle_deg');
    if (!const [45.0, 90.0].contains(base)) {
      return ask(
          'base_angle_deg',
          'Jaki jest kąt całego kolana: 45 czy 90 stopni?',
          'What is the whole elbow angle: 45 or 90 degrees?');
    }
    if (l == null || !l.isFinite || l <= 0) {
      return ask(
          'extrados_mm',
          'Podaj zmierzony zewnętrzny łuk całego kolana (extrados), np. 180 mm.',
          'Give the measured outer arc of the whole elbow (extrados), e.g. 180 mm.');
    }
    if (s == null || !s.isFinite || s <= 0 || s >= l) {
      return ask(
          'intrados_mm',
          'Podaj wewnętrzny łuk (intrados) z jednostką. Musi być krótszy od zewnętrznego.',
          'Give the inner arc (intrados) with a unit. It must be shorter than the outer arc.');
    }
    if (target == null || !target.isFinite || target <= 0 || target >= base!) {
      return ask(
          'target_angle_deg',
          'Jaki kąt chcesz uzyskać? Podaj stopnie, więcej niż 0 i mniej niż ${fmt(base!, ctx.lang)}.',
          'What angle do you want? Give degrees, greater than 0 and less than ${fmt(base, ctx.lang)}.');
    }
    final r = elbowCut(
        baseAngleDeg: base,
        extradosMm: l,
        intradosMm: s,
        targetAngleDeg: target);
    if (r == null || !r.longCutMm.isFinite || !r.odDerivedMm.isFinite) {
      return const FailedResult(AssistantText(
          'Wynik poza zakresem. Sprawdź pomiary łuków.',
          'Result out of range. Check arc measurements.'));
    }
    return AnswerResult(
        AssistantAnswer(
            text: AssistantText(
                'Dla kąta ${fmt(target, ctx.lang)}° odmierz po łukach od tego samego końca: extrados ${fmt(r.longCutMm, ctx.lang)} mm, intrados ${fmt(r.shortCutMm, ctx.lang)} mm. Zostaje ${fmt(r.remainAngleDeg, ctx.lang)}°: łuk zewnętrzny ${fmt(r.longRemainMm, ctx.lang)} mm, wewnętrzny ${fmt(r.shortRemainMm, ctx.lang)} mm. Wpisane długości dotyczą całych łuków kolana bazowego.',
                'For ${fmt(target, ctx.lang)}°, measure along the arcs from the same end: extrados ${fmt(r.longCutMm, ctx.lang)} mm, intrados ${fmt(r.shortCutMm, ctx.lang)} mm. Remaining ${fmt(r.remainAngleDeg, ctx.lang)}°: outer arc ${fmt(r.longRemainMm, ctx.lang)} mm, inner arc ${fmt(r.shortRemainMm, ctx.lang)} mm. Input lengths are full arcs of the base elbow.')),
        show: ShowInModule(toolId, {
          'base_angle_deg': base,
          'extrados_mm': l,
          'intrados_mm': s,
          'target_angle_deg': target
        }));
  }
}
