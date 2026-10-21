import '../widgets/tool_registry.dart';
import 'core/skill.dart';
import 'skills/skill_catalog.dart';

/// Highest registered capability per module: open/explain, calculate, write,
/// draw. This describes the supplied session catalog, not every action on a
/// page. Modules with no specialized skill remain at level A.
///
/// Pass the live catalog when actions are connected; the default catalog has
/// no persistence port and therefore does not advertise record writes.
/// ISO's separate UI command handler is deliberately not inferred as tier D.
Map<String, AssistantTier> assistantCoverage({
  Iterable<AssistantSkill>? skills,
  Iterable<ToolSpec>? tools,
}) {
  final coverage = <String, AssistantTier>{
    for (final tool in tools ?? kToolRegistry) tool.id: AssistantTier.a,
  };
  for (final skill in skills ?? buildSkillCatalog()) {
    final id = skill.toolId;
    final previous = coverage[id];
    if (id != null && previous != null && skill.tier.index > previous.index) {
      coverage[id] = skill.tier;
    }
  }
  return Map.unmodifiable(coverage);
}
