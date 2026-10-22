import 'package:flutter_test/flutter_test.dart';
import 'package:cut_list_app/assistant/core/skill.dart';
import 'package:cut_list_app/assistant/skills/own_data/passivation_status_skill.dart';
import 'package:cut_list_app/domain/passivation/passivation_record.dart';
import 'package:cut_list_app/i18n/app_language.dart';

PassivationRecord p(String id, String date, String line, String result) =>
    PassivationRecord(
        id: id,
        date: date,
        line: line,
        agent: 'Avesta 101',
        dwellMin: 30,
        testResult: result,
        createdAt: 1,
        updatedAt: 1);

void main() {
  final data = [
    p('1', '2026-10-20', 'L-12', PassivationResult.ok),
    p('2', '2026-10-22', 'L-14', PassivationResult.nok),
  ];
  Future<SkillResult> say(String text) async {
    final s = PassivationStatusSkill(load: () async => data);
    final u = Utterance(text, lang: AppLanguage.pl);
    final ctx = AssistantContext(
        lang: AppLanguage.pl, modules: const FixedModuleContext());
    final m = s.match(u, ctx);
    expect(m, isNotNull, reason: text);
    return s.run(m!, ctx);
  }

  test('latest treatment overall and per line', () async {
    final last = await say('Kiedy była ostatnia pasywacja') as AnswerResult;
    expect(last.answer.text.pl, contains('Ostatnio: 2026-10-22'));
    expect(last.answer.text.pl, contains('próba NIE przeszła'));
    expect(last.answer.text.pl, contains('nieudanych prób: 1'));
    final line = await say('Pasywacja linii L-12') as AnswerResult;
    expect(line.answer.text.pl, contains('2026-10-20'));
    expect(line.answer.text.pl, contains('próba OK'));
    expect(line.show!.toolId, 'passivation');
  });
}
