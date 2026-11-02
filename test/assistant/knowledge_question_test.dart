import 'package:cut_list_app/assistant/knowledge_question.dart';
import 'package:cut_list_app/assistant/core/utterance.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cut_list_app/i18n/app_language.dart';

void main() {
  for (final text in [
    'Pomóż mi dobrać gaz osłonowy do nierdzewki',
    'Pomóż mi dobrać gaz i ustawienia do TIG',
    'Pomóż mi wybrać metodę spawania',
    'Pomóż mi dobrać wariant do mojego zadania',
    'Czy możesz mi pomóc dobrać parametry TIG dla 3 mm?',
    'Potrzebuję porady dotyczącej spawania aluminium',
    'Help me choose a shielding gas',
    'Could you help me choose a welding process?',
    'I need advice about welding stainless steel',
  ]) {
    test('requests for help deciding are questions, not module commands: $text',
        () {
      final u = Utterance(text, lang: AppLanguage.pl);
      expect(isKnowledgeQuestion(u), isTrue);
      expect(isExplanationQuestion(u), isTrue);
      expect(requestsConversationAction(u), isFalse);
    });
  }
  for (final text in [
    'Czyli to zmierzona średnica w milimetrach?',
    'Więc to średnica zewnętrzna?',
    'To znaczy nominalna?',
    'So it is the measured diameter?',
    'Does that mean nominal size?',
    'In other words it is nominal?',
    'You mean nominal size?',
    'Does that mean open the valve?',
    'You mean delete the pipe?',
  ]) {
    test('conversational inference stays a knowledge follow-up: $text', () {
      final u = Utterance(text, lang: AppLanguage.pl);
      expect(isEllipticalKnowledgeFollowUp(u), isTrue);
      expect(isKnowledgeQuestion(u), isTrue);
      expect(requestsConversationAction(u), isFalse);
    });
  }
  for (final text in [
    'Czyli otwórz kalkulator', 'Więc usuń rurę',
    'So open the calculator', 'Then delete the pipe',
    'To znaczy oblicz spadek',
  ]) {
    test('inference marker cannot swallow an explicit command: $text', () {
      final u = Utterance(text, lang: AppLanguage.pl);
      expect(requestsConversationAction(u), isTrue);
      expect(isEllipticalKnowledgeFollowUp(u), isFalse);
      expect(isKnowledgeQuestion(u), isFalse);
    });
  }

  for (final text in [
    'A zmniejsz szczelinę o 1 mm?', 'A zwiększ długość rury',
    'A skróć drugi odcinek', 'A wydłuż rurę', 'A obróć kolano',
    'A przesuń element', 'A cofnij zmianę', 'A powtórz zmianę',
    'And decrease the gap?', 'And increase the length',
    'And shorten the pipe', 'And extend the pipe', 'And rotate the elbow',
    'And move the element', 'And undo', 'And redo', 'And rename the project',
    'And reset the calculator',
  ]) {
    test('editing verbs cannot become conversational follow-ups: $text', () {
      final u = Utterance(text, lang: AppLanguage.pl);
      expect(requestsConversationAction(u), isTrue);
      expect(isEllipticalKnowledgeFollowUp(u), isFalse);
      expect(isKnowledgeQuestion(u), isFalse);
    });
  }
  test('unpunctuated follow-ups require conversation context and exclude actions', () {
    for (final text in ['A 316L', 'And stainless steel', 'Czyli nominalna', 'So nominal size']) {
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
    'Czy możesz doradzić dla rury DN50?',
    'Poleć gaz do TIG',
    'Could you compare NPS 2 and DN50?',
  ]) {
    test('advice remains an explanation with numbers: $text', () {
      expect(isExplanationQuestion(Utterance(text, lang: AppLanguage.pl)), isTrue);
    });
  }
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
    'Czy możesz doradzić, jaki gaz wybrać?',
    'Czy możesz porównać MIG i TIG?',
    'Doradź jaki gaz do nierdzewki',
    'Poleć gaz do TIG',
    'Can you recommend a shielding gas?',
    'Could you compare MIG and TIG?',
    'Recommend a shielding gas',
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
    'Czy możesz mi pomóc ustawić szczelinę?',
    'Could you help me calculate the pipe length?',
    'Pomóż mi wybrać gaz i otwórz kalkulator',
    'Help me choose a gas and open the calculator',
    'Pomóż mi dobrać gaz i pokaż kalkulator',
    'Help me choose a gas and save the project',
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
