import 'dart:io';
import 'package:cut_list_app/feedback/feedback_signal.dart';
import 'package:cut_list_app/screens/ai_chat_screen.dart';
import 'package:cut_list_app/database/db.dart';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cut_list_app/security/credential_text.dart';
import 'package:cut_list_app/assistant/assistant_ai_client.dart';
import 'package:cut_list_app/assistant/assistant_intent_client.dart';
import 'package:cut_list_app/assistant/core/skill.dart';
import 'package:cut_list_app/assistant/skills/core/open_tool_skill.dart';
import 'package:cut_list_app/assistant/core/tool_bridge.dart';
import 'package:cut_list_app/services/ai_chat_service.dart';
import 'package:cut_list_app/services/premium_service.dart';
import 'package:cut_list_app/feedback/redact.dart';
import 'package:cut_list_app/feedback/feedback_store.dart';
import 'package:cut_list_app/i18n/app_language.dart';
import 'package:cut_list_app/screens/iso_notebook_screen.dart';
import '../support/test_account.dart';
import '../support/test_database.dart';
import 'ai_chat_execution_test.dart' show mount, FixtureSpeech;
import 'global_pipe_slope_flow_test.dart' show say, settle;
import 'ai_pending_task_switch_test.dart' show newDrawing, pendingPlan;

const sensitive = 'Zaloguj mnie, hasło: FixtureSecret123!';
const secret = 'FixtureSecret123!';
void main() {
  useTestDatabase();
  useGuestAccount();
  test(
      'labelled credentials and recognizable keys are blocked but welding/glossary text stays usable',
      () {
    for (final text in [
      sensitive,
      'Moje hasło to spawacz',
      'my password is private',
      'password=plainvalue',
      'password MySecret123',
      'PIN: 123456',
      'OTP 876543',
      'kod weryfikacyjny: 123456',
      'api_key="fakekeyvalue"',
      'Authorization: Bearer abcdef',
      'Bearer abcdefghijklmnopqrst',
      'sk-ant-abcdefghijklmnop123456',
      'sk_test_abcdefghijklmnop123456',
      '{"token":"abcdefghijklmnopqrst123456"}'
    ]) {
      expect(containsCredentialValue(text), true, reason: text);
      expect(redactCredentialText(text), '***');
      expect(prepareFeedbackText(text), '***');
    }
    for (final text in [
      'Jak zmienić hasło do konta?',
      'What is a password?',
      'Wyjaśnij hasło: spawanie orbitalne',
      'Wyjasnij haslo WPS',
      'Rura DN50 ścianka 3.91 mm długość 1000 mm',
      'API 5L X52',
      'PIN: 3',
      'Kod projektu CW-123',
      'TIG 141, 60 A, 2 mm',
      'Wyjaśnij ciśnienie hydrotestu'
    ]) {
      expect(containsCredentialValue(text), false, reason: text);
    }
  });
  test(
      'request factory refuses current credentials and masks an older credential history entry',
      () {
    final context = AssistantContext(
        lang: AppLanguage.pl, modules: const FixedModuleContext());
    expect(
        () => assistantAiRequest(
            text: sensitive, context: context, skills: [OpenToolSkill()]),
        throwsFormatException);
    final request = assistantAiRequest(
        text: 'Otworz heat input',
        context: context,
        skills: [
          OpenToolSkill()
        ],
        history: [
          {'role': 'user', 'text': sensitive},
          {'role': 'assistant', 'text': 'Previous reply'}
        ]);
    expect(jsonEncode(request), isNot(contains(secret)));
    expect(
        ((request['context'] as Map)['history'] as List).first['text'], '***');
  });
  test('assistant transport rejects credentials before identity and HTTP',
      () async {
    var identities = 0, requests = 0;
    final httpClient = MockClient((_) async {
      requests++;
      return http.Response('{}', 500);
    });
    final client = AssistantAiClient(
        client: httpClient,
        identity: () async {
          identities++;
          return {};
        });
    addTearDown(client.close);
    await expectLater(
        client
            .interpret({'text': sensitive, 'capabilities': [], 'context': {}}),
        throwsA(isA<AssistantAiUnavailable>()
            .having((e) => e.code, 'code', 'AI_SENSITIVE_INPUT')));
    expect(identities, 0);
    expect(requests, 0);
  });
  test('transport masks old history and leaves authentication headers intact',
      () async {
    var calls = 0;
    final client = AssistantAiClient(
        identity: () async => {'X-Install-Secret': 'fixture-auth-header'},
        client: MockClient((request) async {
          calls++;
          expect(request.headers['X-Install-Secret'], 'fixture-auth-header');
          final body = jsonDecode(request.body) as Map;
          expect(jsonEncode(body), isNot(contains(secret)));
          expect(((body['context'] as Map)['history'] as List).first['text'],
              '***');
          return http.Response(
              jsonEncode({
                'kind': 'clarify',
                'steps': [],
                'message': 'Jakie narzędzie?'
              }),
              200,
              headers: {'content-type': 'application/json; charset=utf-8'});
        }));
    addTearDown(client.close);
    final plan = await client.interpret({
      'text': 'Pomóż mi z narzędziami',
      'capabilities': [],
      'context': {
        'history': [
          {'role': 'user', 'text': sensitive}
        ]
      }
    });
    expect(plan.kind, 'clarify');
    expect(calls, 1);
  });
  test(
      'decoding an older feedback queue masks credentials before payload upload',
      () {
    final fixture = jsonDecode(
            File('test/fixtures/feedback_signal_v1.json').readAsStringSync())
        as Map;
    final item =
        Map<String, Object?>.from((fixture['items'] as List).single as Map)
          ..['text'] = sensitive;
    final decoded = FeedbackSignal.fromJson(item);
    expect(decoded.text, '***');
    expect(jsonEncode(feedbackPayload([decoded])), isNot(contains(secret)));
  });
  test('direct legacy intent and knowledge clients do not send credential text',
      () async {
    var requests = 0;
    SharedPreferences.setMockInitialValues({});
    PremiumService.instance.resetForTest();
    await http.runWithClient(() async {
      final intent = await const AssistantIntentClient()
          .classify(sensitive, AppLanguage.pl);
      expect((intent as RemoteIntentUnavailable).kind,
          RemoteUnavailableKind.notAllowed);
      final reply = await AiChatService.instance.sendMessage(sensitive);
      expect(reply.kind, AiReplyKind.localDialogue);
      expect(reply.text, credentialInputNoticePl);
    },
        () => MockClient((_) async {
              requests++;
              return http.Response('{}', 500);
            }));
    expect(requests, 0);
  });
  test('knowledge history drops a sensitive pair rather than sending it later',
      () {
    final history = chatHistoryForRequest([
      ChatMessage(role: ChatRole.user, text: sensitive),
      ChatMessage(
          role: ChatRole.assistant, text: 'previous', kind: AiReplyKind.live),
      ChatMessage(role: ChatRole.user, text: 'Co to WPS?'),
      ChatMessage(
          role: ChatRole.assistant, text: 'Instrukcja', kind: AiReplyKind.live),
    ]);
    expect(history, hasLength(2));
    expect(history.first.text, 'Co to WPS?');
  });
  for (final voice in [false, true]) {
    testWidgets(
        'command credential input stays out of interpreter, history and reports voice=$voice',
        (t) async {
      var calls = 0, chats = 0;
      final speech = FixtureSpeech();
      await mount(t, speech: speech, interpret: (request) async {
        calls++;
        expectSync(jsonEncode(request), isNot(contains(secret)));
        return const AiCommandPlan('clarify', [], 'Jakie narzędzie?');
      }, chatSender: (text, history) async {
        chats++;
        throw StateError('No chat request');
      });
      final before = Map<String, Object?>.of(
          ToolBridge.instance.inputFields('rolling_offset')!);
      if (voice) {
        await t.tap(find.byKey(const Key('assistant-mic')));
        await settle(t);
        speech.emit(sensitive);
        await settle(t);
      } else {
        await say(t, sensitive);
      }
      expect(calls, 0);
      expect(chats, 0);
      expect(find.textContaining(secret), findsNothing);
      expect(find.textContaining('Ta wiadomość nie została wysłana'),
          findsWidgets);
      expect(ToolBridge.instance.inputFields('rolling_offset'), before);
      final reports = (await t.runAsync(() => FeedbackStore.instance.list()))!;
      expect(reports.any((r) => r.text.contains(secret)), false);
      await say(t, 'Pomoz mi prosze z narzedziami');
      expect(calls, 1);
      expect(chats, 0);
    });
  }
  testWidgets(
      'knowledge composer blocks credentials before injected sender and consent flow',
      (t) async {
    var calls = 0, chats = 0;
    await t.pumpWidget(AppLanguageScope(
        controller: AppLanguageController(AppLanguage.pl),
        child: MaterialApp(
            home: AiChatScreen(aiInterpreter: (_) async {
          calls++;
          return const AiCommandPlan('answer', [], '');
        }, chatSender: (text, history) async {
          chats++;
          throw StateError('No chat request');
        }))));
    await settle(t);
    await t.tap(find.byKey(const Key('assistant-mode-answer')));
    await settle(t);
    await t.enterText(
        find.byKey(const Key('assistant-question-input')), sensitive);
    await t.tap(find.byKey(const Key('assistant-send')));
    await settle(t);
    expect(calls, 0);
    expect(chats, 0);
    expect(find.textContaining(secret), findsNothing);
    expect(
        find.textContaining('Ta wiadomość nie została wysłana'), findsWidgets);
  });
  testWidgets(
      'blocked credentials preserve pending native question and queued drawing',
      (t) async {
    await t.runAsync(() async {
      await (await AppDatabase.get()).delete('iso_drawings');
    });
    var calls = 0;
    await mount(t, interpret: (_) async {
      calls++;
      return pendingPlan;
    });
    await say(t, 'Narysuj rura metr w prawo kolano DN50 w gore rura metr');
    final c = IsoNotebookController.active!;
    for (var i = 0; i < 12 && c.isBusy; i++) {
      await settle(t);
    }
    await say(t, newDrawing);
    final revision = c.revision;
    await say(t, sensitive);
    expect(calls, 1);
    expect(c.revision, revision);
    expect(find.textContaining('Na arkuszu jest już rysunek'), findsWidgets);
    await say(t, 'Dorysuj');
    for (var i = 0; i < 12 && c.isBusy; i++) {
      await settle(t);
    }
    await settle(t);
    expect(c.summary!.pipeCount, 4);
    expect(calls, 1);
  });
}
