// Tandem TIG (zbiorniki): interpolacja prądów OUT/IN wyłącznie w zakresie
// danych startowych.
//
// Dane (seed `tandem_tig_params`, poziom, na styk):
//   3/3 → 140/72 A (t_eff 3), 4/4 → 190/100 A (t_eff 4), 3/5 → 180/90 A (t_eff 5)
// t_eff = max(t1, t2).
// Ręcznie:
//   3,5/3,5: k = (3,5−3)/(4−3) = 0,5 → OUT 140 + 50·0,5 = 165, IN 72 + 28·0,5 = 86
//   4,5/4,5: k = 0,5 między 4 (190/100) a 5 (180/90) → 185/95 — prąd MALEJE
//            z grubością → ostrzeżenie o niemonotoniczności.
//   1,5/1,5: poniżej najmniejszej t_eff (3) → brak danych (dawniej 140/72).
//   8/8:     powyżej największej t_eff (5) → brak danych (dawniej 180/90).
// Faza land 3 + szczelina 3: jeden punkt 8,7/10 → 175/105 (t_eff 10):
//   tylko t_eff = 10 daje wynik, 5 mm i 20 mm → brak danych (dawniej 175/105).
// Pion (skalowanie z poziomu przez parę odniesienia 3/3: pion 70/40, poziom 140/72):
//   3,5/3,5 → poziom 165/86 → OUT 165·70/140 = 82,5, IN 86·40/72 = 47,78

import 'package:flutter_test/flutter_test.dart';

import 'package:cut_list_app/domain/welding/tandem_currents.dart';

const _h = [
  TandemPoint(t1: 3, t2: 3, outsideA: 140, insideA: 72),
  TandemPoint(t1: 4, t2: 4, outsideA: 190, insideA: 100),
  TandemPoint(t1: 3, t2: 5, outsideA: 180, insideA: 90),
];

void main() {
  group('estimateTandem (poziom, na styk)', () {
    test('dokładny wpis (bez względu na kolejność t1/t2)', () {
      final r = estimateTandem(_h, 5, 3);
      expect(r.status, TandemStatus.exact);
      expect(r.outsideA, 180);
      expect(r.insideA, 90);
      expect(r.nonMonotonic, isFalse);
    });

    test('interpolacja w zakresie danych', () {
      final r = estimateTandem(_h, 3.5, 3.5);
      expect(r.status, TandemStatus.interpolated);
      expect(r.outsideA, closeTo(165, 1e-9));
      expect(r.insideA, closeTo(86, 1e-9));
      expect(r.nonMonotonic, isFalse);
    });

    test('poniżej zakresu danych: brak wyniku zamiast skrajnego punktu', () {
      final r = estimateTandem(_h, 1.5, 1.5);
      expect(r.status, TandemStatus.outOfRange);
      expect(r.hasResult, isFalse);
      expect(r.outsideA, isNull);
      expect(r.insideA, isNull);
      expect(r.minEffMm, 3);
      expect(r.maxEffMm, 5);
    });

    test('powyżej zakresu danych: brak wyniku', () {
      final r = estimateTandem(_h, 8, 8);
      expect(r.status, TandemStatus.outOfRange);
      expect(r.hasResult, isFalse);
    });

    test('prąd malejący z grubością → ostrzeżenie', () {
      final r = estimateTandem(_h, 4.5, 4.5);
      expect(r.status, TandemStatus.interpolated);
      expect(r.outsideA, closeTo(185, 1e-9));
      expect(r.insideA, closeTo(95, 1e-9));
      expect(r.nonMonotonic, isTrue);
    });

    test('5/5 ma t_eff punktu 3/5, ale mniej prądu niż 4/4 → ostrzeżenie, nie „dokładny”', () {
      final r = estimateTandem(_h, 5, 5);
      expect(r.status, isNot(TandemStatus.exact));
      expect(r.hasResult, isTrue);
      expect(r.nonMonotonic, isTrue);
    });

    test('brak punktów → brak danych', () {
      final r = estimateTandem(const [], 3, 3);
      expect(r.status, TandemStatus.noData);
      expect(r.hasResult, isFalse);
    });

    test('grubość 0 lub ujemna → brak wyniku', () {
      expect(estimateTandem(_h, 0, 0).hasResult, isFalse);
      expect(estimateTandem(_h, -3, 3).hasResult, isFalse);
    });
  });

  group('jeden punkt (faza land 3 + szczelina 3)', () {
    const bevel = [TandemPoint(t1: 8.7, t2: 10, outsideA: 175, insideA: 105)];

    test('ta sama para → wynik', () {
      final r = estimateTandem(bevel, 10, 8.7);
      expect(r.status, TandemStatus.exact);
      expect(r.outsideA, 175);
    });

    test('inna grubość nie dostaje tej samej wartości', () {
      final a = estimateTandem(bevel, 5, 5);
      final b = estimateTandem(bevel, 20, 20);
      expect(a.hasResult, isFalse);
      expect(b.hasResult, isFalse);
      expect(a.status, TandemStatus.outOfRange);
    });
  });

  group('pion z poziomu', () {
    const v = [TandemPoint(t1: 3, t2: 3, outsideA: 70, insideA: 40)];

    test('skalowanie przez parę odniesienia z danych (140/72, nie 138/68)', () {
      final r = estimateTandemVerticalFromHorizontal(
        horizontal: _h,
        vertical: v,
        t1: 3.5,
        t2: 3.5,
      );
      expect(r.status, TandemStatus.scaledFromHorizontal);
      expect(r.outsideA, closeTo(82.5, 1e-9));
      expect(r.insideA, closeTo(86 * 40 / 72, 1e-9));
    });

    test('poziom poza zakresem → pion też bez wyniku', () {
      final r = estimateTandemVerticalFromHorizontal(
        horizontal: _h,
        vertical: v,
        t1: 1.5,
        t2: 1.5,
      );
      expect(r.hasResult, isFalse);
      expect(r.status, TandemStatus.outOfRange);
    });

    test('brak wspólnej pary odniesienia → brak danych', () {
      final r = estimateTandemVerticalFromHorizontal(
        horizontal: _h,
        vertical: const [TandemPoint(t1: 6, t2: 6, outsideA: 90, insideA: 50)],
        t1: 3.5,
        t2: 3.5,
      );
      expect(r.hasResult, isFalse);
      expect(r.status, TandemStatus.noData);
    });

    test('dokładny wpis pionu ma pierwszeństwo', () {
      final r = estimateTandemVerticalFromHorizontal(
        horizontal: _h,
        vertical: v,
        t1: 3,
        t2: 3,
      );
      expect(r.status, TandemStatus.exact);
      expect(r.outsideA, 70);
      expect(r.insideA, 40);
    });
  });
}
