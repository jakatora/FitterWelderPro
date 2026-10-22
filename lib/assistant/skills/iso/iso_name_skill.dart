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
          ? SkillMatch(this, .99, utterance: u, explicitToolTarget: true)
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
    final names =
        RegExp(r'["„“]([^"”]+)["”]').allMatches(original.raw).toList();
    if (names.length != 1 || names.single[1]!.trim() != proposed!.sketchName) {
      return false;
    }
    final name = names.single;
    // Treat the title as literal data. Words such as "czy" or "how" inside it
    // do not turn a request into a question; trailing actions are not ignored.
    if (!RegExp(r'^[\s.!?]*$').hasMatch(original.raw.substring(name.end))) {
      return false;
    }
    final prefix =
        original.withRaw(original.raw.substring(0, name.start)).folded;
    return RegExp(
            r'^(?:(?:(?:chce|chcialbym|chcialabym) |prosze |(?:(?:czy )?mozesz|czy moglbys|czy moglabys) (?:prosze )?)(?:(?:nazwac|nazwij) (?:ten |te |ta |tym )?(?:rysunek|szkic|izometrie)(?: jako| na)?|(?:zmienic|zmien) nazwe (?:tego )?(?:rysunku|szkicu|izometrii) na)|(?:(?:i want to|i would like to|please|can you|could you|would you) )(?:please )?(?:(?:name|call) (?:this |the )?(?:drawing|sketch)(?: as)?|rename (?:this |the )?(?:drawing|sketch)(?: to)?))$')
        .hasMatch(prefix);
  }

  @override
  Future<SkillResult> run(SkillMatch match, AssistantContext ctx) =>
      port.execute(match.utterance!);
}
