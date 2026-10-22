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
    'podsumuj zapisana liste stali',
    'ile wazy cala lista stali',
    'jaki jest koszt listy stali',
    'summarize saved steel list',
    'how much does the whole steel list weigh',
    'what is the cost of the steel list'
  ].contains(text)) {
    return true;
  }
  if (!natural) return false;
  // Let AI recognize varied questions, but never drop a filter, new parameter,
  // recipient or another record while reducing it to a whole-list read.
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
        'wybran',
        'selected',
        'klient',
        'client',
        'customer',
        'cudz',
        'other',
        'innej',
        'czyj',
        'someone',
        'profil',
        'ipe',
        'heb',
        'hea',
        'upn',
        'upe',
        'blach',
        'plate',
        'biezac',
        'pozycj',
        'item',
        'dodaj',
        'usun',
        'delete',
        'remove',
        'ustaw',
        'zmien',
        'change',
        'set',
        'wyslij',
        'send',
        'share',
        'udostepnij',
        'przetlumacz',
        'translate',
        'porownaj',
        'compare',
        'bez',
        'without',
        'except'
      ])) {
    return false;
  }
  final list = u.hasStem(const ['list', 'zamowieni']) &&
      u.hasStem(const ['stal', 'steel', 'material']);
  final summary = u.hasStem(const [
    'podsum',
    'summar',
    'wazy',
    'waga',
    'mas',
    'weigh',
    'cost',
    'koszt',
    'zamowic',
    'order',
    'lacznie',
    'total'
  ]);
  return list && summary;
}

class SteelListSummarySkill extends AssistantSkill {
  @override
  bool get canInterruptPendingWithAi => true;
  @override
  String get id => 'steel.list.summary';
  @override
  String get toolId => 'steel_weight';
  @override
  AssistantTier get tier => AssistantTier.a;
  @override
  List<SkillExample> get examples => const [
        SkillExample(
            'Podsumuj zapisaną listę stali', 'Summarize saved steel list'),
        SkillExample('Ile waży cała lista stali',
            'How much does the whole steel list weigh'),
        SkillExample('Jaki jest koszt listy stali',
            'What is the cost of the steel list'),
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
    final modules = ctx.modules;
    if (modules.activeToolId != toolId || modules is! ModuleActionContext) {
      return const AnswerResult(
          AssistantAnswer(
              text: AssistantText(
                  'Otwórz Ciężar stali, żeby odczytać zapisaną listę materiałową.',
                  'Open Steel weight to read the saved material list.')),
          actionCompleted: false);
    }
    final result = await (modules as ModuleActionContext)
        .performModuleAction(toolId, 'summarize_list');
    return AnswerResult(AssistantAnswer(text: result.message),
        actionCompleted: result.completed);
  }
}
