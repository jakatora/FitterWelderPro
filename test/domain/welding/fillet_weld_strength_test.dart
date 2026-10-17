// Nośność spoiny pachwinowej wg EN 1993-1-8 (4.5.3.2 / 4.5.3.3).
//
// Liczby przeliczone ręcznie (kalkulator, 7 cyfr), niezależnie od kodu:
//  • S235: fvw,d = 360 / (√3 · 0,8 · 1,25) = 360 / 1,7320508 = 207,8461 MPa.
//    a = 4, l = 100, 1 spoina: l_eff = 100 − 2·4 = 92 mm, A = 368 mm²,
//    Fw,Rd = 207,8461 · 368 = 76 487,4 N = 76,487 kN.
//    Kierunkowa w poprzek (θ = 90°): σ⊥ = τ⊥ = F/(√2·A) →
//    √(σ⊥² + 3τ⊥²) = √2·F/A ≤ 360/(0,8·1,25) = 360 →
//    F = 360 · 368 / √2 = 93 677,5 N; 93,6775 / 76,4874 = 1,224745 = √(3/2).
//    Warunek σ⊥ ≤ 0,9·360/1,25 = 259,2 MPa → F ≤ 259,2·√2·368 = 134 896 N
//    (nie decyduje).
//  • S355: fu = 490 (EN 1993-1-1 tabl. 3.1 po AC:2009), βw = 0,9:
//    fvw,d = 490 / (√3 · 1,125) = 490 / 1,9485572 = 251,4682 MPa;
//    a = 5, l = 200, 2 spoiny: l_eff = 190, A = 5 · 380 = 1900 mm² →
//    477 789,6 N.
//  • Obwodowa: S235, rura D = 60,3, a = 3: l = π·60,3 = 189,4380 mm,
//    A = 568,3141 mm² → uproszczona 118,121 kN, osiowo (90°)
//    360/(√2)·568,3141 = 144 669 N.
//  • Wymagane a, S235, l = 100, 1 spoina, uproszczona:
//    F_Ed = 70 kN → 207,8461·a·(100 − 2a) = 70 000 → 2a² − 100a + 336,788 = 0
//    → a = (100 − √7305,70)/4 = (100 − 85,4734)/4 = 3,6317 → 3,7 mm (a4).
//    Sprawdzenie: a = 3,6 → 69 437 N < 70 000; a = 3,7 → 71 212 N.
//    F_Ed = 50 kN → a = 2,534 < 3 → decyduje minimum 3 mm (58 612 N).
//    F_Ed = 200 kN → a_max = l/8 = 12,5: 207,8461·12,5·75 = 194 856 N
//    < 200 000 → trzeba dłuższej spoiny.
//  • Długie połączenie (4.11): S235, a = 3, l = 600 > 150a = 450:
//    βLw = 1,2 − 0,2·600/450 = 0,933333; F = 207,8461·3·594·0,933333 =
//    345 689,7 N.

import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';

import 'package:cut_list_app/domain/welding/fillet_weld_strength.dart';

FilletWeldInput _lin({
  WeldSteelGrade steel = WeldSteelGrade.s235,
  double a = 4,
  double l = 100,
  int n = 1,
  double t = 10,
  FilletMethod method = FilletMethod.simplified,
  double angle = 0,
}) =>
    FilletWeldInput(
      steel: steel,
      throatMm: a,
      maxPartThicknessMm: t,
      lengthMm: l,
      welds: n,
      method: method,
      angleDeg: angle,
    );

FilletWeldInput _tube({
  double a = 3,
  double d = 60.3,
  FilletMethod method = FilletMethod.simplified,
}) =>
    FilletWeldInput(
      steel: WeldSteelGrade.s235,
      throatMm: a,
      maxPartThicknessMm: 10,
      layout: WeldLayout.circumferential,
      tubeOdMm: d,
      method: method,
      // Ignorowany dla spoiny obwodowej — zawsze 90°.
      angleDeg: 0,
    );

void main() {
  group('tabele', () {
    test('fu (EN 1993-1-1 tabl. 3.1, t ≤ 40 mm) i βw (EN 1993-1-8 tabl. 4.1)',
        () {
      final table = {
        for (final s in WeldSteelGrade.values) s.label: (s.fuMpa, s.betaW)
      };
      expect(table, {
        'S235': (360.0, 0.80),
        'S275': (430.0, 0.85),
        'S355': (490.0, 0.90),
        'S420': (520.0, 1.00),
        'S460': (540.0, 1.00),
      });
      expect(kWeldGammaM2, 1.25);
    });

    test('fvw,d S235 = 207,85 MPa, S355 = 251,47 MPa', () {
      expect(simplifiedShearStrengthMpa(WeldSteelGrade.s235),
          closeTo(207.8461, 1e-3));
      expect(simplifiedShearStrengthMpa(WeldSteelGrade.s355),
          closeTo(251.4682, 1e-3));
    });
  });

  group('metoda uproszczona', () {
    test('S235, a 4, l 100: l_eff = l − 2a = 92 mm, Fw,Rd = 76,49 kN', () {
      final r = computeFilletWeld(_lin())!;
      expect(r.effectiveLengthPerWeldMm, 92);
      expect(r.throatAreaMm2, 368);
      expect(r.resistanceKn, closeTo(76.4874, 1e-3));
      expect(r.longJointApplied, isFalse);
    });

    test('S355, a 5, 2 × l 200: 477,79 kN', () {
      final r = computeFilletWeld(_lin(
          steel: WeldSteelGrade.s355, a: 5, l: 200, n: 2))!;
      expect(r.totalEffectiveLengthMm, 380);
      expect(r.resistanceKn, closeTo(477.7896, 1e-2));
    });

    test('obwodowa rura D 60,3, a 3: l = π·D bez odejmowania 2a, 118,12 kN',
        () {
      final r = computeFilletWeld(_tube())!;
      expect(r.weldLengthMm, closeTo(189.4380, 1e-3));
      expect(r.effectiveLengthPerWeldMm, closeTo(189.4380, 1e-3));
      expect(r.resistanceKn, closeTo(118.121, 1e-2));
    });
  });

  group('metoda kierunkowa', () {
    test('w poprzek (90°): 93,68 kN = √(3/2) × uproszczona', () {
      final simple = computeFilletWeld(_lin())!;
      final dir = computeFilletWeld(
          _lin(method: FilletMethod.directional, angle: 90))!;
      expect(dir.resistanceKn, closeTo(93.6775, 1e-3));
      expect(dir.resistanceKn / simple.resistanceKn,
          closeTo(math.sqrt(1.5), 1e-9));
      expect(dir.normalStressGoverns, isFalse);
    });

    test('wzdłuż (0°) = uproszczona; 45° pomiędzy', () {
      final simple = computeFilletWeld(_lin())!.resistanceKn;
      final along = computeFilletWeld(
              _lin(method: FilletMethod.directional, angle: 0))!
          .resistanceKn;
      final at45 = computeFilletWeld(
              _lin(method: FilletMethod.directional, angle: 45))!
          .resistanceKn;
      expect(along, closeTo(simple, 1e-9));
      // 360 / √2,5 = 227,684 MPa · 368 mm².
      expect(at45, closeTo(227.6840 * 368 / 1000, 1e-3));
      expect(at45, greaterThan(simple));
    });

    test('kierunkowa ≥ uproszczona dla każdego kąta i gatunku', () {
      for (final s in WeldSteelGrade.values) {
        for (var deg = 0; deg <= 90; deg += 5) {
          final dir = designStrengthMpa(
              s, FilletMethod.directional, deg.toDouble());
          expect(dir, greaterThanOrEqualTo(simplifiedShearStrengthMpa(s) - 1e-9),
              reason: '${s.label} $deg°');
        }
      }
    });

    test('warunek σ⊥ ≤ 0,9 fu/γM2 nie decyduje dla tabl. 4.1', () {
      for (final s in WeldSteelGrade.values) {
        expect(directionalNormalStrengthMpa(s, 90),
            greaterThan(directionalVonMisesStrengthMpa(s, 90)),
            reason: s.label);
      }
      // S235, 90°: 0,9 · 360 · √2 / 1,25 = 366,564 MPa.
      expect(directionalNormalStrengthMpa(WeldSteelGrade.s235, 90),
          closeTo(366.5642, 1e-3));
    });

    test('obwodowa: zawsze siła osiowa (90°), 144,67 kN', () {
      final r = computeFilletWeld(_tube(method: FilletMethod.directional))!;
      expect(r.input.effectiveAngleDeg, 90);
      expect(r.resistanceKn, closeTo(144.669, 1e-2));
    });
  });

  group('wymagane a', () {
    test('F_Ed 70 kN, l 100: a = 3,63 → 3,7 mm, całe a4', () {
      final req = requiredThroat(_lin(a: double.nan), 70)!;
      expect(req.status, ThroatStatus.found);
      expect(req.exactMm, closeTo(3.63165, 1e-4));
      expect(req.shownMm, 3.7);
      expect(req.wholeMm, 4);
      expect(req.shownLegMm, 5.3); // 3,7 · √2 = 5,233 → w górę 5,3
    });

    test('odwrotnie spójne: wymagane a daje F_Rd ≥ F_Ed, o 0,1 mm mniej — nie',
        () {
      for (final f in [60.0, 70.0, 100.0, 150.0, 190.0]) {
        final req = requiredThroat(_lin(), f)!;
        expect(req.status, ThroatStatus.found, reason: '$f kN');
        final at = computeFilletWeld(_lin(a: req.shownMm!))!.resistanceKn;
        expect(at, greaterThanOrEqualTo(f), reason: '$f kN');
        final below = computeFilletWeld(_lin(a: req.shownMm! - 0.1));
        if (below != null) {
          expect(below.resistanceKn, lessThan(f), reason: '$f kN');
        }
        // Dokładne a odwraca wzór na nośność.
        expect(computeFilletWeld(_lin(a: req.exactMm!))!.resistanceKn,
            closeTo(f, 1e-6),
            reason: '$f kN');
      }
    });

    test('mała siła — decyduje minimum 3 mm', () {
      final req = requiredThroat(_lin(), 50)!;
      expect(req.status, ThroatStatus.minimum);
      expect(req.shownMm, 3);
      expect(req.wholeMm, 3);
    });

    test('za duża siła — trzeba dłuższej spoiny (a_max = l/8)', () {
      final req = requiredThroat(_lin(), 200)!;
      expect(req.status, ThroatStatus.needsLongerWeld);
      expect(req.maxMm, 12.5);
      expect(req.shownMm, isNull);
    });

    test('spoina za krótka nawet dla a = 3', () {
      expect(requiredThroat(_lin(l: 35), 1)!.status, ThroatStatus.weldTooShort);
      // Rura D 8: π·8 = 25,1 mm < 30 mm — żadne a (choć 25,1/6 > 3).
      expect(requiredThroat(_tube(d: 8), 1)!.status, ThroatStatus.weldTooShort);
      expect(filletProblems(_tube(d: 8)), [FilletProblem.lengthTooShort]);
    });

    test('obwodowa: a = F/(f·π·D)', () {
      final req = requiredThroat(_tube(a: double.nan), 150)!;
      // 150 000 / (207,8461 · 189,4380) = 3,8096 → 3,9.
      expect(req.exactMm, closeTo(3.8096, 1e-3));
      expect(req.shownMm, 3.9);
      expect(req.wholeMm, 4);
    });

    test('kierunkowa w poprzek wymaga mniejszego a niż uproszczona', () {
      final s = requiredThroat(_lin(), 100)!;
      final d =
          requiredThroat(_lin(method: FilletMethod.directional, angle: 90), 100)!;
      expect(d.exactMm!, lessThan(s.exactMm!));
    });

    test('brak wyniku dla siły ≤ 0, NaN i złej geometrii', () {
      expect(requiredThroat(_lin(), 0), isNull);
      expect(requiredThroat(_lin(), -5), isNull);
      expect(requiredThroat(_lin(), double.nan), isNull);
      expect(requiredThroat(_lin(l: double.nan), 10), isNull);
      expect(requiredThroat(_lin(t: 50), 10), isNull);
    });
  });

  group('granice normy', () {
    test('a < 3 mm (4.5.2) — brak wyniku', () {
      expect(filletProblems(_lin(a: 2.9)), contains(FilletProblem.throatBelowMin));
      expect(computeFilletWeld(_lin(a: 2.9)), isNull);
      expect(filletProblems(_lin(a: 3)), isEmpty);
      // z = 4,24 → a = 2,998 < 3, mimo że „wygląda” na 3.
      expect(filletProblems(_lin(a: 4.24 / math.sqrt2)),
          contains(FilletProblem.throatBelowMin));
    });

    test('l_eff < max(30 mm; 6a) (4.5.1) — brak wyniku', () {
      // a 3: l 36 → l_eff 30 (granica, OK); l 35,9 → 29,9.
      expect(filletProblems(_lin(a: 3, l: 36)), isEmpty);
      expect(filletProblems(_lin(a: 3, l: 35.9)),
          [FilletProblem.lengthTooShort]);
      // a 8: l 64 → l_eff 48 = 6a (OK); l 63 → 47 < 48.
      expect(filletProblems(_lin(a: 8, l: 64)), isEmpty);
      expect(filletProblems(_lin(a: 8, l: 63)),
          [FilletProblem.lengthTooShort]);
    });

    test('grubość ponad 40 mm — poza tabelą fu', () {
      expect(filletProblems(_lin(t: 40)), isEmpty);
      expect(filletProblems(_lin(t: 40.5)), [FilletProblem.thicknessOver40]);
    });

    test('NaN, ujemne, zero, nieskończoność — komunikat, nie wynik', () {
      expect(filletProblems(_lin(a: double.nan)), [FilletProblem.throat]);
      expect(filletProblems(_lin(a: -4)), [FilletProblem.throat]);
      expect(filletProblems(_lin(a: double.infinity)), [FilletProblem.throat]);
      expect(filletProblems(_lin(l: 0)), [FilletProblem.length]);
      expect(filletProblems(_lin(l: -100)), [FilletProblem.length]);
      expect(filletProblems(_lin(t: double.nan)), [FilletProblem.thickness]);
      expect(filletProblems(_lin(n: 0)), [FilletProblem.welds]);
      expect(filletProblems(_tube(d: 0)), [FilletProblem.tubeOd]);
      expect(
          filletProblems(_lin(method: FilletMethod.directional, angle: 91)),
          [FilletProblem.angle]);
      expect(
          filletProblems(
              _lin(method: FilletMethod.directional, angle: double.nan)),
          [FilletProblem.angle]);
      for (final i in [
        _lin(a: double.nan),
        _lin(l: -1),
        _tube(d: double.nan),
      ]) {
        expect(computeFilletWeld(i), isNull);
      }
    });

    test('wynik zawsze skończony i dodatni', () {
      for (final s in WeldSteelGrade.values) {
        for (final m in FilletMethod.values) {
          final r = computeFilletWeld(_lin(steel: s, method: m, angle: 90))!;
          expect(r.resistanceKn.isFinite && r.resistanceKn > 0, isTrue);
        }
      }
    });
  });

  group('długie połączenie (4.11)', () {
    test('l 600 > 150a: βLw = 0,9333, 345,69 kN', () {
      final r = computeFilletWeld(_lin(a: 3, l: 600))!;
      expect(r.longJointApplied, isTrue);
      expect(r.longJointFactor, closeTo(0.933333, 1e-6));
      expect(r.resistanceKn, closeTo(345.6897, 1e-2));
    });

    test('l = 150a — bez redukcji; obwodowa i czysto poprzeczna — bez', () {
      expect(computeFilletWeld(_lin(a: 3, l: 450))!.longJointApplied, isFalse);
      expect(
          computeFilletWeld(
                  _lin(a: 3, l: 600, method: FilletMethod.directional, angle: 90))!
              .longJointApplied,
          isFalse);
      expect(computeFilletWeld(_tube(d: 1000))!.longJointApplied, isFalse);
    });

    test('l ≥ 900a: βLw ≤ 0 — komunikat', () {
      expect(filletProblems(_lin(a: 3, l: 2700)),
          [FilletProblem.tooLongForThroat]);
    });
  });

  group('werdykt i zaokrąglenia', () {
    test('zielony tylko przy F_Ed ≤ F_Rd dokładnie', () {
      const rd = 76.4874;
      expect(const FilletCheck(designForceKn: rd, resistanceKn: rd).ok, isTrue);
      expect(
          const FilletCheck(designForceKn: rd + 1e-9, resistanceKn: rd).ok,
          isFalse);
    });

    test('wykorzystanie w górę: 100,04 % → 100,1 %, nie „100 %”', () {
      expect(
          const FilletCheck(designForceKn: 100.04, resistanceKn: 100)
              .shownPercent,
          100.1);
      expect(
          const FilletCheck(designForceKn: 100.0000001, resistanceKn: 100)
              .shownPercent,
          100.1);
      expect(
          const FilletCheck(designForceKn: 99.996, resistanceKn: 100)
              .shownPercent,
          100.0);
      expect(
          const FilletCheck(designForceKn: 70, resistanceKn: 100).shownPercent,
          70.0);
      expect(
          const FilletCheck(designForceKn: 70.01, resistanceKn: 100)
              .shownPercent,
          70.1);
    });

    test('para F_Ed / F_Rd nie przeczy werdyktowi', () {
      void check(double ed, double rd) {
        final f = forcePairFormat(ed, rd);
        String show(double v, bool up) => f.conservative
            ? (up ? ceilTo(v, f.decimals) : floorTo(v, f.decimals))
                .toStringAsFixed(f.decimals)
            : v.toStringAsFixed(f.decimals);
        final e = double.parse(show(ed, true));
        final r = double.parse(show(rd, false));
        if (ed <= rd) {
          expect(e, lessThanOrEqualTo(r), reason: '$ed / $rd');
        } else {
          expect(e, greaterThan(r), reason: '$ed / $rd');
        }
      }

      check(76.43, 76.47);
      check(76.47, 76.43);
      check(76.4875, 76.4875);
      check(76.48751, 76.48749);
      check(10.006, 10.009);
      check(50, 76.4874);
      expect(forcePairFormat(76.43, 76.47).decimals, 2);
    });

    test('wymagane a i z zawsze w górę', () {
      expect(ceilTo(3.63165, 1), 3.7);
      expect(ceilTo(4.0, 1), 4.0);
      expect(floorTo(76.4874, 1), 76.4);
      expect(formatThroat(4.24 / math.sqrt2, en: false), '2,99');
      expect(formatThroat(3, en: true), '3.00');
    });

    test('siła charakterystyczna × γF', () {
      expect(designForceKn(50, ForceKind.design), 50);
      expect(designForceKn(50, ForceKind.permanent), closeTo(67.5, 1e-12));
      expect(designForceKn(50, ForceKind.variable), 75);
      expect(designForceKn(0, ForceKind.design), isNull);
      expect(designForceKn(double.nan, ForceKind.design), isNull);
    });
  });

  group('tekst do udostępnienia', () {
    test('PL: liczby, werdykt, wymagane a i zastrzeżenie', () {
      final r = computeFilletWeld(_lin())!;
      final t = filletShareText(result: r, en: false, forceInput: 80);
      expect(t, contains('S235: fu = 360 MPa, βw = 0,80, γM2 = 1,25'));
      expect(t, contains('l_eff = l − 2a = 92,0 mm'));
      expect(t, contains('F_w,Rd = 76,4 kN'));
      expect(t, contains('F_Ed = 80,0 kN'));
      // 80 / 76,4874 = 1,04592 → 104,6 %.
      expect(t, contains('Wykorzystanie 104,6 % — SPOINA NIE WYSTARCZY.'));
      // 80 kN: 2a² − 100a + 384,900 = 0 → a = (100 − √6920,80)/4 = 4,2022
      // → w górę 4,3 mm.
      expect(t, contains('Wymagane a ≥ 4,3 mm'));
      expect(t, contains(filletDisclaimer(en: false)));
    });

    test('EN: γF i kropka dziesiętna', () {
      final r = computeFilletWeld(_lin())!;
      final t = filletShareText(
          result: r, en: true, forceInput: 40, forceKind: ForceKind.variable);
      expect(t, contains('F_Ed = 1.5 × 40 kN = 60.0 kN'));
      expect(t, contains('the weld is sufficient'));
      expect(t, contains(filletDisclaimer(en: true)));
    });
  });

  // Regresja z przeglądu: ekran zaokrąglał w dół, tekst do udostępnienia do
  // najbliższej (S275 fvw,d 233,657 → „233,6” na ekranie, „233,7” w tekście).
  // Teraz oba biorą liczby z FilletFigures.
  group('liczby do pokazania (wspólne dla ekranu i tekstu)', () {
    // S275: fvw,d = 430 / (√3 · 0,85 · 1,25) = 430 / 1,8403040 = 233,6570.
    // a 3,37, 2 × l 640: l_eff = 640 − 6,74 = 633,26; Σ = 1266,52;
    // A = 3,37 · 1266,52 = 4268,17 mm²; 640 > 150·3,37 = 505,5 →
    // βLw = 1,2 − 0,2·640/505,5 = 0,946785.
    final linear = FilletWeldInput(
      steel: WeldSteelGrade.s275,
      throatMm: 3.37,
      maxPartThicknessMm: 10,
      lengthMm: 640,
      welds: 2,
    );

    test('S275 fvw,d 233,657 → „233,6”; l_eff, βLw w dół — tak samo w tekście',
        () {
      final r = computeFilletWeld(linear)!;
      final f = FilletFigures(r, en: false, designForceKn: 900);
      expect(f.fvwd, '233,6');
      expect(f.strength, '233,6');
      expect(f.effectiveLengthPerWeld, '633,2');
      expect(f.totalEffectiveLength, '1266,5');
      expect(f.throatArea, '4268');
      expect(f.longJointFactor, '0,946');
      final t = filletShareText(result: r, en: false, forceInput: 900);
      for (final s in [
        'fvw,d = ${f.fvwd} MPa',
        'l_eff = l − 2a = ${f.effectiveLengthPerWeld} mm',
        'Σ l_eff = ${f.totalEffectiveLength} mm',
        'a·Σl = ${f.throatArea} mm²',
        'βLw = ${f.longJointFactor}',
        'F_w,Rd = ${f.resistance} kN',
        'F_Ed = ${f.designForce} kN',
        'Wykorzystanie ${f.utilisation} %',
      ]) {
        expect(t, contains(s));
      }
      for (final nearest in ['233,7', '633,3', '0,947']) {
        expect(t, isNot(contains(nearest)), reason: nearest);
      }
    });

    test('obwodowa i kierunkowa: π·D i wytrzymałość w dół, w tekście tak samo',
        () {
      // π·60,35 = 189,5951; 90°: 430 / (0,85·1,25·√2) = 286,1703 MPa.
      final r = computeFilletWeld(FilletWeldInput(
        steel: WeldSteelGrade.s275,
        throatMm: 4,
        maxPartThicknessMm: 10,
        layout: WeldLayout.circumferential,
        tubeOdMm: 60.35,
        method: FilletMethod.directional,
      ))!;
      final f = FilletFigures(r, en: false);
      expect(f.weldLength, '189,5');
      expect(f.strength, '286,1');
      final t = filletShareText(result: r, en: false);
      expect(t, contains('l = π·D = 189,5 mm'));
      expect(t, contains('286,1 MPa'));
      expect(t, contains('uproszczona: ${f.simplifiedResistance} kN'));
      expect(t, contains('F_w,Rd = ${f.resistance} kN'));
      expect(t, isNot(contains('189,6')));
      expect(t, isNot(contains('286,2')));
    });

    test('pole wymiaru: a 4 → z „5,65”, a 3 → „3”, w dół i bez zbędnych zer',
        () {
      expect(sizeFieldText(4, leg: true, en: false), '5,65');
      expect(sizeFieldText(4, leg: false, en: false), '4');
      expect(sizeFieldText(3, leg: false, en: false), '3');
      expect(sizeFieldText(3, leg: true, en: true), '4.24');
      expect(formatLeg(4, en: false), '5,65');
      expect(formatThroat(4, en: false), '4,00');
    });
  });
}
