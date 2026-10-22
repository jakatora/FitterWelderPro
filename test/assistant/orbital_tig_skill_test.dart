import 'package:flutter_test/flutter_test.dart';
import 'package:cut_list_app/assistant/core/skill.dart';
import 'support/assistant_test_support.dart';

void main() {
  test('25,4 × 1,65 mm: base 48·t + 0,12·OD = 82 A, taper per level',
      () async {
    final h = BrainHarness();
    addTearDown(h.timer.dispose);
    final reply = await h.say('Parametry orbitala rura 25,4 mm ścianka 1,65 mm',
        byVoice: true);
    expect(reply.match?.skill.id, 'orbital.tig');
    final r = reply.result as AnswerResult;
    expect(r.answer.text.pl, contains('82 / 76 / 69 / 64 A'));
    expect(r.answer.text.pl, contains('posuw 100 mm/min'));
    expect(r.answer.text.pl, contains('obrót ok. 48 s'));
    expect(r.show!.toolId, 'orbital_tig');
    expect(r.show!.fields, {'od_mm': 25.4, 'wall_mm': 1.65});
  });

  test('outside the autogenous model: a message, not a number', () async {
    final h = BrainHarness();
    addTearDown(h.timer.dispose);
    expect((await h.say('orbital rura 168,3 mm ścianka 6 mm')).result,
        isA<FailedResult>());
    expect((await h.say('orbital rura 25,4 mm ścianka 1,65 mm 30 V')).result,
        isA<FailedResult>());
  });

  test('unlabelled OD × wall and the dialogue', () async {
    final h = BrainHarness();
    addTearDown(h.timer.dispose);
    final r = (await h.say('orbital 38,1 x 2 mm')).result as AnswerResult;
    expect(r.show!.fields, {'od_mm': 38.1, 'wall_mm': 2.0});
    final ask = (await h.say('policz parametry orbitala')).result as AskResult;
    expect(ask.slot, 'od_mm');
    final ask2 = (await h.say('12,7 mm')).result as AskResult;
    expect(ask2.slot, 'wall_mm');
    final done = (await h.say('1 mm')).result as AnswerResult;
    expect(done.show!.fields, {'od_mm': 12.7, 'wall_mm': 1.0});
  });
}
