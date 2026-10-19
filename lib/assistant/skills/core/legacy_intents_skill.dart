// Stary parser (assistant_parser.dart) jako umiejętność: zapis parametru
// spawania (`legacy.save`) i wpis do dziennika spoin (`legacy.journal`).
//
// KRADZIEŻ ZAMIARU (Review Focus 2): stary parser traktuje „dodaj/add" jako
// czasownik zapisu, więc „dodaj zawór kulowy dn50", „dodaj rurę 2 metry" czy
// „dodaj spoinę 12" dawały u niego zapis. Tutaj wynik liczy się według
// DOWODÓW, nie czasownika:
//   • parametr spawania wymaga procesu albo materiału ORAZ prądu albo
//     ścianki — samo „dodaj …" daje 0 (brak trafienia);
//   • dziennik wymaga słowa „dziennik/journal/weld log" albo „spoina nr /
//     weld no".
// Walidacja i pytania o brakujące pola — ten sam walidator co dotąd;
// podsumowanie i zapis — przez [AssistantActionsPort] (zadanie 1.0).

import '../../../i18n/app_language.dart';
import '../../assistant_intents.dart';
import '../../assistant_parser.dart';
import '../../assistant_validator.dart';
import '../../core/assistant_actions_port.dart';
import '../../core/skill.dart';

enum _LegacyMode { weldParam, journal }

final _journalEvidenceRe = RegExp(
    r'\bdziennik\w*|\bjournal\b|\bweld log\b|'
    r'\bspoin\w* (?:nr|numer\w*|no|number)\b|\bweld (?:nr|no|number)\b');

final _saveVerbRe = RegExp(
    r'\b(?:zapisz|zapamietaj|zanotuj|dodaj|dopisz|wpisz|save|store|remember|'
    r'record|add|log)\b');

/// Gotowe odpowiedzi-chipy dla pytań walidatora.
List<FollowUp> _choicesFor(String field, AppLanguage lang) {
  final en = lang == AppLanguage.en;
  FollowUp f(String pl, String enText) =>
      FollowUp(AssistantText(pl, enText), en ? enText : pl);
  return switch (field) {
    'material' => [
        f('nierdzewka', 'stainless'),
        f('stal czarna', 'carbon steel'),
        f('duplex', 'duplex'),
      ],
    'process' => [f('TIG', 'TIG'), f('MIG/MAG', 'MIG/MAG'), f('elektroda', 'stick')],
    'filler' => [f('z drutem', 'with filler'), f('bez drutu', 'no filler')],
    _ => const [],
  };
}

AssistantText _rejectText(AssistantRejectReason reason, String? field) {
  final f = field ?? '';
  return switch (reason) {
    AssistantRejectReason.outOfRange => AssistantText(
        'Wartość poza zakresem ($f) — nic nie zapisałem. Powiedz jeszcze raz.',
        'Value out of range ($f) — nothing saved. Say it again.'),
    AssistantRejectReason.inconsistent => const AssistantText(
        'MIG/MAG i elektroda zawsze mają spoiwo — „bez drutu" się nie zgadza. '
            'Nic nie zapisałem.',
        'MIG/MAG and stick always use filler — "no filler" does not fit. '
            'Nothing saved.'),
    _ => AssistantText('Nie mogę tego zapisać ($f). Nic nie zapisałem.',
        'I cannot save that ($f). Nothing saved.'),
  };
}

class LegacyIntentsSkill extends AssistantSkill {
  LegacyIntentsSkill.weldParam(this.actions) : _mode = _LegacyMode.weldParam;
  LegacyIntentsSkill.journal(this.actions) : _mode = _LegacyMode.journal;

  final AssistantActionsPort actions;
  final _LegacyMode _mode;

  bool get _isParam => _mode == _LegacyMode.weldParam;

  @override
  String get id => _isParam ? 'legacy.save' : 'legacy.journal';
  @override
  String? get toolId => _isParam ? 'welder_pipes' : 'weld_journal';
  @override
  AssistantTier get tier => AssistantTier.c;
  @override
  bool get readOnly => false;

  @override
  List<SkillExample> get examples => _isParam
      ? const [
          SkillExample('Zapisz TIG nierdzewka ścianka 2 mm 60 A bez drutu',
              'Save TIG stainless wall 2 mm 60 A no filler'),
          SkillExample('Zapisz MAG czarna ścianka 5 mm 110 amper',
              'Save MAG carbon steel wall 5 mm 110 amps'),
          SkillExample('TIG z drutem kwasówka ścianka 2,77 90 A',
              'TIG with filler stainless wall 2.77 mm 90 A'),
          SkillExample('Zapamiętaj elektroda czarna ścianka 6 mm 120 A',
              'Remember stick carbon steel wall 6 mm 120 A'),
          SkillExample('Zapisz spawam rurę DN50 141 80 amper',
              'Save welding DN50 pipe 141 80 amps'),
          SkillExample('Dodaj parametr TIG nierdzewka 3 mm 90 A',
              'Add parameter TIG stainless 3 mm 90 A'),
        ]
      : const [
          SkillExample('Dopisz do dziennika spoinę 12 projekt Blok 4',
              'Add weld 12 to the journal project Block 4'),
          SkillExample('Zapisz w dzienniku spoina nr 7 projekt Hala B',
              'Log weld no 7 in the journal project Hall B'),
          SkillExample('Dodaj spoinę numer 15 do dziennika projekt Rafineria',
              'Record weld number 15 in the weld log project Refinery'),
        ];

  @override
  List<SkillRejection> get rejections => _isParam
      ? const [
          SkillRejection('dodaj zawór kulowy dn50', alsoNot: ['legacy.journal']),
          SkillRejection('dodaj rurę 2 metry', alsoNot: ['legacy.journal']),
          SkillRejection('dodaj spoinę 12', alsoNot: ['legacy.journal']),
          SkillRejection('add a ball valve DN50',
              alsoNot: ['legacy.journal'], lang: AppLanguage.en),
          SkillRejection('jaki prąd na TIG nierdzewka 2 mm?'),
          SkillRejection('ścianka dn40 sch 40', routesTo: 'pipe.wall'),
        ]
      : const [
          SkillRejection('dodaj spoinę 12', alsoNot: ['legacy.save']),
          SkillRejection('add weld 12',
              alsoNot: ['legacy.save'], lang: AppLanguage.en),
          SkillRejection('jaka jest średnica dn40', routesTo: 'pipe.od'),
        ];

  @override
  SkillMatch? match(Utterance u, AssistantContext ctx) {
    final p = parseAssistantCommand(u.raw);
    if (_isParam) {
      if (p.intent != kIntentSaveWeldParameter) return null;
      final f = p.fields;
      final evidence = (f.containsKey('material') || f.containsKey('process')) &&
          (f.containsKey('current_a') || f.containsKey('wall_mm'));
      if (!evidence) return null;
      final required =
          kSaveWeldRequiredOrder.where(f.containsKey).length / kSaveWeldRequiredOrder.length;
      final verb = _saveVerbRe.hasMatch(u.folded) ? 0.1 : 0.0;
      return SkillMatch(this, 0.7 + verb + 0.1 * required,
          slots: Map.of(f), utterance: u);
    }
    if (p.intent != kIntentAddWeldJournalEntry) return null;
    if (!_journalEvidenceRe.hasMatch(u.folded)) return null;
    return SkillMatch(this, 0.85, slots: Map.of(p.fields), utterance: u);
  }

  /// Kontynuacja nie dotyczy zapisów — „a dla DN50?" po zapisie to nie
  /// kolejny zapis.
  @override
  Map<String, Object?> slotsFrom(Utterance u, AssistantContext ctx) => const {};

  @override
  Map<String, Object?>? fillSlot(
      String slot, Utterance u, AssistantContext ctx) {
    final f = parseFieldAnswer(slot, u.raw);
    return f.containsKey(slot) ? f : null;
  }

  @override
  Future<SkillResult> run(SkillMatch m, AssistantContext ctx) async {
    final lang = ctx.lang;
    final byVoice = m.utterance?.byVoice ?? false;
    final intent =
        _isParam ? kIntentSaveWeldParameter : kIntentAddWeldJournalEntry;
    final check = validateAssistantProposal(intent, m.slots);
    switch (check) {
      case AssistantReadyToSave(:final draft):
        return ConfirmResult(
          actions.weldParamSummary(draft, byVoice: byVoice, lang: lang),
          () => actions.saveWeldParam(draft, byVoice: byVoice, lang: lang),
        );
      case AssistantReadyToJournal(:final draft):
        final prep =
            await actions.prepareJournal(draft, byVoice: byVoice, lang: lang);
        switch (prep) {
          case PreparedJournal():
            return ConfirmResult(
              prep.summary,
              () => actions.saveJournal(prep, byVoice: byVoice, lang: lang),
            );
          case JournalWeldNoTaken(:final weldNo, :final project, :final wps):
            return AskResult(
              'weld_no',
              AssistantText(
                  'Spoina $weldNo jest już w projekcie „$project”. Nic nie '
                      'zapisałem — podaj inny numer.',
                  'Weld $weldNo already exists in project "$project". Nothing '
                      'saved — give another number.'),
              partial: m.copyWith(
                  slots: {'project': project, if (wps != null) 'wps': wps}),
            );
          case JournalUnavailable(:final message):
            return FailedResult(message);
        }
      case AssistantNeedsField(:final field):
        return AskResult(
          field,
          AssistantText(assistantQuestionFor(field, AppLanguage.pl),
              assistantQuestionFor(field, AppLanguage.en)),
          partial: m,
          choices: _choicesFor(field, lang),
        );
      case AssistantRejected(:final reason, :final field):
        return FailedResult(_rejectText(reason, field));
      case AssistantReadyToOpen() ||
            AssistantReadyToAnswer() ||
            AssistantReadyToQuery():
        return const FailedResult(AssistantText(
            'Tego nie zapiszę — powiedz jeszcze raz, co zapisać.',
            'I cannot save that — say again what to save.'));
    }
  }
}
