import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cut_list_app/assistant/assistant_ai_client.dart';
import 'package:cut_list_app/database/db.dart';
import 'package:cut_list_app/database/weld_param_dao.dart';
import 'package:cut_list_app/database/weld_journal_dao.dart';
import 'package:cut_list_app/domain/weld_journal/weld_entry.dart';
import 'package:cut_list_app/feedback/feedback_store.dart';
import '../support/test_database.dart';
import 'ai_chat_execution_test.dart' show mount, FixtureSpeech;
import 'global_pipe_slope_flow_test.dart' show say, settle;

const request = 'Zachowaj dla mnie próbę na później: nierdzewka, TIG, '
    'ścianka 2 milimetry, 60 amperów, bez spoiwa. Następnie przypomnij '
    'jaki prąd mam zapisany na nierdzewkę 2 mm.';
const plan = AiCommandPlan(
    'execute',
    [
      AiCommandStep('legacy.save', 'Zapisz TIG nierdzewka 2 mm 60 A bez drutu'),
      AiCommandStep(
          'params.saved', 'Jaki prąd mam zapisany na nierdzewkę 2 mm'),
    ],
    '');

void main() {
  useTestDatabase();
  setUp(() async {
    final db = await AppDatabase.get();
    await db.delete('weld_params');
    await db.delete(WeldJournalDao.historyTable);
    await db.delete(WeldJournalDao.repairsTable);
    await db.delete(WeldJournalDao.table);
  });
  testWidgets(
      'compound save and read waits for native confirmation then reads actual row',
      (t) async {
    var calls = 0;
    final fixture = jsonDecode(
        File('test/fixtures/assistant_ai_actual_haiku_records.json')
            .readAsStringSync()) as Map;
    await mount(t, interpret: (r) async {
      calls++;
      expect(r['text'], fixture['text']);
      return AiCommandPlan.fromJson(
          fixture['proposal'], {'legacy.save', 'params.saved'});
    });
    await say(t, request);
    expect(calls, 1);
    expect(await t.runAsync(() => WeldParamDao().listAll()), isEmpty);
    final save = find.byKey(const Key('assistant-local-save'));
    expect(save, findsOneWidget);
    await t.ensureVisible(save);
    await settle(t);
    await t.tap(save);
    await settle(t);
    final rows = (await t.runAsync(() => WeldParamDao().listAll()))!;
    expect(rows, hasLength(1));
    expect(rows.single.amps, 60);
    expect(find.textContaining('Zapisane parametry'), findsOneWidget);
    expect(calls, 1);
  });
  testWidgets('compound command cannot partially execute without AI consent',
      (t) async {
    var calls = 0;
    await mount(t, consent: false, interpret: (_) async {
      calls++;
      return plan;
    });
    await say(t, request);
    expect(calls, 0);
    expect(await t.runAsync(() => WeldParamDao().listAll()), isEmpty);
    expect(
        find.textContaining('Polecenie zawiera kilka działań'), findsOneWidget);
    expect(find.byKey(const Key('assistant-local-save')), findsNothing);
    expect(await t.runAsync(() => FeedbackStore.instance.list()), isEmpty);
  });
  testWidgets('compound command cannot partially execute during AI outage',
      (t) async {
    await mount(t,
        interpret: (_) async => throw const AssistantAiUnavailable(503));
    await say(t, request);
    expect(await t.runAsync(() => WeldParamDao().listAll()), isEmpty);
    expect(
        find.textContaining('Nie wykonano żadnego działania'), findsOneWidget);
    expect(find.byKey(const Key('assistant-local-save')), findsNothing);
  });
  testWidgets(
      'voice plan asks wall, accepts typed reply and saves voice provenance',
      (t) async {
    final speech = FixtureSpeech();
    var calls = 0;
    await mount(t, speech: speech, interpret: (_) async {
      calls++;
      return const AiCommandPlan(
          'execute',
          [
            AiCommandStep(
                'legacy.save', 'Zapisz TIG nierdzewka 60 A bez drutu'),
            AiCommandStep('params.saved', 'Pokaż moje parametry TIG'),
          ],
          '');
    });
    await t.tap(find.byKey(const Key('assistant-mic')));
    await settle(t);
    speech.emit(
        'Zachowaj próbę TIG, nierdzewka, 60 amperów, bez spoiwa. Następnie pokaż moje parametry TIG.');
    await settle(t);
    expect(calls, 1);
    expect(find.text('Jaka grubość ścianki w mm?'), findsOneWidget);
    expect(await t.runAsync(() => WeldParamDao().listAll()), isEmpty);
    await say(t, '2 mm');
    final save = find.byKey(const Key('assistant-local-save'));
    expect(save, findsOneWidget);
    await t.ensureVisible(save);
    await settle(t);
    await t.tap(save);
    await settle(t);
    final row = (await t.runAsync(() => WeldParamDao().listAll()))!.single;
    expect(row.wallThicknessMm, 2);
    expect(row.note, contains('Głosowo'));
    expect(find.textContaining('Zapisane parametry'), findsOneWidget);
    expect(calls, 1);
  });
  testWidgets(
      'AI journal plan preserves WPS through duplicate and same-project replies',
      (t) async {
    var calls = 0;
    await mount(t,
        now: () => DateTime(2026, 10, 21, 12, 34),
        welderStamp: () async => 'Jan Testowy / 123',
        interpret: (_) async {
          calls++;
          return const AiCommandPlan(
              'execute',
              [
                AiCommandStep('legacy.journal',
                    'Dodaj do dziennika spoinę nr 7 projekt Blok A WPS-1'),
                AiCommandStep('legacy.journal',
                    'Dodaj do dziennika spoinę nr 7 projekt Blok A WPS-2'),
                AiCommandStep(
                    'legacy.journal', 'Dodaj do dziennika spoinę nr 9 WPS-3'),
              ],
              '');
        });
    Future<void> save() async {
      final button = find.byKey(const Key('assistant-local-save'));
      expect(button, findsOneWidget);
      await t.ensureVisible(button);
      await settle(t);
      await t.tap(button);
      await settle(t);
    }

    await say(t,
        'Zanotuj spoinę 7 w Blok A WPS-1. Następnie dopisz drugą z WPS-2 i trzecią 9 WPS-3 w tym samym projekcie.');
    expect(await t.runAsync(() => WeldJournalDao().listAll()), isEmpty);
    await save();
    expect(find.textContaining('podaj inny numer'), findsOneWidget,
        reason: find
            .byType(Text)
            .evaluate()
            .map((e) => (e.widget as Text).data)
            .join(' | '));
    await say(t, '8');
    expect((await t.runAsync(() => WeldJournalDao().listAll()))!, hasLength(1));
    await save();
    await say(t, 'ten sam');
    expect((await t.runAsync(() => WeldJournalDao().listAll()))!, hasLength(2));
    await save();
    final rows = (await t.runAsync(() => WeldJournalDao().listAll()))!;
    expect(rows, hasLength(3));
    expect({for (final r in rows) r.weldNo: r.wpsRef},
        {'7': '1', '8': '2', '9': '3'});
    for (final r in rows) {
      expect(r.projectName, 'Blok A');
      expect(r.welder, 'Jan Testowy / 123');
      expect(r.date, '2026-10-21');
      expect(r.status, WeldStatus.pending);
    }
    expect(calls, 1);
  });
}
