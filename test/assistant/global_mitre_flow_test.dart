import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cut_list_app/app.dart';
import 'package:cut_list_app/assistant/core/assistant_panel_controller.dart';
import 'package:cut_list_app/assistant/core/tool_bridge.dart';
import 'package:cut_list_app/feedback/feedback_consent.dart';
import 'package:cut_list_app/feedback/feedback_store.dart';
import 'package:cut_list_app/widgets/readout.dart';
import '../support/test_database.dart';
import '../test_prefs.dart';

Future<void> settle(WidgetTester t) async {
  for (var i = 0; i < 5; i++) {
    await flushTestDatabase(t);
    await t.pump(const Duration(milliseconds: 200));
  }
  await t.pumpAndSettle();
}

Future<void> say(WidgetTester t, String text) async {
  await t.enterText(find.byKey(const Key('assistant-command')), text);
  await t.tap(find.byKey(const Key('assistant-go')));
  await settle(t);
}

void main() {
  useTestDatabase();
  testWidgets(
      'common assistant asks, opens real mitre module, applies correction and keeps invalid input out',
      (t) async {
    seedFreshInstall();
    ToolBridge.reset();
    expect(
        await FeedbackConsent.instance.grant(now: DateTime.utc(2026, 10, 21)),
        isTrue);
    t.view.physicalSize = const Size(1080, 2400);
    t.view.devicePixelRatio = 2.5;
    addTearDown(t.view.reset);
    addTearDown(() async {
      await t.pumpWidget(const SizedBox.shrink());
      await settle(t);
      AssistantPanelController.instance.setExpanded(false);
    });
    await t.pumpWidget(const CutListApp());
    await settle(t);
    await t.tap(find.byTooltip('Powiedz, co zrobić'));
    await settle(t);
    await say(t, 'oblicz kolano segmentowe');
    expect(find.textContaining('Jaka średnica zewnętrzna OD'), findsOneWidget);
    expect(ToolBridge.instance.current?.toolId, isNot('mitre_bend'));
    await say(t, '168,3 mm');
    await say(t, '90');
    await say(t, '3');
    await say(t, '252,45 mm');
    await say(t, '0 mm');
    expect(ToolBridge.instance.current?.toolId, 'mitre_bend');
    expect(
        t
            .widget<TextField>(find.byKey(const ValueKey('mitre-od')))
            .controller!
            .text,
        '168.3');
    expect(
        t
            .widget<TextField>(find.byKey(const ValueKey('mitre-radius')))
            .controller!
            .text,
        '252.45');
    expect(find.textContaining('kąt cięcia 15°'), findsWidgets);
    await say(t, 'a spoiny 4');
    expect(
        t
            .widget<ChoiceChip>(find.byKey(const ValueKey('mitre-welds-4')))
            .selected,
        isTrue);
    await say(t, 'a promień 50 mm');
    expect(find.textContaining('Jaki promień po osi'), findsOneWidget);
    expect(
        t
            .widget<TextField>(find.byKey(const ValueKey('mitre-radius')))
            .controller!
            .text,
        '252.45');
    await say(t, '300 mm');
    expect(
        t
            .widget<TextField>(find.byKey(const ValueKey('mitre-radius')))
            .controller!
            .text,
        '300.0');
    await say(t, 'a spoiny 12');
    expect(
        t
            .widget<ChoiceChip>(find.byKey(const ValueKey('mitre-welds-12')))
            .selected,
        isTrue);
    expect(
        find.descendant(of: find.byType(Readout), matching: find.text('3,75')),
        findsOneWidget);
    expect(await FeedbackStore.instance.list(), isEmpty,
        reason:
            'supported calculation and invalid user dimensions are not missing capabilities');
    expect(t.takeException(), isNull);
  });
}
