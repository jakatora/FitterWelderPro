import '../own_data/my_params_skill.dart';
// Katalog grupy „core": pilotażowe umiejętności rdzenia (plan 1.3).

import '../../core/assistant_actions_port.dart';
import '../../core/skill.dart';
import 'capabilities_skill.dart';
import 'calculator_action_skill.dart';
import 'explain_tool_skill.dart';
import 'knowledge_skill.dart';
import 'legacy_intents_skill.dart';
import 'open_tool_skill.dart';
import 'pipe_od_skill.dart';
import 'pipe_wall_skill.dart';

/// Umiejętności rdzenia.
///
/// [actions] — zapisy (parametr spawania, dziennik). Bez nich katalog NIE ma
/// umiejętności `legacy.*`: polecenie zapisu nie trafi wtedy w mózg i pójdzie
/// dalej (do starego silnika w AiChatScreen).
///
/// [catalog] — cały katalog aplikacji (dla „co umiesz" i „do czego służy");
/// domyślnie tylko ta grupa.
List<AssistantSkill> coreSkills({
  AssistantActionsPort? actions,
  SavedParamsReader? savedParams,
  Iterable<AssistantSkill> Function()? catalog,
}) {
  final out = <AssistantSkill>[];
  Iterable<AssistantSkill> all() => catalog?.call() ?? out;
  out.addAll([
    PipeOdSkill(),
    PipeWallSkill(),
    CalculatorActionSkill(),
    MyParamsSkill(load: savedParams),
    if (actions != null) ...[
      LegacyIntentsSkill.weldParam(actions),
      LegacyIntentsSkill.journal(actions),
    ],
    CapabilitiesSkill(all),
    OpenToolSkill(),
    ExplainToolSkill(all),
    KnowledgeSkill(),
  ]);
  return out;
}
