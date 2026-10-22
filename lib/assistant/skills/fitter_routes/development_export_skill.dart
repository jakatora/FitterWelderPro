import '../../core/skill.dart';
import '../../core/command_words.dart';

bool _requested(Utterance u, {bool natural = false}) {
  if (referencesInstruction(u) || isNegatedCommand(u)) return false;
  final text = u.folded.replaceFirst(RegExp(r'^(?:prosze |please )'), '');
  if (RegExp(
          r'^(?:przygotuj pdf biezacego rozwiniecia|eksportuj szablon pdf|wydrukuj biezace rozwiniecie|prepare pdf of current development|export template pdf|print current development)$')
      .hasMatch(text)) {
    return true;
  }
  return natural &&
      RegExp(r'^(?:potrzebuje szablonu pdf aktualnego rozwiniecia|i need a pdf template of the current development)$')
          .hasMatch(text);
}

class DevelopmentExportSkill extends AssistantSkill {
  @override
  String get id => 'development.export';
  @override
  String get toolId => 'cone_layout';
  @override
  AssistantTier get tier => AssistantTier.a;
  @override
  List<SkillExample> get examples => const [
        SkillExample('Przygotuj PDF bieżącego rozwinięcia',
            'Prepare PDF of current development'),
        SkillExample('Eksportuj szablon PDF', 'Export template PDF'),
        SkillExample(
            'Wydrukuj bieżące rozwinięcie', 'Print current development'),
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
      _requested(original, natural: true) && _requested(command);
  @override
  Future<SkillResult> run(SkillMatch m, AssistantContext ctx) async {
    final modules = ctx.modules;
    if (modules.activeToolId != toolId || modules is! ModuleActionContext) {
      return const AnswerResult(
          AssistantAnswer(
              text: AssistantText(
                  'Otwórz rozwinięcie, które chcesz przygotować do druku.',
                  'Open the development you want to prepare for printing.')),
          actionCompleted: false);
    }
    final result = await (modules as ModuleActionContext)
        .performModuleAction(toolId, 'export_pdf');
    return AnswerResult(AssistantAnswer(text: result.message),
        actionCompleted: result.completed);
  }
}
