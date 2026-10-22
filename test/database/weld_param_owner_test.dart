import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cut_list_app/database/db.dart';
import 'package:cut_list_app/assistant/assistant_actions.dart';
import 'package:cut_list_app/assistant/assistant_history.dart';
import 'package:cut_list_app/assistant/assistant_validator.dart';
import 'package:cut_list_app/i18n/app_language.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cut_list_app/database/local_record_owner.dart';
import 'package:cut_list_app/database/weld_param_dao.dart';
import 'package:cut_list_app/models/weld_param.dart';
import 'package:cut_list_app/services/account_service.dart';
import 'package:cut_list_app/services/data_backup.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../support/test_database.dart';

WeldParam param(String id, {double amps = 60}) => WeldParam(
    id: id,
    method: 'TIG_AUTOGEN',
    baseMaterial: 'SS',
    welderModel: null,
    diameterMm: 60.3,
    wallThicknessMm: 2,
    electrodeMm: 1.6,
    torchGasLpm: 8,
    nozzleType: null,
    nozzleSize: null,
    purgeLpm: 4,
    amps: amps,
    outletHoles: 0,
    tempo: null,
    note: 'private-$id',
    createdAt: 1,
    updatedAt: 2);

void main() {
  useTestDatabase();
  late AccountService account;
  final dao = WeldParamDao();
  setUp(() async {
    FlutterSecureStorage.setMockInitialValues({});
    account = AccountService.forTesting(MockClient((r) async {
      final email = jsonDecode(r.body)['email'];
      return http.Response(
          jsonEncode({
            'token': 'fixture-$email',
            'account': {'id': email, 'displayName': email}
          }),
          200);
    }));
    AccountService.instance = account;
    await account.load();
    await (await AppDatabase.get()).delete('weld_params');
  });
  Future<void> signIn(String id) => account.signIn(id, 'fixture-password');

  test('assistant parameter history follows its persisted owner after reload',
      () async {
    SharedPreferences.setMockInitialValues({});
    final history = AssistantHistoryStore.instance;
    history.resetForTest();
    await signIn('A');
    final undo = await AssistantActions().saveWeldParam(
        const WeldParamDraft(
            material: 'SS',
            process: 'TIG',
            filler: false,
            wallMm: 2,
            currentA: 60),
        byVoice: false,
        lang: AppLanguage.pl);
    expect(history.entries.single.ownerScope, 'account:A');
    await signIn('B');
    history.resetForTest();
    await history.load();
    expect(history.entries, isEmpty);
    await account.forgetSession();
    expect(history.entries, isEmpty);
    await signIn('A');
    expect(history.entries.single.ownerScope, 'account:A');
    await undo!();
    expect(history.entries.single.undone, isTrue);
    expect(history.entries.single.ownerScope, 'account:A');
    await history.clear();
  });

  test(
      'guest and two accounts have separate records and cannot mutate other UUIDs',
      () async {
    await dao.insert(param('guest'));
    await signIn('A');
    final a = param('a');
    expect(await dao.listAll(), isEmpty);
    expect(await dao.insertAssistantIdempotent(a), isTrue);
    expect(await dao.insertAssistantIdempotent(a), isTrue);
    await signIn('B');
    expect(await dao.listAll(), isEmpty);
    expect(await dao.insertAssistantIdempotent(a), isFalse);
    expect(await dao.deleteIfUnchanged(a), isFalse);
    await dao.deleteById(a.id);
    await expectLater(dao.update(param('a', amps: 200)), throwsStateError);
    await dao.insert(param('b'));
    expect((await dao.listAll()).map((r) => r.id), ['b']);
    await signIn('A');
    expect((await dao.listAll()).single.amps, 60);
    await dao.update(param('a', amps: 200));
    expect(await dao.deleteIfUnchanged(a), isFalse);
    expect(await dao.deleteIfUnchanged(param('a', amps: 200)), isTrue);
    await account.forgetSession();
    expect((await dao.listAll()).map((r) => r.id), ['guest']);
  });

  for (final write in [false, true]) {
    test(
        'session switch after owner capture rejects delayed ${write ? 'write' : 'read'}',
        () async {
      await signIn('A');
      await dao.insert(param('a'));
      final captured = Completer<void>(), release = Completer<void>();
      final delayed = WeldParamDao(owner: () async {
        final owner = await LocalRecordOwner.capture();
        captured.complete();
        await release.future;
        return owner;
      });
      final operation =
          write ? delayed.insert(param('late')) : delayed.listAll();
      final rejected = expectLater(operation, throwsA(isA<AccountException>()));
      await captured.future;
      await signIn('B');
      release.complete();
      await rejected;
      expect(await dao.listAll(), isEmpty);
      await signIn('A');
      expect((await dao.listAll()).map((r) => r.id), ['a']);
    });
  }

  test('offline retained token never falls back to guest data', () async {
    await dao.insert(param('guest'));
    FlutterSecureStorage.setMockInitialValues(
        {'railway_account_session_v1': 'fixture-offline'});
    AccountService.instance = AccountService.forTesting(MockClient(
        (_) async => http.Response('{"error":{"message":"Offline"}}', 503)));
    await AccountService.instance.load();
    await expectLater(dao.listAll(), throwsA(isA<AccountException>()));
  });

  test(
      'same session cached owner permits offline data after restart; another token does not',
      () async {
    await signIn('A');
    await dao.insert(param('a'));
    final offline = AccountService.forTesting(MockClient(
        (_) async => http.Response('{"error":{"message":"Offline"}}', 503)));
    AccountService.instance = offline;
    await offline.load();
    expect(offline.account, isNull);
    expect(offline.isAdmin, isFalse);
    expect((await dao.listAll()).map((r) => r.id), ['a']);
    await const FlutterSecureStorage()
        .write(key: 'railway_account_session_v1', value: 'different-token');
    final other = AccountService.forTesting(MockClient(
        (_) async => http.Response('{"error":{"message":"Offline"}}', 503)));
    AccountService.instance = other;
    await other.load();
    expect(other.localOwnerId, isNull);
    await expectLater(dao.listAll(), throwsA(isA<AccountException>()));
  });

  test('snapshot pruning removes another owner from SQL and raw SQLite pages',
      () async {
    final dir = await Directory.systemTemp.createTemp('fwp_owner_snapshot_');
    final live = await databaseFactory.openDatabase('${dir.path}/live.db');
    final snapshotPath = '${dir.path}/snapshot.db';
    try {
      await live.execute(
          'CREATE TABLE weld_params(id TEXT PRIMARY KEY, owner_scope TEXT, note TEXT)');
      await live.insert('weld_params',
          {'id': 'a', 'owner_scope': 'account:A', 'note': 'A_OWNED'});
      await live.insert('weld_params', {
        'id': 'b',
        'owner_scope': 'account:B',
        'note': 'B_PRIVATE_MARKER_8fbe21'
      });
      await live.execute('VACUUM INTO ?', [snapshotPath]);
      final snapshot = await databaseFactory.openDatabase(snapshotPath);
      try {
        await pruneWeldParamsSnapshot(snapshot, 'account:A');
        expect(
            (await snapshot.query('weld_params')).map((r) => r['id']), ['a']);
      } finally {
        await snapshot.close();
      }
      expect(
          latin1
              .decode(await File(snapshotPath).readAsBytes())
              .contains('B_PRIVATE_MARKER_8fbe21'),
          isFalse);
      expect((await live.query('weld_params')).length, 2);
    } finally {
      await live.close();
      // Exact files created by this test, no recursive or computed-root delete.
      for (final name in ['live.db', 'snapshot.db']) {
        final file = File('${dir.path}/$name');
        if (await file.exists()) await file.delete();
      }
    }
  });

  test(
      'restore replaces only current owner and copies colliding foreign UUID safely',
      () async {
    await dao.insert(param('guest'));
    await signIn('A');
    await dao.insert(param('a'));
    final db = await AppDatabase.get();
    final source = Map<String, Object?>.of(
        (await db.query('weld_params', where: 'id=?', whereArgs: ['a']))
            .single);
    await signIn('B');
    await dao.insert(param('b'));
    await restoreTablesInto(
        db,
        {
          'weld_params': [source]
        },
        heatPhotosDir: '/fixture',
        restoredPhotoNames: {},
        weldParamsOwner: 'account:B');
    final b = (await dao.listAll()).single;
    expect(b.id, isNot('a'));
    expect(b.amps, 60);
    await signIn('A');
    expect((await dao.listAll()).map((r) => r.id), ['a']);
    await account.forgetSession();
    expect((await dao.listAll()).map((r) => r.id), ['guest']);
  });
}
