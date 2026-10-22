import 'package:flutter_test/flutter_test.dart';
import 'package:cut_list_app/assistant/core/skill.dart';
import 'package:cut_list_app/assistant/skills/own_data/coupons_status_skill.dart';
import 'package:cut_list_app/domain/weld_journal/coupon_entry.dart';
import 'package:cut_list_app/i18n/app_language.dart';

CouponEntry c(String id, String date, String result, {double? o2}) =>
    CouponEntry(
        id: id,
        date: date,
        welder: 'JK-12',
        machine: 'M100',
        size: '1/2"',
        result: result,
        notes: '',
        o2Ppm: o2);

void main() {
  Future<SkillResult> say(String text, List<CouponEntry> data) async {
    final s = CouponsStatusSkill(
        load: () async => data, clock: () => DateTime(2026, 10, 23, 9));
    final u = Utterance(text, lang: AppLanguage.pl);
    final ctx = AssistantContext(
        lang: AppLanguage.pl, modules: const FixedModuleContext());
    final m = s.match(u, ctx);
    expect(m, isNotNull, reason: text);
    return s.run(m!, ctx);
  }

  test('today, pending and the latest coupon', () async {
    final r = await say('Ile kuponów dzisiaj', [
      c('1', '2026-10-22', CouponResult.ok),
      c('2', '2026-10-23', CouponResult.pending, o2: 18),
      c('3', '2026-10-23', CouponResult.ok),
    ]) as AnswerResult;
    expect(r.answer.text.pl, contains('Dziś kuponów: 2, do oceny: 1'));
    expect(r.answer.text.pl, contains('Ostatni: 2026-10-23'));
    expect(r.show!.toolId, 'coupon_log');
  });

  test('empty log and adding are handled', () async {
    final r = await say('pokaż kupony', const []) as AnswerResult;
    expect(r.answer.text.pl, contains('pusty'));
    final s = CouponsStatusSkill(load: () async => const []);
    expect(
        s.match(Utterance('dodaj kupon', lang: AppLanguage.pl),
            AssistantContext(
                lang: AppLanguage.pl, modules: const FixedModuleContext())),
        isNull);
  });
}
