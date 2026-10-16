// Postęp robót z dziennika: DI z tabeli NPS (≈ poza tabelą), brak
// podwójnego liczenia spoiny z dwoma spawaczami, odsetek napraw RT/UT
// (także wynik sprzed naprawy), tempo z okna dni roboczych, pusty zakres.

import 'package:flutter_test/flutter_test.dart';

import 'package:cut_list_app/domain/progress/weld_progress.dart';
import 'package:cut_list_app/domain/progress/work_calendar.dart';
import 'package:cut_list_app/domain/weld_journal/weld_entry.dart';
import 'package:cut_list_app/domain/weld_journal/weld_ndt.dart';
import 'package:cut_list_app/domain/weld_journal/weld_repair.dart';
import 'package:cut_list_app/domain/weld_journal/weld_stats.dart';

import '../../support/weld_fixtures.dart';

/// Spoina po naprawie: wynik [prev] zapamiętany w rekordzie naprawy, bieżące
/// badanie wyczyszczone (jak robi to DAO).
WeldEntry repaired(WeldEntry w, int n, {String id = 'r'}) {
  var x = w;
  for (var i = 0; i < n; i++) {
    x = planWeldRepair(
      x.copyWith(ndt: {
        NdtMethod.rt: ndtOf(NdtScope.selected, NdtResult.nok, 'RT-$i'),
      }),
      id: '$id$i',
      date: '2026-10-1${i + 1}',
      reason: 'porowatość',
      byStamp: 'QC',
      createdAt: i,
    ).weld;
  }
  return x;
}

void main() {
  group('DI z OD', () {
    test('OD z tabeli NPS daje rozmiar w calach (kropka i przecinek)', () {
      expect(weldDiameterInches(weld('a').copyWith(od: '60.3'))!.inches, 2);
      final d = weldDiameterInches(weld('a').copyWith(od: '114,3'))!;
      expect(d.inches, 4);
      expect(d.approx, isFalse);
      expect(weldDiameterInches(weld('a').copyWith(od: '168.3'))!.inches, 6);
    });

    test('OD spoza tabeli → OD / 25,4 oznaczone jako przybliżone', () {
      final d = weldDiameterInches(weld('a').copyWith(od: '101,6'))!;
      expect(d.inches, closeTo(4.0, 1e-9));
      expect(d.approx, isTrue);
    });

    test('brak OD, tekst albo zero → bez DI, liczone osobno', () {
      for (final od in ['', 'DN50', '0', '-60']) {
        expect(weldDiameterInches(weld('a').copyWith(od: od)), isNull,
            reason: od);
      }
      final s = summarizeProgress([
        weld('a').copyWith(od: '60.3'),
        weld('b').copyWith(od: ''),
        weld('c').copyWith(od: '101.6'),
      ]);
      expect(s.welds, 3);
      expect(s.noOdWelds, 1);
      expect(s.approxWelds, 1);
      expect(s.diApprox, isTrue);
      expect(s.di, closeTo(6, 1e-9));
    });
  });

  group('spawacze', () {
    test('spoina z dwoma spawaczami: u obu, ale suma brygady liczy ją raz', () {
      final s = summarizeProgress([
        // Grań AB-03, lico JK-12, 2" → 2 DI.
        weld('a', welder: 'JK-12', rootWelder: 'AB-03'),
        // Sam JK-12, 4" → 4 DI.
        weld('b', welder: 'JK-12').copyWith(od: '114.3'),
        // Ten sam stempel innymi literami — jeden spawacz, nie dwóch.
        weld('c', welder: 'jk-12', rootWelder: 'JK-12'),
      ]);
      expect(s.welds, 3);
      expect(s.di, 8);
      final jk = s.welders.firstWhere((w) => w.stamp == 'JK-12');
      final ab = s.welders.firstWhere((w) => w.stamp == 'AB-03');
      expect(s.welders, hasLength(2));
      expect(jk.welds, 3);
      expect(jk.sharedWelds, 1);
      expect(jk.weldsShare, 2.5);
      expect(jk.diShare, 7);
      expect(ab.welds, 1);
      expect(ab.sharedWelds, 1);
      expect(ab.diShare, 1);
      // Wiersze spawaczy: 4 spoiny, ale brygada 3; udziały i DI sumują się
      // dokładnie do brygady.
      expect(s.welders.fold<int>(0, (x, w) => x + w.welds), 4);
      expect(s.welders.fold<double>(0, (x, w) => x + w.weldsShare), s.welds);
      expect(s.welders.fold<double>(0, (x, w) => x + w.diShare), s.di);
      // Najwięcej DI pierwszy.
      expect(s.welders.first.stamp, 'JK-12');
    });

    test('spoina bez stempla trafia do „—" na końcu listy', () {
      final s = summarizeProgress([
        weld('a', welder: ''),
        weld('b', welder: 'JK-12'),
      ]);
      expect(s.welders.last.stamp, kNoStamp);
      expect(s.welders.last.isUnstamped, isTrue);
      expect(s.welders.first.stamp, 'JK-12');
    });

    test('status: PENDING i NOK też są wykonane', () {
      final s = summarizeProgress([
        weld('a', status: WeldStatus.ok),
        weld('b', status: WeldStatus.nok),
        weld('c', status: WeldStatus.pending),
        weld('d', status: 'ACC'),
      ]);
      expect(s.welds, 4);
      expect((s.statusOk, s.statusNok, s.statusPending, s.statusOther),
          (1, 1, 1, 1));
    });

    test('usunięte wpisy się nie liczą', () {
      final s = summarizeProgress([weld('a'), weld('b', deletedAt: 1)]);
      expect(s.welds, 1);
    });
  });

  group('odsetek napraw RT/UT', () {
    final welds = [
      // JK: zbadana RT OK.
      weld('j1', welder: 'JK-12', ndt: {
        NdtMethod.rt: ndtOf(NdtScope.selected, NdtResult.ok),
      }),
      // JK: RT NOK → R1, czeka na ponowne RT (bieżącego wyniku już nie ma).
      repaired(weld('j2', welder: 'JK-12'), 1, id: 'j2-'),
      // JK: niezbadana.
      weld('j3', welder: 'JK-12'),
      // AB: UT NOK, naprawa jeszcze niewpisana.
      weld('a1', welder: 'AB-03', ndt: {
        NdtMethod.ut: ndtOf(NdtScope.selected, NdtResult.nok),
      }),
      // AB: R1 i R2, teraz RT OK.
      repaired(weld('a2', welder: 'AB-03'), 2, id: 'a2-').copyWith(ndt: {
        NdtMethod.rt: ndtOf(NdtScope.selected, NdtResult.ok),
      }),
      // VT NOK nie jest badaniem objętościowym.
      weld('a3', welder: 'AB-03', ndt: {
        NdtMethod.vt: ndtOf(NdtScope.required, NdtResult.nok),
      }),
    ];

    test('wynik sprzed naprawy liczy się do zbadanych i odrzuconych', () {
      expect(weldVolumetricExaminedEver(welds[1]), isTrue);
      expect(welds[1].isVolumetricExamined, isFalse);
      expect(weldVolumetricRejectedEver(welds[1]), isTrue);
      expect(weldVolumetricExaminedEver(welds[2]), isFalse);
      expect(weldVolumetricExaminedEver(welds[5]), isFalse);
    });

    test('spawacz i brygada: odrzucone ÷ zbadane RT/UT, R1 i R2+', () {
      final s = summarizeProgress(welds);
      final jk = s.welders.firstWhere((w) => w.stamp == 'JK-12').quality;
      final ab = s.welders.firstWhere((w) => w.stamp == 'AB-03').quality;
      expect((jk.volumetricExamined, jk.volumetricRejected), (2, 1));
      expect(jk.repairRatePct, 50);
      expect((jk.repairs, jk.r1, jk.r2plus, jk.repairedWelds), (1, 1, 0, 1));
      expect((ab.volumetricExamined, ab.volumetricRejected), (2, 2));
      expect(ab.repairRatePct, 100);
      expect((ab.repairs, ab.r1, ab.r2plus), (2, 1, 1));

      expect((s.crew.volumetricExamined, s.crew.volumetricRejected), (4, 3));
      expect(s.crew.repairRatePct, 75);
      expect(s.crew.repairs, 3);
      expect(s.crew.repairedWelds, 2);
      expect((s.crew.r1, s.crew.r2plus), (2, 1));
    });

    test('naprawy i §341.3.4 zgodne z podsumowaniem NDT dziennika', () {
      final s = summarizeProgress(welds);
      final stats = computeWeldJournalStats(welds);
      for (final g in stats.byWelder) {
        final w = s.welders.firstWhere((x) => x.stamp == g.key);
        expect(w.quality.repairs, g.repairs, reason: g.key);
        expect(w.quality.repairedWelds, g.repairedWelds, reason: g.key);
        expect(w.quality.toExamine, g.toExamine, reason: g.key);
      }
      expect(s.crew.repairs, stats.total.repairs);
    });

    test('bez RT/UT nie ma odsetka (nie podstawiamy innego mianownika)', () {
      final s = summarizeProgress([
        // Naprawa po odrzuceniu w VT — RT/UT nigdy nie było.
        weld('x', welder: 'ZZ-1', repairs: [
          WeldRepair(
            id: 'r',
            weldId: 'x',
            seq: 1,
            date: '2026-10-10',
            reason: 'podtopienie',
            prevStatus: 'NOK',
            prevNdt: {NdtMethod.vt: ndtOf(NdtScope.required, NdtResult.nok)},
            byStamp: '',
            createdAt: 0,
          ),
        ]),
      ]);
      final q = s.welders.single.quality;
      expect(q.repairs, 1);
      expect(q.volumetricExamined, 0);
      expect(q.repairRatePct, isNull);
      expect(q.repairedWeldsPct, 100);
    });
  });

  group('tempo', () {
    // Środa 2026-10-14.
    final today = DateTime(2026, 10, 14, 15, 30);
    const week = WorkWeek();

    test('okno nie sięga przed pierwszą spoinę; dziś bez wpisów → do wczoraj',
        () {
      final scope = [
        weld('a', date: '2026-10-12'),
        weld('b', date: '2026-10-12'),
        weld('c', date: '2026-10-13').copyWith(od: '114.3'),
      ];
      final p = computePace(scope, today: today, week: week)!;
      expect(p.from, DateTime(2026, 10, 12));
      expect(p.to, DateTime(2026, 10, 13));
      expect(p.workingDays, 2);
      expect(p.requestedDays, 10);
      expect(p.welds, 3);
      expect(p.di, 8);
      expect(p.diPerDay, 4);
      expect(p.weldsPerDay, 1.5);
    });

    test('dziś z wpisami liczy się do tempa', () {
      final scope = [
        weld('a', date: '2026-10-12'),
        weld('b', date: '2026-10-14'),
      ];
      expect(isTodayLogged(scope, today), isTrue);
      final p = computePace(scope, today: today, week: week)!;
      expect(p.to, DateTime(2026, 10, 14));
      expect(p.workingDays, 3);
      expect(p.di, 4);
    });

    test('sobota z nadgodzinami: do sumy tak, do mianownika tylko z sobotami',
        () {
      final scope = [
        weld('sat', date: '2026-10-10'),
        weld('mon', date: '2026-10-12'),
        weld('tue', date: '2026-10-13'),
        // Literówka w przyszłość nie podbija tempa.
        weld('future', date: '2026-10-20'),
      ];
      final p = computePace(scope, today: today, week: week)!;
      expect(p.from, DateTime(2026, 10, 10));
      expect(p.welds, 3);
      expect(p.workingDays, 2);
      final ps = computePace(scope,
          today: today, week: const WorkWeek(saturdays: true))!;
      expect(ps.workingDays, 3);
      expect(ps.di, 6);
    });

    test('okno N dni roboczych przeskakuje weekend', () {
      final scope = [
        for (final d in ['2026-10-01', '2026-10-08', '2026-10-09', '2026-10-13'])
          weld(d, date: d),
      ];
      final p = computePace(scope, today: today, week: week, workingDays: 3)!;
      // Wczoraj (wt 13), pn 12, pt 9 — trzy dni robocze.
      expect(p.from, DateTime(2026, 10, 9));
      expect(p.to, DateTime(2026, 10, 13));
      expect(p.workingDays, 3);
      expect(p.welds, 2);
    });
  });

  group('pusty zakres', () {
    test('brak spoin: zera, brak odsetka, brak tempa', () {
      final s = summarizeProgress(const []);
      expect(s.isEmpty, isTrue);
      expect(s.welds, 0);
      expect(s.di, 0);
      expect(s.welders, isEmpty);
      expect(s.days, isEmpty);
      expect(s.crew.repairRatePct, isNull);
      expect(s.dayOf(DateTime(2026, 10, 14)).welds, 0);
      expect(
          computePace(const [],
              today: DateTime(2026, 10, 14), week: const WorkWeek()),
          isNull);
    });

    test('same spoiny bez daty: liczą się, ale bez dni i tempa', () {
      final scope = [weld('a', date: ''), weld('b', date: '2026-02-30')];
      final s = summarizeProgress(scope);
      expect(s.welds, 2);
      expect(s.undatedWelds, 2);
      expect(s.days, isEmpty);
      expect(
          computePace(scope,
              today: DateTime(2026, 10, 14), week: const WorkWeek()),
          isNull);
    });
  });
}
