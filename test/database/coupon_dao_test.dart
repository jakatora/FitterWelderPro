import 'package:flutter_test/flutter_test.dart';

import 'package:cut_list_app/database/coupon_dao.dart';
import 'package:cut_list_app/database/db.dart';
import 'package:cut_list_app/database/weld_journal_dao.dart';
import 'package:cut_list_app/domain/weld_journal/coupon_entry.dart';
import 'package:cut_list_app/domain/weld_journal/weld_history.dart';

import '../support/test_database.dart';
import '../support/weld_fixtures.dart';

/// Log kuponów jako zapis jakości (v25): historia zmian, miękkie usuwanie,
/// brak domyślnego OK i „żywy” odnośnik w spoinach.
void main() {
  useTestDatabase();

  var now = 1790000000000;
  var seq = 0;
  CouponDao coupons() =>
      CouponDao(clock: () => now, newId: () => 'c-${seq++}');
  WeldJournalDao journal() =>
      WeldJournalDao(clock: () => now, newId: () => 'w-${seq++}');

  setUp(() async {
    final db = await AppDatabase.get();
    for (final t in [
      'weld_journal',
      'weld_journal_history',
      'weld_coupons',
      'weld_coupon_history',
    ]) {
      await db.delete(t);
    }
  });

  const ok = CouponEntry(
    id: 'k1',
    date: '2026-09-20',
    welder: 'JK-12',
    machine: 'M-3',
    size: '2"×1.65',
    result: CouponResult.ok,
    notes: '',
    acceptedBy: 'QC Nowak',
    acceptedAt: '2026-09-20',
  );

  test('pusty wynik w starym wierszu to „do oceny”, nie OK', () {
    final row = ok.toRow()..['result'] = null;
    expect(CouponEntry.fromRow(row).result, CouponResult.pending);
    final empty = ok.toRow()..['result'] = '';
    expect(CouponEntry.fromRow(empty).isPending, isTrue);
  });

  test('zmiana wyniku na NOK: historia kuponu i odnośnik w spoinie', () async {
    await coupons().insert(ok, by: 'JK-12');
    await journal().insert(
        weld('w1').copyWith(couponId: 'k1', couponRef: ok.reference));
    expect(ok.reference, endsWith('· OK'));

    now += 1000;
    final changed =
        await coupons().update(ok.copyWith(result: CouponResult.nok), by: 'QC');
    expect(changed, 1);

    final w = (await journal().getById('w1'))!;
    expect(w.couponRef, endsWith('· NOK'));
    final wh = await journal().history('w1');
    expect(
        wh.any((e) =>
            e.action == WeldHistoryAction.update &&
            e.field == 'coupon_ref' &&
            e.oldValue.endsWith('OK') &&
            e.newValue.endsWith('NOK') &&
            e.byStamp == 'QC'),
        isTrue);

    final ch = await coupons().history('k1');
    expect(ch.map((e) => e.action),
        [CouponHistoryAction.update, CouponHistoryAction.create]);
    expect(ch.first.field, 'result');
    expect(ch.first.oldValue, 'OK');
    expect(ch.first.newValue, 'NOK');
  });

  test('miękkie usuwanie: wiersz zostaje, spoina widzi „usunięty”, cofnięcie',
      () async {
    await coupons().insert(ok);
    await journal().insert(
        weld('w1').copyWith(couponId: 'k1', couponRef: ok.reference));

    await coupons().softDelete('k1', by: 'JK-12');
    expect(await coupons().listAll(), isEmpty);
    final all = await coupons().listAll(includeDeleted: true);
    expect(all.single.isDeleted, isTrue);
    expect((await coupons().getById('k1'))!.isDeleted, isTrue);
    var w = (await journal().getById('w1'))!;
    expect(w.couponRef, contains(kCouponDeletedMarker));

    await coupons().restore('k1');
    expect(await coupons().listAll(), hasLength(1));
    w = (await journal().getById('w1'))!;
    expect(w.couponRef, isNot(contains(kCouponDeletedMarker)));
    expect((await coupons().history('k1')).map((e) => e.action).toList(), [
      CouponHistoryAction.restore,
      CouponHistoryAction.delete,
      CouponHistoryAction.create,
    ]);
  });

  test('zapis bez zmian nie pisze historii ani nie rusza spoin', () async {
    await coupons().insert(ok);
    expect(await coupons().update(ok), 0);
    expect(await coupons().history('k1'), hasLength(1));
  });

  test('ostrzeżenia kuponu: przebarwienie ponad limit przy OK, OK bez „przyjął”',
      () {
    final hot = ok.copyWith(heatTint: 5);
    expect(couponWarnings(hot, tintLimit: 4, en: false).single,
        contains('Przebarwienie poziom 5'));
    expect(couponWarnings(hot, tintLimit: 5, en: false), isEmpty);
    expect(couponWarnings(ok.copyWith(acceptedBy: ''), tintLimit: 4, en: true)
        .single, contains('accepted by'));
    expect(
        couponWarnings(ok.copyWith(result: CouponResult.pending, heatTint: 9),
            tintLimit: 2, en: false),
        isEmpty);
  });
}
