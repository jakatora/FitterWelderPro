import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cut_list_app/assistant/core/skill.dart';
import 'package:cut_list_app/assistant/skills/own_data/journal_last_skill.dart';
import 'package:cut_list_app/database/db.dart';
import 'package:cut_list_app/database/weld_journal_dao.dart';
import 'package:cut_list_app/domain/weld_journal/weld_entry.dart';
import 'package:cut_list_app/i18n/app_language.dart';

import '../support/test_database.dart';
import 'support/assistant_test_support.dart';

WeldEntry weld(String id,
        {String date = '2026-10-19',
        String welder = 'PW01',
        String project = 'Alfa',
        String root = '',
        String cap = '',
        int? deleted}) =>
    WeldEntry.fromRow({
      'id': id,
      'weld_no': id,
      'date': date,
      'welder': welder,
      'root_welder': root,
      'cap_welder': cap,
      'project_name': project,
      'deleted_at': deleted,
      'status': 'PENDING'
    });

void main() {
  useTestDatabase();
  final dao = WeldJournalDao();
  setUp(() async {
    SharedPreferences.setMockInitialValues({
      'welder_identity_v1': jsonEncode({
        'stamp': 'PW01',
        'gdprConsentAt': '2026-01-01T00:00:00',
        'qualificationDeclaredAt': '2026-01-01T00:00:00'
      }),
    });
    final db = await AppDatabase.get();
    await db.delete('weld_journal_history');
    await db.delete('weld_repairs');
    await db.delete('weld_journal');
  });

  Future<AnswerResult> ask(String text,
      {AppLanguage lang = AppLanguage.pl}) async {
    final h = BrainHarness(
        lang: lang, journal: () => readLocalJournal(ownerStamp: 'PW01'));
    final result = await h.say(text);
    expect(result.match?.skill.id, 'journal.last');
    return result.result as AnswerResult;
  }

  test('SQLite selects latest execution date and includes root/cap ownership',
      () async {
    for (final e in [
      weld('largest-number-999', date: '2026-01-01'),
      weld('root', welder: 'PW02', root: ' pw01 '),
      weld('cap', welder: 'PW02', cap: 'PW01'),
      weld('other-person', welder: 'PW02'),
      weld('deleted', deleted: 1),
      weld('bad-date', date: '30.02.2026'),
      weld('empty-date', date: ''),
      weld('future', date: '2026-10-20'),
    ]) {
      await dao.insert(e);
    }
    final db = await AppDatabase.get();
    final rowsBefore = await db.query('weld_journal', orderBy: 'id');
    final historyBefore = await db.query('weld_journal_history', orderBy: 'id');
    final result = await ask('jaka była moja ostatnia spoina?');
    expect(result.answer.lines.take(2).map((l) => l.label.pl),
        ['cap · Alfa', 'root · Alfa']);
    expect(result.answer.text.pl, contains('2026-10-19'));
    expect(result.answer.text.pl, contains('bez godzin'));
    expect(result.answer.lines[2].value, '2');
    expect(result.answer.lines[3].value, '1');
    expect(
        result.answer.lines.first.value, contains('Zapisany status: PENDING'));
    expect(result.show?.fields, isEmpty);
    expect(await db.query('weld_journal', orderBy: 'id'), rowsBefore);
    expect(
        await db.query('weld_journal_history', orderBy: 'id'), historyBefore);
    expect(await db.query('weld_repairs'), isEmpty);
  });

  test('legacy Polish dates normalize, future dates never become last weld',
      () async {
    await dao.insert(weld('old', date: '2026-9-1'));
    await dao.insert(weld('latest', date: '18.10.2026'));
    await dao.insert(weld('planned', date: '2026-10-20'));
    final result = await ask('When did I last weld?', lang: AppLanguage.en);
    expect(result.answer.lines.first.label.en, 'latest · Alfa');
    expect(result.answer.lines.first.value, startsWith('2026-10-18'));
    expect(result.answer.lines.last.label.en, 'Future date — excluded');
    expect(result.answer.text.en, contains('not entry creation order'));
  });

  test('exact project selection preserves accents and punctuation', () async {
    await dao.insert(weld('yes', project: 'Łódź-2'));
    await dao.insert(weld('not-accent', project: 'Lodz-2'));
    await dao.insert(weld('not-hyphen', project: 'Łódź 2'));
    final result = await ask('Podaj moją ostatnią spoinę z projektu Łódź-2?');
    expect(result.answer.lines, hasLength(1));
    expect(result.answer.lines.single.label.pl, 'yes · Łódź-2');
    final en = await ask('Show my last weld from project łódź-2?',
        lang: AppLanguage.en);
    expect(en.answer.lines.single.label.en, 'yes · Łódź-2');
    final spaced = await ask('Ostatnia spoina w   projekcie   Łódź-2?');
    expect(spaced.answer.lines.single.label.pl, 'yes · Łódź-2');
    expect(
        (await ask('ostatnia spoina w projekcie Beta')).answer.lines, isEmpty);
  });

  test('missing owner stamp never falls back to another person', () async {
    await dao.insert(weld('foreign', welder: 'PW02'));
    final result = await ask('ostatnia spoina w dzienniku');
    expect(result.answer.lines, isEmpty);
    expect(result.answer.text.pl, contains('Nie znalazłem'));
    expect((await readLocalJournal(ownerStamp: null)).entries, isEmpty);
    final h = BrainHarness(
        journal: () async => JournalSnapshot(
            stamp: null, entries: [weld('foreign', welder: 'PW02')]));
    final missing = (await h.say('ostatnia spoina')).result as AnswerResult;
    expect(missing.answer.lines, isEmpty);
    expect(missing.answer.text.pl, contains('Ustaw stempel'));
  });

  test('production reader reloads current data and errors are sanitized',
      () async {
    final skill = JournalLastSkill();
    final ctx = AssistantContext(
        lang: AppLanguage.pl,
        modules: const FixedModuleContext(),
        now: () => DateTime(2026, 10, 21));
    final u = Utterance('ostatnia spoina', lang: AppLanguage.pl);
    Future<AnswerResult> read() async =>
        await skill.run(skill.match(u, ctx)!, ctx) as AnswerResult;
    expect((await read()).answer.lines, isEmpty);
    await dao.insert(weld('new', date: '2026-10-21'));
    expect((await read()).answer.lines.single.label.pl, 'new · Alfa');
    await dao.softDelete('new');
    expect((await read()).answer.lines, isEmpty);
    final h =
        BrainHarness(journal: () async => throw StateError('secret-path'));
    final failed = (await h.say('ostatnia spoina')).result as FailedResult;
    expect(failed.reportMissingCapability, isFalse);
    expect(failed.message.pl, isNot(contains('secret-path')));
  });

  test('voice transcript reads data, quoted and negated commands do not',
      () async {
    var reads = 0;
    final h = BrainHarness(journal: () async {
      reads++;
      return JournalSnapshot(stamp: 'PW01', entries: [weld('voice')]);
    });
    for (final text in [
      'nie pokazuj mojej ostatniej spoiny',
      'wyjaśnij polecenie "ostatnia spoina"',
    ]) {
      final r = await h.say(text, byVoice: true);
      expect(r.match?.skill.id, isNot('journal.last'));
    }
    expect(reads, 0);
    final result = await h.say('pokaż moją ostatnią spoinę', byVoice: true);
    expect(result.match?.skill.id, 'journal.last');
    expect(reads, 1);
    expect((result.result as AnswerResult).answer.lines.single.label.pl,
        'voice · Alfa');
  });

  test('unreadable project delimiter does not silently remove selection',
      () async {
    var reads = 0;
    final h = BrainHarness(journal: () async {
      reads++;
      return JournalSnapshot(stamp: 'PW01', entries: [weld('not-selected')]);
    });
    final result = (await h.say('ostatnia spoina w-projekcie Alfa')).result;
    expect(result, isA<FailedResult>());
    expect(reads, 0);
    expect((result as FailedResult).reportMissingCapability, isFalse);
    final corrected = await h.say('ostatnia spoina w projekcie Alfa');
    expect((corrected.result as AnswerResult).answer.lines.single.label.pl,
        'not-selected · Alfa');
    expect(reads, 1);
  });
}
