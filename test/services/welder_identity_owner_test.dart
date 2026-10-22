// Tożsamość spawacza należy do właściciela danych (gość albo konto), tak jak
// rejestr uprawnień od schema32. Gość zostaje na dawnym kluczu
// `welder_identity_v1`, więc jego dane po aktualizacji są nietknięte.

import 'dart:convert';

import 'package:cut_list_app/database/db.dart';
import 'package:cut_list_app/database/local_record_owner.dart';
import 'package:cut_list_app/database/welder_certificate_dao.dart';
import 'package:cut_list_app/domain/qualification/welder_certificate.dart';
import 'package:cut_list_app/services/account_service.dart';
import 'package:cut_list_app/services/welder_identity.dart';
import 'package:cut_list_app/services/welder_qualification_service.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

WelderIdentity identity(String stamp) => WelderIdentity(
    stamp: stamp,
    gdprConsentAt: DateTime.utc(2026, 10, 22),
    qualificationDeclaredAt: DateTime.utc(2026, 10, 22));

WelderCertificate cert(String id, {String stamp = 'SAME'}) =>
    WelderCertificate(
        id: id,
        standard: QualificationStandard.iso9606_1,
        welderStamp: stamp,
        certNo: id,
        createdAt: 1,
        updatedAt: 1);

void main() {
  useTestDatabase();
  late WelderIdentityService service;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await seedGuestAccount();
    final db = await AppDatabase.get();
    await db.delete('welder_cert_confirmations');
    await db.delete('welder_certificates');
    service = WelderIdentityService.forTesting();
  });

  test('gość zostaje na dawnym kluczu; każde konto ma własną tożsamość',
      () async {
    SharedPreferences.setMockInitialValues({
      'welder_identity_v1': jsonEncode(identity('GUEST').toJson()),
    });
    expect((await service.get())?.stamp, 'GUEST');

    await signIn('a');
    expect(await service.get(), isNull,
        reason: 'konto nie dziedziczy tożsamości gościa');
    expect(await service.save(identity('AAA')), isTrue);

    await signIn('b');
    expect(await service.get(), isNull);
    expect(await service.save(identity('BBB')), isTrue);

    await signIn('a');
    expect((await service.get())?.stamp, 'AAA');

    await seedGuestAccount();
    expect((await service.get())?.stamp, 'GUEST');
    final prefs = await SharedPreferences.getInstance();
    expect(
        WelderIdentity.fromJson(Map<String, Object?>.from(
                jsonDecode(prefs.getString('welder_identity_v1')!) as Map))
            ?.stamp,
        'GUEST',
        reason: 'zapis kont nie nadpisuje dawnego klucza gościa');
  });

  test('current nie pokazuje tożsamości poprzedniego konta po przełączeniu',
      () async {
    await signIn('a');
    await service.save(identity('AAA'));
    expect(service.current?.stamp, 'AAA');

    await signIn('b');
    expect(service.current, isNull,
        reason: 'stempel konta A nie może podpisać spoin konta B');
  });

  test('changes emituje tożsamość nowego konta po zmianie sesji', () async {
    await signIn('a');
    await service.save(identity('AAA'));
    await signIn('b');
    await service.save(identity('BBB'));

    final next = service.changes.first;
    await signIn('a');
    service.current; // pierwszy odczyt po zmianie konta uruchamia odświeżenie
    expect((await next.timeout(const Duration(seconds: 5)))?.stamp, 'AAA');
    expect(service.current?.stamp, 'AAA');
  });

  test('zapis z edytora otwartego na innym koncie jest odrzucony', () async {
    await signIn('a');
    final owner = await LocalRecordOwner.capture();
    await signIn('b');
    expect(await service.save(identity('AAA'), expectedOwner: owner), isFalse);
    expect(await service.get(), isNull, reason: 'konto B nic nie dostało');
    await signIn('a');
    expect(await service.get(), isNull,
        reason: 'nieaktualna sesja niczego nie zapisała');
  });

  test('clear kasuje tożsamość i certyfikaty tylko tego samego właściciela',
      () async {
    final dao = WelderCertificateDao();
    await signIn('a');
    await service.save(identity('AAA'));
    await dao.upsert(cert('a'));
    await signIn('b');
    await service.save(identity('BBB'));
    await dao.upsert(cert('b'));

    expect(await service.clear(), isTrue);
    expect(await service.get(), isNull);
    expect(await dao.listAll(), isEmpty);

    await signIn('a');
    expect((await service.get())?.stamp, 'AAA');
    expect((await dao.listAll()).map((c) => c.id), ['a']);
  });

  test('clear z nieaktualnym właścicielem nie rusza bieżącego konta', () async {
    final dao = WelderCertificateDao();
    await signIn('a');
    await service.save(identity('AAA'));
    await dao.upsert(cert('a'));
    final ownerA = await LocalRecordOwner.capture();

    await signIn('b');
    await service.save(identity('BBB'));
    await dao.upsert(cert('b'));

    expect(await service.clear(expectedOwner: ownerA), isFalse);
    expect((await service.get())?.stamp, 'BBB');
    expect((await dao.listAll()).map((c) => c.id), ['b']);
    await signIn('a');
    expect((await service.get())?.stamp, 'AAA',
        reason: 'przerwane kasowanie nie zostawia połowicznego stanu');
    expect((await dao.listAll()).map((c) => c.id), ['a']);
  });

  test('przepisanie stempla certyfikatów jest związane z właścicielem',
      () async {
    final dao = WelderCertificateDao();
    await signIn('a');
    await dao.upsert(cert('a', stamp: 'OLD'));
    final ownerA = await LocalRecordOwner.capture();
    await signIn('b');
    await dao.upsert(cert('b', stamp: 'OLD'));

    await expectLater(
        WelderQualificationService.instance
            .reassignStamp('OLD', 'NEW', owner: ownerA),
        throwsA(isA<AccountException>()));
    expect((await dao.listAll()).single.welderStamp, 'OLD',
        reason: 'certyfikat konta B nie zmienił stempla');
  });
}
