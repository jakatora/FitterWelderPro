import '../../../i18n/app_language.dart';
import '../../core/command_words.dart'
    show referencesInstruction, isNegatedCommand;
import '../../core/skill.dart';

bool? _destination(Utterance u, {bool natural = false}) {
  if (referencesInstruction(u) || isNegatedCommand(u)) return null;
  final text = u.folded;
  if (AccountNavigationSkill._command.hasMatch(text)) {
    return RegExp(r'\b(?:zaloz|zalozyc|utworz|create|sign up)\b')
        .hasMatch(text);
  }
  if (!natural) return null;
  if (RegExp(
          r'^(?:potrzebuje formularza (?:do )?zalozenia konta|przenies mnie do (?:formularza )?rejestracji|(?:could|can|would) you (?:please )?(?:open|show) (?:the )?registration form|i would like to create an account)$')
      .hasMatch(text)) {
    return true;
  }
  if (RegExp(r'^(?:(?:przejdzmy|wejdzmy) (?:teraz )?do|przenies mnie (?:teraz )?do|chcialbym (?:teraz )?otworzyc|chce (?:teraz )?(?:otworzyc|edytowac|uzupelnic)|(?:czy )?mozesz (?:mi )?(?:otworzyc|pokazac)) (?:(?:moj|moje|mojego) )?(?:konto|konta|profil zawodowy|profilu zawodowego|ustawienia konta|formularz logowania)$')
          .hasMatch(text) ||
      RegExp(r'^(?:could|can|would) you (?:please )?(?:open|show) (?:(?:my|the) )?(?:account|professional profile|account settings|login form)$')
          .hasMatch(text) ||
      RegExp(r'^(?:chcialbym|chce) (?:teraz )?sie zalogowac$').hasMatch(text)) {
    return false;
  }
  return null;
}

/// Navigates to account forms locally. Never asks for credentials in chat and
/// never claims that registration, authentication or a profile edit succeeded.
class AccountNavigationSkill extends AssistantSkill {
  @override
  bool get canInterruptPendingWithAi => true;
  @override
  Iterable<String> aiTaskSwitchCommands(
      Utterance source, AssistantContext ctx) {
    final registering = _destination(source, natural: true);
    if (registering == null) return const [];
    return [
      registering
          ? (ctx.lang == AppLanguage.en ? 'Create an account' : 'Utwórz konto')
          : (ctx.lang == AppLanguage.en
              ? 'Open account settings'
              : 'Otwórz ustawienia konta')
    ];
  }

  @override
  bool acceptsProposal(
      Utterance original, Utterance command, AssistantContext context) {
    final source = _destination(original, natural: true),
        target = _destination(command);
    return source != null && target != null && source == target;
  }

  static final _command = RegExp(
    r'^(?:(?:prosze|please|hej|hey)\s+)*'
    r'(?:zaloguj mnie|zaloguj sie|chce sie zalogowac|chce zalozyc konto|'
    r'zaloz mi konto|zaloz konto|utworz konto|'
    r'log in|log me in|sign in|sign me in|sign up|create an account|'
    r'i want to sign in|i want to create an account|'
    r'(?:otworz|pokaz|przejdz do|wejdz w)\s+(?:(?:moj|moje|mojego)\s+)?'
    r'(?:konto|konta|profil zawodowy|profilu zawodowego|ustawienia konta)|'
    r'(?:open|show|go to)\s+(?:(?:my|the)\s+)?(?:account|professional profile|account settings))'
    r'(?:\s+(?:prosze|please))?$',
  );
  @override
  String get id => 'account.open';
  @override
  String get toolId => 'account';
  @override
  AssistantTier get tier => AssistantTier.a;
  @override
  List<SkillExample> get examples => const [
        SkillExample('Chcę założyć konto', 'I want to create an account'),
        SkillExample('Zaloguj mnie', 'Sign me in'),
        SkillExample(
            'Pokaż mój profil zawodowy', 'Show my professional profile'),
        SkillExample('Otwórz ustawienia konta', 'Open account settings'),
        SkillExample('Utwórz konto', 'Create an account'),
        SkillExample('Przejdź do mojego konta', 'Go to my account'),
      ];
  @override
  List<SkillRejection> get rejections => const [
        SkillRejection('otwórz profile stalowe'),
        SkillRejection('ile waży profil stalowy'),
        SkillRejection('zapisz parametry spawania'),
        SkillRejection('nie chcę zakładać konta'),
        SkillRejection('usuń konto'),
      ];
  @override
  SkillMatch? match(Utterance u, AssistantContext ctx) {
    final registering = _destination(u);
    if (registering == null) return null;
    return SkillMatch(this, 0.96,
        slots: {'registering': registering}, utterance: u);
  }

  @override
  Future<SkillResult> run(SkillMatch m, AssistantContext ctx) async {
    final registering = m.slots['registering'] == true;
    return AnswerResult(
      AssistantAnswer(
          text: registering
              ? const AssistantText(
                  'Otwieram formularz tworzenia konta. Dane logowania wpisz w formularzu, poza rozmową z asystentem.',
                  'Opening the account registration form. Enter your sign-in details in the form, outside the assistant conversation.')
              : const AssistantText(
                  'Otwieram konto i profil zawodowy. Dane logowania wpisz w formularzu, poza rozmową z asystentem.',
                  'Opening account and professional profile. Enter your sign-in details in the form, outside the assistant conversation.')),
      show: ShowInModule(registering ? 'account_register' : 'account'),
    );
  }
}
