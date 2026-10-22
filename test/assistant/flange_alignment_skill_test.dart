import 'package:flutter_test/flutter_test.dart';
import 'package:cut_list_app/assistant/core/skill.dart';
import 'support/assistant_test_support.dart';

void main() {
  test('PCC-1 Appendix E limits with verdicts', () async {
    final h = BrainHarness();
    addTearDown(h.timer.dispose);
    final par = (await h.say('Równoległość kołnierzy zmierzone 1 mm'))
        .result as AnswerResult;
    expect(par.answer.text.pl, contains('najwyżej 0,8 mm'));
    expect(par.answer.text.pl, contains('POZA granicą'));
    final axis = (await h.say('Przesunięcie osi kołnierzy zmierzone 1,2 mm'))
        .result as AnswerResult;
    expect(axis.answer.text.pl, contains('w granicy'));
    final spacing = (await h.say('Rozsunięcie kołnierzy 7 mm uszczelka 3 mm'))
        .result as AnswerResult;
    expect(spacing.answer.text.pl, contains('= 6 mm'));
    expect(spacing.show!.toolId, 'flange_check');
  });

  test('summary of all criteria; torque stays elsewhere', () async {
    final h = BrainHarness();
    addTearDown(h.timer.dispose);
    final all = (await h.say('Jaka tolerancja osiowania kołnierzy')).result
        as AnswerResult;
    expect(all.answer.text.pl, contains('PCC-1-2019 zał. E'));
    expect(
        (await h.say('jaki moment dokręcenia śruby 3/4 cala B7 na smarze'))
            .match
            ?.skill
            .id,
        isNot('flange.alignment'));
  });
}
