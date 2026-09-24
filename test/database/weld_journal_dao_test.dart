import 'package:flutter_test/flutter_test.dart';

import 'package:cut_list_app/database/coupon_dao.dart';
import 'package:cut_list_app/database/db.dart';
import 'package:cut_list_app/database/weld_journal_dao.dart';
import 'package:cut_list_app/domain/weld_journal/coupon_entry.dart';
import 'package:cut_list_app/domain/weld_journal/weld_history.dart';
import 'package:cut_list_app/domain/weld_journal/weld_journal_settings.dart';
import 'package:cut_list_app/domain/weld_journal/weld_ndt.dart';

import '../support/test_database.dart';
import '../support/weld_fixtures.dart';

/// Dziennik jako zapis jakości: każda zmiana zostawia ślad (kto — stempel,
/// kiedy, pole, stara → nowa), usunięcie jest miękkie i odwracalne, naprawa
/// zachowuje poprzedni wynik.
void main() {
  useTestDatabase();

  var now = 1790000000000;
  var seq = 0;
  WeldJournalDao dao() => WeldJournalDao(
        clock: () => now,
        newId: () => 'id-${seq++}',
      );

  setUp(() async {
    final db = await AppDatabase.get();
    for (final t in [
      'weld_journal',
      'weld_journal_history',
      'weld_repairs',
      'weld_journal_projects',
      'weld_coupons',
    ]) {
      await db.delete(t);
    }
    now = 1790000000000;
  });

  test('nowa spoina zostawia wpis "utworzono" ze stemplem', () async {
    await dao().insert(weld('w1', weldNo: 'W-001'), by: 'JK-12');
    final h = await dao().history('w1');
    expect(h, hasLength(1));
    expect(h.single.action, WeldHistoryAction.create);
    expect(h.single.byStamp, 'JK-12');
    expect(h.single.at, 1790000000000);
  });

  test('edycja zapisuje każde zmienione pole ze starą i nową wartością',
      () async {
    await dao().insert(weld('w1', material: '316L'), by: 'JK-12');
    now += 60000;
    final changes = await dao().update(
      weld('w1', material: '304L').copyWith(heatNo1: 'H-9'),
      by: 'MN-03',
    );
    expect(changes.map((c) => c.field).toSet(), {'material', 'heat_no1'});

    final h = (await dao().history('w1'))
        .where((e) => e.action == WeldHistoryAction.update)
        .toList();
    expect(h, hasLength(2));
    final mat = h.firstWhere((e) => e.field == 'material');
    expect(mat.oldValue, '316L');
    expect(mat.newValue, '304L');
    expect(mat.byStamp, 'MN-03');
    expect(mat.at, 1790000060000);

    final stored = (await dao().listAll()).single;
    expect(stored.material, '304L');
  });

  test('zapis bez zmian nie dopisuje historii', () async {
    await dao().insert(weld('w1'));
    expect(await dao().update(weld('w1')), isEmpty);
    expect(await dao().history('w1'), hasLength(1));
  });

  test('zmiana statusu jest osobną akcją w historii', () async {
    await dao().insert(weld('w1', status: 'PENDING'));
    expect(await dao().setStatus('w1', 'OK', by: 'QC-1'), isTrue);
    final h = (await dao().history('w1')).first; // najnowsze pierwsze
    expect(h.action, WeldHistoryAction.status);
    expect(h.oldValue, 'PENDING');
    expect(h.newValue, 'OK');
    expect(h.byStamp, 'QC-1');
    expect((await dao().getById('w1'))!.status, 'OK');
  });

  test('ten sam status nie jest zmianą', () async {
    await dao().insert(weld('w1', status: 'OK'));
    expect(await dao().setStatus('w1', 'OK'), isFalse);
    expect(await dao().history('w1'), hasLength(1));
  });

  test('usunięcie jest miękkie: wiersz zostaje, historia to widzi, '
      'można przywrócić', () async {
    await dao().insert(weld('w1'));
    await dao().softDelete('w1', by: 'JK-12');

    final all = await dao().listAll();
    expect(all.single.isDeleted, isTrue);
    expect(all.single.deletedAt, 1790000000000);

    await dao().restore('w1', by: 'JK-12');
    expect((await dao().listAll()).single.isDeleted, isFalse);

    final actions = (await dao().history('w1')).map((h) => h.action).toList();
    expect(actions, [
      WeldHistoryAction.restore,
      WeldHistoryAction.delete,
      WeldHistoryAction.create,
    ]);
  });

  test('naprawa R1/R2 zachowuje poprzedni wynik i cofa spoinę do badania',
      () async {
    await dao().insert(weld('w1',
        status: 'NOK',
        ndt: {NdtMethod.rt: ndtOf(NdtScope.selected, NdtResult.nok, 'RT-7')}));

    final r1 = await dao()
        .addRepair('w1', date: '2026-09-21', reason: 'porowatość', by: 'JK-12');
    expect(r1.label, 'R1');
    var w = (await dao().getById('w1'))!;
    expect(w.status, 'PENDING');
    expect(w.ndtOf(NdtMethod.rt).result, isEmpty);
    expect(w.repairs.single.prevNdt[NdtMethod.rt]!.reportNo, 'RT-7');

    // Po ponownym RT znowu NOK → R2.
    await dao().update(w.copyWith(
      status: 'NOK',
      ndt: {NdtMethod.rt: ndtOf(NdtScope.selected, NdtResult.nok, 'RT-8')},
    ));
    final r2 = await dao()
        .addRepair('w1', date: '2026-09-22', reason: 'brak przetopu');
    expect(r2.label, 'R2');
    w = (await dao().getById('w1'))!;
    expect(w.repairs.map((r) => r.label), ['R1', 'R2']);
    expect(w.repairs.last.prevNdt[NdtMethod.rt]!.reportNo, 'RT-8');

    final h = await dao().history('w1');
    expect(h.where((e) => e.action == WeldHistoryAction.repair), isNotEmpty);
    // Zmiana wyniku RT przez naprawę też jest w historii.
    expect(
      h.any((e) =>
          e.action == WeldHistoryAction.repair &&
          e.field == 'ndt_rt_result' &&
          e.oldValue == 'NOK'),
      isTrue,
    );
  });

  test('listAll dołącza naprawy i sortuje numery naturalnie', () async {
    for (final no in ['W10', 'W9', 'W11']) {
      await dao().insert(weld(no));
    }
    expect((await dao().listAll()).map((e) => e.weldNo), ['W9', 'W10', 'W11']);
  });

  test('ustawienia projektu: zapis, odczyt, nadpisanie', () async {
    final s = WeldJournalSettingsDao();
    await s.save(WeldJournalProjectSettings.empty('Blok 4').copyWith(
      company: 'Montaż Rur Sp. z o.o.',
      client: 'Browar SA',
      documentNo: 'WL-004',
      revision: 'A',
      volumetricTargetPct: 10,
    ));
    var got = await s.forProject('  blok 4 ');
    expect(got!.client, 'Browar SA');
    expect(got.volumetricTargetPct, 10);

    await s.save(got.copyWith(revision: 'B', volumetricTargetPct: null));
    got = await s.forProject('Blok 4');
    expect(got!.revision, 'B');
    expect(got.volumetricTargetPct, isNull);
    expect(await s.listAll(), hasLength(1));
  });

  test('kupon: edycja zachowuje nowe pola (program, O₂, przebarwienie)',
      () async {
    final c = CouponDao();
    await c.insert(const CouponEntry(
      id: 'c1',
      date: '2026-09-20',
      welder: 'JK-12',
      machine: 'M-3',
      size: '2"×1.65',
      result: 'OK',
      notes: '',
    ));
    final edited = (await c.getById('c1'))!.copyWith(
      programNo: '12',
      programParams: '85/45 A, 2.1 rpm',
      o2Ppm: 18.5,
      heatTint: 2,
      result: 'NOK',
    );
    await c.update(edited);
    final back = (await c.listAll()).single;
    expect(back.toRow(), edited.toRow());
    expect(back.heatTint, 2);
    expect(back.o2Ppm, 18.5);
  });
}
