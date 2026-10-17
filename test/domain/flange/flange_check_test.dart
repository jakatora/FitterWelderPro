// Odbiór połączenia kołnierzowego — kryteria ASME PCC-1-2019 zał. E.
//
// Granice (E-2.4): oś 1,5 mm (1/16"), równoległość max − min 0,8 mm
// (1/32"), otwory 3 mm (1/8"), szczelina ≤ 2 × grubość uszczelki.
// Wartość calowa w normie nie jest dokładnym przeliczeniem metrycznej:
// 1/16" = 1,5875 mm > 1,5 mm — protokół ocenia się w jednostce pomiaru.

import 'package:flutter_test/flutter_test.dart';

import 'package:cut_list_app/domain/flange/flange_check.dart';

FlangeCheck _check({
  double? centerline,
  double? rotation,
  List<double?>? gaps,
  AlignmentForce? force,
  double? gasket,
  int? bolts,
  Set<FlangeChecklistItem> checked = const {},
  LengthUnit unit = LengthUnit.mm,
  FlangeTolerances tolerances = FlangeTolerances.pcc1,
}) =>
    FlangeCheck(
      id: 'x',
      joint: FlangeJoint(
          tag: 'L-1', gasketThicknessMm: gasket, boltCount: bolts, dn: 150),
      measurements: FlangeMeasurements(
        centerlineMm: centerline,
        rotationMm: rotation,
        gapsMm: gaps ?? const [null, null, null, null],
        force: force,
      ),
      checked: checked,
      unit: unit,
      tolerances: tolerances,
    );

CheckVerdict _v(FlangeCheck c, FlangeCriterion k) => c.evaluate().of(k).verdict;

/// Komplet, który przechodzi wszystkie kryteria.
FlangeCheck _allOk() => _check(
      centerline: 1.0,
      rotation: 2.0,
      gaps: const [3.0, 3.4, 3.2, 3.6],
      force: AlignmentForce.light,
      gasket: 4.5,
      bolts: 8,
      checked: FlangeChecklistItem.values.toSet(),
    );

void main() {
  group('wartości PCC-1-2019 zał. E', () {
    test('1,5 mm (1/16"), 0,8 mm (1/32"), 3 mm (1/8"), 2 × uszczelka', () {
      const t = FlangeTolerances.pcc1;
      expect(t.centerline.mm, 1.5);
      expect(t.centerline.inch, 1 / 16);
      expect(t.parallelism.mm, 0.8);
      expect(t.parallelism.inch, 1 / 32);
      expect(t.rotation.mm, 3.0);
      expect(t.rotation.inch, 1 / 8);
      expect(t.gapFactor, 2.0);
      expect(t.isPcc1, isTrue);
    });
  });

  group('przesunięcie osi (high/low)', () {
    test('na granicy: 1,5 mm → OK', () {
      expect(_v(_check(centerline: 1.5), FlangeCriterion.centerline),
          CheckVerdict.ok);
    });
    test('tuż ponad: 1,51 mm → poza tolerancją', () {
      expect(_v(_check(centerline: 1.51), FlangeCriterion.centerline),
          CheckVerdict.fail);
    });
    test('brak pomiaru → brak, nie OK', () {
      expect(_v(_check(), FlangeCriterion.centerline), CheckVerdict.missing);
    });
  });

  group('równoległość (max − min szczeliny)', () {
    test('na granicy: 2,3 i 3,1 mm → różnica 0,8 → OK', () {
      final c = _check(gaps: const [2.3, 3.1, 2.7, 2.9]);
      expect(c.evaluate().of(FlangeCriterion.parallelism).valueMm,
          closeTo(0.8, 1e-9));
      expect(_v(c, FlangeCriterion.parallelism), CheckVerdict.ok);
    });
    test('tuż ponad: różnica 0,81 → poza tolerancją', () {
      expect(
          _v(_check(gaps: const [2.3, 3.11, 2.7, 2.9]),
              FlangeCriterion.parallelism),
          CheckVerdict.fail);
    });
    test('brak pomiaru → brak', () {
      expect(_v(_check(), FlangeCriterion.parallelism), CheckVerdict.missing);
    });
    test('niepełny pomiar w granicy → brak (nie OK)', () {
      expect(
          _v(_check(gaps: const [2.3, 2.5, null, null]),
              FlangeCriterion.parallelism),
          CheckVerdict.missing);
    });
    test('niepełny pomiar już ponad granicą → poza tolerancją', () {
      expect(
          _v(_check(gaps: const [2.0, 3.0, null, null]),
              FlangeCriterion.parallelism),
          CheckVerdict.fail);
    });
  });

  group('przesunięcie obrotowe otworów', () {
    test('na granicy: 3,0 mm → OK', () {
      expect(
          _v(_check(rotation: 3.0), FlangeCriterion.rotation), CheckVerdict.ok);
    });
    test('tuż ponad: 3,01 mm → poza tolerancją', () {
      expect(_v(_check(rotation: 3.01), FlangeCriterion.rotation),
          CheckVerdict.fail);
    });
    test('brak pomiaru → brak', () {
      expect(_v(_check(), FlangeCriterion.rotation), CheckVerdict.missing);
    });
  });

  group('nadmierna szczelina (2 × grubość uszczelki)', () {
    test('na granicy: uszczelka 4,5 mm, największa szczelina 9,0 → OK', () {
      final c = _check(gasket: 4.5, gaps: const [8.5, 9.0, 8.8, 8.6]);
      final r = c.evaluate().of(FlangeCriterion.spacing);
      expect(r.limitMm, 9.0);
      expect(r.valueMm, 9.0);
      expect(r.verdict, CheckVerdict.ok);
    });
    test('tuż ponad: 9,01 → poza tolerancją', () {
      expect(
          _v(_check(gasket: 4.5, gaps: const [8.5, 9.01, 8.8, 8.6]),
              FlangeCriterion.spacing),
          CheckVerdict.fail);
    });
    test('brak grubości uszczelki → brak (nawet z kompletem szczelin)', () {
      expect(
          _v(_check(gaps: const [3.0, 3.0, 3.0, 3.0]), FlangeCriterion.spacing),
          CheckVerdict.missing);
    });
    test('brak szczelin → brak', () {
      expect(
          _v(_check(gasket: 3), FlangeCriterion.spacing), CheckVerdict.missing);
    });
    test('niepełny pomiar ponad granicą → poza tolerancją', () {
      expect(
          _v(_check(gasket: 1.5, gaps: const [3.5, null, null, null]),
              FlangeCriterion.spacing),
          CheckVerdict.fail);
    });
  });

  group('siła potrzebna do zestawienia', () {
    test('brak oceny → brak', () {
      expect(_v(_check(), FlangeCriterion.force), CheckVerdict.missing);
    });
    test('ręcznie → OK, duża siła → poza tolerancją', () {
      expect(_v(_check(force: AlignmentForce.light), FlangeCriterion.force),
          CheckVerdict.ok);
      expect(_v(_check(force: AlignmentForce.heavy), FlangeCriterion.force),
          CheckVerdict.fail);
    });
  });

  group('cale', () {
    test('przeliczenie: 1" = 25,4 mm w obie strony', () {
      expect(unitToMm(1, LengthUnit.inch), 25.4);
      expect(mmToUnit(25.4, LengthUnit.inch), 1);
      expect(unitToMm(3, LengthUnit.mm), 3);
      expect(mmToUnit(3, LengthUnit.mm), 3);
    });

    test(
        '1/16" w protokole calowym — na granicy; ten sam odczyt w mm — '
        'poza (1,5875 > 1,5)', () {
      final mm = unitToMm(0.0625, LengthUnit.inch);
      expect(mm, closeTo(1.5875, 1e-12));
      expect(
          _v(_check(centerline: mm, unit: LengthUnit.inch),
              FlangeCriterion.centerline),
          CheckVerdict.ok);
      expect(_v(_check(centerline: mm), FlangeCriterion.centerline),
          CheckVerdict.fail);
    });

    test('tuż ponad 1/16": 0,063" → poza tolerancją', () {
      expect(
          _v(
              _check(
                  centerline: unitToMm(0.063, LengthUnit.inch),
                  unit: LengthUnit.inch),
              FlangeCriterion.centerline),
          CheckVerdict.fail);
    });

    test('równoległość w calach: różnica dokładnie 1/32" → OK', () {
      final gaps = [0.1, 0.13125, 0.11, 0.12]
          .map((g) => unitToMm(g, LengthUnit.inch))
          .toList();
      expect(
          _v(_check(gaps: gaps, unit: LengthUnit.inch),
              FlangeCriterion.parallelism),
          CheckVerdict.ok);
    });

    test('własna granica w mm → wartość calowa to dokładne przeliczenie', () {
      final l = DualLimit.entered(1.0, LengthUnit.mm);
      expect(l.inch, closeTo(1 / 25.4, 1e-12));
      final li = DualLimit.entered(0.05, LengthUnit.inch);
      expect(li.mm, closeTo(1.27, 1e-12));
      expect(li.limitMm(LengthUnit.mm), li.limitMm(LengthUnit.inch));
    });

    test('formatowanie: ułamki do 1/64, przecinek w PL, kropka w EN', () {
      expect(formatInch(1 / 16, en: false), '1/16"');
      expect(formatInch(1 / 8, en: false), '1/8"');
      expect(formatInch(1.5, en: false), '1 1/2"');
      expect(formatInch(1 / 25.4, en: false), '0,039"');
      expect(formatInch(1 / 25.4, en: true), '0.039"');
      expect(formatLimit(kPcc1Centerline, LengthUnit.mm, en: false),
          '1,5 mm (1/16")');
      expect(formatLimit(kPcc1Parallelism, LengthUnit.inch, en: true),
          '1/32" (0.8 mm)');
      expect(formatLength(1.5875, LengthUnit.inch, en: false), '0,0625"');
      expect(fieldText(2.5, LengthUnit.mm, en: false), '2,5');
      expect(fieldText(null, LengthUnit.mm, en: false), '');
    });
  });

  group('4 vs 8 punktów', () {
    test('DN ≥ 300 → 8 punktów, mniejsze → 4', () {
      expect(recommendedGapPoints(250), 4);
      expect(recommendedGapPoints(300), 8);
      expect(recommendedGapPoints(null), 4);
    });

    test('4 → 8: odczyty z 0/90/180/270° na parzystych punktach', () {
      const m = FlangeMeasurements(gapsMm: [1, 2, 3, 4]);
      final m8 = m.withGapPoints(8);
      expect(m8.gapsMm, [1, null, 2, null, 3, null, 4, null]);
      expect(gapPointAngle(2, 8), 90);
    });

    test('8 → 4: zostają odczyty z 0/90/180/270°', () {
      const m = FlangeMeasurements(gapsMm: [1, 9, 2, 9, 3, 9, 4, 9]);
      expect(m.withGapPoints(4).gapsMm, [1, 2, 3, 4]);
    });

    test('klin widoczny tylko w 8 punktach: 4 punkty OK, 8 — poza', () {
      final four = _check(gaps: const [3.0, 3.2, 3.0, 3.2]);
      expect(_v(four, FlangeCriterion.parallelism), CheckVerdict.ok);
      final eight =
          _check(gaps: const [3.0, 2.2, 3.2, 3.1, 3.0, 3.0, 3.2, 3.0]);
      expect(_v(eight, FlangeCriterion.parallelism), CheckVerdict.fail);
    });

    test('8 punktów: brak jednego odczytu → brak', () {
      final c = _check(gaps: const [3.0, 3.1, 3.0, 3.1, 3.0, 3.1, 3.0, null]);
      expect(_v(c, FlangeCriterion.parallelism), CheckVerdict.missing);
    });
  });

  group('werdykt protokołu', () {
    test('wszystko w granicach i odhaczone → zgodny', () {
      expect(_allOk().evaluate().verdict, ProtocolVerdict.accepted);
    });

    test('komplet odhaczeń bez pomiarów → niekompletny, nie zielony', () {
      final c = _check(checked: FlangeChecklistItem.values.toSet());
      expect(c.evaluate().verdict, ProtocolVerdict.incomplete);
    });

    test('pomiary OK, jeden punkt listy nieodhaczony → niekompletny', () {
      final c = _allOk().copyWith(
          checked: FlangeChecklistItem.values.toSet()
            ..remove(FlangeChecklistItem.lubrication));
      expect(c.evaluate().verdict, ProtocolVerdict.incomplete);
    });

    test('jedno kryterium poza → niezgodny, nawet przy brakach', () {
      final c = _check(centerline: 2);
      expect(c.evaluate().verdict, ProtocolVerdict.rejected);
    });

    test('liczba śrub 4–64, wielokrotność 4; błędna blokuje zielony', () {
      expect(isValidBoltCount(4), isTrue);
      expect(isValidBoltCount(64), isTrue);
      expect(isValidBoltCount(6), isFalse);
      expect(isValidBoltCount(0), isFalse);
      expect(isValidBoltCount(68), isFalse);
      final c = _allOk()
          .copyWith(joint: _allOk().joint.copyWith(boltCount: () => 10));
      expect(c.problems, [FlangeDataProblem.boltCount]);
      expect(c.evaluate().verdict, ProtocolVerdict.incomplete);
    });

    test('zerowa tolerancja (wyczyszczone pole) blokuje zielony', () {
      final c = _allOk().copyWith(
          tolerances: FlangeTolerances.pcc1
              .copyWith(centerline: DualLimit.entered(0, LengthUnit.mm)));
      expect(c.problems, contains(FlangeDataProblem.tolerances));
      expect(c.evaluate().of(FlangeCriterion.centerline).verdict,
          CheckVerdict.missing);
      expect(c.evaluate().verdict, ProtocolVerdict.incomplete);
    });

    test('ostrzejsza tolerancja zakładu zmienia werdykt', () {
      final strict = FlangeTolerances.pcc1
          .copyWith(centerline: DualLimit.entered(0.8, LengthUnit.mm));
      expect(strict.isPcc1, isFalse);
      final c = _allOk().copyWith(tolerances: strict);
      expect(c.evaluate().verdict, ProtocolVerdict.rejected);
    });
  });

  group('duplikat „jak poprzedni”', () {
    test('dane połączenia zostają, pomiary/odhaczenia/uwagi znikają', () {
      final src = _allOk().copyWith(
        notes: 'uwaga',
        unit: LengthUnit.inch,
        joint: _allOk().joint.copyWith(tag: 'L-101-F1', rating: 'CL300'),
        measurements: _allOk()
            .measurements
            .copyWith(gapsMm: const [1, 1, 1, 1, 1, 1, 1, 1]),
      );
      final d = src.duplicate(id: 'y', date: '2026-10-17', now: 5);
      expect(d.id, 'y');
      expect(d.joint.tag, 'L-101-F2');
      expect(d.joint.rating, 'CL300');
      expect(d.joint.gasketThicknessMm, 4.5);
      expect(d.joint.boltCount, 8);
      expect(d.joint.date, '2026-10-17');
      expect(d.measurements.isEmpty, isTrue);
      expect(d.measurements.gapPointCount, 8);
      expect(d.checked, isEmpty);
      expect(d.notes, '');
      expect(d.unit, LengthUnit.inch);
      expect(d.evaluate().verdict, ProtocolVerdict.incomplete);
    });

    test('następne oznaczenie', () {
      expect(nextTag('L-101-F1'), 'L-101-F2');
      expect(nextTag('K09'), 'K10');
      expect(nextTag('12-F9-a'), '12-F10-a');
      expect(nextTag('bez cyfr'), 'bez cyfr');
      expect(nextTag(''), '');
    });
  });

  group('JSON', () {
    test('w obie strony — komplet pól', () {
      final src = _allOk().copyWith(
        notes: 'Uszczelka spiralna, łączniki z atestem',
        unit: LengthUnit.inch,
        createdAt: 1,
        updatedAt: 2,
        tolerances: FlangeTolerances.pcc1
            .copyWith(rotation: DualLimit.entered(2, LengthUnit.mm)),
        joint: const FlangeJoint(
          tag: 'L-101-F1',
          dn: 300,
          rating: 'CL300',
          gasketType: 'spiralna',
          gasketThicknessMm: 4.5,
          boltGrade: 'A193 B7 / A194 2H',
          boltCount: 16,
          location: 'Płock, rack 3',
          fitter: 'Jan Spawacz',
          date: '2026-10-17',
        ),
      );
      final back = decodeFlangeChecks(encodeFlangeChecks([src]));
      expect(back, hasLength(1));
      expect(back.single.toJson(), src.toJson());
      expect(back.single.evaluate().verdict, src.evaluate().verdict);
      expect(back.single.tolerances.isPcc1, isFalse);
    });

    test('uszkodzony JSON → pusta lista zamiast wyjątku', () {
      for (final raw in [
        null,
        '',
        '{',
        'null',
        '42',
        '"x"',
        '[1, 2]',
        '{"v":1,"checks":"x"}',
        '{"v":1}',
      ]) {
        expect(decodeFlangeChecks(raw), isEmpty, reason: '$raw');
      }
    });

    test('zepsuty wpis pomijany, reszta zostaje; złe pola → domyślne', () {
      final raw = '{"v":1,"checks":['
          '{"id":""},'
          '{"noId":true},'
          '{"id":"a","joint":"x","measurements":{"gapsMm":[1,"z",-3],'
          '"centerlineMm":"1","force":"??"},"checked":["faces","zzz"],'
          '"unit":"furlong","tolerances":{"centerline":{"mm":-1}}},'
          '{"id":"a"}'
          ']}';
      final list = decodeFlangeChecks(raw);
      expect(list, hasLength(1));
      final c = list.single;
      expect(c.id, 'a');
      expect(c.joint.tag, '');
      expect(c.measurements.gapsMm, [1, null, null, null]);
      expect(c.measurements.centerlineMm, isNull);
      expect(c.measurements.force, isNull);
      expect(c.checked, {FlangeChecklistItem.faces});
      expect(c.unit, LengthUnit.mm);
      expect(c.tolerances.isPcc1, isTrue);
    });
  });
}
