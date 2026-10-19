// Katalog wszystkich umiejętności asystenta = suma katalogów grup.
//
// Każda grupa rejestruje się we własnym `skills/<grupa>/catalog.dart`;
// koordynator dopisuje ją TUTAJ po scaleniu i uruchamia globalny test
// routera (test/assistant/router_corpus_test.dart), który łapie kolizje
// zamiarów między grupami.

import '../core/assistant_actions_port.dart';
import '../core/skill.dart';
import 'core/catalog.dart';

/// Pełny katalog. [actions] — zapisy (bez nich brak umiejętności `legacy.*`).
List<AssistantSkill> buildSkillCatalog({AssistantActionsPort? actions}) {
  final all = <AssistantSkill>[];
  Iterable<AssistantSkill> catalog() => all;
  all.addAll(coreSkills(actions: actions, catalog: catalog));
  // Kolejne grupy (koordynator):
  //   all.addAll(fitterTablesSkills());   // 2.1
  //   all.addAll(fitterRoutesSkills());   // 2.2
  //   all.addAll(welderCalcSkills());     // 2.3
  //   all.addAll(welderMiscSkills());     // 2.4
  //   all.addAll(knowledgeModuleSkills());// 2.5
  //   all.addAll(isoSkills());            // 3.2
  return List.unmodifiable(all);
}
