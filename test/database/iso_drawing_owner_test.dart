import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:cut_list_app/database/db.dart';
import 'package:cut_list_app/database/iso_drawing_dao.dart';
import 'package:cut_list_app/database/local_record_owner.dart';
import 'package:cut_list_app/services/account_service.dart';
import 'package:cut_list_app/services/data_backup.dart';
import '../support/test_database.dart';

IsoDrawingRecord record(String id) => IsoDrawingRecord(
    id: id,
    name: id,
    json: '{"format":1,"name":"$id","items":[]}',
    createdAt: 1,
    updatedAt: 2);
void main() {
  useTestDatabase();
  late AccountService account;
  final dao = IsoDrawingDao();
  setUp(() async {
    FlutterSecureStorage.setMockInitialValues({});
    account = AccountService.forTesting(MockClient((r) async {
      final id = jsonDecode(r.body)['email'];
      return http.Response(
          jsonEncode({
            'token': 'fixture-$id',
            'account': {'id': id}
          }),
          200);
    }));
    AccountService.instance = account;
    await account.load();
    await (await AppDatabase.get()).delete('iso_drawings');
  });
  Future<void> login(String id) => account.signIn(id, 'fixture-password');
  test('guest/A/B cannot read overwrite or delete another sketch', () async {
    await dao.upsert(record('guest'));
    await login('A');
    expect(await dao.latest(), isNull);
    await dao.upsert(record('a'));
    await login('B');
    expect(await dao.listAll(), isEmpty);
    expect(await dao.getById('a'), isNull);
    await expectLater(dao.upsert(record('a')), throwsA(anything));
    await dao.deleteById('a');
    await dao.upsert(record('b'));
    expect((await dao.latest())!.id, 'b');
    await login('A');
    expect((await dao.listAll()).map((r) => r.id), ['a']);
    await account.forgetSession();
    expect((await dao.latest())!.id, 'guest');
  });
  for (final write in [true, false]) {
    test('delayed ${write ? 'autosave' : 'read'} is bound to captured session',
        () async {
      await login('A');
      await dao.upsert(record('a'));
      final entered = Completer<void>(), release = Completer<void>();
      final delayed = IsoDrawingDao(owner: () async {
        final owner = await LocalRecordOwner.capture();
        entered.complete();
        await release.future;
        return owner;
      });
      final operation =
          write ? delayed.upsert(record('late')) : delayed.latest();
      final rejected = expectLater(operation, throwsA(isA<AccountException>()));
      await entered.future;
      await login('B');
      release.complete();
      await rejected;
      expect(await dao.listAll(), isEmpty);
      await login('A');
      expect((await dao.listAll()).map((r) => r.id), ['a']);
    });
  }
  test('restore rebinds ISO copies and never replaces foreign UUID', () async {
    await dao.upsert(record('guest'));
    await login('A');
    await dao.upsert(record('a'));
    final db = await AppDatabase.get();
    final source =
        (await db.query('iso_drawings')).firstWhere((r) => r['id'] == 'a');
    await login('B');
    await dao.upsert(record('b'));
    await restoreTablesInto(
        db,
        {
          'iso_drawings': [source]
        },
        heatPhotosDir: '/fixture',
        restoredPhotoNames: {},
        weldParamsOwner: 'account:B');
    final restored = (await dao.listAll()).single;
    expect(restored.id, isNot('a'));
    expect(restored.name, 'a');
    await login('A');
    expect((await dao.latest())!.id, 'a');
    await account.forgetSession();
    expect((await dao.latest())!.id, 'guest');
  });
  test('v29 ISO migration leaves legacy data with guest', () async {
    final db = await databaseFactory.openDatabase(inMemoryDatabasePath,
        options: OpenDatabaseOptions(singleInstance: false));
    try {
      await db.execute(
          'CREATE TABLE iso_drawings(id TEXT PRIMARY KEY,name TEXT NOT NULL,json TEXT NOT NULL,created_at INTEGER NOT NULL,updated_at INTEGER NOT NULL)');
      await db.insert('iso_drawings', record('legacy').toRow());
      await AppDatabase.migrate(db, 29, 30);
      final row = (await db.query('iso_drawings')).single;
      expect(row['owner_scope'], 'guest');
      expect(row['json'], record('legacy').json);
      await AppDatabase.migrate(db, 29, 30);
      expect((await db.query('iso_drawings')).length, 1);
    } finally {
      await db.close();
    }
  });
  test('pruned snapshot contains neither foreign rows nor their old bytes',
      () async {
    final dir = await Directory.systemTemp.createTemp('fwp_iso_owner_');
    final file = File('${dir.path}/snapshot.db');
    final db = await databaseFactory.openDatabase(file.path);
    try {
      await db.execute(
          'CREATE TABLE iso_drawings(id TEXT PRIMARY KEY,owner_scope TEXT,json TEXT)');
      await db.insert('iso_drawings',
          {'id': 'a', 'owner_scope': 'account:A', 'json': 'A_ONLY'});
      await db.insert('iso_drawings', {
        'id': 'b',
        'owner_scope': 'account:B',
        'json': 'B_ISO_PRIVATE_71d9e'
      });
      await pruneWeldParamsSnapshot(db, 'account:A');
      expect((await db.query('iso_drawings')).map((r) => r['id']), ['a']);
    } finally {
      await db.close();
    }
    expect(latin1.decode(await file.readAsBytes()),
        isNot(contains('B_ISO_PRIVATE_71d9e')));
    await file.delete();
    await dir.delete();
  });
}
