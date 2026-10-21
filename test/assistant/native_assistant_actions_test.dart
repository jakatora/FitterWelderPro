import 'package:flutter_test/flutter_test.dart';
import 'package:cut_list_app/assistant/assistant_actions.dart';
import 'package:cut_list_app/assistant/assistant_history.dart';
import 'package:cut_list_app/assistant/assistant_validator.dart';
import 'package:cut_list_app/assistant/core/assistant_actions_port.dart';
import 'package:cut_list_app/assistant/core/brain.dart';
import 'package:cut_list_app/assistant/core/skill.dart';
import 'package:cut_list_app/assistant/skills/skill_catalog.dart';
import 'package:cut_list_app/assistant/skills/own_data/my_params_skill.dart';
import 'package:cut_list_app/database/db.dart';
import 'package:cut_list_app/database/weld_param_dao.dart';
import 'package:cut_list_app/database/weld_journal_dao.dart';
import 'package:cut_list_app/domain/weld_journal/weld_entry.dart';
import 'package:cut_list_app/i18n/app_language.dart';
import 'package:cut_list_app/models/weld_param.dart';
import '../support/test_database.dart';
import '../test_prefs.dart';

const draft = WeldParamDraft(
    material: 'SS', process: 'TIG', filler: false, wallMm: 2, currentA: 60);
final at = DateTime(2026, 10, 21, 12, 34);

class LostParameterReply extends WeldParamDao {
  bool first = true;
  @override
  Future<bool> insertAssistantIdempotent(WeldParam p) async {
    final ok = await super.insertAssistantIdempotent(p);
    if (first) {
      first = false;
      throw StateError('completion lost');
    }
    return ok;
  }
}

class LostJournalReply extends WeldJournalDao {
  bool first = true;
  @override
  Future<bool> insertAssistantIfAvailable(WeldEntry e,
      {required String by}) async {
    final ok = await super.insertAssistantIfAvailable(e, by: by);
    if (first) {
      first = false;
      throw StateError('completion lost');
    }
    return ok;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  useTestDatabase();
  setUp(() async {
    seedFreshInstall();
    AssistantHistoryStore.instance.resetForTest();
    final db = await AppDatabase.get();
    await db.delete('weld_params');
    await db.delete(WeldJournalDao.historyTable);
    await db.delete(WeldJournalDao.repairsTable);
    await db.delete(WeldJournalDao.table);
  });
  AssistantActions actions(
          {WeldParamDao? parameters, WeldJournalDao? journal}) =>
      AssistantActions(
          parameters: parameters,
          journal: journal,
          now: () => at,
          stamp: () async => 'Spawacz testowy');
  Future<PreparedJournal> prepare(AssistantActions a,
          {String number = '7', String project = 'Blok A'}) async =>
      (await a.prepareJournal(
          WeldJournalDraft(weldNo: number, project: project, wps: 'WPS-1'),
          byVoice: false,
          lang: AppLanguage.pl)) as PreparedJournal;
  test(
      'parameter summary does not save, commit is idempotent and actual undo removes only its own row',
      () async {
    final a = actions();
    a.weldParamSummary(draft, byVoice: true, lang: AppLanguage.pl);
    expect(await a.parameters.listAll(), isEmpty);
    final undo =
        await a.saveWeldParam(draft, byVoice: true, lang: AppLanguage.pl);
    await a.saveWeldParam(draft, byVoice: true, lang: AppLanguage.pl);
    final row = (await a.parameters.listAll()).single;
    expect(row.amps, 60);
    expect(row.wallThicknessMm, 2);
    expect(row.note, contains('Głosowo, 2026-10-21 12:34'));
    expect(AssistantHistoryStore.instance.entries, hasLength(1));
    await undo!();
    await undo();
    expect(await a.parameters.listAll(), isEmpty);
    expect(AssistantHistoryStore.instance.entries.single.undone, isTrue);
  });
  test(
      'parameter manual edit is protected even when timestamp remains identical',
      () async {
    final a = actions();
    final undo =
        await a.saveWeldParam(draft, byVoice: false, lang: AppLanguage.pl);
    final row = (await a.parameters.listAll()).single;
    await (await AppDatabase.get()).update('weld_params', {'amps': 75},
        where: 'id = ?', whereArgs: [row.id]);
    await expectLater(undo!(), throwsStateError);
    expect((await a.parameters.listAll()).single.amps, 75);
    expect(AssistantHistoryStore.instance.entries.single.undone, isFalse);
  });
  test(
      'retry after lost parameter completion uses the original identity without a duplicate',
      () async {
    final a = actions(parameters: LostParameterReply());
    await expectLater(
        a.saveWeldParam(draft, byVoice: false, lang: AppLanguage.pl),
        throwsStateError);
    final original = (await a.parameters.listAll()).single;
    final undo =
        await a.saveWeldParam(draft, byVoice: false, lang: AppLanguage.pl);
    expect((await a.parameters.listAll()).single.id, original.id);
    expect(AssistantHistoryStore.instance.entries, hasLength(1));
    await undo!();
    expect(await a.parameters.listAll(), isEmpty);
  });
  test(
      'journal preparation is read-only; commit uses native stamp/pending status and undo retains evidence',
      () async {
    final a = actions();
    final p = await prepare(a);
    expect(await a.journal.listAll(), isEmpty);
    final undo = await a.saveJournal(p, byVoice: false, lang: AppLanguage.pl);
    await a.saveJournal(p, byVoice: false, lang: AppLanguage.pl);
    final e = (await a.journal.listAll()).single;
    expect(e.welder, 'Spawacz testowy');
    expect(e.status, WeldStatus.pending);
    expect(e.material, isEmpty);
    expect(e.date, '2026-10-21');
    expect(e.wpsRef, 'WPS-1');
    await undo!();
    final deleted = (await a.journal.listAll()).single;
    expect(deleted.isDeleted, isTrue);
    final rows = await (await AppDatabase.get()).query(
        WeldJournalDao.historyTable,
        where: 'weld_id = ?',
        whereArgs: [e.id]);
    expect(rows.map((r) => r['action']), ['CREATE', 'DELETE']);
    expect(
        await a.prepareJournal(
            const WeldJournalDraft(weldNo: '7', project: 'blok a'),
            byVoice: false,
            lang: AppLanguage.pl),
        isA<JournalWeldNoTaken>());
  });
  test(
      'two approved journal drafts cannot race to save the same project weld number',
      () async {
    final a = actions();
    final p = await prepare(a), q = await prepare(a);
    final result = await Future.wait([p, q].map((x) => a
        .saveJournal(x, byVoice: false, lang: AppLanguage.pl)
        .then((_) => true, onError: (Object _) => false)));
    expect(result.where((x) => x), hasLength(1));
    expect(await a.journal.listAll(), hasLength(1));
  });
  test(
      'journal undo refuses an accepted or edited record and preserves the status history',
      () async {
    final a = actions();
    final p = await prepare(a);
    final undo = await a.saveJournal(p, byVoice: false, lang: AppLanguage.pl);
    final e = (await a.journal.listAll()).single;
    await a.journal.setStatus(e.id, WeldStatus.ok, by: 'manual');
    await expectLater(undo!(), throwsStateError);
    expect((await a.journal.getById(e.id))!.isDeleted, isFalse);
    await a.journal.setStatus(e.id, WeldStatus.pending, by: 'manual');
    await expectLater(undo(), throwsStateError,
        reason:
            'restoring the old values does not erase intervening audit events');
  });
  test(
      'retry after lost journal completion does not duplicate its record or create event',
      () async {
    final a = actions(journal: LostJournalReply());
    final p = await prepare(a);
    await expectLater(a.saveJournal(p, byVoice: false, lang: AppLanguage.pl),
        throwsStateError);
    final first = (await a.journal.listAll()).single;
    final undo = await a.saveJournal(p, byVoice: false, lang: AppLanguage.pl);
    expect((await a.journal.listAll()).single.id, first.id);
    expect(await (await AppDatabase.get()).query(WeldJournalDao.historyTable),
        hasLength(1));
    await undo!();
  });
  test(
      'typed answer to a voice-started native pending field preserves voice provenance',
      () async {
    final a = actions();
    final brain = AssistantBrain(skills: buildSkillCatalog(actions: a));
    final ctx = AssistantContext(
        lang: AppLanguage.pl, modules: const FixedModuleContext());
    final q = await brain.handle(
        Utterance('Zapisz TIG nierdzewka 60 A bez drutu',
            lang: AppLanguage.pl, byVoice: true),
        ctx);
    expect(q.result, isA<AskResult>());
    final r = await brain.handle(Utterance('2 mm', lang: AppLanguage.pl), ctx);
    expect(r.result, isA<ConfirmResult>());
    expect(await a.parameters.listAll(), isEmpty);
    await (r.result as ConfirmResult).perform();
    expect((await a.parameters.listAll()).single.note, contains('Głosowo'));
  });
  test(
      'saved parameter skill reads actual local values and never creates a record',
      () async {
    final a = actions();
    await a.saveWeldParam(draft, byVoice: false, lang: AppLanguage.pl);
    final s = MyParamsSkill();
    final ctx = AssistantContext(
        lang: AppLanguage.pl, modules: const FixedModuleContext());
    final m = s.match(
        Utterance('jaki prąd mam zapisany na nierdzewkę 2 mm',
            lang: AppLanguage.pl),
        ctx)!;
    final r = (await s.run(m, ctx)) as AnswerResult;
    expect(r.answer.lines.single.value, contains('60 A'));
    expect(await a.parameters.listAll(), hasLength(1));
  });
}
