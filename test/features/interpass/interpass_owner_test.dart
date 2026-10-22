import 'dart:async';
import 'package:cut_list_app/database/local_record_owner.dart';
import 'package:cut_list_app/services/account_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cut_list_app/domain/welding/interpass_log.dart';
import 'package:cut_list_app/features/interpass/interpass_store.dart';
import '../../support/test_account.dart';

void main() {
  useGuestAccount();
  const store = InterpassStore();
  final now = DateTime(2026, 10, 22);
  setUp(() => SharedPreferences.setMockInitialValues({}));
  test('legacy guest log is not assigned to a signed-in account', () async {
    await store.upsert(InterpassWeld.blank(id: 'same', now: now)
        .copyWith(weldNo: 'GUEST-PRIVATE'));
    await seedSignedInAccount();
    expect((await store.load()).welds, isEmpty);
    await store.upsert(InterpassWeld.blank(id: 'same', now: now)
        .copyWith(weldNo: 'ACCOUNT-PRIVATE'));
    expect((await store.load()).welds.single.weldNo, 'ACCOUNT-PRIVATE');
    await seedGuestAccount();
    expect((await store.load()).welds.single.weldNo, 'GUEST-PRIVATE');
  });
  test('account delete and settings cannot change guest data', () async {
    await store.upsert(InterpassWeld.blank(id: 'same', now: now)
        .copyWith(weldNo: 'GUEST-PRIVATE'));
    await store.saveUnit(InterpassUnit.f);
    await seedSignedInAccount();
    expect(await store.loadUnit(), InterpassUnit.c);
    await store.delete('same');
    await store.saveUnit(InterpassUnit.c);
    await seedGuestAccount();
    expect((await store.load()).welds.single.weldNo, 'GUEST-PRIVATE');
    expect(await store.loadUnit(), InterpassUnit.f);
  });
  test('corrupt backups are kept only with their owner', () async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(InterpassStore.key, 'guest corrupted');
    await store.load();
    await seedSignedInAccount();
    final owner = await LocalRecordOwner.capture();
    expect((await store.load()).corrupt, false);
    await prefs.setString(InterpassStore.ownerKey(InterpassStore.key, owner),
        'account corrupted');
    expect((await store.load()).corrupt, true);
    expect(prefs.getString(InterpassStore.corruptBackupKey), 'guest corrupted');
    expect(
        prefs.getString(
            InterpassStore.ownerKey(InterpassStore.corruptBackupKey, owner)),
        'account corrupted');
  });
  test('a bound store refuses all late manual operations in another session',
      () async {
    final owner = await LocalRecordOwner.capture();
    final bound = store.scoped(() async => owner);
    final weld =
        InterpassWeld.blank(id: 'w', now: now).copyWith(weldNo: 'stale');
    await seedSignedInAccount();
    for (final operation in <Future<dynamic> Function()>[
      bound.load,
      bound.loadUnit,
      () => bound.upsert(weld),
      () => bound.update('w', (w) => w),
      () => bound.delete('w'),
      () => bound.saveUnit(InterpassUnit.f),
      () => bound.replaceIfUnchanged(weld, weld)
    ]) {
      await expectLater(operation(), throwsA(isA<AccountException>()));
    }
    expect((await store.load()).welds, isEmpty);
  });
  test('owner captured before delayed admission never follows another account',
      () async {
    final owner = await LocalRecordOwner.capture();
    final entered = Completer<void>(), release = Completer<void>();
    final delayed = InterpassStore(captureOwner: () async {
      entered.complete();
      await release.future;
      return owner;
    });
    final pending = delayed.upsert(
        InterpassWeld.blank(id: 'late', now: now).copyWith(weldNo: 'private'));
    final rejected = expectLater(pending, throwsA(isA<AccountException>()));
    await entered.future;
    await seedSignedInAccount();
    release.complete();
    await rejected;
    expect((await store.load()).welds, isEmpty);
    await seedGuestAccount();
    expect((await store.load()).welds, isEmpty);
  });
}
