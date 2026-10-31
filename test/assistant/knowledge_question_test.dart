import 'package:cut_list_app/assistant/knowledge_question.dart';
import 'package:cut_list_app/assistant/core/utterance.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cut_list_app/i18n/app_language.dart';
void main() {
  for(final text in [
    'Jak spawać TIG?', 'Jak zmienić wymiar?', 'Czy mogę zmienić wymiar?',
    'Jaki gaz dobrać?', 'Dlaczego powstają pory?', 'Explain MIG versus MAG',
    'How do I change the dimension?',
  ]) {
    test('explanation is not execution: $text',() {
      expect(isKnowledgeQuestion(Utterance(text, lang: AppLanguage.pl)),isTrue);
      expect(requestsConversationAction(Utterance(text, lang: AppLanguage.pl)),isFalse);
    });
  }
  for(final text in [
    'Czy możesz zmniejszyć szczelinę o 1 mm', 'Czy możesz zmienić wymiar?',
    'Could you please set the second pipe to 500 mm?', 'Oblicz heat input',
    'Otwórz kalkulator', 'Zapisz TIG 100 A',
  ]) {
    test('explicit action retains native workflow: $text',() {
      expect(requestsConversationAction(Utterance(text, lang: AppLanguage.pl)),isTrue);
      expect(isKnowledgeQuestion(Utterance(text, lang: AppLanguage.pl)),isFalse);
    });
  }
}
