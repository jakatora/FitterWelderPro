import '../../../domain/fitter/tube_bending.dart';
import '../../../domain/fitter/tube_bending_command.dart';
import '../../core/skill.dart';
import '../../core/spoken_numbers.dart' show SpokenItem, isInchUnit;
import '../core/explain_tool_skill.dart' show explainedTool;
import '../core/skill_words.dart';
import 'quantities.dart';

const _geometryFields = {
  'angle_deg',
  'leg_a_mm',
  'leg_b_mm',
  'height_mm',
  'spread_mm',
  'segments_mm',
  'angles_deg',
  'rotations_deg'
};
const _lengthFields = {
  'clr_mm',
  'leg_a_mm',
  'leg_b_mm',
  'height_mm',
  'spread_mm',
  'min_straight_mm',
  'marker_offset_mm',
  'segments_mm'
};
const _listFields = {'segments_mm', 'angles_deg', 'rotations_deg'};
final _edit = RegExp(
    r'^(?:(?:prosze|please|hej|hey|a|and|teraz|now)\s+)*(?:zmien|ustaw|przelacz|change|set|switch)\b');
const _scalarLabels = {
  'clr': 'clr_mm',
  'promien': 'clr_mm',
  'radius': 'clr_mm',
  'kat': 'angle_deg',
  'kata': 'angle_deg',
  'angle': 'angle_deg',
  'katy': 'angles_deg',
  'angles': 'angles_deg',
  'odcinki': 'segments_mm',
  'segments': 'segments_mm',
  'obroty': 'rotations_deg',
  'rotations': 'rotations_deg',
  'wznios': 'height_mm',
  'wysokosc': 'height_mm',
  'height': 'height_mm',
  'rise': 'height_mm',
  'h': 'height_mm',
  'spread': 'spread_mm',
  'boczne': 'spread_mm',
  'dogiecie': 'springback_deg',
  'springback': 'springback_deg',
  'jednostka': 'unit',
  'jednostki': 'unit',
  'unit': 'unit',
  'units': 'unit',
};

(String, int)? _labelAt(List<SpokenItem> items, int i) {
  final w = items[i].word;
  final next = i + 1 < items.length ? items[i + 1].word : '';
  if (const {'ramie', 'ramienia', 'leg'}.contains(w) &&
      const {'a', 'b'}.contains(next)) {
    return (next == 'a' ? 'leg_a_mm' : 'leg_b_mm', 2);
  }
  if (const {'minimalna', 'minimum', 'min'}.contains(w) &&
      const {'prosta', 'straight'}.contains(next)) {
    return ('min_straight_mm', 2);
  }
  if ((w == 'marker' && next == 'offset') ||
      (w == 'przesuniecie' && next == 'znacznika')) {
    return ('marker_offset_mm', 2);
  }
  if (w == 'przesuniecie' && next == 'boczne') return ('spread_mm', 2);
  if ((w == 'wynik' && next == 'w') || (w == 'output' && next == 'in')) {
    return ('unit', 2);
  }
  if (const {'w', 'in', 'na', 'to'}.contains(w) &&
      (isInchUnit(next) || next == 'mm')) {
    return ('unit', 1);
  }
  final key = _scalarLabels[w];
  return key == null
      ? null
      : (
          key,
          key == 'unit' && const {'w', 'in', 'na', 'to'}.contains(next) ? 2 : 1
        );
}

double? _scale(String word) =>
    isInchUnit(word) ? kMmPerInch : lengthUnitScale(word);
bool _degree(String word) =>
    word.startsWith('stopn') ||
    word.startsWith('stopie') ||
    word.startsWith('degree') ||
    word == 'deg';

/// Each length has its unit, or one final unit explicitly applies to the whole
/// list. Mixed labelled/unlabelled units and spoken alternatives never guess.
List<double> _values(List<SpokenItem> items, {required bool length}) {
  final values = <double>[];
  final scales = <double?>[];
  for (var i = 0; i < items.length; i++) {
    final item = items[i];
    if (item.isNumber) {
      final value = i > 0 && items[i - 1].word == 'minus'
          ? -item.value!.abs()
          : item.value!;
      values.add(value);
      final after = i + 1 < items.length ? items[i + 1].word : '';
      scales.add(_scale(after));
      continue;
    }
    final word = item.word;
    if (_scale(word) != null) {
      if (!length || i == 0 || !items[i - 1].isNumber) return [double.nan];
    } else if (_degree(word)) {
      if (length || i == 0 || !items[i - 1].isNumber) return [double.nan];
    } else if (!const {
      'minus',
      'i',
      'and',
      'wynosi',
      'jest',
      'is',
      'of',
      'to',
      'equals',
      'na',
      'at',
      'the'
    }.contains(word)) {
      return [double.nan];
    }
  }
  if (values.isEmpty) return [double.nan];
  if (!length) return values;
  if (scales.every((s) => s != null)) {
    return [for (var i = 0; i < values.length; i++) values[i] * scales[i]!];
  }
  if (scales.last != null &&
      scales.take(scales.length - 1).every((s) => s == null)) {
    return [for (final v in values) v * scales.last!];
  }
  return [double.nan];
}

Map<String, Object?> _slots(Utterance u) {
  final items = u.items;
  final labels = <(int, String, int)>[];
  final consumed = <int>{};
  for (var i = 0; i < items.length; i++) {
    final label = _labelAt(items, i);
    if (label == null) continue;
    labels.add((i, label.$1, label.$2));
    for (var j = i; j < i + label.$2; j++) {
      consumed.add(j);
    }
    i += label.$2 - 1;
  }
  final modes = <String>{};
  // "jedno" / "one" become numeric SpokenItems; mode names are intent,
  // so identify these phrases before interpreting numeric parameters.
  if (u.hasAny(const ['jedno giecie', 'pojedyncze giecie', 'one bend'])) {
    modes.add('single');
  }
  for (var i = 0; i < items.length; i++) {
    if (consumed.contains(i)) continue;
    final w = items[i].word;
    if (w.startsWith('odsadzk') || w == 'offset') modes.add('offset');
    if (const {'single', 'jedno', 'pojedyncze'}.contains(w)) {
      modes.add('single');
    }
    if (const {'multi', 'multiple', 'wiele', 'wielokrotne'}.contains(w)) {
      modes.add('multi');
    }
  }
  final parsed = <String, Object?>{};
  for (var at = 0; at < labels.length; at++) {
    final (start, key, count) = labels[at];
    final end = at + 1 < labels.length ? labels[at + 1].$1 : items.length;
    final section = items.sublist(start + count, end);
    Object? value;
    if (key == 'unit') {
      final units = <String>{};
      var invalid = false;
      for (final item in section) {
        if (item.word == 'mm' ||
            item.word.startsWith('milimetr') ||
            item.word.startsWith('millimet')) {
          units.add('mm');
        } else if (isInchUnit(item.word) || item.word == 'inch') {
          units.add('inch');
        } else if (!const {'w', 'in', 'na', 'to'}.contains(item.word)) {
          invalid = true;
        }
      }
      value = !invalid && units.length == 1 ? units.single : null;
    } else {
      final values = _values(section, length: _lengthFields.contains(key));
      value = _listFields.contains(key)
          ? values
          : values.length == 1
              ? values.single
              : double.nan;
    }
    if (parsed.containsKey(key) && parsed[key].toString() != value.toString()) {
      parsed[key] = _listFields.contains(key) ? [double.nan] : double.nan;
    } else {
      parsed[key] = value;
    }
  }
  if (u.hasAny(const ['bez obrotow', 'no rotations'])) {
    parsed['rotations_deg'] = null;
  }
  if (u.hasAny(const ['bez dogiecia', 'no springback'])) {
    parsed['springback_deg'] = 0.0;
  }
  if (u.hasAny(const ['bez przesuniecia znacznika', 'no marker offset'])) {
    parsed['marker_offset_mm'] = 0.0;
  }
  if (u.hasAny(const ['bez sprawdzania prostej', 'no minimum straight'])) {
    parsed['min_straight_mm'] = 0.0;
  }
  final hasMode = modes.isNotEmpty;
  final inferredMulti = !hasMode &&
      u.hasStem(const ['rurk', 'rurek', 'tube', 'tubing']) &&
      (parsed.containsKey('segments_mm') || parsed.containsKey('angles_deg'));
  return {
    // Explicit mode selection starts fresh geometry while retaining the
    // bender's common settings in a continuation. Values in this turn win.
    if (hasMode || inferredMulti)
      for (final key in _geometryFields) key: null,
    if (hasMode) 'mode': modes.length == 1 ? modes.single : null,
    if (inferredMulti) 'mode': 'multi',
    ...parsed,
  };
}

bool _otherCalculation(Utterance u) =>
    mentionsWelding(u) ||
    mentionsWall(u) ||
    mentionsFitting(u) ||
    u.hasStem(const [
      'ukos',
      'bevel',
      'spad',
      'slope',
      'cisn',
      'pressure',
      'moment',
      'torque'
    ]) ||
    u.hasAny(const ['rolling offset']) &&
        !u.hasStem(const ['rurk', 'rurek', 'tube', 'tubing']);

class TubeBendingSkill extends AssistantSkill {
  @override
  String get id => 'tube.bending';
  @override
  String get toolId => 'tube_bending';
  @override
  AssistantTier get tier => AssistantTier.b;
  @override
  List<SkillExample> get examples => const [
        SkillExample(
            'Oblicz gięcie rurki jedno gięcie CLR 38 mm kąt 90 stopni ramię A 200 mm ramię B 150 mm',
            'Calculate tube bending single CLR 38 mm angle 90 degrees leg A 200 mm leg B 150 mm'),
        SkillExample(
            'Gięcie rurki odsadzka CLR 38 mm wysokość 100 mm kąt 45 stopni ramię A 200 mm ramię B 200 mm',
            'Tube bending offset CLR 38 mm height 100 mm angle 45 degrees leg A 200 mm leg B 200 mm'),
        SkillExample(
            'Gięcie rurki wiele gięć CLR 38 mm odcinki 150 mm 200 mm 250 mm kąty 90 45',
            'Tube bending multi CLR 38 mm segments 150 mm 200 mm 250 mm angles 90 45'),
        SkillExample('Oblicz gięcie rurek', 'Calculate tube bending'),
        SkillExample(
            'Gięcie rurki jedno gięcie CLR 3 cm kąt 60 stopni ramię A 20 cm ramię B 15 cm dogięcie 2 stopnie',
            'Tube bending single CLR 3 cm angle 60 degrees leg A 20 cm leg B 15 cm springback 2 degrees'),
        SkillExample(
            'Gięcie rurki odsadzka przestrzenna CLR 30 mm wznios 100 mm boczne 50 mm kąt 45 stopni ramię A 200 mm ramię B 200 mm',
            'Tube bending rolling offset CLR 30 mm rise 100 mm spread 50 mm angle 45 degrees leg A 200 mm leg B 200 mm'),
      ];
  @override
  List<SkillRejection> get rejections => const [
        SkillRejection('otwórz gięcie rurek', routesTo: 'tool.open'),
        SkillRejection(
            'rolling offset wznios 300 mm odsunięcie 400 mm kąt 45 stopni',
            routesTo: 'rolling.offset'),
        SkillRejection('oblicz kolano segmentowe', routesTo: 'mitre.bend'),
        SkillRejection('ile waży rura DN100 ścianka 3 mm',
            routesTo: 'pipe.weight'),
      ];
  @override
  SkillMatch? match(Utterance u, AssistantContext ctx) {
    if (referencesInstruction(u) ||
        explainedTool(u) != null ||
        kOpenVerbAtStartRe.hasMatch(u.folded) ||
        kCommandVerbRe.hasMatch(u.folded) ||
        mentionsWeight(u)) {
      return null;
    }
    final edit = _edit.hasMatch(u.folded);
    if (ctx.modules.activeToolId == toolId && edit && !_otherCalculation(u)) {
      final slots = _slots(u);
      if (slots.isNotEmpty) {
        return SkillMatch(this, .96,
            slots: _nativeIntent(u, ctx, slots, force: true), utterance: u);
      }
    }
    if (!u.hasStem(const ['rurk', 'rurek', 'tube', 'tubing']) ||
        !u.hasStem(const ['giec', 'gieci', 'bend', 'odsadzk', 'offset'])) {
      return null;
    }
    final slots = _slots(u);
    return SkillMatch(this, .96,
        slots: _nativeIntent(u, ctx, slots,
            force: edit && slots.keys.every((k) => k == 'unit')),
        utterance: u);
  }

  @override
  Map<String, Object?> slotsFrom(Utterance u, AssistantContext ctx) =>
      _otherCalculation(u) ? const {} : _nativeIntent(u, ctx, _slots(u));

  Map<String, Object?> _nativeIntent(
      Utterance u, AssistantContext ctx, Map<String, Object?> slots,
      {bool force = false}) {
    if (slots.isEmpty) {
      return slots;
    }
    final editing = force ||
        ctx.modules.activeToolId == toolId &&
            (_edit.hasMatch(u.folded) || u.isContinuation);
    return {
      ...slots,
      'native_edit': editing ? true : null,
      'native_edits': editing ? Map<String, Object?>.unmodifiable(slots) : null
    };
  }

  @override
  Map<String, Object?>? fillSlot(
      String slot, Utterance u, AssistantContext ctx) {
    if ((slot == 'mode' || slot == 'parameters') &&
        const {'jedno', 'jeden', 'one', 'pojedyncze'}.contains(u.folded)) {
      return slot == 'mode' ? {'mode': 'single'} : _slots(u.withRaw('single'));
    }
    final slots = _slots(u);
    if (slots.isNotEmpty) {
      if (slot == 'mode') {
        slots.removeWhere((key, value) => value == null && key != 'mode');
      }
      return _nativeIntent(u, ctx, slots);
    }
    if (_lengthFields.contains(slot) ||
        const {'angle_deg', 'springback_deg'}.contains(slot) ||
        _listFields.contains(slot)) {
      if (!u.items.any((item) => item.isNumber)) return null;
      final values = _values(u.items, length: _lengthFields.contains(slot));
      return {
        slot: _listFields.contains(slot)
            ? values
            : values.length == 1
                ? values.single
                : double.nan
      };
    }
    if (slot == 'unit') {
      return _slots(u.withRaw('units ${u.raw}'));
    }
    return null;
  }

  AskResult _ask(String key, SkillMatch m) {
    final (pl, en) = switch (key) {
      'mode' => (
          'Który tryb gięcia rurki: jedno gięcie, odsadzka czy wiele gięć?',
          'Which tube bending mode: single bend, offset or multiple bends?'
        ),
      'unit' => (
          'W jakich jednostkach pokazać i zaokrąglić wynik: mm czy cale?',
          'Which display and rounding units: mm or inches?'
        ),
      'clr_mm' => (
          'Jaki promień gięcia po osi CLR z giętarki? Podaj dodatni wymiar z jednostką, do 5000 mm.',
          'What bender centreline radius CLR? Give a positive dimension with a unit, up to 5000 mm.'
        ),
      'angle_deg' => (
          'Jaki kąt gięcia? Podaj jeden kąt większy od 0 i mniejszy od 180 stopni; w odsadzce maksymalnie 90°.',
          'What bend angle? Give one angle greater than 0 and less than 180 degrees; at most 90° for an offset.'
        ),
      'leg_a_mm' => (
          'Jakie ramię A, od początku rurki do przecięcia osi? Podaj dodatni wymiar z jednostką.',
          'What leg A, from tube start to centreline intersection? Give a positive dimension with a unit.'
        ),
      'leg_b_mm' => (
          'Jakie ramię B, od przecięcia osi do końca rurki? Podaj dodatni wymiar z jednostką.',
          'What leg B, from centreline intersection to tube end? Give a positive dimension with a unit.'
        ),
      'height_mm' => (
          'Jaki wznios H odsadzki? Podaj dodatni wymiar z jednostką; odległość między gięciami nie może przekroczyć 100000 mm.',
          'What offset height H? Give a positive dimension with a unit; travel cannot exceed 100000 mm.'
        ),
      'spread_mm' => (
          'Jakie przesunięcie boczne? Podaj wymiar z jednostką, minimum 0 mm.',
          'What lateral spread? Give a dimension with a unit, at least 0 mm.'
        ),
      'segments_mm' => (
          'Podaj odcinki do przecięć osi, np. „odcinki 150 mm 200 mm 250 mm”. Musi być o jeden odcinek więcej niż kątów, każdy dodatni i do 100000 mm.',
          'Give segments to centreline intersections, e.g. “segments 150 mm 200 mm 250 mm”. There must be one more segment than angles, each positive and up to 100000 mm.'
        ),
      'angles_deg' => (
          'Podaj listę od 1 do 12 kątów gięcia, np. „kąty 90 45”. Każdy kąt musi być większy od 0 i mniejszy od 180°.',
          'Give 1 to 12 bend angles, e.g. “angles 90 45”. Each must be greater than 0 and less than 180°.'
        ),
      'rotations_deg' => (
          'Podaj tyle obrotów, ile kątów, np. „obroty 0 180”. Pierwszy obrót musi wynosić 0; albo powiedz „bez obrotów”.',
          'Give one rotation per angle, e.g. “rotations 0 180”. The first must be 0; or say “no rotations”.'
        ),
      'min_straight_mm' => (
          'Jaka minimalna prosta wymagana przez giętarkę? Podaj wymiar z jednostką, od 0 do 100000 mm; 0 wyłącza sprawdzanie.',
          'What minimum straight does the bender require? Give 0 to 100000 mm with a unit; 0 disables the check.'
        ),
      'marker_offset_mm' => (
          'Jakie przesunięcie znacznika względem początku łuku? Podaj wymiar z jednostką od −1000 do 1000 mm.',
          'What marker offset from the start of the arc? Give −1000 to 1000 mm with a unit.'
        ),
      'springback_deg' => (
          'Jakie dogięcie na sprężynowanie? Podaj jeden kąt od 0 do 30 stopni.',
          'What springback overbend? Give one angle from 0 to 30 degrees.'
        ),
      'geometry' => (
          'Tych odcinków nie da się wygiąć: łuki nachodzą na siebie albo wychodzą poza koniec rurki. Zmień odcinki, kąt lub CLR.',
          'These segments cannot be bent: arcs overlap or extend beyond the tube end. Change the segments, angle or CLR.'
        ),
      _ => (
          'Te pola nie pasują do wybranego trybu. Wybierz ponownie tryb i podaj jego wymiary.',
          'These fields do not belong to the selected mode. Select the mode again and give its dimensions.'
        ),
    };
    return AskResult(key, AssistantText(pl, en),
        partial: m,
        choices: key == 'mode' || key == 'parameters'
            ? const [
                FollowUp(
                    AssistantText('Jedno gięcie', 'Single bend'), 'single'),
                FollowUp(AssistantText('Odsadzka', 'Offset'), 'offset'),
                FollowUp(
                    AssistantText('Wiele gięć', 'Multiple bends'), 'multi'),
              ]
            : const []);
  }

  @override
  Future<SkillResult> run(SkillMatch m, AssistantContext ctx) async {
    if (m.slots['native_edit'] == true) {
      final payload = m.slots['native_edits'];
      final edits =
          payload is Map<String, Object?> ? payload : <String, Object?>{};
      if (edits.length == 1 && edits.containsKey('unit')) {
        final unit = edits['unit'];
        if (unit != 'mm' && unit != 'inch') return _ask('unit', m);
        return AnswerResult(
            AssistantAnswer(
                text: AssistantText(
                    'Wyświetlanie i zaokrąglanie ustawione na ${unit == 'inch' ? 'cale' : 'milimetry'}. Wymiary rurki pozostają bez zmian.',
                    'Display and rounding set to ${unit == 'inch' ? 'inches' : 'millimetres'}. Tube dimensions remain unchanged.')),
            show: ShowInModule(toolId, {'unit': unit}));
      }
      final modules = ctx.modules;
      final current = modules is FieldModuleContext
          ? (modules as FieldModuleContext).inputFields(toolId)
          : null;
      if (current == null) {
        return const FailedResult(
            AssistantText(
                'Nie mogę odczytać bieżących pól gięcia rurki. Otwórz ten moduł i poczekaj na wczytanie ustawień.',
                'I cannot read the current tube bending fields. Open that module and wait for its settings to load.'),
            reportMissingCapability: false);
      }
      // Use actual visible inputs once, then keep this partial while asking.
      // A later answer must not re-read and replace an unresolved edit.
      m = m.copyWith(slots: {...current, ...edits});
    }
    final s = m.slots;
    final mode = s['mode'];
    if (!const {'single', 'offset', 'multi'}.contains(mode)) {
      return _ask('mode', m);
    }
    final required = {
      'mode',
      'unit',
      'clr_mm',
      'min_straight_mm',
      'marker_offset_mm',
      'springback_deg',
      if (mode != 'multi') ...['angle_deg', 'leg_a_mm', 'leg_b_mm'],
      if (mode == 'offset') ...['height_mm', 'spread_mm'],
      if (mode == 'multi') ...['segments_mm', 'angles_deg', 'rotations_deg'],
    };
    if (s.entries.any((e) => e.value != null && !required.contains(e.key))) {
      return _ask('parameters', m);
    }
    final fields = <String, Object?>{
      'unit': 'mm',
      'min_straight_mm': 0.0,
      'marker_offset_mm': 0.0,
      'springback_deg': 0.0,
      if (mode == 'offset') 'spread_mm': 0.0,
      for (final key in required)
        if (s.containsKey(key) && s[key] != null) key: s[key],
    };
    if (s.containsKey('unit') && s['unit'] == null) return _ask('unit', m);
    if (mode == 'multi' &&
        fields['rotations_deg'] == null &&
        fields['angles_deg'] is List) {
      fields['rotations_deg'] =
          List<double>.filled((fields['angles_deg'] as List).length, 0);
    }
    final TubeBendingCommand command;
    try {
      command = TubeBendingCommand.fromFields(fields);
    } on FormatException catch (e) {
      return _ask(e.message, m);
    }
    final run = command.run;
    final inch = command.unit == TubeUnit.inch;
    String length(double mm) =>
        inch ? formatInchFraction(mm / kMmPerInch) : '${fmt(mm, ctx.lang)} mm';
    final lines = <AnswerLine>[
      for (final bend in run.bends)
        AnswerLine(
            AssistantText('Gięcie ${bend.number}: znacznik / kąt giętarki',
                'Bend ${bend.number}: mark / bender angle'),
            '${length(roundMarkMm(bend.markMm, command.unit))} / ${fmt(bend.bendToDeg, ctx.lang)}°'),
      if (command.offset case final offset?)
        AnswerLine(
            const AssistantText(
                'Obrót odsadzki od pionu', 'Offset roll from vertical'),
            '${fmt(offset.rollFromVerticalDeg, ctx.lang)}°'),
      for (final warning in run.warnings)
        AnswerLine(
            const AssistantText('Uwaga', 'Warning'), _warning(warning, ctx)),
      AnswerLine(
          const AssistantText('Ustawienia giętarki', 'Bender settings'),
          AssistantText(
                  'CLR ${fmt(run.input.clrMm, ctx.lang)} mm; min ${fmt(run.input.minStraightMm, ctx.lang)} mm; znacznik ${fmt(run.input.markerOffsetMm, ctx.lang)} mm; dogięcie ${fmt(run.input.springbackDeg, ctx.lang)}°',
                  'CLR ${fmt(run.input.clrMm, ctx.lang)} mm; min ${fmt(run.input.minStraightMm, ctx.lang)} mm; marker ${fmt(run.input.markerOffsetMm, ctx.lang)} mm; springback ${fmt(run.input.springbackDeg, ctx.lang)}°')
              .of(ctx.lang)),
    ];
    return AnswerResult(
        AssistantAnswer(
            text: AssistantText(
                'Utnij ${length(run.cutLengthMm(command.unit))}. Odcinki mierzone do przecięć osi; znaczniki liczone od początku rurki. Zaokrąglenie cięcia w górę: ${inch ? '1/32 cala' : '0,5 mm'}. Niepodane korekty wynoszą 0. Minimum 0 wyłącza sprawdzanie uchwytu; przesunięcie 0 oznacza początek łuku.',
                'Cut ${length(run.cutLengthMm(command.unit))}. Segments are measured to centreline intersections; marks are from the tube start. Cut rounded up to ${inch ? '1/32 inch' : '0.5 mm'}. Unspecified corrections are 0. Minimum 0 disables the grip check; marker offset 0 means arc start.'),
            lines: lines),
        show: ShowInModule(toolId, command.fields));
  }
}

String _warning(TubeBendWarning w, AssistantContext ctx) {
  final actual = fmt(w.straightMm, ctx.lang),
      required = fmt(w.requiredMm, ctx.lang);
  return (switch (w.kind) {
    TubeBendWarningKind.straightTooShort ||
    TubeBendWarningKind.endStraightTooShort =>
      AssistantText(
          'Odcinek ${w.index}: prosta $actual mm, wymagana $required mm.',
          'Segment ${w.index}: straight $actual mm, required $required mm.'),
    TubeBendWarningKind.markOutsideTube => AssistantText(
        'Znacznik ${w.index} wypada poza rurką: $actual mm. Sprawdź przesunięcie z instrukcji giętarki.',
        'Mark ${w.index} is outside the tube: $actual mm. Check the bender manual marker offset.'),
    _ => const AssistantText('Geometria niemożliwa.', 'Impossible geometry.'),
  })
      .of(ctx.lang);
}
