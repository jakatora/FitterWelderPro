import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cut_list_app/assistant/core/skill.dart';
import 'package:cut_list_app/assistant/skills/own_data/piecework_skill.dart';
import 'package:cut_list_app/domain/piecework/piecework.dart';
import 'package:cut_list_app/domain/progress/progress_filter.dart' show DayRange;
import 'package:cut_list_app/domain/quotes/quote_calculator.dart' show formatPln;
import 'package:cut_list_app/domain/weld_journal/weld_entry.dart';
import 'package:cut_list_app/features/piecework/piecework_store.dart';
import 'package:cut_list_app/i18n/app_language.dart';
import '../support/weld_fixtures.dart';

WeldEntry cs(String id, String date) =>
    weld(id, date: date, welder: 'JK-12', material: 'P235GH')
        .copyWith(od: '60.3', t: '3.91');

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  final welds = [
    cs('1', '2026-10-14'),
    cs('2', '2026-10-15'),
    cs('3', '2026-09-20'),
  ];
  PieceworkEarningsSkill skill() => PieceworkEarningsSkill(
      loadWelds: () async => welds,
      loadIdentity: () async => 'JK-12',
      clock: () => DateTime(2026, 10, 22, 12));

  Future<SkillResult> say(String text) async {
    final s = skill();
    final u = Utterance(text, lang: AppLanguage.pl);
    final ctx = AssistantContext(
        lang: AppLanguage.pl, modules: const FixedModuleContext());
    final m = s.match(u, ctx);
    expect(m, isNotNull, reason: text);
    return s.run(m!, ctx);
  }

  test('this month for me: same total as the module domain', () async {
    await const PieceworkRatesStore()
        .save(const PieceworkRates(rateGrosze: 4500));
    final r = await say('Ile zarobiłem akordem w tym miesiącu') as AnswerResult;
    final expected = computePiecework(
        entries: welds,
        rates: const PieceworkRates(rateGrosze: 4500),
        range: DayRange(DateTime(2026, 10, 1), DateTime(2026, 10, 22)),
        welder: 'JK-12');
    expect(r.answer.text.pl, contains(formatPln(expected.totalGrosze)));
    expect(r.answer.text.pl, contains('za 2 spoin'));
    expect(r.answer.text.pl, contains('spawacz JK-12'));
    expect(r.show!.fields, {'period': 'month', 'crew': false});
  });

  test('last month and crew; empty period said plainly', () async {
    final last = await say('Akord za zeszły miesiąc') as AnswerResult;
    expect(last.answer.text.pl, contains('za 1 spoin'));
    final crew = await say('Akord brygady w tym miesiącu') as AnswerResult;
    expect(crew.answer.text.pl, contains('brygada'));
    expect(crew.show!.fields['crew'], true);
    final today = await say('Ile mam akordu dzisiaj') as AnswerResult;
    expect(today.answer.text.pl, contains('brak spoin'));
  });

  test('period is asked when missing', () async {
    final r = await say('policz mój akord');
    expect((r as AskResult).slot, 'period');
  });
}
