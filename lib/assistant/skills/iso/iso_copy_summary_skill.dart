import '../../../i18n/app_language.dart';
import '../../core/skill.dart';
import '../../core/command_words.dart';

bool _requested(Utterance u, {bool natural = false}) {
  if (referencesInstruction(u) ||
      isNegatedCommand(u) ||
      RegExp(r'\b(?:nie|not|never|dont|don t)\b|["„“”]').hasMatch(u.folded)) {
    return false;
  }
  final text = u.folded.replaceFirst(RegExp(r'^(?:prosze |please )'), '');
  if (const [
    'skopiuj zestawienie rysunku iso',
    'kopiuj zestawienie biezacego rysunku iso',
    'copy current iso drawing summary',
    'copy iso drawing summary to clipboard'
  ].contains(text)) {
    return true;
  }
  if (!natural) return false;
  if (u.items.any((i) => i.isNumber) ||
      Utterance(u.raw, lang: AppLanguage.en).items.any((i) => i.isNumber) ||
      u.hasStem(const [
        'tylko',
        'otworz',
        'open',
        'narysuj',
        'rysuj',
        'wyczysc',
        'clear',
        'reset',
        'only',
        'without',
        'bez',
        'selected',
        'wybran',
        'klient',
        'client',
        'email',
        'wyslij',
        'send',
        'udostepnij',
        'share',
        'usun',
        'delete',
        'zmien',
        'change',
        'format',
        'pdf',
        'csv',
        'excel',
        'poprzedn',
        'previous',
        'first',
        'second',
        'pierwsz',
        'drugi'
      ])) {
    return false;
  }
  final drawing = u.hasStem(const ['rysun', 'szkic', 'drawing', 'sketch']) ||
      u.hasAny(const ['iso']);
  final summary = u.hasStem(const ['zestaw', 'podsum', 'summary']);
  final copy = u.hasStem(const ['skopiuj', 'skopiowac', 'kopiuj', 'copy']) ||
      u.hasStem(const ['wrzuc', 'umiesc', 'put']) &&
          u.hasStem(const ['schow', 'clipboard']);
  return drawing &&
      summary &&
      copy &&
      !RegExp(r'^(?:jak|how|kiedy|when|dlaczego|why|did you|have you)\b|\b(?:czy moge|can i|draw)\b')
          .hasMatch(text);
}

class IsoCopySummarySkill extends AssistantSkill {
  @override
  bool get canInterruptPendingWithAi => true;
  @override
  String get id => 'iso.summary.copy';
  @override
  String get toolId => 'iso_notebook';
  @override
  AssistantTier get tier => AssistantTier.a;
  @override
  List<SkillExample> get examples => const [
        SkillExample('Skopiuj zestawienie rysunku ISO',
            'Copy current ISO drawing summary'),
        SkillExample('Kopiuj zestawienie bieżącego rysunku ISO',
            'Copy ISO drawing summary to clipboard'),
      ];
  @override
  SkillMatch? match(Utterance u, AssistantContext ctx) =>
      (ctx.modules.activeToolId == null ||
                  ctx.modules.activeToolId == toolId) &&
              _requested(u)
          ? SkillMatch(this, .99, utterance: u, explicitToolTarget: true)
          : null;
  @override
  bool acceptsProposal(
          Utterance original, Utterance command, AssistantContext context) =>
      (context.modules.activeToolId == toolId || _requested(original)) &&
      _requested(original, natural: true) &&
      _requested(command);
  @override
  Future<SkillResult> run(SkillMatch m, AssistantContext ctx) async {
    final port = ctx.modules;
    if (port.activeToolId != toolId || port is! ModuleActionContext) {
      return const AnswerResult(
          AssistantAnswer(
              text: AssistantText(
                  'Otwórz rysunek ISO, którego zestawienie chcesz skopiować.',
                  'Open the ISO drawing whose summary you want to copy.')),
          actionCompleted: false);
    }
    final result = await (port as ModuleActionContext)
        .performModuleAction(toolId, 'copy_summary');
    return AnswerResult(AssistantAnswer(text: result.message),
        actionCompleted: result.completed);
  }
}
