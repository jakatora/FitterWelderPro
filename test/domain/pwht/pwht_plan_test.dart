// Plan PWHT — wartości z tabel norm (ASME B31.3-2020/2024, ASME B31.1-2022)
// i arytmetyka planu. Liczby w oczekiwaniach przepisane z tekstu norm —
// zmiana któregokolwiek wymaga zmiany źródła w pwht_tables.dart.

import 'package:flutter_test/flutter_test.dart';

import 'package:cut_list_app/domain/pwht/pwht_plan.dart';
import 'package:cut_list_app/domain/pwht/pwht_plan_text.dart';

PwhtPlan _plan(
  PwhtMaterial m,
  double t, {
  PwhtCode code = PwhtCode.asmeB313,
  double? od,
  double? weld,
}) =>
    planPwht(PwhtInput(
      code: code,
      material: m,
      thicknessMm: t,
      outsideDiameterMm: od,
      weldWidthMm: weld,
    ))!;

void main() {
  group('kompletność tabel', () {
    for (final code in PwhtCode.values) {
      test('${code.name}: każda grupa ma wiersz ze źródłem', () {
        expect(pwhtMaterialsFor(code), PwhtMaterial.values);
        for (final m in PwhtMaterial.values) {
          final e = pwhtTableEntry(code, m)!;
          expect(e.code, code);
          expect(
              e.source,
              contains(code == PwhtCode.asmeB313
                  ? 'B31.3-2020/2024'
                  : 'B31.1-2022'));
          if (!e.notRequiredByTable) {
            expect(e.holdRange, isNotNull, reason: m.name);
            expect(e.holdTime, isNotNull, reason: m.name);
          }
        }
      });
    }
  });

  group('temperatura wytrzymania (Tab. 331.1.1 / 132.1.1-1)', () {
    for (final code in PwhtCode.values) {
      test('${code.name}: zakresy °C i °F jak w tabeli', () {
        PwhtTempRange r(PwhtMaterial m) => pwhtTableEntry(code, m)!.holdRange!;
        expect([r(PwhtMaterial.p1).minC, r(PwhtMaterial.p1).maxC], [595, 650]);
        expect(
            [r(PwhtMaterial.p1).minF, r(PwhtMaterial.p1).maxF], [1100, 1200]);
        expect([r(PwhtMaterial.p3).minC, r(PwhtMaterial.p3).maxC], [595, 650]);
        expect([r(PwhtMaterial.p4).minC, r(PwhtMaterial.p4).maxC], [650, 705]);
        expect(
            [r(PwhtMaterial.p4).minF, r(PwhtMaterial.p4).maxF], [1200, 1300]);
        expect(
            [r(PwhtMaterial.p5a).minC, r(PwhtMaterial.p5a).maxC], [675, 760]);
        expect(
            [r(PwhtMaterial.p5a).minF, r(PwhtMaterial.p5a).maxF], [1250, 1400]);
        expect(
            [r(PwhtMaterial.p15e).minC, r(PwhtMaterial.p15e).maxC], [705, 775]);
        expect([r(PwhtMaterial.p15e).minF, r(PwhtMaterial.p15e).maxF],
            [1300, 1425]);
        expect(pwhtTableEntry(code, PwhtMaterial.p8)!.holdRange, isNull);
      });
    }

    test('temperatura w planie = środek zakresu w dół do 5 °C', () {
      expect(_plan(PwhtMaterial.p1, 30).holdTempC, 620);
      expect(_plan(PwhtMaterial.p4, 30).holdTempC, 675);
      expect(_plan(PwhtMaterial.p5a, 30).holdTempC, 715);
      expect(_plan(PwhtMaterial.p15e, 30).holdTempC, 740);
    });
  });

  group('czas wytrzymania', () {
    int hold(PwhtMaterial m, double t) => _plan(m, t).holdMinutes!;

    test('P-No 1/3/4/5A: 1 h/25 mm, minimum 15 min', () {
      expect(hold(PwhtMaterial.p1, 5), 15); // 12 min → minimum 15
      expect(hold(PwhtMaterial.p1, 6.25), 15); // dokładnie 15
      expect(hold(PwhtMaterial.p1, 6.3), 16); // 15,12 → w górę 16
      expect(hold(PwhtMaterial.p1, 10), 24);
      expect(hold(PwhtMaterial.p3, 19), 46); // 45,6 → 46
      expect(hold(PwhtMaterial.p4, 25), 60);
      expect(hold(PwhtMaterial.p5a, 50), 120);
    });

    test('powyżej 50 mm: 2 h + 15 min za każde rozpoczęte 25 mm', () {
      expect(hold(PwhtMaterial.p1, 50.5), 135);
      expect(hold(PwhtMaterial.p1, 75), 135);
      expect(hold(PwhtMaterial.p1, 75.1), 150);
      expect(hold(PwhtMaterial.p4, 100), 150);
      expect(hold(PwhtMaterial.p5a, 125), 165);
    });

    test('P-No 15E: minimum 30 min, 1 h/25 mm do 125 mm, potem +15 min', () {
      expect(hold(PwhtMaterial.p15e, 4), 30);
      expect(hold(PwhtMaterial.p15e, 12.5), 30);
      expect(hold(PwhtMaterial.p15e, 13), 32); // 31,2 → 32
      expect(hold(PwhtMaterial.p15e, 60), 144); // bez przełomu przy 50 mm
      expect(hold(PwhtMaterial.p15e, 125), 300);
      expect(hold(PwhtMaterial.p15e, 126), 315);
      expect(hold(PwhtMaterial.p15e, 150), 315);
      expect(hold(PwhtMaterial.p15e, 151), 330);
    });

    test('B31.1 ma te same czasy', () {
      for (final t in [5.0, 19, 50, 51, 130]) {
        for (final m in [PwhtMaterial.p1, PwhtMaterial.p15e]) {
          expect(hold(m, t.toDouble()),
              _plan(m, t.toDouble(), code: PwhtCode.asmeB311).holdMinutes,
              reason: '${m.name} $t');
        }
      }
    });
  });

  group('czy PWHT wymagane — B31.3 Tab. 331.1.3', () {
    test('P-No 1: każda grubość zwolniona warunkowo', () {
      for (final t in [3.0, 19, 25, 40, 100]) {
        expect(_plan(PwhtMaterial.p1, t.toDouble()).verdict,
            PwhtVerdict.exemptIfConditionsMet,
            reason: '$t mm');
      }
    });

    test('P-No 1: warunki zależne od grubości (5 mm, 25 mm)', () {
      List<String> conds(double t) => _plan(PwhtMaterial.p1, t)
          .entry
          .exemption!
          .conditionsFor(t)
          .map((c) => c.text.pl)
          .toList();
      expect(conds(5), hasLength(1)); // tylko „nie gdy wymaga projekt/WPS”
      expect(conds(5.5), hasLength(2)); // + wielowarstwowo
      expect(conds(25), hasLength(2));
      expect(conds(25.5), hasLength(3)); // + podgrzewanie 95 °C
      expect(conds(25.5).first, contains('95 °C'));
    });

    test('P-No 3: ≤ 16 mm warunkowo, > 16 mm wymagane; 95 °C od > 13 mm', () {
      expect(_plan(PwhtMaterial.p3, 16).verdict,
          PwhtVerdict.exemptIfConditionsMet);
      expect(_plan(PwhtMaterial.p3, 16.1).verdict, PwhtVerdict.required);
      final ex = _plan(PwhtMaterial.p3, 14).entry.exemption!;
      expect(ex.conditionsFor(13).any((c) => c.text.pl.contains('95 °C')),
          isFalse);
      expect(
          ex.conditionsFor(14).any((c) => c.text.pl.contains('95 °C')), isTrue);
      expect(ex.conditions.any((c) => c.text.pl.contains('0,25 %')), isTrue);
    });

    test('P-No 4 i 5A: ≤ 16 mm warunkowo (C ≤ 0,15 %), > 16 mm wymagane', () {
      for (final m in [PwhtMaterial.p4, PwhtMaterial.p5a]) {
        expect(_plan(m, 16).verdict, PwhtVerdict.exemptIfConditionsMet,
            reason: m.name);
        expect(_plan(m, 17).verdict, PwhtVerdict.required, reason: m.name);
        expect(
            _plan(m, 10)
                .entry
                .exemption!
                .conditions
                .any((c) => c.text.pl.contains('≤ 0,15 %')),
            isTrue,
            reason: m.name);
      }
      expect(
          _plan(PwhtMaterial.p4, 10).entry.exemption!.conditions.first.text.pl,
          contains('120 °C'));
    });

    test('P91 (P-No 15E): zawsze wymagane, także cienka ścianka', () {
      for (final t in [1.0, 6, 13, 50, 200]) {
        final p = _plan(PwhtMaterial.p15e, t.toDouble());
        expect(p.verdict, PwhtVerdict.required, reason: '$t mm');
        expect(p.entry.exemption, isNull);
      }
      expect(pwhtVerdictText(_plan(PwhtMaterial.p15e, 6), english: false),
          'PWHT wymagane — tabela nie przewiduje zwolnienia');
    });

    test('austenityczna P-No 8: tabela nie wymaga, brak parametrów', () {
      final p = _plan(PwhtMaterial.p8, 40, od: 273, weld: 20);
      expect(p.verdict, PwhtVerdict.notRequiredByTable);
      expect(p.hasCycleData, isFalse);
      expect(p.holdMinutes, isNull);
      expect(p.cycle, isNull);
      expect(p.rateRule, isNull);
      expect(p.soakBandMm, isNull);
      expect(p.controlZones, isNull);
    });
  });

  group('czy PWHT wymagane — B31.1-2022 Tab. 132.2-1', () {
    test('P-No 3: podgrzewanie 95 °C dopiero > 16 mm', () {
      final ex =
          _plan(PwhtMaterial.p3, 14, code: PwhtCode.asmeB311).entry.exemption!;
      expect(ex.conditionsFor(16).any((c) => c.text.pl.contains('95 °C')),
          isFalse);
      expect(_plan(PwhtMaterial.p3, 16.5, code: PwhtCode.asmeB311).verdict,
          PwhtVerdict.required);
    });

    test('P-No 4: C ≤ 0,20 %; P-No 5A: C ≤ 0,15 %, 205 °C', () {
      final p4 = _plan(PwhtMaterial.p4, 10, code: PwhtCode.asmeB311);
      expect(
          p4.entry.exemption!.conditions
              .any((c) => c.text.pl.contains('≤ 0,20 %')),
          isTrue);
      final p5 = _plan(PwhtMaterial.p5a, 10, code: PwhtCode.asmeB311);
      expect(
          p5.entry.exemption!.conditions
              .any((c) => c.text.pl.contains('≤ 0,15 %')),
          isTrue);
      expect(p5.entry.exemption!.conditions.first.text.pl, contains('205 °C'));
    });

    test('P91: bez zwolnień; P-No 1: zwolnienie warunkowe', () {
      expect(_plan(PwhtMaterial.p15e, 5, code: PwhtCode.asmeB311).verdict,
          PwhtVerdict.required);
      expect(_plan(PwhtMaterial.p1, 60, code: PwhtCode.asmeB311).verdict,
          PwhtVerdict.exemptIfConditionsMet);
    });
  });

  group('szybkości §331.1.4 / §132.5: 335 °C/h ÷ (t[in]/2), maks. 335', () {
    for (final code in PwhtCode.values) {
      test(code.name, () {
        final r = pwhtRateRuleFor(code)!;
        expect(r.controlTempC, 315);
        expect(r.maxHeatingRate(10), 335);
        expect(r.maxHeatingRate(50.8), closeTo(335, 1e-9));
        expect(r.maxHeatingRate(100), closeTo(170.18, 0.005));
        expect(r.maxCoolingRate(200), closeTo(85.09, 0.005));
        // Brak dolnej granicy w regule.
        expect(r.floorCPerH, isNull);
        expect(r.maxHeatingRate(400), closeTo(42.545, 0.001));
      });
    }
  });

  group('cykl', () {
    test('P-No 1, 100 mm: rampy i suma', () {
      final c = _plan(PwhtMaterial.p1, 100).cycle!;
      expect(c.controlTempC, 315);
      expect(c.holdTempC, 620);
      expect(c.heatingRateCPerH, closeTo(170.18, 0.005));
      expect(c.rampUpHours, closeTo(305 / 170.18, 1e-3));
      expect(c.holdMinutes, 150);
      expect(c.totalHours, closeTo(2 * 305 / 170.18 + 2.5, 1e-3));
    });

    test('P91, 20 mm: limit 335 °C/h', () {
      final c = _plan(PwhtMaterial.p15e, 20).cycle!;
      expect(c.heatingRateCPerH, 335);
      expect(c.coolingRateCPerH, 335);
      expect(c.rampUpHours, closeTo((740 - 315) / 335, 1e-9));
      expect(c.holdMinutes, 48);
    });
  });

  group('pasmo wytrzymania §331.2.6 / §132.7: 3 × t', () {
    test('3t niezależnie od spoiny', () {
      expect(_plan(PwhtMaterial.p4, 20).soakBandMm, 60);
      expect(_plan(PwhtMaterial.p4, 20, weld: 30).soakBandMm, 60);
      expect(
          _plan(PwhtMaterial.p15e, 12, code: PwhtCode.asmeB311).soakBandMm, 36);
    });
  });

  group('strefy regulacji AWS D10.10:2021 (rura pozioma)', () {
    int? zones(double? od) => d1010ControlZones(od)?.zones;

    test('progi NPS 6 / 12 / 18 / 30', () {
      expect(zones(60.3), 1);
      expect(zones(168.3), 1);
      expect(zones(168.4), 2); // między NPS 6 a 8 → wyżej
      expect(zones(219.1), 2);
      expect(zones(323.9), 2);
      expect(zones(355.6), 3);
      expect(zones(457.2), 3);
      expect(zones(508), 4);
      expect(zones(762), 4);
      expect(zones(813), isNull);
      expect(d1010ControlZones(813), isNotNull);
    });

    test('brak średnicy → brak stref', () {
      expect(d1010ControlZones(null), isNull);
      expect(d1010ControlZones(0), isNull);
      expect(_plan(PwhtMaterial.p4, 20).controlZones, isNull);
      expect(_plan(PwhtMaterial.p4, 20, od: 114.3).controlZones!.zones, 1);
    });
  });

  group('dane wejściowe', () {
    test('grubość ≤ 0 / NaN → brak planu', () {
      for (final t in [0.0, -3, double.nan, double.infinity]) {
        expect(
            planPwht(PwhtInput(
                code: PwhtCode.asmeB313,
                material: PwhtMaterial.p1,
                thicknessMm: t.toDouble())),
            isNull,
            reason: '$t');
      }
    });
  });

  group('tekst planu', () {
    test('PL: źródło, wartości, warunki i zastrzeżenie', () {
      final text =
          pwhtPlanText(_plan(PwhtMaterial.p4, 12, od: 168.3), english: false);
      expect(text, startsWith('Plan PWHT — Fitter Welder Pro'));
      expect(text, contains('ASME B31.3-2020/2024, Table 331.1.1'));
      expect(text, contains('650–705 °C (1200–1300 °F)'));
      expect(text, contains('Warunek zwolnienia: Zastosowano obowiązkowe'));
      expect(text, contains('ASME B31.3-2020/2024 §331.1.4'));
      expect(text, contains('Strefy regulacji (rura pozioma): 1'));
      expect(text, endsWith(pwhtDisclaimer(english: false)));
    });

    test('EN: tłumaczenie bez polskich etykiet', () {
      final text = pwhtPlanText(_plan(PwhtMaterial.p15e, 30), english: true);
      expect(text, startsWith('PWHT plan — Fitter Welder Pro'));
      expect(text, contains('PWHT required — the table gives no exemption'));
      expect(text, contains('Min. holding time: 1 h 12 min'));
      expect(text, isNot(contains('Temperatura')));
    });
  });
}
