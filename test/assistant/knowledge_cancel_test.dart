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
  for (final cancel in ['anuluj', 'stop', 'cancel']) {
    for (final failed in [false, true]) {
      testWidgets(
          'knowledge cancellation clears clarification: $cancel failed=$failed',
          (tester) async {
        final chats = <Map<String, dynamic>>[];
        await http.runWithClient(() async {
          await mount(tester,
              interpret: (_) async => throw StateError(
                  'Cancellation and knowledge need no interpretation'));
          PremiumService.instance.resetForTest();
          await say(tester, 'Jak dobrać gaz do spawania?');
          if (failed) await say(tester, 'TIG, stal nierdzewna 316L');
          final before = chats.length;
          await say(tester, cancel);
          expect(chats, hasLength(before));
          await say(tester, 'Co oznacza DN na rurze?');
          expect(chats, hasLength(before + 1));
          expect(chats.last.containsKey('question_clarification'), isFalse,
              reason:
                  'A cancelled clarification must not leak into the next question');
          expect(find.textContaining('DN jest oznaczeniem nominalnym'),
              findsWidgets);
          expect(tester.takeException(), isNull);
        },
            () => MockClient((request) async {
                  chats.add(jsonDecode(request.body) as Map<String, dynamic>);
                  if (failed && chats.length == 2) {
                    return http.Response('{"error":{"code":"AI_BUSY"}}', 503,
                        headers: {
                          'content-type': 'application/json; charset=utf-8'
                        });
                  }
                  return http.Response(
                      jsonEncode({
                        'text': chats.length == 1
                            ? 'Jaka metoda i materiał?'
                            : 'DN jest oznaczeniem nominalnym.',
                        'needs_clarification': chats.length == 1,
                        'question_clarification_used': true,
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
}
