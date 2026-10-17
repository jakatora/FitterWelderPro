// Akord z dziennika spoin: DI z tabeli NPS (ta sama reguła co „Postęp
// robót"), dopłaty sumowane od podstawy, potrącenia i naprawy, tryb za
// spoinę, okresy i granice dni, spoiny bez wymiaru pominięte, grosze
// i zaokrąglenia, JSON stawek (także uszkodzony), tekst do wysłania.

import 'package:flutter_test/flutter_test.dart';

import 'package:cut_list_app/domain/piecework/piecework.dart';
import 'package:cut_list_app/domain/progress/progress_filter.dart'
    show DayRange;
import 'package:cut_list_app/domain/quotes/quote_calculator.dart' show formatPln;
import 'package:cut_list_app/domain/weld_journal/weld_entry.dart';
import 'package:cut_list_app/domain/weld_journal/weld_ndt.dart';
import 'package:cut_list_app/domain/weld_journal/weld_repair.dart';

import '../../support/weld_fixtures.dart';

const String nb = ' ';

/// Cały październik 2026.
final DayRange october = DayRange(DateTime(2026, 10, 1), DateTime(2026, 10, 31));

const PieceworkRates di45 = PieceworkRates(rateGrosze: 4500);

WeldRepair repair(String weldId, int seq) => WeldRepair(
      id: '$weldId-r$seq',
      weldId: weldId,
      seq: seq,
      date: '2026-10-15',
      reason: 'porowatość',
      prevStatus: 'NOK',
      prevNdt: const {},
      byStamp: 'JK-12',
      createdAt: 0,
    );

/// Spoina z października (fixture ma wrzesień).
WeldEntry oct(String id, {String material = '316L'}) =>
    weld(id, date: '2026-10-14', material: material);

/// Spoina węglowa bez pozycji — bez żadnych dopłat.
WeldEntry cs(String id,
        {String od = '60.3',
        String date = '2026-10-14',
        String welder = 'JK-12',
        String rootWelder = '',
        String t = '3.91'}) =>
    weld(id,
            date: date,
            welder: welder,
            rootWelder: rootWelder,
            material: 'P235GH')
        .copyWith(od: od, t: t);

PieceworkResult run(List<WeldEntry> welds,
        {PieceworkRates rates = di45,
        DayRange? range,
        String? welder = 'JK-12'}) =>
    computePiecework(
        entries: welds, rates: rates, range: range ?? october, welder: welder);

void main() {
  group('DI', () {
    test('DI ze znanych wymiarów: 2" = 2, 4" = 4, ½" = 0,5, 6" (przecinek) = 6',
        () {
      final r = run([
        cs('a', od: '60.3'),
        cs('b', od: '114.3'),
        cs('c', od: '21.3'),
        cs('d', od: '168,3'),
      ]);
      expect(r.welds, 4);
      expect(r.di, 12.5);
      expect([for (final l in r.lines) l.baseGrosze], [9000, 18000, 2250, 27000]);
      expect(r.totalGrosze, 56250);
      expect(formatPln(r.totalGrosze), '562,50${nb}zł');
      expect(r.approxWelds, 0);
    });

    test('„≈" przy przybliżonym DI: jeden helper dla ekranu, tekstu i PDF', () {
      final approx = run([cs('a', od: '57'), cs('b')]);
      expect(pieceworkDiText(approx, en: false), '≈ 4,24 DI');
      expect(pieceworkDiText(approx, en: true), '≈ 4.24 DI');
      expect(pieceworkDiText(run([cs('b')]), en: false), '2 DI');
      expect(diNumberText(57 / 25.4, en: false, approx: true), '≈ 2,24');
      final text = buildPieceworkText(
          PieceworkReport(result: approx, generatedAt: DateTime(2026, 10, 17)),
          en: false);
      expect(text, contains('Spoiny: 2 spoiny · ≈ 4,24 DI'));
    });

    test('OD spoza tabeli: DI = OD / 25,4, oznaczone ≈ i wliczone', () {
      final r = run([cs('a', od: '57')]);
      expect(r.lines.single.diApprox, isTrue);
      expect(r.lines.single.weldDi, closeTo(57 / 25.4, 1e-12));
      // 2,2441 DI × 4500 gr = 10 098,43 → 10 098 gr.
      expect(r.totalGrosze, 10098);
      expect(pieceworkNotes(r, en: false).first, startsWith('≈ 1 spoina'));
      expect(pieceworkRows(r, en: false).first.label,
          'Podstawa: ≈ 2,24 DI × 45,00${nb}zł/DI');
    });
  });

  group('dopłaty', () {
    const rates = PieceworkRates(
      rateGrosze: 4500,
      stainlessBp: 2000,
      otherMaterialBp: 3000,
      pos2gBp: 500,
      pos5gBp: 1000,
      pos6gBp: 2000,
      wallRule: WallRule.sch80,
      wallBp: 1500,
    );

    test('dopłaty sumują się od podstawy: nierdzewka, pozycja, Sch 80+', () {
      final r = run([
        // 316L 2" Sch 80S (5,54), 6G: 9000 + 20% + 20% + 15%.
        oct('w1', material: '316L').copyWith(t: '5.54', position: '6G'),
        // P235GH 2" Sch 40, PH = 5G: 9000 + 10%.
        cs('w2').copyWith(position: 'PH'),
        // P91 4" Sch 80 (8,56), PC = 2G: 18000 + 30% + 5% + 15%.
        oct('w3', material: 'A335 P91')
            .copyWith(od: '114.3', t: '8.56', position: 'PC'),
      ], rates: rates);
      final v = [for (final l in r.lines) l.valueGrosze];
      expect(v, [13950, 9900, 27000]);
      // Mnożone dałyby 9000 × 1,2 × 1,2 × 1,15 = 14 904 — nie mnożymy.
      expect(r.lines.first.materialGrosze, 1800);
      expect(r.lines.first.positionGrosze, 1800);
      expect(r.lines.first.wallGrosze, 1350);
      expect(r.totalGrosze, 50850);
      final rows = {for (final x in pieceworkRows(r, en: false)) x.id: x};
      expect(rows['stainless']!.grosze, 1800);
      expect(rows['other']!.grosze, 5400);
      expect(rows['p2g']!.grosze, 900);
      expect(rows['p5g']!.grosze, 900);
      expect(rows['p6g']!.grosze, 1800);
      expect(rows['wall']!.grosze, 1350 + 2700);
      expect(rows['wall']!.label,
          'Dopłata: gruba ścianka (≥ Sch 80) +15% (2 spoiny)');
      expect(pieceworkRows(r, en: false).fold<int>(0, (s, x) => s + x.grosze),
          r.totalGrosze);
    });

    test('materiał: nierdzewna, węglowa, inne, nierozpoznany', () {
      for (final m in [
        '316L', '1.4404', 'TP304L', 'A312 TP316L', 'X5CrNi18-10', //
        'duplex 2205', 'Stal nierdzewna', 'F316', '1.4571',
      ]) {
        expect(pieceworkMaterialOf(m), PieceworkMaterial.stainless, reason: m);
      }
      for (final m in [
        'P235GH', 'A106 Gr.B', '1.0345', 'S355J2', 'L360NE', 'API 5L X52', //
        'stal węglowa', 'A333 Gr.6',
      ]) {
        expect(pieceworkMaterialOf(m), PieceworkMaterial.carbon, reason: m);
      }
      for (final m in [
        'P91', 'A335 P11', '13CrMo4-5', '10CrMo9-10', '1.4903', '1.7335', //
        'Inconel 625', '2.4856', 'CuNi 90/10',
      ]) {
        expect(pieceworkMaterialOf(m), PieceworkMaterial.other, reason: m);
      }
      for (final m in ['', '  ', '16Mo3', 'xyz']) {
        expect(pieceworkMaterialOf(m), PieceworkMaterial.unknown, reason: m);
      }
    });

    test('pozycje: PF/PH = 5G, H-L045 = 6G, PC = 2G, 1G bez dopłaty', () {
      expect(payPositionOf('1G'), PayPosition.p1g);
      expect(payPositionOf('PA'), PayPosition.p1g);
      expect(payPositionOf('2G'), PayPosition.p2g);
      expect(payPositionOf('PC'), PayPosition.p2g);
      for (final p in ['5G', 'PF', 'PG', 'PH', 'pj']) {
        expect(payPositionOf(p), PayPosition.p5g, reason: p);
      }
      for (final p in ['6G', '6GR', 'H-L045', 'J-L045']) {
        expect(payPositionOf(p), PayPosition.p6g, reason: p);
      }
      expect(payPositionOf(''), PayPosition.none);
      expect(payPositionOf('PB'), PayPosition.other);
      expect(payPositionOf('2F'), PayPosition.other);
    });

    test('nierozpoznany materiał i pozycja bez dopłaty — policzone w uwagach',
        () {
      final r = run([
        oct('a', material: '').copyWith(position: 'PB'),
        oct('b', material: '316L').copyWith(position: '5G'),
      ], rates: rates.copyWith(wallRule: WallRule.none));
      expect(r.lines.first.valueGrosze, 9000);
      final notes = pieceworkNotes(r, en: false);
      expect(notes, contains(startsWith('1 spoina: materiał pusty')));
      expect(notes, contains(startsWith('1 spoina: bez pozycji')));
    });

    test('grubość: próg w mm, Sch 80 z OD (nierdzewna 80S), brak t → bez dopłaty',
        () {
      bool? thick(WeldEntry e, WallRule rule, [double mm = 10]) =>
          pieceworkThickWall(e, rule: rule, wallMm: mm);
      final base = cs('x');
      expect(thick(base.copyWith(t: '10'), WallRule.mm), isTrue);
      expect(thick(base.copyWith(t: '9,9'), WallRule.mm), isFalse);
      expect(thick(base.copyWith(t: ''), WallRule.mm), isNull);
      expect(thick(base.copyWith(t: '5.54'), WallRule.sch80), isTrue);
      expect(thick(base.copyWith(t: '5.5'), WallRule.sch80), isFalse);
      expect(thick(base.copyWith(od: '57', t: '9'), WallRule.sch80), isNull);
      // 12": Sch 80 = 17,48 mm, ale nierdzewna 80S = 12,70 mm.
      final big = base.copyWith(od: '323.9', t: '13');
      expect(thick(big, WallRule.sch80), isFalse);
      expect(thick(big.copyWith(material: '316L'), WallRule.sch80), isTrue);

      final r = run([base.copyWith(t: '')],
          rates: const PieceworkRates(
              rateGrosze: 4500, wallRule: WallRule.mm, wallBp: 1000));
      expect(r.totalGrosze, 9000);
      expect(r.unknownWalls, 1);
      expect(pieceworkNotes(r, en: false),
          contains('1 spoina: brak grubości ścianki — bez dopłaty za grubość.'));
    });
  });

  group('naprawy', () {
    test('potrącenie za odrzuconą spoinę i naprawa płatna osobno za każdą R',
        () {
      final welds = [
        cs('w1').copyWith(repairs: [repair('w1', 1), repair('w1', 2)]),
        cs('w2'),
      ];
      final r = run(welds,
          rates: const PieceworkRates(
              rateGrosze: 4500,
              rejectBp: 5000,
              repairPaid: true,
              repairBp: 5000));
      final w1 = r.lines.first;
      expect(w1.rejected, isTrue);
      expect(w1.repairs, 2);
      expect(w1.deductionGrosze, 4500);
      expect(w1.repairPayGrosze, 9000);
      expect(w1.netGrosze, 13500);
      expect(r.totalGrosze, 22500);
      final rows = {for (final x in pieceworkRows(r, en: false)) x.id: x};
      expect(rows['reject']!.grosze, -4500);
      expect(rows['reject']!.label,
          'Potrącenie: odrzucone spoiny −50% (1 spoina)');
      expect(rows['repair']!.grosze, 9000);
      expect(rows['repair']!.label, 'Naprawy płatne osobno: 2 naprawy × 50%');

      // 100% = spoina za 0 zł; naprawa niepłatna.
      final zero = run(welds,
          rates: const PieceworkRates(rateGrosze: 4500, rejectBp: 10000));
      expect(zero.lines.first.netGrosze, 0);
      expect(zero.totalGrosze, 9000);
    });

    test('odrzucona = naprawa R1+, status NOK albo wynik NOK badania', () {
      expect(pieceworkRejected(cs('a').copyWith(repairs: [repair('a', 1)])),
          isTrue);
      expect(pieceworkRejected(cs('a').copyWith(status: 'NOK')), isTrue);
      expect(
          pieceworkRejected(cs('a').copyWith(ndt: {
            NdtMethod.pt: ndtOf(NdtScope.selected, NdtResult.nok),
          })),
          isTrue);
      expect(
          pieceworkRejected(cs('a').copyWith(status: 'OK', ndt: {
            NdtMethod.rt: ndtOf(NdtScope.selected, NdtResult.ok),
          })),
          isFalse);
      expect(pieceworkRejected(cs('a')), isFalse);
    });
  });

  group('tryb i spawacz', () {
    test('tryb za spoinę: stawka za sztukę, spoina bez OD liczona', () {
      final r = run([cs('a'), cs('b', od: ''), cs('c', od: '114.3')],
          rates: const PieceworkRates(
              mode: PieceworkMode.weld, rateGrosze: 15000));
      expect(r.welds, 3);
      expect(r.skippedNoOd, isEmpty);
      expect(r.totalGrosze, 45000);
      expect(r.di, 6);
      expect(pieceworkRows(r, en: false).first.label,
          'Podstawa: 3 spoiny × 150,00${nb}zł/szt.');
      expect(pieceworkRows(r, en: true).first.label,
          'Base: 3 welds × 150,00${nb}zł/weld');
    });

    test('spoiny bez wymiaru pominięte w trybie DI: lista, kwota ich nie zawiera',
        () {
      final r = run([
        cs('a', od: ''),
        cs('b', od: 'DN50'),
        cs('c'),
      ]);
      expect(r.welds, 1);
      expect(r.totalGrosze, 9000);
      expect([for (final e in r.skippedNoOd) e.id], ['a', 'b']);
      expect(skippedWeldLine(r.skippedNoOd.first), 'a · 2026-10-14 · L-12 · Blok 4');
    });

    test('spoina z dwoma stemplami dzielona po równo; brygada liczy ją raz',
        () {
      final welds = [
        cs('a', od: '114.3', welder: 'JK-12', rootWelder: 'AB-03'),
        cs('b', welder: 'JK-12'),
      ];
      final jk = run(welds, welder: 'jk-12');
      expect(jk.welder, 'jk-12');
      expect(jk.di, 4);
      expect(jk.totalGrosze, 9000 + 9000);
      expect(jk.sharedWelds, 1);
      final ab = run(welds, welder: 'AB-03');
      expect(ab.totalGrosze, 9000);
      final crew = run(welds, welder: null);
      expect(crew.isCrew, isTrue);
      expect(crew.di, 6);
      expect(crew.totalGrosze, 27000);
    });

    test('podział 1/n bez gubienia groszy: 10,00 zł ÷ 3 i 1,01 zł ÷ 2', () {
      expect([for (var i = 0; i < 3; i++) splitGrosze(1000, i, 3)],
          [333, 333, 334]);
      expect([splitGrosze(101, 0, 2), splitGrosze(101, 1, 2)], [50, 51]);
      const perWeld = PieceworkMode.weld;
      final three = [cs('w', welder: 'CC-3', rootWelder: 'aa-1')
          .copyWith(capWelder: 'BB-2')];
      // Kolejność podziału: stemple alfabetycznie, nie pole spoiny.
      final ten = [
        for (final s in ['AA-1', 'BB-2', 'CC-3'])
          run(three,
                  rates: const PieceworkRates(mode: perWeld, rateGrosze: 1000),
                  welder: s)
              .totalGrosze,
      ];
      expect(ten, [333, 333, 334]);
      final two = [cs('w', welder: 'JK-12', rootWelder: 'AB-03')];
      final oneOhOne = [
        for (final s in ['AB-03', 'JK-12'])
          run(two,
                  rates: const PieceworkRates(mode: perWeld, rateGrosze: 101),
                  welder: s)
              .totalGrosze,
      ];
      expect(oneOhOne, [50, 51]);
      expect(oneOhOne.reduce((a, b) => a + b), 101);
    });

    test('suma udziałów wszystkich stempli = kwota spoiny w widoku brygady, '
        'także z dopłatami, potrąceniem i naprawami', () {
      final welds = <String, List<WeldEntry>>{
        '3 stemple, 316L': [
          oct('a').copyWith(rootWelder: 'AB-03', capWelder: 'ZZ-9'),
        ],
        '2 stemple, 6G, ≈DI, naprawa R1': [
          oct('b', material: 'P235GH').copyWith(
              od: '57',
              rootWelder: 'AB-03',
              position: '6G',
              repairs: [repair('b', 1)]),
        ],
        '3 stemple, P91, Sch 80, NOK': [
          oct('c', material: 'P91').copyWith(
              od: '114.3',
              t: '8.56',
              status: 'NOK',
              rootWelder: 'AB-03',
              capWelder: 'XY-1'),
        ],
      };
      for (final rate in const [1, 2, 99, 100, 101, 1000, 4501, 12345]) {
        for (final mode in PieceworkMode.values) {
          final rates = PieceworkRates(
            mode: mode,
            rateGrosze: rate,
            stainlessBp: 2000,
            otherMaterialBp: 3333,
            pos6gBp: 1250,
            wallRule: WallRule.sch80,
            wallBp: 1500,
            rejectBp: 3333,
            repairPaid: true,
            repairBp: 5000,
          );
          for (final e in welds.entries) {
            final crew = run(e.value, rates: rates, welder: null);
            final parts = [
              for (final s in pieceworkStamps(e.value))
                run(e.value, rates: rates, welder: s),
            ];
            final why = '${e.key}, ${mode.name}, $rate gr';
            int sum(int Function(PieceworkResult r) f) =>
                parts.fold(0, (s, r) => s + f(r));
            expect(sum((r) => r.totalGrosze), crew.totalGrosze, reason: why);
            expect(sum((r) => r.baseGrosze), crew.baseGrosze, reason: why);
            expect(sum((r) => r.materialGrosze), crew.materialGrosze,
                reason: why);
            expect(sum((r) => r.positionGrosze), crew.positionGrosze,
                reason: why);
            expect(sum((r) => r.wallGrosze), crew.wallGrosze, reason: why);
            expect(sum((r) => r.deductionGrosze), crew.deductionGrosze,
                reason: why);
            expect(sum((r) => r.repairPayGrosze), crew.repairPayGrosze,
                reason: why);
          }
        }
      }
      // +20% przy 3 stemplach, 10,00 zł/szt.: 1000 + 200 → 400 = 133+133+134.
      final ss = welds['3 stemple, 316L']!;
      const r20 = PieceworkRates(
          mode: PieceworkMode.weld, rateGrosze: 1000, stainlessBp: 2000);
      expect([
        for (final s in ['AB-03', 'JK-12', 'ZZ-9'])
          run(ss, rates: r20, welder: s).materialGrosze,
      ], [66, 67, 67]);
      expect(run(ss, rates: r20, welder: null).totalGrosze, 1200);
    });

    test('spoiny bez stempla: brygada je liczy, spawacz dostaje uwagę', () {
      final welds = [
        cs('a'),
        cs('b', welder: ''),
        cs('c', welder: '', date: '2026-11-02'),
      ];
      final jk = run(welds);
      expect(jk.welds, 1);
      expect(jk.unstampedWelds, 1);
      expect(pieceworkNotes(jk, en: false),
          contains(startsWith('1 spoina w tym okresie bez stempla spawacza')));
      final crew = run(welds, welder: null);
      expect(crew.welds, 2);
      expect(crew.unstampedWelds, 0);
    });

    test('stemple z dziennika i domyślny spawacz („ja", jedyny, brygada)', () {
      final welds = [
        cs('a', welder: 'jk-12', rootWelder: 'AB-03'),
        cs('b', welder: 'JK-12'),
        cs('c', welder: 'ZZ-9').copyWith(deletedAt: 1),
      ];
      final stamps = pieceworkStamps(welds);
      expect(stamps, ['AB-03', 'jk-12']);
      expect(defaultPieceworkWelder(identityStamp: 'JK-12', stamps: stamps),
          'jk-12');
      expect(defaultPieceworkWelder(identityStamp: 'NEW-1', stamps: stamps),
          'NEW-1');
      expect(defaultPieceworkWelder(stamps: stamps), isNull);
      expect(defaultPieceworkWelder(stamps: const ['JK-12']), 'JK-12');
    });

    test('minimum dzienne: dopłata do dni poniżej minimum, tylko dla spawacza',
        () {
      const rates = PieceworkRates(rateGrosze: 4500, minDayGrosze: 50000);
      final welds = [
        cs('a', date: '2026-10-13'),
        cs('b', date: '2026-10-13'),
        cs('c', date: '2026-10-14', od: '323.9'),
      ];
      final r = run(welds, rates: rates);
      expect([for (final d in r.days) d.topUpGrosze], [32000, 0]);
      expect(r.topUpGrosze, 32000);
      expect(r.totalGrosze, 18000 + 32000 + 54000);
      final rows = {for (final x in pieceworkRows(r, en: false)) x.id: x};
      expect(rows['minDay']!.label,
          'Dopłata do minimum dziennego 500,00${nb}zł (1 dzień)');
      expect(r.perDayGrosze, 52000);

      final crew = run(welds, rates: rates, welder: null);
      expect(crew.topUpGrosze, 0);
      expect(crew.totalGrosze, 72000);
      expect(pieceworkNotes(crew, en: false),
          contains(startsWith('Minimum dzienne liczy się tylko')));
    });
  });

  group('minimum dzienne', () {
    test('dzień z pominiętą spoiną (bez OD) nie dostaje dopłaty do minimum',
        () {
      const rates = PieceworkRates(rateGrosze: 4500, minDayGrosze: 50000);
      final welds = [
        cs('a', date: '2026-10-13'),
        cs('noOd', date: '2026-10-13', od: ''),
        cs('b', date: '2026-10-14'),
        cs('onlySkipped', date: '2026-10-15', od: ''),
      ];
      final r = run(welds, rates: rates);
      expect([for (final d in r.days) d.topUpGrosze], [0, 41000]);
      expect(r.days.first.skippedWelds, 1);
      expect(r.totalGrosze, 9000 + 9000 + 41000);
      expect(r.minDayBlockedDays,
          [DateTime(2026, 10, 13), DateTime(2026, 10, 15)]);
      final notes = pieceworkNotes(r, en: false);
      expect(
          notes,
          containsAll([
            'Dzień 2026-10-13 ma pominięte spoiny — minimum dzienne nie '
                'naliczone, uzupełnij OD.',
            'Dzień 2026-10-15 ma pominięte spoiny — minimum dzienne nie '
                'naliczone, uzupełnij OD.',
          ]));
      // Po uzupełnieniu OD dzień 13 ma 18 000 gr i dostaje dopłatę.
      final fixed = run([
        for (final w in welds) w.od.isEmpty ? w.copyWith(od: '60.3') : w,
      ], rates: rates);
      expect(fixed.minDayBlockedDays, isEmpty);
      expect([for (final d in fixed.days) d.topUpGrosze], [32000, 41000, 41000]);
      // Bez minimum — bez uwag o dniach.
      expect(run(welds).minDayBlockedDays, isEmpty);
      expect(run(welds, rates: rates, welder: null).minDayBlockedDays, isEmpty);
    });
  });

  group('okresy', () {
    final wed = DateTime(2026, 10, 14, 15, 30);

    test('dziś, tydzień od poniedziałku, miesiąc, poprzedni miesiąc, własny',
        () {
      DayRange r(PieceworkPeriod p, {DateTime? now, DateTime? a, DateTime? b}) =>
          pieceworkRange(p, now ?? wed, customFrom: a, customTo: b);
      expect(r(PieceworkPeriod.today),
          DayRange(DateTime(2026, 10, 14), DateTime(2026, 10, 14)));
      expect(r(PieceworkPeriod.week),
          DayRange(DateTime(2026, 10, 12), DateTime(2026, 10, 14)));
      expect(r(PieceworkPeriod.month),
          DayRange(DateTime(2026, 10, 1), DateTime(2026, 10, 14)));
      expect(r(PieceworkPeriod.lastMonth),
          DayRange(DateTime(2026, 9, 1), DateTime(2026, 9, 30)));
      expect(r(PieceworkPeriod.lastMonth, now: DateTime(2026, 1, 10)),
          DayRange(DateTime(2025, 12, 1), DateTime(2025, 12, 31)));
      expect(r(PieceworkPeriod.lastMonth, now: DateTime(2028, 3, 31)),
          DayRange(DateTime(2028, 2, 1), DateTime(2028, 2, 29)));
      // Odwrócony zakres zamieniony; niepełny = dziś.
      expect(
          r(PieceworkPeriod.custom,
              a: DateTime(2026, 10, 20, 8), b: DateTime(2026, 10, 5, 22)),
          DayRange(DateTime(2026, 10, 5), DateTime(2026, 10, 20)));
      expect(r(PieceworkPeriod.custom, a: DateTime(2026, 10, 5)),
          DayRange(DateTime(2026, 10, 14), DateTime(2026, 10, 14)));
      // Niedziela należy do tygodnia od poniedziałku.
      expect(r(PieceworkPeriod.week, now: DateTime(2026, 10, 18, 23)),
          DayRange(DateTime(2026, 10, 12), DateTime(2026, 10, 18)));
    });

    test('granice dni: 23:59 i 00:00, zegar UTC na czas lokalny, zmiana czasu',
        () {
      final welds = [cs('a', date: '2026-10-14')];
      PieceworkResult at(DateTime now) => run(welds,
          range: pieceworkRange(PieceworkPeriod.today, now));
      expect(at(DateTime(2026, 10, 14, 23, 59, 59)).welds, 1);
      expect(at(DateTime(2026, 10, 15)).welds, 0);
      expect(at(DateTime(2026, 10, 14)).welds, 1);

      // Zegar w UTC: dzień liczony w czasie lokalnym telefonu.
      final utc = DateTime.utc(2026, 10, 14, 23, 30);
      final local = utc.toLocal();
      expect(pieceworkRange(PieceworkPeriod.today, utc).from,
          DateTime(local.year, local.month, local.day));

      // Tydzień po zmianie czasu (25.10.2026): poniedziałek 26.10, nie 25.
      expect(pieceworkRange(PieceworkPeriod.week, DateTime(2026, 10, 28, 1)),
          DayRange(DateTime(2026, 10, 26), DateTime(2026, 10, 28)));
      // Granice zakresu włącznie.
      final r = run([
        cs('first', date: '2026-10-01'),
        cs('last', date: '2026-10-31'),
        cs('out', date: '2026-11-01'),
        cs('before', date: '2026-09-30'),
      ]);
      expect([for (final l in r.lines) l.weld.id], ['first', 'last']);
    });

    test('spoiny bez poprawnej daty i usunięte nie wchodzą do okresu', () {
      final r = run([
        cs('a', date: ''),
        cs('b', date: '2026-13-45'),
        cs('c').copyWith(deletedAt: 5),
        cs('d'),
      ]);
      expect(r.welds, 1);
      expect(r.undatedWelds, 2);
      expect(pieceworkNotes(r, en: false),
          contains('2 spoiny bez poprawnej daty — poza każdym okresem.'));
    });

    test('spoiny z datą w przyszłości: uwaga zamiast cichego pominięcia', () {
      final welds = [
        cs('now', date: '2026-10-14'),
        cs('soon', date: '2026-10-20'),
        cs('typo', date: '2026-11-02'),
      ];
      final today = DateTime(2026, 10, 14);
      PieceworkResult at(PieceworkPeriod p,
              {DateTime? from, DateTime? to, DateTime? day}) =>
          computePiecework(
            entries: welds,
            rates: di45,
            range: pieceworkRange(p, DateTime(2026, 10, 14, 15),
                customFrom: from, customTo: to),
            welder: 'JK-12',
            today: day ?? today,
          );
      final month = at(PieceworkPeriod.month);
      expect(month.welds, 1);
      expect(month.futureWelds, 2);
      expect(
          pieceworkNotes(month, en: false),
          contains('2 spoiny z datą po końcu okresu (w przyszłości) — poza tą '
              'kwotą. Sprawdź datę w dzienniku.'));
      expect(pieceworkNotes(month, en: true),
          contains(startsWith('2 welds dated after the end of the period')));
      // Poprzedni miesiąc: spoina z dziś jest po okresie, ale nie w przyszłości.
      expect(at(PieceworkPeriod.lastMonth).futureWelds, 2);
      // Własny zakres obejmujący 20.10 — ta spoina się liczy.
      final custom = at(PieceworkPeriod.custom,
          from: DateTime(2026, 10, 1), to: DateTime(2026, 10, 31));
      expect(custom.welds, 2);
      expect(custom.futureWelds, 1);
      // Bez „dziś" nic nie jest liczone jako przyszłość (stare wywołania).
      expect(run(welds).futureWelds, 0);
    });

    test('kolejność: po dniu, w dniu jak w dzienniku', () {
      final r = run([
        cs('x', date: '2026-10-15'),
        cs('y', date: '2026-10-14'),
        cs('z', date: '2026-10-15'),
      ]);
      expect([for (final l in r.lines) l.weld.id], ['y', 'x', 'z']);
      expect(r.daysWorked, 2);
    });
  });

  group('grosze', () {
    test('połówka grosza od zera, liczone na int', () {
      expect(pctOfGrosze(1, 5000), 1);
      expect(pctOfGrosze(3, 5000), 2);
      expect(pctOfGrosze(1234, 1250), 154);
      expect(pctOfGrosze(-3, 5000), -2);
      expect(divRoundHalf(5, 2), 3);
      expect(divRoundHalf(-5, 2), -3);
      expect(divRoundHalf(4, 3), 1);
      expect(roundGrosze(2250.5), 2251);
      expect(bpFromPct(12.5), 1250);
      expect(bpText(1250, en: false), '12,5%');
      expect(bpText(1250, en: true), '12.5%');
    });

    test('spoina dzielona: 1 DI × 45,01 zł ÷ 2 = 22,505 → 22,51 zł', () {
      final r = run(
          [cs('a', od: '33.4', welder: 'JK-12', rootWelder: 'AB-03')],
          rates: const PieceworkRates(rateGrosze: 4501));
      expect(r.lines.single.baseGrosze, 2251);
    });

    test('suma = suma spoin; średnio na dzień i na godzinę', () {
      final r = run([
        cs('a', date: '2026-10-13'),
        oct('b', material: '316L').copyWith(od: '33.4'),
      ], rates: const PieceworkRates(rateGrosze: 4500, stainlessBp: 3333));
      expect(r.totalGrosze, r.lines.fold<int>(0, (s, l) => s + l.netGrosze));
      // 9000 + (4500 + 33,33% = 1499,85 → 1500).
      expect(r.lines.last.materialGrosze, 1500);
      expect(r.totalGrosze, 15000);
      // 15 000 / 2 dni = 7500; / 7 h = 2142,86 → 2143.
      expect(r.perDayGrosze, 7500);
      expect(pieceworkPerHour(r.totalGrosze, 7), 2143);
      expect(pieceworkPerHour(r.totalGrosze, null), isNull);
      expect(pieceworkPerHour(r.totalGrosze, 0), isNull);
      expect(divRoundHalf(10001, 2), 5001);
    });

    test('godziny: wpisane mają pierwszeństwo, potem godzin dziennie × dni',
        () {
      expect(pieceworkHours(typed: 50, perDay: 10, days: 3).hours, 50);
      final perDay = pieceworkHours(perDay: 10, days: 3);
      expect(perDay.hours, 30);
      expect(perDay.source, PieceworkHoursSource.perDay);
      expect(pieceworkHours(typed: 0, days: 3).source,
          PieceworkHoursSource.none);
      expect(pieceworkHours(perDay: 10, days: 0).hours, isNull);
    });
  });

  group('JSON stawek', () {
    test('zapis i odczyt bez strat', () {
      const rates = PieceworkRates(
        mode: PieceworkMode.weld,
        rateGrosze: 12345,
        stainlessBp: 2000,
        otherMaterialBp: 3050,
        pos2gBp: 500,
        pos5gBp: 1000,
        pos6gBp: 2000,
        wallRule: WallRule.mm,
        wallMm: 12.5,
        wallBp: 1500,
        minDayGrosze: 60000,
        rejectBp: 10000,
        repairPaid: true,
        repairBp: 7500,
        hoursPerDay: 10,
      );
      final d = decodePieceworkRates(rates.encode());
      expect(d.intact, isTrue);
      expect(d.rates, rates);
      expect(d.rates.minDayGrosze, 60000);
      expect(d.rates.hoursPerDay, 10);
      // Pusta wartość opcjonalna zostaje pusta.
      final none = decodePieceworkRates(const PieceworkRates().encode());
      expect(none.rates.minDayGrosze, isNull);
      expect(none.rates.hoursPerDay, isNull);
      expect(none.intact, isTrue);
    });

    test('uszkodzony JSON: domyślne stawki i znacznik uszkodzenia', () {
      for (final raw in ['{nie json', '[1, 2]', '"tekst"', '42']) {
        final d = decodePieceworkRates(raw);
        expect(d.intact, isFalse, reason: raw);
        expect(d.rates, const PieceworkRates(), reason: raw);
      }
      expect(decodePieceworkRates(null).intact, isTrue);
      expect(decodePieceworkRates('').intact, isTrue);
    });

    test('zły typ albo zakres pola: tylko to pole domyślne', () {
      final d = decodePieceworkRates(
          '{"v":1,"rate":"45","ss":2000,"reject":15000,"mode":"xyz",'
          '"wallMm":-3,"repairPaid":"tak","hpd":30,"minDay":1.5}');
      expect(d.intact, isFalse);
      expect(d.rates.rateGrosze, 0);
      expect(d.rates.stainlessBp, 2000);
      expect(d.rates.rejectBp, 0);
      expect(d.rates.mode, PieceworkMode.di);
      expect(d.rates.wallMm, 10);
      expect(d.rates.repairPaid, isFalse);
      expect(d.rates.hoursPerDay, isNull);
      expect(d.rates.minDayGrosze, isNull);
      // Brakujące pola (starszy zapis) — domyślne, bez znacznika.
      final old = decodePieceworkRates('{"rate":4500}');
      expect(old.intact, isTrue);
      expect(old.rates.rateGrosze, 4500);
      // Nieznana wersja — odczytana, ale oznaczona.
      expect(decodePieceworkRates('{"v":2,"rate":100}').intact, isFalse);
    });
  });

  group('raport', () {
    PieceworkReport report(List<WeldEntry> welds,
            {PieceworkHours hours = PieceworkHours.none, int? min}) =>
        PieceworkReport(
          result: run(welds),
          hours: hours,
          hourlyMinGrosze: min,
          generatedAt: DateTime(2026, 10, 17, 15, 30),
        );

    test('tekst do wysłania: kwoty, rozbicie i pominięte spoiny (PL i EN)',
        () {
      final r = report([cs('a'), cs('b', od: '114.3'), cs('c', od: '')],
          hours: const PieceworkHours(10, PieceworkHoursSource.typed));
      final pl = buildPieceworkText(r, en: false);
      expect(pl, startsWith('AKORD — ZAROBEK — 2026-10-01 – 2026-10-31\n'));
      expect(pl, contains('Spawacz: JK-12'));
      expect(pl, contains('Stawka: 45,00${nb}zł/DI'));
      expect(pl, contains('Spoiny: 2 spoiny · 6 DI · dni z wpisami: 1'));
      expect(pl, contains('Podstawa: 6 DI × 45,00${nb}zł/DI: 270,00${nb}zł'));
      expect(pl, contains('RAZEM: 270,00${nb}zł'));
      expect(pl, contains('27,00${nb}zł/h (10 h (wpisane))'));
      expect(pl, contains('POMINIĘTE — brak wymiaru (OD), kwota ich NIE zawiera: 1 spoina'));
      expect(pl, contains('• c · 2026-10-14 · L-12 · Blok 4'));
      expect(pl, endsWith('Fitter Welder Pro · 2026-10-17 15:30 · z dziennika spoin'));

      final en = buildPieceworkText(r, en: true);
      expect(en, startsWith('PIECEWORK EARNINGS — 2026-10-01 – 2026-10-31\n'));
      expect(en, contains('Welds: 2 welds · 6 DI · days with entries: 1'));
      expect(en, contains('TOTAL: 270,00${nb}zł'));
      expect(en, contains('SKIPPED — no size (OD), NOT in the amount: 1 weld'));
      expect(r.fileName(en: false), 'Akord_JK-12_2026-10-01_2026-10-31.pdf');
    });

    test('porównanie ze stawką z „Ile brać za godzinę"', () {
      final hours = const PieceworkHours(4, PieceworkHoursSource.typed);
      // 270 zł / 4 h = 67,50 zł/h.
      final less = report([cs('a'), cs('b', od: '114.3')],
          hours: hours, min: 9500);
      expect(hourlyCompareText(less, en: false),
          'Akord daje 67,50${nb}zł/h, a minimum z „Ile brać za godzinę" to '
          '95,00${nb}zł/h — 27,50${nb}zł/h mniej.');
      final more = report([cs('a'), cs('b', od: '114.3')],
          hours: hours, min: 6000);
      expect(hourlyCompareText(more, en: true), endsWith('7,50${nb}zł/h more.'));
      expect(hourlyCompareText(report([cs('a')], min: 6000), en: false),
          isNull);
    });
  });
}

