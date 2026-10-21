import 'package:uuid/uuid.dart';

import '../../../domain/hot_work/hot_work_permit.dart';
import '../../../features/hot_work/hot_work_store.dart';
import '../../assistant_history.dart';
import '../../core/skill.dart';

final _prepare = RegExp(
  r'^(?:(?:prosze|please)\s+)*(?:przygotuj|utworz|stworz|prepare|create)\s+'
  r'(?:(?:szkic|protokol|formularz|draft|form)\s+)?'
  r'(?:prac pozarowo niebezpiecznych|prac goracych|hot work)\b',
);
final _labels = RegExp(
  r'\b(miejsce|location|opis(?: prac)?|description|numer zezwolenia|nr zezwolenia|permit number|'
  r'wykonawca|contractor|zabezpiecza|secured by|dozor|dozór|fire watch|wystawiajacy|wystawiający|issuer)\s*:\s*',
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
  'permit number': 'permitNo',
  'wykonawca': 'contractor',
  'contractor': 'contractor',
  'zabezpiecza': 'securedBy',
  'secured by': 'securedBy',
  'dozor': 'fireWatch',
  'dozór': 'fireWatch',
  'fire watch': 'fireWatch',
  'wystawiajacy': 'issuer',
  'wystawiający': 'issuer',
  'issuer': 'issuer',
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

class HotWorkPrepareSkill extends AssistantSkill {
  HotWorkPrepareSkill(
      {this.store = const HotWorkStore(), String Function()? newId})
      : _newId = newId ?? const Uuid().v4;
  final HotWorkStore store;
  final String Function() _newId;

  @override
  String get id => 'hot_work.prepare';
  @override
  String get toolId => 'hot_work';
  @override
  AssistantTier get tier => AssistantTier.c;
  @override
  bool get readOnly => false;
  @override
  bool get safetyCritical => true;
  @override
  List<SkillExample> get examples => const [
        SkillExample('Przygotuj protokół prac pożarowo niebezpiecznych',
            'Prepare hot work form'),
        SkillExample('Utwórz szkic prac gorących', 'Create hot work draft'),
        SkillExample('Przygotuj formularz prac gorących, miejsce: Hala A',
            'Prepare hot work form, location: Hall A'),
        SkillExample(
            'Przygotuj protokół prac gorących, miejsce: Hala A; opis: Spawanie podpory',
            'Prepare hot work form, location: Hall A; description: Welding a support'),
        SkillExample(
            'Przygotuj protokół prac gorących, miejsce: Hala B; opis: Cięcie; numer zezwolenia: P-12',
            'Prepare hot work form, location: Hall B; description: Cutting; permit number: P-12'),
        SkillExample('Stwórz formularz prac gorących', 'Create form hot work'),
      ];
  @override
  List<SkillRejection> get rejections => const [
        SkillRejection('otwórz prace pożarowo niebezpieczne',
            routesTo: 'tool.open'),
        SkillRejection('zaznacz wszystkie kontrole prac gorących'),
        SkillRejection('wpisz pomiar DGW zero'),
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
    final draft = HotWorkPermit.blank(id: _newId(), now: at).copyWith(
      location: value('location'),
      description: value('description'),
      permitNo: value('permitNo'),
      contractor: value('contractor'),
      securedBy: value('securedBy'),
      fireWatch: value('fireWatch'),
      issuer: value('issuer'),
    );
    final summary = AssistantAnswer(
      text: const AssistantText(
          'Przygotuję szkic danych organizacyjnych. Nie jest to zezwolenie na rozpoczęcie pracy; kontrole i pomiary sprawdzasz na stanowisku.',
          'I will prepare an organisational draft. This does not authorise starting work; checks and readings must be verified on site.'),
      lines: [
        AnswerLine(const AssistantText('Data', 'Date'), draft.date),
        AnswerLine(const AssistantText('Miejsce', 'Location'), draft.location),
        AnswerLine(
            const AssistantText('Opis', 'Description'), draft.description),
        if (draft.permitNo.isNotEmpty)
          AnswerLine(const AssistantText('Numer zezwolenia', 'Permit number'),
              draft.permitNo),
        if (draft.contractor.isNotEmpty)
          AnswerLine(
              const AssistantText('Wykonawca', 'Contractor'), draft.contractor),
        if (draft.securedBy.isNotEmpty)
          AnswerLine(const AssistantText('Zabezpiecza', 'Secured by'),
              draft.securedBy),
        if (draft.fireWatch.isNotEmpty)
          AnswerLine(
              const AssistantText('Dozór', 'Fire watch'), draft.fireWatch),
        if (draft.issuer.isNotEmpty)
          AnswerLine(
              const AssistantText('Wystawiający', 'Issuer'), draft.issuer),
      ],
    );
    return ConfirmResult(summary, () async {
      if (hotWorkDate(ctx.now()) != draft.date) {
        throw StateError('Draft date changed');
      }
      await store.withClock(ctx.now).insertNew(draft);
      final historyId = 'hot_work.prepare:${draft.id}';
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
    }, touchOnly: true, show: ShowInModule(toolId, {'permit_id': draft.id}));
  }
}
