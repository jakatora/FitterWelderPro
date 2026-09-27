import 'package:flutter_test/flutter_test.dart';

import 'package:cut_list_app/domain/weld_journal/coupon_entry.dart';
import 'package:cut_list_app/domain/weld_journal/weld_consistency.dart';
import 'package:cut_list_app/domain/weld_journal/weld_ndt.dart';

import '../../support/weld_fixtures.dart';

/// Status, odbiór, NDT, daty, PWHT i kupon muszą mówić to samo — inaczej
/// PDF data booka pokazuje przyjętą spoinę, która nie przeszła badań.
void main() {
  final today = DateTime(2026, 9, 26);
  Set<String> codes(Iterable<WeldConsistencyIssue> xs) =>
      xs.map((i) => i.code).toSet();

  test('spoina spójna — bez uwag', () {
    final w = weld('w1',
            status: 'OK',
            ndt: {NdtMethod.rt: ndtOf(NdtScope.selected, NdtResult.ok, 'RT-1')})
        .copyWith(inspector: 'J. Inspektor', inspectedAt: '2026-09-22');
    expect(weldConsistencyIssues(w, today: today), isEmpty);
  });

  test('OK przy RT NOK i przy badaniu bez wyniku', () {
    final w = weld('w1', status: 'OK', ndt: {
      NdtMethod.rt: ndtOf(NdtScope.selected, NdtResult.nok, 'RT-7'),
      NdtMethod.pt: ndtOf(NdtScope.required, NdtResult.none, ''),
    });
    final issues = weldConsistencyIssues(w, today: today);
    expect(codes(issues), {'ok-nok', 'ok-awaiting'});
    expect(issues.first.text(en: false), contains('RT'));
  });

  test('odbiór przy statusie PENDING i datach sprzed spawania / badania', () {
    final w = weld('w1',
            status: 'PENDING',
            date: '2026-09-20',
            ndt: {
              NdtMethod.vt: WeldNdt(
                  scope: NdtScope.required,
                  result: NdtResult.ok,
                  date: '2026-09-21')
            })
        .copyWith(inspector: 'J. Inspektor', inspectedAt: '2026-09-19');
    expect(codes(weldConsistencyIssues(w, today: today)),
        {'accept-status', 'accept-before-weld', 'accept-before-ndt'});
  });

  test('data spawania z przyszłości, PWHT wymagane bez wykresu', () {
    final w = weld('w1', status: 'OK', date: '2026-10-01')
        .copyWith(pwhtRequired: true);
    expect(codes(weldConsistencyIssues(w, today: today)),
        {'weld-future', 'pwht-missing'});
  });

  group('kupon z logu', () {
    const coupon = CouponEntry(
      id: 'k1',
      date: '2026-09-20',
      welder: 'JK-12',
      machine: 'M-3',
      size: '',
      result: CouponResult.nok,
      notes: '',
    );
    final linked = weld('w1').copyWith(couponId: 'k1');

    test('stan odnośnika', () {
      expect(couponLinkState(weld('w0'), null), CouponLinkState.none);
      expect(couponLinkState(linked, null), CouponLinkState.missing);
      expect(couponLinkState(linked, coupon), CouponLinkState.nok);
      expect(couponLinkState(linked, coupon.copyWith(deletedAt: 5)),
          CouponLinkState.deleted);
      expect(
          couponLinkState(
              linked, coupon.copyWith(result: CouponResult.pending)),
          CouponLinkState.pending);
    });

    test('kupon NOK / usunięty / brak → uwaga; nieznany log → bez uwagi', () {
      expect(
          codes(weldConsistencyIssues(linked,
              coupon: coupon, couponKnown: true, today: today)),
          {'coupon-nok'});
      expect(
          codes(weldConsistencyIssues(linked,
              coupon: null, couponKnown: true, today: today)),
          {'coupon-missing'});
      expect(weldConsistencyIssues(linked, today: today), isEmpty);
    });
  });

  test('przy edycji pytamy tylko o nowe niespójności', () {
    final before = weldConsistencyIssues(
        weld('w1', status: 'OK', ndt: {
          NdtMethod.rt: ndtOf(NdtScope.selected, NdtResult.nok, 'RT-7'),
        }),
        today: today);
    final after = weldConsistencyIssues(
        weld('w1', status: 'OK', date: '2026-12-01', ndt: {
          NdtMethod.rt: ndtOf(NdtScope.selected, NdtResult.nok, 'RT-7'),
        }),
        today: today);
    expect(codes(newConsistencyIssues(before, after)), {'weld-future'});
    expect(
        consistencyHistoryText(after, en: false),
        startsWith('Zapisano mimo niespójności dokumentu:\n• '));
  });
}
