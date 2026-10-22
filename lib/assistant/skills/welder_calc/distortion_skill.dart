import '../../../domain/welding/distortion.dart';
import '../../core/skill.dart';
import '../core/explain_tool_skill.dart' show explainedTool;
import '../core/skill_words.dart';
import '../fitter_routes/quantities.dart';

/// Liczba spoin danego rodzaju: „2 spoiny czołowe”, „1 spoina pachwinowa”.
double? _countOf(Utterance u, List<String> kind) {
  final found = <double>{};
  final items = u.items;
  for (var i = 0; i + 2 < items.length; i++) {
    if (items[i].isNumber &&
        (items[i + 1].word.startsWith('spoin') ||
            items[i + 1].word.startsWith('weld')) &&
        kind.any((k) => items[i + 2].word.startsWith(k))) {
      found.add(items[i].value!);
    }
    // EN: „2 butt welds”.
    if (items[i].isNumber &&
        kind.any((k) => items[i + 1].word.startsWith(k)) &&
        items[i + 2].word.startsWith('weld')) {
      found.add(items[i].value!);
    }
  }
  return found.length > 1 ? double.nan : found.singleOrNull;
}

final _halfVRe = RegExp(r'\b(?:pol ?v|half ?v|1 2 v)\b');
final _xRe = RegExp(r'\b(?:rowek|rowka|rowkiem|groove|ukosowanie) x\b|\bx groove\b');
final _vRe = RegExp(r'\b(?:rowek|rowka|rowkiem|groove|ukosowanie) v\b|\bv groove\b');
// Samo „V” bez liczby przed nim (nie „25 V” — wolty).
final _bareVRe = RegExp(r'(?:^|[a-z]\s)v\b');

ButtGroove? _groove(Utterance u) {
  final f = u.folded;
  final rest = f.replaceAll(_halfVRe, ' ');
  final kinds = {
    if (_halfVRe.hasMatch(f)) ButtGroove.halfV,
    if (_xRe.hasMatch(rest)) ButtGroove.x,
    if (_vRe.hasMatch(rest)) ButtGroove.v,
  };
  if (kinds.isEmpty && _bareVRe.hasMatch(rest)) return ButtGroove.v;
  return kinds.length == 1 ? kinds.single : null;
}

Map<String, Object?> _slots(Utterance u) {
  final out = <String, Object?>{};
  final g = _groove(u);
  if (g != null) out['groove'] = g.name;
  final t = lengthNear(u, const ['blach', 'grubos', 'plate', 'thickness', 't']);
  if (t != null) out['thickness_mm'] = t;
  final gap = lengthNear(u, const ['szczelin', 'odstep', 'gap', 'd']);
  if (gap != null) out['gap_mm'] = gap;
  final face = lengthNear(u, const ['prog', 'root', 'c']);
  if (face != null) out['root_face_mm'] = face;
  final angle = angleValue(u);
  if (angle != null) out['angle_deg'] = angle;
  final length = lengthNear(u, const ['koncow', 'final', 'wymiar']);
  if (length != null) out['final_length_mm'] = length;
  final butts = _countOf(u, const ['czolow', 'butt']);
  if (butts != null) out['butt_welds'] = butts;
  final fillets = _countOf(u, const ['pachwin', 'fillet']);
  if (fillets != null) out['fillet_welds'] = fillets;
  return out;
}

class DistortionShrinkageSkill extends AssistantSkill {
  @override
  String get id => 'distortion.shrinkage';
  @override
  String get toolId => 'distortion';
  @override
  AssistantTier get tier => AssistantTier.b;
  @override
  List<SkillExample> get examples => const [
        SkillExample(
            'Skurcz spoiny czołowej blacha 10 mm rowek V kąt 60 stopni szczelina 2 mm próg 1,5 mm',
            'Butt weld shrinkage plate 10 mm V groove angle 60 degrees gap 2 mm root face 1.5 mm'),
        SkillExample(
            'Wymiar przed spawaniem wymiar końcowy 1000 mm 2 spoiny czołowe blacha 10 mm rowek V kąt 60 stopni szczelina 2 mm próg 1,5 mm',
            'Pre-weld length final 1000 mm 2 butt welds plate 10 mm V groove angle 60 degrees gap 2 mm root face 1.5 mm'),
        SkillExample(
            'Skurcz poprzeczny rowek X blacha 20 mm kąt 60 stopni szczelina 3 mm próg 2 mm',
            'Transverse shrinkage X groove plate 20 mm angle 60 degrees gap 3 mm root face 2 mm'),
        SkillExample(
            'Ile się skurczy spoina pół V blacha 12 mm kąt 45 stopni szczelina 2 mm próg 1 mm',
            'How much will a half V weld shrink plate 12 mm angle 45 degrees gap 2 mm root face 1 mm'),
        SkillExample(
            'Naddatek na skurcz wymiar końcowy 2000 mm 3 spoiny czołowe 1 spoina pachwinowa blacha 8 mm rowek V kąt 60 stopni szczelina 2 mm próg 1 mm',
            'Shrinkage allowance final 2000 mm 3 butt welds 1 fillet weld plate 8 mm V groove angle 60 degrees gap 2 mm root face 1 mm'),
        SkillExample('Oblicz skurcz spawalniczy', 'Calculate weld shrinkage'),
      ];
  @override
  List<SkillRejection> get rejections => const [
        SkillRejection('otwórz odkształcenia i skurcz', routesTo: 'tool.open'),
        SkillRejection('do czego służy skurcz spawalniczy',
            routesTo: 'tool.explain'),
        SkillRejection('jaki skurcz rury przy dylatacji 80 stopni'),
      ];

  @override
  SkillMatch? match(Utterance u, AssistantContext ctx) {
    if (explainedTool(u) != null ||
        RegExp(r'^(?:otworz|pokaz|open|show)\b').hasMatch(u.folded)) {
      return null;
    }
    if (u.hasStem(const ['dylatac', 'rozszerzaln', 'expansion'])) return null;
    // „Do czego służą odkształcenia…” to pytanie o moduł, nie obliczenie.
    if (RegExp(r'^(?:do czego|what (?:is|are)\b.*\bfor\b)').hasMatch(u.folded)) {
      return null;
    }
    final shrink = u.hasStem(const ['skurcz', 'skurczy', 'shrink']) ||
        u.hasAny(const ['przed spawaniem', 'pre weld', 'pre-weld']) ||
        u.hasStem(const ['odksztalc', 'distortion']);
    if (!shrink) return null;
    final s = _slots(u);
    return SkillMatch(
        this,
        s.isNotEmpty || u.hasStem(const ['oblicz', 'policz', 'calculate', 'ile'])
            ? .92
            : .66,
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
    if (s.containsKey(slot)) return {slot: s[slot]};
    final numbers = u.items.where((i) => i.isNumber).toList();
    if (numbers.length != 1) return null;
    final v = numbers.single.value!;
    final last = u.items.last.word;
    return switch (slot) {
      'thickness_mm' || 'gap_mm' || 'root_face_mm' =>
        u.items.length == 1
            ? {slot: v}
            : lengthUnitScale(last) != null
                ? {slot: v * lengthUnitScale(last)!}
                : null,
      'angle_deg' => {slot: v},
      _ => null,
    };
  }

  @override
  Future<SkillResult> run(SkillMatch m, AssistantContext ctx) async {
    AskResult ask(String key, String pl, String en) =>
        AskResult(key, AssistantText(pl, en), partial: m);
    bool ok(Object? v) => v is num && v.isFinite;
    final t = m.slots['thickness_mm'];
    if (!ok(t)) {
      return ask('thickness_mm', 'Jaka grubość blachy t w mm?',
          'What is the plate thickness t in mm?');
    }
    final groove =
        ButtGroove.values.where((g) => g.name == m.slots['groove']).firstOrNull;
    if (groove == null) {
      return ask('groove', 'Jaki rowek: V, X czy pół V?',
          'Which groove: V, X or half V?');
    }
    final angle = m.slots['angle_deg'];
    if (!ok(angle)) {
      return groove == ButtGroove.halfV
          ? ask('angle_deg', 'Jaki kąt fazy β w stopniach?',
              'What is the bevel angle β in degrees?')
          : ask('angle_deg', 'Jaki kąt rowka α w stopniach?',
              'What is the included groove angle α in degrees?');
    }
    final gap = m.slots['gap_mm'];
    if (!ok(gap)) {
      return ask('gap_mm', 'Jaki odstęp w grani d w mm?',
          'What is the root gap d in mm?');
    }
    final face = m.slots['root_face_mm'];
    if (!ok(face)) {
      return ask('root_face_mm', 'Jaki próg c w mm?',
          'What is the root face c in mm?');
    }
    final input = ButtShrinkageInput(
        groove: groove,
        thicknessMm: (t as num).toDouble(),
        gapMm: (gap as num).toDouble(),
        rootFaceMm: (face as num).toDouble(),
        angleDeg: (angle as num).toDouble());
    final shrink = computeButtShrinkage(input);
    if (shrink == null) {
      return const FailedResult(AssistantText(
          'Moduł nie przyjął wymiarów rowka (grubość do 100 mm, szczelina do 10 mm, próg mniejszy od grubości, kąt rowka 10–120°, fazy 5–60°).',
          'The module did not accept the groove dimensions (thickness up to 100 mm, gap up to 10 mm, root face below thickness, groove angle 10–120°, bevel 5–60°).'));
    }
    String f(num v) => fmt(v.toDouble(), ctx.lang);
    final fields = <String, Object?>{
      'groove': groove.name,
      'thickness_mm': t.toDouble(),
      'gap_mm': gap.toDouble(),
      'root_face_mm': face.toDouble(),
      'angle_deg': angle.toDouble(),
    };
    final per = shrink.shrinkageAllowanceMm;
    var pl = 'Szacowany skurcz poprzeczny jednej spoiny czołowej: ${f(per)} mm '
        '(Spraragen–Ettinger 0,2·A_w/t + 0,05·d, w górę do 0,1 mm).';
    var en = 'Estimated transverse shrinkage of one butt weld: ${f(per)} mm '
        '(Spraragen–Ettinger 0.2·A_w/t + 0.05·d, rounded up to 0.1 mm).';
    final length = m.slots['final_length_mm'];
    if (ok(length)) {
      final butts = m.slots['butt_welds'];
      if (!ok(butts)) {
        return ask('butt_welds', 'Ile spoin czołowych jest na tym wymiarze?',
            'How many butt welds are along this dimension?');
      }
      final fillets = m.slots['fillet_welds'];
      final pre = computePreWeld(PreWeldInput(
          finalLengthMm: (length as num).toDouble(),
          buttWelds: (butts as num).toDouble(),
          shrinkagePerButtMm: per,
          filletWelds: ok(fillets) ? (fillets as num).toDouble() : 0));
      if (pre == null) {
        return const FailedResult(AssistantText(
            'Moduł nie przyjął wymiaru końcowego albo liczby spoin.',
            'The module did not accept the final length or weld count.'));
      }
      fields['final_length_mm'] = length.toDouble();
      fields['butt_welds'] = pre.buttWelds;
      fields['fillet_welds'] = pre.filletWelds;
      pl += ' Wymiar zestawienia przed spawaniem: ${f(pre.preWeldLengthMm)} mm '
          '(${f(length)} mm + Σ skurczu ${f(pre.totalShrinkageMm)} mm, w górę do 0,5 mm).';
      en += ' Fit-up length before welding: ${f(pre.preWeldLengthMm)} mm '
          '(${f(length)} mm + total shrinkage ${f(pre.totalShrinkageMm)} mm, rounded up to 0.5 mm).';
    }
    pl += ' To szacunek — przy seryjnej robocie zmierz skurcz na próbie.';
    en += ' This is an estimate — for repeat work measure shrinkage on a trial piece.';
    return AnswerResult(AssistantAnswer(text: AssistantText(pl, en)),
        show: ShowInModule(toolId, fields));
  }
}
