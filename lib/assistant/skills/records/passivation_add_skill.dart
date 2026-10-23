import 'dart:convert';

import 'package:uuid/uuid.dart';

import '../../../database/passivation_dao.dart';
import '../../../domain/passivation/passivation_record.dart';
import '../../../domain/weld_journal/weld_dates.dart';
import '../../../i18n/app_language.dart';
import '../../../services/welder_identity.dart';
import '../../assistant_history.dart';
import '../../core/skill.dart';

final _add = RegExp(
  r'^(?:(?:prosze|please)\s+)*(?:dodaj|zapisz|wpisz|zarejestruj|add|log|record|save)\s+'
  r'(?:(?:nowy|nowa|nowe|new|a)\s+)?(?:wpis\s+|entry\s+(?:of\s+)?)?'
  r'(?:pasywacj\w*|trawieni\w*|passivation|pickling)\b',
);

/// Prośba o nowy wpis w rejestrze pasywacji (nie pytanie o jego stan).
bool isPassivationAddRequest(String folded) => _add.hasMatch(folded);

final _labels = RegExp(
  r'(?<![A-Za-z0-9ąćęłńóśźżĄĆĘŁŃÓŚŹŻ])(linia|line|pakiet|test package|obszar|zakres|area|środek|srodek|'
  r'pasta|agent|partia|batch|czas|dwell|temperatura|temp|płukanie|plukanie|'
  r'rinse|test|wynik|result|uwagi|notes|zabieg|treatment)\s*:\s*',
  caseSensitive: false,
);
const _names = {
  'linia': 'line',
  'line': 'line',
  'pakiet': 'testPackage',
  'test package': 'testPackage',
  'obszar': 'area',
  'zakres': 'area',
  'area': 'area',
  'środek': 'agent',
  'srodek': 'agent',
  'pasta': 'agent',
  'agent': 'agent',
  'partia': 'agentBatch',
  'batch': 'agentBatch',
  'czas': 'dwell',
  'dwell': 'dwell',
  'temperatura': 'temp',
  'temp': 'temp',
  'płukanie': 'rinse',
  'plukanie': 'rinse',
  'rinse': 'rinse',
  'test': 'testMethod',
  'wynik': 'result',
  'result': 'result',
  'uwagi': 'notes',
  'notes': 'notes',
  'zabieg': 'treatment',
  'treatment': 'treatment',
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

String _plain(String raw) => raw
    .toLowerCase()
    .replaceAll(RegExp(r'[^a-ząćęłńóśźż+ ]'), ' ')
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim();

/// Zabieg z pola albo z polecenia („zapisz trawienie”); null = nieczytelny.
String? _treatment(String field, String folded) {
  final v = _plain(field);
  final both = RegExp(r'(trawien\w*|pickling).*(pasywac\w*|passivation)|'
      r'(pasywac\w*|passivation).*(trawien\w*|pickling)|^oba$|^both$');
  if (v.isNotEmpty) {
    if (both.hasMatch(v)) return PassivationTreatment.both;
    if (RegExp(r'^(?:trawienie|pickling)$').hasMatch(v)) {
      return PassivationTreatment.pickling;
    }
    if (RegExp(r'^(?:pasywacja|passivation)$').hasMatch(v)) {
      return PassivationTreatment.passivation;
    }
    return null;
  }
  if (both.hasMatch(folded)) return PassivationTreatment.both;
  if (RegExp(r'\b(?:trawieni\w*|pickling)\b').hasMatch(folded)) {
    return PassivationTreatment.pickling;
  }
  return PassivationTreatment.passivation;
}

/// Wynik testu; brak pola = bez wyniku (test nie zawsze jest robiony).
String? _testResult(String raw) {
  final v = _plain(raw);
  if (v.isEmpty) return PassivationResult.none;
  if (const {'ok', 'dobry', 'pozytywny', 'zgodny', 'pass', 'passed', 'good'}
      .contains(v)) {
    return PassivationResult.ok;
  }
  if (const {
    'nok',
    'n ok',
    'zły',
    'zly',
    'negatywny',
    'niezgodny',
    'fail',
    'failed',
    'not ok'
  }.contains(v)) {
    return PassivationResult.nok;
  }
  return null;
}

/// „60 min”, „1,5”, „20 °C”, „5 µS/cm” → liczba; null = nieczytelna.
double? _number(String raw) {
  final m = RegExp(r'^-?\d+(?:[.,]\d+)?').firstMatch(raw.trim());
  return m == null ? null : parsePassivationNumber(m.group(0)!);
}

/// Nowy wpis w rejestrze trawienia / pasywacji konta — po dotknięciu
/// „Potwierdź”, z „Cofnij”. Parametry wiążące są w karcie produktu; rejestr
/// zapisuje, co zrobiono.
class PassivationAddSkill extends AssistantSkill {
  PassivationAddSkill({
    PassivationDao? dao,
    Future<String?> Function()? stamp,
    String Function()? newId,
  })  : _dao = dao,
        _stamp = stamp ??
            (() async => (await WelderIdentityService.instance.get())?.stamp),
        _newId = newId ?? const Uuid().v4;
  final PassivationDao? _dao;
  final Future<String?> Function() _stamp;
  final String Function() _newId;

  PassivationDao get _store => _dao ?? PassivationDao();

  @override
  String get id => 'passivation.add';
  @override
  String get toolId => 'passivation';
  @override
  AssistantTier get tier => AssistantTier.c;
  @override
  bool get readOnly => false;
  @override
  Set<String> get literalReplySlots => const {'line'};
  @override
  bool get safetyCritical => true;
  // Model AI widzi tylko trzy pierwsze przykłady: pierwszy pokazuje
  // wszystkie pola, drugi — trawienie z obszarem, trzeci — oba zabiegi.
  @override
  List<SkillExample> get examples => const [
        SkillExample(
            'Zapisz pasywację, linia: WFI-101; pakiet: TP-12; środek: pasta; '
                'partia: B-7; czas: 60 min; temperatura: 20; płukanie: 4 µS/cm; '
                'test: ferroksyl; wynik: OK; uwagi: bez przebarwień',
            'Log a passivation, line: WFI-101; test package: TP-12; agent: paste; '
                'batch: B-7; dwell: 60 min; temp: 20; rinse: 4 µS/cm; '
                'test: ferroxyl; result: OK; notes: no tint'),
        SkillExample('Zapisz trawienie, obszar: spoiny W-001 do W-040',
            'Log a pickling, area: welds W-001 to W-040'),
        SkillExample('Zapisz trawienie i pasywację, pakiet: TP-12',
            'Log a pickling and passivation, test package: TP-12'),
        SkillExample('Zapisz pasywację', 'Log a passivation'),
        SkillExample('Zapisz pasywację, linia: WFI-101',
            'Log a passivation, line: WFI-101'),
        SkillExample(
            'Dodaj wpis pasywacji, linia: PW-3; test: ferroksyl; wynik: NOK',
            'Add a passivation entry, line: PW-3; test: ferroxyl; result: NOK'),
      ];
  @override
  List<SkillRejection> get rejections => const [
        SkillRejection('ile pasywacji w tym tygodniu',
            routesTo: 'passivation.status'),
        SkillRejection('otwórz pasywację', routesTo: 'tool.open'),
        SkillRejection('jak zrobić pasywację stali nierdzewnej'),
      ];

  @override
  SkillMatch? match(Utterance u, AssistantContext ctx) =>
      isPassivationAddRequest(u.folded)
          ? SkillMatch(this, .97, slots: _fields(u.raw), utterance: u)
          : null;

  @override
  Map<String, Object?>? fillSlot(
      String slot, Utterance u, AssistantContext ctx) {
    final fields = _fields(u.raw);
    if (fields.containsKey(slot)) return fields;
    if (fields.isNotEmpty) return null;
    if (slot == 'line' && u.raw.trim().isNotEmpty) {
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
    final treatment = _treatment(value('treatment'), m.utterance?.folded ?? '');
    final testResult = _testResult(value('result'));
    if (treatment == null || testResult == null) {
      return const FailedResult(AssistantText(
          'Zabieg: trawienie, pasywacja albo oba; wynik testu: OK albo NOK.',
          'Treatment: pickling, passivation or both; test result: OK or NOK.'));
    }
    double? number(String key) =>
        value(key).isEmpty ? null : _number(value(key));
    for (final key in ['dwell', 'temp', 'rinse']) {
      if (value(key).isNotEmpty && number(key) == null) {
        return const FailedResult(AssistantText(
            'Czas, temperaturę i płukanie podaj liczbą, np. „czas: 60 min”.',
            'Give dwell, temperature and rinse as numbers, e.g. “dwell: 60 min”.'));
      }
    }
    if (value('line').isEmpty &&
        value('testPackage').isEmpty &&
        value('area').isEmpty) {
      return AskResult(
          'line',
          const AssistantText(
              'Której linii albo pakietu testowego dotyczy wpis?',
              'Which line or test package is this entry for?'),
          partial: m);
    }
    var by = '';
    try {
      by = (await _stamp())?.trim() ?? '';
    } catch (_) {}
    final at = ctx.now();
    final record = PassivationRecord(
      id: _newId(),
      date: isoDate(at),
      treatment: treatment,
      line: value('line'),
      testPackage: value('testPackage'),
      area: value('area'),
      agent: value('agent'),
      agentBatch: value('agentBatch'),
      dwellMin: number('dwell'),
      tempC: number('temp'),
      rinseUsCm: number('rinse'),
      testMethod: value('testMethod'),
      testResult: testResult,
      byStamp: by,
      notes: value('notes'),
      createdAt: at.millisecondsSinceEpoch,
      updatedAt: at.millisecondsSinceEpoch,
    );
    final en = ctx.lang == AppLanguage.en;
    String fmt(double v) =>
        (v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toString())
            .replaceAll('.', en ? '.' : ',');
    final summary = AssistantAnswer(
      text: const AssistantText(
          'Zapiszę wpis w rejestrze trawienia i pasywacji. Parametry wiążące są w karcie produktu i specyfikacji — rejestr zapisuje, co zrobiono.',
          'I will add an entry to the pickling and passivation register. Binding parameters are in the product data sheet and the specification — the register records what was done.'),
      lines: [
        AnswerLine(const AssistantText('Data', 'Date'), record.date),
        AnswerLine(const AssistantText('Zabieg', 'Treatment'),
            PassivationTreatment.label(treatment, en: en)),
        if (record.line.isNotEmpty)
          AnswerLine(const AssistantText('Linia', 'Line'), record.line),
        if (record.testPackage.isNotEmpty)
          AnswerLine(const AssistantText('Pakiet testowy', 'Test package'),
              record.testPackage),
        if (record.area.isNotEmpty)
          AnswerLine(const AssistantText('Obszar', 'Area'), record.area),
        if (record.agent.isNotEmpty)
          AnswerLine(const AssistantText('Środek', 'Agent'), record.agent),
        if (record.agentBatch.isNotEmpty)
          AnswerLine(const AssistantText('Partia', 'Batch'), record.agentBatch),
        if (record.dwellMin != null)
          AnswerLine(const AssistantText('Czas', 'Dwell'),
              '${fmt(record.dwellMin!)} min'),
        if (record.tempC != null)
          AnswerLine(const AssistantText('Temperatura', 'Temperature'),
              '${fmt(record.tempC!)} °C'),
        if (record.rinseUsCm != null)
          AnswerLine(const AssistantText('Płukanie', 'Rinse'),
              '${fmt(record.rinseUsCm!)} µS/cm'),
        if (record.testMethod.isNotEmpty)
          AnswerLine(const AssistantText('Test', 'Test'), record.testMethod),
        if (record.testResult.isNotEmpty)
          AnswerLine(const AssistantText('Wynik testu', 'Test result'),
              record.testResult),
        if (record.notes.isNotEmpty)
          AnswerLine(const AssistantText('Uwagi', 'Notes'), record.notes),
      ],
    );
    return ConfirmResult(summary, () async {
      if (isoDate(ctx.now()) != record.date) {
        throw StateError('Entry date changed');
      }
      final dao = _store;
      if (await dao.byId(record.id) != null) {
        throw StateError('Entry already exists');
      }
      await dao.save(record);
      final saved = await dao.byId(record.id);
      final historyId = 'passivation.add:${record.id}';
      await AssistantHistoryStore.instance.add(AssistantHistoryEntry(
          id: historyId,
          kind: id,
          summary: [
            PassivationTreatment.label(treatment, en: en),
            record.line,
            record.testPackage,
            record.area,
          ].where((s) => s.isNotEmpty).join(' · '),
          recordId: record.id,
          at: ctx.now(),
          byVoice: m.utterance?.byVoice ?? false));
      return () async {
        final now = await dao.byId(record.id);
        if (saved == null ||
            now == null ||
            now.isDeleted ||
            jsonEncode(now.toRow()) != jsonEncode(saved.toRow())) {
          throw StateError('Entry was edited after confirmation');
        }
        await dao.softDelete(record.id);
        await AssistantHistoryStore.instance.markUndone(historyId);
      };
    }, touchOnly: true, show: const ShowInModule('passivation'));
  }
}
