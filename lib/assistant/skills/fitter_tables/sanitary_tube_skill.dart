import '../../../data/sanitary_tube.dart';
import '../../../domain/fitter/unit_conversion.dart';
import '../../core/skill.dart';
import '../core/explain_tool_skill.dart' show explainedTool;
import '../core/skill_words.dart';
import '../fitter_routes/quantities.dart';

Map<String, Object?> _slots(Utterance u) {
  final out = <String, Object?>{};
  final bpe = u.hasAny(const ['bpe', 'a270', 'a 270']);
  final din = u.hasAny(const ['din', '11850']);
  if (bpe || din) {
    out['standard'] = bpe && din
        ? 'ambiguous'
        : bpe
            ? 'bpe'
            : 'din11850_ii';
  }
  if (RegExp(r'\b(?:seria|serii|series)\s*(?:1|i|3|iii)\b').hasMatch(u.folded)) {
    out['unsupported_series'] = true;
  }
  final od = lengthNear(u, const ['od', 'srednic', 'diameter']);
  if (od != null) out['od_mm'] = od;
  final dn = u.dn();
  if (u.mentionsDn) out['dn'] = dn ?? double.nan;
  final inches = u.npsInches();
  if (inches != null) out['inch_od'] = inches;
  return out;
}

class SanitaryTubeSkill extends AssistantSkill {
  @override
  String get id => 'sanitary.tube';
  @override
  String get toolId => 'sanitary_tube';
  @override
  AssistantTier get tier => AssistantTier.b;
  @override
  List<SkillExample> get examples => const [
        SkillExample('Rura sanitarna ASME BPE 2 cale',
            'Sanitary tube ASME BPE 2 inches'),
        SkillExample(
            'Rura sanitarna DIN 11850 DN50', 'Sanitary tube DIN 11850 DN50'),
        SkillExample(
            'Rura sanitarna BPE OD 50,8 mm', 'Sanitary tube BPE OD 50.8 mm'),
        SkillExample('Rura mleczarska DIN 11850 OD 53 mm',
            'Sanitary tube DIN 11850 OD 53 mm'),
        SkillExample('Rura sanitarna ASTM A270 półtora cala',
            'Sanitary tube ASTM A270 1.5 inches'),
        SkillExample('Oblicz wymiary rury sanitarnej',
            'Calculate sanitary tube dimensions'),
      ];
  @override
  List<SkillRejection> get rejections => const [
        SkillRejection('otwórz rury sanitarne', routesTo: 'tool.open'),
        SkillRejection('średnica rury DN50', routesTo: 'pipe.od'),
        SkillRejection('narysuj rurę sanitarną BPE 2 cale'),
      ];
  @override
  SkillMatch? match(Utterance u, AssistantContext ctx) {
    if (explainedTool(u) != null ||
        kCommandVerbRe.hasMatch(u.folded) ||
        RegExp(r'^(?:otworz|pokaz|open|show)\b').hasMatch(u.folded)) {
      return null;
    }
    if (!u.hasStem(
            const ['sanitarn', 'sanitary', 'hygien', 'higien', 'mleczarsk']) &&
        !u.hasAny(const ['bpe', 'a270', '11850'])) {
      return null;
    }
    final slots = _slots(u);
    return SkillMatch(
        this,
        slots.isNotEmpty || u.hasStem(const ['oblicz', 'calculate'])
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
    if (slot == 'size' &&
        (s.containsKey('dn') ||
            s.containsKey('od_mm') ||
            s.containsKey('inch_od'))) {
      return {'dn': null, 'od_mm': null, 'inch_od': null, ...s};
    }
    return s.containsKey(slot) ? s : null;
  }

  @override
  Future<SkillResult> run(SkillMatch m, AssistantContext ctx) async {
    AskResult ask(String k, String pl, String en) =>
        AskResult(k, AssistantText(pl, en), partial: m);
    final s = m.slots, standard = s['standard'];
    if (!const ['bpe', 'din11850_ii'].contains(standard)) {
      return ask(
          'standard',
          'Jaka norma rury: ASME BPE / ASTM A270 czy DIN 11850 seria II? Rozmiary tych rur są różne.',
          'Which tube standard: ASME BPE / ASTM A270 or DIN 11850 series II? Their dimensions differ.');
    }
    if (s['unsupported_series'] == true) {
      return const FailedResult(AssistantText(
          'Aplikacja ma tabelę DIN 11850 seria II. Brakuje tabeli podanej serii — nie zastąpię jej inną.',
          'The app contains DIN 11850 series II. The requested series is missing; I will not substitute another series.'));
    }
    final bpe = standard == 'bpe';
    final rows = bpe ? kBpeTube : kDin11850Tube;
    final dn = s['dn'];
    final inches = s['inch_od'] as double?;
    final od = (s['od_mm'] as num?)?.toDouble();
    if (od != null && (!od.isFinite || od <= 0)) {
      return ask('size', 'Podaj jeden poprawny rozmiar rury i jednostkę.',
          'Give one valid tube size and unit.');
    }
    if (dn != null && (dn is! int || dn <= 0)) {
      return ask(
          'size',
          'Podaj jedno poprawne DN lub rzeczywiste OD z jednostką.',
          'Give one valid DN or actual OD with a unit.');
    }
    if (bpe && dn != null) {
      return ask(
          'size',
          'W BPE rozmiar oznacza OD w calach, nie DN rury rurowej. Podaj rozmiar w calach lub OD w mm.',
          'BPE sizes are outside diameters in inches, not pipe DN. Give the size in inches or OD in mm.');
    }
    final inchMm = inches == null
        ? null
        : convertLength(inches, LengthUnit.inch, LengthUnit.mm);
    if (inches != null && (inchMm == null || inches <= 0)) {
      return ask('size', 'Podaj poprawny rozmiar calowy rury.',
          'Give a valid tube size in inches.');
    }
    if (od != null && inchMm != null && (od - inchMm).abs() > .00001) {
      return const FailedResult(AssistantText(
          'Rozmiar calowy i OD w mm są sprzeczne. Popraw dane.',
          'The inch size and OD in mm conflict. Correct the inputs.'));
    }
    final actualOd = od ?? inchMm;
    final dnRow =
        dn is int ? rows.where((r) => r.size == 'DN$dn').firstOrNull : null;
    final odRow = actualOd == null
        ? null
        : rows.where((r) => (r.od - actualOd).abs() < .00001).firstOrNull;
    if (dnRow != null &&
        actualOd != null &&
        (dnRow.od - actualOd).abs() > .00001) {
      return const FailedResult(AssistantText(
          'DN i OD nie odpowiadają temu samemu wierszowi wybranej normy. Popraw dane.',
          'DN and OD do not identify the same row in the selected standard. Correct inputs.'));
    }
    if (actualOd == null && dn == null) {
      return ask(
          'size',
          'Jaki rozmiar: np. 2 cale dla BPE lub DN50 dla DIN? Możesz też podać OD w mm.',
          'What size: e.g. 2 inches for BPE or DN50 for DIN? You may also give OD in mm.');
    }
    final row = dnRow ?? odRow;
    if (row == null) {
      return const FailedResult(AssistantText(
          'Brak tego rozmiaru w tabeli wybranej normy. Nie wybieram najbliższej średnicy.',
          'This size is missing from the selected standard table. I will not choose a nearest diameter.'));
    }
    final label = bpe ? 'ASME BPE / ASTM A270' : 'DIN 11850 seria II';
    return AnswerResult(
        AssistantAnswer(
            text: AssistantText(
                '$label ${row.size}: OD ${fmt(row.od, ctx.lang)} mm, ścianka ${fmt(row.wall, ctx.lang)} mm, ID ${fmt(row.id, ctx.lang)} mm. Dla 316L: ${fmt(row.massPerMeter, ctx.lang)} kg/m i ${fmt(row.litresPerMeter, ctx.lang)} l/m objętości wewnętrznej. Są to wymiary nominalne; sprawdź tolerancje i atest rury.',
                '${bpe ? label : 'DIN 11850 series II'} ${row.size}: OD ${fmt(row.od, ctx.lang)} mm, wall ${fmt(row.wall, ctx.lang)} mm, ID ${fmt(row.id, ctx.lang)} mm. For 316L: ${fmt(row.massPerMeter, ctx.lang)} kg/m and ${fmt(row.litresPerMeter, ctx.lang)} l/m internal volume. These are nominal dimensions; check tolerances and the tube certificate.'),
            source:
                AssistantText.same('$label; 316L ρ = 8000 kg/m³ (EN 10088-1)')),
        show: ShowInModule(toolId, {'standard': standard, 'size': row.size}));
  }
}
