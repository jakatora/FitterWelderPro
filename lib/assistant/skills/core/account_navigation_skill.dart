import '../../../i18n/app_language.dart';
import '../../core/command_words.dart'
    show referencesInstruction, isNegatedCommand;
import '../../core/skill.dart';

String? _destination(Utterance u, {bool natural = false}) {
  if (referencesInstruction(u) || isNegatedCommand(u)) return null;
  final text = u.folded;
  if (RegExp(r'^(?:edytuj profil zawodowy z asystentem|otworz profil zawodowy z asystentem|open professional profile with assistant)$')
          .hasMatch(text) ||
      natural &&
          RegExp(r'^(?:pomoz mi uzupelnic (?:moj )?profil zawodowy|help me fill in my professional profile)$')
              .hasMatch(text)) {
    return 'professional_profile';
  }
  if (AccountNavigationSkill._command.hasMatch(text)) {
    return RegExp(r'\b(?:zaloz|zalozyc|utworz|create|sign up)\b').hasMatch(text)
        ? 'account_register'
        : 'account';
  }
  if (!natural) return null;
  if (RegExp(
          r'^(?:potrzebuje formularza (?:do )?zalozenia konta|przenies mnie do (?:formularza )?rejestracji|(?:could|can|would) you (?:please )?(?:open|show) (?:the )?registration form|i would like to create an account)$')
      .hasMatch(text)) {
    return 'account_register';
  }
  if (RegExp(r'^(?:(?:przejdzmy|wejdzmy) (?:teraz )?do|przenies mnie (?:teraz )?do|chcialbym (?:teraz )?otworzyc|chce (?:teraz )?(?:otworzyc|edytowac|uzupelnic)|(?:czy )?mozesz (?:mi )?(?:otworzyc|pokazac)) (?:(?:moj|moje|mojego) )?(?:konto|konta|profil zawodowy|profilu zawodowego|ustawienia konta|formularz logowania)$')
          .hasMatch(text) ||
      RegExp(r'^(?:could|can|would) you (?:please )?(?:open|show) (?:(?:my|the) )?(?:account|professional profile|account settings|login form)$')
          .hasMatch(text) ||
      RegExp(r'^(?:chcialbym|chce) (?:teraz )?sie zalogowac$').hasMatch(text)) {
    return 'account';
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
    final destination = _destination(source, natural: true);
    if (destination == null) return const [];
    return [
      switch (destination) {
        'professional_profile' => ctx.lang == AppLanguage.en
            ? 'Open professional profile with assistant'
            : 'Edytuj profil zawodowy z asystentem',
        'account_register' =>
          ctx.lang == AppLanguage.en ? 'Create an account' : 'Utwórz konto',
        _ => ctx.lang == AppLanguage.en
            ? 'Open account settings'
            : 'Otwórz ustawienia konta',
      }
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
        SkillExample('Edytuj profil zawodowy z asystentem',
            'Open professional profile with assistant'),
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
    final destination = _destination(u);
    if (destination == null) return null;
    return SkillMatch(this, 0.96,
        slots: {'destination': destination}, utterance: u);
  }

  @override
  Future<SkillResult> run(SkillMatch m, AssistantContext ctx) async {
    final destination = m.slots['destination'] as String? ?? 'account';
    final registering = destination == 'account_register';
    if (destination == 'professional_profile') {
      return const AnswerResult(
          AssistantAnswer(
              text: AssistantText(
                  'Otwieram profil zawodowy z asystentem. Zmiany możesz przygotować poleceniem albo wpisać w formularzu.',
                  'Opening your professional profile with the assistant. Prepare changes by asking or edit the form.')),
          show: ShowInModule('professional_profile'));
    }
    return AnswerResult(
      AssistantAnswer(
          text: registering
              ? const AssistantText(
                  'Otwieram formularz tworzenia konta. Dane logowania wpisz w formularzu, poza rozmową z asystentem.',
                  'Opening the account registration form. Enter your sign-in details in the form, outside the assistant conversation.')
              : const AssistantText(
                  'Otwieram konto i profil zawodowy. Dane logowania wpisz w formularzu, poza rozmową z asystentem.',
                  'Opening account and professional profile. Enter your sign-in details in the form, outside the assistant conversation.')),
      show: ShowInModule(destination),
    );
  }
}
