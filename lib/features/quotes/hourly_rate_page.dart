// „Ile muszę brać za godzinę?" — minimalna stawka z kosztów firmy, podatku
// i godzin, które naprawdę da się zafakturować. Otwarta z wyceny zwraca
// stawkę (Navigator.pop) do pola „Stawka spawacza".

import 'dart:async';

import 'package:flutter/material.dart';

import '../../domain/quotes/hourly_rate.dart';
import '../../domain/quotes/quote_calculator.dart'
    show formatPln, formatQty, toGrosze;
import '../../i18n/app_language.dart';
import '../../services/quote_settings.dart';
import '../../theme/app_theme.dart';
import '../../utils/haptic.dart';
import '../../widgets/readout.dart';
import 'quote_widgets.dart';

class HourlyRatePage extends StatefulWidget {
  /// `true` — strona otwarta z wyceny / ustawień: pokazuje „Użyj tej
  /// stawki" i zwraca ją przez Navigator.pop.
  final bool pickMode;
  final HourlyRateStore store;

  const HourlyRatePage({
    super.key,
    this.pickMode = false,
    this.store = const HourlyRateStore(),
  });

  @override
  State<HourlyRatePage> createState() => _HourlyRatePageState();
}

class _HourlyRatePageState extends State<HourlyRatePage> {
  HourlyRateInput _in = const HourlyRateInput();
  bool _loading = true;
  Timer? _save;
  int _gen = 0;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void dispose() {
    _save?.cancel();
    unawaited(widget.store.save(_in));
    super.dispose();
  }

  Future<void> _load() async {
    HourlyRateInput i;
    try {
      i = await widget.store.load();
    } catch (_) {
      i = const HourlyRateInput();
    }
    if (!mounted) return;
    setState(() {
      _in = i;
      _loading = false;
      _gen++;
    });
  }

  void _set(HourlyRateInput i) {
    setState(() => _in = i);
    _save?.cancel();
    _save = Timer(const Duration(milliseconds: 500),
        () => unawaited(widget.store.save(_in)));
  }

  Key _k(String id) => ValueKey('hr-$id-$_gen');

  Widget _num(String id, String label, double value, ValueChanged<double> set,
          {String? unit, String? helper, double max = 1e9, int decimals = 2}) =>
      QuoteNumberField(
        key: _k(id),
        label: label,
        value: value,
        unit: unit,
        helper: helper,
        decimals: decimals,
        validate: (v) => v != null && (v < 0 || v > max)
            ? context.tr(pl: 'Poza zakresem', en: 'Out of range')
            : null,
        onChanged: (v) {
          if (v != null && v >= 0 && v <= max) set(v);
        },
      );

  /// Stawka do wyceny: w górę do pełnych 50 groszy.
  double _rounded(double rate) => (rate * 2).ceil() / 2;

  @override
  Widget build(BuildContext context) {
    final en = context.language == AppLanguage.en;
    if (_loading) {
      return Scaffold(
        appBar: AppBar(
            title: Text(context.tr(
                pl: 'Ile brać za godzinę?', en: 'What to charge per hour?'))),
        body: const Center(child: CircularProgressIndicator(color: kArc)),
      );
    }
    final r = computeHourlyRate(_in);
    final ok = r.problem == null;
    final presets = _in.taxBase == TaxBase.income
        ? const [12.0, 19.0, 32.0]
        : const [5.5, 8.5, 12.0, 15.0];
    return Scaffold(
      appBar: AppBar(
        title: Text(context.tr(
            pl: 'Ile brać za godzinę?', en: 'What to charge per hour?')),
      ),
      body: ListView(
        padding: EdgeInsets.fromLTRB(
            16, 12, 16, 24 + MediaQuery.viewPaddingOf(context).bottom),
        children: [
          QuoteSection(
            title: context.tr(pl: 'Wynik', en: 'Result'),
            children: [
              if (!ok)
                QuoteNotice(
                  color: kFail,
                  icon: Icons.error_outline,
                  text: switch (r.problem!) {
                    HourlyRateProblem.noHours => context.tr(
                        pl: 'Brak godzin do zafakturowania — sprawdź dni, godziny i wykorzystanie.',
                        en: 'No billable hours — check days, hours and utilisation.'),
                    HourlyRateProblem.taxTooHigh => context.tr(
                        pl: 'Stopa podatku musi być poniżej 100%.',
                        en: 'The tax rate must be below 100%.'),
                    HourlyRateProblem.negative => context.tr(
                        pl: 'Kwoty nie mogą być ujemne.',
                        en: 'Amounts cannot be negative.'),
                  },
                )
              else ...[
                Readout(
                  label: context.tr(pl: 'Stawka minimalna', en: 'Minimum rate'),
                  value:
                      formatPln(toGrosze(r.recommendedRate), withUnit: false),
                  unit: context.tr(
                      pl: 'zł / h netto · z rezerwą ${formatQty(_in.reservePct)}%',
                      en: 'zł / h net · incl. ${formatQty(_in.reservePct)}% reserve'),
                  hot: true,
                ),
                const SizedBox(height: 12),
                MoneyRow(
                  label: context.tr(
                      pl: 'Próg bez rezerwy (zero zapasu)',
                      en: 'Break-even (no reserve)'),
                  grosze: toGrosze(r.breakEvenRate),
                ),
                MoneyRow(
                  label: context.tr(pl: 'Dniówka (8 h)', en: 'Day rate (8 h)'),
                  grosze: toGrosze(r.dayRate),
                ),
                MoneyRow(
                  label: context.tr(
                      pl: 'Przychód potrzebny w miesiącu',
                      en: 'Revenue needed per month'),
                  grosze: toGrosze(r.requiredRevenue),
                ),
                MoneyRow(
                  label: context.tr(
                      pl: 'w tym koszty firmy', en: 'of which business costs'),
                  grosze: toGrosze(r.fixedCosts),
                ),
                MoneyRow(
                  label: context.tr(pl: 'w tym podatek', en: 'of which tax'),
                  grosze: toGrosze(r.tax),
                ),
                const SizedBox(height: 6),
                Text(
                  context.tr(
                      pl: 'Fakturujesz średnio ${formatQty(r.billableHours, decimals: 0)} h w miesiącu. '
                          'Każda godzina sprzedana poniżej ${formatPln(toGrosze(r.breakEvenRate))} to dopłacanie do roboty.',
                      en: 'You bill ${formatQty(r.billableHours, decimals: 0)} h a month on average. '
                          'Every hour sold below ${formatPln(toGrosze(r.breakEvenRate))} means paying to work.'),
                  style: const TextStyle(
                      fontSize: 12.5, color: kTextSec, height: 1.4),
                ),
                if (widget.pickMode) ...[
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    key: const ValueKey('hr-apply'),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(52),
                      backgroundColor: kArc,
                      foregroundColor: kOnArc,
                    ),
                    onPressed: () {
                      Haptic.saved();
                      unawaited(widget.store.save(_in));
                      Navigator.of(context).pop(_rounded(r.recommendedRate));
                    },
                    icon: const Icon(Icons.check),
                    label: Text(
                      context.tr(
                          pl: 'Użyj ${formatQty(_rounded(r.recommendedRate))} zł/h w wycenie',
                          en: 'Use ${formatQty(_rounded(r.recommendedRate))} zł/h in the quote'),
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ),
                ],
              ],
            ],
          ),
          QuoteSection(
            title:
                context.tr(pl: 'Ile chcesz mieć', en: 'What you want to keep'),
            children: [
              _num(
                  'net',
                  context.tr(
                      pl: 'Na rękę miesięcznie', en: 'Take-home per month'),
                  _in.netIncome,
                  (v) => _set(_in.copyWith(netIncome: v)),
                  unit: 'zł',
                  decimals: 0),
            ],
          ),
          QuoteSection(
            title: context.tr(
                pl: 'Koszty firmy miesięcznie', en: 'Monthly business costs'),
            subtitle: context.tr(
                pl: 'Netto. ZUS i składkę zdrowotną wpisz swoje — zależą od roku i ulg.',
                en: 'Net. Enter your own social and health contributions — they depend on the year and reliefs.'),
            trailing: Text(formatPln(toGrosze(r.fixedCosts)),
                style: const TextStyle(fontWeight: FontWeight.w800)),
            children: [
              for (final (i, c) in _in.costs.indexed) ...[
                _num('cost-$i', en ? c.labelEn : c.labelPl, c.monthly, (v) {
                  final list = [..._in.costs];
                  list[i] = c.withAmount(v);
                  _set(_in.copyWith(costs: list));
                }, unit: 'zł', decimals: 0),
                const SizedBox(height: 10),
              ],
            ],
          ),
          QuoteSection(
            title: context.tr(pl: 'Podatek dochodowy', en: 'Income tax'),
            children: [
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  ChoiceChip(
                    key: const ValueKey('hr-tax-income'),
                    label: Text(context.tr(
                        pl: 'Od dochodu (skala, liniowy)',
                        en: 'On profit (scale, flat)')),
                    selected: _in.taxBase == TaxBase.income,
                    onSelected: (_) {
                      setState(() => _gen++);
                      _set(_in.copyWith(taxBase: TaxBase.income, taxPct: 19));
                    },
                  ),
                  ChoiceChip(
                    key: const ValueKey('hr-tax-revenue'),
                    label: Text(context.tr(
                        pl: 'Od przychodu (ryczałt)',
                        en: 'On revenue (lump sum)')),
                    selected: _in.taxBase == TaxBase.revenue,
                    onSelected: (_) {
                      setState(() => _gen++);
                      _set(_in.copyWith(taxBase: TaxBase.revenue, taxPct: 8.5));
                    },
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _num('tax', context.tr(pl: 'Stopa podatku', en: 'Tax rate'),
                  _in.taxPct, (v) => _set(_in.copyWith(taxPct: v)),
                  unit: '%', max: 99),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                children: [
                  for (final p in presets)
                    ActionChip(
                      label: Text('${formatQty(p)}%'),
                      onPressed: () {
                        setState(() => _gen++);
                        _set(_in.copyWith(taxPct: p));
                      },
                    ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                context.tr(
                    pl: 'Stawkę (zwłaszcza ryczałtu dla Twojego PKD) potwierdź z księgowym.',
                    en: 'Confirm the rate (especially the lump-sum rate for your activity code) with your accountant.'),
                style: const TextStyle(fontSize: 11.5, color: kTextMut),
              ),
            ],
          ),
          QuoteSection(
            title: context.tr(pl: 'Czas pracy', en: 'Working time'),
            children: [
              FieldPair(
                left: _num(
                    'days',
                    context.tr(pl: 'Dni w miesiącu', en: 'Days per month'),
                    _in.workDaysPerMonth,
                    (v) => _set(_in.copyWith(workDaysPerMonth: v)),
                    max: 31,
                    decimals: 1),
                right: _num(
                    'hours',
                    context.tr(pl: 'Godzin dziennie', en: 'Hours per day'),
                    _in.hoursPerDay,
                    (v) => _set(_in.copyWith(hoursPerDay: v)),
                    max: 24,
                    decimals: 1),
              ),
              const SizedBox(height: 10),
              FieldPair(
                left: _num(
                    'util',
                    context.tr(pl: 'Godziny fakturowane', en: 'Billable share'),
                    _in.utilizationPct,
                    (v) => _set(_in.copyWith(utilizationPct: v)),
                    unit: '%',
                    max: 100,
                    decimals: 0,
                    helper: context.tr(
                        pl: 'Bez dojazdów, przestojów, papierów',
                        en: 'Without travel, downtime, paperwork')),
                right: _num(
                    'off',
                    context.tr(
                        pl: 'Tygodnie bez zarobku', en: 'Weeks without pay'),
                    _in.weeksOff,
                    (v) => _set(_in.copyWith(weeksOff: v)),
                    max: 52,
                    decimals: 1,
                    helper: context.tr(
                        pl: 'Urlop, choroba, święta, przerwy',
                        en: 'Holiday, sickness, bank holidays, gaps')),
              ),
              const SizedBox(height: 10),
              _num(
                  'reserve',
                  context.tr(pl: 'Rezerwa na ryzyko', en: 'Risk reserve'),
                  _in.reservePct,
                  (v) => _set(_in.copyWith(reservePct: v)),
                  unit: '%',
                  max: 200,
                  decimals: 0,
                  helper: context.tr(
                      pl: 'Poprawki, zatory płatnicze, nieprzewidziane',
                      en: 'Rework, late payments, the unexpected')),
            ],
          ),
          Text(
            context.tr(
                pl: 'Przybliżenie: bez progów skali, ulg i zależności składki zdrowotnej od dochodu. '
                    'Ma pokazać, poniżej jakiej stawki robota przestaje się opłacać.',
                en: 'An approximation: no tax brackets, reliefs or income-dependent health contribution. '
                    'It shows below which rate the job stops paying.'),
            style:
                const TextStyle(fontSize: 11.5, color: kTextMut, height: 1.4),
          ),
        ],
      ),
    );
  }
}
