// Czas stygnięcia t8/5 wg EN 1011-2:2001 zał. D.
//
// Liczby przeliczone ręcznie ze wzorów (kalkulator, 6 cyfr):
//  • 3D, Q = 1 kJ/mm, T0 = 20 °C, F3 = 1:
//      (6700 − 100) · 1 · (1/480 − 1/780) = 6600 · 300/374 400 = 5,288462 s
//  • 2D, Q = 1 kJ/mm, T0 = 20 °C, d = 10 mm, F2 = 1:
//      (4300 − 86) · 10⁵ · 1/100 · (1/480² − 1/780²)
//      = 4 214 000 · 378 000 / (230 400 · 608 400) = 11,363566 s
//  • d_t, Q = 1 kJ/mm, T0 = 20 °C:
//      √(4214/6600 · 10⁵ · (1/480 + 1/780)) = √214,87 = 14,658605 mm
//  • 3D, Q = 1, T0 = 100 °C, F3 = 0,9 (ścieg wypełniający):
//      6200 · (1/400 − 1/700) · 0,9 = 5,978571 s; d_t = 15,659467 mm
//  • Okno 5–15 s, T0 = 100 °C, d = 20 mm, F = 0,9: przejście 3D→2D przy
//    Q* = d²/C = 1,6312 kJ/mm; 3D: Q = 5/5,9786 … = 0,8363; 2D: górna
//    granica √(15/β) = 2,0230 kJ/mm → Q ∈ 0,836–2,023 kJ/mm.
//  • Q = 1, d = 20, F = 0,9: t8/5 = 5 s przy T0 = 38,53 °C; przy 300 °C
//    t8/5 = 14,22 s < 15 → górna granica T0 poza sprawdzanym zakresem.
//
// Przykłady ze źródeł (odtworzone liczbowo tymi samymi wzorami):
//  • MIGAL.CO (kalkulator wg EN 1011-2 zał. D), 2D: 30 V, 450 A,
//    35 cm/min, k 0,8, napawanie, d 20 mm, T0 150 °C → E 2,3143 kJ/mm,
//    Q 1,8514 kJ/mm, d_t 22,359 mm → 2D, t8/5 = 18,155 s (strona: 18,16 s).
//  • MIGAL.CO, 3D odwrotnie: d 20 mm, T0 150 °C, t8/5 9 s, napawanie →
//    Q 1,1471 kJ/mm (7,846 s na kJ/mm), d_t 17,599 mm → 3D.
//  • Rontescu i in. (2008), 2D: TIG 15 V, 153 A, 14 cm/min, k 0,6 →
//    Q 0,590 kJ/mm; T0 200 °C, d 10 mm, F2 1 → ok. 10 s (wzór: 9,984 s;
//    d_t 13,34 mm).

import 'package:flutter_test/flutter_test.dart';

import 'package:cut_list_app/domain/welding/cooling_time.dart';
import 'package:cut_list_app/domain/welding/heat_input.dart';

void main() {
  group('wzory zał. D', () {
    test('wzór 3D: Q 1 kJ/mm, T0 20 °C → 5,29 s', () {
      expect(t85ThreeD(heatInputKjMm: 1, preheatC: 20),
          closeTo(5.288462, 1e-5));
      // Liniowo w Q i w F3.
      expect(t85ThreeD(heatInputKjMm: 2, preheatC: 20, f3: 0.67),
          closeTo(2 * 0.67 * 5.288462, 1e-5));
    });

    test('wzór 2D: Q 1 kJ/mm, T0 20 °C, d 10 mm → 11,36 s', () {
      expect(t85TwoD(heatInputKjMm: 1, preheatC: 20, thicknessMm: 10),
          closeTo(11.363566, 1e-5));
      // Kwadratowo w Q, odwrotnie do d².
      expect(t85TwoD(heatInputKjMm: 2, preheatC: 20, thicknessMm: 20),
          closeTo(11.363566, 1e-5));
    });

    test('grubość przejściowa d_t: Q 1, T0 20 °C → 14,66 mm', () {
      expect(transitionThicknessMm(heatInputKjMm: 1, preheatC: 20),
          closeTo(14.658605, 1e-5));
    });

    test('przy d = d_t oba wzory dają ten sam t8/5 (F2 = F3 = 1)', () {
      for (final (q, t0) in [(0.6, 20.0), (1.0, 100.0), (2.5, 150.0)]) {
        final dt = transitionThicknessMm(heatInputKjMm: q, preheatC: t0)!;
        expect(
            t85TwoD(heatInputKjMm: q, preheatC: t0, thicknessMm: dt),
            closeTo(t85ThreeD(heatInputKjMm: q, preheatC: t0)!, 1e-9));
        expect(transitionHeatInputKjMm(preheatC: t0, thicknessMm: dt),
            closeTo(q, 1e-9));
      }
    });

    test('tabl. D.1: współczynniki kształtu', () {
      expect((WeldShape.beadOnPlate.f2Min, WeldShape.beadOnPlate.f3),
          (1.0, 1.0));
      expect((WeldShape.buttFillRun.f2Min, WeldShape.buttFillRun.f3),
          (0.9, 0.9));
      expect(
          (
            WeldShape.filletCorner.f2Min,
            WeldShape.filletCorner.f2Max,
            WeldShape.filletCorner.f3
          ),
          (0.67, 0.9, 0.67));
      expect(
          (
            WeldShape.filletTee.f2Min,
            WeldShape.filletTee.f2Max,
            WeldShape.filletTee.f3
          ),
          (0.45, 0.67, 0.67));
      expect(WeldShape.filletTee.hasF2Range, isTrue);
      expect(WeldShape.filletCorner.hasF2Range, isTrue);
      expect(WeldShape.buttFillRun.hasF2Range, isFalse);
    });

    test('t2D/t3D = (F2/F3)·(d_t/d)²', () {
      for (final (q, t0, d) in [(0.8, 20.0, 8.0), (1.5, 120.0, 30.0)]) {
        final dt = transitionThicknessMm(heatInputKjMm: q, preheatC: t0)!;
        final t2 = t85TwoD(
            heatInputKjMm: q, preheatC: t0, thicknessMm: d, f2: 0.9)!;
        final t3 = t85ThreeD(heatInputKjMm: q, preheatC: t0, f3: 0.67)!;
        expect(t2 / t3, closeTo(0.9 / 0.67 * (dt / d) * (dt / d), 1e-9));
      }
    });

    test('dane bez sensu → null, nie NaN', () {
      expect(t85ThreeD(heatInputKjMm: 0, preheatC: 20), isNull);
      expect(t85ThreeD(heatInputKjMm: 1, preheatC: 500), isNull);
      expect(t85ThreeD(heatInputKjMm: double.nan, preheatC: 20), isNull);
      expect(t85TwoD(heatInputKjMm: 1, preheatC: 20, thicknessMm: 0), isNull);
      expect(transitionThicknessMm(heatInputKjMm: -1, preheatC: 20), isNull);
      expect(
          coolingTime(
              heatInputKjMm: 1,
              preheatC: 20,
              thicknessMm: -5,
              shape: WeldShape.beadOnPlate),
          isNull);
    });
  });

  group('przykłady ze źródeł', () {
    test('MIGAL 2D: 30 V, 450 A, 350 mm/min, MAG, d 20, T0 150 → 18,16 s',
        () {
      final q = heatInputKJPerMm(
          volts: 30,
          amps: 450,
          travelMmPerMin: 350,
          standard: HeatInputStandard.en1011,
          efficiency: WeldingProcess.gmaw.thermalEfficiency)!;
      expect(q, closeTo(1.8514, 1e-4));
      final r = coolingTime(
          heatInputKjMm: q,
          preheatC: 150,
          thicknessMm: 20,
          shape: WeldShape.beadOnPlate)!;
      expect(r.transitionThicknessMm, closeTo(22.359, 1e-3));
      expect(r.flow, HeatFlow.twoD);
      expect(r.t85MinS, closeTo(18.16, 0.01));
    });

    test('MIGAL 3D odwrotnie: d 20, T0 150, t8/5 9 s → Q 1,147 kJ/mm', () {
      // Okno „≤ 9 s” — górna granica przedziału Q to Q dla 9 s.
      final s = heatInputRangesForWindow(
              preheatC: 150,
              thicknessMm: 20,
              shape: WeldShape.beadOnPlate,
              max: 9)
          .single;
      expect(s.clippedLow, isTrue);
      expect(s.max, closeTo(1.1471, 1e-4));
      final r = coolingTime(
          heatInputKjMm: s.max,
          preheatC: 150,
          thicknessMm: 20,
          shape: WeldShape.beadOnPlate)!;
      expect(r.flow, HeatFlow.threeD);
      expect(r.transitionThicknessMm, closeTo(17.599, 1e-3));
      expect(t85ThreeD(heatInputKjMm: 1, preheatC: 150),
          closeTo(7.846, 1e-3));
    });

    test('Rontescu 2008: TIG 15 V, 153 A, 140 mm/min, d 10, T0 200 → ~10 s',
        () {
      final q = heatInputKJPerMm(
          volts: 15,
          amps: 153,
          travelMmPerMin: 140,
          standard: HeatInputStandard.en1011,
          efficiency: WeldingProcess.gtaw.thermalEfficiency)!;
      expect(q, closeTo(0.590, 1e-3));
      final r = coolingTime(
          heatInputKjMm: q,
          preheatC: 200,
          thicknessMm: 10,
          shape: WeldShape.beadOnPlate)!;
      expect(r.flow, HeatFlow.twoD);
      expect(r.transitionThicknessMm, closeTo(13.34, 0.01));
      expect(r.t85MinS, closeTo(9.984, 1e-3));
    });
  });

  group('wybór 2D / 3D', () {
    test('d 20 mm > d_t 14,66 → 3D; ścieg wypełniający F3 0,9 → 4,76 s', () {
      final r = coolingTime(
          heatInputKjMm: 1,
          preheatC: 20,
          thicknessMm: 20,
          shape: WeldShape.buttFillRun)!;
      expect(r.flow, HeatFlow.threeD);
      expect(r.transitionThicknessMm, closeTo(14.658605, 1e-5));
      expect(r.t85MinS, closeTo(0.9 * 5.288462, 1e-5));
      expect(r.isRange, isFalse);
    });

    test('d 10 mm < d_t 14,66 → 2D; F2 0,9 → 10,23 s', () {
      final r = coolingTime(
          heatInputKjMm: 1,
          preheatC: 20,
          thicknessMm: 10,
          shape: WeldShape.buttFillRun)!;
      expect(r.flow, HeatFlow.twoD);
      expect(r.t85MinS, closeTo(0.9 * 11.363566, 1e-5));
      expect(r.t85MaxS, r.t85MinS);
    });

    test('złącze teowe w 2D: F2 0,45–0,67 → przedział wyniku', () {
      final r = coolingTime(
          heatInputKjMm: 1,
          preheatC: 20,
          thicknessMm: 8,
          shape: WeldShape.filletTee)!;
      expect(r.flow, HeatFlow.twoD);
      expect(r.isRange, isTrue);
      expect(r.t85MinS, closeTo(7.9900, 1e-3));
      expect(r.t85MaxS, closeTo(11.8962, 1e-3));
    });

    test('złącze narożne w 2D: F2 0,67–0,9 → przedział wyniku', () {
      final r = coolingTime(
          heatInputKjMm: 1,
          preheatC: 20,
          thicknessMm: 10,
          shape: WeldShape.filletCorner)!;
      expect(r.flow, HeatFlow.twoD);
      expect(r.t85MinS, closeTo(0.67 * 11.363566, 1e-5));
      expect(r.t85MaxS, closeTo(0.9 * 11.363566, 1e-5));
    });

    test('złącze teowe w 3D: jedna liczba (F3 0,67)', () {
      final r = coolingTime(
          heatInputKjMm: 1,
          preheatC: 20,
          thicknessMm: 30,
          shape: WeldShape.filletTee)!;
      expect(r.flow, HeatFlow.threeD);
      expect(r.isRange, isFalse);
      expect(r.t85MinS, closeTo(0.67 * 5.288462, 1e-5));
    });

    test('T0 100 °C, Q 1, d 20, wypełnienie → 3D, 5,98 s', () {
      final r = coolingTime(
          heatInputKjMm: 1,
          preheatC: 100,
          thicknessMm: 20,
          shape: WeldShape.buttFillRun)!;
      expect(r.flow, HeatFlow.threeD);
      expect(r.t85MinS, closeTo(5.978571, 1e-5));
      expect(r.transitionThicknessMm, closeTo(15.659467, 1e-5));
    });
  });

  group('monotoniczność', () {
    // Gdy dolne F2 ≥ F3 (wszystkie rodzaje poza teowym), dolny t8/5 rośnie
    // z Q i z T0 także przez przejście 3D → 2D.
    const shapes = [
      WeldShape.beadOnPlate,
      WeldShape.buttFillRun,
      WeldShape.filletCorner,
    ];
    for (final shape in shapes) {
      test('${shape.name}: więcej Q → dłuższy t8/5', () {
        for (final d in [6.0, 12.0, 25.0, 60.0]) {
          double? prev;
          for (var q = 0.2; q <= 5.0; q += 0.05) {
            final t = coolingTime(
                    heatInputKjMm: q,
                    preheatC: 80,
                    thicknessMm: d,
                    shape: shape)!
                .t85MinS;
            if (prev != null) expect(t, greaterThan(prev));
            prev = t;
          }
        }
      });

      test('${shape.name}: wyższe T0 → dłuższy t8/5', () {
        for (final d in [6.0, 12.0, 25.0, 60.0]) {
          double? prev;
          for (var t0 = 0.0; t0 <= 300; t0 += 5) {
            final t = coolingTime(
                    heatInputKjMm: 1.2,
                    preheatC: t0,
                    thicknessMm: d,
                    shape: shape)!
                .t85MinS;
            if (prev != null) expect(t, greaterThan(prev));
            prev = t;
          }
        }
      });
    }

    test('w obrębie jednego modelu rośnie też dla złącza teowego', () {
      double? prev;
      for (var q = 0.2; q <= 1.5; q += 0.05) {
        final r = coolingTime(
            heatInputKjMm: q,
            preheatC: 20,
            thicknessMm: 40,
            shape: WeldShape.filletTee)!;
        expect(r.flow, HeatFlow.threeD);
        if (prev != null) expect(r.t85MinS, greaterThan(prev));
        prev = r.t85MinS;
      }
    });
  });

  group('werdykt okna', () {
    test('w oknie / za krótko / za długo / brak / błędne okno', () {
      expect(checkT85Window(6, 6, min: 5, max: 15), T85Verdict.inWindow);
      expect(checkT85Window(5, 5, min: 5, max: 15), T85Verdict.inWindow);
      expect(checkT85Window(4.9, 4.9, min: 5, max: 15), T85Verdict.tooShort);
      expect(checkT85Window(15.1, 15.1, min: 5, max: 15), T85Verdict.tooLong);
      expect(checkT85Window(6, 6), T85Verdict.notSet);
      expect(checkT85Window(6, 6, min: 15, max: 5), T85Verdict.invalidWindow);
      expect(checkT85Window(6, 6, min: 0, max: 5), T85Verdict.invalidWindow);
    });

    test('jedna granica wystarcza', () {
      expect(checkT85Window(6, 6, min: 5), T85Verdict.inWindow);
      expect(checkT85Window(4, 4, min: 5), T85Verdict.tooShort);
      expect(checkT85Window(12, 12, max: 10), T85Verdict.tooLong);
    });

    test('przedział częściowo poza oknem → partly', () {
      expect(checkT85Window(8, 12, min: 5, max: 10), T85Verdict.partly);
      expect(checkT85Window(4, 7, min: 5, max: 10), T85Verdict.partly);
      expect(checkT85Window(11, 14, min: 5, max: 10), T85Verdict.tooLong);
    });
  });

  group('rozwiązanie odwrotne', () {
    test('Q dla okna 5–15 s (T0 100 °C, d 20, wypełnienie) = 0,836–2,023',
        () {
      final ranges = heatInputRangesForWindow(
          preheatC: 100,
          thicknessMm: 20,
          shape: WeldShape.buttFillRun,
          min: 5,
          max: 15);
      expect(ranges, hasLength(1));
      final s = ranges.single;
      expect(s.min, closeTo(0.8363, 1e-3));
      expect(s.max, closeTo(2.0230, 1e-3));
      expect(s.clippedLow, isFalse);
      expect(s.clippedHigh, isFalse);
    });

    test('Q z rozwiązania trafia w okno — dla każdego rodzaju spoiny', () {
      for (final shape in WeldShape.values) {
        for (final (t0, d) in [(20.0, 8.0), (100.0, 20.0), (150.0, 40.0)]) {
          final ranges = heatInputRangesForWindow(
              preheatC: t0, thicknessMm: d, shape: shape, min: 5, max: 15);
          expect(ranges, isNotEmpty, reason: '${shape.name} T0=$t0 d=$d');
          for (final s in ranges) {
            for (final q in [s.min * 1.001, s.mid, s.max * 0.999]) {
              final r = coolingTime(
                  heatInputKjMm: q,
                  preheatC: t0,
                  thicknessMm: d,
                  shape: shape)!;
              expect(
                  checkT85Window(r.t85MinS, r.t85MaxS, min: 5, max: 15),
                  T85Verdict.inWindow,
                  reason: '${shape.name} T0=$t0 d=$d Q=$q');
            }
            // Tuż za granicą — już poza oknem.
            if (!s.clippedLow) {
              final r = coolingTime(
                  heatInputKjMm: s.min * 0.99,
                  preheatC: t0,
                  thicknessMm: d,
                  shape: shape)!;
              expect(
                  checkT85Window(r.t85MinS, r.t85MaxS, min: 5, max: 15),
                  isNot(T85Verdict.inWindow));
            }
          }
        }
      }
    });

    test('granice Q dają t8/5 równe granicom okna', () {
      final s = heatInputRangesForWindow(
              preheatC: 50,
              thicknessMm: 30,
              shape: WeldShape.beadOnPlate,
              min: 5,
              max: 10)
          .single;
      double t(double q) => coolingTime(
              heatInputKjMm: q,
              preheatC: 50,
              thicknessMm: 30,
              shape: WeldShape.beadOnPlate)!
          .t85MinS;
      expect(t(s.min), closeTo(5, 1e-6));
      expect(t(s.max), closeTo(10, 1e-6));
    });

    test('T0 dla okna 5–15 s (Q 1, d 20, wypełnienie): od 38,5 °C, '
        'górna granica poza sprawdzanym zakresem', () {
      final ranges = preheatRangesForWindow(
          heatInputKjMm: 1,
          thicknessMm: 20,
          shape: WeldShape.buttFillRun,
          min: 5,
          max: 15);
      expect(ranges, hasLength(1));
      final s = ranges.single;
      expect(s.min, closeTo(38.53, 0.01));
      expect(s.clippedLow, isFalse);
      expect(s.clippedHigh, isTrue);
      expect(s.max, kT0SearchMaxC);
    });

    test('T0 z rozwiązania trafia w okno', () {
      final ranges = preheatRangesForWindow(
          heatInputKjMm: 1.2,
          thicknessMm: 20,
          shape: WeldShape.filletCorner,
          min: 5,
          max: 10);
      expect(ranges, isNotEmpty);
      for (final s in ranges) {
        final r = coolingTime(
            heatInputKjMm: 1.2,
            preheatC: s.mid,
            thicknessMm: 20,
            shape: WeldShape.filletCorner)!;
        expect(checkT85Window(r.t85MinS, r.t85MaxS, min: 5, max: 10),
            T85Verdict.inWindow);
      }
    });

    test('okno nie do osiągnięcia → pusta lista', () {
      // Bardzo wąskie okno poniżej najmniejszego t8/5 w zakresie T0.
      expect(
          preheatRangesForWindow(
              heatInputKjMm: 3,
              thicknessMm: 10,
              shape: WeldShape.beadOnPlate,
              min: 1,
              max: 2),
          isEmpty);
      expect(
          heatInputRangesForWindow(
              preheatC: 20,
              thicknessMm: 20,
              shape: WeldShape.beadOnPlate,
              min: 15,
              max: 5),
          isEmpty);
    });
  });

  test('prędkość spawania dla Q: 28 V, 250 A, k 0,8, Q 0,96 → 350 mm/min',
      () {
    expect(
        travelSpeedForHeatInput(
            volts: 28, amps: 250, efficiency: 0.8, heatInputKjMm: 0.96),
        closeTo(350, 1e-9));
    expect(
        travelSpeedForHeatInput(
            volts: 28, amps: 250, efficiency: 0.8, heatInputKjMm: 0),
        isNull);
  });
}
