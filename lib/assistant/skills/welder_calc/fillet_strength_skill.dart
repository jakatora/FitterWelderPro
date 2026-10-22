import 'dart:math' as math;

import '../../../domain/welding/fillet_weld_strength.dart';
import '../../../utils/decimal_parse.dart';
import '../../core/skill.dart';
import '../core/explain_tool_skill.dart' show explainedTool;
import '../core/labelled_numbers.dart';
import '../core/skill_words.dart';
import '../fitter_routes/quantities.dart';

final _steelRe = RegExp(r'\bs\s?(235|275|355|420|460)\b');
// „a4”, „a 4”, „a=4” — ale nie „a 4 spoiny” (spójnik + liczba spoin).
final _throatRe = RegExp(
    r'(?:^|\s)a\s?(\d+(?:[.,]\d+)?)(?![\d.,])(?!\s*(?:spoin|weld|razy|x\b))');
// Bok spoiny: „z6”, „bok 6 mm”, „bok spoiny z 6”, „leg 6 mm” — samo „z 6”
// to po polsku „z sześcioma”, nie bok.
final _legRe = RegExp(r'(?:^|\s)z(\d+(?:[.,]\d+)?)(?![\d.,])');

Map<String, Object?> _slots(Utterance u) {
  final out = <String, Object?>{};
  final steels = {for (final m in _steelRe.allMatches(u.folded)) m[1]};
  if (steels.isNotEmpty) {
    out['steel'] = steels.length == 1 ? 's${steels.single}' : 'ambiguous';
  }
  final throats = {
    for (final m in _throatRe.allMatches(u.folded)) parseDecimal(m[1]!),
    numberAfterLabel(
        u,
        (w) =>
            w == 'throat' ||
            w.startsWith('grubosc') && u.hasStem(const ['spoin'])),
  }..remove(null);
  final legs = {
    for (final m in _legRe.allMatches(u.folded)) parseDecimal(m[1]!),
    numberAfterLabel(u, (w) => w == 'bok' || w == 'leg',
        skip: const {'spoiny', 'z', 'weld'}),
  }..remove(null);
  if (throats.isNotEmpty || legs.isNotEmpty) {
    final values = {...throats, for (final z in legs) z! / math.sqrt2};
    out['throat_mm'] = values.length == 1 ? values.single : double.nan;
    if (legs.isNotEmpty && throats.isEmpty) out['leg_given'] = true;
  }
  final length = lengthNear(u, const ['dlugosc', 'length', 'l']);
  if (length != null) out['length_mm'] = length;
  final thickness = lengthNear(u, const ['blach', 'plate', 'thickness', 't']);
  if (thickness != null) out['part_thickness_mm'] = thickness;
  final welds =
      numberBeforeUnit(u, (w) => w.startsWith('spoin') || w.startsWith('weld'));
  if (welds != null) out['welds'] = welds;
  final force = numberBeforeUnit(u, (w) => w == 'kn');
  if (force != null) out['force_kn'] = force;
  return out;
}

class FilletStrengthSkill extends AssistantSkill {
  @override
  String get id => 'fillet.strength';
  @override
  String get toolId => 'fillet_strength';
  @override
  AssistantTier get tier => AssistantTier.b;
  @override
  List<SkillExample> get examples => const [
        SkillExample(
            'Nośność spoiny pachwinowej a4 długość 100 mm 2 spoiny S355 blacha 10 mm',
            'Fillet weld resistance a4 length 100 mm 2 welds S355 plate 10 mm'),
        SkillExample(
            'Czy spoina a5 długość 150 mm 2 spoiny S235 blacha 12 mm przeniesie 200 kN',
            'Will a fillet weld a5 length 150 mm 2 welds S235 plate 12 mm carry 200 kN'),
        SkillExample(
            'Nośność spoiny pachwinowej bok z6 długość 80 mm 1 spoina S275 blacha 8 mm',
            'Fillet weld resistance leg z6 length 80 mm 1 weld S275 plate 8 mm'),
        SkillExample(
            'Spoina pachwinowa a3 długość 60 mm 4 spoiny S355 blacha 6 mm',
            'Fillet weld a3 length 60 mm 4 welds S355 plate 6 mm'),
        SkillExample(
            'Nośność spoiny pachwinowej a 6 długość 200 mm 2 spoiny S460 blacha 20 mm siła 500 kN',
            'Fillet weld resistance a 6 length 200 mm 2 welds S460 plate 20 mm force 500 kN'),
        SkillExample('Policz nośność spoiny pachwinowej',
            'Calculate fillet weld resistance'),
      ];
  @override
  List<SkillRejection> get rejections => const [
        SkillRejection('otwórz nośność spoiny', routesTo: 'tool.open'),
        SkillRejection('do czego służy nośność spoiny pachwinowej',
            routesTo: 'tool.explain'),
        SkillRejection('ile spoiwa na spoinę pachwinową a4'),
      ];

  @override
  SkillMatch? match(Utterance u, AssistantContext ctx) {
    if (explainedTool(u) != null ||
        RegExp(r'^(?:otworz|pokaz|open|show)\b').hasMatch(u.folded)) {
      return null;
    }
    final fillet = u.hasStem(const ['pachwin', 'fillet']);
    final strength = u.hasStem(const [
      'nosnos',
      'wytrzym',
      'przeniesie',
      'udzwign',
      'wytrzyma',
      'resistan',
      'strength',
      'carry'
    ]);
    if (!fillet || (!strength && !u.hasAny(const ['kn']))) {
      // „Spoina a4 długość … S355” bez słowa „pachwinowa” — też nośność,
      // gdy jest gatunek stali i grubość a.
      final s = _slots(u);
      if (!(u.hasStem(const ['spoin', 'weld']) &&
          s.containsKey('steel') &&
          s.containsKey('throat_mm') &&
          s.containsKey('length_mm'))) {
        return null;
      }
    }
    if (u.hasStem(const ['spoiw', 'filler', 'drut', 'elektrod', 'zuzyc'])) {
      return null;
    }
    final s = _slots(u);
    return SkillMatch(this, s.isNotEmpty || strength ? .92 : .7,
        slots: s, utterance: u);
  }

  @override
  Map<String, Object?> slotsFrom(Utterance u, AssistantContext ctx) =>
      _slots(u);

  @override
  Map<String, Object?>? fillSlot(
      String slot, Utterance u, AssistantContext ctx) {
    final s = _slots(u);
    if (s.containsKey(slot)) return {slot: s[slot]};
    final items = u.items;
    final number = items.where((i) => i.isNumber).toList();
    if (number.length != 1) {
      return slot == 'force_kn' &&
              u.hasAny(const ['nie', 'brak', 'no', 'none', 'pomin', 'skip'])
          ? {slot: 0}
          : null;
    }
    final v = number.single.value!;
    final unit = items.length > 1 ? items.last.word : '';
    return switch (slot) {
      'throat_mm' || 'length_mm' || 'part_thickness_mm' =>
        lengthUnitScale(unit) != null
            ? {slot: v * lengthUnitScale(unit)!}
            : items.length == 1
                ? {slot: v}
                : null,
      'welds' => {slot: v},
      'force_kn' => {slot: v},
      _ => null,
    };
  }

  @override
  Future<SkillResult> run(SkillMatch m, AssistantContext ctx) async {
    AskResult ask(String key, String pl, String en) =>
        AskResult(key, AssistantText(pl, en), partial: m);
    final steel = WeldSteelGrade.values
        .where((g) => g.name == m.slots['steel'])
        .firstOrNull;
    if (steel == null) {
      return ask('steel', 'Jaki gatunek stali: S235, S275, S355, S420 czy S460?',
          'Which steel grade: S235, S275, S355, S420 or S460?');
    }
    final a = m.slots['throat_mm'];
    if (a is! num || !a.isFinite || a <= 0) {
      return ask(
          'throat_mm',
          'Jaka grubość obliczeniowa spoiny a w mm? (albo bok z, np. z6)',
          'What is the throat thickness a in mm? (or leg z, e.g. z6)');
    }
    final t = m.slots['part_thickness_mm'];
    if (t is! num || !t.isFinite || t <= 0) {
      return ask('part_thickness_mm',
          'Jaka grubość najgrubszej łączonej blachy w mm?',
          'What is the thickness of the thickest joined part in mm?');
    }
    final length = m.slots['length_mm'];
    if (length is! num || !length.isFinite || length <= 0) {
      return ask('length_mm', 'Jaka długość jednej spoiny w mm?',
          'What is the length of one weld in mm?');
    }
    final welds = m.slots['welds'];
    if (welds is! num ||
        welds != welds.roundToDouble() ||
        welds < 1 ||
        welds > 8) {
      return ask('welds', 'Ile jest spoin tej długości (1–8)?',
          'How many welds of this length (1–8)?');
    }
    final input = FilletWeldInput(
        steel: steel,
        throatMm: a.toDouble(),
        maxPartThicknessMm: t.toDouble(),
        lengthMm: length.toDouble(),
        welds: welds.toInt());
    final problems = filletProblems(input);
    final result = computeFilletWeld(input);
    if (result == null) {
      final first = problems.first;
      final (pl, en) = switch (first) {
        FilletProblem.throatBelowMin => (
            'Grubość a poniżej 3 mm — EN 1993-1-8 jej nie dopuszcza.',
            'Throat below 3 mm — EN 1993-1-8 does not allow it.'
          ),
        FilletProblem.lengthTooShort => (
            'Spoina za krótka: długość efektywna l − 2a musi mieć co najmniej max(30 mm; 6a).',
            'Weld too short: effective length l − 2a must be at least max(30 mm; 6a).'
          ),
        FilletProblem.thicknessOver40 => (
            'Blacha ponad 40 mm — poza tabelą fu tego modułu.',
            'Plate over 40 mm — outside this module\'s fu table.'
          ),
        FilletProblem.tooLongForThroat => (
            'Spoina dłuższa niż 900·a — redukcja długiego połączenia daje zero.',
            'Weld longer than 900·a — the long joint reduction gives zero.'
          ),
        _ => (
            'Sprawdź dane spoiny — moduł ich nie przyjął.',
            'Check the weld data — the module did not accept it.'
          ),
      };
      return FailedResult(AssistantText(pl, en));
    }
    String f(num v) => fmt(v.toDouble(), ctx.lang);
    // Nośność w DÓŁ do 0,1 kN — liczba obok werdyktu nie może mu przeczyć.
    final frd = (result.resistanceKn * 10).floorToDouble() / 10;
    final force = m.slots['force_kn'];
    final fields = <String, Object?>{
      'steel': steel.name,
      'throat_mm': a.toDouble(),
      'part_thickness_mm': t.toDouble(),
      'length_mm': length.toDouble(),
      'welds': welds.toInt(),
    };
    var pl = 'Nośność obliczeniowa F_Rd = ${f(frd)} kN '
        '(${steel.label}, a ${f(a)} mm, ${welds.toInt()} × ${f(length)} mm, '
        'metoda uproszczona EN 1993-1-8 §4.5.3.3).';
    var en = 'Design resistance F_Rd = ${f(frd)} kN '
        '(${steel.label}, a ${f(a)} mm, ${welds.toInt()} × ${f(length)} mm, '
        'simplified method EN 1993-1-8 §4.5.3.3).';
    if (m.slots['leg_given'] == true) {
      pl += ' Bok z przeliczony na a = z/√2.';
      en += ' Leg z converted to a = z/√2.';
    }
    if (force is num && force.isFinite && force > 0) {
      final check = FilletCheck(
          designForceKn: designForceKn(force.toDouble(), ForceKind.design)!,
          resistanceKn: result.resistanceKn);
      fields['force_kn'] = force.toDouble();
      final pct = (check.ratio * 100).ceil();
      pl += check.ok
          ? ' Siła obliczeniowa ${f(force)} kN — wystarczy (wykorzystanie $pct %).'
          : ' Siła obliczeniowa ${f(force)} kN — NIE wystarczy (wykorzystanie $pct %).';
      en += check.ok
          ? ' Design force ${f(force)} kN — sufficient ($pct % utilisation).'
          : ' Design force ${f(force)} kN — NOT sufficient ($pct % utilisation).';
    }
    pl += ' Wynik nie zastępuje projektu konstrukcji.';
    en += ' The result does not replace a structural design.';
    return AnswerResult(AssistantAnswer(text: AssistantText(pl, en)),
        show: ShowInModule(toolId, fields));
  }
}
