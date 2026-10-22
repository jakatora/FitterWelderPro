import 'dart:convert';
import '../../security/credential_text.dart';
import '../../services/account_service.dart';
import 'skill.dart';
import 'tool_bridge.dart';

/// Only explicit professional fields. Identity, role, visibility and AI consent
/// cannot be supplied through this contract.
enum ProfileProcessEdit { replace, add, remove }

const professionalProcessCodes = {
  '111',
  '114',
  '121',
  '131',
  '135',
  '136',
  '138',
  '141',
  '311'
};

final class ProfessionalProfilePatch {
  const ProfessionalProfilePatch._(
      {this.profession,
      this.experienceYears,
      this.processes,
      this.qualifications,
      this.stamp,
      this.processEdit = ProfileProcessEdit.replace});
  const ProfessionalProfilePatch.profession(String value)
      : this._(profession: value);
  const ProfessionalProfilePatch.experience(int value)
      : this._(experienceYears: value);
  const ProfessionalProfilePatch.qualifications(String value)
      : this._(qualifications: value);
  const ProfessionalProfilePatch.stamp(String value) : this._(stamp: value);
  ProfessionalProfilePatch.processes(Iterable<String> values,
      {ProfileProcessEdit operation = ProfileProcessEdit.replace})
      : this._(
            processes: List<String>.unmodifiable(values),
            processEdit: operation);
  final String? profession, qualifications, stamp;
  final int? experienceYears;
  final List<String>? processes;
  final ProfileProcessEdit processEdit;
  Map<String, Object> get fields => {
        if (profession != null) 'profession': profession!,
        if (experienceYears != null) 'experienceYears': experienceYears!,
        if (qualifications != null) 'qualifications': qualifications!,
        if (stamp != null) 'stamp': stamp!,
        if (processes != null)
          'processes': List<String>.unmodifiable(processes!.toList()..sort()),
      };
  bool _textValid(String value, int maximum) =>
      value.length <= maximum &&
      !containsCredentialValue(value) &&
      !RegExp(r'[\x00-\x1f\x7f]').hasMatch(value);
  bool get valid {
    if (profession != null) return _textValid(profession!, 80);
    if (experienceYears != null) {
      return experienceYears! >= 0 && experienceYears! <= 80;
    }
    if (qualifications != null) return _textValid(qualifications!, 500);
    if (stamp != null) return _textValid(stamp!, 40);
    return processes != null &&
        (processEdit == ProfileProcessEdit.replace || processes!.isNotEmpty) &&
        processes!.length <= 9 &&
        processes!.toSet().length == processes!.length &&
        processes!.every(professionalProcessCodes.contains);
  }

  bool sameAs(ProfessionalProfilePatch other) =>
      processEdit == other.processEdit &&
      jsonEncode(fields) == jsonEncode(other.fields);
  Map<String, Object> resolve(Map<String, dynamic> baseline) {
    if (processes == null || processEdit == ProfileProcessEdit.replace) {
      return fields;
    }
    final current = Set<String>.from(baseline['processes'] as List);
    if (processEdit == ProfileProcessEdit.add) {
      current.addAll(processes!);
    } else {
      current.removeAll(processes!);
    }
    return {'processes': List<String>.unmodifiable(current.toList()..sort())};
  }

  AssistantText get confirmation {
    if (profession != null) {
      return profession!.isEmpty
          ? const AssistantText('Wyczyścić zawód w Twoim profilu?',
              'Clear the profession in your profile?')
          : AssistantText('Zapisać zawód w Twoim profilu?\n$profession',
              'Save this profession in your profile?\n$profession');
    }
    if (experienceYears != null) {
      return AssistantText(
          'Zapisać doświadczenie w Twoim profilu: $experienceYears lat?',
          'Save this experience in your profile: $experienceYears years?');
    }
    if (qualifications != null) {
      return qualifications!.isEmpty
          ? const AssistantText('Wyczyścić kwalifikacje w Twoim profilu?',
              'Clear the qualifications in your profile?')
          : AssistantText(
              'Zapisać podane kwalifikacje w Twoim profilu?\n$qualifications',
              'Save the qualifications you provided in your profile?\n$qualifications');
    }
    if (stamp != null) {
      return stamp!.isEmpty
          ? const AssistantText('Wyczyścić stempel w Twoim profilu?',
              'Clear the stamp in your profile?')
          : AssistantText('Zapisać stempel w Twoim profilu?\n$stamp',
              'Save this stamp in your profile?\n$stamp');
    }
    final selected = processes!.join(', ');
    // Only the requested codes enter the dialogue/history, never old profile data.
    return switch (processEdit) {
      ProfileProcessEdit.add => AssistantText(
          'Dodać do Twojego profilu procesy: $selected? Pozostałe procesy zostaną zachowane.',
          'Add these processes to your profile: $selected? Other processes will be kept.'),
      ProfileProcessEdit.remove => AssistantText(
          'Usunąć z Twojego profilu procesy: $selected? Pozostałe procesy zostaną zachowane.',
          'Remove these processes from your profile: $selected? Other processes will be kept.'),
      ProfileProcessEdit.replace => processes!.isEmpty
          ? const AssistantText('Wyczyścić listę procesów w Twoim profilu?',
              'Clear the process list in your profile?')
          : AssistantText('Zastąpić listę procesów w Twoim profilu: $selected?',
              'Replace the process list in your profile with: $selected?'),
    };
  }
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
