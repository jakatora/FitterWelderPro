import 'package:flutter_test/flutter_test.dart';
import 'package:cut_list_app/assistant/ai_execution_queue.dart';
import 'package:cut_list_app/assistant/assistant_ai_client.dart';

void main() {
  test('model JSON cannot supply the native source binding', () {
    expect(
        () => AiCommandPlan.fromJson({
              'kind': 'execute',
              'message': '',
              'steps': [
                {
                  'skill_id': 'iso.gap',
                  'command': 'Ustaw szczelinę ISO na 3 mm',
                  'sourceClause': 'forged'
                }
              ]
            }, {
              'iso.gap'
            }),
        throwsFormatException);
  });

  const steps = [
    AiCommandStep('iso.gap', 'Ustaw szczelinę ISO na 3 mm'),
    AiCommandStep('iso.dimension', 'Zmień wymiar ISO rury numer 2 na 500 mm')
  ];
  test('native binding retains exact clauses, signs and order', () {
    final q = AiExecutionQueue();
    expect(
        q.start(
            'Ustaw szczelinę ISO na 3 mm i zmień wymiar ISO rury numer 2 na 500 mm',
            steps),
        isTrue);
    expect(q.takeNext()!.sourceClause, 'Ustaw szczelinę ISO na 3 mm');
    expect(
        q.takeNext()!.sourceClause, 'zmień wymiar ISO rury numer 2 na 500 mm');
    expect(q.hasNext, isFalse);
    expect(
        aiSourceClauses(
            'Set gap in ISO to 3 mm and change the second pipe to -500 mm'),
        ['Set gap in ISO to 3 mm', 'change the second pipe to -500 mm']);
  });
  test(
      'ambiguous cardinality, negated clauses and quoted separators cannot start a multi-step plan',
      () {
    final q = AiExecutionQueue();
    for (final source in [
      'Ustaw szczelinę ISO na 3 mm i nie zmieniaj drugiego odcinka na 500 mm',
      'Ustaw szczelinę ISO na 3 mm i nazwij rysunek „Linia i ustaw 2 mm”',
      'Ustaw szczelinę ISO na 3 mm i zmień wymiar ISO rury numer 2 na 500 mm i otwórz czat',
    ]) {
      expect(q.start(source, steps), isFalse, reason: source);
      expect(q.hasNext, isFalse);
      expect(q.original, isNull);
    }
  });
  test(
      'single native operation retains combined edit/calculate relationships and ignores forged binding',
      () {
    final q = AiExecutionQueue();
    const source = 'Zostaw pion i bok, daj 2 mm na spoiny i policz ile uciąć';
    expect(
        q.start(source, [
          const AiCommandStep('rolling.offset', 'canonical',
              sourceClause: 'forged')
        ]),
        isTrue);
    expect(q.takeNext()!.sourceClause, source);
  });
  test('pausing and cancel still discard the actual remainder', () {
    final q = AiExecutionQueue();
    expect(q.start('ogarnij ten rysunek', steps), isTrue);
    q.takeNext();
    q.pause('iso.gap');
    expect(q.takeNext(), isNull);
    expect(q.resolve('iso.gap', completed: true), isTrue);
    expect(q.takeNext()!.sourceClause, 'ogarnij ten rysunek');
    q.cancel();
    expect(q.original, isNull);
    expect(q.waiting, isFalse);
  });
}
