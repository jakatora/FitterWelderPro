/// „Ile muszę brać za godzinę?" — minimalna stawka netto (bez VAT), która
/// pokrywa koszty firmy, podatek i daje zakładany dochód na rękę.
///
/// Model (miesięcznie, średnio w roku):
///   godziny fakturowane H = dni · h/dzień · wykorzystanie · (52 − tyg. wolne)/52
///   koszty stałe C = suma pozycji (ZUS, zdrowotna, księgowość, auto,
///                    sprzęt, ubezpieczenie…)
///   podatek od DOCHODU (skala / liniowy), stopa r:
///       na rękę = (P − C)·(1 − r)  →  P = C + N / (1 − r)
///   podatek od PRZYCHODU (ryczałt), stopa r:
///       na rękę = P − C − r·P      →  P = (N + C) / (1 − r)
///   stawka = P / H, plus rezerwa na ryzyko (przestoje, poprawki, zatory
///   płatnicze) w %.
///
/// To przybliżenie: składka zdrowotna zależy od dochodu i formy
/// opodatkowania, ulgi i progi skali są pominięte — kwoty ZUS i stopę
/// podatku wpisuje użytkownik (z księgowym). Aplikacja nie zawiera stawek
/// ustawowych, bo zmieniają się co rok.
///
/// Czysty Dart.
library;

enum TaxBase {
  /// Skala / podatek liniowy — podatek od dochodu (przychód − koszty).
  income('INCOME'),

  /// Ryczałt — podatek od przychodu.
  revenue('REVENUE');

  const TaxBase(this.code);
  final String code;

  static TaxBase fromCode(String? c) => c == revenue.code ? revenue : income;
}

/// Pozycja kosztów stałych (miesięcznie, netto).
class FixedCost {
  final String labelPl;
  final String labelEn;
  final double monthly;

  const FixedCost(this.labelPl, this.labelEn, this.monthly);

  FixedCost withAmount(double v) => FixedCost(labelPl, labelEn, v);
}

class HourlyRateInput {
  /// Na rękę miesięcznie, zł.
  final double netIncome;
  final List<FixedCost> costs;
  final TaxBase taxBase;

  /// Stopa podatku, % (np. 12, 19, 8,5).
  final double taxPct;
  final double workDaysPerMonth;
  final double hoursPerDay;

  /// Jaka część godzin pracy jest fakturowana (dojazdy, przestoje, papiery,
  /// szukanie zleceń — nie), %.
  final double utilizationPct;

  /// Tygodnie bez zarobku w roku (urlop, choroba, święta, przerwy między
  /// zleceniami).
  final double weeksOff;

  /// Rezerwa na ryzyko, % od stawki.
  final double reservePct;

  const HourlyRateInput({
    this.netIncome = 9000,
    this.costs = kDefaultFixedCosts,
    this.taxBase = TaxBase.income,
    this.taxPct = 19,
    this.workDaysPerMonth = 21,
    this.hoursPerDay = 8,
    this.utilizationPct = 75,
    this.weeksOff = 6,
    this.reservePct = 10,
  });

  HourlyRateInput copyWith({
    double? netIncome,
    List<FixedCost>? costs,
    TaxBase? taxBase,
    double? taxPct,
    double? workDaysPerMonth,
    double? hoursPerDay,
    double? utilizationPct,
    double? weeksOff,
    double? reservePct,
  }) =>
      HourlyRateInput(
        netIncome: netIncome ?? this.netIncome,
        costs: costs ?? this.costs,
        taxBase: taxBase ?? this.taxBase,
        taxPct: taxPct ?? this.taxPct,
        workDaysPerMonth: workDaysPerMonth ?? this.workDaysPerMonth,
        hoursPerDay: hoursPerDay ?? this.hoursPerDay,
        utilizationPct: utilizationPct ?? this.utilizationPct,
        weeksOff: weeksOff ?? this.weeksOff,
        reservePct: reservePct ?? this.reservePct,
      );

  Map<String, Object?> toJson() => {
        'net': netIncome,
        'costs': [for (final c in costs) c.monthly],
        'tax': taxBase.code,
        'taxPct': taxPct,
        'days': workDaysPerMonth,
        'hours': hoursPerDay,
        'util': utilizationPct,
        'off': weeksOff,
        'reserve': reservePct,
      };

  static HourlyRateInput fromJson(Object? raw) {
    const d = HourlyRateInput();
    if (raw is! Map) return d;
    double n(String k, double f) {
      final v = raw[k];
      return v is num && v.isFinite ? v.toDouble() : f;
    }

    final amounts = raw['costs'];
    final costs = [
      for (var i = 0; i < kDefaultFixedCosts.length; i++)
        kDefaultFixedCosts[i].withAmount(
          amounts is List &&
                  i < amounts.length &&
                  amounts[i] is num &&
                  (amounts[i] as num).isFinite
              ? (amounts[i] as num).toDouble()
              : kDefaultFixedCosts[i].monthly,
        ),
    ];
    return HourlyRateInput(
      netIncome: n('net', d.netIncome),
      costs: costs,
      taxBase: TaxBase.fromCode(raw['tax'] as String?),
      taxPct: n('taxPct', d.taxPct),
      workDaysPerMonth: n('days', d.workDaysPerMonth),
      hoursPerDay: n('hours', d.hoursPerDay),
      utilizationPct: n('util', d.utilizationPct),
      weeksOff: n('off', d.weeksOff),
      reservePct: n('reserve', d.reservePct),
    );
  }
}

/// Pozycje kosztów — kwoty startowe 0 tam, gdzie nie da się zgadnąć
/// (ZUS zależy od ulg i roku: wpisz swój).
const List<FixedCost> kDefaultFixedCosts = [
  FixedCost('ZUS społeczny', 'Social insurance (ZUS)', 0),
  FixedCost('Składka zdrowotna', 'Health contribution', 0),
  FixedCost('Księgowość', 'Accounting', 250),
  FixedCost('Auto (rata, paliwo, serwis)', 'Van (lease, fuel, service)', 1500),
  FixedCost('Sprzęt (spawarka, szlifierki — odłożyć na wymianę)',
      'Equipment (welder, grinders — savings for replacement)', 400),
  FixedCost('Telefon, internet', 'Phone, internet', 100),
  FixedCost('Ubezpieczenie OC', 'Liability insurance', 100),
  FixedCost('BHP, odzież, szkolenia, uprawnienia',
      'PPE, clothing, training, certificates', 200),
  FixedCost('Inne', 'Other', 0),
];

class HourlyRateResult {
  /// Godziny fakturowane w miesiącu (średnio).
  final double billableHours;
  final double fixedCosts;

  /// Wymagany przychód netto miesięcznie.
  final double requiredRevenue;
  final double tax;

  /// Stawka bez rezerwy i z rezerwą, zł/h netto.
  final double breakEvenRate;
  final double recommendedRate;

  /// `null` = da się policzyć; inaczej powód.
  final HourlyRateProblem? problem;

  const HourlyRateResult({
    required this.billableHours,
    required this.fixedCosts,
    required this.requiredRevenue,
    required this.tax,
    required this.breakEvenRate,
    required this.recommendedRate,
    this.problem,
  });

  double get dayRate => recommendedRate * 8;
}

enum HourlyRateProblem { noHours, taxTooHigh, negative }

HourlyRateResult computeHourlyRate(HourlyRateInput i) {
  final fixed = i.costs.fold(0.0, (s, c) => s + c.monthly);
  final weeks = (52 - i.weeksOff).clamp(0, 52) / 52;
  final hours =
      i.workDaysPerMonth * i.hoursPerDay * (i.utilizationPct / 100) * weeks;
  HourlyRateResult fail(HourlyRateProblem p) => HourlyRateResult(
        billableHours: hours > 0 ? hours : 0,
        fixedCosts: fixed,
        requiredRevenue: 0,
        tax: 0,
        breakEvenRate: 0,
        recommendedRate: 0,
        problem: p,
      );
  if (i.netIncome < 0 ||
      fixed < 0 ||
      i.taxPct < 0 ||
      i.reservePct < 0 ||
      i.costs.any((c) => c.monthly < 0)) {
    return fail(HourlyRateProblem.negative);
  }
  if (!(hours > 0)) return fail(HourlyRateProblem.noHours);
  final r = i.taxPct / 100;
  if (r >= 1) return fail(HourlyRateProblem.taxTooHigh);

  final revenue = switch (i.taxBase) {
    TaxBase.income => fixed + i.netIncome / (1 - r),
    TaxBase.revenue => (i.netIncome + fixed) / (1 - r),
  };
  final tax = switch (i.taxBase) {
    TaxBase.income => (revenue - fixed) * r,
    TaxBase.revenue => revenue * r,
  };
  final base = revenue / hours;
  return HourlyRateResult(
    billableHours: hours,
    fixedCosts: fixed,
    requiredRevenue: revenue,
    tax: tax,
    breakEvenRate: base,
    recommendedRate: base * (1 + i.reservePct / 100),
  );
}
