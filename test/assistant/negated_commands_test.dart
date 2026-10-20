import 'package:flutter_test/flutter_test.dart';
import 'package:cut_list_app/assistant/core/skill.dart';
import 'package:cut_list_app/i18n/app_language.dart';
import 'support/assistant_test_support.dart';

void main() {
  for (final entry in {
    'nie obliczaj spadku 2% na 6 metrów': AppLanguage.pl,
    'proszę nie przeliczaj 2 cale na mm': AppLanguage.pl,
    'nie otwieraj fazowania': AppLanguage.pl,
    'nie skracaj redukcji duża 100 mm mała 50 mm długość 200 mm docelowa 75 mm':
        AppLanguage.pl,
    'do not trim reducer large 100 mm small 50 mm length 200 mm target 75 mm':
        AppLanguage.en,
    'nie zapisz TIG 90 A 2 mm': AppLanguage.pl,
    'do not convert 2 inches to mm': AppLanguage.en,
    "don't calculate slope 2% over 6 meters": AppLanguage.en,
    'please do not draw a pipe': AppLanguage.en,
  }.entries) {
    test('negation never executes: ${entry.key}', () async {
      final h = BrainHarness(lang: entry.value);
      final r = await h.say(entry.key,
          byVoice: true, alternatives: ['convert 2 inches to mm']);
      expect(r.match, isNull);
      final answer = r.result as AnswerResult;
      expect(answer.show, isNull);
      expect(h.actions.savedParams, isEmpty);
      expect(h.actions.savedJournal, isEmpty);
    });
  }
  test('negation cancels pending input and alternative cannot reactivate it',
      () async {
    final h = BrainHarness();
    expect((await h.say('oblicz spadek')).result, isA<AskResult>());
    expect(h.brain.pending, isNotNull);
    final r = await h.say('nie obliczaj spadku 1% na 6 metrów');
    expect((r.result as AnswerResult).show, isNull);
    expect(h.brain.pending, isNull);
  });
  test('negated speech alternative is never treated as a positive command',
      () async {
    final r = await BrainHarness().say('yyy',
        byVoice: true, alternatives: ['nie przeliczaj 2 cale na mm']);
    expect(r.result, isA<NotUnderstood>());
  });
  test(
      'temperature difference is refused without blocking pressure differences',
      () async {
    expect(
        (await BrainHarness().say('przelicz różnicę temperatur 10 C na F'))
            .result,
        isA<FailedResult>());
    expect(
        (await BrainHarness().say('przelicz różnicę ciśnienia 1 bar na psi'))
            .result,
        isA<AnswerResult>());
  });
}
