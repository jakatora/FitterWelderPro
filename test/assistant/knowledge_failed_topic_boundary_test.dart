import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:cut_list_app/services/premium_service.dart';
import '../support/test_account.dart';
import '../support/test_database.dart';
import 'ai_chat_execution_test.dart' show mount;
import 'global_pipe_slope_flow_test.dart' show say;

void main() {
  useGuestAccount();
  useTestDatabase();
  for (final transition in [
    'anuluj',
    'Mam inne pytanie',
    'spadek 1% na 6 metrów'
  ]) {
    testWidgets('failed knowledge context stops after: $transition', (t) async {
      final chats = <Map>[];
      await http.runWithClient(() async {
        await mount(t,
            interpret: (_) async =>
                throw StateError('No interpretation expected'));
        PremiumService.instance.resetForTest();
        await say(t, 'Jak dobrać gaz do spawania TIG?');
        await say(t, transition);
        expect(chats, hasLength(1));
        await say(t, 'A co oznacza DN na rurze?');
        expect(chats, hasLength(2));
        expect(chats.last.containsKey('question_clarification'), isFalse);
        expect((chats.last['history'] as List).any((m) =>
            (m as Map)['text'] == 'Jak dobrać gaz do spawania TIG?'), isFalse);
        if (transition.startsWith('spadek')) {
          expect((chats.last['history'] as List).first['text'], transition);
        }
        expect(find.textContaining('Nowy temat DN'), findsWidgets);
        expect(t.takeException(), isNull);
      },
          () => MockClient((r) async {
                chats.add(jsonDecode(r.body) as Map);
                if (chats.length == 1) {
                  return http.Response('{"error":{"code":"AI_BUSY"}}', 503);
                }
                return http.Response(
                    jsonEncode({
                      'text': 'Nowy temat DN',
                      'question_clarification_used': true,
                      'calculator_context_used': true
                    }),
                    200,
                    headers: {
                      'content-type': 'application/json; charset=utf-8'
                    });
              }));
    });
  }
}
