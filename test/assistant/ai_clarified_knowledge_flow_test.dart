import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:cut_list_app/assistant/assistant_ai_client.dart';
import 'package:cut_list_app/assistant/core/skill.dart';
import 'package:cut_list_app/services/account_service.dart';
import 'package:cut_list_app/services/premium_service.dart';
import '../support/test_account.dart';
import '../support/test_database.dart';
import 'ai_chat_execution_test.dart' show mount, FixtureSkill, FixtureSpeech;
import 'global_pipe_slope_flow_test.dart' show say, settle;

void main() {
  useGuestAccount();
  useTestDatabase();
  for (final voice in [false, true]) {
    for (final mode in ['normal', 'retry', 'expired', 'oldServer']) {
      testWidgets(
          'clarified knowledge voice=$voice mode=$mode preserves the original question',
          (t) async {
        final turns = [
          'Ogarnij mi temat temperatury międzyściegowej dla tego pomiaru',
          'dla spoiny rurowej',
          'przed drugim ściegiem',
          'jeszcze jeden szczegół'
        ];
        final requests = <http.Request>[];
        List<http.Request> chats() =>
            requests.where((r) => r.url.path == '/api/fitter/ai/chat').toList();
        var calls = 0;
        final speech = FixtureSpeech();
        await http.runWithClient(() async {
          await mount(t, speech: speech, skills: [
            FixtureSkill(
                'fixture.question',
                'fixture question',
                (_) async => const AnswerResult(
                    AssistantAnswer(text: AssistantText.same('Fixture'))))
          ], interpret: (_) async {
            calls++;
            return calls < 5
                ? AiCommandPlan('clarify', [], 'Pytanie numer $calls')
                : const AiCommandPlan('answer', [], '');
          });
          PremiumService.instance.resetForTest();
          for (final turn in turns) {
            await say(t, turn);
          }
          if (voice) {
            await t.tap(find.byKey(const Key('assistant-mic')));
            await settle(t);
            speech.emit('termometrem kontaktowym');
            await settle(t);
          } else {
            await say(t, 'termometrem kontaktowym');
          }
          expect(calls, 5);
          expect(chats(), hasLength(1),
              reason: 'there is no automatic knowledge retry');
          if (mode == 'retry' || mode == 'expired') {
            expect(find.textContaining('Pełna odpowiedź na pytanie'),
                findsNothing);
            final action =
                t.widget<SnackBarAction>(find.byType(SnackBarAction));
            if (mode == 'expired') {
              await t.runAsync(AccountService.instance.invalidateSession);
              await settle(t);
            }
            action.onPressed();
            action.onPressed();
            await settle(t);
          }
          expect(chats(), hasLength(mode == 'retry' ? 2 : 1));
          expect(calls, 5,
              reason: 'knowledge retry must not repeat interpretation');
          final body = jsonDecode(chats().last.body) as Map;
          File('build/clarified-knowledge-wire-${voice ? 'voice' : 'text'}-$mode.json')
              .writeAsStringSync(chats().last.body);
          expect(body['message'], 'termometrem kontaktowym');
          expect(
              (body['history'] as List)
                  .any((m) => (m as Map)['text'] == turns.first),
              false);
          expect(body['question_clarification'], {'user_turns': turns});
          expect(
              find.textContaining('Pełna odpowiedź na pytanie'),
              mode == 'expired' || mode == 'oldServer'
                  ? findsNothing
                  : findsWidgets);
          if (mode == 'oldServer') {
            expect(find.byType(SnackBarAction), findsNothing);
            expect(find.textContaining('Zadaj całe pytanie ponownie'),
                findsWidgets);
          }
          expect(t.takeException(), isNull);
        },
            () => MockClient((r) async {
                  requests.add(r);
                  if ((mode == 'retry' || mode == 'expired') &&
                      r.url.path == '/api/fitter/ai/chat' &&
                      chats().length == 1) {
                    return http.Response(
                        jsonEncode({
                          'error': {'code': 'AI_BUSY'}
                        }),
                        503);
                  }
                  return http.Response(
                      jsonEncode({
                        'text': 'Pełna odpowiedź na pytanie',
                        'citations': [],
                        if (mode != 'oldServer')
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
}
