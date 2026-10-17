// Spawarka: cykl pracy z tabliczki i przewody. Liczby policzone ręcznie:
//  • tabliczka 200 A / 35 %, prąd 150 A: X₂ = 35·(200/150)² = 35·16/9 =
//    62,22 % → 62 % (w dół): 6,2 min spawania, 3,8 min przerwy na 10 min;
//    I₁₀₀ = 200·√0,35 = 118,32 A → 118 A; 250 A → poza zakresem źródła;
//  • przykład AWS: 200 A / 60 % przy 250 A → 38,4 % → 38 %;
//    I₁₀₀ = 200·√0,6 = 154,92 → 154 A (AWS zaokrągla do 155 — my w dół);
//  • tabliczka 200/35, 160/60, 130/100: przy 150 A szacunki 62,22 / 68,27 /
//    75,11 → 62 %; przy 140 A → 71,43 → 71 %; przy 125 A → 100 %
//    (tabliczka: 130 A / 100 %); I₁₀₀ = 130 A (tabliczka > 118,32);
//  • przewód 35 mm², pętla 25 + 25 = 50 m, 200 A: ΔU = 200·50·0,709/1000 =
//    7,09 V → 7,1 V > 4 V; najdłuższa pętla 4000/(200·0,709) = 28,2 → 28 m
//    (ΔU 3,97 → 4,0 V); obciążalność 60 % (10 min) 243 A × 0,96 (30 °C) =
//    233,28 → 233 A ≥ 200 A;
//  • dobór 200 A, 50 m, 60 %, 30 °C, 4 V: nagrzewanie → 35 mm², spadek:
//    50 mm² 4,93 V ✗, 70 mm² 3,48 V ✓ → 70 mm² (decyduje spadek).

import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';

import 'package:cut_list_app/domain/welding/power_source.dart';

PlateRowInput _row(int row, double i, double x) =>
    PlateRowInput(row: row, currentA: i, dutyPct: x);

DutyCycleInput _duty(List<(double, double)> plate, double current) =>
    DutyCycleInput(rows: [
      for (final (k, (i, x)) in plate.indexed) _row(k + 1, i, x),
    ], weldCurrentA: current);

const _plate3 = [(200.0, 35.0), (160.0, 60.0), (130.0, 100.0)];

CableInput _cable({
  double current = 200,
  double weld = 25,
  double ret = 25,
  int section = 35,
  double duty = 60,
  int ambient = 30,
  double limit = 4,
}) =>
    CableInput(
      currentA: current,
      weldLeadM: weld,
      returnLeadM: ret,
      sectionMm2: section,
      dutyPct: duty,
      ambientC: ambient,
      dropLimitV: limit,
    );

void main() {
  group('Cykl pracy — wzór AWS i tabliczka', () {
    test('200 A / 35 % przy 150 A: 62 %, 6,2 min spawania, 3,8 min przerwy',
        () {
      final r = computeDutyCycle(_duty([(200, 35)], 150))!;
      expect(r.dutyExactPct, closeTo(35 * 16 / 9, 1e-9));
      expect(r.dutyExactPct, closeTo(62.2222, 1e-4));
      expect(r.dutyPct, 62);
      expect(r.weldMinutes, closeTo(6.2, 1e-12));
      expect(r.restMinutes, closeTo(3.8, 1e-12));
      expect(r.fromPlate, isFalse);
      expect(r.estimateBasis, const PlatePoint(200, 35));
      expect(r.i100ExactA, closeTo(200 * math.sqrt(0.35), 1e-9));
      expect(r.i100ExactA, closeTo(118.3216, 1e-4));
      expect(r.i100A, 118);
      expect(r.i100FromPlate, isFalse);
    });

    test('powyżej największego prądu z tabliczki → poza zakresem źródła', () {
      final r = computeDutyCycle(_duty([(200, 35)], 250))!;
      expect(r.outOfRange, isTrue);
      expect(r.dutyPct, isNull);
      expect(r.weldMinutes, isNull);
      expect(r.restMinutes, isNull);
      expect(r.maxPoint, const PlatePoint(200, 35));
      // Prąd przy 100 % to cecha tabliczki — liczy się dalej.
      expect(r.i100A, 118);
      // Tuż nad granicą też poza zakresem; równo granica — z tabliczki.
      expect(computeDutyCycle(_duty([(200, 35)], 200.5))!.outOfRange, isTrue);
      final edge = computeDutyCycle(_duty([(200, 35)], 200))!;
      expect(edge.dutyPct, 35);
      expect(edge.fromPlate, isTrue);
    });

    test('przykład AWS: 200 A / 60 % przy 250 A → 38 % (zakres 250 A)', () {
      // W przykładzie AWS źródło ma 250 A na tabliczce („as far as
      // permitted”) — bez tego punktu 250 A byłoby poza zakresem.
      final r = computeDutyCycle(_duty([(250, 20), (200, 60)], 250))!;
      expect(r.dutyPct, 20); // tabliczka 250 A / 20 % ma pierwszeństwo
      final est = dutyFromPoint(const PlatePoint(200, 60), 250);
      expect(est, closeTo(38.4, 1e-9));
      expect(floorSafe(est), 38);
      expect(currentFromPoint(const PlatePoint(200, 60), 100),
          closeTo(154.919, 1e-3));
      expect(computeDutyCycle(_duty([(200, 60)], 100))!.i100A, 154);
    });

    test('poniżej prądu przy 100 % → 100 %, nie więcej', () {
      final r = computeDutyCycle(_duty([(200, 35)], 100))!;
      expect(dutyFromPoint(const PlatePoint(200, 35), 100), closeTo(140, 1e-9));
      expect(r.dutyPct, 100);
      expect(r.weldMinutes, 10);
      expect(r.restMinutes, 0);
    });

    test('granica I₁₀₀: 118 A → 100 %, 119 A → 98 % (w dół)', () {
      expect(computeDutyCycle(_duty([(200, 35)], 118))!.dutyPct, 100);
      final r = computeDutyCycle(_duty([(200, 35)], 119))!;
      // 35·40000/14161 = 98,863 %.
      expect(r.dutyExactPct, closeTo(35 * 40000 / 14161, 1e-9));
      expect(r.dutyExactPct, closeTo(98.863, 1e-3));
      expect(r.dutyPct, 98);
      // 63,9 % → 63, nie 64.
      final r148 = computeDutyCycle(_duty([(200, 35)], 148))!;
      expect(r148.dutyExactPct, closeTo(63.915, 1e-3));
      expect(r148.dutyPct, 63);
    });

    test('trzy punkty: najmniejszy szacunek, ale nie mniej niż tabliczka', () {
      final r150 = computeDutyCycle(_duty(_plate3, 150))!;
      expect(r150.dutyPct, 62);
      expect(r150.estimateBasis, const PlatePoint(200, 35));
      final r140 = computeDutyCycle(_duty(_plate3, 140))!;
      expect(r140.dutyExactPct, closeTo(35 * math.pow(200 / 140, 2), 1e-9));
      expect(r140.dutyPct, 71);
      // 125 A ≤ 130 A z tabliczki przy 100 % — szacunek z 200/35 (89,6 %)
      // nie może przeczyć tabliczce.
      final r125 = computeDutyCycle(_duty(_plate3, 125))!;
      expect(
          dutyFromPoint(const PlatePoint(200, 35), 125), closeTo(89.6, 1e-9));
      expect(r125.dutyPct, 100);
      expect(r125.fromPlate, isTrue);
      expect(r125.plateBasis, const PlatePoint(130, 100));
      // Prąd przy 100 % z tabliczki (130 A > szacunek 118 A).
      expect(r150.i100A, 130);
      expect(r150.i100FromPlate, isTrue);
      // Kolejność wierszy nie ma znaczenia.
      final shuffled =
          computeDutyCycle(_duty([(130, 100), (200, 35), (160, 60)], 150))!;
      expect(shuffled.dutyPct, 62);
      expect(shuffled.plate.first, const PlatePoint(130, 100));
    });

    test(
        'siatka: wynik między gwarancją tabliczki a szacunkiem, maks. 100 %, '
        'minuty sumują się do 10', () {
      for (final plate in [
        [(200.0, 35.0)],
        _plate3,
        [(315.0, 40.0), (250.0, 60.0), (200.0, 100.0)],
        [(180.0, 20.0), (120.0, 60.0)],
      ]) {
        final maxI = plate.map((p) => p.$1).reduce(math.max);
        for (var i2 = 5.0; i2 <= maxI + 50; i2 += 2.5) {
          final r = computeDutyCycle(_duty(plate, i2))!;
          if (i2 > maxI) {
            expect(r.outOfRange, isTrue, reason: '$plate $i2');
            continue;
          }
          final pts = [for (final (i, x) in plate) PlatePoint(i, x)];
          final minEst = pts.map((p) => dutyFromPoint(p, i2)).reduce(math.min);
          final guarantee = pts
              .where((p) => p.currentA >= i2)
              .map((p) => p.dutyPct)
              .reduce(math.max);
          final d = r.dutyPct!;
          expect(d, lessThanOrEqualTo(100), reason: '$plate $i2');
          expect(d, greaterThanOrEqualTo(guarantee.floor()),
              reason: '$plate $i2');
          expect(d, lessThanOrEqualTo(math.max(minEst, guarantee) + 1e-9),
              reason: '$plate $i2');
          expect(r.weldMinutes! + r.restMinutes!, closeTo(10, 1e-9));
          // Przy prądzie ≤ I₁₀₀ (zaokrąglonym w dół) zawsze 100 %.
          if (i2 <= r.i100A) expect(d, 100, reason: '$plate $i2');
          expect(r.i100A, lessThanOrEqualTo(maxI));
        }
      }
    });
  });

  group('Cykl pracy — walidacja', () {
    test('puste / nieczytelne pole to problem, nie wynik', () {
      expect(dutyProblems(_duty([], 150)),
          [const DutyProblem(DutyProblemKind.noPlate)]);
      expect(dutyProblems(_duty([(double.nan, 35)], 150)),
          [const DutyProblem(DutyProblemKind.plateCurrent, 1)]);
      expect(dutyProblems(_duty([(200, 35), (160, double.nan)], 150)),
          [const DutyProblem(DutyProblemKind.plateDuty, 2)]);
      expect(dutyProblems(_duty([(200, 35)], double.nan)),
          [const DutyProblem(DutyProblemKind.weldCurrent)]);
      for (final bad in [
        _duty([], 150),
        _duty([(double.nan, 35)], 150),
        _duty([(200, 35)], double.nan),
        _duty([(200, 35)], 0),
      ]) {
        expect(computeDutyCycle(bad), isNull);
      }
    });

    test('granice pól: cykl 1–100 %, prądy do 1500 A, prąd > 0', () {
      expect(dutyProblems(_duty([(200, 0)], 150)), isNotEmpty);
      expect(dutyProblems(_duty([(200, 101)], 150)), isNotEmpty);
      expect(dutyProblems(_duty([(200, 1)], 150)), isEmpty);
      expect(dutyProblems(_duty([(200, 100)], 150)), isEmpty);
      expect(dutyProblems(_duty([(0, 35)], 150)), isNotEmpty);
      expect(dutyProblems(_duty([(1501, 35)], 150)), isNotEmpty);
      expect(dutyProblems(_duty([(200, 35)], -5)), isNotEmpty);
      expect(dutyProblems(_duty([(200, 35)], 1501)), isNotEmpty);
      expect(dutyProblems(_duty([(200, 35)], double.infinity)), isNotEmpty);
    });

    test('sprzeczna tabliczka i powtórzony prąd', () {
      // Większy prąd z większym cyklem — zamienione pola?
      expect(dutyProblems(_duty([(200, 60), (160, 35)], 150)),
          [const DutyProblem(DutyProblemKind.inconsistentPlate)]);
      expect(dutyProblems(_duty([(200, 35), (200, 60)], 150)),
          [const DutyProblem(DutyProblemKind.duplicateCurrent)]);
      // Ten sam cykl przy dwóch prądach — nadmiarowe, nie sprzeczne.
      expect(dutyProblems(_duty([(130, 100), (120, 100)], 100)), isEmpty);
    });

    test('poprawne punkty do zapisu pomijają wiersze z błędem', () {
      expect(
          validPlatePoints([
            _row(1, 200, 35),
            _row(2, double.nan, 60),
            _row(3, 130, 100),
          ]),
          const [PlatePoint(200, 35), PlatePoint(130, 100)]);
    });
  });

  group('Przewody — spadek napięcia', () {
    test('200 A, pętla 50 m, 35 mm²: ΔU 7,09 → 7,1 V, powyżej 4 V', () {
      final r = checkCable(_cable())!;
      expect(r.loopM, 50);
      expect(r.dropExactV, closeTo(7.09, 1e-9));
      expect(r.dropV, 7.1);
      expect(r.dropOk, isFalse);
      expect(r.maxLoopM, 28);
      // 28 m: 3,9704 V → 4,0 V — mieści się.
      final at28 = checkCable(_cable(weld: 14, ret: 14))!;
      expect(at28.dropExactV, closeTo(3.9704, 1e-9));
      expect(at28.dropV, 4.0);
      expect(at28.dropOk, isTrue);
      // 28,3 m: 4,013 V → 4,1 V — nie mieści się (w górę do 0,1 V).
      final at283 = checkCable(_cable(weld: 14.15, ret: 14.15))!;
      expect(at283.dropV, 4.1);
      expect(at283.dropOk, isFalse);
    });

    test('pętla = przewód spawalniczy + masowy (cała pętla)', () {
      final one = checkCable(_cable(weld: 50, ret: 0))!;
      final two = checkCable(_cable(weld: 25, ret: 25))!;
      expect(one.dropExactV, closeTo(two.dropExactV, 1e-12));
      expect(checkCable(_cable(weld: 25, ret: 0))!.dropExactV,
          closeTo(two.dropExactV / 2, 1e-12));
    });

    test(
        'dane przewodu zgodne z fizyką: opór > ρ miedzi w 85 °C / A '
        '(żyła wielodrutowa), najwyżej o 20 %', () {
      expect(copperResistivityAt(20), kCopperResistivity20);
      expect(copperResistivityAt(85), closeTo(0.021645, 1e-6));
      for (final s in kCableSectionsMm2) {
        final r = checkCable(_cable(section: s))!;
        final ratio = r.equivalentResistivity / copperResistivityAt(85);
        expect(ratio, inInclusiveRange(1.0, 1.2), reason: '$s mm²');
      }
    });

    test('grubszy przewód — mniejszy spadek i dłuższa pętla', () {
      double? prevDrop;
      int? prevLoop;
      for (final s in kCableSectionsMm2) {
        final r = checkCable(_cable(section: s))!;
        if (prevDrop != null) {
          expect(r.dropExactV, lessThan(prevDrop), reason: '$s');
          expect(r.maxLoopM, greaterThanOrEqualTo(prevLoop!), reason: '$s');
        }
        prevDrop = r.dropExactV;
        prevLoop = r.maxLoopM;
      }
      expect(checkCable(_cable(section: 70))!.dropV, 3.5);
    });

    test('najdłuższa pętla zawsze mieści się w progu, o 1 m więcej — już nie',
        () {
      for (final s in kCableSectionsMm2) {
        for (final i in <double>[50, 120, 200, 333, 500]) {
          for (final limit in <double>[2, 4, 4.05, 6.5]) {
            final r = checkCable(_cable(section: s, current: i, limit: limit))!;
            final l = r.maxLoopM;
            if (l > 0) {
              expect(
                  checkCable(_cable(
                          section: s,
                          current: i,
                          limit: limit,
                          weld: l.toDouble(),
                          ret: 0))!
                      .dropOk,
                  isTrue,
                  reason: '$s $i $limit');
            }
            expect(
                checkCable(_cable(
                        section: s,
                        current: i,
                        limit: limit,
                        weld: l + 1.0,
                        ret: 0))!
                    .dropOk,
                isFalse,
                reason: '$s $i $limit');
          }
        }
      }
    });
  });

  group('Przewody — obciążalność (10 min, 25 °C)', () {
    test('35 mm², 60 %, do 30 °C: 243 × 0,96 = 233,28 → 233 A', () {
      final r = checkCable(_cable())!;
      expect(r.dutyColumnPct, 60);
      expect(r.tableAmpacityA, 243);
      expect(r.ambientFactor, 0.96);
      expect(r.ampacityA, 233);
      expect(r.heatOk, isTrue);
      expect(checkCable(_cable(ambient: 25))!.ampacityA, 243);
      expect(checkCable(_cable(ambient: 40))!.ampacityA, 211);
      expect(checkCable(_cable(ambient: 50))!.ampacityA, 184);
    });

    test('cykl między kolumnami → kolumna wyższa (mniejszy prąd)', () {
      expect(cableDutyColumn(60), 60);
      expect(cableDutyColumn(61), 80);
      expect(cableDutyColumn(36), 60);
      expect(cableDutyColumn(35), 35);
      expect(cableDutyColumn(5), 8);
      expect(cableDutyColumn(1), 8);
      expect(cableDutyColumn(86), 100);
      expect(cableDutyColumn(100), 100);
      expect(cableTableAmpacityA(35, 61), 231);
      expect(cableTableAmpacityA(35, 100), 225);
      expect(cableTableAmpacityA(35, 5), 497);
    });

    test('granica: 243 A przy 243 A — OK, 243,5 A — za mały', () {
      expect(checkCable(_cable(ambient: 25, current: 243))!.heatOk, isTrue);
      expect(checkCable(_cable(ambient: 25, current: 243.5))!.heatOk, isFalse);
    });

    test('tabela: obciążalność rośnie z przekrojem i maleje z cyklem', () {
      for (var k = 0; k < kCableDutyColumnsPct.length; k++) {
        var prev = 0;
        for (final s in kCableSectionsMm2) {
          final a = kCableAmpacity10MinA[s]![k];
          expect(a, greaterThan(prev), reason: '$s mm² kol. $k');
          prev = a;
        }
      }
      for (final s in kCableSectionsMm2) {
        final row = kCableAmpacity10MinA[s]!;
        expect(row, hasLength(kCableDutyColumnsPct.length));
        for (var k = 1; k < row.length; k++) {
          // Kolumny: 100, 85, 80, 60, 35, 20, 8 % — mniejszy cykl, większy
          // prąd.
          expect(row[k], greaterThanOrEqualTo(row[k - 1]), reason: '$s mm²');
        }
      }
      for (var k = 1; k < kCableAmbientFactors.length; k++) {
        expect(kCableAmbientFactors[k].$2,
            lessThan(kCableAmbientFactors[k - 1].$2));
      }
    });
  });

  group('Dobór przekroju — w górę do typoszeregu', () {
    test('200 A, 50 m, 60 %, 30 °C, 4 V → 70 mm², decyduje spadek', () {
      final r = sizeCable(_cable(section: 16))!;
      expect(r.heatSectionMm2, 35);
      expect(r.dropSectionMm2, 70);
      expect(r.sectionMm2, 70);
      expect(r.dropGoverns, isTrue);
      expect(r.heatGoverns, isFalse);
      expect(r.check!.dropV, 3.5);
      expect(r.check!.ok, isTrue);
      // Przekrój z pola nie ma znaczenia.
      expect(sizeCable(_cable(section: 95))!.sectionMm2, 70);
    });

    test('krótka pętla, 100 %, 40 °C → decyduje nagrzewanie', () {
      final r = sizeCable(
          _cable(current: 300, weld: 2, ret: 2, duty: 100, ambient: 40))!;
      expect(r.dropSectionMm2, 16);
      // 50 mm²: 285 × 0,87 = 247 A < 300; 70 mm²: 355 × 0,87 = 308 A.
      expect(r.heatSectionMm2, 70);
      expect(r.sectionMm2, 70);
      expect(r.heatGoverns, isTrue);
      expect(r.check!.ampacityA, 308);
    });

    test('żaden do 95 mm² → brak wyniku z powodem', () {
      final drop = sizeCable(_cable(weld: 100, ret: 100))!;
      expect(drop.sectionMm2, isNull);
      expect(drop.dropSectionMm2, isNull);
      expect(drop.heatSectionMm2, 35);
      expect(drop.check, isNull);
      final both = sizeCable(_cable(current: 500, weld: 50, ret: 50))!;
      expect(both.sectionMm2, isNull);
      expect(both.heatSectionMm2, isNull);
    });

    test('siatka: dobrany przekrój spełnia oba warunki, mniejszy już nie', () {
      for (final i in <double>[40, 90, 150, 200, 260, 330, 420]) {
        for (final loop in <double>[4, 10, 20, 35, 50, 80]) {
          for (final duty in <double>[20, 35, 60, 100]) {
            for (final amb in [25, 40]) {
              final input = _cable(
                  current: i, weld: loop, ret: 0, duty: duty, ambient: amb);
              final r = sizeCable(input)!;
              final s = r.sectionMm2;
              if (s == null) {
                expect(
                    kCableSectionsMm2
                        .any((x) => CableCheckResult(input.withSection(x)).ok),
                    isFalse);
                continue;
              }
              expect(CableCheckResult(input.withSection(s)).ok, isTrue);
              final k = kCableSectionsMm2.indexOf(s);
              if (k > 0) {
                expect(
                    CableCheckResult(
                            input.withSection(kCableSectionsMm2[k - 1]))
                        .ok,
                    isFalse,
                    reason: '$i A $loop m $duty % $amb °C');
              }
            }
          }
        }
      }
    });
  });

  group('Przewody — walidacja', () {
    test('puste / nieczytelne pole to problem, nie wynik', () {
      expect(
          cableProblems(_cable(current: double.nan)), [CableProblem.current]);
      expect(cableProblems(_cable(weld: double.nan)), [CableProblem.weldLead]);
      expect(cableProblems(_cable(ret: -1)), [CableProblem.returnLead]);
      expect(cableProblems(_cable(weld: 0, ret: 0)), [CableProblem.noLength]);
      expect(cableProblems(_cable(section: 40)), [CableProblem.section]);
      expect(cableProblems(_cable(section: 40), forSizing: true), isEmpty);
      expect(cableProblems(_cable(duty: 0)), [CableProblem.duty]);
      expect(cableProblems(_cable(duty: 101)), [CableProblem.duty]);
      expect(cableProblems(_cable(ambient: 27)), [CableProblem.ambient]);
      expect(cableProblems(_cable(limit: 0.2)), [CableProblem.dropLimit]);
      expect(
          cableProblems(_cable(limit: double.nan)), [CableProblem.dropLimit]);
      expect(checkCable(_cable(current: double.nan)), isNull);
      expect(sizeCable(_cable(weld: double.nan)), isNull);
    });
  });

  group('Zapis tabliczki', () {
    test('zapis i odczyt bez strat', () {
      const pts = [PlatePoint(200, 35), PlatePoint(162.5, 60)];
      final r = decodePlateDetailed(encodePlate(pts));
      expect(r.points, pts);
      expect(r.lossy, isFalse);
    });

    test('uszkodzony / obcy zapis: to, co da się odczytać, i flaga straty', () {
      expect(decodePlateDetailed('{"v":1,"points":[{"i":'),
          (points: const <PlatePoint>[], lossy: true));
      expect(decodePlateDetailed('[1,2]').lossy, isTrue);
      final partial = decodePlateDetailed(
          '{"v":1,"points":[{"i":200,"x":35},{"i":"x","x":60},'
          '{"i":130,"x":140}]}');
      expect(partial.points, const [PlatePoint(200, 35)]);
      expect(partial.lossy, isTrue);
      final tooMany = decodePlateDetailed(
          '{"v":1,"points":[{"i":1,"x":1},{"i":2,"x":1},{"i":3,"x":1},'
          '{"i":4,"x":1}]}');
      expect(tooMany.points, hasLength(kPlateRows));
      expect(tooMany.lossy, isTrue);
      expect(decodePlateDetailed('{"v":2,"points":[]}').lossy, isTrue);
    });
  });

  group('Tekst', () {
    test('PL przecinek, EN kropka — te same liczby', () {
      expect(psFixed(7.09, 1, en: false), '7,1');
      expect(psFixed(7.09, 1, en: true), '7.1');
      expect(psNum(4, en: false), '4');
      expect(psNum(0.709, en: false), '0,709');
      expect(psNum(162.5, en: true), '162.5');
      expect(
          platePointText(const PlatePoint(200, 35), en: false), '200 A / 35 %');
    });

    test('udostępniany tekst: cykl, przewody, dobór, zastrzeżenie', () {
      final duty = computeDutyCycle(_duty([(200, 35)], 150));
      final cable = checkCable(_cable());
      final sizing = sizeCable(_cable());
      final pl = powerSourceShareText(
          en: false, duty: duty, cable: cable, sizing: sizing);
      expect(pl, contains('Tabliczka: 200 A / 35 %'));
      expect(
          pl,
          contains('cykl pracy 62 %: 6,2 min spawania, 3,8 min '
              'przerwy na każde 10 min'));
      expect(pl, contains('szacunek z 200 A / 35 %'));
      expect(pl, contains('Praca ciągła (100 %): do 118 A'));
      expect(pl, contains('pętla 25 + 25 = 50 m, 35 mm²'));
      expect(pl, contains('ΔU = 7,1 V — POWYŻEJ progu 4 V'));
      expect(pl, contains('Najdłuższa pętla dla 4 V: 28 m'));
      expect(pl, contains('obciążalność 233 A ≥ 200 A — OK'));
      expect(
          pl,
          contains('Najmniejszy przekrój: 70 mm² (decyduje spadek '
              'napięcia)'));
      expect(pl, endsWith(powerSourceDisclaimer(en: false)));
      expect(pl, isNot(contains('NaN')));

      final en = powerSourceShareText(
          en: true, duty: duty, cable: cable, sizing: sizing);
      expect(en, contains('duty cycle 62 %: 6.2 min welding, 3.8 min rest'));
      expect(en, contains('ΔU = 7.1 V — ABOVE the 4 V limit'));
      expect(en, contains('Smallest size: 70 mm² (governed by voltage drop)'));

      final out = powerSourceShareText(
          en: false, duty: computeDutyCycle(_duty([(200, 35)], 250)));
      expect(
          out,
          contains('250 A — poza zakresem źródła (największy '
              'z tabliczki 200 A)'));
      expect(out, isNot(contains('Przewody')));
    });

    test('wskazówki: każda ze źródłem, PL i EN te same liczby, bez emoji', () {
      final number = RegExp(r'\d+(?:[.,]\d+)?');
      final emoji = RegExp(
          r'[\u{1F300}-\u{1FAFF}\u{2600}-\u{27BF}\u{1F000}-\u{1F2FF}]',
          unicode: true);
      List<String> nums(String s) =>
          number.allMatches(s).map((m) => m[0]!.replaceAll(',', '.')).toList();
      for (final t in kPowerSourceTips) {
        expect(t.source.trim(), isNotEmpty, reason: t.id);
        expect(nums(t.textPl), nums(t.textEn), reason: t.id);
        for (final s in [t.titlePl, t.titleEn, t.textPl, t.textEn]) {
          expect(emoji.hasMatch(s), isFalse, reason: t.id);
        }
      }
      for (final en in [false, true]) {
        for (final s in [
          dutyFormulaNote(en: en),
          dutyAmbientNote(en: en),
          cableDropNote(en: en),
          dropLimitNote(en: en),
          cableHeatNote(en: en),
        ]) {
          expect(s, isNot(contains('NaN')));
        }
      }
      expect(nums(cableDropNote(en: false)), nums(cableDropNote(en: true)));
      expect(nums(cableHeatNote(en: false)), nums(cableHeatNote(en: true)));
      expect(nums(dutyAmbientNote(en: false)), nums(dutyAmbientNote(en: true)));
    });
  });
}
