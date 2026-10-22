import '../../../domain/fitter/transition_assistant_input.dart';
import '../../../domain/fitter/cone_development.dart';
import '../../core/skill.dart';
import '../../core/command_words.dart';
import '../core/explain_tool_skill.dart' show explainedTool;
import 'quantities.dart';

Map<String, Object?> _slots(Utterance original) {
  // Preserve typed signs before speech folding removes punctuation.
  var raw = original.raw.replaceAll(RegExp(r'[-−]\s*(?=\d)'), ' minus ');
  for (final e in {
    r'\b(?:bok|side)\s+a\b': 'sidea',
    r'\b(?:bok|side)\s+b\b': 'sideb',
    r'(?:przesunięcie|przesuniecie|offset)\s+x\b': 'offsetx',
    r'(?:przesunięcie|przesuniecie|offset)\s+y\b': 'offsety',
  }.entries) {
    raw = raw.replaceAll(RegExp(e.key, caseSensitive: false), e.value);
  }
  final u = original.withRaw(raw), s = <String, Object?>{};
  for (final e in {
    'side_a_mm': ['sidea'],
    'side_b_mm': ['sideb'],
    'diameter_mm': ['srednic', 'diameter'],
    'height_mm': ['wysokosc', 'height'],
    'thickness_mm': ['grubosc', 'thickness'],
    'offset_x_mm': ['offsetx'],
    'offset_y_mm': ['offsety'],
  }.entries) {
    final n = lengthNear(u, e.value);
    if (n != null) s[e.key] = n;
  }
  if (u.hasStem(const ['centryczn', 'centered', 'centred']) ||
      u.hasAny(const ['bez przesuniecia', 'no offset'])) {
    for (final k in ['offset_x_mm', 'offset_y_mm']) {
      s[k] = s[k] == null || s[k] == 0 ? 0 : double.nan;
    }
  }
  final refs = {
    if (u.hasStem(const ['zewnetrz', 'outside', 'external'])) 'outside',
    if (u.hasStem(const ['wewnetrz', 'inside', 'internal'])) 'inside',
    if (u.hasAny(const ['srednie', 'srednia', 'sredni', 'mean', 'neutral']))
      'mean',
  };
  if (refs.isNotEmpty) {
    s['reference'] = refs.length == 1 ? refs.single : 'ambiguous';
  }
  for (final e in {
    'parts': ['czesc', 'part'],
    'divisions': ['podzial', 'division']
  }.entries) {
    final nums = <double>{};
    for (var i = 0; i < u.items.length; i++) {
      if (!e.value.any((k) => u.items[i].word.startsWith(k))) continue;
      if (i > 0 && u.items[i - 1].isNumber) nums.add(signedQuantity(u, i - 1));
      if (i + 1 < u.items.length &&
          u.items[i + 1].isNumber &&
          !(i + 2 < u.items.length &&
              const ['czesc', 'part', 'podzial', 'division']
                  .any((k) => u.items[i + 2].word.startsWith(k)))) {
        nums.add(signedQuantity(u, i + 1));
      }
    }
    if (u.hasStem(e.value)) {
      final n = nums.length == 1 ? nums.single : double.nan;
      s[e.key] = n.isFinite && n == n.roundToDouble() ? n.toInt() : -1;
    }
  }
  if (u.hasStem(const ['szew', 'seam'])) {
    final seams = {
      if (u.hasAny(const ['szew a', 'szew bok a', 'seam a', 'seam side a']))
        'sideA',
      if (u.hasAny(const ['szew b', 'szew bok b', 'seam b', 'seam side b']))
        'sideB',
      if (u.hasStem(const ['naroz', 'corner'])) 'corner',
    };
    // Use original words: normalization of side A/B belongs to dimensions.
    if (original.hasAny(const ['szew bok a', 'seam side a'])) {
      seams.add('sideA');
    }
    if (original.hasAny(const ['szew bok b', 'seam side b'])) {
      seams.add('sideB');
    }
    s['seam'] = seams.length == 1 ? seams.single : 'ambiguous';
  }
  if (u.hasStem(const ['naddat', 'allowance'])) {
    s['unsupported_allowance'] = true;
  }
  return s;
}

class TransitionLayoutSkill extends AssistantSkill {
  @override
  bool get currentFormEditsNeedAi => true;
  @override
  String get id => 'transition.layout';
  @override
  String get toolId => 'cone_layout';
  @override
  AssistantTier get tier => AssistantTier.b;
  @override
  List<SkillExample> get examples => const [
        SkillExample(
            'Oblicz przejście prostokąt koło bok A 600 mm bok B 400 mm średnica 300 mm wysokość 400 mm grubość 4 mm zewnętrzne centryczne',
            'Calculate rectangle to round transition side A 600 mm side B 400 mm diameter 300 mm height 400 mm thickness 4 mm outside centered'),
        SkillExample(
            'Przejście kwadrat koło bok A 500 mm bok B 500 mm średnica 200 mm wysokość 300 mm grubość 3 mm wewnętrzne przesunięcie X minus 50 mm przesunięcie Y 20 mm',
            'Square to round transition side A 500 mm side B 500 mm diameter 200 mm height 300 mm thickness 3 mm inside offset X minus 50 mm offset Y 20 mm'),
        SkillExample(
            'Przejście prostokąt koło bok A 600 mm bok B 400 mm średnica 300 mm wysokość 400 mm grubość 0 mm średnie centryczne 2 części 24 podziały szew naroże',
            'Rectangle to round transition side A 600 mm side B 400 mm diameter 300 mm height 400 mm thickness 0 mm mean centered 2 parts 24 divisions seam corner'),
        SkillExample('Oblicz przejście prostokąt koło',
            'Calculate rectangle to round transition'),
        SkillExample(
            'Przejście prostokąt koło bok A 60 cm bok B 40 cm średnica 30 cm wysokość 40 cm grubość 4 mm zewnętrzne centryczne szew A',
            'Rectangle to round transition side A 60 cm side B 40 cm diameter 30 cm height 40 cm thickness 4 mm outside centered seam A'),
        SkillExample(
            'Przejście prostokąt koło bok A 600 mm bok B 400 mm średnica 300 mm wysokość 400 mm grubość 4 mm',
            'Rectangle to round transition side A 600 mm side B 400 mm diameter 300 mm height 400 mm thickness 4 mm'),
      ];
  @override
  List<SkillRejection> get rejections => const [
        SkillRejection('Otwórz rozwinięcie stożka', routesTo: 'tool.open'),
        SkillRejection('Do czego służy rozwinięcie stożka',
            routesTo: 'tool.explain'),
        SkillRejection('Oblicz stożek współosiowy'),
      ];
  @override
  SkillMatch? match(Utterance u, AssistantContext ctx) {
    if (referencesInstruction(u) ||
        isNegatedCommand(u) ||
        explainedTool(u) != null ||
        kOpenVerbAtStartRe.hasMatch(u.folded)) {
      return null;
    }
    if (!(u.hasStem(const ['przejsc', 'transition']) &&
        u.hasStem(const ['prostokat', 'kwadrat', 'rectangle', 'square']) &&
        u.hasStem(const ['kolo', 'round']))) {
      return null;
    }
    return SkillMatch(this, .95,
        slots: _slots(u),
        utterance: u,
        explicitToolTarget: true,
        requiresAiInterpretation:
            pendingReplyNeedsInterpretation(u) || requestsCurrentFormEdit(u));
  }

  @override
  Map<String, Object?> slotsFrom(Utterance u, AssistantContext ctx) =>
      _slots(u);
  @override
  Map<String, Object?>? fillSlot(
      String slot, Utterance u, AssistantContext ctx) {
    final s = _slots(u);
    if (s.containsKey(slot) || slot == 'inputs' && s.isNotEmpty) return s;
    if (const [
      'side_a_mm',
      'side_b_mm',
      'diameter_mm',
      'height_mm',
      'thickness_mm'
    ].contains(slot)) {
      final signed =
          u.withRaw(u.raw.replaceAll(RegExp(r'[-−]\s*(?=\d)'), ' minus '));
      final nums = <double>{};
      for (var i = 0; i + 1 < signed.items.length; i++) {
        final scale = lengthUnitScale(signed.items[i + 1].word);
        if (signed.items[i].isNumber && scale != null) {
          nums.add(signedQuantity(signed, i) * scale);
        }
      }
      if (nums.length == 1) return {slot: nums.single};
    }
    return null;
  }

  @override
  bool acceptsProposal(
      Utterance original, Utterance command, AssistantContext context) {
    if (referencesInstruction(original) ||
        isNegatedCommand(original) ||
        pendingReplyNeedsInterpretation(original) ||
        requestsCurrentFormEdit(original)) {
      return false;
    }
    final a = _slots(original), b = _slots(command);
    return a.isNotEmpty &&
        a.length == b.length &&
        a.entries.every((e) => b[e.key] == e.value);
  }

  @override
  Future<SkillResult> run(SkillMatch m, AssistantContext ctx) async {
    AskResult ask(String slot, String pl, String en) =>
        AskResult(slot, AssistantText(pl, en), partial: m);
    final s = m.slots;
    for (final e in {
      'side_a_mm': (
        'Jaki bok A? Podaj jednostkę.',
        'What side A? Include a unit.'
      ),
      'side_b_mm': (
        'Jaki bok B? Podaj jednostkę.',
        'What side B? Include a unit.'
      ),
      'diameter_mm': (
        'Jaka średnica koła? Podaj jednostkę.',
        'What circle diameter? Include a unit.'
      ),
      'height_mm': (
        'Jaka wysokość? Podaj jednostkę.',
        'What height? Include a unit.'
      ),
      'thickness_mm': (
        'Jaka grubość blachy? Podaj jednostkę.',
        'What plate thickness? Include a unit.'
      ),
    }.entries) {
      final n = s[e.key];
      if (n is! num ||
          !n.isFinite ||
          n < 0 ||
          n == 0 && e.key != 'thickness_mm') {
        return ask(e.key, e.value.$1, e.value.$2);
      }
    }
    if (!DiameterRef.values.any((r) => r.name == s['reference'])) {
      return ask(
          'reference',
          'Czy wymiary są zewnętrzne, wewnętrzne czy średnie?',
          'Are the dimensions outside, inside or mean?');
    }
    if (['offset_x_mm', 'offset_y_mm']
        .any((k) => s[k] is! num || !(s[k] as num).isFinite)) {
      return ask(
          'inputs',
          'Podaj przesunięcie X i Y z jednostką i znakiem albo wybierz przejście centryczne.',
          'Give signed X and Y offsets with units or choose a centered transition.');
    }
    final fields = <String, Object?>{
      ...s,
      'shape': 'transition',
      'parts': s['parts'] ?? 1,
      'divisions': s['divisions'] ?? 16,
      'seam': s['seam'] ?? 'sideB'
    };
    TransitionAssistantInput parsed;
    try {
      parsed = TransitionAssistantInput.fromFields(fields);
    } on FormatException {
      return ask(
          'inputs',
          'Popraw wymiary. Części: 1, 2 lub 4; podziały: 12, 16, 24, 32 lub 48; szew A, B lub naroże. Naddatek nie jest obsługiwany.',
          'Correct dimensions. Parts: 1, 2 or 4; divisions: 12, 16, 24, 32 or 48; seam A, B or corner. Allowance is unsupported.');
    }
    final r = parsed.result, i = parsed.input;
    return AnswerResult(
        AssistantAnswer(
            text: AssistantText(
                'Przejście prostokąt–koło: ${i.parts} części, ${i.divisions} podziałów, szew ${i.seam.name}. Przesunięcie X ${i.offsetXMm} mm, Y ${i.offsetYMm} mm. Krawędź dolna ${r.bottomEdgeMm.toStringAsFixed(2)} mm, górna ${r.topEdgeMm.toStringAsFixed(2)} mm. Sprawdź tabelę triangulacji i przybliżenie osi obojętnej. ${i.circleOverhangs ? "Koło wystaje poza prostokąt." : ""}',
                'Rectangle-to-round transition: ${i.parts} parts, ${i.divisions} divisions, seam ${i.seam.name}. Offset X ${i.offsetXMm} mm, Y ${i.offsetYMm} mm. Bottom edge ${r.bottomEdgeMm.toStringAsFixed(2)} mm, top ${r.topEdgeMm.toStringAsFixed(2)} mm. Check the triangulation table and neutral-surface approximation. ${i.circleOverhangs ? "The circle overhangs the rectangle." : ""}')),
        show: ShowInModule(toolId, fields));
  }
}
