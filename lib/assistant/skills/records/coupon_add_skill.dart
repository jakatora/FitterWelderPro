import 'dart:convert';

import 'package:uuid/uuid.dart';

import '../../../database/coupon_dao.dart';
import '../../../domain/weld_journal/coupon_entry.dart';
import '../../../domain/weld_journal/weld_dates.dart';
import '../../../i18n/app_language.dart';
import '../../../services/welder_identity.dart';
import '../../assistant_history.dart';
import '../../core/skill.dart';

final _add = RegExp(
  r'^(?:(?:prosze|please)\s+)*(?:(?:dodaj|zapisz|wpisz|zarejestruj|add|log|record|save)\s+(?:(?:nowy|new|a)\s+){0,2}|(?:nowy|new)\s+)'
  r'(?:kupon|coupon)(?:\s+(?:probny|testowy|test))?\b',
);

/// Kupon do spoiny („dodaj kupon do spoiny W-12”) to operacja dziennika.
final _toWeld = RegExp(r'\b(?:do spoiny|to (?:the )?weld)\b');

/// Prośba o nowy wpis w logu kuponów (nie pytanie o stan logu).
bool isCouponAddRequest(String folded) =>
    _add.hasMatch(folded) && !_toWeld.hasMatch(folded);

final _labels = RegExp(
  r'(?<![A-Za-z0-9ąćęłńóśźżĄĆĘŁŃÓŚŹŻ])(spawacz|welder|stempel|stamp|maszyna|machine|spawarka|zgrzewarka|'
  r'głowica|glowica|head|wymiar|rozmiar|size|program|tlen|o2|oxygen|'
  r'wynik|result|uwagi|notes)\s*:\s*',
  caseSensitive: false,
);
const _names = {
  'spawacz': 'welder',
  'welder': 'welder',
  'stempel': 'welder',
  'stamp': 'welder',
  'maszyna': 'machine',
  'machine': 'machine',
  'spawarka': 'machine',
  'zgrzewarka': 'machine',
  'głowica': 'machine',
  'glowica': 'machine',
  'head': 'machine',
  'wymiar': 'size',
  'rozmiar': 'size',
  'size': 'size',
  'program': 'programNo',
  'tlen': 'o2',
  'o2': 'o2',
  'oxygen': 'o2',
  'wynik': 'result',
  'result': 'result',
  'uwagi': 'notes',
  'notes': 'notes',
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
        .replaceAll(RegExp(r'[;,.]+$'), '')
        .trim();
    if (result.containsKey(key) && result[key] != value) {
      result['ambiguous'] = true;
    }
    result[key] = value;
  }
  return result;
}

/// Wynik podany słowami → kod logu; null = nieczytelny. Domyślnie (brak
/// pola) kupon czeka na ocenę — przyjmuje się go świadomie, nie domyślnie.
String? _result(String raw) {
  final v = raw
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-ząćęłńóśźż ]'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  if (v.isEmpty) return CouponResult.pending;
  const pending = {
    'do oceny',
    'czeka',
    'czeka na ocenę',
    'oczekuje',
    'nieoceniony',
    'pending',
    'to assess',
    'awaiting',
    'not assessed'
  };
  const nok = {
    'nok',
    'n ok',
    'zły',
    'zly',
    'odrzucony',
    'negatywny',
    'nie przeszedł',
    'nie przeszedl',
    'niezgodny',
    'rejected',
    'fail',
    'failed',
    'not ok'
  };
  const ok = {
    'ok',
    'dobry',
    'przeszedł',
    'przeszedl',
    'pozytywny',
    'zgodny',
    'przyjęty',
    'przyjety',
    'pass',
    'passed',
    'accepted',
    'good'
  };
  if (pending.contains(v)) return CouponResult.pending;
  if (nok.contains(v)) return CouponResult.nok;
  if (ok.contains(v)) return CouponResult.ok;
  return null;
}

/// Nowy kupon w logu kuponów konta — po dotknięciu „Potwierdź”, z „Cofnij”.
class CouponAddSkill extends AssistantSkill {
  CouponAddSkill({
    CouponDao? dao,
    Future<String?> Function()? stamp,
    String Function()? newId,
  })  : _dao = dao,
        _stamp = stamp ??
            (() async => (await WelderIdentityService.instance.get())?.stamp),
        _newId = newId ?? const Uuid().v4;
  final CouponDao? _dao;
  final Future<String?> Function() _stamp;
  final String Function() _newId;

  CouponDao get _store => _dao ?? CouponDao();

  @override
  String get id => 'coupon.add';
  @override
  String get toolId => 'coupon_log';
  @override
  AssistantTier get tier => AssistantTier.c;
  @override
  bool get readOnly => false;
  @override
  Set<String> get literalReplySlots => const {'welder'};
  @override
  bool get safetyCritical => true;
  // Model AI widzi tylko trzy pierwsze przykłady: pierwszy pokazuje
  // wszystkie pola, które ten zapis przyjmuje.
  @override
  List<SkillExample> get examples => const [
        SkillExample(
            'Dodaj kupon, spawacz: JK-12; maszyna: M-3; wymiar: 2 cale; '
                'program: 4; tlen: 20 ppm; wynik: OK; uwagi: przetop równy',
            'Add a coupon, welder: JK-12; machine: M-3; size: 2 in; '
                'program: 4; oxygen: 20 ppm; result: OK; notes: even root'),
        SkillExample(
            'Dodaj kupon, wynik: do oceny', 'Add a coupon, result: pending'),
        SkillExample('Dodaj kupon', 'Add a coupon'),
        SkillExample('Zapisz nowy kupon, spawacz: JK-12',
            'Log a new coupon, welder: JK-12'),
        SkillExample('Zapisz kupon, maszyna: M-3; tlen: 20 ppm',
            'Log a coupon, machine: M-3; oxygen: 20 ppm'),
        SkillExample('Dodaj kupon, spawacz: AB-1; wynik: NOK',
            'Add a coupon, welder: AB-1; result: NOK'),
      ];
  @override
  List<SkillRejection> get rejections => const [
        SkillRejection('ile kuponów dzisiaj', routesTo: 'coupons.status'),
        SkillRejection('otwórz log kuponów', routesTo: 'tool.open'),
        SkillRejection('podepnij kupon K-7 do spoiny W-12'),
      ];

  @override
  SkillMatch? match(Utterance u, AssistantContext ctx) =>
      isCouponAddRequest(u.folded)
          ? SkillMatch(this, .97, slots: _fields(u.raw), utterance: u)
          : null;

  @override
  Map<String, Object?>? fillSlot(
      String slot, Utterance u, AssistantContext ctx) {
    final fields = _fields(u.raw);
    if (fields.containsKey(slot)) return fields;
    if (fields.isNotEmpty) return null;
    if (slot == 'welder' && u.raw.trim().isNotEmpty) {
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
                (m.slots[key] as String).length > 500))) {
      return const FailedResult(AssistantText(
          'Podaj jedną wartość każdego pola, maksymalnie 500 znaków.',
          'Give one value per field, up to 500 characters.'));
    }
    String value(String key) => (m.slots[key] as String? ?? '').trim();
    final result = _result(value('result'));
    if (result == null) {
      return const FailedResult(AssistantText(
          'Wynik kuponu: OK, NOK albo „do oceny”.',
          'Coupon result: OK, NOK or “pending”.'));
    }
    double? o2;
    if (value('o2').isNotEmpty) {
      o2 = parseO2Ppm(value('o2'));
      if (o2 == null) {
        return const FailedResult(AssistantText(
            'Nie rozumiem odczytu tlenu — podaj ppm, np. „tlen: 20 ppm”.',
            'I cannot read the oxygen value — give ppm, e.g. “oxygen: 20 ppm”.'));
      }
    }
    var welder = value('welder');
    if (welder.isEmpty) {
      try {
        welder = (await _stamp())?.trim() ?? '';
      } catch (_) {
        welder = '';
      }
    }
    if (welder.isEmpty) {
      return AskResult(
          'welder',
          const AssistantText('Kto spawał kupon? Podaj stempel spawacza.',
              'Who welded the coupon? Give the welder stamp.'),
          partial: m);
    }
    final entry = CouponEntry(
      id: _newId(),
      date: isoDate(ctx.now()),
      welder: welder,
      machine: value('machine'),
      size: value('size'),
      programNo: value('programNo'),
      o2Ppm: o2,
      result: result,
      notes: value('notes'),
    );
    String resultLabel(bool en) => switch (result) {
          CouponResult.ok => 'OK',
          CouponResult.nok => 'NOK',
          _ => en ? 'pending' : 'do oceny',
        };
    final summary = AssistantAnswer(
      text: AssistantText(
          result == CouponResult.pending
              ? 'Zapiszę kupon w logu jako czekający na ocenę.'
              : 'Zapiszę kupon w logu z wynikiem ${resultLabel(false)} — wynik to Twoja ocena kuponu.',
          result == CouponResult.pending
              ? 'I will log the coupon as awaiting assessment.'
              : 'I will log the coupon with result ${resultLabel(true)} — the result is your assessment.'),
      lines: [
        AnswerLine(const AssistantText('Data', 'Date'), entry.date),
        AnswerLine(const AssistantText('Spawacz', 'Welder'), entry.welder),
        if (entry.machine.isNotEmpty)
          AnswerLine(const AssistantText('Maszyna', 'Machine'), entry.machine),
        if (entry.size.isNotEmpty)
          AnswerLine(const AssistantText('Wymiar', 'Size'), entry.size),
        if (entry.programNo.isNotEmpty)
          AnswerLine(
              const AssistantText('Program', 'Program'), entry.programNo),
        if (o2 != null)
          AnswerLine(
              const AssistantText('Tlen', 'Oxygen'), '${formatO2Ppm(o2)} ppm'),
        AnswerLine(const AssistantText('Wynik', 'Result'),
            resultLabel(ctx.lang == AppLanguage.en)),
        if (entry.notes.isNotEmpty)
          AnswerLine(const AssistantText('Uwagi', 'Notes'), entry.notes),
      ],
    );
    return ConfirmResult(summary, () async {
      if (isoDate(ctx.now()) != entry.date) {
        throw StateError('Coupon date changed');
      }
      final dao = _store;
      await dao.insert(entry, by: welder);
      final historyId = 'coupon.add:${entry.id}';
      await AssistantHistoryStore.instance.add(AssistantHistoryEntry(
          id: historyId,
          kind: id,
          summary: entry.reference,
          recordId: entry.id,
          at: ctx.now(),
          byVoice: m.utterance?.byVoice ?? false));
      return () async {
        final now = await dao.getById(entry.id);
        if (now == null ||
            now.isDeleted ||
            jsonEncode(now.toRow()) != jsonEncode(entry.toRow())) {
          throw StateError('Coupon was edited after confirmation');
        }
        if ((await dao.linkedWelds(entry.id)).isNotEmpty) {
          throw StateError('Coupon is linked to a weld');
        }
        await dao.softDelete(entry.id, by: welder);
        await AssistantHistoryStore.instance.markUndone(historyId);
      };
    }, touchOnly: true, show: const ShowInModule('coupon_log'));
  }
}
