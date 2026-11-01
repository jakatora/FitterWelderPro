import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:cut_list_app/services/premium_service.dart';
import 'package:cut_list_app/services/ai_chat_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import '../support/test_account.dart';
import '../support/test_database.dart';
import 'ai_chat_execution_test.dart' show mount;
import 'global_pipe_slope_flow_test.dart' show say, settle;

void main() {
  useGuestAccount();
  useTestDatabase();
  testWidgets('bare topic change asks locally and clears the old clarification', (t) async {
    final chats = <Map>[];
    await http.runWithClient(() async {
      await mount(t, interpret: (_) async => throw StateError('Topic change must stay local'));
      PremiumService.instance.resetForTest();
      await say(t, 'Jak dobrać gaz do spawania?');
      expect(chats, hasLength(1));
      await say(t, 'Mam inne pytanie');
      expect(chats, hasLength(1));
      expect(find.textContaining('Jasne — o co chcesz zapytać?'), findsWidgets);
      await say(t, 'Jak spawać aluminium?');
      expect(chats, hasLength(2));
      expect(chats.last.containsKey('question_clarification'), isFalse);
      expect(t.takeException(), isNull);
    }, () => MockClient((r) async {
      if (r.url.path.endsWith('/ai/chat')) chats.add(jsonDecode(r.body) as Map);
      return http.Response(jsonEncode({
        'text': chats.length == 1 ? 'Jaka metoda i materiał?' : 'Nowe wyjaśnienie',
        'needs_clarification': chats.length == 1,
        'question_clarification_used': true, 'calculator_context_used': true,
      }), 200, headers: {'content-type': 'application/json; charset=utf-8'});
    }));
  });
  for (final newQuestion in [
    'Mam inne pytanie: dlaczego powstają pory?',
    'New question: why does porosity occur?',
  ]) {
    testWidgets('explicit new topic does not carry a previous clarification: $newQuestion', (t) async {
      final chats = <Map>[];
      await http.runWithClient(() async {
        await mount(t, interpret: (_) async => throw StateError('A new knowledge topic is not a command'));
        PremiumService.instance.resetForTest();
        await say(t, 'Jak dobrać gaz do spawania?');
        await say(t, newQuestion);
        expect(chats, hasLength(2));
        expect(chats.last['message'], newQuestion);
        expect(chats.last.containsKey('question_clarification'), isFalse);
        expect((chats.last['history'] as List).any((m) => m['text'] == 'Jak dobrać gaz do spawania?'), isTrue);
        expect(find.textContaining('Wyjaśnienie nowego tematu'), findsWidgets);
        expect(t.takeException(), isNull);
      }, () => MockClient((r) async {
        if (r.url.path.endsWith('/ai/chat')) chats.add(jsonDecode(r.body) as Map);
        return http.Response(jsonEncode({
          'text': chats.length == 1 ? 'Jaka metoda i materiał?' : 'Wyjaśnienie nowego tematu',
          'needs_clarification': chats.length == 1,
          'question_clarification_used': true,
          'calculator_context_used': true,
        }), 200, headers: {'content-type': 'application/json; charset=utf-8'});
      }));
    });
  }
  for (final failureKind in [AiReplyKind.unavailable, AiReplyKind.offlineHelp]) {
    testWidgets('temporary initial knowledge failure has one explicit retry: $failureKind', (t) async {
      final questions = <String>[];
      await mount(t, interpret: (_) async => throw StateError('No command expected'),
          chatSender: (text, _) async {
        questions.add(text);
        return ChatMessage(role: ChatRole.assistant,
            text: questions.length == 1 ? 'Chwilowy brak połączenia' : 'Odpowiedź po przywróceniu połączenia',
            kind: questions.length == 1 ? failureKind : AiReplyKind.live);
      });
      await say(t, 'Wyjaśnij spawanie TIG');
      expect(questions, hasLength(1), reason: 'never retry automatically');
      final retry = t.widget<SnackBarAction>(find.byType(SnackBarAction)).onPressed;
      retry();
      retry();
      await settle(t);
      expect(questions, ['Wyjaśnij spawanie TIG', 'Wyjaśnij spawanie TIG']);
      expect(find.textContaining('Odpowiedź po przywróceniu połączenia'), findsWidgets);
      expect(t.takeException(), isNull);
    });
  }
  testWidgets('old knowledge retry cannot repeat after a native command', (t) async {
    var questions = 0;
    await mount(t, interpret: (_) async => throw StateError('Native calculation must stay local'),
        chatSender: (_, __) async { questions++; throw StateError('Fixture offline'); });
    await say(t, 'Wyjaśnij spawanie TIG');
    final retry = t.widget<SnackBarAction>(find.byType(SnackBarAction)).onPressed;
    await say(t, 'spadek 1% na 6 metrów');
    await t.enterText(find.byKey(const Key('assistant-command')), 'Nie usuwaj tego szkicu');
    retry();
    await settle(t);
    expect(questions, 1);
    expect(t.widget<TextField>(find.byKey(const Key('assistant-command'))).controller!.text,
        'Nie usuwaj tego szkicu');
    expect(t.takeException(), isNull);
  });
  testWidgets('an old retry cannot mix a failed question with a newer clarification', (t) async {
    final questions = <String>[];
    await mount(t, interpret: (_) async => throw StateError('No command expected'),
        chatSender: (text, _) async {
      questions.add(text);
      if (questions.length == 1) throw StateError('Fixture connection lost');
      return ChatMessage(role: ChatRole.assistant, text: 'Jaki materiał?',
          kind: AiReplyKind.live, needsClarification: true);
    });
    await say(t, 'Wyjaśnij spawanie TIG');
    final oldRetry = t.widget<SnackBarAction>(find.byType(SnackBarAction)).onPressed;
    await say(t, 'Jak dobrać gaz do spawania?');
    expect(questions, hasLength(2));
    oldRetry();
    await settle(t);
    expect(questions, ['Wyjaśnij spawanie TIG', 'Jak dobrać gaz do spawania?']);
    expect(find.textContaining('Jaki materiał?'), findsWidgets);
    expect(t.takeException(), isNull);
  });
  for (final question in [
    'Jak spawać nierdzewkę metodą TIG?',
    'Jaki gaz dobrać do spawania nierdzewki?',
    'Dlaczego powstają pory w spoinie?',
    'How do I weld stainless steel with TIG?',
    'Explain the difference between MIG and MAG',
    'Wyszukaj w internecie informacje o spawaniu hybrydowym',
    'Search the web for hybrid welding information',
    'Pomóż mi zrozumieć, dlaczego spoina ma pory',
    'Czy możesz mi pomóc zrozumieć spawanie TIG?',
    'Can you help me understand TIG welding?',
  ]) {
    testWidgets('answers question instead of asking for a module: $question',
        (t) async {
      var interpretations = 0;
      final chats = <Map>[];
      await http.runWithClient(() async {
        await mount(t, interpret: (_) async {
          interpretations++;
          throw StateError('A knowledge question is not a module command');
        });
        PremiumService.instance.resetForTest();
        await say(t, question);
        expect(interpretations, 0);
        expect(chats, hasLength(1));
        expect(chats.single['message'], question);
        expect(chats.single['conversation_mode'], true);
        expect(find.textContaining('Odpowiedź oparta na wiedzy aplikacji'),
            findsWidgets);
        expect(t.takeException(), isNull);
      },
          () => MockClient((r) async {
                if (r.url.path.endsWith('/ai/chat')) {
                  chats.add(jsonDecode(r.body) as Map);
                }
                return http.Response(
                    jsonEncode({
                      'text': 'Odpowiedź oparta na wiedzy aplikacji',
                      'citations': ['TIG'],
                      'needs_clarification': false,
                      'calculator_context_used': true
                    }),
                    200,
                    headers: {
                      'content-type': 'application/json; charset=utf-8'
                    });
              }));
    });
  }
  testWidgets(
      'short answer continues the AI question instead of selecting a module',
      (t) async {
    final chats = <Map>[];
    await http.runWithClient(() async {
      await mount(t,
          interpret: (_) async =>
              throw StateError('Unexpected interpretation'));
      PremiumService.instance.resetForTest();
      await say(t, 'Jak dobrać gaz do spawania?');
      expect(find.textContaining('Jaka metoda i materiał?'), findsWidgets);
      await say(t, 'TIG, stal nierdzewna 316L');
      expect(chats, hasLength(2));
      expect(chats.last['question_clarification'], {
        'user_turns': ['Jak dobrać gaz do spawania?'],
      });
      expect(chats.last['message'], 'TIG, stal nierdzewna 316L');
      expect(find.textContaining('Uwzględniam TIG i 316L'), findsWidgets);
      expect(t.takeException(), isNull);
    },
        () => MockClient((r) async {
              if (r.url.path.endsWith('/ai/chat')) {
                chats.add(jsonDecode(r.body) as Map);
              }
              final clarifying = chats.length == 1;
              return http.Response(
                  jsonEncode({
                    'text': clarifying
                        ? 'Jaka metoda i materiał?'
                        : 'Uwzględniam TIG i 316L',
                    'citations': [],
                    'needs_clarification': clarifying,
                    'calculator_context_used': true,
                    'question_clarification_used': true,
                  }),
                  200,
                  headers: {'content-type': 'application/json; charset=utf-8'});
            }));
  });

  for (final followUp in [
    'A 316L?',
    'And stainless steel?',
    'A dla aluminium?',
    'A jeśli spoina ma pory?',
    'What about aluminium?',
    'And for thicker material?',
  ]) {
    testWidgets('follow-up stays in the conversation: $followUp', (t) async {
      final chats = <Map>[];
      var interpretations = 0;
      await http.runWithClient(() async {
        await mount(t, interpret: (_) async {
          interpretations++;
          throw StateError('A follow-up is not a module request');
        });
        PremiumService.instance.resetForTest();
        await say(t, 'Jak spawać nierdzewkę metodą TIG?');
        await say(t, followUp);
        expect(interpretations, 0);
        expect(chats, hasLength(2));
        expect(chats.last['message'], followUp);
        expect(chats.last['history'], [
          {'role': 'user', 'text': 'Jak spawać nierdzewkę metodą TIG?'},
          {'role': 'assistant', 'text': 'Odpowiedź do pierwszego pytania.'},
        ]);
        expect(find.textContaining('Odpowiedź do kontynuacji.'), findsWidgets);
        expect(t.takeException(), isNull);
      },
          () => MockClient((request) async {
                if (request.url.path.endsWith('/ai/chat')) {
                  chats.add(jsonDecode(request.body) as Map);
                }
                return http.Response(
                    jsonEncode({
                      'text': chats.length == 1
                          ? 'Odpowiedź do pierwszego pytania.'
                          : 'Odpowiedź do kontynuacji.',
                      'citations': [],
                      'needs_clarification': false,
                      'calculator_context_used': true,
                    }),
                    200,
                    headers: {
                      'content-type': 'application/json; charset=utf-8'
                    });
              }));
    });
  }
}
