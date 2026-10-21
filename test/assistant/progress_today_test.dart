import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cut_list_app/assistant/core/skill.dart';
import 'package:cut_list_app/assistant/core/tool_bridge.dart';
import 'package:cut_list_app/assistant/skills/own_data/journal_last_skill.dart';
import 'package:cut_list_app/assistant/skills/own_data/progress_today_skill.dart';
import 'package:cut_list_app/database/db.dart';
import 'package:cut_list_app/database/weld_journal_dao.dart';
import 'package:cut_list_app/domain/weld_journal/weld_entry.dart';
import 'package:cut_list_app/features/progress/progress_page.dart';
import 'package:cut_list_app/i18n/app_language.dart';
import 'package:cut_list_app/widgets/readout.dart';

import '../support/test_database.dart';
import 'support/assistant_test_support.dart';

WeldEntry weld(String id,
        {String od = '60.3',
        String project = 'Alfa',
        String date = '2026-10-19',
        String who = 'PW01',
        String root = '',
        String cap = '',
        String status = 'PENDING',
        int? deleted}) =>
    WeldEntry.fromRow({
      'id': id,
      'weld_no': id,
      'project_name': project,
      'date': date,
      'od': od,
      'welder': who,
      'root_welder': root,
      'cap_welder': cap,
      'status': status,
      'deleted_at': deleted,
    });

DateTime clock() => DateTime(2026, 10, 19, 12);

void main() {
  useTestDatabase();
  final dao = WeldJournalDao();
  setUp(() async {
    SharedPreferences.setMockInitialValues({
      'welder_identity_v1': jsonEncode({
        'stamp': 'PW01',
        'gdprConsentAt': '2026-01-01T00:00:00',
        'qualificationDeclaredAt': '2026-01-01T00:00:00',
      })
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
    final r = await h.say(text);
    expect(r.match?.skill.id, 'progress.today');
    return r.result as AnswerResult;
  }

  test(
      'SQLite shares DI, uses NPS, includes pending/rejected and excludes other dates',
      () async {
    for (final e in [
      weld('own', root: 'pw01'),
      weld('shared', od: '114.3', who: 'PW02', cap: ' PW01 '),
      weld('missing-od', od: '', status: 'NOK'),
      weld('foreign', who: 'PW02', od: '168.3'),
      weld('deleted', deleted: 1),
      weld('yesterday', date: '2026-10-18'),
      weld('tomorrow', date: '2026-10-20'),
      weld('undated', date: ''),
    ]) {
      await dao.insert(e);
    }
    final db = await AppDatabase.get();
    final before = await db.query('weld_journal', orderBy: 'id');
    final history = await db.query('weld_journal_history', orderBy: 'id');
    final result = await ask('ile cali-średnic zrobiłem dzisiaj?');
    expect(result.answer.lines[0].value, '4 DI');
    expect(result.answer.lines[1].value, '3');
    expect(
        result.answer.lines[2].value, startsWith('1 · DI dzielone po równo'));
    expect(result.answer.lines[3].value, '1');
    expect(result.answer.lines[4].value, '1');
    expect(result.answer.text.pl, contains('2026-10-19'));
    expect(result.show?.fields, {'project': '', 'period': 'today'});
    expect(await db.query('weld_journal', orderBy: 'id'), before);
    expect(await db.query('weld_journal_history', orderBy: 'id'), history);
  });

  test('off-table diameter is approximate; explicit project remains exact',
      () async {
    await dao.insert(weld('approx', od: '100', project: 'Łódź-2'));
    await dao.insert(weld('other', od: '168.3', project: 'Lodz-2'));
    final result = await ask('Ile DI dzisiaj w   projekcie Łódź-2?');
    expect(result.answer.lines.first.value, '≈ 3,9 DI');
    expect(result.answer.lines[1].value, '1');
    expect(result.answer.lines.last.label.pl, 'Przybliżenie DI');
    expect(result.show?.fields, {'project': 'Łódź-2', 'period': 'today'});
    final en =
        await ask('How many DI today in project Łódź-2?', lang: AppLanguage.en);
    expect(en.answer.lines.first.value, '≈ 3.9 DI');
    expect(en.answer.lines.last.value, 'OD / 25.4 mm');
    final missing = await ask('ile DI dzisiaj w projekcie Missing?');
    expect(missing.answer.lines.first.value, '0 DI');
    expect(missing.show, isNull);
  });

  test(
      'missing stamp is not crew output; malformed project cannot broaden scope',
      () async {
    var reads = 0;
    final h = BrainHarness(journal: () async {
      reads++;
      return JournalSnapshot(
          stamp: null, entries: [weld('foreign', who: 'PW02')]);
    });
    final invalid =
        (await h.say('ile DI dzisiaj w-projekcie Alfa')).result as FailedResult;
    expect(invalid.reportMissingCapability, isFalse);
    expect(reads, 0);
    final noOwner = (await h.say('ile DI dzisiaj')).result as AnswerResult;
    expect(noOwner.answer.text.pl, contains('Ustaw stempel'));
    expect(noOwner.answer.lines, isEmpty);
  });

  test('production reader reloads; clean empty data differs from errors',
      () async {
    final skill = ProgressTodaySkill();
    final ctx = AssistantContext(
        lang: AppLanguage.pl, modules: const FixedModuleContext(), now: clock);
    final u = Utterance('ile DI dzisiaj', lang: AppLanguage.pl);
    Future<AnswerResult> read() async =>
        await skill.run(skill.match(u, ctx)!, ctx) as AnswerResult;
    expect((await read()).answer.lines.first.value, '0 DI');
    await dao.insert(weld('fresh'));
    expect((await read()).answer.lines.first.value, '2 DI');
    await dao.softDelete('fresh');
    expect((await read()).answer.lines.first.value, '0 DI');
    final h =
        BrainHarness(journal: () async => throw StateError('secret-path'));
    final error = (await h.say('ile DI dzisiaj')).result as FailedResult;
    expect(error.message.pl, isNot(contains('secret-path')));
    expect(error.reportMissingCapability, isFalse);
  });

  testWidgets(
      'answer fields select real progress page and invalid fields are atomic',
      (t) async {
    ToolBridge.reset();
    await t.runAsync(() async {
      await dao.insert(weld('a'));
      await dao.insert(weld('b', project: 'Beta', od: '114.3'));
    });
    final answer =
        await t.runAsync(() => ask('ile DI dzisiaj w projekcie Alfa'));
    await t.pumpWidget(AppLanguageScope(
        controller: AppLanguageController(AppLanguage.pl),
        child: const MaterialApp(home: ProgressPage(clock: clock))));
    for (var i = 0; i < 6; i++) {
      await flushTestDatabase(t);
      await t.pump(const Duration(milliseconds: 50));
    }
    await t.pumpAndSettle();
    final handle = ToolBridge.instance.current!;
    expect(ToolBridge.instance.isReady(handle), isTrue);
    expect(
        t.widget<Readout>(find.byKey(const ValueKey('progress-total'))).value,
        '6');
    expect(answer!.show!.fields.keys.toSet().difference(handle.supportedFields),
        isEmpty);
    expect(await t.runAsync(() => handle.apply(answer.show!.fields)), isEmpty);
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('progress-project-Alfa')), findsOneWidget);
    expect(
        t
            .widget<ChoiceChip>(
                find.byKey(const ValueKey('progress-period-today')))
            .selected,
        isTrue);
    expect(
        t.widget<Readout>(find.byKey(const ValueKey('progress-total'))).value,
        '2');
    expect(
        await t.runAsync(
            () => handle.apply({'project': 'Missing', 'period': 'today'})),
        {'project'});
    expect(
        await t.runAsync(() =>
            handle.apply({'project': 'Beta', 'period': 'today', 'total': 999})),
        isNotEmpty);
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('progress-project-Alfa')), findsOneWidget);
    expect(t.takeException(), isNull);
  });
}
