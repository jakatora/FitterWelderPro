import 'dart:math' as math;
import '../../../data/nps_dn_od_r.dart';
import '../../../domain/fitter/fitter_calcs.dart';
import '../../../services/takeout_catalog.dart';
import '../../core/skill.dart';
import '../core/explain_tool_skill.dart' show explainedTool;
import '../core/skill_words.dart';
import 'quantities.dart';

Map<String, Object?> _slots(Utterance u) {
  final s = <String, Object?>{};
  for (final e in const {
    'od_mm': ['od', 'srednic', 'diameter'],
    'radius_mm': ['r', 'promien', 'radius'],
    'offset_mm': ['offset', 'odsunieci', 'przesunieci'],
    'gap_mm': ['szczelin', 'gap'],
  }.entries) {
    final n = lengthNear(u, e.value);
    if (n != null) s[e.key] = n;
  }
  final angle = angleValue(u);
  if (angle != null) s['angle_deg'] = angle;
  if (u.mentionsDn) s['dn'] = u.dn() ?? double.nan;
  final modes = <String>{};
  if (u.hasAny(const ['lr']) ||
      RegExp(r'\b1[.,]5\s*d\b', caseSensitive: false).hasMatch(u.raw)) {
    modes.add('1.5D');
  }
  if (u.hasAny(const ['sr']) ||
      RegExp(r'\b1\s*d\b', caseSensitive: false).hasMatch(u.raw)) {
    modes.add('1D');
  }
  if (RegExp(r'\b3\s*d\b', caseSensitive: false).hasMatch(u.raw)) {
    modes.add('3D');
  }
  if (u.hasStem(const ['reczn', 'manual']) || s.containsKey('radius_mm')) {
    modes.add('manual');
  }
  if (modes.isNotEmpty) {
    s['mode'] = modes.length == 1 ? modes.single : 'ambiguous';
  }
  return s;
}

class InsertLengthSkill extends AssistantSkill {
  @override
  String get id => 'insert.length';
  @override
  String get toolId => 'insert';
  @override
  AssistantTier get tier => AssistantTier.b;
  @override
  List<SkillExample> get examples => const [
        SkillExample(
            'Oblicz wstawkę offset 300 mm kąt 45 stopni promień 100 mm szczelina 2 mm',
            'Calculate insert offset 300 mm angle 45 degrees radius 100 mm gap 2 mm'),
        SkillExample(
            'Wstawka między kolanami DN50 LR offset 300 mm kąt 45 stopni szczelina 2 mm',
            'Insert between elbows DN50 LR offset 300 mm angle 45 degrees gap 2 mm'),
        SkillExample('Oblicz długość wstawki', 'Calculate insert length'),
        SkillExample(
            'Wstawka DN50 SR offset 400 mm kąt 90 stopni szczelina 0 mm',
            'Insert DN50 SR offset 400 mm angle 90 degrees gap 0 mm'),
        SkillExample(
            'Wstawka OD 60,3 mm 3D offset 500 mm kąt 45 stopni szczelina 3 mm',
            'Insert OD 60.3 mm 3D offset 500 mm angle 45 degrees gap 3 mm'),
        SkillExample(
            'Wstawka promień 10 cm offset 30 cm kąt 60 stopni szczelina 0 mm',
            'Insert radius 10 cm offset 30 cm angle 60 degrees gap 0 mm'),
      ];
  @override
  List<SkillRejection> get rejections => const [
        SkillRejection('otwórz wstawkę', routesTo: 'tool.open'),
        SkillRejection('narysuj kolano DN50 LR 90 stopni'),
        SkillRejection('wymiar kolana DN50 LR kąt 45 stopni',
            routesTo: 'elbow.takeout'),
      ];
  @override
  SkillMatch? match(Utterance u, AssistantContext ctx) {
    // English "insert" is also the name of this spool calculation.
    if (explainedTool(u) != null ||
        kCommandVerbRe
            .hasMatch(u.folded.replaceAll(RegExp(r'\binsert\b'), '')) ||
        RegExp(r'^(?:otworz|pokaz|open|show)\b').hasMatch(u.folded)) {
      return null;
    }
    if (!u.hasStem(const ['wstawk', 'spool']) && !u.hasAny(const ['insert'])) {
      return null;
    }
    final s = _slots(u);
    return SkillMatch(
        this,
        s.isNotEmpty || u.hasStem(const ['oblicz', 'policz', 'calculate'])
            ? .95
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
    if (slot == 'size' && (s.containsKey('dn') || s.containsKey('od_mm'))) {
      return {'dn': null, 'od_mm': null, ...s};
    }
    if (s.containsKey(slot)) return s;
    if (slot.endsWith('_mm')) {
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
    AskResult ask(String key, String pl, String en) =>
        AskResult(key, AssistantText(pl, en), partial: m);
    double? n(String k) => (m.slots[k] as num?)?.toDouble();
    final mode = m.slots['mode'];
    if (!const ['manual', '1D', '1.5D', '3D'].contains(mode)) {
      return ask(
          'mode',
          'Dwa jednakowe kolana: podaj rodzinę LR (1,5D), SR (1D), 3D albo ręczny promień osi R z karty kolana.',
          'For two identical elbows, give family LR (1.5D), SR (1D), 3D, or manual centreline radius R from the elbow datasheet.');
    }
    final angle = n('angle_deg');
    if (angle == null ||
        !angle.isFinite ||
        angle <= 0 ||
        angle >= 180 ||
        mode != 'manual' && angle > 90) {
      return ask(
          'angle_deg',
          'Podaj kąt każdego kolana w stopniach: powyżej 0 do 90° dla tabeli, poniżej 180° dla ręcznego R.',
          'Give each elbow angle in degrees: greater than 0 up to 90° for tables, below 180° for manual R.');
    }
    final off = n('offset_mm');
    if (off == null || !off.isFinite || off <= 0) {
      return ask(
          'offset_mm',
          'Podaj prostopadłe odsunięcie osi równoległych rur (offset), np. 300 mm.',
          'Give the perpendicular offset between parallel pipe axes, e.g. 300 mm.');
    }
    final gap = n('gap_mm');
    if (gap == null || !gap.isFinite || gap < 0) {
      return ask(
          'gap_mm',
          'Jaka szczelina na KAŻDĄ z dwóch spoin? Podaj jednostkę, również dla zera (np. 0 mm).',
          'What gap for EACH of the two welds? Include a unit, including zero (e.g. 0 mm).');
    }
    double takeout;
    final fields = <String, Object?>{
      'mode': mode,
      'angle_deg': angle,
      'offset_mm': off,
      'gap_mm': gap
    };
    String plBasis, enBasis;
    if (mode == 'manual') {
      final radius = n('radius_mm');
      if (radius == null || !radius.isFinite || radius <= 0) {
        return ask(
            'radius_mm',
            'Podaj promień osi kolana R z jednostką, np. 100 mm.',
            'Give elbow centreline radius R with a unit, e.g. 100 mm.');
      }
      takeout = radius * math.tan(angle * math.pi / 360);
      fields['radius_mm'] = radius;
      plBasis = 'Ręczny R: odjęcie każdego kolana R × tan(θ/2).';
      enBasis = 'Manual R: each elbow takeout is R × tan(θ/2).';
    } else {
      final dn = m.slots['dn'], od = n('od_mm');
      final dnRow =
          kNpsTable.where((r) => r.dn == dn && r.hasB169Elbows).firstOrNull;
      final row = od == null ? dnRow : b169RowForOd(od);
      if (row == null ||
          dn != null && row.dn != dn ||
          od != null && (!od.isFinite || od <= 0)) {
        return ask(
            'size',
            'Podaj poprawne DN albo OD kolana ASME B16.9, np. DN50 lub OD 60,3 mm.',
            'Give a valid ASME B16.9 elbow DN or OD, e.g. DN50 or OD 60.3 mm.');
      }
      final type = switch (mode) {
        '1D' => ElbowRadiusType.short1D,
        '3D' => ElbowRadiusType.long3D,
        _ => ElbowRadiusType.long15D
      };
      final result = b169ElbowTakeout(dn: row.dn, type: type, angleDeg: angle);
      if (result == null) {
        return const FailedResult(
            AssistantText(
                'Brak tej rodziny i rozmiaru w tabeli kolan. Wybierz inną rodzinę albo ręczny promień R.',
                'This elbow family and size are missing from the table. Choose another family or manual radius R.'),
            reportMissingCapability: true);
      }
      takeout = result.mm;
      fields['od_mm'] = row.odMm;
      plBasis = result.basis == TakeoutBasis.segment
          ? 'Segment kolana 90° wg ASME B16.9 §6.2.4 (nie tablicowe kolano gotowe).'
          : 'Wymiar kolana z tabeli ASME B16.9.';
      enBasis = result.basis == TakeoutBasis.segment
          ? 'Segment of a 90° elbow per ASME B16.9 §6.2.4 (not a tabulated ready-made elbow).'
          : 'Elbow dimension from ASME B16.9 table.';
    }
    final r = insertBetweenElbows(
        offsetMm: off, angleDeg: angle, takeoutMm: takeout, weldGapMm: gap);
    if (!r.cutMm.isFinite ||
        !r.travelMm.isFinite ||
        !r.runMm.isFinite ||
        r.cutMm <= 0) {
      return const FailedResult(AssistantText(
          'Dla tych wymiarów nie powstaje dodatnia długość wstawki. Sprawdź offset, kąt, kolana i szczeliny.',
          'These dimensions do not produce a positive insert cut length. Check offset, angle, elbows and gaps.'));
    }
    return AnswerResult(
        AssistantAnswer(
            source: AssistantText.same(mode == 'manual'
                ? 'L = offset / sin(θ) − 2 × R × tan(θ/2) − 2 × gap'
                : 'ASME B16.9-2018; L = offset / sin(θ) − 2 × takeout − 2 × gap'),
            text: AssistantText(
                'Wstawka do cięcia: ${fmt(r.cutMm, ctx.lang)} mm. Dwa jednakowe kolana: odjęcie każdego ${fmt(takeout, ctx.lang)} mm oraz dwie szczeliny po ${fmt(gap, ctx.lang)} mm. Travel osi ${fmt(r.travelMm, ctx.lang)} mm; między końcami kolan ${fmt(r.insertMm, ctx.lang)} mm przed odjęciem szczelin. $plBasis',
                'Insert cut length: ${fmt(r.cutMm, ctx.lang)} mm. Two identical elbows: each takeout ${fmt(takeout, ctx.lang)} mm and two gaps of ${fmt(gap, ctx.lang)} mm each. Centreline travel ${fmt(r.travelMm, ctx.lang)} mm; between elbow ends ${fmt(r.insertMm, ctx.lang)} mm before deducting gaps. $enBasis')),
        show: ShowInModule(toolId, fields));
  }
}
