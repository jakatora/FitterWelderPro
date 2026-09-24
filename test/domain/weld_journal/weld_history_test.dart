import 'package:flutter_test/flutter_test.dart';

import 'package:cut_list_app/domain/weld_journal/weld_entry.dart';
import 'package:cut_list_app/domain/weld_journal/weld_history.dart';
import 'package:cut_list_app/domain/weld_journal/weld_ndt.dart';

import '../../support/weld_fixtures.dart';

/// Historia zmian: edycja nadpisywała wiersz bez śladu, a inspektor pyta
/// właśnie o to, kto i kiedy zmienił wynik. Diff jest czystą funkcją —
/// DAO zapisuje dokładnie to, co ona zwraca.
void main() {
  test('niezmieniony wpis nie daje żadnej zmiany', () {
    final a = weld('w1');
    expect(diffWeldEntries(a, a.copyWith()), isEmpty);
  });

  test('zmienione pola mają starą i nową wartość', () {
    final before = weld('w1', status: 'PENDING', material: '316L');
    final after = before.copyWith(status: 'OK', material: '304L');
    final changes = diffWeldEntries(before, after);
    expect(changes.map((c) => c.field).toSet(), {'status', 'material'});
    final status = changes.firstWhere((c) => c.field == 'status');
    expect(status.oldValue, 'PENDING');
    expect(status.newValue, 'OK');
  });

  test('zmiana wyniku NDT jest osobnym polem', () {
    final before = weld('w1', ndt: {NdtMethod.rt: ndtOf(NdtScope.selected)});
    final after = before.copyWith(ndt: {
      NdtMethod.rt: ndtOf(NdtScope.selected, NdtResult.nok, 'RT-7'),
    });
    final changes = diffWeldEntries(before, after);
    expect(changes.map((c) => c.field).toSet(),
        {'ndt_rt_result', 'ndt_rt_report'});
    expect(changes.firstWhere((c) => c.field == 'ndt_rt_result').newValue,
        'NOK');
  });

  test('identyfikatory techniczne i znacznik usunięcia nie są polami historii',
      () {
    final before = weld('w1');
    final after = before.copyWith(
      projectId: 'p-9',
      couponId: 'c-1',
      deletedAt: 123,
    );
    expect(diffWeldEntries(before, after), isEmpty);
  });

  test('każde pole historii ma etykietę PL i EN', () {
    for (final field in weldAuditFieldKeys) {
      expect(weldFieldLabel(field, en: false), isNot(field),
          reason: 'brak etykiety PL dla $field');
      expect(weldFieldLabel(field, en: true), isNotEmpty);
    }
  });

  test('wiersz historii przechodzi przez bazę bez zmian', () {
    const h = WeldHistoryEntry(
      id: 'h1',
      weldId: 'w1',
      at: 1790000000000,
      byStamp: 'JK-12',
      action: WeldHistoryAction.status,
      field: 'status',
      oldValue: 'PENDING',
      newValue: 'OK',
    );
    expect(WeldHistoryEntry.fromRow(h.toRow()).toRow(), h.toRow());
  });

  test('WeldEntry przechodzi przez wiersz bazy bez zmian', () {
    final e = weld('w1',
            ndt: {NdtMethod.ut: ndtOf(NdtScope.required, NdtResult.ok, 'UT-1')})
        .copyWith(
      pwhtRequired: true,
      pwhtChart: 'PW-3',
      projectId: 'p1',
      couponId: 'c1',
      spool: 'SP-01',
      position: '5G',
    );
    final back = WeldEntry.fromRow(e.toRow());
    expect(back.toRow(), e.toRow());
    expect(back.pwhtRequired, isTrue);
    expect(back.ndtOf(NdtMethod.ut).reportNo, 'UT-1');
  });
}
