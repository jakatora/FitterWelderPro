import '../../../data/pipe_schedules.dart';
import '../../../domain/fitter/mitre_bend.dart';
import '../../core/skill.dart';
import '../core/explain_tool_skill.dart' show explainedTool;
import '../core/skill_words.dart';
import 'quantities.dart';

const _odLabels = ['od', 'srednic', 'diameter'];
const _radiusLabels = ['promien', 'radius'];
const _tangentLabels = ['prosty', 'tangent', 'straight'];
const _allLabels = [
  ..._odLabels,
  ..._radiusLabels,
  ..._tangentLabels,
  'kat',
  'angle',
  'spoin',
  'weld',
  'dn',
];

bool _isLabel(String word, List<String> labels) => labels
    .any((label) => label == 'od' ? word == label : word.startsWith(label));

bool _alternativeFor(Utterance u, List<String> labels) {
  final items = u.items;
  for (var i = 0; i < items.length; i++) {
    if (items[i].isNumber || !_isLabel(items[i].word, labels)) continue;
    int? firstNumber;
    for (var j = i + 1; j < items.length && j <= i + 7; j++) {
      if (items[j].isNumber) firstNumber ??= j;
      final word = items[j].word;
      if (_isLabel(word, _allLabels)) break;
      // "angle 90 degrees 3 or 4 welds" has an ambiguous COUNT, not
      // an ambiguous angle. Keep the valid angle when asking about welds.
      var afterNumber = j + 1;
      while (afterNumber < items.length &&
          (items[afterNumber].isNumber ||
              const {'or', 'albo', 'lub', 'czy', 'i', 'and'}
                  .contains(items[afterNumber].word))) {
        afterNumber++;
      }
      final numberIsCount = afterNumber < items.length &&
          _isLabel(items[afterNumber].word, const ['spoin', 'weld']);
      if (items[j].isNumber && firstNumber != j && !numberIsCount) {
        return true;
      }
      final previousNumber = items[j - 1].isNumber ? j - 1 : j - 2;
      final startsCount = j + 2 < items.length &&
          _isLabel(items[j + 2].word, const ['spoin', 'weld']);
      if (!startsCount &&
          const {'or', 'albo', 'lub', 'czy', 'i', 'and'}.contains(word) &&
          j + 1 < items.length &&
          items[j + 1].isNumber &&
          j > i + 1 &&
          previousNumber == firstNumber) {
        return true;
      }
    }
  }
  return false;
}

double? _dimension(Utterance u, List<String> labels) {
  if (_alternativeFor(u, labels)) return double.nan;
  final value = lengthNear(u, labels);
  final mentioned = u.items.any((item) =>
      !item.isNumber &&
      labels.any((label) =>
          label == 'od' ? item.word == label : item.word.startsWith(label)));
  return value ?? (mentioned ? double.nan : null);
}

// A count has no physical unit. Retain conflicting/invalid explicit values
// as NaN so a continuation cannot silently reuse an older valid count.
double? _weldCount(Utterance u) {
  final values = <double>{};
  bool label(String word) =>
      word.startsWith('spoin') || word == 'weld' || word == 'welds';
  for (var i = 0; i < u.items.length; i++) {
    if (!label(u.items[i].word)) continue;
    var j = i + 1;
    while (j < u.items.length &&
        const {'is', 'to', 'minus', 'jest', 'wynosi', 'equals'}
            .contains(u.items[j].word)) {
      j++;
    }
    if (j < u.items.length && u.items[j].isNumber) {
      values.add(signedQuantity(u, j));
      if (j + 1 < u.items.length &&
          (u.items[j + 1].isNumber ||
              lengthUnitScale(u.items[j + 1].word) != null ||
              const {
                'kg',
                'a',
                'v',
                'bar',
                'deg',
                'stopni',
                'degrees',
                'percent',
                'procent'
              }.contains(u.items[j + 1].word))) {
        values.add(double.nan);
      }
      if (j + 2 < u.items.length &&
          const {'or', 'albo', 'lub', 'i', 'and'}
              .contains(u.items[j + 1].word) &&
          u.items[j + 2].isNumber) {
        values.add(signedQuantity(u, j + 2));
      }
    } else if (i > 0 && u.items[i - 1].isNumber) {
      values.add(signedQuantity(u, i - 1));
      if (i > 2 &&
          const {'or', 'albo', 'lub', 'i', 'and'}
              .contains(u.items[i - 2].word) &&
          u.items[i - 3].isNumber) {
        values.add(signedQuantity(u, i - 3));
      }
    } else {
      values.add(double.nan);
    }
  }
  return values.length > 1 ? double.nan : values.singleOrNull;
}

Map<String, Object?> _slots(Utterance u) {
  var od = _dimension(u, _odLabels);
  if (u.mentionsDn) {
    final dn = u.dn();
    final row = kPipeWalls.where((r) => r.dn == dn).firstOrNull;
    final fromDn = row?.od ?? double.nan;
    od = od == null || od == fromDn ? fromDn : double.nan;
  }
  final angle = _alternativeFor(u, const ['kat', 'angle'])
      ? double.nan
      : angleValue(u) ?? (u.hasAny(const ['kat', 'angle']) ? double.nan : null);
  final welds = _weldCount(u);
  final radius = _dimension(u, _radiusLabels);
  final tangent = _dimension(u, _tangentLabels);
  final result = <String, Object?>{
    if (od != null) 'od_mm': od,
    if (od != null) 'dn': u.mentionsDn ? u.dn() : null,
    if (od != null) 'dn_source': u.mentionsDn,
    if (angle != null) 'angle_deg': angle,
    if (welds != null) 'welds': welds,
    if (radius != null) 'radius_mm': radius,
    if (tangent != null) 'tangent_mm': tangent,
  };
  return result;
}

class MitreBendSkill extends AssistantSkill {
  @override
  String get id => 'mitre.bend';
  @override
  String get toolId => 'mitre_bend';
  @override
  AssistantTier get tier => AssistantTier.b;
  @override
  List<SkillExample> get examples => const [
        SkillExample(
            'Oblicz kolano segmentowe OD 168,3 mm kąt 90 stopni 3 spoiny promień 252,45 mm prosty 0 mm',
            'Calculate mitred bend OD 168.3 mm angle 90 degrees 3 welds radius 252.45 mm tangent 0 mm'),
        SkillExample('Oblicz kolano segmentowe', 'Calculate lobster back bend'),
        SkillExample(
            'Kolano segmentowe DN100 kąt 60 stopni 2 spoiny promień 200 mm prosty 5 cm',
            'Mitered bend DN100 angle 60 degrees 2 welds radius 200 mm straight 5 cm'),
        SkillExample(
            'Kolano segmentowe OD 100 mm kąt 90 stopni 1 spoina prosty 100 mm',
            'Segmented elbow OD 100 mm angle 90 degrees 1 weld tangent 100 mm'),
        SkillExample(
            'Kolano segmentowe OD 20 cm kąt 120 stopni 4 spoiny promień 40 cm prosty 0 mm',
            'Gored elbow OD 20 cm angle 120 degrees 4 welds radius 40 cm tangent 0 mm'),
        SkillExample(
            'Kolano segmentowe OD 100 mm kąt 180 stopni 3 spoiny promień 200 mm prosty 10 mm',
            'Mitred bend OD 100 mm angle 180 degrees 3 welds radius 200 mm tangent 10 mm'),
      ];
  @override
  List<SkillRejection> get rejections => const [
        SkillRejection('otwórz kolano segmentowe', routesTo: 'tool.open'),
        SkillRejection('narysuj kolano w górę'),
        SkillRejection('ile waży rura DN100 ścianka 3 mm',
            routesTo: 'pipe.weight'),
        SkillRejection('oblicz obrót kolanka OD 100 mm kąt 90 stopni',
            routesTo: 'elbow.rotation'),
      ];
  @override
  SkillMatch? match(Utterance u, AssistantContext ctx) {
    if (explainedTool(u) != null ||
        referencesInstruction(u) ||
        kOpenVerbAtStartRe.hasMatch(u.folded) ||
        kCommandVerbRe.hasMatch(u.folded) ||
        mentionsWeight(u)) {
      return null;
    }
    if (!(u.hasStem(const ['kolan', 'elbow', 'bend']) &&
        u.hasStem(const [
          'segmentow',
          'segmented',
          'mitre',
          'miter',
          'lobster',
          'gored'
        ]))) {
      return null;
    }
    final slots = _slots(u);
    return SkillMatch(
        this,
        slots.isNotEmpty ||
                u.hasStem(const ['oblicz', 'policz', 'calculate', 'compute'])
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
    final slots = _slots(u);
    if (slots.isNotEmpty) return slots;
    if (slot == 'welds' || slot == 'angle_deg') {
      final items = u.items;
      if (items.length == 1 && items.single.isNumber ||
          items.length == 2 &&
              items.first.word == 'minus' &&
              items.last.isNumber) {
        return {slot: signedQuantity(u, items.length - 1)};
      }
    }
    if (const {'od_mm', 'radius_mm', 'tangent_mm'}.contains(slot)) {
      final items = u.items;
      final i = items.length == 3 && items.first.word == 'minus' ? 1 : 0;
      if (items.length == i + 2 && items[i].isNumber) {
        final scale = lengthUnitScale(items[i + 1].word);
        if (scale != null) {
          return {
            slot: signedQuantity(u, i) * scale,
            if (slot == 'od_mm') 'dn_source': false,
            if (slot == 'od_mm') 'dn': null,
          };
        }
      }
    }
    return null;
  }

  @override
  Future<SkillResult> run(SkillMatch m, AssistantContext ctx) async {
    double? n(String k) =>
        m.slots[k] is num ? (m.slots[k] as num).toDouble() : null;
    final od = n('od_mm'), angle = n('angle_deg'), welds = n('welds');
    final radius = n('radius_mm'), tangent = n('tangent_mm');
    AskResult ask(String slot, String pl, String en) =>
        AskResult(slot, AssistantText(pl, en), partial: m);
    if (od == null || !od.isFinite || od <= 0 || od > 3000) {
      return ask(
          'od_mm',
          'Jaka średnica zewnętrzna OD (do 3000 mm)? Podaj wymiar z jednostką albo jedno DN z tabeli.',
          'What outside diameter OD (up to 3000 mm)? Give a dimension with a unit or one tabulated DN.');
    }
    if (angle == null || !angle.isFinite || angle <= 0 || angle > 180) {
      return ask(
          'angle_deg',
          'Jaki całkowity kąt kolana? Podaj kąt większy od 0 do 180 stopni.',
          'What total bend angle? Give an angle greater than 0 up to 180 degrees.');
    }
    if (welds == null ||
        !welds.isFinite ||
        welds != welds.roundToDouble() ||
        welds < 1 ||
        welds > 12 ||
        angle / welds >= 180) {
      return ask(
          'welds',
          'Ile spoin ukośnych (1–12)? To liczba łączeń; elementów rury jest o jeden więcej. Zmiana kierunku na jednej spoinie musi być mniejsza niż 180°.',
          'How many mitred welds (1–12)? This counts joints; there is one more pipe piece. Deflection per weld must be less than 180°.');
    }
    if (welds > 1 && (radius == null || !radius.isFinite || radius <= od / 2)) {
      return ask(
          'radius_mm',
          'Jaki promień po osi? Podaj wymiar z jednostką, większy od połowy OD.',
          'What centreline radius? Give a dimension with a unit, greater than half the OD.');
    }
    if (tangent == null || !tangent.isFinite || tangent < 0) {
      return ask(
          'tangent_mm',
          'Jaki odcinek prosty na każdym końcu? Podaj wymiar z jednostką; bez odcinka powiedz „0 mm”.',
          'What straight tangent at each end? Give a dimension with a unit; say “0 mm” for none.');
    }
    final input = MitreBendInput(
        odMm: od,
        bendAngleDeg: angle,
        welds: welds.toInt(),
        radiusMm: welds == 1 ? 0 : radius!,
        tangentMm: tangent);
    if (input.problems.contains(MitreProblem.tangentTooShort)) {
      return ask(
          'tangent_mm',
          'Przy jednej spoinie odcinek prosty nie mieści skosu. Podaj dłuższy odcinek z jednostką.',
          'With one weld the straight tangent cannot contain the cut. Give a longer tangent with a unit.');
    }
    final result = computeMitreBend(input);
    if (result == null) {
      return const FailedResult(
          AssistantText('Wynik poza zakresem. Sprawdź wymiary.',
              'Result out of range. Check dimensions.'),
          reportMissingCapability: false);
    }
    final full = result.fullSegment;
    String mm(double v) => '${fmt(v, ctx.lang)} mm';
    return AnswerResult(
        AssistantAnswer(
            source: m.slots['dn_source'] == true
                ? const AssistantText.same('DN → OD: ASME B36.10M / B36.19M')
                : null,
            text: AssistantText(
                'Kolano segmentowe: kąt cięcia ${fmt(result.cutAngleDeg, ctx.lang)}°, ${result.fullSegments} pełnych segmentów i 2 końcowe. Geometria powierzchni zewnętrznej, bez szczelin, ukosowania i rzazów; dopuszczenie kolana określa projekt.',
                'Mitred bend: cut angle ${fmt(result.cutAngleDeg, ctx.lang)}°, ${result.fullSegments} full segments and 2 end pieces. Outside-surface geometry without gaps, bevels or saw kerf; the design determines whether the bend is permitted.'),
            lines: [
              if (full != null) ...[
                AnswerLine(
                    const AssistantText(
                        'Pełny segment po osi', 'Full segment centreline'),
                    mm(full.centreMm)),
                AnswerLine(
                    const AssistantText('Pełny segment gardło / grzbiet',
                        'Full segment throat / heel'),
                    '${mm(full.throatMm)} / ${mm(full.heelMm)}'),
              ],
              AnswerLine(
                  const AssistantText('Końcowy po osi', 'End piece centreline'),
                  mm(result.endPiece.centreMm)),
              AnswerLine(
                  const AssistantText(
                      'Końcowy gardło / grzbiet', 'End piece throat / heel'),
                  '${mm(result.endPiece.throatMm)} / ${mm(result.endPiece.heelMm)}'),
              AnswerLine(
                  const AssistantText('Rura po osi bez rzazów',
                      'Centreline pipe stock without kerf'),
                  mm(result.pipeNeededMm)),
            ]),
        show: ShowInModule(toolId, {
          'od_mm': od,
          'angle_deg': angle,
          'welds': welds.toInt(),
          'radius_mm': input.radiusMm,
          'tangent_mm': tangent,
        }));
  }
}
