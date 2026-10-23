// Rejestry prób ciśnieniowych, pasywacji i przyrządów należą do właściciela
// danych (schema34): dawne wiersze zostają gościowi, konto nie widzi, nie
// nadpisuje i nie usuwa cudzych wpisów.

import 'dart:convert';

import 'package:cut_list_app/database/db.dart';
import 'package:cut_list_app/database/hydrotest_dao.dart';
import 'package:cut_list_app/database/instrument_dao.dart';
import 'package:cut_list_app/database/passivation_dao.dart';
import 'package:cut_list_app/domain/instruments/instrument.dart';
import 'package:cut_list_app/domain/passivation/passivation_record.dart';
import 'package:cut_list_app/services/account_service.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

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

void main() {
  useTestDatabase();
  setUp(() async {
    await seedGuestAccount();
    final db = await AppDatabase.get();
    for (final t in ['hydrotest_records', 'passivation_records', 'instruments']) {
      await db.delete(t);
    }
  });

  test('pressure tests: own register, count and delete', () async {
    HydrotestRecord r(String id) => HydrotestRecord(
        id: id, systemName: 'L-$id', date: '2026-10-23', result: 'OK', createdAt: 1);
    await HydrotestDao().insert(r('guest'));
    await signIn('a');
    expect(await HydrotestDao().listAll(), isEmpty);
    expect(await HydrotestDao().count(), 0);
    await HydrotestDao().insert(r('a1'));
    await expectLater(
        HydrotestDao().insert(r('guest')), throwsA(isA<AccountException>()));
    await HydrotestDao().deleteById('guest');
    await seedGuestAccount();
    expect((await HydrotestDao().listAll()).map((x) => x.id), ['guest'],
        reason: 'konto A nie usunęło próby gościa');
  });

  test('passivation: own entries, foreign id is taken', () async {
    PassivationRecord p(String id, String line) => PassivationRecord(
        id: id, date: '2026-10-23', line: line, createdAt: 1, updatedAt: 1);
    await signIn('a');
    await PassivationDao().save(p('x', 'A-line'));
    await signIn('b');
    expect(await PassivationDao().listAll(), isEmpty);
    await expectLater(PassivationDao().save(p('x', 'B-steal')),
        throwsA(isA<AccountException>()));
    await PassivationDao().softDelete('x');
    await signIn('a');
    expect((await PassivationDao().listAll()).single.line, 'A-line');
  });

  test('instruments: own register only', () async {
    Instrument i(String id) =>
        Instrument(id: id, name: 'Manometr $id', createdAt: 1, updatedAt: 1);
    await signIn('a');
    await InstrumentDao().save(i('m1'));
    await signIn('b');
    expect(await InstrumentDao().listAll(), isEmpty);
    await expectLater(
        InstrumentDao().save(i('m1')), throwsA(isA<AccountException>()));
    await InstrumentDao().softDelete('m1');
    await signIn('a');
    expect((await InstrumentDao().listAll()).single.id, 'm1');
  });
}
