import '../i18n/app_language.dart';
import 'assistant_ai_client.dart';
import 'ai_execution_queue.dart';
import 'core/skill.dart';
import 'skills/core/calculator_action_skill.dart';
import 'skills/core/open_tool_skill.dart';

/// Validate implicit navigation before any step runs. A named clear/copy cannot
/// be reduced to opening a screen, or followed by a different operation.
bool validNavigationPrerequisites(
    String source, List<AiCommandStep> steps, AppLanguage lang) {
  final clauses = steps.length == 1 ? [source] : aiSourceClauses(source);
  if (clauses == null ||
      steps.isEmpty ||
      clauses.length > 1 && clauses.length != steps.length) {
    return false;
  }
  final open = OpenToolSkill(), calculator = CalculatorActionSkill();
  for (var i = 0; i < steps.length; i++) {
    if (steps[i].skillId != open.id) continue;
    final original =
        Utterance(clauses.length == 1 ? source : clauses[i], lang: lang);
    final requirement = calculatorNavigationPrerequisite(original);
    if (requirement == null) continue;
    if (clauses.length != 1 ||
        i + 1 >= steps.length ||
        steps[i + 1].skillId != calculator.id) {
      return false;
    }
    final ctx = AssistantContext(
        lang: lang,
        modules: FixedModuleContext(activeToolId: requirement.toolId));
    final command = Utterance(steps[i].command, lang: lang);
    if (open.match(command, ctx)?.slots['tool'] != requirement.toolId ||
        !open.acceptsProposal(original, command, ctx)) {
      return false;
    }
    final following = Utterance(steps[i + 1].command, lang: lang);
    if (calculator.match(following, ctx)?.slots['module_action'] !=
            requirement.action ||
        !calculator.acceptsProposal(original, following, ctx)) {
      return false;
    }
  }
  return true;
}
