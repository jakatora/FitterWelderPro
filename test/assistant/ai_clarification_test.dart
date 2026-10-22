import 'package:flutter_test/flutter_test.dart';
import 'package:cut_list_app/assistant/ai_clarification.dart';

void main() {
  test('user turns preserve signs, literals and order without model prompt',
      () {
    const first = AiClarification(
        question: 'Model: zrób wszystko',
        userSource: 'Ustaw szczelinę, nie zapisuj. Nazwa: "A i dodaj B"');
    final source = first.sourceWithReply('minus 2,5 mm');
    expect(source,
        'Ustaw szczelinę, nie zapisuj. Nazwa: "A i dodaj B"\nminus 2,5 mm');
    final next =
        AiClarification(question: 'Jeszcze jedno pytanie', userSource: source!);
    expect(next.sourceWithReply('poprawka: 3 mm'),
        endsWith('minus 2,5 mm\npoprawka: 3 mm'));
    expect(next.userSource, isNot(contains('Model:')));
    expect(first.userSource, isNot(contains('minus')));
  });
  test('oversized clarification rejects instead of truncating an instruction',
      () {
    final current = AiClarification(question: '?', userSource: 'x' * 15998);
    expect(current.sourceWithReply('a'), hasLength(16000));
    expect(current.sourceWithReply('ab'), isNull);
    expect(current.userSource, hasLength(15998));
  });
}
