import 'dart:async';
import 'package:cut_list_app/screens/ai_chat_screen.dart';
import 'package:cut_list_app/screens/consent_screen.dart';
import 'package:cut_list_app/i18n/app_language.dart';
import 'package:cut_list_app/services/legal_consent.dart';
import '../test_prefs.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cut_list_app/services/ai_chat_service.dart';
import '../support/test_account.dart';
import '../support/test_database.dart';
import 'ai_chat_execution_test.dart' show mount;
import 'global_pipe_slope_flow_test.dart' show settle;

void main() {
  useGuestAccount();
  useTestDatabase();
  testWidgets('rapid sends start only one answer request', (t) async {
    seedFreshInstall();
    await LegalConsent.instance.accept();
    t.view.physicalSize = const Size(1080, 2400);
    t.view.devicePixelRatio = 2.5;
    addTearDown(t.view.reset);
    final pending = Completer<ChatMessage>();
    var calls = 0;
    await t.pumpWidget(AppLanguageScope(
      controller: AppLanguageController(AppLanguage.pl),
      child: MaterialApp(
          home: AiChatScreen(
              initialMode: AssistantMode.answer,
              chatSender: (_, __) {
                calls++;
                return pending.future;
              })),
    ));
    await settle(t);
    final input = find.byKey(const Key('assistant-question-input'));
    await t.enterText(input, 'Co oznacza DN50?');
    await t.pump();
    final send = t
        .widget<IconButton>(find.byKey(const Key('assistant-send')))
        .onPressed!;
    send();
    send();
    for (var i = 0; i < 10; i++) {
      await t.pump(const Duration(milliseconds: 100));
    }
    expect(calls, 1);
    pending.complete(ChatMessage(
        role: ChatRole.assistant,
        text: 'Rozmiar nominalny.',
        kind: AiReplyKind.live));
    await settle(t);
    await t.enterText(input, 'A co oznacza NPS?');
    await t.pump();
    await t.tap(find.byKey(const Key('assistant-send')));
    await settle(t);
    expect(calls, 2,
        reason: 'A new question is allowed after the first answer');
    expect(t.takeException(), isNull);
  });
  testWidgets('rapid sends open consent once and cancellation unlocks sending',
      (t) async {
    seedFreshInstall();
    LegalConsent.instance.resetForTest();
    t.view.physicalSize = const Size(1080, 2400);
    t.view.devicePixelRatio = 2.5;
    addTearDown(t.view.reset);
    var calls = 0;
    await t.pumpWidget(AppLanguageScope(
      controller: AppLanguageController(AppLanguage.pl),
      child: MaterialApp(
          home: AiChatScreen(
              initialMode: AssistantMode.answer,
              chatSender: (_, __) async {
                calls++;
                return ChatMessage(role: ChatRole.assistant, text: 'answer');
              })),
    ));
    await settle(t);
    final input = find.byKey(const Key('assistant-question-input'));
    await t.enterText(input, 'Co oznacza DN50?');
    await t.pump();
    final send = t
        .widget<IconButton>(find.byKey(const Key('assistant-send')))
        .onPressed!;
    send();
    send();
    await settle(t);
    expect(find.byType(ConsentScreen), findsOneWidget);
    await t.binding.handlePopRoute();
    await settle(t);
    expect(find.byType(ConsentScreen), findsNothing);
    expect(calls, 0);
    await t.enterText(input, 'Co oznacza NPS?');
    await t.pump();
    await t.tap(find.byKey(const Key('assistant-send')));
    await settle(t);
    expect(find.byType(ConsentScreen), findsOneWidget);
    expect(calls, 0);
    await t.binding.handlePopRoute();
    await settle(t);
    expect(t.takeException(), isNull);
  });
  for (final embedded in [true, false]) {
    for (final failure in ['unavailable', 'offline', 'exception']) {
      testWidgets(
          'explicit knowledge retry preserves a new draft: $failure embedded=$embedded',
          (t) async {
        final questions = <String>[];
        final pending = Completer<ChatMessage>();
        Future<ChatMessage> sender(
            String text, List<ChatMessage> history) async {
          questions.add(text);
          if (questions.length > 1) return pending.future;
          if (failure == 'exception') throw StateError('Connection lost');
          return ChatMessage(
              role: ChatRole.assistant,
              text: 'Temporary failure',
              kind: failure == 'offline'
                  ? AiReplyKind.offlineHelp
                  : AiReplyKind.unavailable);
        }

        if (embedded) {
          await mount(t,
              interpret: (_) async => throw StateError('No command expected'),
              chatSender: sender);
        } else {
          seedFreshInstall();
          await LegalConsent.instance.accept();
          t.view.physicalSize = const Size(1080, 2400);
          t.view.devicePixelRatio = 2.5;
          addTearDown(t.view.reset);
          addTearDown(() async {
            await t.pumpWidget(const SizedBox.shrink());
            await settle(t);
          });
          await t.pumpWidget(AppLanguageScope(
              controller: AppLanguageController(AppLanguage.pl),
              child: MaterialApp(
                  home: AiChatScreen(
                      initialMode: AssistantMode.answer, chatSender: sender))));
          await settle(t);
        }
        final input = find.byKey(
            Key(embedded ? 'assistant-command' : 'assistant-question-input'));
        await t.enterText(input, 'Explain TIG welding');
        await t
            .tap(find.byKey(Key(embedded ? 'assistant-go' : 'assistant-send')));
        await settle(t);
        expect(questions, ['Explain TIG welding']);
        final retry =
            t.widget<SnackBarAction>(find.byType(SnackBarAction)).onPressed;
        await t.enterText(input, 'My next question is still a draft');
        retry();
        retry();
        for (var i = 0; i < 5; i++) {
          await t.pump(const Duration(milliseconds: 100));
        }
        expect(questions, ['Explain TIG welding', 'Explain TIG welding']);
        expect(t.widget<TextField>(input).controller!.text,
            'My next question is still a draft');
        expect(t.widget<TextField>(input).enabled, isNot(false));
        await t.enterText(input, 'Draft edited while waiting for the answer');
        if (!embedded) {
          expect(
              t
                  .widget<IconButton>(find.byKey(const Key('assistant-send')))
                  .onPressed,
              isNull);
          await t.testTextInput.receiveAction(TextInputAction.send);
          await t.pump();
          expect(questions, hasLength(2),
              reason: 'Keyboard submit is blocked while waiting');
        }
        pending.complete(ChatMessage(
            role: ChatRole.assistant,
            text: 'Recovered answer',
            kind: AiReplyKind.live));
        await settle(t);
        expect(t.widget<TextField>(input).controller!.text,
            'Draft edited while waiting for the answer');
        expect(find.textContaining('Recovered answer'), findsWidgets);
        expect(questions, hasLength(2),
            reason: 'Draft must not be sent without its own submit');
        expect(t.takeException(), isNull);
      });
    }
  }
}
