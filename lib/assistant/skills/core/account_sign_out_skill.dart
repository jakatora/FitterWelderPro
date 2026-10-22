import '../../../i18n/app_language.dart';
import '../../../services/account_service.dart';
import '../../core/command_words.dart'
    show referencesInstruction, isNegatedCommand;
import '../../core/skill.dart';

bool _requested(Utterance u, {bool natural = false}) {
  if (referencesInstruction(u) || isNegatedCommand(u)) return false;
  if (RegExp(
          r'^(?:(?:prosze|please|hej|hey) )*(?:wyloguj(?: mnie| sie| moje konto)?|sign me out|sign out|log me out|log out)(?: (?:prosze|please))?$')
      .hasMatch(u.folded)) {
    return true;
  }
  return natural &&
      RegExp(r'^(?:(?:chce|chcialbym|chcialabym) (?:sie )?(?:teraz )?wylogowac|(?:czy )?mozesz (?:mnie )?(?:teraz )?wylogowac(?: mnie)?|(?:could|can|would) you (?:please )?(?:sign|log) me out|i (?:want|would like) to (?:sign|log) out)$')
          .hasMatch(u.folded);
}

class AccountSignOutSkill extends AssistantSkill {
  @override
  String get id => 'account.sign_out';
  @override
  String get toolId => 'account';
  @override
  AssistantTier get tier => AssistantTier.c;
  @override
  bool get readOnly => false;
  @override
  bool get canInterruptPendingWithAi => true;
  @override
  List<SkillExample> get examples => const [
        SkillExample('Wyloguj mnie', 'Sign me out'),
        SkillExample('Wyloguj się', 'Log me out'),
        SkillExample('Wyloguj moje konto', 'Sign out'),
      ];
  @override
  List<SkillRejection> get rejections => const [
        SkillRejection('Nie wylogowuj mnie'),
        SkillRejection('Jak się wylogować'),
        SkillRejection('Usuń moje konto'),
        SkillRejection('Wyloguj innego użytkownika'),
      ];
  @override
  Iterable<String> aiTaskSwitchCommands(
          Utterance source, AssistantContext ctx) =>
      _requested(source, natural: true)
          ? [ctx.lang == AppLanguage.en ? 'Sign me out' : 'Wyloguj mnie']
          : const [];
  @override
  bool acceptsProposal(
          Utterance original, Utterance command, AssistantContext context) =>
      _requested(original, natural: true) && _requested(command);
  @override
  SkillMatch? match(Utterance u, AssistantContext ctx) =>
      _requested(u) ? SkillMatch(this, .97, utterance: u) : null;
  @override
  Future<SkillResult> run(SkillMatch m, AssistantContext ctx) async {
    final account = AccountService.instance;
    try {
      await account.load();
    } catch (_) {
      return const FailedResult(AssistantText(
          'Nie udało się odczytać sesji. Otwórz Konto i sprawdź jej stan.',
          'Could not read the session. Open Account and check its state.'));
    }
    if (!identical(account, AccountService.instance)) {
      return const FailedResult(AssistantText(
          'Sesja zmieniła się. Powtórz polecenie.',
          'The session changed. Repeat the request.'));
    }
    if (account.account == null && !account.needsIdentityRefresh) {
      return const AnswerResult(
          AssistantAnswer(
              text: AssistantText('Nie ma aktywnej sesji konta do wylogowania.',
                  'There is no active account session to sign out.')),
          actionCompleted: false);
    }
    return AccountSignOutConfirmation(account);
  }
}

/// Native-only confirmation. No identity/credentials enter model context.
final class AccountSignOutConfirmation extends ConfirmResult {
  factory AccountSignOutConfirmation(AccountService account) =>
      AccountSignOutConfirmation._(
          _PreparedSignOut(account, account.sessionRevision));
  AccountSignOutConfirmation._(this._prepared)
      : super(
            const AssistantAnswer(
                text: AssistantText(
                    'Wylogować bieżące konto? Aplikacja najpierw spróbuje zapisać otwarte dane powiązane z kontem. Bieżąca rozmowa i oczekujące polecenia zostaną wyczyszczone. Konto i zapisy nie zostaną usunięte.',
                    'Sign out of the current account? The app first tries to save open account data. The current conversation and pending commands will be cleared. Your account and records will not be deleted.')),
            _prepared.perform);
  final _PreparedSignOut _prepared;
  bool get completedForCurrentGuest =>
      _prepared.completed &&
      identical(AccountService.instance, _prepared.account) &&
      _prepared.account.sessionRevision == _prepared.revision + 1 &&
      _prepared.account.account == null &&
      !_prepared.account.needsIdentityRefresh &&
      _prepared.account.localOwnerId == null;
  static const success = AssistantText(
      'Wylogowano. Bieżąca rozmowa i oczekujące polecenia zostały wyczyszczone.',
      'Signed out. The current conversation and pending commands were cleared.');
  static const failure = AssistantText(
      'Nie udało się potwierdzić wylogowania. Sprawdź połączenie i zapisz otwarte dane przed ponowieniem.',
      'Could not confirm sign-out. Check your connection and save open data before retrying.');
  static const cancelled =
      AssistantText('Anulowano wylogowanie.', 'Sign-out cancelled.');
  static const cancelledAfterFailure = AssistantText(
      'Anulowano dalsze próby wylogowania. Sprawdź stan konta.',
      'Further sign-out attempts cancelled. Check your account state.');
}

class _PreparedSignOut {
  _PreparedSignOut(this.account, this.revision);
  final AccountService account;
  final int revision;
  Future<UndoAction?>? _inFlight;
  bool completed = false;
  Future<UndoAction?> perform() {
    if (completed) return Future.value(null);
    return _inFlight ??= _perform().whenComplete(() => _inFlight = null);
  }

  Future<UndoAction?> _perform() async {
    if (!identical(account, AccountService.instance) ||
        account.sessionRevision != revision) {
      throw AccountException('Session changed');
    }
    await account.signOut();
    completed = true;
    return null;
  }
}
