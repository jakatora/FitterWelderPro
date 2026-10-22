import 'package:flutter_test/flutter_test.dart';
import 'package:cut_list_app/assistant/core/skill.dart';
import 'support/assistant_test_support.dart';

void main() {
  test('opens the checklist for the named process, never ticks', () async {
    final h = BrainHarness();
    addTearDown(h.timer.dispose);
    final r = (await h.say('Co sprawdzić przed spawaniem migomagiem'))
        .result as AnswerResult;
    expect(r.show!.toolId, 'pre_weld_checklist');
    expect(r.show!.fields, {'process': 'mag'});
    expect(r.answer.text.pl, contains('asystent ich nie zaznacza'));
    final orb = (await h.say('Checklista przed spawaniem orbitalnym')).result
        as AnswerResult;
    expect(orb.show!.fields, {'process': 'tig-orb'});
  });

  test('process is asked when missing; weather is a different module',
      () async {
    final h = BrainHarness();
    addTearDown(h.timer.dispose);
    final ask = (await h.say('lista kontrolna przed spawaniem')).result
        as AskResult;
    expect(ask.slot, 'process');
    final r = (await h.say('TIG')).result as AnswerResult;
    expect(r.show!.fields, {'process': 'tig-man'});
  });
}
