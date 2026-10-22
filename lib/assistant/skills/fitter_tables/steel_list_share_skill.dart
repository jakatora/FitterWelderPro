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
    'udostepnij zapisana liste stali',
    'przygotuj liste stali do wyslania',
    'share saved steel list',
    'prepare steel list for sharing'
  ].contains(text)) {
    return true;
  }
  if (!natural) return false;
  if (u.items.any((i) => i.isNumber) ||
      Utterance(u.raw, lang: AppLanguage.en).items.any((i) => i.isNumber) ||
      u.hasStem(const [
        'tylko',
        'skopiuj',
        'kopiuj',
        'copy',
        'schow',
        'clipboard',
        'wyczysc',
        'clear',
        'reset',
        'only',
        'selected',
        'wybran',
        'klient',
        'client',
        'customer',
        'email',
        'mail',
        'szef',
        'boss',
        'jan',
        'john',
        'cena',
        'price',
        'rabat',
        'discount',
        'zmien',
        'change',
        'delete',
        'usun',
        'dodaj',
        'add',
        'pdf',
        'csv',
        'excel',
        'bez',
        'without',
        'except',
        'inna',
        'other',
        'czyj',
        'someone',
        'porownaj',
        'compare'
      ]) ||
      RegExp(r'^(?:jak|how)\b|\b(?:czy moge|czy mozna|can i|may i)\b')
          .hasMatch(text)) {
    return false;
  }
  final list = u.hasStem(const ['list', 'zamowieni']) &&
      u.hasStem(const ['stal', 'steel', 'material']);
  final sharing =
      u.hasStem(const ['udostepnij', 'udostepnic', 'share', 'sharing']) ||
          u.hasStem(const ['przygotuj', 'przygotowac', 'prepare', 'ready']) &&
              u.hasStem(const ['wyslan', 'wysylk', 'sending']);
  return list && sharing;
}

class SteelListShareSkill extends AssistantSkill {
  @override
  bool get canInterruptPendingWithAi => true;
  @override
  String get id => 'steel.list.share';
  @override
  String get toolId => 'steel_weight';
  @override
  AssistantTier get tier => AssistantTier.a;
  @override
  List<SkillExample> get examples => const [
        SkillExample(
            'Udostępnij zapisaną listę stali', 'Share saved steel list'),
        SkillExample('Przygotuj listę stali do wysłania',
            'Prepare steel list for sharing'),
      ];
  @override
  SkillMatch? match(Utterance u, AssistantContext ctx) =>
      (ctx.modules.activeToolId == null ||
                  ctx.modules.activeToolId == toolId) &&
              _requested(u)
          ? SkillMatch(this, .99, utterance: u)
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
                  'Otwórz Ciężar stali, żeby przygotować zapisaną listę do udostępnienia.',
                  'Open Steel weight to prepare the saved list for sharing.')),
          actionCompleted: false);
    }
    final result = await (port as ModuleActionContext)
        .performModuleAction(toolId, 'share_list');
    return AnswerResult(AssistantAnswer(text: result.message),
        actionCompleted: result.completed);
  }
}
