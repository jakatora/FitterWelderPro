import '../../../i18n/app_language.dart';
import '../../core/skill.dart';
import '../../core/command_words.dart';

bool _requested(Utterance u, {bool natural = false}) {
  if (referencesInstruction(u) || isNegatedCommand(u)) return false;
  final text = u.folded.replaceFirst(RegExp(r'^(?:prosze|please) '), '');
  return RegExp(
              r'^(?:dodaj (?:biezaca |te |aktualna )pozycje(?: stali)? do listy(?: materialowej)?|zapisz (?:biezaca |aktualna )pozycje stali na liscie(?: materialowej)?|add (?:the )?(?:current|this) steel item to (?:the )?(?:material )?list|save (?:the )?current steel item on (?:the )?(?:material )?list)$')
          .hasMatch(text) ||
      natural &&
          RegExp(r'^(?:wrzuc te pozycje na liste(?: materialowa)?|zachowaj ten profil na liscie materialowej|put this steel item on the material list)$')
              .hasMatch(text);
}

// Let AI normalize ordinary prose about this item. The native confirmation
// still owns every value; requests with extra parameters or another target
// cannot be reduced to a parameter-free add operation.
bool _naturalCurrentItem(Utterance u, AssistantContext context) {
  if (context.modules.activeToolId != 'steel_weight' ||
      referencesInstruction(u) ||
      isNegatedCommand(u)) {
    return false;
  }
  final text = u.folded;
  // Probe both language grammars, even when English words arrive in a PL UI.
  // Polish 'ten profil' is a demonstrative, not the English number ten.
  final polishAction = u.hasStem(
      const ['dodaj', 'dodac', 'dorzuc', 'zapis', 'wrzuc', 'umiesc', 'zachow']);
  final numericText = polishAction
      ? text.replaceAll(
          RegExp(
              r'\bten (?=(?:(?:sam|aktualny|biezacy) )?(?:profil|element|pret|arkusz|katownik|ceownik|dwuteownik|plaskownik|ksztaltownik|wyrob|odcinek)\b)'),
          'this ')
      : text;
  if (Utterance(numericText, lang: AppLanguage.en)
      .items
      .any((item) => item.isNumber)) {
    return false;
  }
  if (RegExp(r'\b(?:nie|not|never|dont|don t|without|off|out|remove|exclude|omit)\b')
          .hasMatch(text) ||
      RegExp(r'^(?:jak|how|dlaczego|why)\b|\b(?:czy moge|czy mozna|can i|may i)\b')
          .hasMatch(text)) {
    return false;
  }
  if (u.hasStem(const [
    'cena',
    'cene',
    'price',
    'cost',
    'koszt',
    'rabat',
    'discount',
    'ilosc',
    'quantity',
    'dlugosc',
    'length',
    'srednic',
    'diameter',
    'grubosc',
    'thickness',
    'alumin',
    'nierdzewn',
    'stainless',
    'weglow',
    'carbon',
    'ustaw',
    'zmien',
    'change',
    'delete',
    'usun',
    'wyslij',
    'send',
    'share',
    'udostepnij',
    'account',
    'konto',
    'zawod',
    'parametr',
    'weld',
    'spawal',
    'email',
    'klient',
    'client',
    'invoice',
    'faktur',
    'wycen',
    'quote',
    'poprzedn',
    'ostatni',
    'previous',
    'last',
    'first',
    'second',
    'third',
    'pierwsz',
    'drugi',
    'trzeci',
    'kilk',
    'few',
    'several',
    'many',
    'more',
    'less',
    'polow',
    'half',
    'double',
    'twice'
  ])) {
    return false;
  }
  if (RegExp(
          r'["„“”]|\b(?:komend\w*|instrukcj\w*|command|instruction|obok|zamiast)\b|\bnew (?:(?:material|materials|steel) )?list\b|\bnow\w* list\w*\b')
      .hasMatch(text)) {
    return false;
  }
  final action = RegExp(
          r'\b(?:dodaj|dodac|dorzuc|dorzucic|zapisz|zapisac|wrzuc|wrzucic|zachowaj|zachowac|umiesc|umiescic|add|save|put|append|keep)\b')
      .hasMatch(text);
  final list = u.hasStem(const ['list', 'zamowieni']) ||
      u.hasAny(const ['material order', 'materials order']);
  final current = u.hasStem(const ['biezac', 'aktualn']) ||
      u.hasAny(
          const ['ten', 'te', 'ta', 'taki', 'this', 'that', 'it', 'current']);
  final polishReference = u.hasAny(const ['to']) &&
      u.hasStem(const [
        'dodaj',
        'dodac',
        'dorzuc',
        'zapis',
        'wrzuc',
        'umiesc',
        'zachow'
      ]);
  return action && list && (current || polishReference);
}

class SteelAddSkill extends AssistantSkill {
  @override
  String get id => 'steel.item.add';
  @override
  String get toolId => 'steel_weight';
  @override
  AssistantTier get tier => AssistantTier.c;
  @override
  bool get readOnly => false;
  @override
  List<SkillExample> get examples => const [
        SkillExample('Dodaj bieżącą pozycję stali do listy',
            'Add current steel item to the list'),
        SkillExample('Zapisz bieżącą pozycję stali na liście',
            'Save current steel item on the list'),
        SkillExample('Zapisz aktualną pozycję stali na liście materiałowej',
            'Save current steel item on the material list'),
      ];
  @override
  SkillMatch? match(Utterance u, AssistantContext ctx) {
    final active = ctx.modules.activeToolId;
    if (active != toolId &&
        (active != null || !u.hasAny(const ['stali', 'steel']))) {
      return null;
    }
    return _requested(u) ? SkillMatch(this, .99, utterance: u) : null;
  }

  @override
  bool acceptsProposal(
          Utterance original, Utterance command, AssistantContext context) =>
      (_requested(original, natural: true) ||
          _naturalCurrentItem(original, context)) &&
      _requested(command);
  @override
  Future<SkillResult> run(SkillMatch m, AssistantContext ctx) async {
    final port = ctx.modules;
    final prepared = port is RecordActionModuleContext
        ? (port as RecordActionModuleContext)
            .prepareModuleRecord(toolId, 'add_draft')
        : null;
    if (prepared == null) {
      return const AnswerResult(
          AssistantAnswer(
              text: AssistantText(
                  'Otwórz zakładkę Profil w Ciężarze stali i sprawdź dane pozycji przed dodaniem.',
                  'Open the Profile tab in Steel weight and check the item before adding it.')),
          actionCompleted: false);
    }
    return ConfirmResult(
        AssistantAnswer(text: prepared.summary), prepared.perform);
  }
}
