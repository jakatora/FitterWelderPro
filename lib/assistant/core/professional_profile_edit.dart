import 'dart:convert';
import '../../security/credential_text.dart';
import '../../services/account_service.dart';
import 'skill.dart';
import 'tool_bridge.dart';

/// Only explicit professional fields. Identity, role, visibility and AI consent
/// cannot be supplied through this contract.
final class ProfessionalProfilePatch {
  const ProfessionalProfilePatch.profession(String value)
      : profession = value,
        experienceYears = null;
  const ProfessionalProfilePatch.experience(int value)
      : profession = null,
        experienceYears = value;
  final String? profession;
  final int? experienceYears;
  Map<String, Object> get fields => {
        if (profession != null) 'profession': profession!,
        if (experienceYears != null) 'experienceYears': experienceYears!,
      };
  bool get valid => profession != null
      ? profession!.trim().isNotEmpty &&
          profession!.length <= 80 &&
          !containsCredentialValue(profession!) &&
          !RegExp(r'[\x00-\x1f\x7f]').hasMatch(profession!)
      : experienceYears != null &&
          experienceYears! >= 0 &&
          experienceYears! <= 80;
  bool sameAs(ProfessionalProfilePatch other) =>
      profession == other.profession &&
      experienceYears == other.experienceYears;
}

abstract interface class ProfessionalProfileEditorHandle {
  SkillResult prepareProfessionalProfileEdit(ProfessionalProfilePatch patch);
}

/// Local-only snapshot. Never expose it via InputToolHandle or AI context.
Map<String, dynamic> professionalProfileValues(Map<String, dynamic>? account) =>
    {
      'displayName': account?['displayName'] ?? '',
      'profession': account?['profession'] ?? '',
      'experienceYears': account?['experienceYears'] ?? 0,
      'processes': List<String>.from(account?['processes'] as List? ?? [])
        ..sort(),
      'qualifications': account?['qualifications'] ?? '',
      'stamp': account?['stamp'] ?? '',
      'publicProfile': account?['publicProfile'] == true,
    };
bool sameProfessionalProfile(Map<String, dynamic> a, Map<String, dynamic> b) =>
    jsonEncode(a) == jsonEncode(b);

Future<SkillResult> prepareProfessionalProfileEdit(
    ProfessionalProfilePatch patch,
    AccountService account,
    int revision) async {
  const unavailable = AnswerResult(
      AssistantAnswer(
          text: AssistantText(
              'Otwórz profil zawodowy z asystentem i powtórz zmianę. Nie zapisano profilu.',
              'Open the professional profile with the assistant and repeat the change. The profile was not saved.')),
      actionCompleted: false);
  if (!patch.valid ||
      !identical(account, AccountService.instance) ||
      revision != account.sessionRevision ||
      account.account == null) {
    return unavailable;
  }
  final outcome = await showInModule(const ShowInModule('professional_profile'),
      explicit: true);
  if (outcome != ShowOutcome.opened && outcome != ShowOutcome.appliedInPlace) {
    return unavailable;
  }
  final bridge = ToolBridge.instance;
  final handle = await bridge.whenReady('professional_profile');
  if (!identical(account, AccountService.instance) ||
      account.sessionRevision != revision ||
      account.account == null ||
      handle == null ||
      !identical(handle, bridge.current) ||
      handle is! ProfessionalProfileEditorHandle) {
    return unavailable;
  }
  return (handle as ProfessionalProfileEditorHandle)
      .prepareProfessionalProfileEdit(patch);
}
