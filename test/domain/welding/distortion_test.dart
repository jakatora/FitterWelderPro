// Skurcz poprzeczny spoiny czołowej (Spraragen–Ettinger) i wymiar przed
// spawaniem. Liczby policzone ręcznie (tg 30° = 0,5773502692):
//  • rowek V 60°, t 10, d 2, c 1,5:
//      A_w = 2·10 + 8,5²·tg 30° = 20 + 72,25·0,57735 = 61,7136 mm²
//      A_w/t = 6,1714 mm; 0,2·A_w/t = 1,2343; 0,05·d = 0,1
//      S = 1,3343 mm → w górę do 0,1 → „1,4”;
//  • rowek X 60°, t 20, d 2, c 2: A_w = 2·20 + 2·9²·tg 30° = 133,5307 mm²,
//      S = 0,2·6,6765 + 0,1 = 1,4353 mm; ten sam rowek V: 227,0615 mm²,
//      S = 2,3706 mm (X ma mniej stopiwa → mniejszy skurcz);
//  • rowek ½V 45°, t 12, d 2, c 1,5: A_w = 24 + ½·10,5²·1 = 79,125 mm²,
//      S = 0,2·6,59375 + 0,1 = 1,41875 mm → „1,5”;
//  • łańcuch: 1000 + 2 × 1,4 = 1002,8 → w górę do 0,5 → 1003,0 (+0,2);
//    3 spoiny: 1000 + 3 × 1,4 = 1004,2 → 1004,5 ≥ surowe 1004,003
//    (zaokrąglenie do najbliższej 1,3 dawało 1003,9 → 1004,0 — za mało).
// Zgodność z regułą TWI (rowek V 60°: 1,5–3 mm na spoinę) dla t 12–20 mm.

import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';

import 'package:cut_list_app/data/distortion_tips.dart';
import 'package:cut_list_app/domain/quotes/weld_geometry.dart';
import 'package:cut_list_app/domain/welding/distortion.dart';

ButtShrinkageInput _in({
  ButtGroove groove = ButtGroove.v,
  double t = 10,
  double d = 2,
  double c = 1.5,
  double a = 60,
}) =>
    ButtShrinkageInput(
        groove: groove, thicknessMm: t, gapMm: d, rootFaceMm: c, angleDeg: a);

void main() {
  final tan30 = math.tan(math.pi / 6);

  group('Skurcz poprzeczny — wzór i pole rowka', () {
    test('rowek V 60°, t 10: przykład policzony ręcznie', () {
      final r = computeButtShrinkage(_in())!;
      final area = 2 * 10 + 8.5 * 8.5 * tan30;
      expect(r.areaMm2, closeTo(area, 1e-9));
      expect(r.areaMm2, closeTo(61.7136, 1e-4));
      expect(r.meanWidthMm, closeTo(6.1714, 1e-4));
      expect(r.areaTermMm, closeTo(1.2343, 1e-4));
      expect(r.gapTermMm, closeTo(0.1, 1e-12));
      expect(r.shrinkageMm, closeTo(1.3343, 1e-4));
      expect(r.shrinkageAllowanceMm, 1.4);
    });

    test('rowek X liczony z weld_geometry: mniej stopiwa niż V', () {
      final x = computeButtShrinkage(
          _in(groove: ButtGroove.x, t: 20, d: 2, c: 2))!;
      final v = computeButtShrinkage(_in(t: 20, d: 2, c: 2))!;
      expect(x.areaMm2, closeTo(2 * 20 + 2 * 9 * 9 * tan30, 1e-9));
      expect(x.shrinkageMm, closeTo(1.4353, 1e-4));
      expect(v.areaMm2, closeTo(227.0615, 1e-4));
      expect(v.shrinkageMm, closeTo(2.3706, 1e-4));
      expect(x.shrinkageMm, lessThan(v.shrinkageMm));
    });

    test('rowek ½V 45°: pole z grooveAreaHalfV', () {
      final r = computeButtShrinkage(
          _in(groove: ButtGroove.halfV, t: 12, d: 2, c: 1.5, a: 45))!;
      expect(r.areaMm2, closeTo(79.125, 1e-9));
      expect(r.areaMm2,
          grooveAreaHalfV(h: 12, gap: 2, rootFace: 1.5, bevelDeg: 45));
      expect(r.shrinkageMm, closeTo(1.41875, 1e-9));
      expect(r.shrinkageAllowanceMm, 1.5);
    });

    test('pole rowka = model wycen bez nadlewów (V i X)', () {
      // V: plateButtVolumes = rowek + nadlew lica + nadlew grani.
      const t = 12.0, d = 2.5, c = 1.5, a = 60.0;
      final pv = plateButtVolumes(
          t: t,
          lengthMm: 1,
          groove: GrooveType.v,
          gap: d,
          rootFace: c,
          includedAngleDeg: a);
      final capV = reinforcementArea(
          grooveTopWidthV(t: t, gap: d, rootFace: c, includedAngleDeg: a) +
              2 * kCapOverlapMm,
          kCapHeightMm);
      final pen = reinforcementArea(d + 2, kRootReinforcementMm);
      expect(buttGrooveAreaMm2(_in(t: t, d: d, c: c, a: a)),
          closeTo(pv.totalMm3 - capV - pen, 1e-9));

      // X: plateButtVolumes = rowek + dwa nadlewy lica.
      final px = plateButtVolumes(
          t: t,
          lengthMm: 1,
          groove: GrooveType.x,
          gap: d,
          rootFace: c,
          includedAngleDeg: a);
      final halfOpen = (t - c) / 2;
      final capX = reinforcementArea(
          d + 2 * halfOpen * tan30 + 2 * kCapOverlapMm, kCapHeightMm);
      expect(buttGrooveAreaMm2(_in(groove: ButtGroove.x, t: t, d: d, c: c, a: a)),
          closeTo(px.totalMm3 - 2 * capX, 1e-9));
    });

    test('jednostki: te same współczynniki dla mm i cali', () {
      final mm = computeButtShrinkage(_in())!;
      const inch = 25.4;
      final inInput = _in(t: 10 / inch, d: 2 / inch, c: 1.5 / inch);
      final areaIn = buttGrooveAreaMm2(inInput);
      expect(areaIn, closeTo(mm.areaMm2 / (inch * inch), 1e-12));
      final sIn = spraragenEttingerShrinkage(
          areaW: areaIn, thickness: 10 / inch, gap: 2 / inch);
      expect(sIn * inch, closeTo(mm.shrinkageMm, 1e-12));
      // Postać „5,08·A/t + 1,27·d” = 25,4 × współczynniki: mm tylko przy
      // wejściu w calach; z wejściem w mm zawyża 25,4 raza.
      final mixedFromInches = 5.08 * areaIn / (10 / inch) + 1.27 * (2 / inch);
      expect(mixedFromInches, closeTo(mm.shrinkageMm, 1e-12));
      final mixedFromMm = 5.08 * mm.areaMm2 / 10 + 1.27 * 2;
      expect(mixedFromMm / mm.shrinkageMm, closeTo(inch, 1e-9));
    });

    test('rowek V 60°, t 12–20 mm, d 2–3 mm: w zakresie reguły TWI 1,5–3 mm',
        () {
      for (final t in [12.0, 14.0, 16.0, 18.0, 20.0]) {
        for (final d in [2.0, 2.5, 3.0]) {
          final s = computeButtShrinkage(_in(t: t, d: d))!.shrinkageMm;
          expect(s, inInclusiveRange(kTwiButtV60MinMm, kTwiButtV60MaxMm),
              reason: 't $t, d $d → $s');
        }
      }
    });

    test('większa szczelina i większy kąt → większy skurcz', () {
      final base = computeButtShrinkage(_in())!.shrinkageMm;
      expect(computeButtShrinkage(_in(d: 3))!.shrinkageMm, greaterThan(base));
      expect(computeButtShrinkage(_in(a: 70))!.shrinkageMm, greaterThan(base));
    });
  });

  group('Skurcz poprzeczny — walidacja', () {
    test('puste / nieczytelne pole (NaN) to problem, nie wynik', () {
      for (final i in [
        _in(t: double.nan),
        _in(d: double.nan),
        _in(c: double.nan),
        _in(a: double.nan),
      ]) {
        expect(shrinkageProblems(i), isNotEmpty);
        expect(computeButtShrinkage(i), isNull);
      }
    });

    test('granice pól', () {
      expect(shrinkageProblems(_in(t: 0)), contains(ShrinkageProblem.thickness));
      expect(shrinkageProblems(_in(t: -5)), contains(ShrinkageProblem.thickness));
      expect(shrinkageProblems(_in(t: 101)), contains(ShrinkageProblem.thickness));
      expect(shrinkageProblems(_in(t: double.infinity)),
          contains(ShrinkageProblem.thickness));
      expect(shrinkageProblems(_in(d: -0.1)), [ShrinkageProblem.gap]);
      expect(shrinkageProblems(_in(d: 11)), [ShrinkageProblem.gap]);
      expect(shrinkageProblems(_in(d: 0)), isEmpty);
      expect(shrinkageProblems(_in(c: 10)), [ShrinkageProblem.rootFace]);
      expect(shrinkageProblems(_in(c: -1)), [ShrinkageProblem.rootFace]);
      expect(shrinkageProblems(_in(c: 0)), isEmpty);
      expect(shrinkageProblems(_in(a: 5)), [ShrinkageProblem.angle]);
      expect(shrinkageProblems(_in(a: 130)), [ShrinkageProblem.angle]);
      expect(shrinkageProblems(_in(groove: ButtGroove.halfV, a: 70)),
          [ShrinkageProblem.angle]);
      expect(shrinkageProblems(_in(groove: ButtGroove.halfV, a: 45)), isEmpty);
    });

    test('żadnego NaN ani ∞ w całym zakresie pól', () {
      for (final g in ButtGroove.values) {
        for (final t in [0.5, 3.0, 10.0, 40.0, 100.0]) {
          for (final d in [0.0, 1.0, 4.0, 10.0]) {
            for (final a in [10.0, 30.0, 60.0, 120.0]) {
              final i = _in(groove: g, t: t, d: d, c: 0, a: a);
              final r = computeButtShrinkage(i);
              if (r == null) continue;
              expect(r.shrinkageMm.isFinite, isTrue);
              expect(r.shrinkageMm, greaterThan(0));
            }
          }
        }
      }
    });
  });

  group('Wymiar przed spawaniem', () {
    test('1000 + 2 × 1,3 → 1002,6 → 1003,0 (w górę o 0,4)', () {
      final r = computePreWeld(const PreWeldInput(
          finalLengthMm: 1000, buttWelds: 2, shrinkagePerButtMm: 1.3))!;
      expect(r.buttShrinkageMm, closeTo(2.6, 1e-12));
      expect(r.totalShrinkageMm, closeTo(2.6, 1e-12));
      expect(r.rawLengthMm, closeTo(1002.6, 1e-9));
      expect(r.preWeldLengthMm, 1003.0);
      expect(r.roundingAddMm, closeTo(0.4, 1e-9));
    });

    test('wynik dokładnie na 0,5 mm nie jest podbijany', () {
      final r = computePreWeld(const PreWeldInput(
          finalLengthMm: 1000, buttWelds: 2, shrinkagePerButtMm: 1.25))!;
      expect(r.preWeldLengthMm, 1002.5);
      expect(r.roundingAddMm, 0);
      final five = computePreWeld(const PreWeldInput(
          finalLengthMm: 1000, buttWelds: 5, shrinkagePerButtMm: 1.3))!;
      expect(five.preWeldLengthMm, 1006.5);
    });

    test('zaokrąglenie W GÓRĘ — nigdy mniej niż wymiar z naddatkiem', () {
      expect(roundUpToStep(1002.0, 0.5), 1002.0);
      expect(roundUpToStep(1002.01, 0.5), 1002.5);
      expect(roundUpToStep(1002.49, 0.5), 1002.5);
      expect(roundUpToStep(1002.51, 0.5), 1003.0);
      // Szum zmiennoprzecinkowy nie podbija o cały krok.
      expect(roundUpToStep(1002.5 + 1e-10, 0.5), 1002.5);
      expect(roundUpToStep(1003.9000000000001, 0.5), 1004.0);
      for (var k = 0; k < 400; k++) {
        final s = k * 0.037;
        final r = computePreWeld(PreWeldInput(
            finalLengthMm: 750, buttWelds: 3, shrinkagePerButtMm: s))!;
        expect(r.preWeldLengthMm, greaterThanOrEqualTo(r.rawLengthMm - 1e-6));
        expect(r.roundingAddMm, lessThan(kPreWeldStepMm));
        expect((r.preWeldLengthMm / 0.5) % 1, 0);
      }
    });

    test('spoiny pachwinowe wg TWI 0,8 mm; bez czołowych skurcz czołowy '
        'nie jest potrzebny', () {
      final r = computePreWeld(const PreWeldInput(
          finalLengthMm: 500,
          buttWelds: 0,
          shrinkagePerButtMm: double.nan,
          filletWelds: 2))!;
      expect(r.filletShrinkageMm, closeTo(1.6, 1e-12));
      expect(r.buttShrinkageMm, 0);
      expect(r.preWeldLengthMm, 502.0);
      final mixed = computePreWeld(const PreWeldInput(
          finalLengthMm: 2000,
          buttWelds: 1,
          shrinkagePerButtMm: 2.4,
          filletWelds: 1))!;
      expect(mixed.totalShrinkageMm, closeTo(3.2, 1e-12));
      expect(mixed.preWeldLengthMm, 2003.5);
    });

    test('walidacja łańcucha', () {
      List<PreWeldProblem> p(
              {double l = 1000, double n = 2, double s = 1.3, double f = 0}) =>
          preWeldProblems(PreWeldInput(
              finalLengthMm: l,
              buttWelds: n,
              shrinkagePerButtMm: s,
              filletWelds: f));
      expect(p(), isEmpty);
      expect(p(l: double.nan), [PreWeldProblem.finalLength]);
      expect(p(l: 0), [PreWeldProblem.finalLength]);
      expect(p(l: 100001), [PreWeldProblem.finalLength]);
      expect(p(n: 1.5), contains(PreWeldProblem.buttWelds));
      expect(p(n: -1), contains(PreWeldProblem.buttWelds));
      expect(p(n: double.nan), contains(PreWeldProblem.buttWelds));
      expect(p(f: double.nan), [PreWeldProblem.filletWelds]);
      expect(p(n: 0, f: 0), [PreWeldProblem.noWelds]);
      expect(p(s: double.nan), [PreWeldProblem.shrinkagePerButt]);
      expect(p(s: -0.1), [PreWeldProblem.shrinkagePerButt]);
      expect(p(s: 21), [PreWeldProblem.shrinkagePerButt]);
      expect(p(n: 0, f: 1, s: double.nan), isEmpty);
      expect(
          computePreWeld(const PreWeldInput(
              finalLengthMm: 1000,
              buttWelds: 2,
              shrinkagePerButtMm: double.nan)),
          isNull);
    });
  });

  group('Naddatek nigdy za mały', () {
    test('skurcz do łańcucha w górę do 0,1 — do najbliższej dawało za mały '
        'wymiar', () {
      final s = computeButtShrinkage(_in())!;
      expect(s.shrinkageMm, closeTo(1.3343, 1e-4));
      expect(s.shrinkageAllowanceMm, 1.4);
      PreWeldResult chain(double perWeld) => computePreWeld(PreWeldInput(
          finalLengthMm: 1000, buttWelds: 3, shrinkagePerButtMm: perWeld))!;
      // Ile naprawdę trzeba: 1000 + 3 × 1,3343 = 1004,003.
      final needed = 1000 + 3 * s.shrinkageMm;
      expect(needed, closeTo(1004.003, 1e-3));
      // Stare zaokrąglenie do najbliższej (1,3): 1003,9 → 1004,0 < 1004,003.
      final nearest = (s.shrinkageMm * 10).round() / 10;
      expect(nearest, 1.3);
      expect(chain(nearest).preWeldLengthMm, 1004.0);
      expect(chain(nearest).preWeldLengthMm, lessThan(needed));
      // Teraz: 3 × 1,4 = 4,2 → 1004,2 → 1004,5 ≥ 1004,003.
      final now = chain(s.shrinkageAllowanceMm);
      expect(now.totalShrinkageMm, closeTo(4.2, 1e-12));
      expect(now.preWeldLengthMm, 1004.5);
      expect(now.preWeldLengthMm, greaterThanOrEqualTo(needed));
    });

    test('dla każdego rowka i liczby spoin wymiar ≥ wymiar z wartości surowej',
        () {
      for (final g in ButtGroove.values) {
        for (final t in [4.0, 8.0, 12.5, 17.0, 25.0, 40.0]) {
          for (final d in [0.0, 1.5, 2.0, 3.0]) {
            final s = computeButtShrinkage(_in(groove: g, t: t, d: d, c: 1,
                a: g == ButtGroove.halfV ? 45 : 60))!;
            expect(s.shrinkageAllowanceMm,
                greaterThanOrEqualTo(s.shrinkageMm - 1e-12));
            expect(s.shrinkageAllowanceMm - s.shrinkageMm, lessThan(0.1));
            for (var n = 1; n <= 12; n++) {
              final r = computePreWeld(PreWeldInput(
                  finalLengthMm: 1234.5,
                  buttWelds: n.toDouble(),
                  shrinkagePerButtMm: s.shrinkageAllowanceMm))!;
              expect(r.preWeldLengthMm,
                  greaterThanOrEqualTo(1234.5 + n * s.shrinkageMm - 1e-9),
                  reason: '${g.name} t $t d $d n $n');
            }
          }
        }
      }
    });

    test('pomiar w górę do 0,01 mm; dokładna wartość bez zmian', () {
      PreWeldResult r(double s) => computePreWeld(PreWeldInput(
          finalLengthMm: 1000, buttWelds: 2, shrinkagePerButtMm: s))!;
      expect(r(1.23).perButtMm, 1.23);
      expect(r(1.23).buttShrinkageMm, closeTo(2.46, 1e-12));
      expect(r(1.234).perButtMm, 1.24);
      expect(r(1.234).buttShrinkageMm, closeTo(2.48, 1e-12));
      expect(r(1.8).perButtMm, 1.8);
      expect(ceilToTenth(1.3000000001), 1.3);
      expect(ceilToHundredth(1.2300000001), 1.23);
    });
  });

  group('Ostrzeżenia poza zakresem wzoru', () {
    test('rowek prawie I i cienka blacha → ostrzeżenie, wynik zostaje', () {
      final nearlyI = _in(t: 10, c: 9.9);
      expect(shrinkageWarnings(nearlyI), [ShrinkageWarning.nearlySquare]);
      expect(computeButtShrinkage(nearlyI), isNotNull);
      final thin = _in(t: 2.5, c: 0.5, d: 1);
      expect(shrinkageWarnings(thin), [ShrinkageWarning.thinPlate]);
      expect(computeButtShrinkage(thin), isNotNull);
      expect(shrinkageWarnings(_in(t: 2, c: 1.8, d: 0.5)),
          [ShrinkageWarning.nearlySquare, ShrinkageWarning.thinPlate]);
      expect(shrinkageWarnings(_in()), isEmpty);
      // X i ½V — ta sama reguła.
      expect(shrinkageWarnings(_in(groove: ButtGroove.x, t: 20, c: 17)),
          [ShrinkageWarning.nearlySquare]);
      expect(
          shrinkageWarnings(
              _in(groove: ButtGroove.halfV, t: 12, c: 11, a: 45)),
          [ShrinkageWarning.nearlySquare]);
    });

    test('progi przyjęte w aplikacji: (t − c)/t < 0,2 i t < 3 mm', () {
      expect(kNearlySquareOpenRatio, 0.2);
      expect(kThinPlateMm, 3);
      // Na progu — bez ostrzeżenia.
      expect(shrinkageWarnings(_in(t: 10, c: 8)), isEmpty);
      expect(shrinkageWarnings(_in(t: 10, c: 8.01)),
          [ShrinkageWarning.nearlySquare]);
      expect(shrinkageWarnings(_in(t: 3, c: 1)), isEmpty);
      expect(shrinkageWarnings(_in(t: 2.99, c: 1)),
          [ShrinkageWarning.thinPlate]);
      // Błędne dane — brak wyniku, brak ostrzeżeń.
      expect(shrinkageWarnings(_in(t: double.nan)), isEmpty);
      for (final w in ShrinkageWarning.values) {
        final pl = shrinkageWarningText(w, en: false);
        final en = shrinkageWarningText(w, en: true);
        expect(pl, contains('próg przyjęty w aplikacji'));
        expect(en, contains('threshold set in the app'));
      }
    });
  });

  group('Tekst do udostępnienia', () {
    final shrink = computeButtShrinkage(_in())!;
    final pre = computePreWeld(PreWeldInput(
        finalLengthMm: 1000,
        buttWelds: 2,
        shrinkagePerButtMm: shrink.shrinkageAllowanceMm))!;
    final measures =
        measuresFor(DistortionElement.plateButt, DistortionKind.angular);

    test('PL: liczby z przecinkiem, wszystkie części, zastrzeżenie', () {
      final s = distortionShareText(
        en: false,
        shrinkage: shrink,
        preWeld: pre,
        element: DistortionElement.plateButt,
        kind: DistortionKind.angular,
        measures: measures,
      );
      expect(s, contains('rowek V 60°, t = 10 mm, d = 2 mm, c = 1,5 mm'));
      expect(s, contains('A_w = 61,7 mm²'));
      expect(s, contains('S = 1,334 mm → 1,4 mm na spoinę (w górę do 0,1 mm)'));
      expect(s, contains('Spoiny czołowe: 2 × 1,4 mm (szacunek) = 2,8 mm'));
      expect(s, contains('Suma skurczu 2,8 mm'));
      expect(s, contains('Zestaw przed spawaniem: 1003,0 mm'));
      expect(s, contains('Sytuacja: Blachy doczołowo — Kątowe'));
      for (final m in measures) {
        expect(s, contains(m.titlePl));
        expect(s, contains(m.whyPl));
      }
      expect(s, contains(distortionDisclaimer(en: false)));
      expect(s, isNot(contains('NaN')));
      expect(s, isNot(contains('Infinity')));
    });

    test('EN: kropka dziesiętna, te same liczby', () {
      final s = distortionShareText(
        en: true,
        shrinkage: shrink,
        preWeld: pre,
        measuredShrinkage: true,
        element: DistortionElement.plateButt,
        kind: DistortionKind.angular,
        measures: measures,
      );
      expect(s, contains('single-V 60°, t = 10 mm, d = 2 mm, c = 1.5 mm'));
      expect(s, contains('S = 1.334 mm → 1.4 mm per weld (rounded up to 0.1 mm)'));
      expect(s, contains('Butt welds: 2 × 1.4 mm (measured) = 2.8 mm'));
      expect(s, contains('Set up before welding: 1003.0 mm'));
      expect(s, contains(distortionDisclaimer(en: true)));
    });

    test('pomiar z 2 miejscami: rachunek w tekście zgodny co do cyfry', () {
      String text(double perWeld, {double fillets = 0}) =>
          distortionShareText(
            en: false,
            measuredShrinkage: true,
            preWeld: computePreWeld(PreWeldInput(
                finalLengthMm: 1000,
                buttWelds: 2,
                shrinkagePerButtMm: perWeld,
                filletWelds: fillets))!,
          );
      // Było: „2 × 1,23 mm (pomiar) = 2,5 mm”.
      final a = text(1.23);
      expect(a, contains('Spoiny czołowe: 2 × 1,23 mm (pomiar) = 2,46 mm'));
      expect(a, contains('Suma skurczu 2,46 mm'));
      expect(a, contains('Zestaw przed spawaniem: 1002,5 mm'));
      // Trzy miejsca we wpisie: w górę do 0,01 i powiedziane wprost.
      final b = text(1.234, fillets: 1);
      expect(
          b,
          contains('Spoiny czołowe: 2 × 1,24 mm (pomiar, w górę do 0,01 mm) '
              '= 2,48 mm'));
      expect(b, contains('Spoiny pachwinowe: 1 × 0,8 mm (TWI) = 0,8 mm'));
      expect(b, contains('Suma skurczu 3,28 mm'));
      expect(b, contains('Zestaw przed spawaniem: 1003,5 mm'));
      // Każda linia „n × s = suma” liczy się co do cyfry.
      final line = RegExp(r'(\d+) × (\d+(?:,\d+)?) mm \([^)]*\) = (\d+(?:,\d+)?) mm');
      for (final s in [a, b]) {
        for (final m in line.allMatches(s)) {
          double p(String x) => double.parse(x.replaceAll(',', '.'));
          expect(int.parse(m.group(1)!) * p(m.group(2)!),
              closeTo(p(m.group(3)!), 1e-9),
              reason: m.group(0));
        }
      }
    });

    test('ostrzeżenie trafia do tekstu', () {
      final s = distortionShareText(
          en: false, shrinkage: computeButtShrinkage(_in(t: 10, c: 9.9)));
      expect(s,
          contains(shrinkageWarningText(ShrinkageWarning.nearlySquare, en: false)));
    });

    test('brak wyniku = brak sekcji, nie zero', () {
      final s = distortionShareText(en: false);
      expect(s, isNot(contains('Skurcz poprzeczny')));
      expect(s, isNot(contains('Zestaw przed spawaniem')));
      expect(s, contains(distortionDisclaimer(en: false)));
    });
  });
}
