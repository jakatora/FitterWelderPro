import 'package:flutter_test/flutter_test.dart';
import 'package:cut_list_app/assistant/core/skill.dart';
import 'support/assistant_test_support.dart';

void main() {
  test('question with A–D chips; the right letter is praised', () async {
    final h = BrainHarness();
    addTearDown(h.timer.dispose);
    final ask = (await h.say('Zadaj mi pytanie egzaminacyjne', byVoice: true))
        .result as AskResult;
    expect(ask.slot, 'answer');
    expect(ask.choices.map((c) => c.utterance), containsAll(['A', 'B']));
    final correct = ask.partial.slots['correct'] as int;
    final letter = 'ABCDEF'[correct];
    final r = (await h.say(letter)).result as AnswerResult;
    expect(r.answer.text.pl, startsWith('Dobrze!'));
    expect(r.show!.toolId, 'welder_exam');
  });

  test('a wrong answer names the correct option and its source', () async {
    final h = BrainHarness();
    addTearDown(h.timer.dispose);
    final ask = (await h.say('Przepytaj mnie z BHP')).result as AskResult;
    final options = (ask.partial.slots['options'] as List).cast<String>();
    final correct = ask.partial.slots['correct'] as int;
    final wrong = correct == 0 ? 1 : 0;
    final r = (await h.say('ABCDEF'[wrong])).result as AnswerResult;
    expect(r.answer.text.pl, startsWith('Niestety nie. Poprawna:'));
    expect(r.answer.text.pl, contains(options[correct]));
  });

  test('an unclear answer asks for the letter again', () async {
    final h = BrainHarness();
    addTearDown(h.timer.dispose);
    await h.say('Daj mi pytanie z egzaminu');
    final again = (await h.say('nie wiem może coś')).result;
    expect(again, isA<AskResult>());
  });
}
