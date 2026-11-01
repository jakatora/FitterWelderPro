import 'package:cut_list_app/assistant/knowledge_question.dart';
import 'package:cut_list_app/assistant/core/utterance.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cut_list_app/i18n/app_language.dart';

void main() {
  test('how many retains deterministic numeric lookups', () {
    expect(
        isExplanationQuestion(
            Utterance('How many DI today?', lang: AppLanguage.en)),
        isFalse);
  });
  for (final text in [
    'Jak spawać TIG?',
    'Jak zmienić wymiar?',
    'Czy mogę zmienić wymiar?',
    'Jaki gaz dobrać?',
    'Dlaczego powstają pory?',
    'Explain MIG versus MAG',
    'How do I change the dimension?',
    'Czy możesz wyjaśnić spawanie TIG?',
    'Could you please explain TIG welding?',
    'Wyszukaj w internecie informacje o spawaniu hybrydowym',
    'Search the web for hybrid welding information',
    'A dla aluminium?',
    'A jeśli spoina ma pory?',
    'And for thicker material?',
    'A jak spawać TIG?',
    'Pomóż mi zrozumieć, dlaczego spoina ma pory',
    'Czy możesz pomóc mi zrozumieć spawanie TIG?',
    'Czy możesz mi pomóc zrozumieć wynik kalkulatora?',
    'Can you help me understand TIG welding?',
    'Could you please help me understand this result?',
    'Please help me understand porosity',
  ]) {
    test('explanation is not execution: $text', () {
      expect(
          isKnowledgeQuestion(Utterance(text, lang: AppLanguage.pl)), isTrue);
      expect(requestsConversationAction(Utterance(text, lang: AppLanguage.pl)),
          isFalse);
    });
  }
  for (final text in [
    'Czy możesz zmniejszyć szczelinę o 1 mm',
    'Czy możesz zmienić wymiar?',
    'Could you please set the second pipe to 500 mm?',
    'Oblicz heat input',
    'Otwórz kalkulator',
    'Zapisz TIG 100 A',
    'Czy możesz nazwać rysunek?',
    'Czy możesz podsumować aktualny rysunek ISO?',
    'A otwórz kalkulator',
    'And set the second pipe to 500 mm',
    'A czy możesz podsumować rysunek?',
    'Czy możesz pomóc mi otworzyć kalkulator?',
    'Can you help me open the calculator?',
  ]) {
    test('explicit action retains native workflow: $text', () {
      expect(requestsConversationAction(Utterance(text, lang: AppLanguage.pl)),
          isTrue);
      expect(
          isKnowledgeQuestion(Utterance(text, lang: AppLanguage.pl)), isFalse);
    });
  }
}
