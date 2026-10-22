import 'package:flutter_test/flutter_test.dart';
import 'package:cut_list_app/assistant/core/skill.dart';
import 'support/assistant_test_support.dart';

void main() {
  test('MSS SP-58 table values for water and vapor service', () async {
    final h = BrainHarness();
    addTearDown(h.timer.dispose);
    final reply = await h.say('Rozstaw podpór DN100 woda', byVoice: true);
    expect(reply.match?.skill.id, 'pipe.supports');
    final r = reply.result as AnswerResult;
    expect(r.answer.text.pl, contains('maksymalny rozstaw podpór 4,3 m'));
    expect(r.show!.toolId, 'pipe_supports');
    expect(r.show!.fields, {'dn': 100, 'service': 'water'});
    final steam = (await h.say('Maksymalny rozstaw podpór DN200 para'))
        .result as AnswerResult;
    expect(steam.answer.text.pl, contains('7,3 m'));
  });

  test('supports on a run: ceil(run / spacing) + 1', () async {
    final h = BrainHarness();
    addTearDown(h.timer.dispose);
    // DN50 gaz: 4,0 m; 24 m → 24/4 = 6 przęseł → 7 podpór.
    final r = (await h.say('Ile podpór na odcinku 24 m DN50 gaz')).result
        as AnswerResult;
    expect(r.answer.text.pl, contains('7 podpór'));
    expect(r.show!.fields['run_m'], 24.0);
  });

  test('dialogue asks DN and service; DN outside the table is refused',
      () async {
    final h = BrainHarness();
    addTearDown(h.timer.dispose);
    final first = (await h.say('policz rozstaw podpór')).result as AskResult;
    expect(first.slot, 'dn');
    final second = (await h.say('DN80')).result as AskResult;
    expect(second.slot, 'service');
    final r = (await h.say('woda')).result as AnswerResult;
    expect(r.show!.fields, {'dn': 80, 'service': 'water'});
    expect((await h.say('rozstaw podpór DN110 woda')).result,
        isA<FailedResult>());
  });
}
