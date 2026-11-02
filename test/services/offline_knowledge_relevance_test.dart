import 'package:flutter_test/flutter_test.dart';
import 'package:cut_list_app/i18n/app_language.dart';
import 'package:cut_list_app/services/ai_chat_service.dart';

void main() {
  final original = AppLanguageController.current;
  tearDown(() => AppLanguageController.current = original);
  for (final query in [
    'Pomóż mi dobrać gaz osłonowy do nierdzewki',
    'Jaki gaz osłonowy wybrać do spawania stali nierdzewnej?',
  ]) {
    test('offline shielding gas selection gives actionable context: $query', () {
      AppLanguageController.current = AppLanguage.pl;
      final reply = AiChatService.instance.offlineReply(query);
      expect(reply.text, contains('Dobór spoiwa'));
      expect(reply.text, contains('gatunk'));
      expect(reply.text, contains('proces'));
      expect(reply.text, contains('WPS'));
      expect(reply.citations, isNotEmpty);
    });
  }
  test('English offline gas selection points to the selector', () {
    AppLanguageController.current = AppLanguage.en;
    final reply = AiChatService.instance.offlineReply(
        'Help me choose a shielding gas for stainless steel welding');
    expect(reply.text, contains('Filler metal selector'));
    expect(reply.text, contains('grade'));
    expect(reply.text, contains('process'));
    expect(reply.text, contains('WPS'));
    expect(reply.citations, isNotEmpty);
  });
  for (final language in AppLanguage.values) {
    test('gas flow question still finds the flow entry: $language', () {
      AppLanguageController.current = language;
      final reply = AiChatService.instance.offlineReply(language == AppLanguage.pl
          ? 'Jaki przepływ gazu osłonowego ustawić?'
          : 'What shielding gas flow should be set?');
      expect(reply.text, contains(language == AppLanguage.pl
          ? 'Jaki przepływ gazu osłonowego ustawić?'
          : 'What shielding gas flow should be set?'));
    });
  }
  for (final query in [
    'Jaki przepływ gazu osłonowego do spawania nierdzewki TIG?',
    'What shielding gas flow for stainless steel TIG welding?',
  ]) {
    test('gas flow is not mistaken for gas selection: $query', () {
      AppLanguageController.current = query.startsWith('What')
          ? AppLanguage.en : AppLanguage.pl;
      final reply = AiChatService.instance.offlineReply(query);
      expect(reply.text, isNot(contains('Filler metal selector')));
      expect(reply.text, isNot(contains('Dobór spoiwa')));
    });
  }
  test('porosity question does not return unrelated imported weld help', () {
    AppLanguageController.current = AppLanguage.pl;
    final reply =
        AiChatService.instance.offlineReply('dlaczego powstaja pory w spoinie');
    expect(reply.text, isNot(contains('spoin z importu')));
    expect(reply.citations, isEmpty);
    expect(reply.text, contains('Nie znalazłem'));
  });
  test('English porosity question does not return unrelated imported weld help',
      () {
    AppLanguageController.current = AppLanguage.en;
    final reply = AiChatService.instance
        .offlineReply('why does porosity appear in welds');
    expect(reply.text, isNot(contains('imported welds')));
  });
  for (final language in AppLanguage.values) {
    test('pump NPSH keeps its own offline entry: $language', () {
      AppLanguageController.current = language;
      final reply = AiChatService.instance.offlineReply('NPSH');
      expect(reply.text,
          contains(language == AppLanguage.pl ? 'Co to NPSH' : 'What is NPSH'));
    });

    for (final query in ['DN', 'DN25', 'NPS', 'NPS1']) {
      test('nominal pipe size offline help is not pump NPSH: $language $query',
          () {
        AppLanguageController.current = language;
        final reply = AiChatService.instance.offlineReply(query);
        expect(reply.citations, isNotEmpty);
        expect(
            reply.text,
            contains(language == AppLanguage.pl
                ? 'Co oznaczają DN i NPS?'
                : 'What do DN and NPS mean?'));
      });
    }

    test('offline help does not match only question words: $language', () {
      AppLanguageController.current = language;
      final reply = AiChatService.instance.offlineReply(
          language == AppLanguage.pl
              ? 'Jak naprawić teleskop astronomiczny?'
              : 'How can I repair an astronomical telescope?');
      expect(reply.kind, AiReplyKind.offlineHelp);
      expect(reply.citations, isEmpty);
      expect(
          reply.text,
          contains(language == AppLanguage.pl
              ? 'Nie znalazłem'
              : 'I found nothing'));
    });
    test(
        'a technical offline hit is labelled as a related help entry: $language',
        () {
      AppLanguageController.current = language;
      final reply = AiChatService.instance.offlineReply('preheat P91');
      expect(reply.kind, AiReplyKind.offlineHelp);
      expect(reply.citations, isNotEmpty);
      expect(
          reply.text,
          contains(language == AppLanguage.pl
              ? 'Najbliższy wpis pomocy'
              : 'Closest help entry'));
      expect(reply.text, contains('P91'));
    });
  }
}
