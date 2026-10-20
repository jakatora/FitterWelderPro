import 'package:flutter_test/flutter_test.dart';
import 'package:cut_list_app/assistant/core/skill.dart';
import 'support/assistant_test_support.dart';

void main() {
  test('304L matches screen coefficient and does not assume temperature range',
      () async {
    final r = (await BrainHarness()
            .say('oblicz dylatację długość 50 m delta 100 C 304L'))
        .result as AnswerResult;
    expect(r.answer.text.pl, contains('80 mm'));
    expect(r.answer.text.pl, contains('20–100'));
    expect(r.show!.fields,
        {'length_m': 50.0, 'delta_k': 100.0, 'material': 'ss304L'});
  });
  test('dialogue collects dimensions and material without defaults', () async {
    final h = BrainHarness();
    expect((await h.say('oblicz dylatację')).result, isA<AskResult>());
    expect((await h.say('50 metrów')).result, isA<AskResult>());
    expect((await h.say('100 C')).result, isA<AskResult>());
    final r = (await h.say('stal węglowa')).result as AnswerResult;
    expect(r.answer.text.pl, contains('60 mm'));
    expect(r.show!.fields['material'], 'cs');
  });
  for (final text in [
    'dylatacja długość minus 50 m delta 100 C 304L',
    'dylatacja długość 50 m delta minus 100 C 304L',
    'dylatacja długość 50 m delta 100 F 304L',
    'dylatacja długość 50 m delta 100 C 304L 316L',
    'dylatacja długość 50 m delta 100 C stal nierdzewna',
    'dylatacja długość 50 m długość 60 m delta 100 C 304L',
  ]) {
    test('invalid or ambiguous input asks: $text', () async {
      expect((await BrainHarness().say(text)).result, isA<AskResult>());
    });
  }
  test('zero delta is valid and gives no growth', () async {
    final r =
        (await BrainHarness().say('dylatacja długość 50 m delta 0 C aluminium'))
            .result as AnswerResult;
    expect(r.answer.text.pl, contains('0 mm'));
  });
}
