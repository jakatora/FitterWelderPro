import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:cut_list_app/assistant/core/tool_bridge.dart';
import 'package:cut_list_app/services/premium_service.dart';
import '../support/test_account.dart';
import '../support/test_database.dart';
import 'ai_chat_execution_test.dart' show mount;
import 'global_pipe_slope_flow_test.dart' show say;

void main() {
  useGuestAccount();
  useTestDatabase();
  for (final afterClarification in [false, true]) {
    testWidgets(
        'daily limit preserves local calculation and excludes notice from AI history afterClarification=$afterClarification',
        (tester) async {
      final chats = <Map<String, dynamic>>[];
      var interpretations = 0;
      final limitedTurn = afterClarification ? 2 : 1;
      await http.runWithClient(() async {
        await mount(tester, interpret: (_) async {
          interpretations++;
          throw StateError('Known commands and questions use their own paths');
        });
        PremiumService.instance.resetForTest();
        await say(tester, 'Jak dobrać gaz do spawania?');
        if (afterClarification) {
          await say(tester, 'TIG, stal nierdzewna 316L');
        }
        expect(chats, hasLength(limitedTurn));
        expect(find.textContaining('Dzienny limit'), findsWidgets);
        expect(find.widgetWithText(SnackBarAction, 'Ponów'), findsNothing,
            reason: 'A daily quota is not a transient retry opportunity');
        await say(tester,
            'Rolling offset wznios 300 mm odsunięcie 400 mm kąt 45 stopni DN100 LR szczelina 3 mm');
        expect(chats, hasLength(limitedTurn));
        expect(interpretations, 0);
        expect(
            ToolBridge.instance.inputFields('rolling_offset')!['rise_mm'], 300);
        expect(ToolBridge.instance.inputFields('rolling_offset')!['spread_mm'],
            400);
        expect(find.text('573.1'), findsOneWidget);
        await say(tester, 'Mam inne pytanie: co oznacza DN na rurze?');
        expect(chats, hasLength(limitedTurn + 1));
        expect(chats.last.containsKey('question_clarification'), isFalse);
        final history = chats.last['history'] as List;
        expect(
            history.any(
                (m) => (m as Map)['text'].toString().contains('Dzienny limit')),
            isFalse);
        expect(find.textContaining('DN jest oznaczeniem nominalnym'),
            findsWidgets);
        expect(tester.takeException(), isNull);
      },
          () => MockClient((request) async {
                if (!request.url.path.endsWith('/ai/chat')) {
                  throw StateError('Unexpected request: ${request.url.path}');
                }
                chats.add(jsonDecode(request.body) as Map<String, dynamic>);
                if (chats.length == limitedTurn) {
                  return http.Response(
                      jsonEncode({
                        'error': {
                          'code': 'RATE_LIMITED',
                          'message':
                              'Dzienny limit pytań do asystenta AI został wyczerpany.'
                        }
                      }),
                      429,
                      headers: {
                        'content-type': 'application/json; charset=utf-8'
                      });
                }
                return http.Response(
                    jsonEncode({
                      'text': chats.length < limitedTurn
                          ? 'Jaka metoda i materiał?'
                          : 'DN jest oznaczeniem nominalnym.',
                      'needs_clarification': chats.length < limitedTurn,
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
  for (final followUp in ['A NPS 1?', 'A NPS 1']) {
    testWidgets('a nominal-size follow-up retains its conversation: $followUp',
        (tester) async {
      final chats = <Map<String, dynamic>>[];
      await http.runWithClient(() async {
        await mount(tester,
            interpret: (_) async => throw StateError(
                'A knowledge follow-up is not a module request'));
        PremiumService.instance.resetForTest();
        await say(tester, 'Co oznacza DN na rurze?');
        await say(tester, followUp);
        expect(chats, hasLength(2));
        expect(chats.last['message'], followUp);
        expect(chats.last['history'], [
          {'role': 'user', 'text': 'Co oznacza DN na rurze?'},
          {'role': 'assistant', 'text': 'DN jest oznaczeniem nominalnym.'},
        ]);
        expect(find.textContaining('Kontynuacja o NPS'), findsWidgets);
        expect(tester.takeException(), isNull);
      },
          () => MockClient((request) async {
                if (!request.url.path.endsWith('/ai/chat')) {
                  throw StateError('Unexpected request: ${request.url.path}');
                }
                chats.add(jsonDecode(request.body) as Map<String, dynamic>);
                return http.Response(
                    jsonEncode({
                      'text': chats.length == 1
                          ? 'DN jest oznaczeniem nominalnym.'
                          : 'Kontynuacja o NPS.',
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
