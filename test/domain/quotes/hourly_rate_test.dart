// „Ile muszę brać za godzinę?" i lista zakupów wyceny.

import 'package:flutter_test/flutter_test.dart';

import 'package:cut_list_app/domain/quotes/hourly_rate.dart';
import 'package:cut_list_app/domain/quotes/quote_calculator.dart';
import 'package:cut_list_app/domain/quotes/quote_process.dart';
import 'package:cut_list_app/domain/quotes/quote_shopping.dart';
import 'package:cut_list_app/domain/quotes/weld_geometry.dart';
import 'package:cut_list_app/domain/quotes/weld_quote.dart';

HourlyRateInput _input({
  TaxBase base = TaxBase.income,
  double tax = 19,
  double reserve = 0,
}) =>
    HourlyRateInput(
      netIncome: 10000,
      costs: const [FixedCost('a', 'a', 3000), FixedCost('b', 'b', 1000)],
      taxBase: base,
      taxPct: tax,
      workDaysPerMonth: 20,
      hoursPerDay: 8,
      utilizationPct: 75,
      weeksOff: 0,
      reservePct: reserve,
    );

void main() {
  group('stawka godzinowa', () {
    test('godziny fakturowane = dni · h · wykorzystanie · tygodnie pracy', () {
      final r = computeHourlyRate(_input());
      expect(r.billableHours, closeTo(20 * 8 * 0.75, 1e-9));
      final off = computeHourlyRate(_input().copyWith(weeksOff: 13));
      expect(off.billableHours, closeTo(120 * 39 / 52, 1e-9));
    });

    test('podatek od dochodu: przychód = koszty + na rękę / (1 − r)', () {
      final r = computeHourlyRate(_input());
      expect(r.fixedCosts, 4000);
      expect(r.requiredRevenue, closeTo(4000 + 10000 / 0.81, 1e-6));
      // Na rękę po podatku = cel.
      expect(r.requiredRevenue - r.fixedCosts - r.tax, closeTo(10000, 1e-6));
      expect(r.breakEvenRate, closeTo(r.requiredRevenue / 120, 1e-9));
    });

    test('ryczałt: przychód = (na rękę + koszty) / (1 − r)', () {
      final r = computeHourlyRate(_input(base: TaxBase.revenue, tax: 8.5));
      expect(r.requiredRevenue, closeTo(14000 / 0.915, 1e-6));
      expect(r.tax, closeTo(r.requiredRevenue * 0.085, 1e-6));
      expect(r.requiredRevenue - r.fixedCosts - r.tax, closeTo(10000, 1e-6));
    });

    test('rezerwa podnosi stawkę o procent', () {
      final r = computeHourlyRate(_input(reserve: 10));
      expect(r.recommendedRate, closeTo(r.breakEvenRate * 1.1, 1e-9));
      expect(r.dayRate, closeTo(r.recommendedRate * 8, 1e-9));
    });

    test('błędne dane: bez godzin, podatek ≥ 100%, ujemne kwoty', () {
      expect(computeHourlyRate(_input().copyWith(utilizationPct: 0)).problem,
          HourlyRateProblem.noHours);
      expect(computeHourlyRate(_input().copyWith(weeksOff: 52)).problem,
          HourlyRateProblem.noHours);
      expect(computeHourlyRate(_input(tax: 100)).problem,
          HourlyRateProblem.taxTooHigh);
      expect(computeHourlyRate(_input().copyWith(netIncome: -1)).problem,
          HourlyRateProblem.negative);
    });

    test('zapis JSON tam i z powrotem', () {
      final i = _input(base: TaxBase.revenue, tax: 12).copyWith(costs: [
        for (final c in kDefaultFixedCosts) c.withAmount(c.monthly + 7),
      ]);
      final back = HourlyRateInput.fromJson(i.toJson());
      expect(back.taxBase, TaxBase.revenue);
      expect(back.taxPct, 12);
      expect(back.costs.map((c) => c.monthly), i.costs.map((c) => c.monthly));
      expect(HourlyRateInput.fromJson('zepsute').netIncome,
          const HourlyRateInput().netIncome);
    });
  });

  group('lista zakupów', () {
    WeldQuote q(
            {double reserve = 10,
            Map<QuoteProcess, double> packs = const {}}) =>
        WeldQuote(
          id: 'q',
          material: QuoteMaterial.stainless,
          purge: true,
          rates: QuoteRates.defaultsFor(QuoteMaterial.stainless)
              .copyWith(stockReservePct: reserve, packKg: packs),
          joints: const [
            QuoteJoint(
                id: 'j',
                kind: JointKind.pipeButt,
                odMm: 168.3,
                wallMm: 7.11,
                count: 40),
          ],
          createdAt: 0,
          updatedAt: 0,
        );

    test('spoiwo w pełnych opakowaniach z zapasem, gazy w butlach', () {
      final quote = q();
      final r = computeQuote(quote);
      final list = shoppingList(r, quote.rates);
      final tig = list.firstWhere((i) => i.process == QuoteProcess.tig);
      final mma = list.firstWhere((i) => i.process == QuoteProcess.mma);
      expect(
          tig.needed, closeTo(r.byProcess[QuoteProcess.tig]!.fillerKg, 1e-12));
      expect(tig.withReserve, closeTo(tig.needed * 1.1, 1e-9));
      expect(tig.packs, (tig.withReserve / 5).ceil());
      expect(mma.packs * mma.packSize, greaterThanOrEqualTo(mma.withReserve));
      expect((mma.packs - 1) * mma.packSize, lessThan(mma.withReserve));
      final argon = list.firstWhere((i) => i.kind == ShoppingKind.argon);
      expect(argon.packs,
          (r.shieldGasM3(QuoteGasKind.argon) * 1.1 / 10 - 1e-9).ceil());
      expect(list.any((i) => i.kind == ShoppingKind.purge), isTrue);
      expect(list.any((i) => i.kind == ShoppingKind.mix), isFalse);
    });

    test('własne opakowanie i zapas 0 %', () {
      final quote = q(reserve: 0, packs: {QuoteProcess.mma: 2});
      final list = shoppingList(computeQuote(quote), quote.rates);
      final mma = list.firstWhere((i) => i.process == QuoteProcess.mma);
      expect(mma.packSize, 2);
      expect(mma.withReserve, mma.needed);
      expect(mma.packs, (mma.needed / 2 - 1e-9).ceil());
    });

    test('opakowania i zapas przeżywają zapis wyceny', () {
      final quote = q(reserve: 20, packs: {QuoteProcess.tig: 2.5});
      final back = WeldQuote.fromRow(quote.toRow(netGrosze: 0, grossGrosze: 0));
      expect(back.rates.stockReservePct, 20);
      expect(back.rates.packKgOf(QuoteProcess.tig), 2.5);
      expect(back.rates.packKgOf(QuoteProcess.mma),
          kDefaultPackKg[QuoteProcess.mma]);
    });

    test('tekst listy do wysłania', () {
      final quote = q().copyWith(number: 'WYC/2026/004');
      final text = buildShoppingText(
          quote: quote,
          items: shoppingList(computeQuote(quote), quote.rates),
          en: false);
      expect(text, startsWith('Lista zakupów — WYC/2026/004'));
      expect(text, contains('Spoiwo TIG 141'));
      expect(text, contains('Gaz formujący'));
    });

    test('pusta wycena — pusta lista', () {
      final quote = q().copyWith(joints: const []);
      expect(shoppingList(computeQuote(quote), quote.rates), isEmpty);
    });
  });
}
