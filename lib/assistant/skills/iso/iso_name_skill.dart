import '../../core/skill.dart';
import 'iso_command_parser.dart';
import 'iso_draw_skill.dart';

/// The sheet name is literal user data, never rewritten or inferred by AI.
class IsoNameSkill extends AssistantSkill {
  IsoNameSkill(this.port);
  final IsoDrawingPort port;
  @override
  String get id => 'iso.name';
  @override
  String get toolId => 'iso_notebook';
  @override
  AssistantTier get tier => AssistantTier.d;
  @override
  bool get readOnly => false;
  @override
  List<SkillExample> get examples => const [
        SkillExample('Nazwij rysunek Linia CW-123', 'Name drawing Line CW-123'),
        SkillExample('Zmień nazwę rysunku na Magistrala pary',
            'Rename drawing to Steam main'),
        SkillExample('Nazwij tę izometrię „Rurociąg chłodzący”',
            'Name this drawing “Cooling pipe”'),
      ];
  @override
  SkillMatch? match(Utterance u, AssistantContext ctx) =>
      parseIsoCommand(u)?.kind == IsoCommandKind.renameSketch
          ? SkillMatch(this, .99, utterance: u)
          : null;
  @override
  bool acceptsProposal(
      Utterance original, Utterance command, AssistantContext context) {
    final source = parseIsoCommand(original),
        proposed = parseIsoCommand(command);
    if (proposed?.kind != IsoCommandKind.renameSketch) return false;
    if (source?.kind == IsoCommandKind.renameSketch) {
      return source!.sketchName == proposed!.sketchName;
    }
    if (!RegExp(r'^(?:chce|chcialbym|chcialabym|prosze|please|i want|i would like)\b')
            .hasMatch(original.folded) ||
        !original.hasStem(const ['nazw', 'nazyw', 'name', 'renam', 'call']) ||
        original.hasAny(const ['jak', 'czy', 'how', 'which', 'whether'])) {
      return false;
    }
    final names =
        RegExp(r'["„“]([^"”]+)["”]').allMatches(original.raw).toList();
    return names.length == 1 && names.single[1]!.trim() == proposed!.sketchName;
  }

  @override
  Future<SkillResult> run(SkillMatch match, AssistantContext ctx) =>
      port.execute(match.utterance!);
}
