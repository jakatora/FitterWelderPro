import '../../../domain/ferrite_pmi/ferrite.dart';
import '../../../domain/ferrite_pmi/ferrite_pmi_sources.dart';
import '../../core/skill.dart';
import '../core/explain_tool_skill.dart' show explainedTool;

/// Typowe wymagane zakresy ferrytu z presetów modułu „Ferryt i PMI”
/// (zawsze: decyduje specyfikacja projektu). Protokół zostaje w module.
class FerriteRangeSkill extends AssistantSkill {
  @override
  String get id => 'ferrite.range';
  @override
  String get toolId => 'ferrite_pmi';
  @override
  AssistantTier get tier => AssistantTier.b;
  @override
  bool get readOnly => true;
  @override
  List<SkillExample> get examples => const [
        SkillExample('Jaki zakres ferrytu dla duplex', 'What ferrite range for duplex'),
        SkillExample('Ile ferrytu w spoinie 316L', 'How much ferrite in a 316L weld'),
        SkillExample('Ferryt w spoinie austenitycznej wymagania',
            'Ferrite requirements in an austenitic weld'),
        SkillExample('Zakres FN dla super duplex', 'FN range for super duplex'),
        SkillExample('Jaki ferryt w spoinie 304', 'What ferrite in a 304 weld'),
        SkillExample('Wymagany ferryt', 'Required ferrite'),
      ];
  @override
  List<SkillRejection> get rejections => const [
        SkillRejection('otwórz ferryt i PMI', routesTo: 'tool.open'),
        SkillRejection('do czego służy ferryt i PMI', routesTo: 'tool.explain'),
        SkillRejection('jakie spoiwo dać do stali 316L'),
      ];

  @override
  SkillMatch? match(Utterance u, AssistantContext ctx) {
    if (explainedTool(u) != null ||
        RegExp(r'^(?:otworz|open|do czego)\b').hasMatch(u.folded)) {
      return null;
    }
    if (!u.hasStem(const ['ferryt', 'ferrite']) && !u.hasAny(const ['fn'])) {
      return null;
    }
    final group = u.hasStem(const ['duplex', 'dupleks'])
        ? FerritePresetGroup.duplex
        : RegExp(r'\b30[4]l?\b|\b31[6]l?\b|\b321\b|\b347\b|\baustenit')
                .hasMatch(u.folded)
            ? FerritePresetGroup.austenitic
            : null;
    return SkillMatch(this, .9,
        slots: {if (group != null) 'group': group.name}, utterance: u);
  }

  @override
  Map<String, Object?>? fillSlot(
      String slot, Utterance u, AssistantContext ctx) {
    if (slot != 'group') return null;
    if (u.hasStem(const ['duplex', 'dupleks'])) return {'group': 'duplex'};
    if (u.hasStem(const ['austenit', 'nierdzew', 'stainless']) ||
        RegExp(r'\b30[4]|\b31[6]').hasMatch(u.folded)) {
      return {'group': 'austenitic'};
    }
    return null;
  }

  @override
  Future<SkillResult> run(SkillMatch m, AssistantContext ctx) async {
    final group = FerritePresetGroup.values
        .where((g) => g.name == m.slots['group'])
        .firstOrNull;
    if (group == null) {
      return AskResult(
          'group',
          const AssistantText('Dla jakiego materiału: duplex czy austenityczna (304/316)?',
              'For which material: duplex or austenitic (304/316)?'),
          partial: m);
    }
    final presets = kFerritePresets.where((p) => p.group == group).toList();
    if (presets.isEmpty) {
      return const FailedResult(AssistantText(
          'Moduł nie ma presetu dla tej grupy.', 'The module has no preset for this group.'));
    }
    String list(bool en) => presets
        .map((p) =>
            '${p.title(en: en)}: ${p.requirement.text(en: en)} (${p.source(en: en)})')
        .join('; ');
    return AnswerResult(
        AssistantAnswer(
            text: AssistantText(
                'Typowe wymagania: ${list(false)}. Decyduje specyfikacja projektu; protokół pomiarów zrobisz w module.',
                'Typical requirements: ${list(true)}. The project specification governs; record the readings in the module.')),
        show: ShowInModule(toolId));
  }
}
