// Równoważniki Schaefflera i skład stopiwa — przeliczone ręcznie:
//
// Spoiwo 309L: C 0,02 Si 0,8 Mn 1,6 Cr 23,5 Mo 0,1 Ni 13
//   Cr_eq = 23,5 + 0,1 + 1,5·0,8 = 24,8
//   Ni_eq = 13 + 30·0,02 + 0,5·1,6 = 14,4
// Stal węglowa: C 0,2 Si 0,3 Mn 1,0 (Cr = Ni = 0)
//   Cr_eq = 0,45;  Ni_eq = 6 + 0,5 = 6,5
// 304L: C 0,02 Si 0,4 Mn 1,5 Cr 18,2 Ni 8,1
//   Cr_eq = 18,2 + 0,6 = 18,8;  Ni_eq = 8,1 + 0,6 + 0,75 = 9,45
// Stopiwo, D = 30 %, udział A = 50 %:
//   Cr_eq = 0,7·24,8 + 0,3·(0,5·0,45 + 0,5·18,8) = 17,36 + 2,8875 = 20,2475
//   Ni_eq = 0,7·14,4 + 0,3·(0,5·6,5 + 0,5·9,45) = 10,08 + 2,3925 = 12,4725

import 'package:flutter_test/flutter_test.dart';

import 'package:cut_list_app/domain/filler/schaeffler.dart';

const _f309L =
    WeldComposition(c: 0.02, si: 0.8, mn: 1.6, cr: 23.5, mo: 0.1, ni: 13);
const _cs = WeldComposition(c: 0.2, si: 0.3, mn: 1.0);
const _ss304L = WeldComposition(c: 0.02, si: 0.4, mn: 1.5, cr: 18.2, ni: 8.1);

void main() {
  test('równoważniki pojedynczych składów', () {
    expect(_f309L.crEq, closeTo(24.8, 1e-9));
    expect(_f309L.niEq, closeTo(14.4, 1e-9));
    expect(_cs.crEq, closeTo(0.45, 1e-9));
    expect(_cs.niEq, closeTo(6.5, 1e-9));
    expect(_ss304L.crEq, closeTo(18.8, 1e-9));
    expect(_ss304L.niEq, closeTo(9.45, 1e-9));
    // Nb liczy się połową.
    expect(const WeldComposition(cr: 18, nb: 0.6).crEq, closeTo(18.3, 1e-9));
  });

  test('stopiwo z rozcieńczeniem 30 %, po równo z A i B', () {
    final w = weldMetalComposition(
        filler: _f309L, baseA: _cs, baseB: _ss304L, dilution: 0.3)!;
    expect(w.crEq, closeTo(20.2475, 1e-9));
    expect(w.niEq, closeTo(12.4725, 1e-9));
    final p = SchaefflerPoint.of(w);
    expect(p.crEq, w.crEq);
    expect(p.niEq, w.niEq);
  });

  test('skrajności: bez rozcieńczenia = spoiwo, pełne = materiał A', () {
    final none = weldMetalComposition(
        filler: _f309L, baseA: _cs, baseB: _ss304L, dilution: 0)!;
    expect(none.crEq, closeTo(_f309L.crEq, 1e-9));
    final full = weldMetalComposition(
        filler: _f309L,
        baseA: _cs,
        baseB: _ss304L,
        dilution: 1,
        shareA: 1)!;
    expect(full.niEq, closeTo(_cs.niEq, 1e-9));
  });

  test('dane poza zakresem dają null — nigdy cichy wynik', () {
    expect(
        weldMetalComposition(
            filler: _f309L, baseA: _cs, baseB: _ss304L, dilution: 1.2),
        isNull);
    expect(
        weldMetalComposition(
            filler: _f309L,
            baseA: _cs,
            baseB: _ss304L,
            dilution: 0.3,
            shareA: -0.1),
        isNull);
    expect(
        weldMetalComposition(
            filler: const WeldComposition(cr: 80, ni: 30),
            baseA: _cs,
            baseB: _ss304L,
            dilution: 0.3),
        isNull,
        reason: 'suma > 100 %');
    expect(const WeldComposition(cr: -1).isValid, isFalse);
    expect(const WeldComposition(cr: double.nan).isValid, isFalse);
  });
}
