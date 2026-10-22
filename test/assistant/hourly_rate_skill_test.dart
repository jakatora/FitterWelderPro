import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cut_list_app/assistant/core/skill.dart';
import 'package:cut_list_app/domain/quotes/hourly_rate.dart';
import 'package:cut_list_app/services/quote_settings.dart';
import 'support/assistant_test_support.dart';

String _pl(double v) {
  final s = v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(1);
  return s.replaceAll('.', ',');
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('only the stated value changes; the rest comes from saved settings',
      () async {
    await const HourlyRateStore()
        .save(const HourlyRateInput(netIncome: 7000, taxPct: 12));
    final h = BrainHarness();
    addTearDown(h.timer.dispose);
    final reply = await h.say('Jaka stawka za godzinę na rękę 12000 zł',
        byVoice: true);
    expect(reply.match?.skill.id, 'hourly.rate');
    final r = reply.result as AnswerResult;
    final expected = computeHourlyRate(
        const HourlyRateInput(netIncome: 12000, taxPct: 12));
    final rate = (expected.recommendedRate * 2).ceil() / 2;
    expect(r.answer.text.pl, contains('Minimalna stawka: ${_pl(rate)} zł/h'));
    expect(r.answer.text.pl, contains('podatek od dochodu 12 %'));
    expect(r.answer.text.pl, contains('z zapisanych ustawień'));
    expect(r.show!.toolId, 'hourly_rate');
    expect(r.show!.fields, {'net_income': 12000.0});
  });

  test('flat tax with its percentage, days and hours', () async {
    final h = BrainHarness();
    addTearDown(h.timer.dispose);
    final r = (await h.say('Stawka godzinowa ryczałt 8,5% na rękę 10000 zł'))
        .result as AnswerResult;
    expect(r.show!.fields,
        {'net_income': 10000.0, 'tax_base': 'revenue', 'tax_pct': 8.5});
    final d = (await h.say(
            'Ile muszę brać za godzinę podatek liniowy 19% 20 dni 8 godzin'))
        .result as AnswerResult;
    expect(d.show!.fields['work_days'], 20.0);
    expect(d.show!.fields['hours_per_day'], 8.0);
    expect(d.show!.fields['tax_pct'], 19.0);
  });

  test('piecework is not the hourly rate', () async {
    final h = BrainHarness();
    addTearDown(h.timer.dispose);
    expect((await h.say('ile zarobię akordem za 40 cali')).match?.skill.id,
        isNot('hourly.rate'));
  });

  test('a flow per hour is not an hourly rate', () async {
    final h = BrainHarness();
    addTearDown(h.timer.dispose);
    expect(
        (await h.say(
                'Oblicz zużycie gazu spoiny 10 spawanie 2 min palnik 600 litres per hour'))
            .match
            ?.skill
            .id,
        isNot('hourly.rate'));
  });
}
