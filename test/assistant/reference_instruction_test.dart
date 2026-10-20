import 'package:flutter_test/flutter_test.dart';
import 'package:cut_list_app/assistant/assistant_engine.dart';
import 'package:cut_list_app/assistant/assistant_intents.dart';
import 'package:cut_list_app/assistant/assistant_parser.dart';
import 'package:cut_list_app/assistant/core/skill.dart';
import 'package:cut_list_app/assistant/skills/iso/iso_command_parser.dart';
import 'package:cut_list_app/i18n/app_language.dart';
import 'support/assistant_test_support.dart';

void main() {
  const phrases = [
    'Przetłumacz: narysuj rurę 2 m w prawo',
    'Translate: save TIG stainless 2 mm 60 A',
    'Wyjaśnij polecenie oblicz masę rury DN50 3 mm 2 m',
    'What does draw pipe 2 m right mean?',
    'Jak powiedzieć po angielsku zapisz TIG 2 mm 60 A',
    'Co to znaczy narysuj rurę 2 m w prawo',
    'Jak jest po angielsku zapisz TIG 2 mm 60 A',
  ];
  for (final text in phrases) {
    test('quoted action remains a question: $text', () async {
      expect(parseAssistantCommand(text).intent, kIntentAnswerQuestion);
      expect(parseIsoCommand(Utterance(text, lang: AppLanguage.pl)), isNull);
      final h = BrainHarness(activeToolId: 'pipe_weight');
      await h.say('Oblicz masę rury');
      final r = await h
          .say(text, byVoice: true, alternatives: ['narysuj rurę 2 m w prawo']);
      expect(r.result, isNot(isA<ConfirmResult>()));
      expect(r.match?.skill.id,
          anyOf(isNull, 'knowledge', 'glossary.term', 'tool.explain'));
      expect(h.brain.pending, isNull);
      expect(h.actions.savedParams, isEmpty);
      var consentChecks = 0;
      final engine = AssistantEngine(remoteAllowed: () async {
        consentChecks++;
        return false;
      });
      final outcome = await engine.interpret(text,
          lang: AppLanguage.pl,
          carriedIntent: kIntentSaveWeldParameter,
          carried: {'process': 'TIG'},
          answeringField: 'current_a');
      expect(outcome.intent, kIntentAnswerQuestion);
      expect(outcome.fields, {'text': text});
      expect(consentChecks, 0);
    });
  }
  test('normal commands and dictionary translations remain available',
      () async {
    expect(parseAssistantCommand('zapisz TIG 2 mm 60 A').intent,
        kIntentSaveWeldParameter);
    expect(
        parseIsoCommand(
            Utterance('narysuj rurę 2 m w prawo', lang: AppLanguage.pl)),
        isNotNull);
    final r = await BrainHarness().say('przetłumacz WPS na niemiecki');
    expect(r.match?.skill.id, 'glossary.term');
    expect(r.result, isA<AnswerResult>());
  });
}
