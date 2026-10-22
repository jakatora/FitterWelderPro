import '../../../i18n/app_language.dart';
import '../../../services/account_service.dart';
import '../../core/professional_profile_edit.dart';
import '../../core/skill.dart';
import '../../core/command_words.dart';

ProfessionalProfilePatch? _patch(Utterance u, {bool natural = false}) {
  if (referencesInstruction(u) || isNegatedCommand(u)) return null;
  final text = u.raw.trim().replaceFirst(RegExp(r'[.!?]+$'), '').trim();
  final profession = RegExp(
          r'^(?:ustaw w moim profilu zaw[oó]d na|set my profile profession to) (.+)$',
          caseSensitive: false)
      .firstMatch(text);
  final experience = RegExp(
          r'^(?:ustaw w moim profilu do[sś]wiadczenie na|set my profile experience to) (\d+) (?:lat|lata|rok|years?|year)$',
          caseSensitive: false)
      .firstMatch(text);
  if (profession != null) {
    final value = profession[1]!.trim();
    if (RegExp(
            r'\b(?:usun|usuń|delete|wyloguj|zapisz|ustaw|zmien|zmień|password|hasło|haslo|email)\b',
            caseSensitive: false)
        .hasMatch(value)) {
      return null;
    }
    final result = ProfessionalProfilePatch.profession(value);
    return result.valid ? result : null;
  }
  if (experience != null) {
    final result =
        ProfessionalProfilePatch.experience(int.parse(experience[1]!));
    return result.valid ? result : null;
  }
  if (!natural) return null;
  final naturalProfession = RegExp(
          r'^(?:(?:czy )?mo[zż]esz (?:mi )?wpisa[cć] w (?:moim )?profilu(?: zawodowym)? zaw[oó]d|chcia[łl]bym ustawi[cć] w moim profilu zaw[oó]d na|put my profession in my profile as) (.+)$',
          caseSensitive: false)
      .firstMatch(text);
  if (naturalProfession != null) {
    return _patch(
        u.withRaw('Ustaw w moim profilu zawód na ${naturalProfession[1]}'));
  }
  final naturalYears = RegExp(
          r'^(?:mam (\d+) lat do[sś]wiadczenia[, ]+wpisz to w moim profilu|put (\d+) years of experience in my profile)$',
          caseSensitive: false)
      .firstMatch(text);
  if (naturalYears != null) {
    return _patch(u.withRaw(
        'Ustaw w moim profilu doświadczenie na ${naturalYears[1] ?? naturalYears[2]} lat'));
  }
  return null;
}

class ProfessionalProfileEditSkill extends AssistantSkill {
  @override
  String get id => 'account.professional.edit';
  @override
  String get toolId => 'professional_profile';
  @override
  AssistantTier get tier => AssistantTier.c;
  @override
  bool get readOnly => false;
  @override
  bool get canInterruptPendingWithAi => true;
  @override
  List<SkillExample> get examples => const [
        SkillExample('Ustaw w moim profilu zawód na monter rurociągów',
            'Set my profile profession to pipe fitter'),
        SkillExample('Ustaw w moim profilu doświadczenie na 8 lat',
            'Set my profile experience to 8 years'),
      ];
  @override
  List<SkillRejection> get rejections => const [
        SkillRejection('Ustaw rolę administratora'),
        SkillRejection('Włącz publiczny profil'),
        SkillRejection('Ustaw cenę profilu stalowego na 8'),
        SkillRejection('Jak zmienić zawód w profilu'),
      ];
  @override
  Iterable<String> aiTaskSwitchCommands(
      Utterance source, AssistantContext ctx) {
    final patch = _patch(source, natural: true);
    if (patch == null) return const [];
    return [
      ctx.lang == AppLanguage.en
          ? patch.profession != null
              ? 'Set my profile profession to ${patch.profession}'
              : 'Set my profile experience to ${patch.experienceYears} years'
          : patch.profession != null
              ? 'Ustaw w moim profilu zawód na ${patch.profession}'
              : 'Ustaw w moim profilu doświadczenie na ${patch.experienceYears} lat'
    ];
  }

  @override
  bool acceptsProposal(
      Utterance original, Utterance command, AssistantContext context) {
    final source = _patch(original, natural: true), proposed = _patch(command);
    return source != null && proposed != null && source.sameAs(proposed);
  }

  @override
  SkillMatch? match(Utterance u, AssistantContext ctx) =>
      _patch(u) == null ? null : SkillMatch(this, .98, utterance: u);
  @override
  Future<SkillResult> run(SkillMatch m, AssistantContext ctx) async {
    final patch = _patch(m.utterance!);
    final account = AccountService.instance;
    final revision = account.sessionRevision;
    await account.load();
    if (!identical(account, AccountService.instance) ||
        revision != account.sessionRevision) {
      return const AnswerResult(
          AssistantAnswer(
              text: AssistantText('Sesja zmieniła się. Powtórz zmianę profilu.',
                  'The session changed. Repeat the profile change.')),
          actionCompleted: false);
    }
    if (account.account == null || patch == null) {
      return const AnswerResult(
          AssistantAnswer(
              text: AssistantText(
                  'Zaloguj się w formularzu konta, aby zmienić profil zawodowy.',
                  'Sign in using the account form to change your professional profile.')),
          show: ShowInModule('account'),
          actionCompleted: false);
    }
    return prepareProfessionalProfileEdit(patch, account, revision);
  }
}
