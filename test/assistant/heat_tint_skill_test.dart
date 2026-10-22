import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cut_list_app/assistant/core/skill.dart';
import 'package:cut_list_app/data/heat_tint.dart';
import 'support/assistant_test_support.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('colour words map to AWS D18.2 samples, longest name first', () async {
    final h = BrainHarness();
    addTearDown(h.timer.dispose);
    for (final (text, level) in [
      ('Przebarwienie spoiny słomkowe czy przejdzie', 2),
      ('przebarwienie czerwono-fioletowe', 5),
      ('przebarwienie fioletowe', 6),
      ('nalot od środka niebieski co z tym', 7),
      ('przebarwienie szaroniebieskie', 8),
      ('przebarwienie szare', 9),
    ]) {
      final reply = await h.say(text);
      expect(reply.match?.skill.id, 'heat_tint.check', reason: text);
      final r = reply.result as AnswerResult;
      expect(r.show!.fields, {'level': level}, reason: text);
    }
  });

  test('project limit from the module setting decides the warning', () async {
    final h = BrainHarness();
    addTearDown(h.timer.dispose);
    final bronze = (await h.say('kolor spoiny brąz czy ok na spożywczy')).result
        as AnswerResult;
    expect(bronze.answer.text.pl, contains('Mieści się w limicie projektu'));
    await saveHeatTintLimit(2);
    final again = (await h.say('przebarwienie brąz')).result as AnswerResult;
    expect(again.answer.text.pl, contains('Powyżej limitu projektu'));
  });

  test('O₂ ppm picks the nearest sample; unknown colour asks', () async {
    final h = BrainHarness();
    addTearDown(h.timer.dispose);
    final r = (await h.say('przebarwienie przy 200 ppm tlenu')).result
        as AnswerResult;
    expect(r.show!.fields['level'], 5);
    final ask = (await h.say('jaki poziom przebarwienia od środka rury')).result as AskResult;
    expect(ask.slot, 'level');
    final done = (await h.say('złoty')).result as AnswerResult;
    expect(done.show!.fields['level'], 3);
  });
}
