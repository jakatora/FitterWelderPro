import '../../core/skill.dart';
import '../../core/command_words.dart';

bool _requested(Utterance u) =>
    !referencesInstruction(u) &&
    RegExp(r'^(?:(?:prosze|please) )?(?:cofnij|cofnij te zmiane|cofnij ostatnia zmiane rozwiniecia|undo|undo this change|undo last development change)$')
        .hasMatch(u.folded);

class DevelopmentUndoSkill extends AssistantSkill {
  @override
  String get id => 'development.undo';
  @override
  String get toolId => 'cone_layout';
  @override
  AssistantTier get tier => AssistantTier.a;
  @override
  List<SkillExample> get examples => const [
        SkillExample('Cofnij ostatnią zmianę rozwinięcia',
            'Undo last development change'),
        SkillExample('Cofnij tę zmianę', 'Undo this change'),
        SkillExample('Cofnij', 'Undo'),
      ];
  @override
  SkillMatch? match(Utterance u, AssistantContext ctx) {
    final active = ctx.modules.activeToolId;
    if (active != null && active != toolId) return null;
    return _requested(u) ? SkillMatch(this, .99, utterance: u) : null;
  }

  @override
  bool acceptsProposal(
          Utterance original, Utterance command, AssistantContext context) =>
      _requested(original) && _requested(command);
  @override
  Future<SkillResult> run(SkillMatch m, AssistantContext ctx) async {
    final modules = ctx.modules;
    if (modules.activeToolId != toolId || modules is! ModuleActionContext) {
      return const AnswerResult(
          AssistantAnswer(
              text: AssistantText(
                  'Otwórz rozwinięcie, którego zmianę chcesz cofnąć.',
                  'Open the development whose change you want to undo.')),
          actionCompleted: false);
    }
    final result = await (modules as ModuleActionContext)
        .performModuleAction(toolId, 'undo');
    return AnswerResult(AssistantAnswer(text: result.message),
        actionCompleted: result.completed);
  }
}
