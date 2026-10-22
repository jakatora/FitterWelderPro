import 'package:shared_preferences/shared_preferences.dart';
import 'package:cut_list_app/assistant/skills/own_data/certificates_expiry_skill.dart';
import 'package:cut_list_app/services/welder_qualification_service.dart';
import 'dart:async';
import 'package:cut_list_app/database/local_record_owner.dart';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:cut_list_app/database/db.dart';
import 'package:cut_list_app/database/welder_certificate_dao.dart';
import 'package:cut_list_app/domain/qualification/welder_certificate.dart';
import 'package:cut_list_app/services/account_service.dart';
import '../support/test_account.dart';
import '../support/test_database.dart';

Future<void> signIn(String id) async {
  FlutterSecureStorage.setMockInitialValues({});
  AccountService.instance =
      AccountService.forTesting(MockClient((_) async => http.Response(
          jsonEncode({
            'token': 'test-$id',
            'account': {'id': id, 'role': 'user'}
          }),
          200)));
  await AccountService.instance.signIn('$id@example.test', 'test-password');
}

WelderCertificate cert(String id) => WelderCertificate(
    id: id,
    standard: QualificationStandard.iso9606_1,
    welderStamp: 'SAME',
    certNo: id,
    createdAt: 1,
    updatedAt: 1);
void main() {
  useTestDatabase();
  setUp(() async {
    await seedGuestAccount();
    final db = await AppDatabase.get();
    await db.delete('welder_cert_confirmations');
    await db.delete('welder_certificates');
  });
  test('same stamp is not account ownership; legacy rows stay with guest',
      () async {
    final dao = WelderCertificateDao();
    await dao.upsert(cert('guest'));
    await signIn('a');
    expect(await dao.listAll(), isEmpty);
    await dao.upsert(cert('a'));
    await signIn('b');
    expect(await dao.count(), 0);
    expect(await dao.getById('a'), isNull);
    await dao.upsert(cert('b'));
    expect((await dao.listAll()).map((c) => c.id), ['b']);
    await seedGuestAccount();
    expect((await dao.listAll()).map((c) => c.id), ['guest']);
  });
  test('account cannot replace foreign ID or erase another register', () async {
    final dao = WelderCertificateDao();
    await dao.upsert(cert('guest'));
    await signIn('a');
    await dao.upsert(cert('a'));
    await signIn('b');
    await expectLater(dao.upsert(cert('a')), throwsA(isA<AccountException>()));
    await dao.upsert(cert('b'));
    expect((await dao.deleteAll()).map((c) => c.id), ['b']);
    await signIn('a');
    expect((await dao.listAll()).map((c) => c.id), ['a']);
    await seedGuestAccount();
    expect((await dao.listAll()).map((c) => c.id), ['guest']);
  });
  test('confirmation history and stamp reassignment follow the parent account',
      () async {
    final dao = WelderCertificateDao();
    await signIn('a');
    await dao.upsert(cert('a'));
    final history = CertificateConfirmation(
        id: 'history-a',
        certificateId: 'a',
        date: DateTime(2026, 10, 1),
        createdAt: 1);
    await dao.addConfirmation(history);
    await signIn('b');
    expect(await dao.confirmationsOf('a'), isEmpty);
    await expectLater(
        dao.addConfirmation(history), throwsA(isA<AccountException>()));
    await expectLater(
        dao.deleteConfirmation(history), throwsA(isA<AccountException>()));
    await expectLater(dao.delete('a'), throwsA(isA<AccountException>()));
    await dao.upsert(cert('b'));
    expect(await dao.reassignStamp('SAME', 'NEW'), 1);
    await dao.deleteAll();
    await signIn('a');
    final own = await dao.getById('a');
    expect(own!.welderStamp, 'SAME');
    expect(own.confirmations.single.id, 'history-a');
    expect(own.lastConfirmedDate, DateTime(2026, 10, 1));
  });
  test('late owner capture cannot write under another account', () async {
    await signIn('a');
    final owner = await LocalRecordOwner.capture();
    final entered = Completer<void>();
    final release = Completer<void>();
    final dao = WelderCertificateDao(captureOwner: () async {
      entered.complete();
      await release.future;
      return owner;
    });
    final pending = dao.upsert(cert('late'));
    final assertion = expectLater(pending, throwsA(isA<AccountException>()));
    await entered.future;
    await signIn('b');
    release.complete();
    await assertion;
    expect(await WelderCertificateDao().count(), 0);
    await signIn('a');
    expect(await WelderCertificateDao().count(), 0);
  });
  test('v31 migration preserves legacy rows and confirmation history as guest',
      () async {
    final db = await AppDatabase.get();
    await db.execute('ALTER TABLE welder_certificates DROP COLUMN owner_scope');
    await db.insert('welder_certificates', cert('legacy').toRow());
    final history = CertificateConfirmation(
        id: 'legacy-h',
        certificateId: 'legacy',
        date: DateTime(2026, 10, 1),
        createdAt: 1);
    await db.insert('welder_cert_confirmations', history.toRow());
    await AppDatabase.migrate(db, 31, AppDatabase.schemaVersion);
    final dao = WelderCertificateDao();
    expect((await dao.getById('legacy'))!.confirmations.single.id, 'legacy-h');
    expect(
        (await db.query('welder_certificates')).single['owner_scope'], 'guest');
    await signIn('a');
    expect(await dao.listAll(), isEmpty);
  });
  test(
      'assistant reads only current account certificates even with identical stamps',
      () async {
    await signIn('a');
    await WelderCertificateDao().upsert(cert('a'));
    expect(
        (await readLocalCertificateEvaluations(DateTime(2026, 10, 22),
                ownerStamp: 'SAME'))
            .map((e) => e.certificate.id),
        ['a']);
    await signIn('b');
    expect(
        await readLocalCertificateEvaluations(DateTime(2026, 10, 22),
            ownerStamp: 'SAME'),
        isEmpty);
  });
  test(
      'legacy identity migration never assigns guest data to a signed-in account',
      () async {
    SharedPreferences.setMockInitialValues({
      'welder_identity_v1': jsonEncode(
          {'stamp': 'SAME', 'wpqrNo': 'OLD-GUEST', 'wpqrExpiry': '2028-01-01'})
    });
    await signIn('a');
    final db = await AppDatabase.get();
    final prefs = await SharedPreferences.getInstance();
    expect(await migrateLegacyQualification(db, prefs), isNull);
    expect(await WelderCertificateDao().listAll(), isEmpty);
    expect(prefs.getBool(kLegacyCertMigratedPrefsKey), isNot(true));
    await seedGuestAccount();
    expect((await migrateLegacyQualification(db, prefs))!.certNo, 'OLD-GUEST');
  });
}
