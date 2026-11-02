import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cut_list_app/assistant/assistant_ai_client.dart';
import 'package:cut_list_app/assistant/core/tool_bridge.dart';
import 'package:cut_list_app/screens/consent_screen.dart';
import 'package:cut_list_app/screens/ai_chat_screen.dart';
import 'package:cut_list_app/services/legal_consent.dart';
import '../support/test_account.dart';
import '../support/test_database.dart';
import 'ai_chat_execution_test.dart' show mount;
import 'global_pipe_slope_flow_test.dart' show say, settle;

const request = 'Przejdźmy teraz do kalkulatora heat input';
final enable = find.byKey(const Key('assistant-enable-ai'));

Future<void> accept(WidgetTester t) async {
  final checkbox = find.byType(Checkbox);
  final scroll = find
      .descendant(
          of: find.byType(ConsentScreen), matching: find.byType(Scrollable))
      .first;
  await t.scrollUntilVisible(checkbox, 200, scrollable: scroll);
  await t.tap(checkbox);
  await t.pump();
  final button = find.widgetWithText(FilledButton, 'Akceptuję');
  await t.scrollUntilVisible(button, 100, scrollable: scroll);
  await t.tap(button);
  await settle(t);
}

void main() {
  useGuestAccount();
  useTestDatabase();
  testWidgets('enable action remains reachable with large text', (t) async {
    t.platformDispatcher.textScaleFactorTestValue = 1.8;
    addTearDown(t.platformDispatcher.clearTextScaleFactorTestValue);
    await mount(t,
        consent: false,
        interpret: (_) async => throw StateError('No request before consent'));
    await say(t, request);
    final panelScroll = find
        .descendant(
            of: find.byType(AiChatScreen), matching: find.byType(Scrollable))
        .first;
    await t.scrollUntilVisible(enable, 100, scrollable: panelScroll);
    expect(t.getSize(enable).height, greaterThanOrEqualTo(48));
    expect(find.text('Włącz AI'), findsOneWidget);
    expect(t.takeException(), isNull);
  });
  for (final duplicate in [false, true]) {
    testWidgets(
        'compact assistant enables AI with consent once duplicate=$duplicate',
        (t) async {
      var calls = 0;
      await mount(t, consent: false, interpret: (r) async {
        calls++;
        expect(LegalConsent.instance.isAccepted, isTrue);
        expect(r['text'], request);
        return const AiCommandPlan(
            'execute', [AiCommandStep('tool.open', 'Otwórz heat input')], '');
      });
      await say(t, request);
      expect(calls, 0);
      expect(enable, findsOneWidget);
      await t.ensureVisible(enable);
      final activate = t.widget<OutlinedButton>(enable).onPressed!;
      activate();
      if (duplicate) activate();
      await settle(t);
      expect(find.byType(ConsentScreen, skipOffstage: false), findsOneWidget);
      expect(calls, 0);
      await accept(t);
      expect(calls, 1);
      expect(ToolBridge.instance.activeToolId, 'heat_input');
      expect(find.byType(ConsentScreen), findsNothing);
      expect(t.takeException(), isNull);
    });
  }
  testWidgets('declining AI consent retains the command and sends nothing',
      (t) async {
    var calls = 0;
    await mount(t, consent: false, interpret: (_) async {
      calls++;
      throw StateError('No request without consent');
    });
    await say(t, request);
    await t.ensureVisible(enable);
    await t.tap(enable);
    await settle(t);
    expect(find.byType(ConsentScreen), findsOneWidget);
    await t.pageBack();
    await settle(t);
    expect(calls, 0);
    expect(LegalConsent.instance.isAccepted, isFalse);
    final input =
        t.widget<TextField>(find.byKey(const Key('assistant-command')));
    expect(input.controller!.text, request);
    expect(t.widget<OutlinedButton>(enable).onPressed, isNotNull);
    expect(ToolBridge.instance.activeToolId, 'rolling_offset');
    expect(t.takeException(), isNull);
  });
}
