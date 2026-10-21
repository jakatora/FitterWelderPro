import 'package:flutter_test/flutter_test.dart';
import 'package:cut_list_app/assistant/core/skill.dart';
import 'package:cut_list_app/assistant/skills/own_data/instruments_due_skill.dart';
import 'package:cut_list_app/database/db.dart';
import 'package:cut_list_app/database/instrument_dao.dart';
import 'package:cut_list_app/domain/instruments/instrument.dart';
import 'package:cut_list_app/i18n/app_language.dart';

import '../support/test_database.dart';
import 'support/assistant_test_support.dart';

Instrument instrument(String id,
        {String name = '',
        String serial = '',
        String last = '',
        String due = '',
        int months = 12,
        InstrumentKind kind = InstrumentKind.pressureGauge}) =>
    Instrument(
        id: id,
        name: name,
        serialNo: serial,
        kind: kind,
        lastCalibration: last,
        dueOverride: due,
        intervalMonths: months,
        createdAt: 1,
        updatedAt: 1);

void main() {
  useTestDatabase();
  setUp(() async => (await AppDatabase.get()).delete(InstrumentDao.table));

  Future<AnswerResult> ask(String text,
      {AppLanguage lang = AppLanguage.pl}) async {
    final h = BrainHarness(lang: lang, instruments: InstrumentDao().listAll);
    final r = await h.say(text);
    expect(r.match?.skill.id, 'instruments.due');
    return r.result as AnswerResult;
  }

  test('real SQLite dates, override, month clamping, unknown and soft deletion',
      () async {
    final dao = InstrumentDao();
    await dao.save(instrument('past', name: 'Past', due: '2026-10-18'));
    await dao.save(instrument('today', name: 'Today', due: '2026-10-19'));
    await dao.save(instrument('unknown', name: 'Unknown'));
    await dao.save(instrument('manual',
        name: 'Manual', last: '2026-01-01', due: '2026-11-01'));
    await dao.save(
        instrument('clamp', name: 'Clamp', last: '2026-01-31', months: 1));
    await dao.save(instrument('deleted', name: 'Deleted', due: '2020-01-01'));
    await dao.softDelete('deleted');
    final db = await AppDatabase.get();
    final before = await db.query(InstrumentDao.table, orderBy: 'id');
    final result = await ask('kiedy kalibracja?');
    expect(result.answer.lines.map((l) => l.label.pl),
        ['Clamp', 'Past', 'Today', 'Manual', 'Unknown']);
    expect(result.answer.lines.first.value, '2026-02-28 · Po terminie');
    expect(result.answer.lines[2].value, '2026-10-19 · Termin w ciągu 30 dni');
    expect(result.answer.lines[3].value, startsWith('2026-11-01'));
    expect(result.answer.lines.last.value, contains('Brak zapisanego terminu'));
    expect(result.answer.text.pl, contains('2026-10-19'));
    expect(await db.query(InstrumentDao.table, orderBy: 'id'), before);
    expect(result.show?.fields, isEmpty);
  });

  test(
      'matches name, exact serial and Polish inflection; no arbitrary fallback',
      () async {
    final dao = InstrumentDao();
    await dao.save(
        instrument('one', name: 'Wika', serial: '123', due: '2026-12-01'));
    await dao.save(instrument('two',
        name: 'Kemppi', serial: '1234', kind: InstrumentKind.weldingMachine));
    expect(
        (await ask('kiedy kalibracja manometru?')).answer.lines, hasLength(1));
    expect((await ask('kiedy kalibracja 123?')).answer.lines.single.label.pl,
        'Wika (123)');
    final named =
        await ask('When is Kemppi due for calibration?', lang: AppLanguage.en);
    expect(named.answer.lines.single.label.en, 'Kemppi (1234)');
    expect(named.answer.lines.single.value, contains('No recorded due date'));
    final missing = await ask('kiedy kalibracja Fluke?');
    expect(missing.answer.lines, isEmpty);
    expect(missing.answer.text.pl, contains('Nie znalazłem'));
  });

  test('empty register is an answer and a read error is not a capability gap',
      () async {
    expect((await ask('kiedy kalibracja?')).answer.text.pl,
        contains('jest pusty'));
    final h =
        BrainHarness(instruments: () async => throw StateError('private-path'));
    final result = (await h.say('kiedy kalibracja?')).result as FailedResult;
    expect(result.reportMissingCapability, isFalse);
    expect(result.message.pl, isNot(contains('private-path')));
  });

  test('no I/O during matching; requests to record or explain are not reads',
      () {
    var reads = 0;
    final s = InstrumentsDueSkill(load: () async {
      reads++;
      return [];
    });
    final ctx = AssistantContext(
        lang: AppLanguage.pl, modules: const FixedModuleContext());
    for (final text in [
      'zapisz kalibrację manometru',
      'jak skalibrować manometr',
      'kalibracja co 12 miesięcy'
    ]) {
      expect(s.match(Utterance(text, lang: AppLanguage.pl), ctx), isNull);
    }
    expect(s.match(Utterance('kiedy kalibracja?', lang: AppLanguage.pl), ctx),
        isNotNull);
    expect(reads, 0);
  });

  test('production reader reloads the register for each question', () async {
    final skill = InstrumentsDueSkill();
    final ctx = AssistantContext(
      lang: AppLanguage.pl,
      modules: const FixedModuleContext(),
      now: () => DateTime(2026, 10, 21),
    );
    final u = Utterance('kiedy kalibracja?', lang: AppLanguage.pl);
    Future<AnswerResult> read() async =>
        await skill.run(skill.match(u, ctx)!, ctx) as AnswerResult;
    expect((await read()).answer.lines, isEmpty);
    await InstrumentDao().save(instrument('live', due: '2026-10-21'));
    expect((await read()).answer.lines.single.value,
        '2026-10-21 · Termin w ciągu 30 dni');
    await InstrumentDao().softDelete('live');
    expect((await read()).answer.lines, isEmpty);
  });
}
