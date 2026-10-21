import '../../../domain/fitter/rolling_offset.dart';
import '../../../services/takeout_catalog.dart' show TakeoutBasis;
import '../../core/skill.dart';
import '../core/skill_words.dart';
import '../core/explain_tool_skill.dart' show explainedTool;
import 'quantities.dart';

const _rise = ['rise', 'wznios', 'wysokosc'];
const _spread = ['spread', 'odsunieci', 'przesunieci', 'rozsunieci'];
const _gap = ['szczelin', 'gap'];
final _unsupportedFamily = RegExp(r'^(?:sr|3d)\d*$');
final _suffixAngle = RegExp(r'^(?:lr|sr|3d)(\d+)$');
final _edit = RegExp(
    r'^(?:(?:a|and|prosze|please|teraz|now)\s+)*(?:zmien|ustaw|change|set)\b');
final _clear = RegExp(
    r'^(?:(?:prosze|please)\s+)*(?:wyczysc|wyzeruj|clear|reset)(?:\s+rolling\s+offset)?$');
const _recalculate = {
  'oblicz',
  'policz',
  'przelicz',
  'calculate',
  'recalculate',
  'oblicz aktualny rolling offset',
  'calculate current rolling offset'
};
bool _foreign(Utterance u) =>
    u.hasStem(const [
      'rurk',
      'rurek',
      'tube',
      'tubing',
      'spad',
      'slope',
      'ukos',
      'bevel',
      'tras',
      'route',
      'narys',
      'draw'
    ]) ||
    u.hasAny(const ['gietarka', 'bender']) ||
    mentionsWeight(u);
Map<String, Object?> _slots(Utterance u) {
  final result = <String, Object?>{};
  for (final (key, labels) in [
    ('rise_mm', _rise),
    ('spread_mm', _spread),
    ('gap_mm', _gap)
  ]) {
    final n = lengthNear(u, labels);
    if (n != null || u.hasStem(labels)) result[key] = n ?? double.nan;
  }
  final angle = angleValue(u);
  if (angle != null || u.hasStem(const ['kat', 'angle'])) {
    result['angle_deg'] = angle ?? double.nan;
  }
  final attachedAngles = <double>{};
  for (final item in u.items) {
    final match = _suffixAngle.firstMatch(item.word);
    if (match != null) attachedAngles.add(double.parse(match[1]!));
  }
  if (attachedAngles.isNotEmpty) {
    if (attachedAngles.length != 1 ||
        angle != null && angle != attachedAngles.single) {
      result['angle_deg'] = double.nan;
    } else {
      result['angle_deg'] = attachedAngles.single;
    }
  }
  if (u.mentionsDn) result['dn'] = u.dn() ?? double.nan;
  if (u.hasAny(const ['bez szczeliny', 'no gap'])) result['gap_mm'] = 0.0;
  if (u.hasAny(const ['tylko geometria', 'geometry only'])) {
    result.addAll({'dn': null, 'gap_mm': null, 'cut_requested': false});
  } else if (u.mentionsDn ||
      result.containsKey('gap_mm') ||
      u.hasStem(const ['ciecia']) ||
      u.hasAny(const ['cut length', 'pipe cut'])) {
    result['cut_requested'] = true;
  }
  final customRadius = lengthNear(u, const ['r', 'promien', 'radius']);
  if (customRadius != null &&
      !u.hasAny(const ['tylko geometria', 'geometry only'])) {
    result['cut_requested'] = true;
  }
  if (customRadius != null ||
      u.items.any((i) => _unsupportedFamily.hasMatch(i.word)) ||
      u.hasAny(const ['short radius', 'krotki promien']) ||
      u.hasStem(const ['segmentow', 'mitred', 'mitered'])) {
    result['radius_model'] = 'unsupported';
  } else if (u.hasAny(const ['lr', 'long radius'])) {
    result['radius_model'] = 'LR';
  }
  return result;
}

class RollingOffsetSkill extends AssistantSkill {
  @override
  String get id => 'rolling.offset';
  @override
  String get toolId => 'rolling_offset';
  @override
  AssistantTier get tier => AssistantTier.b;
  @override
  List<SkillExample> get examples => const [
        SkillExample(
            'Rolling offset wznios 300 mm odsunięcie 400 mm kąt 45 stopni',
            'Rolling offset rise 300 mm spread 400 mm angle 45 degrees'),
        SkillExample('Oblicz rolling offset', 'Calculate rolling offset'),
        SkillExample(
            'Rolling offset wznios 300 mm odsunięcie 400 mm kąt 45 stopni DN100 LR szczelina 3 mm',
            'Rolling offset rise 300 mm spread 400 mm angle 45 degrees DN100 LR gap 3 mm'),
        SkillExample(
            'Rolling offset wznios 500 mm odsunięcie 500 mm kąt 90 stopni DN50 szczelina 0 mm',
            'Rolling offset rise 500 mm spread 500 mm angle 90 degrees DN50 gap 0 mm'),
        SkillExample(
            'Rolling offset wznios 30 cm odsunięcie 40 cm kąt 30 stopni',
            'Rolling offset rise 30 cm spread 40 cm angle 30 degrees'),
        SkillExample(
            'Rolling offset wznios 1 metr odsunięcie 2 metry kąt 60 stopni',
            'Rolling offset rise 1 meter spread 2 meters angle 60 degrees'),
        SkillExample(
            'Rolling offset wznios 300 mm odsunięcie 400 mm kąt 90 stopni',
            'Rolling offset rise 300 mm spread 400 mm angle 90 degrees'),
        SkillExample('Rolling offset wznios 150 mm odsunięcie 200 mm',
            'Rolling offset rise 150 mm spread 200 mm'),
      ];
  @override
  List<SkillRejection> get rejections => const [
        SkillRejection('otwórz rolling offset', routesTo: 'tool.open'),
        SkillRejection('spadek rury 1% na 6 metrów', routesTo: 'pipe.slope'),
        SkillRejection('narysuj rurę 300 mm i skręć 45 stopni'),
        SkillRejection('dodaj spoinę 45'),
      ];
  Map<String, Object?> _intent(
      Utterance u, AssistantContext ctx, Map<String, Object?> s,
      {bool continuation = false}) {
    if (s.isEmpty) return s;
    return {
      ...s,
      'native_action': null,
      'native_edit': ctx.modules.activeToolId == toolId &&
              (continuation || u.isContinuation || _edit.hasMatch(u.folded))
          ? Map<String, Object?>.unmodifiable(s)
          : null
    };
  }

  @override
  SkillMatch? match(Utterance u, AssistantContext ctx) {
    if (referencesInstruction(u) ||
        explainedTool(u) != null ||
        _foreign(u) ||
        kOpenVerbAtStartRe.hasMatch(u.folded) ||
        kCommandVerbRe.hasMatch(u.folded)) {
      return null;
    }
    final active = ctx.modules.activeToolId == toolId,
        topic = u.hasAny(const ['rolling offset']);
    if (_clear.hasMatch(u.folded) && (active || topic)) {
      return SkillMatch(this, .97,
          slots: const {'native_action': 'clear'}, utterance: u);
    }
    if (active &&
        (_recalculate.contains(u.folded) ||
            topic &&
                u.hasStem(const [
                  'oblicz',
                  'policz',
                  'przelicz',
                  'calculate',
                  'recalculate'
                ]) &&
                _slots(u).isEmpty)) {
      return SkillMatch(this, .97,
          slots: const {'native_edit': <String, Object?>{}}, utterance: u);
    }
    if (!topic && !(active && _edit.hasMatch(u.folded))) return null;
    final slots = _slots(u);
    if (active && _edit.hasMatch(u.folded) && slots.isNotEmpty) {
      return SkillMatch(this, .97, slots: _intent(u, ctx, slots), utterance: u);
    }
    if (!topic) return null;
    final explicitCalculation =
        u.hasStem(const ['oblicz', 'policz', 'calculate', 'compute']);
    return SkillMatch(this, slots.isNotEmpty || explicitCalculation ? .92 : .65,
        slots: _intent(u, ctx, slots), utterance: u);
  }

  @override
  Map<String, Object?> slotsFrom(Utterance u, AssistantContext ctx) =>
      _foreign(u) ? const {} : _intent(u, ctx, _slots(u), continuation: true);

  @override
  Map<String, Object?>? fillSlot(
      String slot, Utterance u, AssistantContext ctx) {
    final s = _slots(u);
    if (s.isNotEmpty) return s;
    if ((slot == 'dn' || slot == 'angle_deg') &&
        u.items.length == 1 &&
        u.items.single.isNumber) {
      final value = u.items.single.value!;
      return {
        slot: slot == 'dn'
            ? (value.isFinite && value == value.roundToDouble()
                ? value.toInt()
                : double.nan)
            : value
      };
    }
    if (slot == 'rise_mm' || slot == 'spread_mm' || slot == 'gap_mm') {
      final values = <double>[];
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

  AskResult _ask(String key, SkillMatch m) {
    final (pl, en) = switch (key) {
      'rise_mm' => (
          'Jaki wznios? Podaj dodatni wymiar z jednostką, np. 300 mm.',
          'What rise? Give a positive dimension with a unit, e.g. 300 mm.'
        ),
      'spread_mm' => (
          'Jakie odsunięcie boczne? Podaj dodatni wymiar z jednostką, np. 400 mm.',
          'What lateral spread? Give a positive dimension with a unit, e.g. 400 mm.'
        ),
      'angle_deg' => (
          'Jaki kąt kolan? Podaj jeden kąt większy od 5° i mniejszy od 89°, albo dokładnie 90°.',
          'What elbow angle? Give one angle greater than 5° and less than 89°, or exactly 90°.'
        ),
      'dn' => (
          'Jakie jedno DN kolan LR z tabeli ASME B16.9?',
          'What single LR elbow DN from the ASME B16.9 table?'
        ),
      'gap_mm' => (
          'Jaka szczelina spoiny przy każdym końcu wstawki? Podaj jednostkę, także dla 0 mm.',
          'What weld root gap at each insert end? Include a unit, including for 0 mm.'
        ),
      _ => (
          'Wymiary nie mieszczą kolan i szczelin albo wynik jest poza zakresem. Popraw wznios, odsunięcie, kąt, DN lub szczelinę.',
          'The dimensions do not fit the elbows and gaps, or the result is out of range. Correct rise, spread, angle, DN or gap.'
        ),
    };
    return AskResult(key, AssistantText(pl, en), partial: m);
  }

  @override
  Future<SkillResult> run(SkillMatch m, AssistantContext ctx) async {
    if (m.slots['native_action'] == 'clear') {
      return const AnswerResult(
          AssistantAnswer(
              text: AssistantText('Wyczyszczono kalkulator rolling offset.',
                  'Rolling-offset calculator cleared.')),
          show: ShowInModule('rolling_offset', {'action': 'clear'}));
    }
    final edits = m.slots['native_edit'];
    if (edits is Map<String, Object?>) {
      final modules = ctx.modules;
      final current = modules is FieldModuleContext
          ? (modules as FieldModuleContext).inputFields(toolId)
          : null;
      if (current == null) {
        return const FailedResult(
            AssistantText(
                'Otwórz moduł rolling offset i poczekaj na wczytanie bieżących danych.',
                'Open rolling offset and wait for current inputs to load.'),
            reportMissingCapability: false);
      }
      m = m.copyWith(slots: {...current, ...edits});
    }
    final fields = <String, Object?>{
      for (final key in RollingOffsetInput.keys)
        if (m.slots.containsKey(key)) key: m.slots[key]
    };
    final wantsCut = m.slots['cut_requested'] == true || fields['dn'] != null;
    if (m.slots['radius_model'] == 'unsupported' && wantsCut) {
      return const FailedResult(
          AssistantText(
              'Ten kalkulator długości do cięcia obsługuje kolana LR i ich segmenty według ASME B16.9, nie kolana SR/3D, własny promień ani kolana składane z odcinków rury. Nie zmieniłem danych.',
              'This cut-length calculator supports ASME B16.9 LR elbows and their segments, not SR/3D, a custom radius or pipe mitre bends. Inputs unchanged.'),
          reportMissingCapability: true);
    }
    for (final key in ['rise_mm', 'spread_mm', 'angle_deg']) {
      final n = fields[key];
      if (n is! num ||
          !n.isFinite ||
          n <= 0 ||
          key == 'angle_deg' && !rollingOffsetAngleValid(n.toDouble())) {
        return _ask(key, m);
      }
    }
    if (wantsCut && fields['dn'] == null) return _ask('dn', m);
    if (wantsCut && fields['gap_mm'] == null) return _ask('gap_mm', m);
    final RollingOffsetInput input;
    try {
      input = RollingOffsetInput.fromFields(fields);
    } on FormatException catch (e) {
      return _ask(e.message, m);
    }
    final r = input.result, cut = input.cut;
    final source = cut == null
        ? null
        : AssistantText.same(
            'ASME B16.9-2018, LR, ${switch (cut.takeout.basis) {
            TakeoutBasis.tableA90 => 'A (90°)',
            TakeoutBasis.tableB45 => 'B (45°)',
            TakeoutBasis.segment => '§6.2.4, A × tan(θ/2)'
          }}');
    return AnswerResult(
        AssistantAnswer(
            source: source,
            lines: [
              AnswerLine(
                  const AssistantText('Rzut wzdłuż osi (Run)', 'Axial run'),
                  '${fmt(r.runMm, ctx.lang)} mm'),
              AnswerLine(
                  const AssistantText('Obrót od pionu', 'Roll from vertical'),
                  '${fmt(r.rollFromVerticalDeg, ctx.lang)}°'),
              if (cut != null) ...[
                AnswerLine(
                    const AssistantText('Rura do cięcia', 'Pipe cut length'),
                    '${fmt(cut.cutMm, ctx.lang)} mm'),
                AnswerLine(
                    const AssistantText(
                        'Zabudowa jednego kolana LR', 'One LR elbow take-out'),
                    '${fmt(cut.takeout.mm, ctx.lang)} mm'),
                AnswerLine(
                    const AssistantText('Szczelina na każdym z 2 końców',
                        'Gap at each of 2 ends'),
                    '${fmt(cut.gapMm, ctx.lang)} mm'),
              ],
              if (r.multiplierWarning)
                const AnswerLine(AssistantText('Uwaga', 'Warning'),
                    'Travel multiplier > 10'),
            ],
            text: AssistantText(
              'Rzeczywiste odsunięcie: ${fmt(r.trueOffsetMm, ctx.lang)} mm. Odległość między punktami przecięcia osi kolan (Travel): ${fmt(r.travelMm, ctx.lang)} mm. ${cut == null ? 'To nie jest długość rury do cięcia.' : 'Rura do cięcia: ${fmt(cut.cutMm, ctx.lang)} mm — po odjęciu zabudów dwóch kolan LR i dwóch szczelin.'}',
              'True offset: ${fmt(r.trueOffsetMm, ctx.lang)} mm. Distance between elbow centerline intersection points (Travel): ${fmt(r.travelMm, ctx.lang)} mm. ${cut == null ? 'This is not the pipe cut length.' : 'Pipe cut length: ${fmt(cut.cutMm, ctx.lang)} mm — after deducting two LR elbow take-outs and two gaps.'}',
            )),
        show: ShowInModule(toolId, input.fields),
        contextSlots: input.fields);
  }
}
