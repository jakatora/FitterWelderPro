import 'dart:convert';

import 'package:cut_list_app/assistant/assistant_ai_client.dart';
import 'package:cut_list_app/services/premium_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../support/test_account.dart';
import '../support/test_database.dart';
import 'ai_chat_execution_test.dart' show mount;
import 'global_pipe_slope_flow_test.dart' show say, settle;
import 'speech_session_lifecycle_test.dart' show HeldSpeech;
import 'voice_session_screen_test.dart' show VoiceFake;

void main() {
  useGuestAccount();
  useTestDatabase();
  for (final byVoice in [false, true]) {
    testWidgets('knowledge request marks only spoken input: $byVoice', (tester) async {
      final speech = HeldSpeech();
      final voice = VoiceFake();
      final bodies = <Map<String, dynamic>>[];
      await http.runWithClient(() async {
        await mount(tester, speech: speech, voice: voice,
            interpret: (_) async => const AiCommandPlan('answer', [], ''));
        PremiumService.instance.resetForTest();
        if (byVoice) {
          await tester.tap(find.byKey(const Key('assistant-voice-session')));
          await settle(tester);
          speech.results.single('Jaki gaz do spawania metodą tę ideę?', true);
          await settle(tester);
        } else {
          await say(tester, 'Jaki gaz do spawania metodą tę ideę?');
        }
        expect(bodies, hasLength(1));
        expect(bodies.single['message'], 'Jaki gaz do spawania metodą tę ideę?');
        expect(bodies.single['speech_transcript'], byVoice ? true : null);
        expect(tester.takeException(), isNull);
      }, () => MockClient((request) async {
        expectSync(request.url.path, '/api/fitter/ai/chat');
        bodies.add(jsonDecode(request.body) as Map<String, dynamic>);
        return http.Response(jsonEncode({
          'text':'Jaką metodę spawania masz na myśli?',
          'citations':[], 'needs_clarification':true,
          'calculator_context_used':true,
        }), 200, headers:{'content-type':'application/json; charset=utf-8'});
      }));
    });
  }
  testWidgets('spoken clarification carries the original question to the next turn', (tester) async {
    final speech = HeldSpeech();
    final voice = VoiceFake();
    final bodies = <Map<String, dynamic>>[];
    await http.runWithClient(() async {
      await mount(tester, speech: speech, voice: voice,
          interpret: (_) async => const AiCommandPlan('answer', [], ''));
      PremiumService.instance.resetForTest();
      await tester.tap(find.byKey(const Key('assistant-voice-session')));
      await settle(tester);
      speech.results.single('Jaki gaz do spawania metodą tę ideę?', true);
      await settle(tester);
      expect(bodies, hasLength(1));
      voice.playback!.complete();
      await settle(tester);
      speech.results.last('TIG', true);
      await settle(tester);
      expect(bodies, hasLength(2));
      expect(bodies.last['message'], 'TIG');
      expect(bodies.last['speech_transcript'], true);
      expect(bodies.last['question_clarification'], {
        'user_turns': ['Jaki gaz do spawania metodą tę ideę?']
      });
      expect(tester.takeException(), isNull);
    }, () => MockClient((request) async {
      bodies.add(jsonDecode(request.body) as Map<String, dynamic>);
      return http.Response(jsonEncode({
        'text': bodies.length == 1 ? 'Jaką metodę spawania masz na myśli?' : 'Dla TIG stosuje się argon.',
        'citations': [], 'needs_clarification': bodies.length == 1,
        'calculator_context_used': true,
        if (bodies.length > 1) 'question_clarification_used': true,
      }), 200, headers:{'content-type':'application/json; charset=utf-8'});
    }));
  });
  testWidgets('retry preserves the spoken source after a temporary failure', (tester) async {
    final speech = HeldSpeech();
    final voice = VoiceFake();
    final bodies = <Map<String, dynamic>>[];
    await http.runWithClient(() async {
      await mount(tester, speech: speech, voice: voice,
          interpret: (_) async => const AiCommandPlan('answer', [], ''));
      PremiumService.instance.resetForTest();
      await tester.tap(find.byKey(const Key('assistant-voice-session')));
      await settle(tester);
      speech.results.single('Jaki gaz do spawania?', true);
      await settle(tester);
      expect(bodies, hasLength(1));
      final retry = tester.widget<SnackBarAction>(find.byType(SnackBarAction));
      retry.onPressed();
      await settle(tester);
      expect(bodies, hasLength(2));
      expect(bodies.map((body) => body['speech_transcript']), [true, true]);
      expect(bodies.last['message'], 'Jaki gaz do spawania?');
      expect(tester.takeException(), isNull);
    }, () => MockClient((request) async {
      bodies.add(jsonDecode(request.body) as Map<String, dynamic>);
      if (bodies.length == 1) {
        return http.Response(jsonEncode({'error':{'code':'AI_BUSY'}}), 503);
      }
      return http.Response(jsonEncode({'text':'Jaką metodę masz na myśli?',
        'citations':[], 'needs_clarification':true, 'calculator_context_used':true}),
        200, headers:{'content-type':'application/json; charset=utf-8'});
    }));
  });
}
