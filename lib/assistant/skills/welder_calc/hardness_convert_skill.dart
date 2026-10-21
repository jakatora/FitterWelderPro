import '../../../domain/welding/hardness.dart';
import '../../core/skill.dart';
import '../core/skill_words.dart';
import '../core/explain_tool_skill.dart' show explainedTool;

class HardnessConvertSkill extends AssistantSkill {
  @override
  String get id => 'hardness.convert';
  @override
  String get toolId => 'hardness';
  @override
  AssistantTier get tier => AssistantTier.b;
  @override
  List<SkillExample> get examples => const [
        SkillExample(
            'Przelicz twardość 250 HV na HB', 'Convert hardness 250 HV to HB'),
        SkillExample('Przelicz 30 HRC na HV', 'Convert 30 HRC to HV'),
        SkillExample('Zamień 190 HB na HV', 'Convert 190 HB to HV'),
        SkillExample('Przelicz 90 HRB na HB', 'Convert 90 HRB to HB'),
        SkillExample('Przelicz twardość', 'Convert hardness'),
        SkillExample('Twardość 250 HV na HRC stal niestopowa',
            'Hardness 250 HV to HRC carbon steel'),
      ];
  @override
  List<SkillRejection> get rejections => const [
        SkillRejection('otwórz twardość', routesTo: 'tool.open'),
        SkillRejection('zapisz pomiar twardości 250 HV'),
        SkillRejection('przelicz 10 mm na cale'),
      ];
  @override
  Map<String, Object?> slotsFrom(Utterance u, AssistantContext ctx) {
    final s = <String, Object?>{};
    final matches = RegExp(
            r'(?<![\w.,])(-?\d+(?:[.,]\d+)?)\s*(HV|HB|HRC|HRB)\b',
            caseSensitive: false)
        .allMatches(u.raw)
        .toList();
    if (matches.isNotEmpty) {
      s['value'] = matches.length == 1
          ? double.tryParse(matches.single[1]!.replaceAll(',', '.'))
          : double.nan;
      s['from'] = matches.first[2]!.toLowerCase();
      if (RegExp(r'(?:minus|\u2212)\s*$', caseSensitive: false)
          .hasMatch(u.raw.substring(0, matches.first.start))) {
        s['value'] = double.nan;
      }
      if (RegExp(r'\d[.,]?\s+$')
          .hasMatch(u.raw.substring(0, matches.first.start))) {
        s['value'] = double.nan;
      }
    }
    final target =
        RegExp(r'\b(?:na|to|into)\s+(HV|HB|HRC|HRB)\b', caseSensitive: false)
            .allMatches(u.raw)
            .toList();
    if (target.isNotEmpty) {
      s['to'] = target.length == 1 ? target.single[1]!.toLowerCase() : null;
    }
    final carbon = u.hasAny(const [
      'stal niestopowa',
      'stal niskostopowa',
      'carbon steel',
      'low alloy steel'
    ]);
    final stainless = u.hasStem(const ['nierdzewn', 'austenit', 'stainless']);
    if (carbon || stainless) {
      s['material'] = carbon && stainless
          ? 'ambiguous'
          : stainless
              ? 'stainless'
              : 'carbonLowAlloy';
    }
    return s;
  }

  @override
  SkillMatch? match(Utterance u, AssistantContext ctx) {
    if (explainedTool(u) != null ||
        kCommandVerbRe.hasMatch(u.folded) ||
        kOpenVerbAtStartRe.hasMatch(u.folded)) {
      return null;
    }
    final s = slotsFrom(u, ctx);
    if (!u.hasStem(const ['twardosc', 'hardness']) &&
        !(s.containsKey('from') && s.containsKey('to'))) {
      return null;
    }
    return SkillMatch(this, .94, slots: s);
  }

  @override
  Map<String, Object?>? fillSlot(
      String slot, Utterance u, AssistantContext ctx) {
    final s = slotsFrom(u, ctx);
    if (slot == 'to') {
      final v = u.raw.trim().toLowerCase();
      if (HardnessScale.values.any((e) => e.name == v)) s['to'] = v;
    }
    return s.containsKey(slot) ? s : null;
  }

  @override
  Future<SkillResult> run(SkillMatch m, AssistantContext ctx) async {
    final s = m.slots;
    AskResult ask(String slot, String pl, String en) =>
        AskResult(slot, AssistantText(pl, en), partial: m);
    final from =
        HardnessScale.values.where((e) => e.name == s['from']).firstOrNull;
    final to = HardnessScale.values.where((e) => e.name == s['to']).firstOrNull;
    final value = (s['value'] as num?)?.toDouble();
    if (from == null || value == null) {
      return ask('value', 'Podaj jedną wartość i skalę, np. 250 HV.',
          'Give one value and its scale, e.g. 250 HV.');
    }
    if (!value.isFinite || value <= 0 || value > from.maxPlausible) {
      return ask('value', 'Podaj prawidłową dodatnią wartość i skalę.',
          'Give a valid positive value and its scale.');
    }
    if (to == null) {
      return ask('to', 'Na jaką skalę: HV, HB, HRC czy HRB?',
          'Which target scale: HV, HB, HRC or HRB?');
    }
    if (s['material'] != 'carbonLowAlloy' && s['material'] != 'stainless') {
      return ask(
          'material',
          'Jaki materiał: stal niestopowa/niskostopowa czy nierdzewna/austenityczna?',
          'Which material: carbon/low alloy steel or stainless/austenitic steel?');
    }
    if (from != to && s['material'] == 'stainless') {
      return const FailedResult(AssistantText(
          'Tabela A.1 nie dotyczy stali nierdzewnej/austenitycznej. Zmierz twardość w docelowej skali.',
          'Table A.1 does not apply to stainless/austenitic steel. Measure in the target scale.'));
    }
    final result = convertHardness(value, from: from, to: to);
    if (result == null) {
      return const FailedResult(AssistantText(
          'Brak przeliczenia w zakresie tabeli. Nie ekstrapoluję wyniku.',
          'No conversion within the table range. No extrapolation.'));
    }
    return AnswerResult(
        AssistantAnswer(
            text: const AssistantText(
                'Przeliczenie przybliżone — bez oceny zgodności pomiaru.',
                'Approximate conversion — no measurement acceptance assessment.'),
            lines: [
              AnswerLine(const AssistantText('Wartość wejściowa', 'Input'),
                  '$value ${from.label}'),
              AnswerLine(const AssistantText('Wynik', 'Result'),
                  '${result.toStringAsFixed(2)} ${to.label}')
            ],
            source: const AssistantText(
                kHardnessTableSourcePl, kHardnessTableSourceEn)),
        show: ShowInModule('hardness', {
          'value': value,
          'scale': from.name,
          'material': (s['material'] ?? 'carbonLowAlloy')
        }));
  }
}
