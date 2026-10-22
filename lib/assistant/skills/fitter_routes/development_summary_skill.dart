import '../../../domain/fitter/cone_assistant_input.dart';
import '../../../domain/fitter/eccentric_cone_assistant_input.dart';
import '../../../domain/fitter/transition_assistant_input.dart';
import '../../assistant_validator.dart' show assistantNumber;
import '../../core/skill.dart';
import '../../core/command_words.dart';

String? _query(Utterance u, {bool natural = false}) {
  if (referencesInstruction(u) ||
      u.hasAny(
          const ['nie', 'not', 'dont', 'don t', 'never', 'new', 'nowego'])) {
    return null;
  }
  final text = u.folded.replaceFirst(
      RegExp(
          r'^(?:prosze |please |powiedz mi |tell me |czy mozesz |could you |can you )'),
      '');
  if (RegExp(
          r'^(?:jaka (?:jest )?(?:aktualna |obecna )?wysokosc|ile wynosi (?:aktualna |obecna )?wysokosc|what is (?:the )?(?:current )?height)(?: (?:tego )?(?:stozka|przejscia|rozwinięcia|rozwiniecia)| of (?:this |the )?(?:cone|transition|development))?$')
      .hasMatch(text)) {
    return 'height';
  }
  if (RegExp(
          r'^(?:podsumuj (?:ten |to |biezace |aktualne |aktualny )?(?:stozek|przejscie|rozwiniecie)|summari[sz]e (?:this |the |current )?(?:cone|transition|development))$')
      .hasMatch(text)) {
    return 'summary';
  }
  if (natural &&
      RegExp(r'^(?:(?:zrob|przygotuj) (?:mi )?zestawienie (?:tego |aktualnego |biezacego )?(?:stozka|przejscia|rozwiniecia)|(?:give|prepare) (?:me )?a summary of (?:this|the current) (?:cone|transition|development))$')
          .hasMatch(text)) {
    return 'summary';
  }
  return null;
}

class DevelopmentSummarySkill extends AssistantSkill {
  @override
  String get id => 'development.summary';
  @override
  String get toolId => 'cone_layout';
  @override
  AssistantTier get tier => AssistantTier.a;
  @override
  List<SkillExample> get examples => const [
        SkillExample(
            'Podsumuj bieżące rozwinięcie', 'Summarize current development'),
        SkillExample('Podsumuj ten stożek', 'Summarize this cone'),
        SkillExample(
            'Jaka jest aktualna wysokość', 'What is the current height'),
      ];
  @override
  SkillMatch? match(Utterance u, AssistantContext ctx) {
    final active = ctx.modules.activeToolId;
    if (active != null && active != toolId) return null;
    final query = _query(u);
    return query == null
        ? null
        : SkillMatch(this, .99, slots: {'query': query}, utterance: u);
  }

  @override
  bool acceptsProposal(
      Utterance original, Utterance command, AssistantContext context) {
    final q = _query(original, natural: true);
    return q != null && q == _query(command);
  }

  @override
  Future<SkillResult> run(SkillMatch m, AssistantContext ctx) async {
    final modules = ctx.modules;
    final fields =
        modules.activeToolId == toolId && modules is FieldModuleContext
            ? (modules as FieldModuleContext).inputFields(toolId)
            : null;
    if (fields == null) {
      return const AnswerResult(
          AssistantAnswer(
              text: AssistantText(
                  'Otwórz rozwinięcie stożka lub przejścia, abym odczytał bieżące dane.',
                  'Open a cone or transition development so I can read current inputs.')),
          actionCompleted: false);
    }
    final lines = <AnswerLine>[];
    String number(num n) => assistantNumber(n.toDouble(), ctx.lang);
    void length(String pl, String en, num value) =>
        lines.add(AnswerLine(AssistantText(pl, en), '${number(value)} mm'));
    void count(String pl, String en, int value) =>
        lines.add(AnswerLine(AssistantText(pl, en), '$value'));
    late double height;
    late AssistantText shape;
    try {
      switch (fields['shape']) {
        case 'concentric':
          final parsed = ConeAssistantInput.fromFields(fields),
              r = parsed.result,
              i = parsed.input;
          height = r.heightMm;
          shape = const AssistantText(
              'Bieżący stożek współosiowy.', 'Current concentric cone.');
          length('Duża średnica', 'Large diameter', i.largeDiaMm);
          length('Mała średnica', 'Small diameter', i.smallDiaMm);
          length('Grubość blachy', 'Plate thickness', i.thicknessMm);
          count('Części', 'Parts', i.parts);
          length('Naddatek', 'Allowance', i.allowanceMm);
          length('Promień zewnętrzny rozwinięcia', 'Outer development radius',
              r.outerRadiusMm);
          length('Promień wewnętrzny rozwinięcia', 'Inner development radius',
              r.innerRadiusMm);
          lines.add(AnswerLine(
              const AssistantText('Kąt wycinka', 'Sector angle'),
              '${number(r.sectorAngleDeg)}°'));
        case 'eccentric':
          final parsed = EccentricConeAssistantInput.fromFields(fields),
              r = parsed.result,
              i = parsed.input;
          height = i.heightMm;
          shape = const AssistantText(
              'Bieżący stożek mimośrodowy.', 'Current eccentric cone.');
          length('Duża średnica', 'Large diameter', i.largeDiaMm);
          length('Mała średnica', 'Small diameter', i.smallDiaMm);
          length('Grubość blachy', 'Plate thickness', i.thicknessMm);
          length('Przesunięcie osi', 'Axis offset', r.offsetMm);
          length('Najkrótsza tworząca', 'Shortest generator',
              r.shortestGeneratorMm);
          length(
              'Najdłuższa tworząca', 'Longest generator', r.longestGeneratorMm);
          count('Części', 'Parts', i.parts);
          count('Podziały', 'Divisions', i.divisions);
          lines.add(AnswerLine(
              const AssistantText('Wariant', 'Variant'),
              AssistantText(
                      i.verticalSide
                          ? 'Ścianka pionowa'
                          : 'Zadane przesunięcie',
                      i.verticalSide ? 'Vertical side' : 'Explicit offset')
                  .of(ctx.lang)));
          lines.add(AnswerLine(
              const AssistantText('Szew', 'Seam'),
              AssistantText(
                      i.seamOnShortSide ? 'Krótka strona' : 'Długa strona',
                      i.seamOnShortSide ? 'Short side' : 'Long side')
                  .of(ctx.lang)));
        case 'transition':
          final parsed = TransitionAssistantInput.fromFields(fields),
              r = parsed.result,
              i = parsed.input;
          height = i.heightMm;
          shape = const AssistantText('Bieżące przejście prostokąt–koło.',
              'Current rectangle-to-round transition.');
          length('Bok A', 'Side A', i.sideAMm);
          length('Bok B', 'Side B', i.sideBMm);
          length('Średnica koła', 'Circle diameter', i.diameterMm);
          length('Grubość blachy', 'Plate thickness', i.thicknessMm);
          length('Przesunięcie X', 'X offset', i.offsetXMm);
          length('Przesunięcie Y', 'Y offset', i.offsetYMm);
          count('Części', 'Parts', i.parts);
          count('Podziały', 'Divisions', i.divisions);
          lines.add(AnswerLine(
              const AssistantText('Szew', 'Seam'),
              switch (i.seam.name) {
                'sideA' => 'A',
                'sideB' => 'B',
                _ => const AssistantText('Naroże', 'Corner').of(ctx.lang),
              }));
          length('Łączna krawędź dolna', 'Total bottom edge', r.bottomEdgeMm);
          length('Łączna krawędź górna', 'Total top edge', r.topEdgeMm);
        default:
          throw const FormatException('unknown development shape');
      }
      final reference = switch (fields['reference']) {
        'outside' => const AssistantText('Zewnętrzne', 'Outside'),
        'inside' => const AssistantText('Wewnętrzne', 'Inside'),
        _ => const AssistantText('Średnie', 'Mean'),
      };
      lines.insert(
          0,
          AnswerLine(
              const AssistantText(
                  'Odniesienie wymiarów', 'Dimension reference'),
              reference.of(ctx.lang)));
    } on FormatException {
      return const FailedResult(
          AssistantText(
              'Bieżący formularz ma niepełne lub nieprawidłowe dane. Popraw je przed odczytaniem wyniku.',
              'The current form has incomplete or invalid inputs. Correct them before reading a result.'),
          reportMissingCapability: false);
    }
    if (m.slots['query'] == 'height') {
      return AnswerResult(AssistantAnswer(
          text: AssistantText('Bieżąca wysokość wynosi ${number(height)} mm.',
              'The current height is ${number(height)} mm.')));
    }
    lines.insert(
        0,
        AnswerLine(
            const AssistantText('Wysokość', 'Height'), '${number(height)} mm'));
    return AnswerResult(AssistantAnswer(
        text: AssistantText(
            '${shape.pl} Odczyt z aktualnego kalkulatora; dla blachy sprawdź zastosowane przybliżenie osi obojętnej.',
            '${shape.en} Read from the current calculator; for plate check its neutral-surface approximation.'),
        lines: lines));
  }
}
