// Log kuponów i biblioteka WPS należą do właściciela danych (schema33), tak
// jak rejestr uprawnień od schema32: dawne wiersze zostają gościowi, konto
// nie widzi ani nie nadpisuje cudzych wpisów, historia idzie za rodzicem.

import 'dart:convert';

import 'package:cut_list_app/database/coupon_dao.dart';
import 'package:cut_list_app/database/db.dart';
import 'package:cut_list_app/database/wps_dao.dart';
import 'package:cut_list_app/domain/weld_journal/coupon_entry.dart';
import 'package:cut_list_app/domain/wps/wps_record.dart';
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

CouponEntry coupon(String id, {String result = CouponResult.ok}) =>
    CouponEntry(
        id: id,
        date: '2026-10-22',
        welder: 'SAME',
        machine: 'M1',
        size: '60.3x2',
        result: result,
        notes: 'NOTE-$id');

WpsRecord wps(String id, {String notes = ''}) => WpsRecord(
    id: id, wpsNo: 'WPS-1', notes: notes, createdAt: 1, updatedAt: 1);

void main() {
  useTestDatabase();
  setUp(() async {
    await seedGuestAccount();
    final db = await AppDatabase.get();
    for (final t in [
      'weld_coupon_history',
      'weld_coupons',
      'wps_versions',
      'wps_library'
    ]) {
      await db.delete(t);
    }
  });

  test('kupony: gość i konta mają osobne logi, historia idzie za kuponem',
      () async {
    final dao = CouponDao();
    await dao.insert(coupon('guest'));
    await signIn('a');
    expect(await dao.listAll(), isEmpty, reason: 'konto nie widzi gościa');
    await dao.insert(coupon('a'), by: 'A');
    await signIn('b');
    expect(await dao.listAll(), isEmpty);
    expect(await dao.getById('a'), isNull);
    expect(await dao.history('a'), isEmpty, reason: 'cudza historia');
    await dao.insert(coupon('b'));
    expect((await dao.listAll()).map((c) => c.id), ['b']);
    await signIn('a');
    expect((await dao.listAll()).map((c) => c.id), ['a']);
    expect((await dao.history('a')).single.byStamp, 'A');
    await seedGuestAccount();
    expect((await dao.listAll()).map((c) => c.id), ['guest']);
  });

  test('kupony: cudze id nie pozwala nadpisać, usunąć ani przywrócić wpisu',
      () async {
    final dao = CouponDao();
    await signIn('a');
    await dao.insert(coupon('a'));
    await signIn('b');
    await expectLater(dao.insert(coupon('a', result: CouponResult.nok)),
        throwsA(isA<AccountException>()));
    await expectLater(dao.update(coupon('a', result: CouponResult.nok)),
        throwsA(isA<AccountException>()));
    expect(await dao.softDelete('a'), 0);
    expect(await dao.restore('a'), 0);
    await signIn('a');
    final own = (await dao.listAll()).single;
    expect(own.result, CouponResult.ok, reason: 'wpis A nietknięty');
    expect(own.isDeleted, isFalse);
  });

  test('WPS: osobne biblioteki, wersje idą za WPS, cudze id odrzucone',
      () async {
    final dao = WpsDao();
    await dao.upsert(wps('guest'));
    await signIn('a');
    expect(await dao.listAll(), isEmpty);
    expect(await dao.findByNumber('WPS-1'), isNull,
        reason: 'numer z biblioteki gościa nie pasuje do konta');
    await dao.upsert(wps('a'));
    await signIn('b');
    expect(await dao.getById('a'), isNull);
    expect(await dao.versionsOf('a'), isEmpty);
    expect(await dao.versionsByWps(), isEmpty);
    await expectLater(dao.upsert(wps('a', notes: 'przejęte')),
        throwsA(isA<AccountException>()));
    await dao.delete('a');
    await signIn('a');
    expect((await dao.listAll()).single.notes, '',
        reason: 'konto B nie nadpisało ani nie usunęło WPS konta A');
    expect((await dao.versionsOf('a')).single.versionNo, 1);
    await seedGuestAccount();
    expect((await dao.listAll()).map((w) => w.id), ['guest']);
  });

  test('migracja v32 → v33 zostawia dawne kupony i WPS gościowi', () async {
    final db = await AppDatabase.get();
    // Odtworzenie bazy v32: bez kolumny (i bez indeksów, które jej używają).
    await db.execute('DROP INDEX IF EXISTS idx_weld_coupons_owner');
    await db.execute('DROP INDEX IF EXISTS idx_wps_library_owner');
    await db.execute('ALTER TABLE weld_coupons DROP COLUMN owner_scope');
    await db.execute('ALTER TABLE wps_library DROP COLUMN owner_scope');
    await db.insert('weld_coupons', coupon('legacy').toRow());
    await db.insert('wps_library', wps('legacy-wps').toRow());
    await AppDatabase.migrate(db, 32, AppDatabase.schemaVersion);
    expect((await db.query('weld_coupons')).single['owner_scope'], 'guest');
    expect((await db.query('wps_library')).single['owner_scope'], 'guest');
    expect((await CouponDao().listAll()).single.id, 'legacy');
    expect((await WpsDao().listAll()).single.id, 'legacy-wps');
    await signIn('a');
    expect(await CouponDao().listAll(), isEmpty);
    expect(await WpsDao().listAll(), isEmpty);
  });
}
