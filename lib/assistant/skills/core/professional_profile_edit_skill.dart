import '../../../i18n/app_language.dart';
import '../../../services/account_service.dart';
import 'dart:convert';
import '../../core/professional_profile_edit.dart';
import '../../core/skill.dart';
import '../../core/command_words.dart';

String? _literal(String raw) {
  final value = raw.trim();
  if (value.length >= 2 && value.startsWith('"') && value.endsWith('"')) {
    try {
      final decoded = jsonDecode(value);
      return decoded is String ? decoded.trim() : null;
    } catch (_) {
      return null;
    }
  }
  if (RegExp(
          r'\b(?:usun|usuń|delete|wyloguj|zapisz|ustaw|zmien|zmień|password|hasło|haslo|email|set|change|save)\b',
          caseSensitive: false)
      .hasMatch(value)) {
    return null;
  }
  return value;
}

class _ProcessSelection {
  _ProcessSelection(Iterable<String> codes, this.needsMag)
      : codes = List.unmodifiable(codes.toList()..sort());
  final List<String> codes;
  final bool needsMag;
}

_ProcessSelection? _processSelection(String raw, Utterance u) {
  final normalized = u.withRaw(raw).folded.replaceAllMapped(
      RegExp(r'\b(tig|mma|mig|saw|mag)(\d{3})\b'), (m) => '${m[1]} ${m[2]}');
  final words = normalized.split(RegExp(r'\s+'));
  final selected = <String>{};
  var needsMag = false;
  const aliases = {'tig': '141', 'mma': '111', 'mig': '131', 'saw': '121'};
  for (var i = 0; i < words.length; i++) {
    final word = words[i];
    if (word.isEmpty || const {'i', 'oraz', 'and', 'plus'}.contains(word)) {
      continue;
    }
    final next = i + 1 < words.length ? words[i + 1] : '';
    if (word == 'mag') {
      if (const {'135', '136', '138'}.contains(next)) {
        selected.add(next);
        i++;
      } else {
        if (professionalProcessCodes.contains(next)) return null;
        needsMag = true;
      }
      continue;
    }
    final code = aliases[word] ?? word;
    if (!professionalProcessCodes.contains(code)) return null;
    if (aliases.containsKey(word) && professionalProcessCodes.contains(next)) {
      if (next != code) return null;
      i++;
    }
    selected.add(code);
  }
  if (selected.isEmpty && !needsMag) return null;
  return _ProcessSelection(selected, needsMag);
}

ProfessionalProfilePatch? _processPatch(
    String raw, Utterance u, ProfileProcessEdit operation) {
  final selection = _processSelection(raw, u);
  if (selection == null || selection.needsMag) return null;
  return ProfessionalProfilePatch.processes(selection.codes,
      operation: operation);
}

/// Native question state retains the requested operation and explicit codes.
/// It never contains the private existing process list or crosses the AI wire.
class _MagQuestion {
  _MagQuestion(this.selection, this.operation);
  final _ProcessSelection selection;
  final ProfileProcessEdit operation;
  bool sameAs(_MagQuestion other) =>
      operation == other.operation &&
      jsonEncode(selection.codes) == jsonEncode(other.selection.codes);
  String canonical(AppLanguage lang) {
    final prefix = switch ((lang, operation)) {
      (AppLanguage.en, ProfileProcessEdit.add) => 'Add profile processes',
      (AppLanguage.en, ProfileProcessEdit.remove) => 'Remove profile processes',
      (AppLanguage.en, _) => 'Set my profile processes to',
      (_, ProfileProcessEdit.add) => 'Dodaj w moim profilu procesy',
      (_, ProfileProcessEdit.remove) => 'Usuń w moim profilu procesy',
      _ => 'Ustaw w moim profilu procesy na',
    };
    return '$prefix ${[
      ...selection.codes,
      'MAG'
    ].join(lang == AppLanguage.en ? ' and ' : ' i ')}';
  }
}

_MagQuestion? _magQuestion(Utterance u, {bool natural = false}) {
  if (referencesInstruction(u) || isNegatedCommand(u)) return null;
  for (final entry in <(ProfileProcessEdit, String)>[
    (
      ProfileProcessEdit.replace,
      r'^(?:ustaw w moim profilu procesy na|set my profile processes to) (.+)$'
    ),
    (
      ProfileProcessEdit.add,
      r'^(?:dodaj w moim profilu procesy|add profile processes) (.+)$'
    ),
    (
      ProfileProcessEdit.remove,
      r'^(?:usun w moim profilu procesy|remove profile processes) (.+)$'
    ),
    if (natural) ...[
      (
        ProfileProcessEdit.replace,
        r'^(?:wpisz w moim profilu procesy|set the welding processes in my profile to) (.+)$'
      ),
      (
        ProfileProcessEdit.add,
        r'^(?:dodaj|dopisz) (.+) do mojego profilu$|^add (.+) to my professional profile$'
      ),
      (
        ProfileProcessEdit.remove,
        r'^usun (.+) z mojego profilu$|^remove (.+) from my professional profile$'
      ),
    ],
  ]) {
    final match = RegExp(entry.$2).firstMatch(u.folded);
    if (match == null) continue;
    final selection = _processSelection(match[1] ?? match[2]!, u);
    if (selection == null || !selection.needsMag) return null;
    return _MagQuestion(selection, entry.$1);
  }
  if (natural) {
    final supplied = _naturalFieldValue(u);
    if (supplied != null &&
        supplied.$1.field == ProfessionalProfileField.processes &&
        supplied.$2 is _ProcessSelection &&
        (supplied.$2 as _ProcessSelection).needsMag) {
      return _MagQuestion(
          supplied.$2 as _ProcessSelection, supplied.$1.operation);
    }
  }

  return null;
}

class _FieldQuestion {
  const _FieldQuestion(this.field,
      [this.operation = ProfileProcessEdit.replace]);
  final ProfessionalProfileField field;
  final ProfileProcessEdit operation;
  String get slot => switch (field) {
        ProfessionalProfileField.profession => 'profile_profession',
        ProfessionalProfileField.experienceYears => 'profile_experience_years',
        ProfessionalProfileField.processes => 'profile_processes',
        ProfessionalProfileField.qualifications => 'profile_qualifications',
        ProfessionalProfileField.stamp => 'profile_stamp',
      };
  bool sameAs(_FieldQuestion other) =>
      field == other.field && operation == other.operation;
  String canonical(AppLanguage lang) {
    if (field == ProfessionalProfileField.processes &&
        operation != ProfileProcessEdit.replace) {
      return switch ((lang, operation)) {
        (AppLanguage.en, ProfileProcessEdit.add) => 'Add profile processes',
        (AppLanguage.en, _) => 'Remove profile processes',
        (_, ProfileProcessEdit.add) => 'Dodaj w moim profilu procesy',
        _ => 'Usuń w moim profilu procesy',
      };
    }
    final label = switch ((lang, field)) {
      (AppLanguage.en, ProfessionalProfileField.experienceYears) =>
        'experience',
      (AppLanguage.en, _) => field.name,
      (_, ProfessionalProfileField.profession) => 'zawód',
      (_, ProfessionalProfileField.experienceYears) => 'doświadczenie',
      (_, ProfessionalProfileField.processes) => 'procesy',
      (_, ProfessionalProfileField.qualifications) => 'kwalifikacje',
      _ => 'stempel',
    };
    return lang == AppLanguage.en
        ? 'Set my profile $label'
        : 'Ustaw w moim profilu $label';
  }

  AssistantText get question => switch (field) {
        ProfessionalProfileField.profession => const AssistantText(
            'Jaki zawód zapisać w Twoim profilu?',
            'What profession should I save in your profile?'),
        ProfessionalProfileField.experienceYears => const AssistantText(
            'Ile lat doświadczenia zapisać w Twoim profilu?',
            'How many years of experience should I save in your profile?'),
        ProfessionalProfileField.qualifications => const AssistantText(
            'Jakie kwalifikacje wpisać w Twoim profilu? Podaj ich treść.',
            'What qualifications should I enter in your profile? Provide the text.'),
        ProfessionalProfileField.stamp => const AssistantText(
            'Jaki stempel wpisać w Twoim profilu?',
            'What stamp should I enter in your profile?'),
        ProfessionalProfileField.processes => switch (operation) {
            ProfileProcessEdit.add => const AssistantText(
                'Jakie procesy dodać do Twojego profilu? Podaj kody lub nazwy, np. TIG i MMA.',
                'Which processes should I add to your profile? Provide codes or names, e.g. TIG and MMA.'),
            ProfileProcessEdit.remove => const AssistantText(
                'Jakie procesy usunąć z Twojego profilu? Podaj kody lub nazwy.',
                'Which processes should I remove from your profile? Provide codes or names.'),
            _ => const AssistantText(
                'Jakie procesy zapisać w Twoim profilu zamiast obecnej listy? Podaj kody lub nazwy.',
                'Which processes should replace the current list in your profile? Provide codes or names.'),
          },
      };
  ProfessionalProfilePatch? patch(Object? value) {
    final patch = switch ((field, value)) {
      (ProfessionalProfileField.profession, final String text) =>
        ProfessionalProfilePatch.profession(text),
      (ProfessionalProfileField.experienceYears, final int years) =>
        ProfessionalProfilePatch.experience(years),
      (ProfessionalProfileField.qualifications, final String text) =>
        ProfessionalProfilePatch.qualifications(text),
      (ProfessionalProfileField.stamp, final String text) =>
        ProfessionalProfilePatch.stamp(text),
      (ProfessionalProfileField.processes, final _ProcessSelection selection)
          when !selection.needsMag =>
        ProfessionalProfilePatch.processes(selection.codes,
            operation: operation),
      _ => null,
    };
    return patch != null && patch.valid ? patch : null;
  }
}

_FieldQuestion? _fieldQuestion(Utterance u, {bool natural = false}) {
  if (!natural && !u.folded.contains('profil')) return null;
  if (referencesInstruction(u) || isNegatedCommand(u)) return null;
  final text = u.folded;
  if (const {'dodaj w moim profilu procesy', 'add profile processes'}
      .contains(text)) {
    return const _FieldQuestion(
        ProfessionalProfileField.processes, ProfileProcessEdit.add);
  }
  if (const {'usun w moim profilu procesy', 'remove profile processes'}
      .contains(text)) {
    return const _FieldQuestion(
        ProfessionalProfileField.processes, ProfileProcessEdit.remove);
  }
  const labels = <String, ProfessionalProfileField>{
    'zawod': ProfessionalProfileField.profession,
    'profession': ProfessionalProfileField.profession,
    'doswiadczenie': ProfessionalProfileField.experienceYears,
    'experience': ProfessionalProfileField.experienceYears,
    'procesy': ProfessionalProfileField.processes,
    'processes': ProfessionalProfileField.processes,
    'kwalifikacje': ProfessionalProfileField.qualifications,
    'qualifications': ProfessionalProfileField.qualifications,
    'stempel': ProfessionalProfileField.stamp,
    'stamp': ProfessionalProfileField.stamp,
  };
  final canonical = RegExp(r'^(?:ustaw w moim profilu|set my profile) (\w+)$')
      .firstMatch(text);
  if (canonical != null && labels.containsKey(canonical[1])) {
    return _FieldQuestion(labels[canonical[1]]!);
  }
  if (!natural) return null;
  final prose = text
      .replaceFirst(RegExp(r'^(?:(?:prosze|please|hej|hey|asystencie) )*'), '')
      .replaceFirst(
          RegExp(
              r'^(?:(?:czy )?mozesz (?:mi )?|chce |chcialbym |can you (?:please )?)'),
          '');
  const plVerb = r'(?:zmien(?:ic)?|ustaw(?:ic)?|uzupeln(?:ij|ic)|wpis(?:z|ac))';
  for (final pattern in [
    '^$plVerb (?:moj|moje) (\\w+)' r'$',
    '^$plVerb (\\w+) (?:w moim profilu|w profilu zawodowym)' r'$',
    '^$plVerb w moim profilu (\\w+)' r'$',
    r'^(?:change|set|update|enter) my (?:profile )?(\w+)$',
  ]) {
    final match = RegExp(pattern).firstMatch(prose);
    if (match != null && labels.containsKey(match[1])) {
      return _FieldQuestion(labels[match[1]]!);
    }
  }
  final addRemove = RegExp(
          r'^(dodaj|dopisz|usun) (?:proces|procesy)(?: spawalnicze)? (?:do mojego|z mojego) profilu$')
      .firstMatch(prose);
  if (addRemove != null) {
    // Do not normalize contradictory direction words into an operation.
    if (addRemove[1] == 'usun' && !prose.contains(' z mojego ') ||
        addRemove[1] != 'usun' && !prose.contains(' do mojego ')) {
      return null;
    }
    return _FieldQuestion(
        ProfessionalProfileField.processes,
        addRemove[1] == 'usun'
            ? ProfileProcessEdit.remove
            : ProfileProcessEdit.add);
  }
  return null;
}

bool _isProfileValueReply(Utterance u) =>
    !referencesInstruction(u) &&
    !isNegatedCommand(u) &&
    !kOpenVerbAtStartRe.hasMatch(u.folded) &&
    !RegExp(r'^(?:anuluj|cancel|stop|tak|nie|yes|no|ok|okay|nie wiem|nie pamietam|i don t know)$')
        .hasMatch(u.folded) &&
    !RegExp(r'^(?:(?:a|and) )?(?:jak\w*|co|czy|ile|dlaczego|moge|mog\w*|moze\w*|could|would|should|may|does|is|are|what|how|why|which|can|potrzebuje|pomoz|help|i need|i want|chce|chcial\w*|prosze|please|masz|znasz|wiesz|powiedz|tell|explain|zrob|make|wroc|back|go back|return|zapisz|dodaj|dopisz|wpisz|usun|ustaw|zmien|wyczysc|wyloguj|narysuj|dorysuj|oblicz|policz|save|add|remove|delete|set|change|clear|draw|calculate|sign out|log out)\b')
        .hasMatch(u.folded);

Object? _fieldReply(String slot, Utterance u) {
  final raw = u.raw.trim();
  final quotedText = const {
        'profile_profession',
        'profile_qualifications',
        'profile_stamp'
      }.contains(slot) &&
      raw.startsWith('"') &&
      raw.endsWith('"');
  if (!quotedText && !_isProfileValueReply(u)) return null;
  if (slot == 'profile_processes') return _processSelection(u.raw, u);
  if (slot == 'profile_experience_years') {
    if (pendingReplyNeedsInterpretation(u) ||
        RegExp(r'[-+*/=]').hasMatch(u.raw)) {
      return null;
    }
    final values = u.items.where((item) => item.isNumber).toList();
    if (values.length != 1 ||
        u.items.where((item) => !item.isNumber).any((item) => !const {
              'mam',
              'lat',
              'lata',
              'rok',
              'years',
              'year',
              'i',
              'have',
              'of',
              'experience',
              'doswiadczenia'
            }.contains(item.text))) {
      return null;
    }
    final number = values.single.value!;
    if (number != number.roundToDouble() || number < 0 || number > 80) {
      return null;
    }
    return number.toInt();
  }
  final field = switch (slot) {
    'profile_profession' => ProfessionalProfileField.profession,
    'profile_qualifications' => ProfessionalProfileField.qualifications,
    'profile_stamp' => ProfessionalProfileField.stamp,
    _ => null,
  };
  if (field == null || u.raw.trim().isEmpty) return null;
  final literal = _literal(u.raw);
  return literal != null && _FieldQuestion(field).patch(literal) != null
      ? literal
      : null;
}

(_FieldQuestion, Object)? _naturalFieldValue(Utterance u) {
  final match = RegExp(r'^(.+?) (?:na|to|as) (.+)$', caseSensitive: false)
      .firstMatch(u.raw.trim());
  if (match == null) return null;
  final question = _fieldQuestion(u.withRaw(match[1]!), natural: true);
  if (question == null) return null;
  final rawValue = match[2]!.trim();
  final textField = const {
    ProfessionalProfileField.profession,
    ProfessionalProfileField.qualifications,
    ProfessionalProfileField.stamp
  }.contains(question.field);
  // An explicit field/value boundary owns its whole literal RHS. Preserve it,
  // including a job title such as Change Manager, rather than dropping words.
  final value = textField
      ? (rawValue.startsWith('"') ? _literal(rawValue) : rawValue)
      : _fieldReply(question.slot, u.withRaw(rawValue));
  if (value == null || textField && question.patch(value) == null) return null;
  return (question, value);
}

bool _sameProfileReply(Object? a, Object? b) =>
    a is _ProcessSelection && b is _ProcessSelection
        ? a.needsMag == b.needsMag && jsonEncode(a.codes) == jsonEncode(b.codes)
        : a == b;

ProfessionalProfilePatch? _patch(Utterance u, {bool natural = false}) {
  if (referencesInstruction(u) || isNegatedCommand(u)) return null;
  final raw = u.raw.trim();
  final text = raw.replaceFirst(RegExp(r'[.!?]+$'), '').trim();
  final clear = RegExp(
          r'^(?:wyczysc w moim profilu (zawod|kwalifikacje|stempel|procesy)|clear my profile (profession|qualifications|stamp|processes))$')
      .firstMatch(u.folded);
  if (clear != null) {
    return switch (clear[1] ?? clear[2]) {
      'zawod' || 'profession' => const ProfessionalProfilePatch.profession(''),
      'kwalifikacje' ||
      'qualifications' =>
        const ProfessionalProfilePatch.qualifications(''),
      'stempel' || 'stamp' => const ProfessionalProfilePatch.stamp(''),
      _ => ProfessionalProfilePatch.processes(const []),
    };
  }
  final experience = RegExp(
          r'^(?:ustaw w moim profilu do[sś]wiadczenie na|set my profile experience to) (\d+) (?:lat|lata|rok|years?)$',
          caseSensitive: false)
      .firstMatch(text);
  if (experience != null) {
    final result =
        ProfessionalProfilePatch.experience(int.tryParse(experience[1]!) ?? -1);
    return result.valid ? result : null;
  }
  for (final entry in <(String, String)>[
    (
      'profession',
      r'(?:ustaw w moim profilu zaw[oó]d na|set my profile profession to)'
    ),
    (
      'qualifications',
      r'(?:ustaw w moim profilu kwalifikacje na|set my profile qualifications to)'
    ),
    ('stamp', r'(?:ustaw w moim profilu stempel na|set my profile stamp to)'),
  ]) {
    final match = RegExp('^${entry.$2} (.+)' r'$', caseSensitive: false)
        .firstMatch(entry.$1 == 'profession' ? text : raw);
    if (match == null) continue;
    final value = _literal(match[1]!);
    if (value == null) return null;
    final patch = switch (entry.$1) {
      'profession' => ProfessionalProfilePatch.profession(value),
      'qualifications' => ProfessionalProfilePatch.qualifications(value),
      _ => ProfessionalProfilePatch.stamp(value),
    };
    return patch.valid ? patch : null;
  }
  for (final entry in <(ProfileProcessEdit, String)>[
    (
      ProfileProcessEdit.replace,
      r'(?:ustaw w moim profilu procesy na|set my profile processes to)'
    ),
    (
      ProfileProcessEdit.add,
      r'(?:dodaj w moim profilu procesy|add profile processes)'
    ),
    (
      ProfileProcessEdit.remove,
      r'(?:usu[nń] w moim profilu procesy|remove profile processes)'
    ),
  ]) {
    final match =
        RegExp('^${entry.$2} (.+)' r'$', caseSensitive: false).firstMatch(text);
    if (match != null) return _processPatch(match[1]!, u, entry.$1);
  }
  if (!natural) return null;
  final supplied = _naturalFieldValue(u);
  if (supplied != null) return supplied.$1.patch(supplied.$2);
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
  for (final entry in <(String, String)>[
    (
      'kwalifikacje',
      r'(?:wpisz w moim profilu kwalifikacje|put my profile qualifications as)'
    ),
    ('stempel', r'(?:wpisz w moim profilu stempel|put my profile stamp as)'),
  ]) {
    final match =
        RegExp('^${entry.$2} (.+)' r'$', caseSensitive: false).firstMatch(raw);
    if (match != null) {
      return _patch(
          u.withRaw('Ustaw w moim profilu ${entry.$1} na ${match[1]}'));
    }
  }
  final replace = RegExp(
          r'^(?:wpisz w moim profilu procesy|set the welding processes in my profile to) (.+)$',
          caseSensitive: false)
      .firstMatch(text);
  if (replace != null) {
    return _processPatch(replace[1]!, u, ProfileProcessEdit.replace);
  }
  final add = RegExp(
          r'^(?:dodaj|dopisz) (.+) do mojego profilu$|^add (.+) to my professional profile$',
          caseSensitive: false)
      .firstMatch(text);
  if (add != null) {
    return _processPatch(add[1] ?? add[2]!, u, ProfileProcessEdit.add);
  }
  final remove = RegExp(
          r'^usu[nń] (.+) z mojego profilu$|^remove (.+) from my professional profile$',
          caseSensitive: false)
      .firstMatch(text);
  if (remove != null) {
    return _processPatch(remove[1] ?? remove[2]!, u, ProfileProcessEdit.remove);
  }
  return null;
}

String _canonical(ProfessionalProfilePatch patch, AppLanguage lang) {
  final field = patch.fields.entries.single;
  if (patch.processes != null) {
    if (patch.processes!.isEmpty) {
      return lang == AppLanguage.en
          ? 'Clear my profile processes'
          : 'Wyczyść w moim profilu procesy';
    }
    final codes = patch.processes!.toList()..sort();
    return switch ((lang, patch.processEdit)) {
      (AppLanguage.en, ProfileProcessEdit.add) =>
        'Add profile processes ${codes.join(' and ')}',
      (AppLanguage.en, ProfileProcessEdit.remove) =>
        'Remove profile processes ${codes.join(' and ')}',
      (AppLanguage.en, _) =>
        'Set my profile processes to ${codes.join(' and ')}',
      (_, ProfileProcessEdit.add) =>
        'Dodaj w moim profilu procesy ${codes.join(' i ')}',
      (_, ProfileProcessEdit.remove) =>
        'Usuń w moim profilu procesy ${codes.join(' i ')}',
      _ => 'Ustaw w moim profilu procesy na ${codes.join(' i ')}',
    };
  }
  if (patch.experienceYears != null) {
    return lang == AppLanguage.en
        ? 'Set my profile experience to ${patch.experienceYears} years'
        : 'Ustaw w moim profilu doświadczenie na ${patch.experienceYears} lat';
  }
  if (lang == AppLanguage.en) {
    return 'Set my profile ${field.key} to ${jsonEncode(field.value)}';
  }
  final label = switch (field.key) {
    'profession' => 'zawód',
    'qualifications' => 'kwalifikacje',
    _ => 'stempel'
  };
  return 'Ustaw w moim profilu $label na ${jsonEncode(field.value)}';
}

class ProfessionalProfileEditSkill extends AssistantSkill {
  @override
  bool get professionalProcessQuestions => true;
  @override
  bool get professionalFieldQuestions => true;
  @override
  Set<String> get literalReplySlots => const {
        'profile_profession',
        'profile_experience_years',
        'profile_processes',
        'profile_qualifications',
        'profile_stamp',
      };

  @override
  Map<String, Object?>? fillSlot(
      String slot, Utterance u, AssistantContext ctx) {
    if (slot != 'profile_mag_code') {
      final value = _fieldReply(slot, u);
      return value == null ? null : {slot: value};
    }
    if (referencesInstruction(u) || isNegatedCommand(u)) return null;
    final match = RegExp(r'^(?:mag )?(135|136|138)$').firstMatch(u.folded);
    return match == null ? null : {slot: match[1]!};
  }

  @override
  Map<String, Object?>? fillProposalSlot(String slot, Utterance command,
      Utterance original, AssistantContext ctx) {
    final source = fillSlot(slot, original, ctx);
    final proposed = fillSlot(slot, command, ctx);
    return source != null &&
            proposed != null &&
            _sameProfileReply(source[slot], proposed[slot])
        ? source
        : null;
  }

  @override
  List<ProfessionalProfileField> get professionalProfileFields =>
      ProfessionalProfileField.values;
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
        SkillExample('Ustaw w moim profilu procesy na 141 i 111',
            'Set my profile processes to 141 and 111'),
        SkillExample('Ustaw w moim profilu kwalifikacje na szkolenie TIG',
            'Set my profile qualifications to TIG training'),
        SkillExample('Ustaw w moim profilu stempel na AB7',
            'Set my profile stamp to AB7'),
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
    if (patch != null) return [_canonical(patch, ctx.lang)];
    final question = _magQuestion(source, natural: true);
    if (question != null) return [question.canonical(ctx.lang)];
    final field = _fieldQuestion(source, natural: true);
    return field == null ? const [] : [field.canonical(ctx.lang)];
  }

  @override
  bool acceptsProposal(
      Utterance original, Utterance command, AssistantContext context) {
    final source = _patch(original, natural: true), proposed = _patch(command);
    if (source != null && proposed != null) return source.sameAs(proposed);
    final sourceQuestion = _magQuestion(original, natural: true);
    final proposedQuestion = _magQuestion(command);
    if (sourceQuestion != null && proposedQuestion != null) {
      return sourceQuestion.sameAs(proposedQuestion);
    }
    final sourceField = _fieldQuestion(original, natural: true);
    final proposedField = _fieldQuestion(command);
    return sourceField != null &&
        proposedField != null &&
        sourceField.sameAs(proposedField);
  }

  @override
  SkillMatch? match(Utterance u, AssistantContext ctx) => (_patch(u) == null &&
          _magQuestion(u) == null &&
          _fieldQuestion(u) == null)
      ? null
      : SkillMatch(this, .98, utterance: u);
  @override
  Future<SkillResult> run(SkillMatch m, AssistantContext ctx) async {
    var patch = _patch(m.utterance!);
    var question =
        m.slots['_mag_question'] as _MagQuestion? ?? _magQuestion(m.utterance!);
    final account = AccountService.instance;
    final revision = account.sessionRevision;
    await account.load();
    if (!identical(account, AccountService.instance) ||
        revision != account.sessionRevision ||
        (m.slots.containsKey('_profile_owner') &&
            (!identical(m.slots['_profile_owner'], account) ||
                m.slots['_profile_revision'] != revision))) {
      return const AnswerResult(
          AssistantAnswer(
              text: AssistantText('Sesja zmieniła się. Powtórz zmianę profilu.',
                  'The session changed. Repeat the profile change.')),
          actionCompleted: false);
    }
    if (account.account == null) {
      return const AnswerResult(
          AssistantAnswer(
              text: AssistantText(
                  'Zaloguj się w formularzu konta, aby zmienić profil zawodowy.',
                  'Sign in using the account form to change your professional profile.')),
          show: ShowInModule('account'),
          actionCompleted: false);
    }
    final field = m.slots['_field_question'] as _FieldQuestion? ??
        _fieldQuestion(m.utterance!);
    if (field != null) {
      final value = m.slots[field.slot];
      if (field.field == ProfessionalProfileField.processes &&
          value is _ProcessSelection &&
          value.needsMag) {
        question = _MagQuestion(value, field.operation);
      } else {
        patch = field.patch(value);
        if (patch == null) {
          return AskResult(field.slot, field.question,
              partial: m.copyWith(slots: {
                ...m.slots,
                '_field_question': field,
                '_profile_owner': account,
                '_profile_revision': revision,
              }));
        }
      }
    }
    if (question != null) {
      final reply = m.slots['profile_mag_code'];
      if (reply is String && const {'135', '136', '138'}.contains(reply)) {
        patch = ProfessionalProfilePatch.processes(
            {...question.selection.codes, reply},
            operation: question.operation);
      } else {
        return AskResult(
            'profile_mag_code',
            const AssistantText(
                'Który proces MAG masz na myśli: 135, 136 czy 138?',
                'Which MAG process do you mean: 135, 136 or 138?'),
            partial: m.copyWith(slots: {
              ...m.slots,
              '_mag_question': question,
              '_profile_owner': account,
              '_profile_revision': revision
            }),
            choices: const [
              FollowUp(AssistantText('135', '135'), '135'),
              FollowUp(AssistantText('136', '136'), '136'),
              FollowUp(AssistantText('138', '138'), '138'),
            ]);
      }
    }
    if (patch == null) {
      return const AnswerResult(
          AssistantAnswer(
              text: AssistantText(
                  'Powtórz zmianę profilu.', 'Repeat the profile change.')),
          actionCompleted: false);
    }
    return prepareProfessionalProfileEdit(patch, account, revision);
  }
}
