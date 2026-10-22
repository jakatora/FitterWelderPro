import '../../../domain/quotes/hourly_rate.dart';
import '../../../services/quote_settings.dart';
import '../../core/skill.dart';
import '../core/explain_tool_skill.dart' show explainedTool;
import '../core/labelled_numbers.dart';
import '../core/skill_words.dart';
import '../fitter_routes/quantities.dart';

bool _zl(String w) => w == 'zl' || w.startsWith('zlot') || w == 'pln';

Map<String, Object?> _slots(Utterance u) {
  final out = <String, Object?>{};
  final net = numberAfterLabel(
          u,
          (w) =>
              w == 'reke' ||
              w == 'netto' ||
              w.startsWith('zarobi') ||
              w.startsWith('dochod') ||
              w == 'take' ||
              w == 'income',
          unit: _zl,
          skip: const {'na', 'miesiecznie', 'chce', 'mam', 'home'}) ??
      (u.hasAny(const ['na reke', 'take home', 'netto'])
          ? numberBeforeUnit(u, _zl)
          : null);
  if (net != null) out['net_income'] = net;
  if (u.hasStem(const ['ryczalt', 'revenue', 'flat rate'])) {
    out['tax_base'] = TaxBase.revenue.name;
  } else if (u.hasStem(const ['liniow', 'skal', 'linear'])) {
    out['tax_base'] = TaxBase.income.name;
  }
  final tax = numberAfterLabel(
      u, (w) => w.startsWith('podat') || w.startsWith('ryczalt') || w == 'tax',
      skip: const {'liniowy', 'ryczaltem', 'stawka'});
  final pct = percentValue(u);
  if (tax != null) {
    out['tax_pct'] = tax;
  } else if (pct != null &&
      u.hasStem(const ['podat', 'ryczalt', 'tax'])) {
    out['tax_pct'] = pct;
  }
  final days = numberBeforeUnit(u, (w) => w.startsWith('dni') || w == 'days');
  if (days != null) out['work_days'] = days;
  final hours = numberBeforeUnit(
      u, (w) => w.startsWith('godzin') || w == 'h' || w == 'hours');
  if (hours != null) out['hours_per_day'] = hours;
  return out;
}

/// „Ile brać za godzinę” — stawka z zapisanych kosztów firmy; asystent
/// zmienia tylko to, co padło w poleceniu, i mówi, co wziął z ustawień.
class HourlyRateSkill extends AssistantSkill {
  HourlyRateSkill({HourlyRateStore store = const HourlyRateStore()})
      : _store = store;
  final HourlyRateStore _store;

  @override
  String get id => 'hourly.rate';
  @override
  String get toolId => 'hourly_rate';
  @override
  AssistantTier get tier => AssistantTier.b;
  @override
  List<SkillExample> get examples => const [
        SkillExample('Ile brać za godzinę żeby mieć 9000 zł na rękę',
            'What to charge per hour to take home 9000 zł'),
        SkillExample('Stawka godzinowa ryczałt 8,5% na rękę 10000 zł',
            'Hourly rate flat tax 8.5% take home 10000 zł'),
        SkillExample('Ile muszę brać za godzinę podatek liniowy 19% 20 dni 8 godzin',
            'What must I charge per hour linear tax 19% 20 days 8 hours'),
        SkillExample('Jaka stawka za godzinę na rękę 12000 zł',
            'What hourly rate take home 12000 zł'),
        SkillExample('Policz minimalną stawkę godzinową',
            'Calculate the minimum hourly rate'),
        SkillExample('Ile brać za godzinę', 'What to charge per hour'),
      ];
  @override
  List<SkillRejection> get rejections => const [
        SkillRejection('otwórz ile brać za godzinę', routesTo: 'tool.open'),
        SkillRejection('do czego służy ile brać za godzinę',
            routesTo: 'tool.explain'),
        SkillRejection('ile zarobię akordem za 40 cali'),
      ];

  @override
  SkillMatch? match(Utterance u, AssistantContext ctx) {
    if (explainedTool(u) != null ||
        RegExp(r'^(?:otworz|pokaz|open|show|do czego)\b').hasMatch(u.folded)) {
      return null;
    }
    if (u.hasStem(const ['akord', 'piecework'])) return null;
    final rate = u.hasAny(const [
          'za godzine',
          'stawka godzinowa',
          'stawke godzinowa',
          'stawka za godzine',
          'stawkowe godzinowa',
          // Samo „per hour” to też przepływ („600 litres per hour”).
          'charge per hour',
          'rate per hour',
          'earn per hour',
          'hourly rate',
          'minimalna stawke godzinowa',
          'minimalna stawka godzinowa'
        ]) ||
        u.hasStem(const ['godzinow']) && u.hasStem(const ['stawk']);
    if (!rate) return null;
    return SkillMatch(this, .9, slots: _slots(u), utterance: u);
  }

  @override
  Map<String, Object?> slotsFrom(Utterance u, AssistantContext ctx) =>
      _slots(u);

  @override
  Future<SkillResult> run(SkillMatch m, AssistantContext ctx) async {
    HourlyRateInput saved;
    try {
      saved = await _store.load();
    } catch (_) {
      saved = const HourlyRateInput();
    }
    double? n(String key) {
      final v = m.slots[key];
      return v is num && v.isFinite && v >= 0 ? v.toDouble() : null;
    }

    final base = TaxBase.values
        .where((b) => b.name == m.slots['tax_base'])
        .firstOrNull;
    final input = saved.copyWith(
        netIncome: n('net_income'),
        taxBase: base,
        taxPct: n('tax_pct'),
        workDaysPerMonth: n('work_days'),
        hoursPerDay: n('hours_per_day'));
    final r = computeHourlyRate(input);
    String f(num v) => fmt(v.toDouble(), ctx.lang);
    if (r.problem != null) {
      return FailedResult(switch (r.problem!) {
        HourlyRateProblem.noHours => const AssistantText(
            'Brak godzin do zafakturowania — sprawdź dni, godziny i wykorzystanie.',
            'No billable hours — check days, hours and utilisation.'),
        HourlyRateProblem.taxTooHigh => const AssistantText(
            'Podatek za wysoki dla tego wyliczenia.',
            'The tax rate is too high for this calculation.'),
        HourlyRateProblem.negative => const AssistantText(
            'Dane dają ujemną stawkę — sprawdź kwoty.',
            'The data gives a negative rate — check the amounts.'),
      });
    }
    // Stawka do wyceny: w górę do pełnych 50 groszy (jak na ekranie).
    final rate = (r.recommendedRate * 2).ceil() / 2;
    final fixed = input.costs.fold(0.0, (s, c) => s + c.monthly);
    final taxLabel = input.taxBase == TaxBase.revenue ? 'ryczałt' : 'podatek od dochodu';
    final taxLabelEn = input.taxBase == TaxBase.revenue ? 'flat tax' : 'income tax';
    final fields = <String, Object?>{
      if (n('net_income') != null) 'net_income': n('net_income'),
      if (base != null) 'tax_base': base.name,
      if (n('tax_pct') != null) 'tax_pct': n('tax_pct'),
      if (n('work_days') != null) 'work_days': n('work_days'),
      if (n('hours_per_day') != null) 'hours_per_day': n('hours_per_day'),
    };
    return AnswerResult(
        AssistantAnswer(
            text: AssistantText(
                'Minimalna stawka: ${f(rate)} zł/h netto (dzień ${f((rate * input.hoursPerDay).roundToDouble())} zł), próg rentowności ${f(r.breakEvenRate.roundToDouble())} zł/h. '
                'Liczone dla ${f(input.netIncome)} zł na rękę, kosztów stałych ${f(fixed.roundToDouble())} zł/mies., $taxLabel ${f(input.taxPct)} %, '
                '${f(input.workDaysPerMonth)} dni × ${f(input.hoursPerDay)} h, fakturowane ${f(input.utilizationPct)} %, ${f(input.weeksOff)} tyg. przerw, rezerwa ${f(input.reservePct)} % — '
                'czego nie podałeś, wziąłem z zapisanych ustawień modułu.',
                'Minimum rate: ${f(rate)} zł/h net (day ${f((rate * input.hoursPerDay).roundToDouble())} zł), break-even ${f(r.breakEvenRate.roundToDouble())} zł/h. '
                'Based on ${f(input.netIncome)} zł take-home, fixed costs ${f(fixed.roundToDouble())} zł/month, $taxLabelEn ${f(input.taxPct)} %, '
                '${f(input.workDaysPerMonth)} days × ${f(input.hoursPerDay)} h, ${f(input.utilizationPct)} % billable, ${f(input.weeksOff)} weeks off, ${f(input.reservePct)} % reserve — '
                'anything you did not say comes from the saved module settings.')),
        show: ShowInModule(toolId, fields));
  }
}
