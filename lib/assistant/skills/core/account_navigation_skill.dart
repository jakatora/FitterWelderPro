import '../../core/skill.dart';

/// Navigates to account forms locally. Never asks for credentials in chat and
/// never claims that registration, authentication or a profile edit succeeded.
class AccountNavigationSkill extends AssistantSkill {
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
    if (!_command.hasMatch(u.folded)) return null;
    final registering = RegExp(r'\b(?:zaloz|zalozyc|utworz|create|sign up)\b')
        .hasMatch(u.folded);
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
