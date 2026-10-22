// Kopia zapasowa a konta: eksport niesie tylko dane BIEŻĄCEGO właściciela
// (certyfikaty, historię ich potwierdzeń i ich skany), a przywrócenie na
// innym koncie nigdy nie kasuje ani nie nadpisuje rejestrów innych kont.
//
// RED przed poprawką: `_ownedLocalTables` nie obejmowało welder_certificates,
// więc ZIP konta A zawierał certyfikaty gościa i konta B, katalog heat_photos
// leciał w całości, a restore na koncie B robił `DELETE FROM
// welder_certificates` — kasując rejestr konta A.

import 'dart:convert';
import 'dart:io';

import 'package:cut_list_app/data/app_database.dart' as module_db;
import 'package:cut_list_app/database/db.dart';
import 'package:cut_list_app/database/coupon_dao.dart';
import 'package:cut_list_app/database/weld_journal_dao.dart';
import 'package:cut_list_app/database/welder_certificate_dao.dart';
import 'package:cut_list_app/database/wps_dao.dart';
import 'package:cut_list_app/domain/weld_journal/coupon_entry.dart';
import 'package:cut_list_app/domain/weld_journal/weld_entry.dart';
import 'package:cut_list_app/domain/wps/wps_record.dart';
import 'package:cut_list_app/domain/qualification/welder_certificate.dart';
import 'package:cut_list_app/services/account_service.dart';
import 'package:cut_list_app/services/data_backup.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../support/test_account.dart';
import '../support/weld_fixtures.dart';

const _pathProvider = MethodChannel('plugins.flutter.io/path_provider');

WelderCertificate _cert(String id, {String? photoPath}) => WelderCertificate(
    id: id,
    standard: QualificationStandard.iso9606_1,
    welderStamp: 'SAME',
    certNo: 'CERTNO-$id',
    photoPath: photoPath,
    createdAt: 1,
    updatedAt: 1);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory sandbox;
  late Directory documents;
  late Directory heatPhotos;
  late AccountService account;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    await seedGuestAccount();
    sandbox = await Directory.systemTemp.createTemp('fwp_backup_owner_');
    documents = Directory(p.join(sandbox.path, 'documents'));
    final temp = Directory(p.join(sandbox.path, 'tmp'));
    final databases = Directory(p.join(sandbox.path, 'databases'));
    heatPhotos = Directory(p.join(documents.path, 'heat_photos'));
    for (final d in [documents, temp, databases, heatPhotos]) {
      await d.create(recursive: true);
    }
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_pathProvider, (call) async {
      switch (call.method) {
        case 'getApplicationDocumentsDirectory':
        case 'getApplicationSupportDirectory':
          return documents.path;
        case 'getTemporaryDirectory':
          return temp.path;
      }
      return null;
    });
    await AppDatabase.clearTestingConfiguration();
    await (await module_db.AppDatabase.instance.db).close();
    await databaseFactory.setDatabasesPath(databases.path);
    account = AccountService.forTesting(MockClient((r) async {
      final id = jsonDecode(r.body)['email'];
      return http.Response(
          jsonEncode({
            'token': 'fixture-$id',
            'account': {'id': id}
          }),
          200);
    }));
  });

  tearDown(() async {
    await AppDatabase.clearTestingConfiguration();
    await (await module_db.AppDatabase.instance.db).close();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_pathProvider, null);
    try {
      await sandbox.delete(recursive: true);
    } catch (_) {
      // Windows potrafi zwolnić uchwyt pliku chwilę później.
    }
  });

  Future<String> photo(String name) async {
    final f = File(p.join(heatPhotos.path, name));
    await f.writeAsBytes(utf8.encode('PHOTO-$name'));
    return f.path;
  }

  test('eksport konta A niesie tylko jego certyfikaty, potwierdzenia i skany',
      () async {
    final dao = WelderCertificateDao();
    await dao.upsert(_cert('guest', photoPath: await photo('scan-guest.jpg')));
    AccountService.instance = account;
    await account.signIn('A', 'fixture-password');
    await dao.upsert(_cert('a', photoPath: await photo('scan-a.jpg')));
    await dao.addConfirmation(CertificateConfirmation(
        id: 'conf-a',
        certificateId: 'a',
        date: DateTime(2026, 10, 1),
        notes: 'CONFNOTE-a',
        createdAt: 1));
    await account.signIn('B', 'fixture-password');
    await dao.upsert(_cert('b', photoPath: await photo('scan-b.jpg')));
    await dao.addConfirmation(CertificateConfirmation(
        id: 'conf-b',
        certificateId: 'b',
        date: DateTime(2026, 10, 2),
        notes: 'CONFNOTE-b',
        createdAt: 1));
    await account.signIn('A', 'fixture-password');

    final archive =
        await DataBackup.createBackupFile(now: DateTime(2026, 10, 22, 10));
    final bytes = latin1.decode(await archive.readAsBytes());
    expect(bytes.contains('CERTNO-a'), isTrue);
    expect(bytes.contains('CONFNOTE-a'), isTrue);
    expect(bytes.contains('scan-a.jpg'), isTrue);
    expect(bytes.contains('CERTNO-b'), isFalse, reason: 'cudzy certyfikat');
    expect(bytes.contains('CERTNO-guest'), isFalse, reason: 'rejestr gościa');
    expect(bytes.contains('CONFNOTE-b'), isFalse, reason: 'cudza historia');
    expect(bytes.contains('PHOTO-scan-b.jpg'), isFalse, reason: 'cudzy skan');
    expect(bytes.contains('PHOTO-scan-guest.jpg'), isFalse,
        reason: 'skan gościa');
  });

  test('przywrócenie na koncie B nie kasuje ani nie nadpisuje rejestru A',
      () async {
    final dao = WelderCertificateDao();
    AccountService.instance = account;
    await account.signIn('A', 'fixture-password');
    await dao.upsert(_cert('a', photoPath: await photo('scan-a.jpg')));
    await dao.addConfirmation(CertificateConfirmation(
        id: 'conf-a',
        certificateId: 'a',
        date: DateTime(2026, 10, 1),
        notes: 'CONFNOTE-a',
        createdAt: 1));
    final archive = await (await DataBackup.createBackupFile(
            now: DateTime(2026, 10, 22, 10)))
        .copy(p.join(sandbox.path, 'carried.zip'));

    await account.signIn('B', 'fixture-password');
    await dao.upsert(_cert('b'));
    await DataBackup.restore(archive.path);

    // Przywrócenie ZASTĘPUJE rejestr bieżącego konta zawartością kopii (jak
    // parametry spawania) — ale tylko jego, nigdy rejestru innego konta.
    final imported = await dao.listAll();
    expect(imported.map((c) => c.certNo).toList(), ['CERTNO-a'],
        reason: 'B ma zawartość kopii');
    final copy = imported.single;
    expect(copy.id, isNot('a'),
        reason: 'identyfikator A nie może przejąć wiersza konta A');
    expect((await dao.confirmationsOf(copy.id)).single.notes, 'CONFNOTE-a',
        reason: 'historia potwierdzeń idzie za skopiowanym certyfikatem');

    await account.signIn('A', 'fixture-password');
    final own = await dao.listAll();
    expect(own.map((c) => c.id), ['a'], reason: 'rejestr A nietknięty');
    expect((await dao.confirmationsOf('a')).single.id, 'conf-a');
  });

  test('stara kopia z rejestrami wszystkich kont: konto B bierze tylko swoje',
      () async {
    final dao = WelderCertificateDao();
    AccountService.instance = account;
    await account.signIn('A', 'fixture-password');
    await dao.upsert(_cert('live-a'));
    await account.signIn('B', 'fixture-password');

    Map<String, Object?> certRow(String id, String owner) => {
          ..._cert(id).toRow(),
          'owner_scope': owner,
        };
    // Kopia sprzed przycinania eksportu: certyfikaty i historia A, B, gościa.
    final tables = <String, List<Map<String, Object?>>>{
      'welder_certificates': [
        certRow('old-a', 'account:A'),
        certRow('old-b', 'account:B'),
        certRow('old-guest', 'guest'),
      ],
      'welder_cert_confirmations': [
        for (final c in ['old-a', 'old-b', 'old-guest'])
          {
            'id': 'conf-$c',
            'certificate_id': c,
            'date': '2026-10-01',
            'confirmed_by': '',
            'notes': 'NOTE-$c',
            'created_at': 1,
          },
      ],
    };
    final db = await AppDatabase.get();
    await restoreTablesInto(db, tables,
        heatPhotosDir: heatPhotos.path,
        restoredPhotoNames: <String>{},
        wipeTablesNotInBackup: false,
        weldParamsOwner: 'account:B',
        preserveWeldParamOwner: true);

    final own = await dao.listAll();
    expect(own.map((c) => c.id), ['old-b']);
    expect((await dao.confirmationsOf('old-b')).single.notes, 'NOTE-old-b');
    await account.signIn('A', 'fixture-password');
    expect((await dao.listAll()).map((c) => c.id), ['live-a'],
        reason: 'rejestr A nietknięty, cudze wiersze kopii pominięte');
    final all = await db.query('welder_cert_confirmations');
    expect(all.map((r) => r['id']), ['conf-old-b'],
        reason: 'historia certyfikatów innych kont nie wpada do bazy');
  });

  test('kupony i WPS: eksport tylko właściciela, restore przemapowuje id '
      'i odwołania spoiny', () async {
    final coupons = CouponDao();
    final wpsDao = WpsDao();
    AccountService.instance = account;
    await account.signIn('A', 'fixture-password');
    await coupons.insert(const CouponEntry(
        id: 'c-a',
        date: '2026-10-22',
        welder: 'SAME',
        machine: 'M1',
        size: '60.3x2',
        result: CouponResult.ok,
        notes: 'COUPON-a'));
    await wpsDao.upsert(const WpsRecord(
        id: 'w-a', wpsNo: 'WPS-A', notes: 'WPSNOTE-a', createdAt: 1, updatedAt: 1));
    final welded = weld('s-a');
    await WeldJournalDao().insert(WeldEntry.fromRow({
      ...welded.toRow(),
      'coupon_id': 'c-a',
      'wps_id': 'w-a',
    }));
    await account.signIn('B', 'fixture-password');
    await coupons.insert(const CouponEntry(
        id: 'c-b',
        date: '2026-10-22',
        welder: 'SAME',
        machine: 'M1',
        size: '60.3x2',
        result: CouponResult.ok,
        notes: 'COUPON-b'));
    await wpsDao.upsert(const WpsRecord(
        id: 'w-b', wpsNo: 'WPS-B', notes: 'WPSNOTE-b', createdAt: 1, updatedAt: 1));
    await account.signIn('A', 'fixture-password');

    final archive = await (await DataBackup.createBackupFile(
            now: DateTime(2026, 10, 22, 11)))
        .copy(p.join(sandbox.path, 'carried-coupons.zip'));
    final bytes = latin1.decode(await archive.readAsBytes());
    expect(bytes.contains('COUPON-a'), isTrue);
    expect(bytes.contains('WPSNOTE-a'), isTrue);
    expect(bytes.contains('COUPON-b'), isFalse, reason: 'cudzy kupon');
    expect(bytes.contains('WPSNOTE-b'), isFalse, reason: 'cudza WPS');

    await account.signIn('B', 'fixture-password');
    await DataBackup.restore(archive.path);
    final copy = (await coupons.listAll()).single;
    expect(copy.notes, 'COUPON-a');
    expect(copy.id, isNot('c-a'), reason: 'id zajęte przez konto A');
    expect((await coupons.history(copy.id)), isNotEmpty,
        reason: 'historia kuponu idzie za nowym id');
    final wpsCopy = (await wpsDao.listAll()).single;
    expect(wpsCopy.id, isNot('w-a'));
    expect((await wpsDao.versionsOf(wpsCopy.id)), isNotEmpty);
    final restoredWeld = (await WeldJournalDao().listAll()).single;
    expect(restoredWeld.couponId, copy.id,
        reason: 'spoina wskazuje kopię kuponu, nie kupon konta A');
    expect(restoredWeld.wpsId, wpsCopy.id);

    await account.signIn('A', 'fixture-password');
    expect((await coupons.listAll()).single.id, 'c-a');
    expect((await wpsDao.listAll()).single.id, 'w-a');
    expect((await WeldJournalDao().listAll()).single.couponId, 'c-a');
  });
}
