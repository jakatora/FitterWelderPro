// Plan badań NDT: wymagane ⌈n·p⌉ w górę, grupy spawacz × linia × metoda,
// spoina z dwoma spawaczami, §341.3.4 z weld_stats, nieprzypisane spoiny,
// otwarte naprawy, gotowość linii, wybór deterministyczny, reguły w JSON.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:cut_list_app/domain/ndt/ndt_plan.dart';
import 'package:cut_list_app/domain/weld_journal/weld_entry.dart';
import 'package:cut_list_app/domain/weld_journal/weld_ndt.dart';
import 'package:cut_list_app/domain/weld_journal/weld_repair.dart';
import 'package:cut_list_app/domain/weld_journal/weld_stats.dart';

import '../../support/weld_fixtures.dart';

const String nb = ' ';

/// Spoina doczołowa (BW) projektu Blok 4.
WeldEntry bw(
  String id, {
  String welder = 'JK-12',
  String line = 'L-12',
  String root = '',
  String cap = '',
  String joint = WeldJointType.butt,
  String material = '316L',
  String status = 'PENDING',
  String project = 'Blok 4',
  Map<NdtMethod, WeldNdt> ndt = const {},
  List<WeldRepair> repairs = const [],
}) =>
    weld(id,
            project: project,
            line: line,
            welder: welder,
            rootWelder: root,
            capWelder: cap,
            material: material,
            status: status,
            ndt: ndt,
            repairs: repairs)
        .copyWith(jointType: joint);

WeldRepair repair(String weldId,
        {Map<NdtMethod, WeldNdt> prevNdt = const {}}) =>
    WeldRepair(
      id: '$weldId-r1',
      weldId: weldId,
      seq: 1,
      date: '2026-10-10',
      reason: 'brak przetopu',
      prevStatus: 'NOK',
      prevNdt: prevNdt,
      byStamp: 'QC',
      createdAt: 1,
    );

NdtRule rule(
  NdtMethod m,
  double pct, {
  List<String> joints = const [WeldJointType.butt],
  bool perWelder = true,
  bool perLine = true,
  String material = '',
  String id = 'r',
}) =>
    NdtRule(
      id: id,
      method: m,
      bp: ndtBpFromPct(pct)!,
      joints: joints,
      material: material,
      perWelder: perWelder,
      perLine: perLine,
    );

final WeldNdt rtSelOk = ndtOf(NdtScope.selected, NdtResult.ok);
final WeldNdt rtSelNok = ndtOf(NdtScope.selected, NdtResult.nok);
final WeldNdt sel = ndtOf(NdtScope.selected);
final WeldNdt addOk = ndtOf(NdtScope.progressive, NdtResult.ok);
final WeldNdt vtOk = ndtOf(NdtScope.required, NdtResult.ok);

List<WeldEntry> many(int n,
        {String prefix = 'w',
        String welder = 'JK-12',
        String line = 'L-12',
        Map<NdtMethod, WeldNdt> ndt = const {}}) =>
    [
      for (var i = 1; i <= n; i++)
        bw('$prefix$i', welder: welder, line: line, ndt: ndt)
    ];

NdtGroup only(NdtPlan p) => p.groups.single;

NdtLine lineOf(NdtPlan p, String line) =>
    p.lines.singleWhere((l) => l.line == line);

void main() {
  group('wymagane = ⌈n · p⌉, zawsze w górę', () {
    test('5 % z 1 / 19 / 20 / 21 spoin = 1 / 1 / 1 / 2', () {
      expect(ndtRequiredCount(1, 500), 1);
      expect(ndtRequiredCount(19, 500), 1);
      expect(ndtRequiredCount(20, 500), 1);
      expect(ndtRequiredCount(21, 500), 2);
      for (final (n, want) in [(1, 1), (19, 1), (20, 1), (21, 2)]) {
        final p = computeNdtPlan(many(n),
            rules: [rule(NdtMethod.rt, 5)]);
        expect(only(p).required, want, reason: '$n spoin');
        expect(only(p).missing, want, reason: '$n spoin');
      }
    });

    test('małe n i ułamki procentów: zawsze w górę, nigdy 0 przy n > 0', () {
      for (var n = 1; n <= 10; n++) {
        expect(ndtRequiredCount(n, 1000), 1, reason: '10 % z $n');
      }
      expect(ndtRequiredCount(11, 1000), 2);
      expect(ndtRequiredCount(7, kNdtFullBp), 7);
      expect(ndtRequiredCount(8, 1250), 1); // 12,5 % z 8 = 1,0
      expect(ndtRequiredCount(9, 1250), 2); // 1,125 → 2
      expect(ndtRequiredCount(3, 3333), 1); // 0,9999 → 1
      expect(ndtRequiredCount(1, 1), 1); // 0,01 % z 1 spoiny
      expect(ndtRequiredCount(0, 500), 0);
      expect(ndtRequiredCount(5, 0), 0);
    });

    test('procent spoza 0–100, NaN i nieskończoność nie tworzą reguły', () {
      expect(ndtBpFromPct(5), 500);
      expect(ndtBpFromPct(12.5), 1250);
      expect(ndtBpFromPct(0), 0);
      expect(ndtBpFromPct(100), kNdtFullBp);
      expect(ndtBpFromPct(-1), isNull);
      expect(ndtBpFromPct(100.01), isNull);
      expect(ndtBpFromPct(double.nan), isNull);
      expect(ndtBpFromPct(double.infinity), isNull);
      expect(ndtBpFromPct(null), isNull);
      // Reguła spoza zakresu podana wprost: pominięta i plan nie jest „gotowy".
      final p = computeNdtPlan([
        bw('a', ndt: {NdtMethod.rt: rtSelOk})
      ], rules: const [
        NdtRule(id: 'x', method: NdtMethod.rt, bp: 15000, joints: ['BW'])
      ]);
      expect(p.rules, isEmpty);
      expect(p.rulesIntact, isFalse);
      expect(lineOf(p, 'L-12').ready, isFalse);
      expect(lineOf(p, 'L-12').blockers.keys,
          containsAll([NdtBlocker.rulesDamaged, NdtBlocker.noRules]));
    });
  });

  group('podział na spawacza i linię', () {
    final welds = [
      ...many(12, prefix: 'j', welder: 'JK-12', line: 'L-12'),
      ...many(3, prefix: 'a', welder: 'AB-03', line: 'L-12'),
      ...many(5, prefix: 'k', welder: 'JK-12', line: 'L-14'),
    ];

    int total(NdtPlan p) => p.groups.fold(0, (s, g) => s + g.required);

    test('spawacz × linia: każda grupa liczona osobno, w górę', () {
      final p = computeNdtPlan(welds, rules: [rule(NdtMethod.rt, 10)]);
      expect([for (final g in p.groups) '${g.line}/${g.welder}=${g.required}'],
          ['L-12/AB-03=1', 'L-12/JK-12=2', 'L-14/JK-12=1']);
      expect(total(p), 4);
    });

    test('tylko spawacz (partia = projekt), tylko linia, bez podziału', () {
      expect(
          total(computeNdtPlan(welds,
              rules: [rule(NdtMethod.rt, 10, perLine: false)])),
          3); // JK-12 17 → 2, AB-03 3 → 1
      expect(
          total(computeNdtPlan(welds,
              rules: [rule(NdtMethod.rt, 10, perWelder: false)])),
          3); // L-12 15 → 2, L-14 5 → 1
      final whole = computeNdtPlan(welds,
          rules: [rule(NdtMethod.rt, 10, perWelder: false, perLine: false)]);
      expect(only(whole).welds, hasLength(20));
      expect(only(whole).required, 2);
      expect(only(whole).line, isNull);
      expect(only(whole).welder, isNull);
    });

    test('linia bez pola „Rura / linia" = numer ISO; projekty się nie łączą',
        () {
      final p = computeNdtPlan([
        bw('i1', line: '').copyWith(isoDrawing: 'ISO-7'),
        bw('i2', line: '').copyWith(isoDrawing: 'iso-7'),
        bw('x1', project: 'Browar'),
      ], rules: [
        rule(NdtMethod.rt, 10)
      ]);
      expect([for (final g in p.groups) '${g.project}|${g.line}|${g.welds.length}'],
          ['Blok 4|ISO-7|2', 'Browar|L-12|1']);
      // Filtr projektu (bez wielkości liter).
      final one = computeNdtPlan(
          [bw('a'), bw('b', project: 'Browar')],
          rules: [rule(NdtMethod.rt, 10)],
          project: 'BLOK 4');
      expect(one.lines.single.project, 'Blok 4');
    });

    test('zakres reguły: rodzaj spoiny i materiał („zawiera")', () {
      final p = computeNdtPlan([
        bw('b1'),
        bw('f1', joint: WeldJointType.fillet),
        bw('s1', joint: WeldJointType.socket, material: 'P235GH'),
        bw('s2', joint: WeldJointType.socket, material: '1.4404 / 316 L'),
      ], rules: [
        rule(NdtMethod.pt, 100,
            joints: [WeldJointType.socket, WeldJointType.fillet],
            material: '316L',
            perWelder: false),
      ]);
      expect([for (final w in only(p).welds) w.id], ['f1', 's2']);
      // b1 (BW) i s1 (P235GH) są poza regułą — informacja, nie blokada.
      expect(lineOf(p, 'L-12').uncovered, 2);
    });
  });

  group('spoina z dwoma spawaczami (grań / lico)', () {
    test('jest w grupie każdego i jej badanie liczy się obu — jak weld_stats',
        () {
      final welds = [
        bw('s1', welder: 'JK-12', cap: 'AB-03', ndt: {NdtMethod.rt: rtSelOk}),
        ...many(9, prefix: 'j', welder: 'JK-12'),
        bw('a1', welder: 'AB-03'),
      ];
      final p = computeNdtPlan(welds, rules: [rule(NdtMethod.rt, 10)]);
      final ab = p.groups.singleWhere((g) => g.welder == 'AB-03');
      final jk = p.groups.singleWhere((g) => g.welder == 'JK-12');
      expect(ab.welds.length, 2); // s1 + a1
      expect(jk.welds.length, 10); // s1 + j1..j9
      expect(ab.examined, 1);
      expect(jk.examined, 1);
      expect(ab.isComplete, isTrue);
      expect(jk.isComplete, isTrue);
      // Ta sama reguła co podsumowanie NDT dziennika: spoina u obu.
      final stats = computeWeldJournalStats(welds).byWelder;
      expect(stats.singleWhere((g) => g.key == 'AB-03').welds, ab.welds.length);
      expect(stats.singleWhere((g) => g.key == 'JK-12').welds, jk.welds.length);
    });

    test('spoina wybrana dla jednego spawacza, wspólna — pokrywa też drugiego',
        () {
      final p = computeNdtPlan([
        bw('s1', welder: 'JK-12', root: 'AB-03'),
        bw('j1'),
        bw('j2'),
        bw('j3'),
      ], rules: [
        rule(NdtMethod.rt, 25)
      ]);
      final ab = p.groups.singleWhere((g) => g.welder == 'AB-03');
      final jk = p.groups.singleWhere((g) => g.welder == 'JK-12');
      expect([for (final w in ab.proposal) w.id], ['s1']);
      expect([for (final w in jk.proposal) w.id], ['s1']);
      // W zleceniu raz.
      expect([for (final i in p.toOrder[NdtMethod.rt]!) i.weld.id], ['s1']);
    });

    test('odrzucenie spoiny wspólnej daje §341.3.4 obu spawaczom', () {
      final p = computeNdtPlan([
        bw('s1',
            welder: 'JK-12',
            cap: 'AB-03',
            ndt: {NdtMethod.rt: rtSelOk},
            repairs: [
              repair('s1', prevNdt: {NdtMethod.rt: rtSelNok})
            ]),
      ], rules: [
        rule(NdtMethod.rt, 10)
      ]);
      expect([for (final g in p.groups) '${g.welder}:${g.progressive}'],
          ['AB-03:2', 'JK-12:2']);
      expect(lineOf(p, 'L-12').progressive, 4);
    });
  });

  group('§341.3.4 — dodatkowe z weld_stats', () {
    test('odrzucona próbka → 2 dodatkowe; „dod." OK zamyka; nie liczą się do %',
        () {
      final base = [
        bw('a', ndt: {NdtMethod.rt: rtSelOk}),
        bw('b',
            ndt: {NdtMethod.rt: rtSelOk},
            repairs: [repair('b', prevNdt: {NdtMethod.rt: rtSelNok})]),
        ...many(9, prefix: 'c'),
      ];
      final p = computeNdtPlan(base, rules: [rule(NdtMethod.rt, 10)]);
      final g = only(p);
      expect(g.required, 2); // 11 spoin
      expect(g.examined, 2);
      expect(g.missing, 0);
      expect(g.progressive, 2);
      expect(
          g.progressive,
          computeWeldJournalStats(base)
              .byWelder
              .single
              .toExamineBy(NdtMethod.rt));
      expect(g.status, NdtGroupStatus.missing);
      final l = lineOf(p, 'L-12');
      expect(l.ready, isFalse);
      expect(l.blockers[NdtBlocker.progressive], 2);
      expect(l.blockers[NdtBlocker.incompleteGroups], 1);

      final done = [
        ...base.take(2),
        bw('c1', ndt: {NdtMethod.rt: addOk}),
        bw('c2', ndt: {NdtMethod.rt: addOk}),
        ...base.skip(4),
      ];
      final p2 = computeNdtPlan(done, rules: [rule(NdtMethod.rt, 10)]);
      expect(only(p2).progressive, 0);
      expect(only(p2).examined, 2); // „dod." nie podnosi podstawy
      expect(only(p2).isComplete, isTrue);
      expect(lineOf(p2, 'L-12').ready, isTrue);
    });

    test('przy regule 100 % badanie „dod." liczy się jak każde', () {
      final p = computeNdtPlan([
        bw('a', ndt: {NdtMethod.rt: addOk}),
        bw('b', ndt: {NdtMethod.rt: ndtOf(NdtScope.required, NdtResult.ok)}),
      ], rules: [
        rule(NdtMethod.rt, 100, perWelder: false)
      ]);
      expect(only(p).examined, 2);
      expect(only(p).isComplete, isTrue);
    });

    test('partia: linia (dodatkowe tylko z tej linii) albo projekt', () {
      final welds = [
        bw('b1',
            line: 'L-12',
            ndt: {NdtMethod.rt: rtSelOk},
            repairs: [repair('b1', prevNdt: {NdtMethod.rt: rtSelNok})]),
        bw('x1', line: 'L-14', ndt: {NdtMethod.rt: addOk}),
        bw('x2', line: 'L-14', ndt: {NdtMethod.rt: addOk}),
      ];
      final perLine = computeNdtPlan(welds, rules: [rule(NdtMethod.rt, 5)]);
      expect(lineOf(perLine, 'L-12').progressive, 2);
      expect(lineOf(perLine, 'L-14').progressive, 0);
      final perProject = computeNdtPlan(welds,
          rules: [rule(NdtMethod.rt, 5, perLine: false)]);
      expect(lineOf(perProject, 'L-12').progressive, 0);
      expect(lineOf(perProject, 'L-14').progressive, 0);
    });

    test('odrzucenie metodą bez reguły też blokuje linię', () {
      final p = computeNdtPlan([
        bw('f1',
            joint: WeldJointType.fillet,
            ndt: {NdtMethod.pt: ndtOf(NdtScope.selected, NdtResult.ok)},
            repairs: [
              repair('f1', prevNdt: {
                NdtMethod.pt: ndtOf(NdtScope.selected, NdtResult.nok)
              })
            ]),
      ], rules: [
        rule(NdtMethod.rt, 10)
      ]);
      final l = lineOf(p, 'L-12');
      expect(l.progressiveByMethod, {NdtMethod.pt: 2});
      expect(l.ready, isFalse);
    });
  });

  group('nieprzypisane i brak danych', () {
    test('spoina bez spawacza: osobna grupa „nieprzypisane", linia niegotowa',
        () {
      final p = computeNdtPlan([
        bw('a', ndt: {NdtMethod.rt: rtSelOk}),
        bw('u', welder: ''),
      ], rules: [
        rule(NdtMethod.rt, 10)
      ]);
      final u = p.groups.singleWhere((g) => g.unassigned);
      expect(u.welder, '');
      expect(u.status, NdtGroupStatus.unassigned);
      expect(u.proposal, isEmpty); // najpierw przypisz spawacza
      expect(p.groups.singleWhere((g) => g.welder == 'JK-12').isComplete,
          isTrue);
      final l = lineOf(p, 'L-12');
      expect(l.ready, isFalse);
      expect(l.blockers[NdtBlocker.unassigned], 1);
      expect(p.issues.single.weld.id, 'u');
      expect(p.issues.single.issues, [NdtWeldIssue.noWelder]);
    });

    test('bez rodzaju spoiny: blokuje, gdy reguła rodzaj rozróżnia', () {
      final welds = [
        bw('a', ndt: {NdtMethod.rt: rtSelOk, NdtMethod.vt: vtOk}),
        bw('n', joint: '', ndt: {NdtMethod.vt: vtOk}),
      ];
      final p = computeNdtPlan(welds, rules: [rule(NdtMethod.rt, 10)]);
      expect(lineOf(p, 'L-12').blockers[NdtBlocker.noJointType], 1);
      expect(only(p).welds.map((w) => w.id), ['a']);
      // VT 100 % wszystkich rodzajów: rodzaj nie ma znaczenia.
      final vt = computeNdtPlan(welds,
          rules: [
            rule(NdtMethod.vt, 100,
                joints: WeldJointType.values, perWelder: false)
          ]);
      expect(lineOf(vt, 'L-12').ready, isTrue);
    });

    test('bez materiału przy regule z materiałem; bez linii i ISO', () {
      final p = computeNdtPlan([
        bw('m', material: ''),
        bw('n', line: ''),
      ], rules: [
        rule(NdtMethod.rt, 100, material: '316', perWelder: false)
      ]);
      expect(p.issues.map((i) => '${i.weld.id}:${i.issues}'), [
        'm:[NdtWeldIssue.noMaterial]',
        'n:[NdtWeldIssue.noLine]',
      ]);
      expect(lineOf(p, '').blockers.keys, contains(NdtBlocker.noLine));
      expect(lineOf(p, 'L-12').blockers.keys, contains(NdtBlocker.noMaterial));
    });

    test('brak reguł i uszkodzone reguły — żadna linia nie jest gotowa', () {
      final welds = [bw('a', ndt: {NdtMethod.rt: rtSelOk})];
      final none = computeNdtPlan(welds, rules: const []);
      expect(lineOf(none, 'L-12').blockers.keys, [NdtBlocker.noRules]);
      final damaged = computeNdtPlan(welds,
          rules: [rule(NdtMethod.rt, 5)], rulesIntact: false);
      expect(lineOf(damaged, 'L-12').blockers.keys, [NdtBlocker.rulesDamaged]);
      final ok = computeNdtPlan(welds, rules: [rule(NdtMethod.rt, 5)]);
      expect(lineOf(ok, 'L-12').ready, isTrue);
    });
  });

  group('naprawy i wyniki blokują gotowość', () {
    final rules = [rule(NdtMethod.rt, 10)];

    test('odrzucona bez naprawy → „naprawy otwarte", linia niegotowa', () {
      final p = computeNdtPlan([
        bw('a', ndt: {NdtMethod.rt: rtSelNok}),
        ...many(3, prefix: 'c'),
      ], rules: rules);
      expect(only(p).examined, 1); // próbka pobrana
      expect(only(p).status, NdtGroupStatus.repairsOpen);
      final l = lineOf(p, 'L-12');
      expect(l.blockers[NdtBlocker.openDefects], 1);
      expect(l.ready, isFalse);
    });

    test('naprawiona, czeka na ponowne badanie → zlecona, nie zbadana', () {
      final p = computeNdtPlan([
        bw('a',
            ndt: {NdtMethod.rt: sel},
            repairs: [repair('a', prevNdt: {NdtMethod.rt: rtSelNok})]),
        ...many(3, prefix: 'c'),
      ], rules: rules);
      final g = only(p);
      expect(g.examined, 0);
      expect(g.ordered.map((w) => w.id), ['a']);
      expect(g.toOrder, 0);
      expect(g.status, NdtGroupStatus.repairsOpen);
      expect(lineOf(p, 'L-12').blockers[NdtBlocker.repairsAwaiting], 1);
    });

    test('status NOK bez badań też jest otwartą wadą', () {
      final p = computeNdtPlan([
        bw('a', status: 'NOK', ndt: {NdtMethod.rt: rtSelOk})
      ], rules: rules);
      expect(lineOf(p, 'L-12').blockers[NdtBlocker.openDefects], 1);
    });

    test('zlecone ponad wymagane, bez wyniku → czeka na wynik', () {
      final p = computeNdtPlan([
        bw('a', ndt: {NdtMethod.rt: rtSelOk}),
        bw('b', ndt: {NdtMethod.rt: sel}),
      ], rules: rules);
      expect(only(p).missing, 0);
      expect(only(p).status, NdtGroupStatus.awaiting);
      expect(lineOf(p, 'L-12').blockers[NdtBlocker.awaitingResults], 1);
    });

    test('VT 100 %: każda spoina VT OK, inaczej brakuje', () {
      final rules = [
        rule(NdtMethod.vt, 100, joints: WeldJointType.values, perWelder: false)
      ];
      final p = computeNdtPlan([
        bw('a', ndt: {NdtMethod.vt: vtOk}),
        bw('b'),
      ], rules: rules);
      expect(lineOf(p, 'L-12').missing, 1);
      expect(lineOf(p, 'L-12').ready, isFalse);
      final ok = computeNdtPlan([
        bw('a', ndt: {NdtMethod.vt: vtOk}),
        bw('b', ndt: {NdtMethod.vt: vtOk}),
      ], rules: rules);
      expect(lineOf(ok, 'L-12').ready, isTrue);
    });

    test('gotowa linia: liczby obok werdyktu się z nim zgadzają', () {
      final p = computeNdtPlan([
        bw('a', ndt: {NdtMethod.rt: rtSelOk, NdtMethod.vt: vtOk}),
        for (var i = 1; i <= 9; i++)
          bw('c$i', ndt: {NdtMethod.vt: vtOk}),
        bw('s', joint: WeldJointType.socket, ndt: {NdtMethod.vt: vtOk}),
      ], rules: [
        rule(NdtMethod.rt, 10, id: 'rt'),
        rule(NdtMethod.vt, 100,
            joints: WeldJointType.values, perWelder: false, id: 'vt'),
      ]);
      final l = lineOf(p, 'L-12');
      expect(l.ready, isTrue);
      expect(l.blockers, isEmpty);
      expect(l.completeGroups, l.groups.length);
      expect(l.missing, 0);
      expect(ndtVerdictText(l, en: false), 'Gotowa do próby ciśnieniowej');
      expect(ndtLineNumbers(l, en: false),
          '11 spoin · grupy kompletne 2/2 · brakuje 0');
    });
  });

  group('wybór deterministyczny i stabilny', () {
    test('FNV-1a: znane wartości (ten sam wynik na każdej platformie)', () {
      expect(ndtSeedHash(''), 0x811C9DC5);
      expect(ndtSeedHash('a'), 0xE40C292C);
      expect(ndtSeedHash('foobar'), 0xBF9CF968);
    });

    List<String> picks(List<WeldEntry> welds, {int round = 0, double pct = 10}) =>
        [
          for (final w in computeNdtPlan(welds,
                  rules: [rule(NdtMethod.rt, pct)], round: round)
              .groups
              .single
              .proposal)
            w.id
        ];

    test('te same dane = ta sama lista, niezależnie od kolejności wpisów', () {
      final welds = many(30);
      final a = picks(welds);
      expect(a, hasLength(3));
      expect(picks(welds), a);
      expect(picks(welds.reversed.toList()), a);
    });

    test('nowa spoina nie wyrzuca wcześniej wybranych', () {
      final welds = many(30);
      final before = picks(welds);
      final after = picks([...welds, bw('w31')]); // 31 → 4
      expect(after, hasLength(4));
      expect(after, containsAll(before));
    });

    test('„losuj ponownie" zmienia listę, powrót do rundy 0 ją przywraca', () {
      final welds = many(30);
      final r0 = picks(welds);
      final r1 = picks(welds, round: 1);
      expect(r1, hasLength(3));
      expect(r1, isNot(equals(r0)));
      expect(picks(welds, round: 0), r0);
    });

    test('preferencja: najpierw spoiny nie badane innymi metodami', () {
      final welds = [
        for (var i = 1; i <= 9; i++)
          bw('u$i', ndt: {NdtMethod.ut: ndtOf(NdtScope.selected, NdtResult.ok)}),
        bw('clean'),
      ];
      expect(picks(welds), ['clean']);
    });

    test('zlecone bez wyniku liczą się do wymaganych — nie zlecamy podwójnie',
        () {
      final welds = [bw('a', ndt: {NdtMethod.rt: sel}), ...many(19)];
      final g = computeNdtPlan(welds, rules: [rule(NdtMethod.rt, 10)])
          .groups
          .single;
      expect(g.required, 2);
      expect(g.ordered.map((w) => w.id), ['a']);
      expect(g.toOrder, 1);
      expect(g.proposal, hasLength(1));
      expect(g.proposal.single.id, isNot('a'));
    });
  });

  group('reguły w JSON', () {
    test('zapis i odczyt bez strat; presety', () {
      final set = NdtRuleSet(rules: [
        rule(NdtMethod.rt, 12.5, id: 'a'),
        rule(NdtMethod.pt, 10,
            joints: [WeldJointType.socket, WeldJointType.fillet],
            material: '316L',
            perLine: false,
            id: 'b'),
      ]);
      final d = decodeNdtRuleSet(set.encode());
      expect(d.intact, isTrue);
      expect(d.saved, isTrue);
      expect(d.set, set);
      // Rodzaje w stałej kolejności, bez powtórzeń.
      final j = decodeNdtRuleSet(jsonEncode({
        'v': 1,
        'rules': [
          {
            'id': 'a',
            'method': 'PT',
            'pct': 10,
            'joints': ['SW', 'FW', 'SW']
          }
        ],
      }));
      expect(j.set.rules.single.joints, ['SW', 'FW']);

      final b313 = NdtRuleSet.fromPreset(NdtPreset.b313);
      expect(b313.rules.map((r) => ndtRuleShort(r, en: false)),
          ['RT 5$nb% BW', 'VT 100$nb%']);
      // RT: każdy spawacz, partia = projekt (§341.4.1(b)(1)); VT 100 %
      // ukończonych spoin (§341.4.1(a)(3), wydania 2020 i 2024).
      expect(b313.rules.first.perWelder && !b313.rules.first.perLine, isTrue);
      expect(b313.rules.last.isFull && b313.rules.last.coversAllJoints, isTrue);
      expect(decodeNdtRuleSet(b313.encode()).set, b313);
      expect(NdtRuleSet.fromPreset(NdtPreset.rt100).rules.single.isFull,
          isTrue);
      expect(NdtRuleSet.fromPreset(NdtPreset.custom).rules, isEmpty);
      expect(ndtPresetNote(NdtPreset.b313, en: false), contains('§341.4.1'));
    });

    test('brak zapisu ≠ uszkodzenie', () {
      expect(decodeNdtRuleSet(null).saved, isFalse);
      expect(decodeNdtRuleSet(null).intact, isTrue);
      expect(decodeNdtRuleSet('  ').saved, isFalse);
    });

    test('uszkodzony JSON, zła wersja, reguły złego typu → nienaruszony = nie',
        () {
      for (final raw in [
        '{"v":1,"rules":[',
        '[]',
        '{"v":2,"rules":[]}',
        '{"v":1,"rules":"x"}',
      ]) {
        final d = decodeNdtRuleSet(raw);
        expect(d.intact, isFalse, reason: raw);
        expect(d.set.rules, isEmpty, reason: raw);
      }
      Map<String, Object?> r(Map<String, Object?> patch) => {
            'id': 'a',
            'method': 'RT',
            'pct': 10,
            'joints': ['BW'],
            ...patch,
          };
      final bad = [
        r({'pct': 150}),
        r({'pct': -1}),
        r({'pct': 'NaN'}),
        r({'pct': null}),
        r({'joints': []}),
        r({'joints': ['XX']}),
        r({'method': 'XR'}),
        r({'perWelder': 'tak'}),
        r({'id': ''}),
      ];
      for (final x in bad) {
        final d = decodeNdtRuleSet(jsonEncode({
          'v': 1,
          'rules': [x, r({'id': 'ok'})],
        }));
        expect(d.intact, isFalse, reason: '$x');
        expect(d.dropped, 1, reason: '$x');
        expect(d.set.rules.single.id, 'ok', reason: '$x');
      }
      // Brak flag podziału = podział (bezpieczniej).
      final d = decodeNdtRuleSet(jsonEncode({
        'v': 1,
        'rules': [
          {'id': 'a', 'method': 'ut', 'pct': 5, 'joints': ['BW']}
        ],
      }));
      expect(d.intact, isTrue);
      expect(d.set.rules.single.perWelder, isTrue);
      expect(d.set.rules.single.perLine, isTrue);
      expect(d.set.rules.single.method, NdtMethod.ut);
    });
  });

  group('poprawki z przeglądu', () {
    test('N1: linia z samymi FW przy regule BW → niegotowa (spoiny poza regułami)',
        () {
      final welds = [
        bw('f1', line: 'L-7', joint: WeldJointType.fillet),
        bw('s1', line: 'L-7', joint: WeldJointType.socket),
      ];
      final p = computeNdtPlan(welds, rules: [rule(NdtMethod.rt, 10)]);
      final l = lineOf(p, 'L-7');
      expect(l.groups, isEmpty);
      expect(l.ready, isFalse);
      expect(l.blockers, {NdtBlocker.uncovered: 2});
      expect(ndtBlockerText(NdtBlocker.uncovered, l, en: false),
          contains('dodaj regułę dla tych spoin (także 0 %'));
      expect(p.issues.map((i) => i.issues),
          everyElement([NdtWeldIssue.uncovered]));
    });

    test('N1: reguła 0 % to świadome „nie wymagam" — pokrywa spoiny', () {
      final p = computeNdtPlan([
        bw('f1', line: 'L-7', joint: WeldJointType.fillet),
        bw('s1', line: 'L-7', joint: WeldJointType.socket),
      ], rules: [
        rule(NdtMethod.rt, 10, id: 'rt'),
        rule(NdtMethod.pt, 0,
            joints: [WeldJointType.fillet, WeldJointType.socket],
            perWelder: false,
            id: 'pt0'),
      ]);
      final l = lineOf(p, 'L-7');
      expect(l.uncovered, 0);
      expect(l.ready, isTrue);
      expect(only(p).required, 0);
    });

    test('N2: bieżące NOK bez zakresu blokuje, dopóki zakres nie jest ustawiony',
        () {
      final p = computeNdtPlan([
        bw('a', ndt: {NdtMethod.rt: ndtOf(NdtScope.none, NdtResult.nok)}),
      ], rules: [
        rule(NdtMethod.rt, 10)
      ]);
      final l = lineOf(p, 'L-12');
      expect(l.blockers[NdtBlocker.unclassifiedRejects], 1);
      expect(p.issues.single.issues, [NdtWeldIssue.unclassifiedReject]);
    });

    test('N2: NOK bez zakresu sprzed naprawy liczy się jak losowe — 2 dodatkowe',
        () {
      final base = [
        bw('b',
            ndt: {NdtMethod.rt: rtSelOk},
            repairs: [
              repair('b', prevNdt: {
                NdtMethod.rt: ndtOf(NdtScope.none, NdtResult.nok)
              })
            ]),
        ...many(9, prefix: 'c'),
      ];
      // weld_stats nie liczy go do §341.3.4 („nie wiadomo")…
      expect(computeWeldJournalStats(base).byWelder.single.toExamine, 0);
      // …a plan przyjmuje wersję bezpieczniejszą.
      final p = computeNdtPlan(base, rules: [rule(NdtMethod.rt, 10)]);
      final l = lineOf(p, 'L-12');
      expect(only(p).progressive, 2);
      expect(l.blockers[NdtBlocker.progressive], 2);
      expect(l.blockers.containsKey(NdtBlocker.unclassifiedRejects), isFalse);
      expect(l.assumedRandomRejects, 1);
      expect(ndtLineNotes(l, en: false).single,
          contains('przyjęte jako losowe (2 dodatkowe'));

      // Dwa „dod." OK zamykają — linia gotowa, uwaga zostaje.
      final done = computeNdtPlan([
        base.first,
        bw('c1', ndt: {NdtMethod.rt: addOk}),
        bw('c2', ndt: {NdtMethod.rt: addOk}),
        ...base.skip(3),
      ], rules: [
        rule(NdtMethod.rt, 10)
      ]);
      expect(lineOf(done, 'L-12').ready, isTrue);
      expect(lineOf(done, 'L-12').assumedRandomRejects, 1);
    });

    test('N2: przy regule 100 % tej metody NOK bez zakresu = wymagane, bez §341.3.4',
        () {
      final p = computeNdtPlan([
        bw('v',
            ndt: {NdtMethod.vt: vtOk},
            repairs: [
              repair('v', prevNdt: {
                NdtMethod.vt: ndtOf(NdtScope.none, NdtResult.nok)
              })
            ]),
      ], rules: [
        rule(NdtMethod.vt, 100,
            joints: WeldJointType.values, perWelder: false)
      ]);
      final l = lineOf(p, 'L-12');
      expect(l.progressive, 0);
      expect(l.assumedRequiredRejects, 1);
      expect(l.ready, isTrue);
    });

    test('N3: sam numer raportu bez wyniku nie wyklucza spoiny z propozycji', () {
      final p = computeNdtPlan([
        bw('w4', ndt: {NdtMethod.vt: vtOk}),
        bw('w5', ndt: {NdtMethod.vt: const WeldNdt(reportNo: 'VT-17')}),
      ], rules: [
        rule(NdtMethod.vt, 100, joints: WeldJointType.values, perWelder: false)
      ]);
      expect(only(p).missing, 1);
      expect(p.toOrder[NdtMethod.vt]!.single.weld.id, 'w5');
      expect(p.shortfalls, isEmpty);
    });

    test('N3: brakuje, a nie ma kandydatów → ostrzeżenie z numerami spoin', () {
      final p = computeNdtPlan([
        bw('w1', ndt: {NdtMethod.rt: addOk}),
        bw('w2', ndt: {NdtMethod.rt: ndtOf(NdtScope.progressive)}),
      ], rules: [
        rule(NdtMethod.rt, 50)
      ]);
      final g = only(p);
      expect(g.missing, 1);
      expect(g.proposal, isEmpty);
      expect(g.shortfall, 1);
      expect(g.stuck.map((w) => w.id), ['w1', 'w2']);
      expect(p.shortfalls, [g]);
      expect(ndtShortfallText(g, en: false),
          'RT 50$nb% BW · L-12 · JK-12: brakuje 1, a nie ma spoin do wybrania '
          '— blokują: w1, w2 (zakres „dod." nie liczy się do %; zmień zakres '
          'w dzienniku)');
      expect(lineOf(p, 'L-12').missing, 1);
    });

    test('N4: braki linii raz na badanie — spoina wspólna i dwie reguły tej '
        'samej metody', () {
      final shared = computeNdtPlan([
        bw('s1', welder: 'JK-12', root: 'AB-03'),
        bw('j1'),
        bw('j2'),
        bw('j3'),
      ], rules: [
        rule(NdtMethod.rt, 25)
      ]);
      expect(shared.groups.fold<int>(0, (s, g) => s + g.missing), 2);
      expect(lineOf(shared, 'L-12').missing, 1);
      expect(shared.toOrderCount, 1);

      final twoRules = computeNdtPlan(many(10), rules: [
        rule(NdtMethod.rt, 10, id: 'a'),
        rule(NdtMethod.rt, 10, perWelder: false, id: 'b'),
      ]);
      expect(twoRules.groups.map((g) => g.missing), [1, 1]);
      expect(lineOf(twoRules, 'L-12').missing, 1);
      expect(twoRules.toOrderCount, 1);
    });

    test('N7: procent zawsze w górę do 0,01 % — dodatni nigdy nie daje 0 %', () {
      expect(ndtBpFromPct(0.004), 1);
      expect(ndtBpFromPct(5.004), 501);
      expect(ndtBpFromPct(0.07), 7);
      expect(ndtBpFromPct(0.29), 29);
      expect(ndtBpFromPct(12.5), 1250);
      expect(ndtBpFromPct(99.999), kNdtFullBp);
      final d = decodeNdtRuleSet(jsonEncode({
        'v': 1,
        'rules': [
          {'id': 'a', 'method': 'RT', 'pct': 0.004, 'joints': ['BW']}
        ],
      }));
      expect(d.set.rules.single.bp, 1);
      expect(d.set.rules.single.requiredFor(1), 1);
    });

    test('N6: tekst ma uwagi linii, brak danych, braki bez kandydatów i powód '
        'zleconych', () {
      final plan = computeNdtPlan([
        bw('a', ndt: {NdtMethod.rt: sel}),
        ...many(9, prefix: 'c'),
        bw('r',
            line: 'L-14',
            ndt: {NdtMethod.rt: sel},
            repairs: [
              repair('r', prevNdt: {
                NdtMethod.rt: ndtOf(NdtScope.none, NdtResult.nok)
              })
            ]),
        bw('f', line: 'L-14', joint: WeldJointType.fillet),
        bw('x1', line: 'L-16', ndt: {NdtMethod.rt: addOk}),
      ], rules: [
        rule(NdtMethod.rt, 10)
      ]);
      final text = buildNdtOrderText(
          NdtOrderReport(
              project: 'Blok 4',
              plan: plan,
              generatedAt: DateTime(2026, 10, 17)),
          en: false);
      expect(text,
          contains('• RT: a · L-12 · JK-12 · BW (zlecone, bez wyniku · '
              'losowo 10$nb% · JK-12 · L-12)'));
      expect(text,
          contains('• RT: r · L-14 · JK-12 · BW (ponowne badanie po naprawie '
              'R1 · losowo 10$nb% · JK-12 · L-14)'));
      expect(text, contains('  – Odrzucenia sprzed naprawy bez zakresu badania: 1'));
      expect(text, contains('Brak danych (uzupełnij w dzienniku spoin):'));
      expect(text, contains('• f · L-14 · JK-12 · FW — poza regułami'));
      expect(text, contains('• RT 10$nb% BW · L-16 · JK-12: brakuje 1, a nie ma '
          'spoin do wybrania — blokują: x1'));
      expect(text, contains('Spoiny poza regułami: 1'));
    });
  });

  test('teksty: zlecenie tekstem z listą, dodatkowymi i gotowością', () {
    final welds = [
      ...many(10),
      bw('n',
          line: 'L-14',
          ndt: {NdtMethod.rt: rtSelOk},
          repairs: [repair('n', prevNdt: {NdtMethod.rt: rtSelNok})]),
    ];
    final plan = computeNdtPlan(welds,
        rules: [rule(NdtMethod.rt, 10)], project: 'Blok 4');
    final report = NdtOrderReport(
        project: 'Blok 4',
        plan: plan,
        generatedAt: DateTime(2026, 10, 17, 9, 5));
    final text = buildNdtOrderText(report, en: false);
    final pick = plan.toOrder[NdtMethod.rt]!.single.weld;
    expect(text, startsWith('ZLECENIE BADAŃ NDT — Blok 4\n2026-10-17\n'));
    expect(text,
        contains('• RT 10$nb% · BW · każdy spawacz osobno · każda linia osobno'));
    expect(text, contains('RT — do zlecenia: 1 spoina'));
    expect(text,
        contains('• ${pick.weldNo} · L-12 · JK-12 · BW (losowo 10$nb% · JK-12 · L-12)'));
    expect(text, contains('• RT 10$nb% BW · L-14 · JK-12: 2'));
    expect(text, contains('Gotowe do próby ciśnieniowej: 0 z 2 linii'));
    expect(report.fileName(en: false), 'zlecenie-ndt-Blok-4-2026-10-17.pdf');
    final en = buildNdtOrderText(report, en: true);
    expect(en, contains('RT — to order: 1 weld'));
    expect(en, contains('Ready for the pressure test: 0 of 2 lines'));
    expect(ndtPctText(1250, en: false), '12,5$nb%');
    expect(ndtPctText(1250, en: true), '12.5$nb%');
    expect(ndtPctText(505, en: false), '5,05$nb%');
  });
}
