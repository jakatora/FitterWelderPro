import 'package:cut_list_app/database/coupon_dao.dart';
import 'package:cut_list_app/domain/weld_journal/coupon_entry.dart';
import 'package:cut_list_app/services/welder_qualification_service.dart';
import 'package:cut_list_app/assistant/assistant_actions.dart';
import 'package:cut_list_app/assistant/assistant_history.dart';
import 'package:cut_list_app/assistant/assistant_validator.dart';
import 'package:cut_list_app/assistant/core/assistant_actions_port.dart';
import 'package:cut_list_app/i18n/app_language.dart';
import 'dart:async';
import 'dart:io';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cut_list_app/database/local_record_owner.dart';
import 'package:cut_list_app/domain/weld_journal/weld_journal_settings.dart';
import 'package:cut_list_app/domain/weld_journal/weld_defaults.dart';
import 'package:cut_list_app/services/data_backup.dart';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:cut_list_app/database/db.dart';
import 'package:cut_list_app/database/weld_journal_dao.dart';
import 'package:cut_list_app/services/account_service.dart';
import '../support/test_database.dart';
import '../support/weld_fixtures.dart';

void main() {
  useTestDatabase();
  late AccountService account;
  final dao = WeldJournalDao();
  setUp(() async {
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferences.setMockInitialValues({});
    AssistantHistoryStore.instance.resetForTest();
    final previous = AccountService.instance;
    final client = MockClient((r) async {
      final id = jsonDecode(r.body)['email'];
      return http.Response(
          jsonEncode({
            'token': 'fixture-$id',
            'account': {'id': id}
          }),
          200);
    });
    account = AccountService.forTesting(client);
    AccountService.instance = account;
    addTearDown(() {
      AccountService.instance = previous;
      account.dispose();
      client.close();
    });
    await account.load();
    final db = await AppDatabase.get();
    for (final table in [
      'weld_journal_history',
      'weld_repairs',
      'weld_journal',
      'weld_journal_projects'
    ]) {
      await db.delete(table);
    }
  });
  Future<void> login(String id) => account.signIn(id, 'fixture-password');
  test(
      'journal data belongs to guest or the signed-in account, even with the same stamp',
      () async {
    await dao.insert(weld('guest', welder: 'SAME'));
    await login('A');
    expect(await dao.listAll(), isEmpty);
    expect(await dao.getById('guest'), isNull);
    await dao.insert(weld('a', welder: 'SAME'));
    await login('B');
    expect(await dao.listAll(), isEmpty);
    expect(await dao.getById('a'), isNull);
    await dao.insert(weld('b', welder: 'SAME'));
    await login('A');
    expect((await dao.listAll()).map((e) => e.id), ['a']);
    await account.forgetSession();
    expect((await dao.listAll()).map((e) => e.id), ['guest']);
  });
  test(
      'foreign journal entries, audit history, repairs and project headers cannot be read or changed',
      () async {
    await login('A');
    final entry = weld('a', weldNo: 'W1', welder: 'SAME', status: 'NOK');
    await dao.insert(entry, by: 'SAME');
    await dao.addRepair('a',
        date: '2026-10-22', reason: 'A private repair', by: 'SAME');
    final before = (await dao.getById('a'))!;
    final history = (await dao.history('a')).length;
    final settings = WeldJournalSettingsDao();
    await settings.save(WeldJournalProjectSettings.empty('Shared project')
        .copyWith(company: 'A private company'));
    await login('B');
    expect(await dao.getById('a'), isNull);
    expect(await dao.history('a'), isEmpty);
    expect(await dao.historyFor(['a']), isEmpty);
    await expectLater(
        dao.update(entry.copyWith(notes: 'B overwrite')), throwsStateError);
    await expectLater(dao.setStatus('a', 'OK'), throwsStateError);
    await expectLater(
        dao.addRepair('a', date: '2026-10-22', reason: 'B repair'),
        throwsStateError);
    await expectLater(dao.addChecklist('a', 'B checklist'), throwsStateError);
    await dao.softDelete('a');
    await dao.restore('a');
    expect(await dao.insertAssistantIfAvailable(entry, by: 'SAME'), false);
    expect(await dao.softDeleteAssistantIfUnchanged(entry, by: 'SAME'), false);
    expect(await settings.forProject('Shared project'), isNull);
    await settings.save(WeldJournalProjectSettings.empty('Shared project')
        .copyWith(company: 'B company'));
    expect(
        await dao.insertAssistantIfAvailable(
            weld('b', weldNo: 'W1', welder: 'SAME'),
            by: 'SAME'),
        true);
    expect((await dao.listAll()).map((e) => e.id), ['b']);
    await login('A');
    expect((await dao.getById('a'))!.toRow(), before.toRow());
    expect((await dao.getById('a'))!.repairs, hasLength(1));
    expect(await dao.history('a'), hasLength(history));
    expect((await settings.forProject('Shared project'))!.company,
        'A private company');
  });
  for (final op in ['read', 'write', 'history', 'settings']) {
    test('a delayed $op stays bound to the captured journal owner', () async {
      await login('A');
      await dao.insert(weld('a'));
      final entered = Completer<void>(), release = Completer<void>();
      Future<LocalRecordOwner> delayedOwner() async {
        final owner = await LocalRecordOwner.capture();
        entered.complete();
        await release.future;
        return owner;
      }

      final delayed = WeldJournalDao(owner: delayedOwner);
      final operation = switch (op) {
        'read' => delayed.listAll(),
        'write' => delayed.insert(weld('late')),
        'history' => delayed.history('a'),
        _ => WeldJournalSettingsDao(owner: delayedOwner)
            .save(WeldJournalProjectSettings.empty('Late')),
      };
      final rejected = expectLater(operation, throwsA(isA<AccountException>()));
      await entered.future;
      await login('B');
      release.complete();
      await rejected;
      expect(await dao.listAll(), isEmpty);
      await login('A');
      expect((await dao.listAll()).map((e) => e.id), ['a']);
      expect(await WeldJournalSettingsDao().listAll(), isEmpty);
    });
  }
  test(
      'an assistant prepared owner cannot be rebound to another account for save or undo',
      () async {
    await login('A');
    final owner = await LocalRecordOwner.capture();
    final entry = weld('a');
    expect(
        await dao.insertAssistantIfAvailable(entry,
            by: 'SAME', expectedOwner: owner),
        true);
    expect(
        await dao.insertAssistantIfAvailable(entry,
            by: 'SAME', expectedOwner: owner),
        true);
    await login('B');
    await expectLater(
        dao.insertAssistantIfAvailable(weld('late'),
            by: 'SAME', expectedOwner: owner),
        throwsA(isA<AccountException>()));
    await expectLater(
        dao.softDeleteAssistantIfUnchanged(entry,
            by: 'SAME', expectedOwner: owner),
        throwsA(isA<AccountException>()));
    await login('A');
    expect((await dao.getById('a'))!.isDeleted, false);
  });
  test('remembered journal project and defaults are separate for guest A and B',
      () async {
    await saveLastWeldProject('Guest project');
    await saveWeldDefaults(const WeldEntryDefaults(lastWeldId: 'guest'));
    await login('A');
    expect(await loadLastWeldProject(), '');
    expect((await loadWeldDefaults()).lastWeldId, '');
    await saveLastWeldProject('A project');
    await saveWeldDefaults(const WeldEntryDefaults(lastWeldId: 'a'));
    await login('B');
    expect(await loadLastWeldProject(), '');
    expect((await loadWeldDefaults()).lastWeldId, '');
    await saveLastWeldProject('B project');
    await login('A');
    expect(await loadLastWeldProject(), 'A project');
    expect((await loadWeldDefaults()).lastWeldId, 'a');
    await account.forgetSession();
    expect(await loadLastWeldProject(), 'Guest project');
    expect((await loadWeldDefaults()).lastWeldId, 'guest');
  });
  test(
      'restore copies a foreign journal UUID and remaps history and repairs without replacing its owner',
      () async {
    await login('A');
    await dao.insert(weld('a', status: 'NOK'));
    await dao.addRepair('a', date: '2026-10-22', reason: 'Private repair');
    await WeldJournalSettingsDao().save(
        WeldJournalProjectSettings.empty('Shared')
            .copyWith(company: 'A company'));
    final db = await AppDatabase.get();
    const names = [
      'weld_journal',
      'weld_journal_history',
      'weld_repairs',
      'weld_journal_projects'
    ];
    final source = {
      for (final name in names)
        name: await db
            .query(name, where: 'owner_scope = ?', whereArgs: ['account:A'])
    };
    await login('B');
    await dao.insert(weld('b'));
    await restoreTablesInto(db, source,
        heatPhotosDir: '/fixture',
        restoredPhotoNames: {},
        weldParamsOwner: 'account:B');
    final imported = (await dao.listAll()).single;
    expect(imported.id, isNot('a'));
    expect(imported.id, isNot('b'));
    expect(imported.repairs, hasLength(1));
    expect(imported.repairs.single.weldId, imported.id);
    expect(await dao.history(imported.id),
        hasLength(source['weld_journal_history']!.length));
    expect((await WeldJournalSettingsDao().forProject('Shared'))!.company,
        'A company');
    await login('A');
    expect((await dao.listAll()).single.id, 'a');
    for (final name in names) {
      expect(
          await db
              .query(name, where: 'owner_scope = ?', whereArgs: ['account:A']),
          source[name]);
    }
  });
  test(
      'restore cannot attach a forged history row to a foreign parent and rolls back',
      () async {
    await login('A');
    await dao.insert(weld('a'));
    final db = await AppDatabase.get();
    final foreign = (await db.query('weld_journal_history')).single;
    await login('B');
    await dao.insert(weld('b'));
    await expectLater(
        restoreTablesInto(
            db,
            {
              'weld_journal_history': [foreign]
            },
            heatPhotosDir: '/fixture',
            restoredPhotoNames: {},
            weldParamsOwner: 'account:B'),
        throwsA(isA<BackupFormatException>()));
    expect((await dao.listAll()).single.id, 'b');
    expect(await dao.history('b'), hasLength(1));
    await login('A');
    expect(await dao.history('a'), hasLength(1));
  });
  test('journal snapshot removes every foreign table row and its SQLite bytes',
      () async {
    final dir = await Directory.systemTemp.createTemp('fwp_journal_owner_');
    final file = File('${dir.path}/snapshot.db');
    final db = await databaseFactory.openDatabase(file.path);
    const names = [
      'weld_journal',
      'weld_journal_history',
      'weld_repairs',
      'weld_journal_projects'
    ];
    try {
      for (final name in names) {
        await db.execute(
            'CREATE TABLE $name(id TEXT PRIMARY KEY,owner_scope TEXT,payload TEXT)');
        await db.insert(
            name, {'id': 'a', 'owner_scope': 'account:A', 'payload': 'A kept'});
        await db.insert(name, {
          'id': 'b',
          'owner_scope': 'account:B',
          'payload': 'B_PRIVATE_JOURNAL_6b3f'
        });
      }
      await pruneWeldParamsSnapshot(db, 'account:A');
      for (final name in names) {
        expect((await db.query(name)).map((r) => r['id']), ['a']);
      }
    } finally {
      await db.close();
    }
    expect(latin1.decode(await file.readAsBytes()),
        isNot(contains('B_PRIVATE_JOURNAL_6b3f')));
    await file.delete();
    await dir.delete();
  });
  test(
      'v30 journal migration preserves legacy records, extension values and composite project keys',
      () async {
    final db = await databaseFactory.openDatabase(inMemoryDatabasePath,
        options: OpenDatabaseOptions(singleInstance: false));
    try {
      await AppDatabase.createSchema(db);
      for (final index in [
        'idx_weld_journal_owner',
        'idx_weld_history_owner',
        'idx_weld_repairs_owner'
      ]) {
        await db.execute('DROP INDEX $index');
      }
      for (final name in [
        'weld_journal',
        'weld_journal_history',
        'weld_repairs'
      ]) {
        await db.execute('ALTER TABLE $name DROP COLUMN owner_scope');
      }
      await db.execute('DROP TABLE weld_journal_projects');
      await db.execute(
          'CREATE TABLE weld_journal_projects(project_key TEXT PRIMARY KEY,project_name TEXT,company TEXT,extra TEXT)');
      await db.insert('weld_journal', weld('legacy').toRow());
      await db.insert('weld_journal_history',
          {'id': 'legacy-h', 'weld_id': 'legacy', 'at': 1, 'action': 'CREATE'});
      await db.insert('weld_journal_projects', {
        'project_key': 'legacy',
        'project_name': 'Legacy',
        'company': 'Legacy company',
        'extra': 'Keep extra'
      });
      await AppDatabase.migrate(db, 30, 31);
      expect((await db.query('weld_journal')).single['owner_scope'], 'guest');
      expect((await db.query('weld_journal_history')).single['owner_scope'],
          'guest');
      final old = (await db.query('weld_journal_projects')).single;
      expect(old['owner_scope'], 'guest');
      expect(old['extra'], 'Keep extra');
      await db.insert('weld_journal_projects', {
        'project_key': 'legacy',
        'owner_scope': 'account:A',
        'company': 'A'
      });
      await db.insert('weld_journal_projects', {
        'project_key': 'legacy',
        'owner_scope': 'account:B',
        'company': 'B'
      });
      await AppDatabase.migrate(db, 30, 31);
      expect(await db.query('weld_journal_projects'), hasLength(3));
    } finally {
      await db.close();
    }
  });
  test(
      'the assistant binds actual journal commits, history summaries and undo to the prepared account',
      () async {
    await login('A');
    final actions = AssistantActions(stamp: () async => 'SAME');
    const draft =
        WeldJournalDraft(weldNo: 'W-ACCOUNT', project: 'A_PRIVATE_PROJECT');
    final prepared = await actions.prepareJournal(draft,
        byVoice: false, lang: AppLanguage.pl) as PreparedJournal;
    final undo = await actions.saveJournal(prepared,
        byVoice: false, lang: AppLanguage.pl);
    expect(
        AssistantHistoryStore.instance.entries.single.ownerScope, 'account:A');
    expect(actions.lastJournalProject, 'A_PRIVATE_PROJECT');
    await login('B');
    expect(AssistantHistoryStore.instance.entries, isEmpty);
    expect(actions.lastJournalProject, '');
    await expectLater(
        Future.sync(() => actions.saveJournal(prepared,
            byVoice: false, lang: AppLanguage.pl)),
        throwsA(isA<AccountException>()));
    await expectLater(undo!(), throwsA(isA<AccountException>()));
    expect(await dao.listAll(), isEmpty);
    await login('A');
    expect((await dao.listAll()).single.isDeleted, false);
    expect(AssistantHistoryStore.instance.entries, hasLength(1));
  });
  test(
      'shared-coupon propagation cannot reveal or rewrite another account journal',
      () async {
    // schema33: log kuponów należy do właściciela (tu: gościa). Spoiny kont A
    // i B wskazują ten sam id kuponu (stare dane sprzed podziału) — zmiana
    // kuponu nigdy nie ujawnia ani nie przepisuje dziennika innego konta,
    // a konto nie może zmienić cudzego kuponu.
    const coupon = CouponEntry(
        id: 'shared-coupon',
        date: '2026-10-22',
        welder: 'SAME',
        machine: '',
        size: '',
        result: CouponResult.ok,
        notes: '');
    final coupons = CouponDao();
    await coupons.insert(coupon);
    await login('A');
    await dao.insert(
        weld('a').copyWith(couponId: coupon.id, couponRef: 'A original ref'));
    await login('B');
    await dao.insert(
        weld('b').copyWith(couponId: coupon.id, couponRef: 'B original ref'));
    expect((await coupons.linkedWelds(coupon.id)).map((e) => e.$1), ['b']);
    await expectLater(
        coupons.update(coupon.copyWith(result: CouponResult.nok)),
        throwsA(isA<AccountException>()),
        reason: 'konto B nie zmienia kuponu gościa');
    expect((await dao.getById('b'))!.couponRef, 'B original ref');
    await account.forgetSession();
    expect(await coupons.update(coupon.copyWith(result: CouponResult.nok)), 0,
        reason: 'gość nie ma spoin z tym kuponem — kont nie przepisuje');
    await login('A');
    expect((await dao.getById('a'))!.couponRef, 'A original ref');
    expect(await dao.history('a'), hasLength(1));
    await login('B');
    expect((await dao.getById('b'))!.couponRef, 'B original ref');
    expect(await dao.history('b'), hasLength(1));
  });
  test(
      'qualification continuity reads only the current account journal even for a repeated stamp',
      () async {
    await login('A');
    await dao.insert(weld('a', welder: 'SAME'));
    await login('B');
    await dao.insert(weld('b', welder: 'SAME'));
    final service = WelderQualificationService.instance;
    expect(await service.countJournalWeldsWithStamp('SAME'), 1);
    expect(
        await service.readJournalWelds(
            stamp: 'SAME', today: DateTime(2026, 10, 22)),
        hasLength(1));
    await account.forgetSession();
    expect(await service.countJournalWeldsWithStamp('SAME'), 0);
    expect(
        await service.readJournalWelds(
            stamp: 'SAME', today: DateTime(2026, 10, 22)),
        isEmpty);
  });
}
