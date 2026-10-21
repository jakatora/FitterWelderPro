import 'package:uuid/uuid.dart';

import '../../../domain/confined_space/confined_space_record.dart';
import '../../../features/confined_space/confined_space_store.dart';
import '../../../domain/qualification/qualification_dates.dart'
    show formatIsoDate;
import '../../assistant_history.dart';
import '../../core/skill.dart';

final _prepare = RegExp(
  r'^(?:(?:prosze|please)\s+)*(?:przygotuj|utworz|stworz|prepare|create)\s+'
  r'(?:(?:szkic|protokol|formularz|draft|form)\s+)?'
  r'(?:przestrzeni zamknietej|wejscia do przestrzeni zamknietej|prac w przestrzeni zamknietej|confined space)\b',
);
final _labels = RegExp(
  r'\b(miejsce|location|opis(?: prac)?|description|numer zezwolenia|nr zezwolenia|numer pozwolenia|nr pozwolenia|permit number|'
  r'wchodzacy|wchodzący|entrants|asekurujacy|asekurujący|attendant|nadzor|nadzór|supervisor|wystawiajacy|wystawiający|issuer|ratownictwo|rescue)\s*:\s*',
  caseSensitive: false,
);
const _names = {
  'miejsce': 'location',
  'location': 'location',
  'opis': 'description',
  'opis prac': 'description',
  'description': 'description',
  'numer zezwolenia': 'permitNo',
  'nr zezwolenia': 'permitNo',
  'numer pozwolenia': 'permitNo',
  'nr pozwolenia': 'permitNo',
  'permit number': 'permitNo',
  'wchodzacy': 'entrants',
  'wchodzący': 'entrants',
  'entrants': 'entrants',
  'asekurujacy': 'attendant',
  'asekurujący': 'attendant',
  'attendant': 'attendant',
  'nadzor': 'supervisor',
  'nadzór': 'supervisor',
  'supervisor': 'supervisor',
  'wystawiajacy': 'issuer',
  'wystawiający': 'issuer',
  'issuer': 'issuer',
  'ratownictwo': 'rescue',
  'rescue': 'rescue',
};

Map<String, Object?> _fields(String raw) {
  final found = _labels.allMatches(raw).toList();
  final result = <String, Object?>{};
  for (var i = 0; i < found.length; i++) {
    final key = _names[found[i].group(1)!.toLowerCase()]!;
    final end = i + 1 < found.length ? found[i + 1].start : raw.length;
    final value = raw
        .substring(found[i].end, end)
        .trim()
        .replaceAll(RegExp(r'[;,]+$'), '')
        .trim();
    if (result.containsKey(key) && result[key] != value) {
      result['ambiguous'] = true;
    }
    result[key] = value;
  }
  return result;
}

class ConfinedSpacePrepareSkill extends AssistantSkill {
  ConfinedSpacePrepareSkill(
      {this.store = const ConfinedSpaceStore(), String Function()? newId})
      : _newId = newId ?? const Uuid().v4;
  final ConfinedSpaceStore store;
  final String Function() _newId;

  @override
  String get id => 'confined_space.prepare';
  @override
  String get toolId => 'confined_space';
  @override
  AssistantTier get tier => AssistantTier.c;
  @override
  bool get readOnly => false;
  @override
  Set<String> get literalReplySlots => const {'location', 'description'};
  @override
  bool get safetyCritical => true;
  @override
  List<SkillExample> get examples => const [
        SkillExample('Przygotuj protokół przestrzeni zamkniętej',
            'Prepare confined space form'),
        SkillExample('Utwórz szkic wejścia do przestrzeni zamkniętej',
            'Create confined space draft'),
        SkillExample(
            'Przygotuj formularz przestrzeni zamkniętej, miejsce: Zbiornik A',
            'Prepare confined space form, location: Tank A'),
        SkillExample(
            'Przygotuj protokół prac w przestrzeni zamkniętej, miejsce: Zbiornik A; opis: Spawanie podpory',
            'Prepare confined space form, location: Tank A; description: Welding a support'),
        SkillExample(
            'Przygotuj protokół przestrzeni zamkniętej, miejsce: Zbiornik B; opis: Kontrola; numer pozwolenia: P-12',
            'Prepare confined space form, location: Tank B; description: Inspection; permit number: P-12'),
        SkillExample('Stwórz formularz przestrzeni zamkniętej',
            'Create form confined space'),
      ];
  @override
  List<SkillRejection> get rejections => const [
        SkillRejection('otwórz przestrzeń zamknięta', routesTo: 'tool.open'),
        SkillRejection('zaznacz wszystkie kontrole przestrzeni zamkniętej'),
        SkillRejection('wyłącz wymagany pomiar tlenu'),
        SkillRejection('przygotuj protokół prac gorących',
            routesTo: 'hot_work.prepare'),
      ];
  @override
  SkillMatch? match(Utterance u, AssistantContext ctx) =>
      _prepare.hasMatch(u.folded)
          ? SkillMatch(this, .98, slots: _fields(u.raw), utterance: u)
          : null;

  @override
  Map<String, Object?>? fillSlot(
      String slot, Utterance u, AssistantContext ctx) {
    final fields = _fields(u.raw);
    if (fields.containsKey(slot)) return fields;
    if (fields.isNotEmpty) return null;
    if (const {'location', 'description'}.contains(slot) &&
        u.raw.trim().isNotEmpty) {
      return {slot: u.raw.trim()};
    }
    return null;
  }

  @override
  Future<SkillResult> run(SkillMatch m, AssistantContext ctx) async {
    if (m.slots['ambiguous'] == true ||
        _names.values.toSet().any((key) =>
            m.slots[key] != null &&
            (m.slots[key] is! String ||
                (m.slots[key] as String).length > 1000))) {
      return const FailedResult(AssistantText(
          'Podaj jedną wartość każdego pola, maksymalnie 1000 znaków.',
          'Give one value per field, up to 1000 characters.'));
    }
    String value(String key) => (m.slots[key] as String? ?? '').trim();
    for (final key in ['location', 'description']) {
      if (value(key).isEmpty) {
        return AskResult(
            key,
            key == 'location'
                ? const AssistantText('Gdzie mają być prowadzone prace?',
                    'Where will the work take place?')
                : const AssistantText(
                    'Jaki jest opis prac?', 'What work is planned?'),
            partial: m);
      }
    }
    final at = ctx.now();
    final draft = ConfinedSpaceRecord.blank(id: _newId(), now: at).copyWith(
      location: value('location'),
      description: value('description'),
      permitNo: value('permitNo'),
      entrants: value('entrants'),
      attendant: value('attendant'),
      supervisor: value('supervisor'),
      issuer: value('issuer'),
      rescue: value('rescue'),
    );
    final summary = AssistantAnswer(
      text: const AssistantText(
          'Przygotuję szkic danych organizacyjnych. Nie jest to zezwolenie na rozpoczęcie pracy; kontrole i pomiary atmosfery sprawdzasz na miejscu przed wejściem.',
          'I will prepare an organisational draft. This does not authorise starting work; checks and atmosphere readings must be verified on site before entry.'),
      lines: [
        AnswerLine(const AssistantText('Data', 'Date'), draft.date),
        AnswerLine(const AssistantText('Miejsce', 'Location'), draft.location),
        AnswerLine(
            const AssistantText('Opis', 'Description'), draft.description),
        if (draft.permitNo.isNotEmpty)
          AnswerLine(const AssistantText('Numer zezwolenia', 'Permit number'),
              draft.permitNo),
        if (draft.entrants.isNotEmpty)
          AnswerLine(
              const AssistantText('Wchodzący', 'Entrants'), draft.entrants),
        if (draft.attendant.isNotEmpty)
          AnswerLine(
              const AssistantText('Asekurujący', 'Attendant'), draft.attendant),
        if (draft.supervisor.isNotEmpty)
          AnswerLine(
              const AssistantText('Nadzór', 'Supervisor'), draft.supervisor),
        if (draft.rescue.isNotEmpty)
          AnswerLine(
              const AssistantText('Ratownictwo', 'Rescue'), draft.rescue),
        if (draft.issuer.isNotEmpty)
          AnswerLine(
              const AssistantText('Wystawiający', 'Issuer'), draft.issuer),
      ],
    );
    return ConfirmResult(summary, () async {
      if (formatIsoDate(ctx.now()) != draft.date) {
        throw StateError('Draft date changed');
      }
      await store.withClock(ctx.now).insertNew(draft);
      final historyId = 'confined_space.prepare:${draft.id}';
      await AssistantHistoryStore.instance.add(AssistantHistoryEntry(
          id: historyId,
          kind: id,
          summary: '${draft.location} · ${draft.description}',
          recordId: draft.id,
          at: ctx.now(),
          byVoice: m.utterance?.byVoice ?? false));
      return () async {
        if (!await store.withClock(ctx.now).deleteIfUnchanged(draft)) {
          throw StateError('Draft was edited after confirmation');
        }
        await AssistantHistoryStore.instance.markUndone(historyId);
      };
    }, touchOnly: true, show: ShowInModule(toolId, {'record_id': draft.id}));
  }
}
