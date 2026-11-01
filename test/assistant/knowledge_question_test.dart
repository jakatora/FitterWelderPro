import 'package:cut_list_app/assistant/knowledge_question.dart';
import 'package:cut_list_app/assistant/core/utterance.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cut_list_app/i18n/app_language.dart';

void main() {
  test('unpunctuated follow-ups require conversation context and exclude actions', () {
    for (final text in ['A 316L', 'And stainless steel']) {
      final u = Utterance(text, lang: AppLanguage.pl);
      expect(isEllipticalKnowledgeFollowUp(u), isTrue);
      expect(isKnowledgeQuestion(u), isFalse);
    }
    for (final text in ['A dodaj projekt', 'And delete the pipe', '316L', 'A']) {
      expect(isEllipticalKnowledgeFollowUp(Utterance(text, lang: AppLanguage.pl)), isFalse);
    }
  });
  test('bare topic controls are distinct from questions and ordinary replies', () {
    for (final text in ['Mam inne pytanie', 'Zmieńmy temat', 'New question']) {
      expect(isBareKnowledgeTopicChange(Utterance(text, lang: AppLanguage.pl)), isTrue);
    }
    for (final text in ['Nowe pytanie: jak spawać TIG?', 'TIG, 316L']) {
      expect(isBareKnowledgeTopicChange(Utterance(text, lang: AppLanguage.pl)), isFalse);
    }
  });
  for (final text in [
    'Mam inne pytanie: dlaczego spoina ma pory?',
    'A nowe pytanie: jak spawać aluminium?',
    'Zmieńmy temat: co to jest TIG?',
    'New question: why does porosity occur?',
    'I have another question: how does TIG work?',
  ]) {
    test('explicit topic marker keeps the actual question: $text', () {
      final u = Utterance(text, lang: AppLanguage.pl);
      expect(startsNewKnowledgeTopic(u), isTrue);
      expect(isKnowledgeQuestion(u), isTrue);
      expect(isExplanationQuestion(u), isTrue);
      expect(requestsConversationAction(u), isFalse);
    });
  }
  for (final text in ['TIG, 316L', 'A dla aluminium?', 'Jak sformułować nowe pytanie?']) {
    test('ordinary context does not request a topic reset: $text', () {
      expect(startsNewKnowledgeTopic(Utterance(text, lang: AppLanguage.pl)), isFalse);
    });
  }
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
    'A 316L?',
    'And stainless steel?',
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
    'Nowe pytanie: otwórz kalkulator',
    'New question: set the second pipe to 500 mm',
  ]) {
    test('explicit action retains native workflow: $text', () {
      expect(requestsConversationAction(Utterance(text, lang: AppLanguage.pl)),
          isTrue);
      expect(
          isKnowledgeQuestion(Utterance(text, lang: AppLanguage.pl)), isFalse);
    });
  }
}
