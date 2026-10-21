import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:cut_list_app/assistant/assistant_ai_client.dart';
import 'package:cut_list_app/services/account_service.dart';
import 'package:cut_list_app/services/user_profile.dart';
import 'package:cut_list_app/services/ai_chat_service.dart';
import 'package:cut_list_app/services/legal_consent.dart';
import 'package:cut_list_app/screens/ai_chat_screen.dart';
import 'package:cut_list_app/i18n/app_language.dart';
import 'package:cut_list_app/database/weld_param_dao.dart';
import '../support/test_database.dart';
import '../test_prefs.dart';
import 'ai_chat_execution_test.dart' show mount, FixtureSpeech;
import 'global_pipe_slope_flow_test.dart' show say, settle;

void main() {
  useTestDatabase();
  late AccountService account;
  setUp(() async {
    FlutterSecureStorage.setMockInitialValues({});
    final previous = AccountService.instance;
    final client = MockClient((r) async {
      final body =
          r.body.isEmpty ? <String, dynamic>{} : jsonDecode(r.body) as Map;
      final email = body['email'] ?? 'a@example.test';
      return http.Response(
          jsonEncode({
            'account': {'id': email, 'email': email, 'displayName': 'Test'},
            'token': 'test-token-$email',
          }),
          200);
    });
    account = AccountService.forTesting(client);
    AccountService.instance = account;
    addTearDown(() {
      AccountService.instance = previous;
      client.close();
    });
    await account.signIn('a@example.test', 'test-password');
  });

  testWidgets(
      'same-account new login clears AI history but profile editing preserves it',
      (t) async {
    final calls = <Map<String, Object?>>[];
    await mount(t, interpret: (r) async {
      calls.add(r);
      return const AiCommandPlan('clarify', [], 'Doprecyzuj próbę.');
    });
    await say(t, 'Pomóż z moją pierwszą próbą');
    await t.runAsync(() => account.saveProfile({'displayName': 'Nowe imię'}));
    await say(t, 'Mam jeszcze drugą próbę');
    expect(((calls.last['context'] as Map)['history'] as List), isNotEmpty);
    await t.runAsync(() => account.signIn('a@example.test', 'test-password'));
    await settle(t);
    await say(t, 'Zacznijmy trzecią próbę');
    expect(((calls.last['context'] as Map)['history'] as List), isEmpty);
  });

  testWidgets(
      'late AI action from old account cannot create a confirmation in new session',
      (t) async {
    final pending = Completer<AiCommandPlan>();
    await mount(t, interpret: (_) => pending.future);
    await t.enterText(find.byKey(const Key('assistant-command')),
        'Ogarnij moją próbę proszę');
    await t.tap(find.byKey(const Key('assistant-go')));
    await t.pump(const Duration(milliseconds: 200));
    await t.runAsync(() async {
      await account.forgetSession();
      await account.signIn('b@example.test', 'test-password');
    });
    await settle(t);
    pending.complete(const AiCommandPlan(
        'execute',
        [
          AiCommandStep(
              'legacy.save', 'Zapisz TIG nierdzewka 2 mm 60 A bez drutu'),
        ],
        ''));
    await settle(t);
    expect(find.byKey(const Key('assistant-local-save')), findsNothing);
    expect(find.byKey(const Key('assistant-ai-cancel')), findsNothing);
  });

  testWidgets('local profile erasure clears transient AI conversation',
      (t) async {
    final calls = <Map<String, Object?>>[];
    await mount(t, interpret: (r) async {
      calls.add(r);
      return const AiCommandPlan('clarify', [], 'Doprecyzuj próbę.');
    });
    await say(t, 'Pomóż z prywatną próbą');
    await t.runAsync(() => UserProfileService.instance.clear());
    await settle(t);
    await say(t, 'Zacznijmy nową próbę');
    expect(((calls.last['context'] as Map)['history'] as List), isEmpty);
  });
  testWidgets('late answer from old session cannot return to new conversation',
      (t) async {
    final reply = Completer<ChatMessage>();
    var sent = false;
    await mount(t,
        interpret: (_) async => const AiCommandPlan('answer', [], ''),
        chatSender: (_, __) {
          sent = true;
          return reply.future;
        });
    await t.enterText(find.byKey(const Key('assistant-command')),
        'Wytłumacz mi tę prywatną próbę');
    await t.tap(find.byKey(const Key('assistant-go')));
    await t.pump(const Duration(milliseconds: 200));
    expect(sent, isTrue);
    await t.runAsync(account.forgetSession);
    await settle(t);
    reply.complete(ChatMessage(
        role: ChatRole.assistant,
        text: 'Prywatna odpowiedź starego konta',
        kind: AiReplyKind.live));
    await settle(t);
    expect(
        find.textContaining('Prywatna odpowiedź starego konta'), findsNothing);
  });
  testWidgets(
      'late microphone transcript cannot submit a command after session change',
      (t) async {
    final speech = FixtureSpeech();
    var calls = 0;
    await mount(t, speech: speech, interpret: (_) async {
      calls++;
      return const AiCommandPlan('clarify', [], 'Doprecyzuj.');
    });
    await t.tap(find.byKey(const Key('assistant-mic')));
    await settle(t);
    await t.runAsync(account.forgetSession);
    await settle(t);
    speech.emit('Ogarnij prywatną próbę starego konta');
    await settle(t);
    expect(calls, 0);
    expect(
        (t.widget<TextField>(find.byKey(const Key('assistant-command'))))
            .controller!
            .text,
        isEmpty);
  });
  testWidgets(
      'clear chat also clears model clarification and hidden AI history',
      (t) async {
    seedFreshInstall();
    await LegalConsent.instance.accept();
    final calls = <Map<String, Object?>>[];
    await t.pumpWidget(AppLanguageScope(
        controller: AppLanguageController(AppLanguage.pl),
        child: MaterialApp(home: AiChatScreen(aiInterpreter: (r) async {
          calls.add(r);
          return const AiCommandPlan('clarify', [], 'Doprecyzuj próbę.');
        }))));
    await settle(t);
    await say(t, 'Pomóż w mojej prywatnej próbie');
    await t.tap(find.byKey(const Key('assistant-mode-answer')));
    await settle(t);
    await t.tap(find.byTooltip('Wyczyść rozmowę'));
    await settle(t);
    await t.tap(find.text('Wyczyść'));
    await settle(t);
    await t.tap(find.byKey(const Key('assistant-mode-act')));
    await settle(t);
    await say(t, 'Zacznijmy zupełnie inną próbę');
    final context = calls.last['context'] as Map;
    expect(context['history'], isEmpty);
    expect(context['pending_question'], isNull);
  });
  testWidgets(
      'session change dismisses the old native record summary without saving',
      (t) async {
    await mount(t,
        interpret: (_) async =>
            throw StateError('Local command must stay offline'));
    await say(t, 'Zapisz TIG nierdzewka 2 mm 60 A bez drutu');
    expect(find.text('Sprawdź i zapisz'), findsOneWidget);
    await t.runAsync(account.forgetSession);
    await settle(t);
    expect(find.text('Sprawdź i zapisz'), findsNothing);
    expect(find.byKey(const Key('assistant-local-save')), findsNothing);
    expect(await t.runAsync(() => WeldParamDao().listAll()), isEmpty);
  });
}
