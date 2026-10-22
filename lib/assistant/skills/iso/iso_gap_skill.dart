import '../../core/skill.dart';
import '../../../domain/iso_notebook/sketch_settings.dart';
import 'iso_command_parser.dart';
import 'iso_draw_skill.dart';

class IsoGapSkill extends AssistantSkill {
  IsoGapSkill(this.port);
  final IsoDrawingPort port;
  @override
  String get id => 'iso.gap';
  @override
  String get toolId => 'iso_notebook';
  @override
  AssistantTier get tier => AssistantTier.d;
  @override
  bool get readOnly => false;
  @override
  List<SkillExample> get examples => const [
        SkillExample('Ustaw szczelinę w tym rysunku na 3 mm',
            'Set weld gap in this drawing to 3 mm'),
        SkillExample('Ustaw szczelinę ISO na 0 mm', 'Set gap in ISO to 0 mm'),
        SkillExample('Zmień szczelinę spoiny w szkicu na 2,5 mm',
            'Change root gap in the sketch to 2.5 mm'),
      ];
  @override
  SkillMatch? match(Utterance u, AssistantContext ctx) {
    if (parseIsoCommand(u)?.kind == IsoCommandKind.setRootGap) {
      return SkillMatch(this, .99, utterance: u, explicitToolTarget: true);
    }
    // A typo in an explicitly named ISO setting must not edit the calculator
    // underneath the assistant instead. Retain its target and validate locally.
    if (RegExp(
            r'^(?:(?:prosze|please)\s+)*(?:(?:ustaw|zmien) szczeline (?:spoiny )?(?:w (?:tym )?(?:rysunku|szkicu|iso)|iso) na|(?:set|change) (?:(?:weld|root) )?gap (?:in|for) (?:the |this )?(?:drawing|sketch|iso) to)\b')
        .hasMatch(u.folded)) {
      return SkillMatch(this, .99,
          utterance: u,
          explicitToolTarget: true,
          slots: const {'invalid_gap': true});
    }
    return null;
  }

  @override
  Future<SkillResult> run(SkillMatch match, AssistantContext ctx) async {
    if (match.slots['invalid_gap'] == true) {
      final max = kSketchMaxGapMm.toStringAsFixed(0);
      return FailedResult(AssistantText(
          'Podaj jedną szczelinę ISO od 0 do $max mm, z jednostką. Rysunek i pozostałe pola są bez zmian.',
          'Give one ISO weld gap from 0 to $max mm, with its unit. The drawing and other inputs are unchanged.'));
    }
    return port.execute(match.utterance!);
  }

  @override
  bool acceptsProposal(
      Utterance original, Utterance command, AssistantContext context) {
    // Retain the unmodified source for signs: folded speech drops punctuation.
    if (RegExp(r'[-−]\s*\d|\bminus\b').hasMatch(original.raw.toLowerCase())) {
      return false;
    }
    original = _requestedAction(original);
    final proposed = parseIsoCommand(command);
    if (proposed?.kind != IsoCommandKind.setRootGap) return false;
    final literal = parseIsoCommand(original);
    if (literal?.kind == IsoCommandKind.setRootGap) {
      return literal!.gapMm == proposed!.gapMm;
    }
    final indirect = _hasBoundReference(context) && _isPronounRequest(original);
    if (original.hasAny(const ['albo', 'lub', 'or', 'either']) ||
        (!original.hasStem(const ['szczelin', 'gap']) && !indirect) ||
        !RegExp(r'^(?:(?:prosze|please)\s+)*(?:ustaw|zmien|zmniejsz|zwieksz|set|change|reduce|decrease|increase)\b')
            .hasMatch(original.folded) ||
        !RegExp(r'(?:\b|\d)(?:mm|cm|m|milimetr\w*|centymetr\w*|metr\w*|millimet\w*|centimet\w*|meter\w*|metre\w*)\b')
            .hasMatch(original.folded)) {
      return false;
    }
    if (!indirect &&
        !(original.hasAny(const ['iso']) &&
            !RegExp(r'\biso\s*\d').hasMatch(original.folded)) &&
        !original.hasStem(const [
          'rysun',
          'szkic',
          'drawing',
          'sketch',
          'izometr',
          'isometric'
        ])) {
      return false;
    }
    final amount = original.lengthMm();
    if (amount == null) return false;
    var expected = amount;
    if (original.hasAny(const ['o', 'by'])) {
      if (original.hasAny(const ['do', 'to', 'na']) ||
          context.modules.activeToolId != toolId ||
          context.modules is! FieldModuleContext) {
        return false;
      }
      final current = (context.modules as FieldModuleContext)
          .inputFields(toolId)?['gap_mm'];
      if (current is! num || !isValidSketchGapMm(current)) return false;
      final decrease = original.hasStem(const ['zmniejsz', 'decreas', 'reduc']);
      final increase = original.hasStem(const ['zwieksz', 'increas']);
      if (decrease == increase) return false;
      expected = current.toDouble() + (decrease ? -amount : amount);
    }
    return isValidSketchGapMm(expected) &&
        (expected - proposed!.gapMm!).abs() < 1e-9;
  }

  /// Normalize only a request addressed to the assistant. Questions about
  /// permission, instructions and hypothetical changes remain questions.
  Utterance _requestedAction(Utterance original) {
    final request = RegExp(
            r'^(?:(?:czy )?mozesz|czy moglbys|czy moglabys|can you|could you|would you) (?:prosze |please )?(ustawic|zmienic|zmniejszyc|zwiekszyc|ustaw|zmien|zmniejsz|zwieksz|set|change|reduce|decrease|increase) (.+)$')
        .firstMatch(original.folded);
    if (request == null) return original;
    const verbs = {
      'ustawic': 'ustaw',
      'zmienic': 'zmien',
      'zmniejszyc': 'zmniejsz',
      'zwiekszyc': 'zwieksz',
    };
    return original.withRaw('${verbs[request[1]] ?? request[1]} ${request[2]}');
  }

  bool _hasBoundReference(AssistantContext context) {
    if (context.modules.activeToolId != toolId ||
        !port.isForeground ||
        port is! IsoReferencePort) {
      return false;
    }
    final reference = (port as IsoReferencePort).reference;
    final previous = context.recentMatch();
    return reference != null &&
        previous?.skill.id == id &&
        previous!.slots['iso_gap_sheet_id'] == reference.id &&
        previous.slots['iso_gap_sheet_revision'] == reference.revision &&
        previous.slots['iso_gap_reference_generation'] ==
            context.actionReferenceGeneration;
  }

  @override
  AssistantText? proposalRejectionHint(
          Utterance original, Utterance command, AssistantContext context) =>
      _isPronounRequest(original) && !_hasBoundReference(context)
          ? const AssistantText(
              'Co mam zmniejszyć lub zwiększyć? Podaj pełne polecenie z nazwą pola, np. „zmniejsz szczelinę w ISO o 1 mm”. Niczego nie zmieniłem.',
              'What should I decrease or increase? Give the complete request with the field name, e.g. “decrease the gap in ISO by 1 mm”. Nothing was changed.')
          : null;

  bool _isPronounRequest(Utterance original) {
    original = _requestedAction(original);
    final match = RegExp(
            r'^(?:(?:prosze|please)\s+)*(?:(?:zmniejsz|zwieksz) (?:ja|jej|to) o|(?:decrease|reduce|increase) (?:it|that) by) (.+)$')
        .firstMatch(original.folded);
    if (match == null) return false;
    final quantity = original.withRaw(match[1]!).items;
    return quantity.length == 2 &&
        quantity.first.isNumber &&
        RegExp(r'^(?:mm|cm|m|milimetr\w*|centymetr\w*|metr\w*|millimet\w*|centimet\w*|meter\w*|metre\w*)$')
            .hasMatch(quantity.last.word);
  }
}
