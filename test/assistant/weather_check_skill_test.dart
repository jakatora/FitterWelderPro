import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cut_list_app/assistant/core/skill.dart';
import 'support/assistant_test_support.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('good conditions with a dry joint: welding is possible', () async {
    final h = BrainHarness();
    addTearDown(h.timer.dispose);
    final reply = await h.say(
        'Warunki do spawania temperatura 20 stopni wilgotność 60% wiatr 1 m/s 141 powierzchnia sucha',
        byVoice: true);
    expect(reply.match?.skill.id, 'weather.check');
    final r = reply.result as AnswerResult;
    expect(r.answer.text.pl, startsWith('Można spawać.'));
    // Punkt rosy 20 °C / 60 % ≈ 12 °C (Magnus).
    expect(r.answer.text.pl, contains('punkt rosy 12'));
    expect(r.show!.toolId, 'weather_check');
    expect(r.show!.fields, {
      'ambient_c': 20.0,
      'rh_pct': 60.0,
      'wind_ms': 1.0,
      'process': 'tig141',
      'material': 'carbonSteel',
      'precipitation': 'none',
      'shelter': 'none',
      'surface_state': 'dry',
    });
  });

  test('wind blows away TIG gas shielding', () async {
    final h = BrainHarness();
    addTearDown(h.timer.dispose);
    final r = (await h.say(
            'Czy mogę spawać temperatura 15 stopni wilgotność 50% wiatr 6 m/s TIG powierzchnia sucha'))
        .result as AnswerResult;
    expect(r.answer.text.pl, isNot(startsWith('Można spawać.')));
  });

  test('minus and frost give a negative air temperature', () async {
    final h = BrainHarness();
    addTearDown(h.timer.dispose);
    for (final text in [
      'Czy mogę spawać temperatura minus 5 stopni wilgotność 85% wiatr 4 m/s MMA',
      'czy mogę spawać 5 stopni mrozu wilgotność 85% wiatr 4 m/s elektrodą',
    ]) {
      final r = (await h.say(text)).result as AnswerResult;
      expect(r.show!.fields['ambient_c'], -5.0, reason: text);
      expect(r.show!.fields['process'], 'mma111', reason: text);
    }
  });

  test('unstated material is assumed aloud, never silently', () async {
    final h = BrainHarness();
    addTearDown(h.timer.dispose);
    final r = (await h.say(
            'warunki do spawania temperatura 10 stopni wilgotność 70% wiatr 1 m/s 135'))
        .result as AnswerResult;
    expect(r.answer.text.pl, contains('Przyjąłem stal węglową'));
    final s = (await h.say(
            'warunki do spawania temperatura 10 stopni wilgotność 70% wiatr 1 m/s 135 nierdzewka'))
        .result as AnswerResult;
    expect(s.answer.text.pl, isNot(contains('Przyjąłem')));
    expect(s.show!.fields['material'], 'stainless');
  });

  test('dialogue asks for measurements and the process', () async {
    final h = BrainHarness();
    addTearDown(h.timer.dispose);
    Future<String> ask(String text) async =>
        ((await h.say(text)).result as AskResult).slot;
    expect(await ask('sprawdź warunki do spawania'), 'ambient_c');
    expect(await ask('8 stopni'), 'rh_pct');
    expect(await ask('75%'), 'wind_ms');
    expect(await ask('3 m/s'), 'process');
    final r = (await h.say('migomag')).result as AnswerResult;
    expect(r.show!.fields['process'], 'mag135');
    expect(r.show!.fields['wind_ms'], 3.0);
  });

  test('interpass and preheat questions are not weather checks', () async {
    final h = BrainHarness();
    addTearDown(h.timer.dispose);
    final reply = await h.say('jaka temperatura międzyściegowa dla P91');
    expect(reply.match?.skill.id, isNot('weather.check'));
  });
}
