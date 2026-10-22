import '../../../domain/fitter/cone_assistant_input.dart';
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
  if (u.hasStem(const ['mimosrod', 'eccentric', 'przejsc', 'transition'])) {
    s['shape'] = 'unsupported';
  }
  final parts = <double>{};
  for (var i = 0; i < u.items.length; i++) {
    if (!u.items[i].word.startsWith('czesc') &&
        !u.items[i].word.startsWith('part')) {
      continue;
    }
    if (i > 0 && u.items[i - 1].isNumber) parts.add(signedQuantity(u, i - 1));
    if (i + 1 < u.items.length && u.items[i + 1].isNumber) {
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
    return SkillMatch(this, .94,
        slots: _slots(u),
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
    if (s.containsKey(slot) || slot == 'inputs' && s.isNotEmpty) return s;
    if (const ['large_dia_mm', 'small_dia_mm', 'thickness_mm'].contains(slot)) {
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
          'Sterowanie stożkiem mimośrodowym i przejściem nie jest jeszcze podłączone. Otwórz moduł i wybierz ten kształt ręcznie.',
          'Assistant control of eccentric cones and transitions is not connected yet. Open the module and select that shape manually.'));
    }
    if (s['shape'] != 'concentric') {
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
