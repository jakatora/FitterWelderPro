import '../../core/skill.dart';
import '../core/explain_tool_skill.dart' show explainedTool;

String? _process(Utterance u) {
  final f = u.folded;
  if (RegExp(r'\borbital\w*').hasMatch(f)) return 'tig-orb';
  if (RegExp(r'\btig\w*|\b141\b').hasMatch(f)) return 'tig-man';
  if (RegExp(r'\bmma\b|\b111\b|\belektrod\w*|\bstick\b').hasMatch(f)) return 'mma';
  if (RegExp(r'\bmag\b|\bmigomag\w*|\b13[568]\b').hasMatch(f)) return 'mag';
  return null;
}

const _labels = {
  'tig-orb': ('TIG orbitalny', 'orbital TIG'),
  'tig-man': ('TIG ręczny', 'manual TIG'),
  'mma': ('MMA (111)', 'MMA (111)'),
  'mag': ('MAG (135/136)', 'MAG (135/136)'),
};

/// Otwiera listę kontrolną przed spawaniem z właściwym procesem. Punktów
/// bezpieczeństwa asystent nie odhacza — robi to spawacz na ekranie.
class PreweldChecklistSkill extends AssistantSkill {
  @override
  String get id => 'checklist.preweld';
  @override
  String get toolId => 'pre_weld_checklist';
  @override
  AssistantTier get tier => AssistantTier.b;
  @override
  List<SkillExample> get examples => const [
        SkillExample('Lista kontrolna przed spawaniem TIG', 'Pre-weld checklist TIG'),
        SkillExample('Co sprawdzić przed spawaniem migomagiem',
            'What to check before MAG welding'),
        SkillExample('Checklista przed spawaniem orbitalnym',
            'Checklist before orbital welding'),
        SkillExample('Lista przed spawaniem elektrodą', 'Checklist before stick welding'),
        SkillExample('Sprawdzenie przed spawaniem 141', 'Check before welding 141'),
        SkillExample('Lista kontrolna przed spawaniem', 'Pre-weld checklist'),
      ];
  @override
  List<SkillRejection> get rejections => const [
        SkillRejection('otwórz checklistę przed spawaniem', routesTo: 'tool.open'),
        SkillRejection('do czego służy checklista przed spawaniem',
            routesTo: 'tool.explain'),
        SkillRejection('czy mogę spawać temperatura 20 stopni wilgotność 60% wiatr 1 m/s TIG'),
      ];

  @override
  SkillMatch? match(Utterance u, AssistantContext ctx) {
    if (explainedTool(u) != null ||
        RegExp(r'^(?:otworz|open|do czego)\b').hasMatch(u.folded)) {
      return null;
    }
    final before = u.hasAny(const ['przed spawaniem', 'pre weld', 'pre-weld']) ||
        u.hasStem(const ['preweld']) ||
        (u.hasAny(const ['before']) && u.hasStem(const ['weld']));
    final list = u.hasStem(const ['list', 'check', 'sprawdz', 'kontrol']);
    if (!before || !list) return null;
    if (u.hasStem(const ['wiatr', 'wilgotn', 'wind', 'humid', 'skurcz', 'shrink'])) {
      return null;
    }
    final p = _process(u);
    return SkillMatch(this, .95, slots: {if (p != null) 'process': p}, utterance: u);
  }

  @override
  Map<String, Object?>? fillSlot(
          String slot, Utterance u, AssistantContext ctx) =>
      slot == 'process' && _process(u) != null ? {'process': _process(u)} : null;

  @override
  Future<SkillResult> run(SkillMatch m, AssistantContext ctx) async {
    final p = m.slots['process'];
    final label = _labels[p];
    if (label == null) {
      return AskResult(
          'process',
          const AssistantText('Dla jakiego procesu: TIG ręczny, TIG orbitalny, MMA czy MAG?',
              'For which process: manual TIG, orbital TIG, MMA or MAG?'),
          partial: m);
    }
    return AnswerResult(
        AssistantAnswer(
            text: AssistantText(
                'Otwieram listę kontrolną przed spawaniem — ${label.$1}. Punkty odhaczasz sam na ekranie; asystent ich nie zaznacza.',
                'Opening the pre-weld checklist — ${label.$2}. Tick the items yourself on screen; the assistant does not mark them.')),
        show: ShowInModule(toolId, {'process': p}));
  }
}
