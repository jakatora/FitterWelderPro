import '../../core/skill.dart';
import 'iso_command_parser.dart';
import 'iso_draw_skill.dart';

/// A separate capability advertises editing without removing drawing examples.
class IsoDimensionSkill extends AssistantSkill {
  IsoDimensionSkill(this.port);
  final IsoDrawingPort port;
  @override
  String get id => 'iso.dimension';
  @override
  String get toolId => 'iso_notebook';
  @override
  AssistantTier get tier => AssistantTier.d;
  @override
  bool get readOnly => false;
  @override
  List<SkillExample> get examples => const [
        SkillExample('Zmień wymiar ISO ostatniej rury na 500 mm',
            'Set ISO dimension of last pipe to 500 mm'),
        SkillExample('Zmień wymiar ISO rury numer 2 na 1500 mm',
            'Set ISO dimension of pipe number 2 to 1500 mm'),
        SkillExample('Ustaw wymiar ISO rury numer 1 na 2 m',
            'Set ISO dimension of pipe number 1 to 2 m'),
      ];
  @override
  SkillMatch? match(Utterance u, AssistantContext ctx) =>
      parseIsoCommand(u)?.kind == IsoCommandKind.setPipeDimension
          ? SkillMatch(this, .99, utterance: u, explicitToolTarget: true)
          : null;
  @override
  Future<SkillResult> run(SkillMatch match, AssistantContext ctx) =>
      port.execute(match.utterance!);

  @override
  bool acceptsProposal(
          Utterance original, Utterance command, AssistantContext context) =>
      acceptsIsoDimensionProposal(original, command);
}

/// A model may normalize prose, never choose another pipe or change a number.
bool acceptsIsoDimensionProposal(Utterance original, Utterance command) {
  if (original.hasAny(const ['albo', 'lub', 'or', 'either'])) return false;
  if (RegExp(r'[-−]\s*\d|\bminus\b').hasMatch(original.raw.toLowerCase())) {
    return false;
  }
  // A model's execute plan does not override the user's negation or turn
  // advice/permission questions into mutations. Preserve declarative requests.
  if (_dimensionSourceIsQuestionOrNegation(original)) return false;
  final proposed = parseIsoCommand(command);
  if (proposed?.kind != IsoCommandKind.setPipeDimension) return false;
  final literal = parseIsoCommand(original);
  if (literal?.kind == IsoCommandKind.setPipeDimension) {
    return literal!.dimensionMm == proposed!.dimensionMm &&
        literal.pipeOrdinal == proposed.pipeOrdinal;
  }
  if (!RegExp(
          r'(?:\b|\d)(?:mm|cm|m|milimetr\w*|centymetr\w*|metr\w*|millimet\w*|centimet\w*|meter\w*|metre\w*)\b')
      .hasMatch(original.folded)) {
    return false;
  }
  final length = original
      .withRaw(original.raw.replaceAll(
          RegExp(r'\bhalf\s+(?:a\s+)?(?:meter|metre)\b', caseSensitive: false),
          '0.5 m'))
      .lengthMm();
  if (length == null || length <= 0 || length != proposed!.dimensionMm) {
    return false;
  }
  final last =
      original.hasStem(const ['ostatni']) || original.hasAny(const ['last']);
  final ordinals = <int>{};
  const words = <int, List<String>>{
    1: ['pierwsz', 'first'],
    2: ['drugi', 'second'],
    3: ['trzeci', 'third'],
    4: ['czwart', 'fourth'],
    5: ['piat', 'fifth'],
    6: ['szost', 'sixth'],
    7: ['siodm', 'seventh'],
    8: ['osm', 'eighth'],
    9: ['dziewiat', 'ninth'],
    10: ['dziesiat', 'tenth']
  };
  for (final entry in words.entries) {
    if (original.hasStem(entry.value)) ordinals.add(entry.key);
  }
  for (final match
      in RegExp(r'\b(?:numer|number|rur\w*|odcinek\w*|pipe|segment)\s+(\d+)\b')
          .allMatches(original.folded)) {
    ordinals.add(int.parse(match[1]!));
  }
  return last
      ? proposed.pipeOrdinal == null && ordinals.isEmpty
      : ordinals.length == 1 && ordinals.single == proposed.pipeOrdinal;
}

bool _dimensionSourceIsQuestionOrNegation(Utterance source) {
  if (RegExp(r"\b[a-z]+n['’]t\b", caseSensitive: false).hasMatch(source.raw)) {
    return true;
  }
  if (source.hasAny(
          const ['nie', 'nigdy', 'not', 'dont', 'never', 'jak', 'how']) ||
      source.hasStem(const ['wyjasn', 'explain'])) {
    return true;
  }
  final text = source.folded.replaceFirst(RegExp(r'^(?:prosze|please)\s+'), '');
  final addressedRequest = RegExp(
          r'^(?:(?:czy )?mozesz|czy moglbys|czy moglabys) (?:prosze )?(?:zmienic|zmien|ustawic|ustaw|skrocic|skroc|wydluzyc|wydluz)\b|^(?:can|could|would|will) you (?:please )?(?:set|change|make|shorten|lengthen)\b')
      .hasMatch(text);
  if (addressedRequest) return false;
  return source.raw.trimRight().endsWith('?') ||
      RegExp(r'^(?:czy|jak|dlaczego|kiedy|ktory|jaki|can|could|would|will|should|is|are|does|do|what|why|when|which)\b')
          .hasMatch(text);
}
