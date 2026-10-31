import 'dart:convert';
import 'package:cut_list_app/services/premium_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import '../support/test_account.dart';
import '../support/test_database.dart';
import 'ai_chat_execution_test.dart' show mount;
import 'global_pipe_slope_flow_test.dart' show say;

void main() {
  useGuestAccount();
  useTestDatabase();
  for (final question in [
    'Jak spawać nierdzewkę metodą TIG?',
    'Jaki gaz dobrać do spawania nierdzewki?',
    'Dlaczego powstają pory w spoinie?',
    'How do I weld stainless steel with TIG?',
    'Explain the difference between MIG and MAG',
    'Wyszukaj w internecie informacje o spawaniu hybrydowym',
    'Search the web for hybrid welding information',
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
}
