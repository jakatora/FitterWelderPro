import 'dart:async';
import 'dart:convert';

import 'package:cut_list_app/app_navigator.dart';
import 'package:cut_list_app/assistant/assistant_ai_client.dart';
import 'package:cut_list_app/assistant/core/skill.dart';
import 'package:cut_list_app/assistant/core/tool_bridge.dart';
import 'package:cut_list_app/i18n/app_language.dart';
import 'package:cut_list_app/screens/ai_chat_screen.dart';
import 'package:cut_list_app/services/account_service.dart';
import 'package:cut_list_app/services/ai_chat_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../support/test_database.dart';
import 'ai_chat_execution_test.dart' show mount, FixtureSpeech, FixtureSkill;
import 'global_pipe_slope_flow_test.dart' show say, settle;

Finder message(String text) =>
    find.byWidgetPredicate((w) => w is SelectableText && w.data == text);
final conversation = find.byKey(const Key('assistant-conversation'));
final page = find.byKey(const Key('assistant-conversation-page'));

Future<void> openConversation(WidgetTester tester) async {
  await tester.tap(conversation);
  await settle(tester);
  expect(page, findsOneWidget);
}

void main() {
  useTestDatabase();
  late AccountService previous, account;
  setUp(() async {
    previous = AccountService.instance;
    FlutterSecureStorage.setMockInitialValues({});
    account = AccountService.forTesting(MockClient((_) async => http.Response(
        jsonEncode({
          'token': 'fixture-token',
          'account': {
            'id': 'fixture',
            'displayName': 'Anna',
            'profession': 'Spawacz',
          }
        }),
        200)));
    AccountService.instance = account;
    await account.signIn('fixture@example.test', 'fixture-password');
  });
  tearDown(() => AccountService.instance = previous);

  testWidgets(
      'conversation stays disabled throughout a plan after native navigation',
      (tester) async {
    final pending = Completer<SkillResult>();
    var waiting = false;
    final first = FixtureSkill(
        'fixture.open',
        'fixture open',
        (_) async => const AnswerResult(
            AssistantAnswer(text: AssistantText.same('Otwieram')),
            show: ShowInModule('pipe_slope', {
              'mode': 'length_to_rise',
              'length_mm': 6000.0,
              'slope_pct': 1.0,
            })));
    final second = FixtureSkill('fixture.next', 'fixture next', (_) {
      waiting = true;
      return pending.future;
    });
    await mount(tester,
        speech: FixtureSpeech(),
        skills: [first, second],
        interpret: (_) async => const AiCommandPlan(
            'execute',
            [
              AiCommandStep('fixture.open', 'fixture open'),
              AiCommandStep('fixture.next', 'fixture next'),
            ],
            ''));
    await tester.enterText(
        find.byKey(const Key('assistant-command')), 'ogarnij te dwie sprawy');
    await tester.tap(find.byKey(const Key('assistant-go')));
    await settle(tester);
    expect(waiting, isTrue);
    expect(ToolBridge.instance.current?.toolId, 'pipe_slope');
    expect(tester.widget<IconButton>(conversation).onPressed, isNull);
    pending.complete(const AnswerResult(
        AssistantAnswer(text: AssistantText.same('Gotowe'))));
    await settle(tester);
    expect(tester.widget<IconButton>(conversation).onPressed, isNotNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'legacy clarification and rejected reply are visible without becoming AI facts',
      (tester) async {
    await mount(tester,
        speech: FixtureSpeech(),
        interpret: (_) async =>
            throw StateError('Literal workflow must stay local'));
    await say(tester, 'Zapisz TIG bez drutu, nierdzewka, ścianka 2 mm');
    expect(find.text('Jaki prąd w amperach?'), findsOneWidget);
    await openConversation(tester);
    expect(message('Jaki prąd w amperach?'), findsOneWidget);
    appNavigatorKey.currentState!.pop();
    await settle(tester);
    await say(tester, '99999 A');
    await openConversation(tester);
    expect(message('99999 A'), findsOneWidget);
    expect(
        find.byWidgetPredicate((w) =>
            w is SelectableText &&
            (w.data?.contains('Wartość poza zakresem') ?? false)),
        findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final language in AppLanguage.values) {
    testWidgets(
        'conversation fits narrow phone with enlarged text in ${language.name}',
        (tester) async {
      await mount(tester,
          speech: FixtureSpeech(),
          interpret: (_) async => throw StateError('No paid AI expected'));
      tester.view.physicalSize = const Size(800, 1600);
      tester.platformDispatcher.textScaleFactorTestValue = 1.3;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      AppLanguageScope.of(tester.element(find.byType(AiChatScreen)))
          .setLanguage(language);
      await settle(tester);
      final size = tester.getSize(conversation);
      expect(size.width, greaterThanOrEqualTo(48));
      expect(size.height, greaterThanOrEqualTo(48));
      await tester.enterText(
          find.byKey(const Key('assistant-command')), 'szkic');
      await openConversation(tester);
      expect(tester.takeException(), isNull);
      appNavigatorKey.currentState!.pop();
      await settle(tester);
      expect(
          tester
              .widget<TextField>(find.byKey(const Key('assistant-command')))
              .controller!
              .text,
          'szkic');
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
      'session change closes both conversation and its clear confirmation',
      (tester) async {
    await mount(tester,
        speech: FixtureSpeech(),
        interpret: (_) async =>
            const AiCommandPlan('clarify', [], 'Prywatna odpowiedź'));
    await say(tester, 'moje prywatne pytanie');
    await openConversation(tester);
    await tester.tap(find.byKey(const Key('assistant-conversation-clear')));
    await settle(tester);
    expect(find.byType(AlertDialog), findsOneWidget);
    await tester.runAsync(account.forgetSession);
    await settle(tester);
    expect(page, findsNothing);
    expect(find.byType(AlertDialog), findsNothing);
    await openConversation(tester);
    expect(message('Prywatna odpowiedź'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'native result and AI answer remain readable without losing module or draft',
      (tester) async {
    var interpretations = 0, answers = 0;
    await mount(tester, speech: FixtureSpeech(), interpret: (_) async {
      interpretations++;
      return const AiCommandPlan('answer', [], '');
    }, chatSender: (_, __) async {
      answers++;
      return ChatMessage(
          role: ChatRole.assistant,
          text: 'Wyjaśnienie poprzedniego wyniku.',
          kind: AiReplyKind.live,
          citations: ['Norma fixture']);
    });
    await say(tester, 'spadek 1% na 6 metrów');
    final native = ToolBridge.instance.current;
    final fields = Map.of(ToolBridge.instance.inputFields('pipe_slope')!);
    await say(tester, 'a dlaczego tyle wyszlo');
    final chat = tester.state(find.byType(AiChatScreen));
    await tester.enterText(
        find.byKey(const Key('assistant-command')), 'mój szkic');
    await openConversation(tester);
    expect(appRoutes.assistantAvailable, isFalse);
    expect(message('Wyjaśnienie poprzedniego wyniku.'), findsOneWidget);
    expect(find.text('Asystent · AI'), findsOneWidget);
    expect(message('a dlaczego tyle wyszlo'), findsOneWidget);
    // Citation labels are readable but cannot open a private unowned popup.
    await tester.tap(find.text('Norma fixture'));
    await settle(tester);
    expect(page, findsOneWidget);
    expect(find.byType(AlertDialog), findsNothing);
    expect(interpretations, 1);
    expect(answers, 1);
    await tester.drag(find.byKey(const Key('assistant-conversation-messages')),
        const Offset(0, 200));
    await settle(tester);
    expect(message('spadek 1% na 6 metrów'), findsOneWidget);
    appNavigatorKey.currentState!.pop();
    await settle(tester);
    expect(ToolBridge.instance.current, same(native));
    expect(ToolBridge.instance.inputFields('pipe_slope'), fields);
    expect(tester.state(find.byType(AiChatScreen)), same(chat));
    expect(
        tester
            .widget<TextField>(find.byKey(const Key('assistant-command')))
            .controller!
            .text,
        'mój szkic');
  });

  testWidgets(
      'reading conversation preserves a paused ordered plan and native reply',
      (tester) async {
    var finished = 0;
    final ask = FixtureSkill(
        'fixture.ask',
        'fixture question',
        (match) async => match.slots['value'] == null
            ? AskResult('value', const AssistantText.same('Podaj wartość'),
                partial: match)
            : const AnswerResult(
                AssistantAnswer(text: AssistantText.same('Przyjęto'))));
    final next = FixtureSkill('fixture.next', 'fixture next', (_) async {
      finished++;
      return const AnswerResult(
          AssistantAnswer(text: AssistantText.same('Drugi krok')));
    });
    await mount(
      tester,
      speech: FixtureSpeech(),
      skills: [ask, next],
      interpret: (_) async => const AiCommandPlan(
          'execute',
          [
            AiCommandStep('fixture.ask', 'fixture question'),
            AiCommandStep('fixture.next', 'fixture next'),
          ],
          ''),
    );
    await say(tester, 'ogarnij te dwie sprawy');
    await openConversation(tester);
    expect(message('Podaj wartość'), findsOneWidget);
    appNavigatorKey.currentState!.pop();
    await settle(tester);
    await say(tester, '120');
    expect(finished, 1);
    expect(find.text('Drugi krok'), findsOneWidget);
  });

  testWidgets(
      'logout closes the private snapshot and removes prior-session messages',
      (tester) async {
    await mount(tester,
        speech: FixtureSpeech(),
        interpret: (_) async =>
            const AiCommandPlan('clarify', [], 'Prywatne pytanie sesji A'));
    await say(tester, 'pomóż z moją prywatną sprawą');
    await openConversation(tester);
    expect(message('Prywatne pytanie sesji A'), findsOneWidget);
    await tester.runAsync(account.forgetSession);
    await settle(tester);
    expect(page, findsNothing);
    await openConversation(tester);
    expect(message('Prywatne pytanie sesji A'), findsNothing);
    expect(message('pomóż z moją prywatną sprawą'), findsNothing);
  });

  testWidgets(
      'clearing conversation confirms on root navigator and clears private history',
      (tester) async {
    await mount(tester,
        speech: FixtureSpeech(),
        interpret: (_) async =>
            const AiCommandPlan('clarify', [], 'Poprzednie pytanie'));
    await say(tester, 'pomóż przy pierwszej próbie');
    await openConversation(tester);
    final clear = find.byKey(const Key('assistant-conversation-clear'));
    await tester.tap(clear);
    await settle(tester);
    expect(find.byType(AlertDialog), findsOneWidget);
    await tester.tap(find.text('Anuluj'));
    await settle(tester);
    expect(page, findsOneWidget);
    expect(message('Poprzednie pytanie'), findsOneWidget);
    await tester.tap(clear);
    await settle(tester);
    await tester.tap(find.widgetWithText(TextButton, 'Wyczyść'));
    await settle(tester);
    expect(page, findsNothing);
    await openConversation(tester);
    expect(message('Poprzednie pytanie'), findsNothing);
    expect(message('pomóż przy pierwszej próbie'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('conversation cannot cover an in-flight AI command',
      (tester) async {
    final pending = Completer<AiCommandPlan>();
    await mount(tester,
        speech: FixtureSpeech(), interpret: (_) => pending.future);
    await tester.enterText(
        find.byKey(const Key('assistant-command')), 'ogarnij moje rurki');
    await tester.tap(find.byKey(const Key('assistant-go')));
    await tester.pump(const Duration(milliseconds: 100));
    expect(tester.widget<IconButton>(conversation).onPressed, isNull);
    pending.complete(const AiCommandPlan('clarify', [], 'Która rura?'));
    await settle(tester);
    expect(tester.widget<IconButton>(conversation).onPressed, isNotNull);
    expect(tester.takeException(), isNull);
  });
}
