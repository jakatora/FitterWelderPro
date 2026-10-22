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
    final proposed = parseIsoCommand(command);
    if (proposed?.kind != IsoCommandKind.setRootGap) return false;
    final literal = parseIsoCommand(original);
    if (literal?.kind == IsoCommandKind.setRootGap) {
      return literal!.gapMm == proposed!.gapMm;
    }
    if (RegExp(r'[-−]\s*\d|\bminus\b').hasMatch(original.raw.toLowerCase()) ||
        original.hasAny(const ['albo', 'lub', 'or', 'either']) ||
        !original.hasStem(const ['szczelin', 'gap']) ||
        !RegExp(r'^(?:(?:prosze|please)\s+)*(?:ustaw|zmien|zmniejsz|zwieksz|set|change|reduce|decrease|increase)\b')
            .hasMatch(original.folded) ||
        !RegExp(r'(?:\b|\d)(?:mm|cm|m|milimetr\w*|centymetr\w*|metr\w*|millimet\w*|centimet\w*|meter\w*|metre\w*)\b')
            .hasMatch(original.folded)) {
      return false;
    }
    if (!(original.hasAny(const ['iso']) &&
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
}
