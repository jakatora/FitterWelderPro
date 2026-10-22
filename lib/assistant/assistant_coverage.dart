import '../widgets/tool_registry.dart';
import 'core/skill.dart';
import 'skills/skill_catalog.dart';

/// Highest registered capability per module: open/explain, calculate, write,
/// draw. This describes the supplied session catalog, not every action on a
/// page. Modules with no specialized skill remain at level A.
///
/// Pass the live catalog when legacy actions are connected. The default
/// catalog includes writes backed by local module stores; legacy journal and
/// parameter writes require their separate persistence port.
/// Drawing is tier D only when the session has a connected ISO drawing port.
Map<String, AssistantTier> assistantCoverage({
  Iterable<AssistantSkill>? skills,
  Iterable<ToolSpec>? tools,
}) {
  final coverage = <String, AssistantTier>{
    for (final tool in tools ?? kToolRegistry) tool.id: AssistantTier.a,
  };
  final catalog = (skills ?? buildSkillCatalog()).toList(growable: false);
  final canDraw = catalog.any((s) =>
      s.id == 'iso.draw' &&
      s.toolId == 'iso_notebook' &&
      s.tier == AssistantTier.d);
  for (final skill in catalog) {
    final id = skill.toolId;
    final previous = coverage[id];
    // Naming, dimensions and summaries alone do not confer drawing support.
    final tier =
        id == 'iso_notebook' && !canDraw && skill.tier == AssistantTier.d
            ? AssistantTier.a
            : skill.tier;
    if (id != null && previous != null && tier.index > previous.index) {
      coverage[id] = tier;
    }
  }
  return Map.unmodifiable(coverage);
}
