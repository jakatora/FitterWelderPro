import 'package:flutter_test/flutter_test.dart';

import 'package:cut_list_app/domain/weld_journal/weld_ndt.dart';
import 'package:cut_list_app/domain/weld_journal/weld_repair.dart';

import '../../support/weld_fixtures.dart';

/// Naprawa R1/R2: spoina naprawiona wraca do badania, ale poprzedni wynik
/// (NOK z RT i status) nie może zniknąć — zostaje w zapisie naprawy.
void main() {
  final rejected = weld(
    'w1',
    status: 'NOK',
    ndt: {
      NdtMethod.vt: ndtOf(NdtScope.required, NdtResult.ok, 'VT-1'),
      NdtMethod.rt: ndtOf(NdtScope.selected, NdtResult.nok, 'RT-7'),
      // Wynik bez zaznaczonego zakresu — po naprawie badanie jest wymagane.
      NdtMethod.pt: ndtOf(NdtScope.none, NdtResult.ok, 'PT-2'),
    },
  );

  test('naprawa zapisuje poprzedni status i wyniki NDT', () {
    final plan = planWeldRepair(
      rejected,
      id: 'r1',
      date: '2026-09-21',
      reason: 'Porowatość w graniu',
      byStamp: 'JK-12',
      createdAt: 1000,
    );
    expect(plan.repair.seq, 1);
    expect(plan.repair.label, 'R1');
    expect(plan.repair.prevStatus, 'NOK');
    expect(plan.repair.prevNdt[NdtMethod.rt]!.result, NdtResult.nok);
    expect(plan.repair.prevNdt[NdtMethod.rt]!.reportNo, 'RT-7');
    expect(plan.repair.reason, 'Porowatość w graniu');
  });

  test('spoina po naprawie czeka na ponowne badanie tymi samymi metodami', () {
    final plan = planWeldRepair(rejected,
        id: 'r1', date: '2026-09-21', reason: 'x', byStamp: '', createdAt: 1);
    final after = plan.weld;
    expect(after.status, 'PENDING');
    expect(after.ndtOf(NdtMethod.rt).result, isEmpty);
    expect(after.ndtOf(NdtMethod.rt).reportNo, isEmpty);
    // Zakres zostaje: wybrana do RT dalej jest wybrana.
    expect(after.ndtOf(NdtMethod.rt).scope, NdtScope.selected);
    // Metoda z wynikiem, ale bez zakresu, staje się wymagana.
    expect(after.ndtOf(NdtMethod.pt).scope, NdtScope.required);
    // Metody nieużyte zostają puste.
    expect(after.ndtOf(NdtMethod.ut).isEmpty, isTrue);
  });

  test('druga naprawa dostaje numer R2', () {
    final first = planWeldRepair(rejected,
        id: 'r1', date: '2026-09-21', reason: 'a', byStamp: '', createdAt: 1);
    final withR1 = first.weld.copyWith(repairs: [first.repair], status: 'NOK');
    final second = planWeldRepair(withR1,
        id: 'r2', date: '2026-09-22', reason: 'b', byStamp: '', createdAt: 2);
    expect(second.repair.seq, 2);
    expect(second.repair.label, 'R2');
    expect(second.weld.repairs.map((r) => r.label), ['R1', 'R2']);
  });

  test('zapis naprawy przechodzi przez bazę bez zmian', () {
    final plan = planWeldRepair(rejected,
        id: 'r1', date: '2026-09-21', reason: 'Podtopienie', byStamp: 'JK-12',
        createdAt: 5);
    final back = WeldRepair.fromRow(plan.repair.toRow());
    expect(back.toRow(), plan.repair.toRow());
    expect(back.prevNdt[NdtMethod.rt]!.result, NdtResult.nok);
  });

  test('uszkodzony zapis poprzednich wyników nie wywraca odczytu', () {
    final row = planWeldRepair(rejected,
            id: 'r1', date: '', reason: '', byStamp: '', createdAt: 1)
        .repair
        .toRow()
      ..['prev_ndt'] = '{nie-json';
    expect(WeldRepair.fromRow(row).prevNdt, isEmpty);
  });
}
