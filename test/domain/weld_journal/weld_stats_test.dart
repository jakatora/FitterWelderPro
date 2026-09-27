import 'package:flutter_test/flutter_test.dart';

import 'package:cut_list_app/domain/weld_journal/weld_ndt.dart';
import 'package:cut_list_app/domain/weld_journal/weld_repair.dart';
import 'package:cut_list_app/domain/weld_journal/weld_stats.dart';

import '../../support/weld_fixtures.dart';

WeldRepair _repair(String weldId, int seq,
        {Map<NdtMethod, WeldNdt> prevNdt = const {}}) =>
    WeldRepair(
      id: '$weldId-r$seq',
      weldId: weldId,
      seq: seq,
      date: '2026-09-21',
      reason: 'porowatość',
      prevStatus: 'NOK',
      prevNdt: prevNdt,
      byStamp: 'JK-12',
      createdAt: seq,
    );

/// Podsumowanie NDT: % spoin zbadanych objętościowo (RT/UT) per projekt,
/// linia i spawacz, wskaźnik napraw i licznik "do dobadania" wg ASME B31.3
/// §341.3.4. Wymaganego % NIE ma w kodzie — przychodzi z ustawień projektu.
void main() {
  final journal = [
    weld('a', project: 'Blok 4', line: 'L-12', welder: 'JK-12',
        ndt: {NdtMethod.rt: ndtOf(NdtScope.selected, NdtResult.ok)}),
    weld('b', project: 'Blok 4', line: 'L-12', welder: 'JK-12',
        ndt: {NdtMethod.rt: ndtOf(NdtScope.selected, NdtResult.nok)}),
    weld('c', project: 'Blok 4', line: 'L-14', welder: 'JK-12'),
    weld('d', project: 'Blok 4', line: 'L-14', welder: 'MN-03',
        ndt: {NdtMethod.ut: ndtOf(NdtScope.required, NdtResult.ok)}),
    weld('e', project: 'Browar', line: 'L-1', welder: 'MN-03'),
    // Usunięta — nie liczy się nigdzie.
    weld('x', project: 'Blok 4', welder: 'JK-12', deletedAt: 1,
        ndt: {NdtMethod.rt: ndtOf(NdtScope.selected, NdtResult.nok)}),
  ];

  test('% spoin zbadanych RT/UT w całym zbiorze', () {
    final s = computeWeldJournalStats(journal);
    expect(s.total.welds, 5);
    expect(s.total.volumetricExamined, 3); // a, b (RT), d (UT)
    expect(s.total.rtExamined, 2);
    expect(s.total.utExamined, 1);
    expect(s.total.volumetricPct, closeTo(60, 1e-9));
  });

  test('per projekt, z celem z ustawień projektu', () {
    final s = computeWeldJournalStats(journal,
        volumetricTargets: {'blok 4': 80.0});
    final blok = s.byProject.firstWhere((g) => g.key == 'Blok 4');
    expect(blok.welds, 4);
    expect(blok.volumetricExamined, 3);
    expect(blok.volumetricPct, closeTo(75, 1e-9));
    expect(blok.targetPct, 80.0);
    expect(blok.belowTarget, isTrue);
    final browar = s.byProject.firstWhere((g) => g.key == 'Browar');
    // Bez ustawienia nie ma celu — i nie ma "poniżej celu".
    expect(browar.targetPct, isNull);
    expect(browar.belowTarget, isFalse);
  });

  test('per linia w projekcie', () {
    final s = computeWeldJournalStats(journal);
    final l12 = s.byLine.firstWhere((g) => g.key == 'Blok 4 · L-12');
    expect(l12.welds, 2);
    expect(l12.volumetricPct, closeTo(100, 1e-9));
    final l14 = s.byLine.firstWhere((g) => g.key == 'Blok 4 · L-14');
    expect(l14.volumetricPct, closeTo(50, 1e-9));
  });

  test('per spawacz liczy też stemple graniówki i lica', () {
    final s = computeWeldJournalStats([
      weld('a', welder: 'JK-12', rootWelder: 'MN-03', capWelder: 'JK-12'),
    ]);
    expect(s.byWelder.map((g) => g.key).toSet(), {'JK-12', 'MN-03'});
    expect(s.byWelder.every((g) => g.welds == 1), isTrue);
  });

  test('wskaźnik napraw per spawacz = spoiny naprawiane / spoiny', () {
    final s = computeWeldJournalStats([
      weld('a', welder: 'JK-12', repairs: [_repair('a', 1), _repair('a', 2)]),
      weld('b', welder: 'JK-12'),
      weld('c', welder: 'JK-12'),
      weld('d', welder: 'JK-12'),
    ]);
    final jk = s.byWelder.single;
    expect(jk.repairedWelds, 1);
    expect(jk.repairs, 2);
    expect(jk.repairRatePct, closeTo(25, 1e-9));
  });

  group('§341.3.4 — dwie dodatkowe spoiny za każdą odrzuconą', () {
    test('odrzucona w badaniu wyrywkowym → 2 do dobadania', () {
      final s = computeWeldJournalStats(journal);
      final jk = s.byWelder.firstWhere((g) => g.key == 'JK-12');
      expect(jk.rejects, 1); // b; x jest usunięta
      expect(jk.progressiveRequired, 2);
      expect(jk.toExamine, 2);
    });

    test('dodatkowe badania oznaczone przez użytkownika zmniejszają licznik',
        () {
      final s = computeWeldJournalStats([
        weld('b', welder: 'JK-12',
            ndt: {NdtMethod.rt: ndtOf(NdtScope.selected, NdtResult.nok)}),
        weld('c', welder: 'JK-12',
            ndt: {NdtMethod.rt: ndtOf(NdtScope.progressive, NdtResult.ok)}),
      ]);
      final jk = s.byWelder.single;
      expect(jk.progressiveSelected, 1);
      expect(jk.toExamine, 1);
    });

    test('odrzucenie przy badaniu 100% (wymagane) nie uruchamia §341.3.4',
        () {
      final s = computeWeldJournalStats([
        weld('b', welder: 'JK-12',
            ndt: {NdtMethod.rt: ndtOf(NdtScope.required, NdtResult.nok)}),
      ]);
      expect(s.byWelder.single.rejects, 0);
      expect(s.byWelder.single.toExamine, 0);
    });

    test('odrzucenie sprzed naprawy nadal się liczy', () {
      // Po naprawie wynik RT jest wyczyszczony, a NOK siedzi w zapisie R1.
      final s = computeWeldJournalStats([
        weld('b', welder: 'JK-12', repairs: [
          _repair('b', 1, prevNdt: {
            NdtMethod.rt: ndtOf(NdtScope.selected, NdtResult.nok),
          }),
        ]),
      ]);
      expect(s.byWelder.single.rejects, 1);
      expect(s.byWelder.single.toExamine, 2);
    });

    test('licznik nie spada poniżej zera', () {
      final s = computeWeldJournalStats([
        weld('c', welder: 'JK-12',
            ndt: {NdtMethod.rt: ndtOf(NdtScope.progressive, NdtResult.ok)}),
      ]);
      expect(s.byWelder.single.toExamine, 0);
    });
  });

  test('pusty zbiór nie dzieli przez zero', () {
    final s = computeWeldJournalStats(const []);
    expect(s.total.welds, 0);
    expect(s.total.volumetricPct, 0);
    expect(s.total.repairRatePct, 0);
    expect(s.byWelder, isEmpty);
  });

  group('§341.3.4 — bez fałszywych odrzutów, per metoda', () {
    test('VT NOK bez zakresu nie jest odrzutem losowym', () {
      final st = computeWeldJournalStats([
        weld('w1', ndt: {NdtMethod.vt: ndtOf(NdtScope.none, NdtResult.nok)}),
      ]);
      expect(st.total.rejects, 0);
      expect(st.total.toExamine, 0);
      expect(st.total.rejectsNoScope, 1);
    });

    test('dodatkowe badanie innej metody nie odpowiada na odrzut', () {
      final st = computeWeldJournalStats([
        weld('w1', ndt: {NdtMethod.pt: ndtOf(NdtScope.selected, NdtResult.nok)}),
        weld('w2', ndt: {NdtMethod.rt: ndtOf(NdtScope.progressive)}),
        weld('w3', ndt: {NdtMethod.rt: ndtOf(NdtScope.progressive)}),
      ]);
      expect(st.total.rejectsByMethod[NdtMethod.pt], 1);
      expect(st.total.toExamineBy(NdtMethod.pt), 2);
      expect(st.total.toExamine, 2);
    });
  });
}
