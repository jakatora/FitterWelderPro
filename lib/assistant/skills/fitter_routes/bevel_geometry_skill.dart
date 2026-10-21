import '../../../domain/fitter/fitter_calcs.dart';
import '../../core/skill.dart';
import '../core/explain_tool_skill.dart' show explainedTool;
import '../core/skill_words.dart';
import 'quantities.dart';

Map<String, Object?> _slots(Utterance u) {
  final out = <String, Object?>{};
  for (final entry in {
    'wall_mm': ['sciank', 'thick', 'wall', 'grubosc'],
    'root_face_mm': ['prog', 'land', 'face'],
    'gap_mm': ['szczelin', 'gap'],
  }.entries) {
    final value = lengthNear(u, entry.value);
    if (value != null) out[entry.key] = value;
  }
  final angles = <double>{};
  for (var i = 0; i < u.items.length; i++) {
    if (!const ['kat', 'angle', 'rowka', 'groove', 'fazy', 'bevel']
        .contains(u.items[i].word)) {
      continue;
    }
    for (var j = i + 1; j < u.items.length && j <= i + 3; j++) {
      final n = u.items[j];
      if (n.isNumber) {
        final scale = j + 1 < u.items.length
            ? lengthUnitScale(u.items[j + 1].word)
            : null;
        angles.add(scale == null ? signedQuantity(u, j) : double.nan);
        break;
      }
      if (!const ['na', 'strone', 'per', 'side', 'minus', 'wynosi', 'is']
          .contains(n.word)) {
        break;
      }
    }
  }
  if (angles.isNotEmpty) {
    out['angle_deg'] = angles.length == 1 ? angles.single : double.nan;
  }
  final included = u.hasStem(const ['rowka', 'groove', 'included', 'calkowit']);
  final perSide = u.hasAny(const ['na strone', 'per side']);
  if (included || perSide) {
    out['convention'] = included && perSide
        ? 'ambiguous'
        : included
            ? 'grooveIncluded'
            : 'perSide';
  }
  final v = u.hasAny(const ['v', 'single v']);
  final x = u.hasAny(const ['x', 'double v']);
  if (v || x) {
    out['joint'] = v && x && !u.hasAny(const ['double v'])
        ? 'ambiguous'
        : x
            ? 'x'
            : 'v';
  }
  return out;
}

class BevelGeometrySkill extends AssistantSkill {
  @override
  String get id => 'bevel.geometry';
  @override
  String get toolId => 'bevel';
  @override
  AssistantTier get tier => AssistantTier.b;
  @override
  List<SkillExample> get examples => const [
        SkillExample(
            'Fazowanie V ścianka 10 mm kąt rowka 60 stopni próg 1 mm szczelina 0 mm',
            'Bevel V wall 10 mm groove angle 60 degrees root face 1 mm gap 0 mm'),
        SkillExample(
            'Fazowanie X ścianka 20 mm kąt na stronę 30 próg 2 mm szczelina 2 mm',
            'Bevel X wall 20 mm angle per side 30 root face 2 mm gap 2 mm'),
        SkillExample('Oblicz fazowanie', 'Calculate bevel'),
        SkillExample(
            'Oblicz ukosowanie V ścianka 10 mm kąt na stronę 30 próg 1 mm szczelina 2 mm',
            'Calculate bevel preparation V wall 10 mm angle per side 30 root face 1 mm gap 2 mm'),
        SkillExample('Fazowanie V ścianka 8 mm', 'Bevel V wall 8 mm'),
        SkillExample('Fazowanie X ścianka 12 mm kąt rowka 60',
            'Bevel X wall 12 mm groove angle 60'),
        SkillExample(
            'Fazowanie V ścianka 1 cm kąt na stronę 37,5 próg 1 mm szczelina 3 mm',
            'Bevel V wall 1 cm angle per side 37.5 root face 1 mm gap 3 mm'),
      ];
  @override
  List<SkillRejection> get rejections => const [
        SkillRejection('otwórz fazowanie', routesTo: 'tool.open'),
        SkillRejection('do czego służy fazowanie', routesTo: 'tool.explain'),
        SkillRejection('oblicz spadek 1% na 6 m'),
      ];
  @override
  SkillMatch? match(Utterance u, AssistantContext ctx) {
    if (explainedTool(u) != null ||
        RegExp(r'^(?:otworz|pokaz|open|show)\b').hasMatch(u.folded)) {
      return null;
    }
    if (!u.hasStem(const ['fazow', 'ukosow', 'bevel'])) return null;
    final s = _slots(u);
    return SkillMatch(
        this,
        s.isNotEmpty || u.hasStem(const ['oblicz', 'policz', 'calculate'])
            ? .92
            : .65,
        slots: s,
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
    if (const ['wall_mm', 'root_face_mm', 'gap_mm'].contains(slot)) {
      final numbers = <double>{};
      for (var i = 0; i + 1 < u.items.length; i++) {
        final scale = lengthUnitScale(u.items[i + 1].word);
        if (u.items[i].isNumber && scale != null) {
          numbers.add(signedQuantity(u, i) * scale);
        }
      }
      if (numbers.length == 1) return {slot: numbers.single};
    }
    if (slot == 'angle_deg') {
      final numbers = [
        for (var i = 0; i < u.items.length; i++)
          if (u.items[i].isNumber) signedQuantity(u, i)
      ];
      if (numbers.length == 1 && u.hasStem(const ['stopn', 'degree'])) {
        return {slot: numbers.single, ...s};
      }
    }
    return null;
  }

  @override
  Future<SkillResult> run(SkillMatch m, AssistantContext ctx) async {
    AskResult ask(String key, String pl, String en) =>
        AskResult(key, AssistantText(pl, en), partial: m);
    final s = m.slots;
    double? number(String key) =>
        s[key] is num ? (s[key] as num).toDouble() : null;
    final wall = number('wall_mm'),
        angle = number('angle_deg'),
        land = number('root_face_mm'),
        gap = number('gap_mm');
    if (wall == null || !wall.isFinite || wall <= 0) {
      return ask('wall_mm', 'Jaka grubość ścianki? Podaj jednostkę, np. 10 mm.',
          'What wall thickness? Include a unit, e.g. 10 mm.');
    }
    final joint =
        BevelJoint.values.where((v) => v.name == s['joint']).firstOrNull;
    if (joint == null) {
      return ask('joint', 'Jaki typ przygotowania: V czy X?',
          'Which joint preparation: V or X?');
    }
    final conv = BevelAngleConvention.values
        .where((v) => v.name == s['convention'])
        .firstOrNull;
    if (conv == null) {
      return ask(
          'convention',
          'Czy podany kąt jest na stronę, czy to całkowity kąt rowka?',
          'Is the angle per side or the included groove angle?');
    }
    if (angle == null ||
        !angle.isFinite ||
        bevelPerSideDeg(angle, conv) <= 0 ||
        bevelPerSideDeg(angle, conv) >= 60) {
      return ask(
          'angle_deg',
          'Podaj kąt w stopniach: poniżej 60° na stronę lub poniżej 120° dla całego rowka.',
          'Give an angle in degrees: below 60° per side or below 120° included.');
    }
    if (land == null || !land.isFinite || land < 0 || land >= wall) {
      return ask(
          'root_face_mm',
          'Jaki próg? Podaj od 0 mm do wartości mniejszej niż grubość ścianki.',
          'What root face? Give 0 mm or more, less than the wall thickness.');
    }
    if (gap == null || !gap.isFinite || gap < 0) {
      return ask(
          'gap_mm',
          'Jaka szczelina? Podaj jednostkę, np. 0 mm lub 2 mm.',
          'What root gap? Include a unit, e.g. 0 mm or 2 mm.');
    }
    final geo = bevelGeometry(
        joint: joint,
        wallMm: wall,
        angleDeg: angle,
        convention: conv,
        rootFaceMm: land,
        gapMm: gap);
    if (!geo.widthPerSideMm.isFinite || !geo.grooveOpeningMm.isFinite) {
      return const FailedResult(AssistantText(
          'Wynik poza zakresem. Sprawdź dane.',
          'Result out of range. Check inputs.'));
    }
    return AnswerResult(
        AssistantAnswer(
            text: AssistantText(
                'Faza ${joint.name.toUpperCase()}: głębokość z jednej strony ${fmt(geo.depthPerFaceMm, ctx.lang)} mm, szerokość na stronę ${fmt(geo.widthPerSideMm, ctx.lang)} mm, rozwarcie rowka ${fmt(geo.grooveOpeningMm, ctx.lang)} mm. Kąt na stronę ${fmt(geo.perSideDeg, ctx.lang)}°, całkowity ${fmt(geo.grooveDeg, ctx.lang)}°. Geometria dla podanych danych; przygotowanie złącza dobierz według WPS.',
                '${joint.name.toUpperCase()} preparation: depth per face ${fmt(geo.depthPerFaceMm, ctx.lang)} mm, width per side ${fmt(geo.widthPerSideMm, ctx.lang)} mm, groove opening ${fmt(geo.grooveOpeningMm, ctx.lang)} mm. Angle per side ${fmt(geo.perSideDeg, ctx.lang)}°, included ${fmt(geo.grooveDeg, ctx.lang)}°. Geometry for your inputs; choose joint preparation according to the WPS.')),
        show: ShowInModule(toolId, {
          'wall_mm': wall,
          'angle_deg': angle,
          'root_face_mm': land,
          'gap_mm': gap,
          'joint': joint.name,
          'convention': conv.name
        }));
  }
}
