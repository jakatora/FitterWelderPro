import '../../../domain/fitter/cone_assistant_input.dart';
import '../../../domain/fitter/eccentric_cone_assistant_input.dart';
import '../../../domain/fitter/cone_development.dart';
import '../../core/skill.dart';
import '../../core/command_words.dart';
import '../core/explain_tool_skill.dart' show explainedTool;
import 'quantities.dart';

Map<String, Object?> _slots(Utterance original) {
  final u = original.withRaw(original.raw.replaceAllMapped(
      RegExp(r'(large|small) (?:diameter|dia)', caseSensitive: false),
      (m) => m[1]!));
  final s = <String, Object?>{};
  for (final entry in {
    'large_dia_mm': ['duza', 'duzej', 'large'],
    'small_dia_mm': ['mala', 'malej', 'small'],
    'height_mm': ['wysokosc', 'height'],
    'slant_mm': ['tworzac', 'slant'],
    'thickness_mm': ['grubosc', 'blacha', 'thickness'],
    'allowance_mm': ['naddat', 'allowance'],
    'offset_mm': ['przesunie', 'offset'],
  }.entries) {
    final value = lengthNear(u, entry.value);
    if (value != null) s[entry.key] = value;
  }
  final angle = angleValue(u);
  if (angle != null) s['half_angle_deg'] = angle;
  final modes = {
    if (s.containsKey('height_mm')) 'height',
    if (s.containsKey('slant_mm')) 'slant',
    if (s.containsKey('half_angle_deg')) 'halfAngle',
  };
  if (modes.isNotEmpty) {
    s['mode'] = modes.length == 1 &&
            (angle == null || u.hasStem(const ['polowk', 'half']))
        ? modes.single
        : 'ambiguous';
  }
  final refs = {
    if (u.hasStem(const ['zewnetrz', 'outside', 'external'])) 'outside',
    if (u.hasStem(const ['wewnetrz', 'inside', 'internal'])) 'inside',
    if (u.hasAny(
        const ['srednie', 'srednia', 'sredni', 'srednich', 'mean', 'neutral']))
      'mean',
  };
  // "Średnica" is not the mean-diameter reference.
  if (refs.isNotEmpty) {
    s['reference'] = refs.length == 1 ? refs.single : 'ambiguous';
  }
  if (u.hasStem(const ['wspolosiow', 'concentric'])) s['shape'] = 'concentric';
  if (u.hasStem(const ['mimosrod', 'eccentric'])) s['shape'] = 'eccentric';
  if (u.hasStem(const ['przejsc', 'transition'])) {
    s['shape'] = 'unsupported';
  }
  if (u.hasAny(const ['scianka pionowa', 'pionowa scianka', 'vertical side'])) {
    s['vertical_side'] = true;
    s['offset_mm'] = null;
  }
  if (u.hasStem(const ['przesunie', 'offset'])) {
    if (s['vertical_side'] == true) {
      s['vertical_side'] = 'ambiguous';
    } else {
      s['vertical_side'] = false;
    }
    if (!s.containsKey('offset_mm')) s['offset_mm'] = double.nan;
  }
  if (u.hasStem(const ['szew', 'seam'])) {
    final short = u.hasStem(const ['krotk', 'short']);
    final long = u.hasStem(const ['dlug', 'long']);
    s['seam_on_short_side'] = short == long ? 'ambiguous' : short;
  }
  final divisions = <double>{};
  for (var i = 0; i < u.items.length; i++) {
    if (!u.items[i].word.startsWith('podzial') &&
        !u.items[i].word.startsWith('division')) {
      continue;
    }
    if (i + 1 < u.items.length &&
        u.items[i + 1].isNumber &&
        !(i + 2 < u.items.length &&
            (u.items[i + 2].word.startsWith('czesc') ||
                u.items[i + 2].word.startsWith('part')))) {
      divisions.add(signedQuantity(u, i + 1));
    }
    if (i > 0 && u.items[i - 1].isNumber) {
      divisions.add(signedQuantity(u, i - 1));
    }
  }
  if (u.hasStem(const ['podzial', 'division'])) {
    final n = divisions.length == 1 ? divisions.single : double.nan;
    s['divisions'] = n.isFinite && n == n.roundToDouble() ? n.toInt() : -1;
  }
  final parts = <double>{};
  for (var i = 0; i < u.items.length; i++) {
    if (!u.items[i].word.startsWith('czesc') &&
        !u.items[i].word.startsWith('part')) {
      continue;
    }
    if (i > 0 && u.items[i - 1].isNumber) parts.add(signedQuantity(u, i - 1));
    if (i + 1 < u.items.length &&
        u.items[i + 1].isNumber &&
        !(i + 2 < u.items.length &&
            (u.items[i + 2].word.startsWith('podzial') ||
                u.items[i + 2].word.startsWith('division')))) {
      parts.add(signedQuantity(u, i + 1));
    }
  }
  if (u.hasStem(const ['naddat', 'allowance']) &&
      !s.containsKey('allowance_mm')) {
    s['allowance_mm'] = double.nan;
  }
  if (parts.isEmpty && u.hasStem(const ['czesc', 'part'])) s['parts'] = -1;
  if (parts.isNotEmpty) {
    final n = parts.length == 1 ? parts.single : double.nan;
    s['parts'] = n.isFinite && n == n.roundToDouble() ? n.toInt() : -1;
  }
  if (RegExp(r'[-−]\s*\d|\bminus\b').hasMatch(original.raw.toLowerCase())) {
    s['large_dia_mm'] = double.nan;
  }
  return s;
}

bool _needsInterpretation(Utterance source) {
  // A named half-angle is a literal geometric convention, not "half of" a value.
  final u = source.withRaw(source.folded
      .replaceAll(RegExp(r'\b(?:kat polowkowy|half angle)\b'), 'angle'));
  return pendingReplyNeedsInterpretation(u) || requestsCurrentFormEdit(u);
}

class ConeLayoutSkill extends AssistantSkill {
  @override
  String get id => 'cone.layout';
  @override
  String get toolId => 'cone_layout';
  @override
  AssistantTier get tier => AssistantTier.b;
  @override
  List<SkillExample> get examples => const [
        SkillExample(
            'Oblicz stożek współosiowy duża 600 mm mała 200 mm wysokość 400 mm grubość 4 mm zewnętrzne',
            'Calculate concentric cone large 600 mm small 200 mm height 400 mm thickness 4 mm outside'),
        SkillExample(
            'Stożek współosiowy duża 60 cm mała 20 cm tworząca 450 mm grubość 4 mm wewnętrzne',
            'Concentric cone large 60 cm small 20 cm slant 450 mm thickness 4 mm inside'),
        SkillExample(
            'Stożek współosiowy duża 600 mm mała 0 mm kąt połówkowy 30 stopni grubość 0 mm średnie',
            'Concentric cone large 600 mm small 0 mm half angle 30 degrees thickness 0 mm mean'),
        SkillExample('Oblicz rozwinięcie stożka', 'Calculate cone development'),
        SkillExample(
            'Stożek współosiowy duża 800 mm mała 300 mm wysokość 500 mm grubość 5 mm zewnętrzne 2 części naddatek 10 mm',
            'Concentric cone large 800 mm small 300 mm height 500 mm thickness 5 mm outside 2 parts allowance 10 mm'),
        SkillExample(
            'Stożek współosiowy duża 800 mm mała 300 mm wysokość 500 mm grubość 5 mm',
            'Concentric cone large 800 mm small 300 mm height 500 mm thickness 5 mm'),
      ];
  @override
  List<SkillRejection> get rejections => const [
        SkillRejection('Otwórz rozwinięcie stożka', routesTo: 'tool.open'),
        SkillRejection('Oblicz fazowanie V ścianka 10 mm'),
        SkillRejection('Do czego służy rozwinięcie stożka',
            routesTo: 'tool.explain'),
      ];
  @override
  SkillMatch? match(Utterance u, AssistantContext ctx) {
    if (referencesInstruction(u) ||
        isNegatedCommand(u) ||
        explainedTool(u) != null ||
        kOpenVerbAtStartRe.hasMatch(u.folded)) {
      return null;
    }
    if (!u.hasStem(const ['stoz', 'cone'])) return null;
    final slots = _slots(u);
    if (id == 'cone.layout' && slots['shape'] == 'eccentric' ||
        id == 'cone.eccentric' && slots['shape'] != 'eccentric') {
      return null;
    }
    return SkillMatch(this, .94,
        slots: slots,
        utterance: u,
        explicitToolTarget: true,
        requiresAiInterpretation: _needsInterpretation(u));
  }

  @override
  Map<String, Object?> slotsFrom(Utterance u, AssistantContext ctx) =>
      _slots(u);
  @override
  Map<String, Object?>? fillSlot(
      String slot, Utterance u, AssistantContext ctx) {
    final s = _slots(u);
    if (RegExp(r'[-−]\s*\d|\bminus\b').hasMatch(u.raw.toLowerCase())) {
      return {slot: double.nan};
    }
    if (slot == 'eccentric_offset' && s.containsKey('vertical_side')) return s;
    if (s.containsKey(slot) || slot == 'inputs' && s.isNotEmpty) return s;
    if (const [
      'large_dia_mm',
      'small_dia_mm',
      'thickness_mm',
      'eccentric_offset'
    ].contains(slot)) {
      final values = <double>{};
      for (var i = 0; i + 1 < u.items.length; i++) {
        final scale = lengthUnitScale(u.items[i + 1].word);
        if (u.items[i].isNumber && scale != null) {
          values.add(signedQuantity(u, i) * scale);
        }
      }
      if (values.length == 1) {
        return slot == 'eccentric_offset'
            ? {'offset_mm': values.single, 'vertical_side': false}
            : {slot: values.single};
      }
    }
    return null;
  }

  @override
  bool acceptsProposal(
      Utterance original, Utterance command, AssistantContext context) {
    if (referencesInstruction(original) ||
        isNegatedCommand(original) ||
        _needsInterpretation(original)) {
      return false;
    }
    final proposed = _slots(command), source = _slots(original);
    return source.isNotEmpty &&
        proposed.isNotEmpty &&
        proposed.entries.every((e) => source[e.key] == e.value) &&
        source.entries.every((e) => proposed[e.key] == e.value);
  }

  @override
  Future<SkillResult> run(SkillMatch m, AssistantContext ctx) async {
    AskResult ask(String key, String pl, String en) =>
        AskResult(key, AssistantText(pl, en), partial: m);
    final s = m.slots;
    if (s['shape'] == 'unsupported') {
      return const FailedResult(AssistantText(
          'Sterowanie przejściem nie jest jeszcze podłączone. Otwórz moduł i wybierz ten kształt ręcznie.',
          'Assistant control of transitions is not connected yet. Open the module and select that shape manually.'));
    }
    if (s['shape'] != 'concentric' && s['shape'] != 'eccentric') {
      return ask('shape', 'Czy chodzi o stożek współosiowy?',
          'Is this a concentric cone?');
    }
    for (final e in {
      'large_dia_mm': (
        'Jaka duża średnica? Podaj jednostkę, np. 600 mm.',
        'What large diameter? Include a unit, e.g. 600 mm.'
      ),
      'small_dia_mm': (
        'Jaka mała średnica? Podaj jednostkę; 0 mm oznacza pełny stożek.',
        'What small diameter? Include a unit; 0 mm means a full cone.'
      ),
      'thickness_mm': (
        'Jaka grubość blachy? Podaj jednostkę, np. 4 mm.',
        'What plate thickness? Include a unit, e.g. 4 mm.'
      ),
    }.entries) {
      final v = s[e.key];
      if (v is! num ||
          !v.isFinite ||
          v < 0 ||
          e.key == 'large_dia_mm' && v == 0) {
        return ask(e.key, e.value.$1, e.value.$2);
      }
    }
    if (!DiameterRef.values.any((v) => v.name == s['reference'])) {
      return ask(
          'reference',
          'Czy średnice są zewnętrzne, wewnętrzne czy średnie?',
          'Are the diameters outside, inside or mean?');
    }
    if (s['shape'] == 'eccentric') return _runEccentric(m);
    if (!ConeSizeMode.values.any((v) => v.name == s['mode'])) {
      return ask(
          'inputs',
          'Podaj jeden wymiar boku: wysokość w mm, tworzącą w mm albo kąt połówkowy w stopniach.',
          'Give one side dimension: height in mm, slant in mm or half angle in degrees.');
    }
    final fields = <String, Object?>{
      ...s,
      'parts': s['parts'] ?? 1,
      'allowance_mm': s['allowance_mm'] ?? 0
    };
    ConeAssistantInput parsed;
    try {
      parsed = ConeAssistantInput.fromFields(fields);
    } on FormatException {
      return ask(
          'inputs',
          'Wymiary są sprzeczne lub poza zakresem kalkulatora. Popraw średnice, grubość i wymiar boku; części: 1, 2, 3, 4, 6, 8 lub 12; naddatek 0–200 mm.',
          'Dimensions conflict or exceed the calculator range. Correct diameters, thickness and side size; parts: 1, 2, 3, 4, 6, 8 or 12; allowance 0–200 mm.');
    }
    final r = parsed.result;
    return AnswerResult(
        AssistantAnswer(
            text: AssistantText(
                'Stożek współosiowy: promień zewnętrzny ${r.outerRadiusMm.toStringAsFixed(2)} mm, wewnętrzny ${r.innerRadiusMm.toStringAsFixed(2)} mm, kąt wycinka ${r.sectorAngleDeg.toStringAsFixed(2)}°. Części: ${r.parts}, naddatek ${parsed.input.allowanceMm} mm. Wymiary według wybranego odniesienia średnic.',
                'Concentric cone: outer radius ${r.outerRadiusMm.toStringAsFixed(2)} mm, inner radius ${r.innerRadiusMm.toStringAsFixed(2)} mm, sector angle ${r.sectorAngleDeg.toStringAsFixed(2)}°. Parts: ${r.parts}, allowance ${parsed.input.allowanceMm} mm. Dimensions use the selected diameter reference.')),
        show: ShowInModule(toolId, fields));
  }
}

Future<SkillResult> _runEccentric(SkillMatch m) async {
  AskResult ask(String pl, String en) =>
      AskResult('inputs', AssistantText(pl, en), partial: m);
  final s = m.slots;
  if (s['vertical_side'] is! bool) {
    return AskResult(
        'eccentric_offset',
        const AssistantText(
            'Podaj przesunięcie osi w mm albo wybierz jedną ściankę pionową; nie łącz obu wariantów.',
            'Give the axis offset in mm or choose one vertical side; do not combine both variants.'),
        partial: m);
  }
  final fields = <String, Object?>{
    ...s,
    'parts': s['parts'] ?? 1,
    'divisions': s['divisions'] ?? 16,
    'seam_on_short_side': s['seam_on_short_side'] ?? true
  };
  EccentricConeAssistantInput parsed;
  try {
    parsed = EccentricConeAssistantInput.fromFields(fields);
  } on FormatException {
    return ask(
        'Sprawdź wysokość, przesunięcie, średnice i grubość. Części: 1, 2 lub 4; podziały: 12, 16, 24, 32 lub 48; szew po krótkiej lub długiej stronie. Naddatek nie jest obsługiwany dla tego kształtu.',
        'Check height, offset, diameters and thickness. Parts: 1, 2 or 4; divisions: 12, 16, 24, 32 or 48; seam on short or long side. Allowance is unsupported for this shape.');
  }
  final r = parsed.result;
  return AnswerResult(
      AssistantAnswer(
          text: AssistantText(
              'Stożek mimośrodowy: przesunięcie ${r.offsetMm.toStringAsFixed(2)} mm, najkrótsza tworząca ${r.shortestGeneratorMm.toStringAsFixed(2)} mm, najdłuższa ${r.longestGeneratorMm.toStringAsFixed(2)} mm. Części: ${parsed.input.parts}, podziały: ${parsed.input.divisions}, szew: ${parsed.input.seamOnShortSide ? "krótka" : "długa"} strona. Rozwinięcie korzysta z przybliżenia osi obojętnej dla grubości blachy; sprawdź tabelę triangulacji.',
              'Eccentric cone: offset ${r.offsetMm.toStringAsFixed(2)} mm, shortest generator ${r.shortestGeneratorMm.toStringAsFixed(2)} mm, longest ${r.longestGeneratorMm.toStringAsFixed(2)} mm. Parts: ${parsed.input.parts}, divisions: ${parsed.input.divisions}, seam: ${parsed.input.seamOnShortSide ? "short" : "long"} side. Development uses a neutral-surface approximation for plate thickness; check the triangulation table.')),
      show: ShowInModule('cone_layout', fields));
}

class EccentricConeSkill extends ConeLayoutSkill {
  @override
  String get id => 'cone.eccentric';
  @override
  List<SkillExample> get examples => const [
        SkillExample(
            'Stożek mimośrodowy duża 600 mm mała 200 mm wysokość 400 mm grubość 4 mm zewnętrzne przesunięcie 100 mm',
            'Eccentric cone large 600 mm small 200 mm height 400 mm thickness 4 mm outside offset 100 mm'),
        SkillExample(
            'Stożek mimośrodowy duża 600 mm mała 200 mm wysokość 400 mm grubość 4 mm wewnętrzne ścianka pionowa',
            'Eccentric cone large 600 mm small 200 mm height 400 mm thickness 4 mm inside vertical side'),
        SkillExample(
            'Stożek mimośrodowy duża 600 mm mała 200 mm wysokość 400 mm grubość 0 mm średnie przesunięcie 50 mm 2 części 24 podziały szew po długiej stronie',
            'Eccentric cone large 600 mm small 200 mm height 400 mm thickness 0 mm mean offset 50 mm 2 parts 24 divisions seam long side'),
        SkillExample('Oblicz stożek mimośrodowy', 'Calculate eccentric cone'),
        SkillExample(
            'Stożek mimośrodowy duża 60 cm mała 0 mm wysokość 40 cm grubość 0 mm średnie przesunięcie 100 mm',
            'Eccentric cone large 60 cm small 0 mm height 40 cm thickness 0 mm mean offset 100 mm'),
        SkillExample(
            'Stożek mimośrodowy duża 600 mm mała 200 mm wysokość 400 mm grubość 4 mm zewnętrzne',
            'Eccentric cone large 600 mm small 200 mm height 400 mm thickness 4 mm outside'),
      ];
}
