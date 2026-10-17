// Plan badań NDT na prawdziwej bazie testowej: spoiny i naprawy zapisane
// przez WeldJournalDao (R1 czyści wynik i zostawia zakres, NOK trafia do
// rekordu naprawy), odczyt listAll(), usunięta spoina poza planem.

import 'package:flutter_test/flutter_test.dart';

import 'package:cut_list_app/database/db.dart';
import 'package:cut_list_app/database/weld_journal_dao.dart';
import 'package:cut_list_app/domain/ndt/ndt_plan.dart';
import 'package:cut_list_app/domain/weld_journal/weld_entry.dart';
import 'package:cut_list_app/domain/weld_journal/weld_ndt.dart';

import '../../support/test_database.dart';
import '../../support/weld_fixtures.dart';

WeldEntry _bw(String id,
        {String welder = 'JK-12',
        String cap = '',
        Map<NdtMethod, WeldNdt> ndt = const {}}) =>
    weld(id, welder: welder, capWelder: cap, ndt: ndt)
        .copyWith(jointType: WeldJointType.butt);

const NdtRule _rt10 = NdtRule(
  id: 'rt',
  method: NdtMethod.rt,
  bp: 1000,
  joints: [WeldJointType.butt],
);

void main() {
  useTestDatabase();

  setUp(() async {
    final db = await AppDatabase.get();
    for (final t in [
      'weld_journal',
      'weld_journal_history',
      'weld_repairs',
      'weld_journal_projects',
    ]) {
      await db.delete(t);
    }
  });

  test(
      'z bazy (DAO): naprawa R1 → czeka na ponowne RT i 2 dodatkowe; po '
      'badaniach linia gotowa', () async {
    final dao = WeldJournalDao();
    await dao.insert(
        _bw('w1', ndt: {NdtMethod.rt: ndtOf(NdtScope.selected, NdtResult.nok)}));
    await dao.insert(_bw('w2',
        cap: 'AB-03',
        ndt: {NdtMethod.rt: ndtOf(NdtScope.selected, NdtResult.ok)}));
    for (var i = 3; i <= 10; i++) {
      await dao.insert(_bw('w$i'));
    }
    await dao.addRepair('w1', date: '2026-10-15', reason: 'brak przetopu');

    var plan = computeNdtPlan(await dao.listAll(),
        rules: const [_rt10], project: 'Blok 4');
    var jk = plan.groups.singleWhere((g) => g.welder == 'JK-12');
    expect(jk.welds, hasLength(10));
    expect(jk.examined, 1); // w2; w1 po naprawie bez wyniku
    expect(jk.ordered.map((w) => w.id), ['w1']);
    expect(jk.progressive, 2); // NOK z rekordu naprawy (weld_stats)
    expect(jk.status, NdtGroupStatus.repairsOpen);
    final ab = plan.groups.singleWhere((g) => g.welder == 'AB-03');
    expect(ab.isComplete, isTrue); // spoina wspólna w2 liczy się obu
    var line = plan.lines.single;
    expect(line.ready, isFalse);
    expect(line.blockers[NdtBlocker.repairsAwaiting], 1);
    expect(line.blockers[NdtBlocker.progressive], 2);

    // Ponowne RT naprawy OK, dwie dodatkowe OK, jedna spoina usunięta.
    Future<void> setRt(String id, String scope) async {
      final e = (await dao.getById(id))!;
      await dao.update(e.copyWith(
          ndt: {NdtMethod.rt: ndtOf(scope, NdtResult.ok, 'RT-$id')}));
    }

    await setRt('w1', NdtScope.selected);
    await setRt('w3', NdtScope.progressive);
    await setRt('w4', NdtScope.progressive);
    await dao.softDelete('w10');

    plan = computeNdtPlan(await dao.listAll(),
        rules: const [_rt10], project: 'blok 4');
    jk = plan.groups.singleWhere((g) => g.welder == 'JK-12');
    expect(jk.welds, hasLength(9));
    expect(jk.required, 1);
    expect(jk.examined, 2); // w1, w2 — „dod." nie liczą się do 10 %
    expect(jk.progressive, 0);
    expect(jk.isComplete, isTrue);
    line = plan.lines.single;
    expect(line.ready, isTrue);
    expect(line.welds.map((w) => w.id), isNot(contains('w10')));
  });
}
