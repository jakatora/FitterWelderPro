import '../../../utils/decimal_parse.dart';
import '../../../data/elbow_takeouts.dart';
import '../../../domain/fitter/pipe_route.dart';
import '../../core/skill.dart';
import '../../core/spoken_numbers.dart' show SpokenItem, isInchUnit;
import '../core/explain_tool_skill.dart' show explainedTool;
import '../core/skill_words.dart';
import 'quantities.dart';

final _edit = RegExp(
    r'^(?:(?:a|and|prosze|please|teraz|now)\s+)*(?:zmien|ustaw|change|set)\b');
const _recalculate = {
  'oblicz',
  'policz',
  'przelicz',
  'calculate',
  'recalculate',
  'oblicz to',
  'oblicz aktualna trase',
  'oblicz aktualna trase rur',
  'oblicz biezaca trase',
  'przelicz aktualna trase',
  'calculate current route',
  'calculate current pipe route',
  'recalculate route'
};
final _clear =
    RegExp(r'^(?:(?:prosze|please)\s+)*(?:wyczysc|wyzeruj|clear|reset)\b');
(String, int)? _label(List<SpokenItem> items, int i) {
  final w = items[i].word, next = i + 1 < items.length ? items[i + 1].word : '';
  if (w == 'h1' || w == 'h2') return ('${w}_mm', 1);
  if (const {'h', 'ha', 'height'}.contains(w) &&
      i + 1 < items.length &&
      items[i + 1].isNumber &&
      (items[i + 1].value == 1 || items[i + 1].value == 2)) {
    return (items[i + 1].value == 1 ? 'h1_mm' : 'h2_mm', 2);
  }
  if (const {'x', 'y', 'r', 'g'}.contains(w)) {
    return ('${w == 'g' ? 'gap' : w}_mm', 1);
  }
  if (w.startsWith('szczelin') || w == 'gap') return ('gap_mm', 1);
  if (RegExp(r'^(?:lr|sr)(?:[0-9]+)?$').hasMatch(w) ||
      RegExp(r'^\d+(?:\.\d+)?d(?:[0-9]+)?$').hasMatch(w)) {
    return ('radius_kind', 1);
  }
  if ((w == 'short' || w == 'long') && next == 'radius' ||
      (w.startsWith('krotk') || w.startsWith('dlug')) &&
          next.startsWith('promien')) {
    return ('radius_kind', 2);
  }
  if (const {'takeout', 'promien', 'radius'}.contains(w)) return ('r_mm', 1);
  if (w == 'dn' || RegExp(r'^dn[0-9]').hasMatch(w)) return ('dn', 1);
  if (w == 'de' && next == 'en' || w == 'd' && next == 'n') return ('dn', 2);
  if ((w == 'spoiny' && next == 'koncowe') || (w == 'end' && next == 'welds')) {
    return ('end_welds', 2);
  }
  if (i + 2 < items.length) {
    final third = items[i + 2].word;
    if (w == 'bez' && next == 'spoin' && third == 'koncowych' ||
        w == 'without' && next == 'end' && third == 'welds') {
      return ('end_off', 3);
    }
    if (w == 'ze' && next == 'spoinami' && third == 'koncowymi' ||
        w == 'with' && next == 'end' && third == 'welds') {
      return ('end_on', 3);
    }
  }
  if (w == 'bez' && next == 'szczeliny' || w == 'no' && next == 'gap') {
    return ('gap_zero', 2);
  }
  return null;
}

double _dimension(List<SpokenItem> items) {
  final values = <double>[];
  for (var i = 0; i < items.length; i++) {
    final item = items[i];
    if (item.isNumber) {
      final unit = i + 1 < items.length ? items[i + 1].word : '';
      final scale = isInchUnit(unit) ? 25.4 : lengthUnitScale(unit);
      if (scale == null) return double.nan;
      values.add((i > 0 && items[i - 1].word == 'minus'
              ? -item.value!.abs()
              : item.value!) *
          scale);
    } else if (lengthUnitScale(item.word) == null &&
        !isInchUnit(item.word) &&
        !const {'minus', 'na', 'to', 'is', 'jest', 'wynosi', 'equals'}
            .contains(item.word)) {
      return double.nan;
    }
  }
  return values.length == 1 ? values.single : double.nan;
}

bool? _bool(Utterance u) {
  if (const {
    'tak',
    'yes',
    'true',
    'with',
    'ze spoinami koncowymi',
    'with end welds'
  }.contains(u.folded)) {
    return true;
  }
  if (const {
    'nie',
    'no',
    'false',
    'without',
    'bez spoin koncowych',
    'without end welds'
  }.contains(u.folded)) {
    return false;
  }
  return null;
}

String? _shape(Utterance u) {
  if (u.hasStem(
      const ['segmentow', 'segmented', 'mitre', 'miter', 'gored', 'lobster'])) {
    return 'unsupported';
  }
  if (RegExp(r'\b(?:lr|sr|\d+(?:\.\d+)?d)(\d+)\b')
      .allMatches(u.folded)
      .any((m) => m[1] != '90')) {
    return 'unsupported';
  }
  final angles = <double>{}, counts = <double>{};
  final degreeValues = <double>{
    for (final m in RegExp(r'(-?\d+(?:[.,]\d+)?)\s*°').allMatches(u.raw))
      (parseDecimal(m[1]!) ?? double.nan)
  };
  var dimension = false, angleContext = false, angleLabel = false;
  for (var i = 0; i < u.items.length; i++) {
    final item = u.items[i], w = item.word;
    final label = _label(u.items, i);
    if (label != null) {
      dimension = !const {'end_on', 'end_off', 'end_welds'}.contains(label.$1);
      angleContext = false;
      i += label.$2 - 1;
      continue;
    }
    if (w == 'kat' ||
        w == 'kata' ||
        w == 'angle' ||
        w.startsWith('kolan') ||
        w.startsWith('elbow')) {
      dimension = false;
      angleContext = true;
      if (w == 'kat' || w == 'kata' || w == 'angle') {
        angleLabel = true;
      }
      continue;
    }
    if (!item.isNumber || dimension) continue;
    final next = i + 1 < u.items.length ? u.items[i + 1].word : '';
    final number = signedQuantity(u, i);
    if (next.startsWith('kolan') || next.startsWith('elbow')) {
      if (number == 90) {
        angles.add(number);
      } else {
        counts.add(number);
      }
    } else if (angleContext ||
        next.startsWith('stopn') ||
        next.startsWith('degree') ||
        degreeValues.contains(number)) {
      angles.add(number);
    }
  }
  if (counts.any((c) => c != 2)) {
    return u.hasAny(const ['albo', 'lub', 'or']) ? 'ambiguous' : 'unsupported';
  }
  if (angles.length > 1) {
    return 'ambiguous';
  }
  if (angles.isNotEmpty) {
    return angles.single == 90 ? 'valid' : 'unsupported';
  }
  if (angleLabel) {
    return 'ambiguous';
  }
  return null;
}

Map<String, Object?> _slots(Utterance u) {
  final items = u.items, labels = <(int, String, int)>[];
  for (var i = 0; i < items.length; i++) {
    final label = _label(items, i);
    if (label == null) continue;
    labels.add((i, label.$1, label.$2));
    i += label.$2 - 1;
  }
  final s = <String, Object?>{};
  if (_shape(u) case final shape?) s['route_shape'] = shape;
  for (var at = 0; at < labels.length; at++) {
    final (start, key, count) = labels[at];
    if (key == 'dn' || key == 'radius_kind') continue;
    final end = at + 1 < labels.length ? labels[at + 1].$1 : items.length;
    final section = items.sublist(start + count, end);
    final target = key == 'end_on' || key == 'end_off'
        ? 'end_welds'
        : key == 'gap_zero'
            ? 'gap_mm'
            : key;
    Object? value;
    if (key == 'end_on' || key == 'end_off') {
      value = key == 'end_on';
    } else if (key == 'gap_zero') {
      value = 0.0;
    } else if (key == 'end_welds') {
      value = _bool(u.withRaw(section.map((x) => x.text).join(' ')));
    } else {
      value = _dimension(section);
    }
    if (s.containsKey(target) && s[target] != value) {
      s[target] = target == 'end_welds' ? null : double.nan;
    } else {
      s[target] = value;
    }
  }
  final explicitR = s.containsKey('r_mm');
  if (explicitR) {
    s['dn'] = null;
    s['requested_dn'] = null;
    s['radius_kind'] = null;
  }
  if (u.mentionsDn) {
    s['requested_dn'] = u.dn() ?? double.nan;
    s['dn'] = u.dn();
    if (!explicitR) s['r_mm'] = null;
  }
  final kinds = <String>{};
  if ((u.hasAny(const ['lr', 'long radius']) ||
          RegExp(r'\blr[0-9]+\b').hasMatch(u.folded)) ||
      RegExp(r'\bdlug\w*\s+promien\w*\b').hasMatch(u.folded)) {
    kinds.add('LR');
  }
  if ((u.hasAny(const ['sr', 'short radius', '1d']) ||
          RegExp(r'\bsr[0-9]+\b').hasMatch(u.folded)) ||
      RegExp(r'\bkrotk\w*\s+promien\w*\b').hasMatch(u.folded)) {
    kinds.add('SR');
  }
  for (final m
      in RegExp(r'\b(\d+(?:\.\d+)?)d(?:[0-9]+)?\b').allMatches(u.folded)) {
    kinds.add(switch (m[1]) {
      '1' => 'SR',
      '1.5' => 'LR',
      '3' => '3D',
      _ => 'unsupported'
    });
  }
  if (kinds.isNotEmpty) {
    s['radius_kind'] = kinds.length == 1 ? kinds.single : 'ambiguous';
    if (!explicitR) s['r_mm'] = null;
  }
  return s;
}

class PipeRouteSkill extends AssistantSkill {
  @override
  String get id => 'pipe.route';
  @override
  String get toolId => 'pipe_route';
  @override
  AssistantTier get tier => AssistantTier.b;
  @override
  List<SkillExample> get examples => const [
        SkillExample(
            'Oblicz trasę rur H1 2000 mm H2 500 mm X 1000 mm Y 800 mm DN100 szczelina 3 mm bez spoin końcowych',
            'Calculate pipe route H1 2000 mm H2 500 mm X 1000 mm Y 800 mm DN100 gap 3 mm without end welds'),
        SkillExample(
            'Trasa rur H1 2000 mm H2 500 mm X 1000 mm Y 800 mm R 152 mm szczelina 3 mm ze spoinami końcowymi',
            'Pipe route H1 2000 mm H2 500 mm X 1000 mm Y 800 mm R 152 mm gap 3 mm with end welds'),
        SkillExample('Oblicz trasę rur', 'Calculate pipe route'),
        SkillExample('Wyczyść trasę rur', 'Clear pipe route'),
        SkillExample(
            'Trasa rur H1 2 m H2 50 cm X 1 m Y 80 cm R 152 mm bez szczeliny bez spoin końcowych',
            'Pipe route H1 2 meters H2 50 cm X 1 meter Y 80 cm R 152 mm no gap without end welds'),
        SkillExample(
            'Trasa rur H1 minus 500 mm H2 minus 2000 mm X 1000 mm Y 800 mm DN100 szczelina 2 mm spoiny końcowe nie',
            'Pipe route H1 minus 500 mm H2 minus 2000 mm X 1000 mm Y 800 mm DN100 gap 2 mm end welds no'),
        SkillExample(
            'Trasa rur H1 2000 mm H2 500 mm X 1000 mm Y 800 mm R 0 mm bez szczeliny bez spoin końcowych',
            'Pipe route H1 2000 mm H2 500 mm X 1000 mm Y 800 mm R 0 mm no gap without end welds'),
        SkillExample(
            'Trasa rur H1 2000 mm H2 500 mm X 1000 mm Y 800 mm DN100 SR szczelina 3 mm bez spoin końcowych',
            'Pipe route H1 2000 mm H2 500 mm X 1000 mm Y 800 mm DN100 SR gap 3 mm without end welds'),
        SkillExample(
            'Trasa rur H1 2000 mm H2 500 mm X 1000 mm Y 800 mm DN100 3D szczelina 3 mm bez spoin końcowych',
            'Pipe route H1 2000 mm H2 500 mm X 1000 mm Y 800 mm DN100 3D gap 3 mm without end welds'),
      ];
  @override
  List<SkillRejection> get rejections => const [
        SkillRejection('otwórz trasę rur', routesTo: 'tool.open'),
        SkillRejection('oblicz spadek rury 1% na 6 metrów',
            routesTo: 'pipe.slope'),
        SkillRejection('narysuj rura metr w prawo kolano w górę rura metr',
            routesTo: 'iso.draw'),
        SkillRejection(
            'rolling offset wznios 300 mm odsunięcie 400 mm kąt 45 stopni',
            routesTo: 'rolling.offset'),
      ];
  bool _foreign(Utterance u) =>
      u.hasStem(const [
        'spad',
        'slope',
        'rolling',
        'ukos',
        'fazow',
        'bevel',
        'giet',
        'bend'
      ]) ||
      mentionsWeight(u);
  @override
  SkillMatch? match(Utterance u, AssistantContext ctx) {
    final topic =
        u.hasStem(const ['tras', 'route']) && u.hasStem(const ['rur', 'pipe']);
    if (referencesInstruction(u) ||
        explainedTool(u) != null ||
        kOpenVerbAtStartRe.hasMatch(u.folded) ||
        kCommandVerbRe.hasMatch(u.folded) ||
        _foreign(u) && !(topic && _shape(u) == 'unsupported')) {
      return null;
    }
    if (_clear.hasMatch(u.folded) &&
        (topic || ctx.modules.activeToolId == toolId)) {
      return SkillMatch(this, .96,
          slots: const {'native_action': 'clear'}, utterance: u);
    }
    if (ctx.modules.activeToolId == toolId && _recalculate.contains(u.folded)) {
      return SkillMatch(this, .96,
          slots: const {'native_edit': <String, Object?>{}}, utterance: u);
    }
    final edit = _edit.hasMatch(u.folded);
    if (!topic && !(ctx.modules.activeToolId == toolId && edit)) return null;
    final s = _slots(u);
    if (ctx.modules.activeToolId == toolId &&
        topic &&
        s.isEmpty &&
        u.hasStem(const [
          'oblicz',
          'policz',
          'przelicz',
          'calculate',
          'recalculate'
        ])) {
      return SkillMatch(this, .96,
          slots: const {'native_edit': <String, Object?>{}}, utterance: u);
    }
    if (ctx.modules.activeToolId == toolId && edit && s.isNotEmpty) {
      return SkillMatch(this, .96,
          slots: _intent(u, ctx, s, force: true), utterance: u);
    }
    if (!(u.hasStem(const ['tras', 'route']) &&
        u.hasStem(const ['rur', 'pipe']))) {
      return null;
    }
    return SkillMatch(this, .96, slots: s, utterance: u);
  }

  Map<String, Object?> _intent(
      Utterance u, AssistantContext ctx, Map<String, Object?> s,
      {bool force = false}) {
    if (s.isEmpty) return s;
    final editing = force ||
        ctx.modules.activeToolId == toolId &&
            (u.isContinuation || _edit.hasMatch(u.folded));
    return {
      ...s,
      'native_action': null,
      'native_edit': editing ? Map<String, Object?>.unmodifiable(s) : null
    };
  }

  @override
  Map<String, Object?> slotsFrom(Utterance u, AssistantContext ctx) =>
      _foreign(u) ? const {} : _intent(u, ctx, _slots(u));
  @override
  Map<String, Object?>? fillSlot(
      String slot, Utterance u, AssistantContext ctx) {
    final s = _slots(u);
    if (s.isNotEmpty) return _intent(u, ctx, s);
    if (slot == 'shape' && u.items.length == 1 && u.items.single.isNumber) {
      return {
        'route_shape': u.items.single.value == 90 ? 'valid' : 'unsupported'
      };
    }
    if (slot == 'end_welds') {
      final b = _bool(u);
      return b == null ? null : {slot: b};
    }
    if (const {'h1_mm', 'h2_mm', 'x_mm', 'y_mm', 'r_mm', 'gap_mm'}
            .contains(slot) &&
        u.items.any((i) => i.isNumber)) {
      return {
        slot: _dimension(u.items),
        if (slot == 'r_mm') ...{
          'dn': null,
          'requested_dn': null,
          'radius_kind': null
        }
      };
    }
    return null;
  }

  AskResult _ask(String key, SkillMatch m) {
    final (pl, en) = switch (key) {
      'shape' => (
          'Ten kalkulator liczy trasę na dokładnie dwóch kolanach 90°. Potwierdź kąt 90° albo podaj inny rodzaj trasy.',
          'This calculator handles exactly two 90° elbows. Confirm 90° or specify a different route type.'
        ),
      'h1_mm' => (
          'Podaj H1, wysokość startu, z jednostką. Zero i ujemne wysokości są dozwolone.',
          'Give H1, start height, with a unit. Zero and negative datum heights are allowed.'
        ),
      'h2_mm' => (
          'Podaj H2, wysokość końca, z jednostką.',
          'Give H2, end height, with a unit.'
        ),
      'heights' => (
          'Podaj różne H1 i H2 z jednostkami. Równe wysokości nie tworzą tej trasy na dwóch kolanach 90°.',
          'Give different H1 and H2 with units. Equal heights do not form this two-90°-elbow route.'
        ),
      'x_mm' => (
          'Jaki bieg poziomy X? Podaj dodatni wymiar z jednostką.',
          'What horizontal run X? Give a positive dimension with a unit.'
        ),
      'y_mm' => (
          'Jaki bieg poziomy Y? Podaj dodatni wymiar z jednostką.',
          'What horizontal run Y? Give a positive dimension with a unit.'
        ),
      'r_mm' => (
          'Podaj take-out R kolana 90° z jednostką albo jedno DN i rodzaj LR, SR lub 3D z tabeli ASME B16.9 (bez rodzaju: LR). Dla wariantu bez danych tabelarycznych podaj rzeczywiste R. R = 0 to tylko C-C, nie gotowe długości do cięcia.',
          'Give the 90° elbow take-out R with a unit or one DN and LR, SR or 3D type from the ASME B16.9 table (unspecified type: LR). For a missing table entry give the actual R. R = 0 is C-C only, not ready-to-cut lengths.'
        ),
      'gap_mm' => (
          'Jaka szczelina spoiny g? Podaj wymiar z jednostką, minimum 0 mm.',
          'What weld root gap g? Give a dimension with a unit, at least 0 mm.'
        ),
      'end_welds' => (
          'Czy X i Y są mierzone do czół przyspawanych elementów, ze spoinami także na obu końcach trasy? Wybierz tak lub nie.',
          'Are X and Y measured to faces of welded-on parts, with welds at both route ends too? Choose yes or no.'
        ),
      _ => (
          'Te wymiary nie mieszczą kolan i szczelin albo wynik jest poza zakresem. Popraw H1, H2, X, Y lub R.',
          'These dimensions cannot accommodate the elbows and gaps, or the result is out of range. Correct H1, H2, X, Y or R.'
        ),
    };
    return AskResult(key, AssistantText(pl, en),
        partial: m,
        choices: key == 'end_welds'
            ? const [
                FollowUp(AssistantText('Tak, oba końce', 'Yes, both ends'),
                    'with end welds'),
                FollowUp(AssistantText('Nie, tylko kolana', 'No, elbows only'),
                    'without end welds'),
              ]
            : const []);
  }

  @override
  Future<SkillResult> run(SkillMatch m, AssistantContext ctx) async {
    if (m.slots['native_action'] == 'clear') {
      return const AnswerResult(
          AssistantAnswer(
              text: AssistantText(
                  'Wyczyszczono pola i wynik kalkulatora trasy.',
                  'Route calculator inputs and result cleared.')),
          show: ShowInModule('pipe_route', {'action': 'clear'}));
    }

    if (m.slots['route_shape'] == 'unsupported') {
      return const FailedResult(
          AssistantText(
              'Ten kalkulator obsługuje dokładnie dwa kolana 90°. Nie zmieniłem trasy; inna liczba kolan, inny kąt lub kolano segmentowe wymaga innego modelu obliczeń.',
              'This calculator supports exactly two 90° elbows. Route unchanged; other elbow counts, angles or mitred bends require a different calculation model.'),
          reportMissingCapability: true);
    }
    if (m.slots['route_shape'] == 'ambiguous') return _ask('shape', m);
    final edits = m.slots['native_edit'];
    if (edits is Map<String, Object?>) {
      final modules = ctx.modules;
      final current = modules is FieldModuleContext
          ? (modules as FieldModuleContext).inputFields(toolId)
          : null;
      if (current == null) {
        return const FailedResult(
            AssistantText(
                'Nie mogę odczytać bieżącej trasy. Otwórz moduł i poczekaj na jego wczytanie.',
                'I cannot read the current route. Open the module and wait for it to load.'),
            reportMissingCapability: false);
      }
      m = m.copyWith(slots: {...current, ...edits});
    }
    final fields = {
      for (final key in PipeRouteInput.keys)
        if (m.slots.containsKey(key)) key: m.slots[key]
    };
    AssistantText? source;
    final nominal = m.slots.containsKey('requested_dn')
        ? m.slots['requested_dn']
        : m.slots['dn'];
    if (nominal != null) {
      if (nominal is! int) return _ask('r_mm', m);
      final kind = m.slots['radius_kind'] ?? 'LR';
      final row = elbowTakeoutForDn(nominal);
      final takeout = switch (kind) {
        'LR' => row?.lr90,
        'SR' => row?.sr90,
        '3D' => row?.r3d90,
        _ => null
      };
      final explicit = fields['r_mm'];
      if (takeout == null || explicit != null && explicit != takeout) {
        return _ask('r_mm', m);
      }
      fields['r_mm'] = takeout;
      // The native DN picker represents LR only. Other standard take-outs use
      // its custom-R field, never a misleading LR badge.
      fields['dn'] = kind == 'LR' ? nominal : null;
      source = AssistantText.same('ASME B16.9-2018, $kind 90°, A');
    }
    final PipeRouteInput input;
    try {
      input = PipeRouteInput.fromFields(fields);
    } on FormatException catch (e) {
      return _ask(e.message, m);
    }
    final r = input.result, cc = (input.fields['r_mm'] as num) == 0;
    String mm(double v) => '${fmt(v, ctx.lang)} mm';
    return AnswerResult(
        AssistantAnswer(
            text: AssistantText(
                cc
                    ? 'R = 0: wynik C-C, nie długości rur do cięcia. Uwzględnij rzeczywiste kolana przed cięciem.'
                    : 'Trasa na dwóch kolanach 90°. Rury do cięcia: ${mm(r.seg1)}, ${mm(r.seg2)}, ${mm(r.seg3)}. Suma prostych ${mm(r.total)}.',
                cc
                    ? 'R = 0: C-C result, not pipe cut lengths. Allow for actual elbows before cutting.'
                    : 'Route with two 90° elbows. Pipe cut lengths: ${mm(r.seg1)}, ${mm(r.seg2)}, ${mm(r.seg3)}. Straight total ${mm(r.total)}.'),
            source: source,
            lines: [
              AnswerLine(
                  const AssistantText(
                      'Kolana / spoiny ze szczeliną', 'Elbows / gapped welds'),
                  '${r.elbowCount} / ${r.weldCount}'),
              AnswerLine(
                  const AssistantText(
                      'Długość rozwinięta osi z kolanami i szczelinami',
                      'Developed centreline length including elbows and gaps'),
                  mm(r.developedMm)),
              AnswerLine(
                  const AssistantText(
                      'Take-out R / szczelina g', 'Take-out R / gap g'),
                  '${mm((input.fields['r_mm'] as num).toDouble())} / ${mm((input.fields['gap_mm'] as num).toDouble())}'),
            ]),
        show: ShowInModule(toolId, input.fields));
  }
}
