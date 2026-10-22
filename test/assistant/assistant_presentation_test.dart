import 'package:cut_list_app/app_navigator.dart';
import 'package:cut_list_app/assistant/core/assistant_panel_controller.dart';
import 'package:cut_list_app/screens/ai_chat_screen.dart';
import 'package:cut_list_app/screens/premium_screen.dart';
import 'package:cut_list_app/assistant/core/tool_bridge.dart';
import 'package:cut_list_app/assistant/core/skill.dart';
import 'package:cut_list_app/assistant/assistant_ai_client.dart';
import 'package:cut_list_app/services/api_client.dart';
import 'package:cut_list_app/services/premium_service.dart';
import 'package:cut_list_app/widgets/tool_registry.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../support/test_database.dart';
import 'ai_chat_execution_test.dart' show mount, FixtureSpeech, FixtureSkill;
import 'global_pipe_slope_flow_test.dart' show settle, say;

void main() {
  useTestDatabase();

  testWidgets('ordered AI plan continues in the native module from full chat',
      (tester) async {
    var finished = 0, interpretations = 0;
    final open = FixtureSkill(
        'fixture.open',
        'fixture open',
        (_) async => const AnswerResult(
            AssistantAnswer(text: AssistantText.same('Otwieram')),
            show: ShowInModule('pipe_slope', {
              'mode': 'length_to_rise',
              'length_mm': 6000.0,
              'slope_pct': 1.0
            })));
    final next = FixtureSkill('fixture.next', 'fixture next', (_) async {
      expect(ToolBridge.instance.current?.toolId, 'pipe_slope');
      expect(ToolBridge.instance.inputFields('pipe_slope')!['length_mm'], 6000);
      finished++;
      return const AnswerResult(
          AssistantAnswer(text: AssistantText.same('Plan zakończony')));
    });
    await mount(tester,
        home: const Scaffold(body: Text('Home')),
        speech: FixtureSpeech(),
        skills: [open, next], interpret: (_) async {
      interpretations++;
      return const AiCommandPlan(
          'execute',
          [
            AiCommandStep('fixture.open', 'fixture open'),
            AiCommandStep('fixture.next', 'fixture next'),
          ],
          '');
    });
    final assistant = tester.state(find.byType(AiChatScreen));
    appNavigatorKey.currentState!.push(MaterialPageRoute<void>(
        builder: (_) => const Scaffold(body: Text('Underlying page'))));
    await settle(tester);
    await openTool(
        appNavigatorKey.currentState!.overlay!.context, toolById('assistant')!);
    await settle(tester);
    await say(tester, 'ogarnij mi te dwie sprawy');
    expect(interpretations, 1);
    expect(finished, 1);
    expect(find.text('Plan zakończony'), findsOneWidget);
    expect(
        identical(tester.state(find.byType(AiChatScreen)), assistant), isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'Premium CTA preserves its state and conversation during module navigation',
      (tester) async {
    final requests = <http.Request>[];
    ApiClient.instance.debugSetClient(MockClient((request) async {
      requests.add(request);
      return http.Response('{"plan":"free"}', 200);
    }));
    addTearDown(() => ApiClient.instance.debugSetClient(null));
    PremiumService.instance.resetForTest();
    await mount(tester,
        home: const Scaffold(body: Text('Home')),
        speech: FixtureSpeech(),
        interpret: (_) async => throw StateError('No paid AI expected'));
    final assistant = tester.state(find.byType(AiChatScreen));
    appNavigatorKey.currentState!
        .push(MaterialPageRoute<void>(builder: (_) => const PremiumScreen()));
    await settle(tester);
    final premium = tester.state(find.byType(PremiumScreen));
    final before = requests.length;
    await tester.tap(find.text('Wypróbuj AI Asystenta'));
    await settle(tester);
    expect(appRoutes.assistantPresentation, isTrue);
    expect(
        identical(tester.state(find.byType(AiChatScreen)), assistant), isTrue);
    expect(requests.length, before);
    expect(requests.any((r) => r.url.path.contains('checkout')), isFalse);

    await say(tester, 'spadek 1% na 6 metrów');
    expect(ToolBridge.instance.current?.toolId, 'pipe_slope');
    expect(appRoutes.assistantPresentation, isFalse);
    expect(
        identical(tester.state(find.byType(AiChatScreen)), assistant), isTrue);
    expect(tester.getSize(find.byType(AiChatScreen)).height, lessThan(500));
    // First back collapses the compact panel; the next returns to full chat.
    await appNavigatorKey.currentState!.maybePop();
    await settle(tester);
    await appNavigatorKey.currentState!.maybePop();
    await settle(tester);
    expect(appRoutes.assistantPresentation, isTrue);
    // Returning from a module must not leave an empty full-page scaffold.
    expect(AssistantPanelController.instance.expanded, isTrue);
    await tester.tap(find.byTooltip('Zwiń'));
    await settle(tester);
    expect(
        identical(tester.state(find.byType(PremiumScreen)), premium), isTrue);
    expect(tester.takeException(), isNull);
  });

  for (final closeWithBack in [false, true]) {
    testWidgets(
        'one conversation survives presentation and '
        '${closeWithBack ? 'back' : 'collapse'}', (tester) async {
      await mount(tester,
          home: const Scaffold(body: Text('Home')),
          speech: FixtureSpeech(),
          interpret: (_) async => throw StateError('No paid AI expected'));
      final assistant = tester.state(find.byType(AiChatScreen));
      final input = find.byKey(const ValueKey('assistant-command'));
      await tester.enterText(input, 'mój niedokończony opis');

      final underlying = MaterialPageRoute<void>(
          builder: (_) => const Scaffold(body: Text('Underlying page')));
      appNavigatorKey.currentState!.push(underlying);
      await settle(tester);
      expect(appRoutes.assistantAvailable, isFalse);
      await openTool(appNavigatorKey.currentState!.overlay!.context,
          toolById('assistant')!);
      await settle(tester);
      expect(appRoutes.assistantPresentation, isTrue);
      expect(find.byType(AiChatScreen), findsOneWidget);
      expect(identical(tester.state(find.byType(AiChatScreen)), assistant),
          isTrue);
      expect(underlying.isActive, isTrue);
      expect(tester.widget<TextField>(input).controller!.text,
          'mój niedokończony opis');
      expect(
          tester.getSize(find.byType(AiChatScreen)).height, greaterThan(600));

      // Dialogs still hide the conversation, even on its dedicated page.
      final dialog = showDialog<void>(
          context: appNavigatorKey.currentState!.overlay!.context,
          builder: (_) => const AlertDialog(content: Text('Private dialog')));
      await settle(tester);
      expect(appRoutes.assistantAvailable, isFalse);
      appNavigatorKey.currentState!.pop();
      await dialog;
      await settle(tester);
      expect(appRoutes.assistantAvailable, isTrue);

      if (closeWithBack) {
        await appNavigatorKey.currentState!.maybePop();
      } else {
        await tester.tap(find.byTooltip('Zwiń'));
      }
      await settle(tester);
      expect(appRoutes.top, same(underlying));
      expect(appRoutes.assistantAvailable, isFalse);
      appNavigatorKey.currentState!.pop();
      AssistantPanelController.instance.setExpanded(true);
      await settle(tester);
      expect(identical(tester.state(find.byType(AiChatScreen)), assistant),
          isTrue);
      expect(tester.widget<TextField>(input).controller!.text,
          'mój niedokończony opis');
      expect(tester.takeException(), isNull);
    });
  }
}
