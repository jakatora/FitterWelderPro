import 'package:flutter_test/flutter_test.dart';
import 'package:cut_list_app/assistant/ai_clarification.dart';

void main() {
  test('literal user turns remain immutable and separate from model prompt',
      () {
    final turns = ['Ustaw szczelinę, nie zapisuj. Nazwa: "A i dodaj B"'];
    final first =
        AiClarification(question: 'Model: zrób wszystko', userTurns: turns);
    turns[0] = 'changed outside';
    final source = first.sourceWithReply('minus 2,5 mm');
    expect(source,
        'Ustaw szczelinę, nie zapisuj. Nazwa: "A i dodaj B"\nminus 2,5 mm');
    final next = AiClarification(
        question: 'Jeszcze jedno pytanie',
        userTurns: [...first.userTurns, 'minus 2,5 mm']);
    expect(next.sourceWithReply('poprawka: 3 mm'),
        endsWith('minus 2,5 mm\npoprawka: 3 mm'));
    expect(next.userSource, isNot(contains('Model:')));
    expect(() => first.userTurns.add('external'), throwsUnsupportedError);
  });
  test('bounds refuse rather than truncate the user source', () {
    final current =
        AiClarification(question: '?', userTurns: List.filled(7, 'x' * 2000));
    expect(current.sourceWithReply('a' * 1993), hasLength(16000));
    expect(current.sourceWithReply('a' * 1994), isNull);
    expect(current.sourceWithReply('a' * 2001), isNull);
    expect(current.sourceWithReply(' '), isNull);
    final maximum =
        AiClarification(question: '?', userTurns: List.filled(32, 'a'));
    expect(maximum.sourceWithReply('b'), isNull);
    for (final turns in <List<String>>[
      [],
      [''],
      ['x' * 2001],
      List.filled(33, 'a'),
      List.filled(8, 'x' * 2000)
    ]) {
      expect(() => AiClarification(question: '?', userTurns: turns),
          throwsFormatException);
    }
  });
}
