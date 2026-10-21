import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cut_list_app/app.dart';
import 'package:cut_list_app/assistant/core/assistant_panel_controller.dart';
import 'package:cut_list_app/assistant/core/tool_bridge.dart';
import 'package:cut_list_app/features/tube_bending/tube_bending_store.dart';
import 'package:cut_list_app/feedback/feedback_consent.dart';
import 'package:cut_list_app/feedback/feedback_store.dart';
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

Future<TubeBendingSaved> saved() async => decodeTubeBending(
        (await SharedPreferences.getInstance()).getString(TubeBendingStore.key))
    .state!;
void main() {
  useTestDatabase();
  testWidgets(
      'global conversation controls all three tube modes and preserves invalid-input state',
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
    await say(t, 'oblicz gięcie rurek');
    expect(find.textContaining('Który tryb gięcia rurki'), findsOneWidget);
    await say(t, 'jedno');
    await say(t, '38 mm');
    await say(t, '90');
    await say(t, '200 mm');
    await say(t, '150 mm');
    expect(ToolBridge.instance.current?.toolId, 'tube_bending');
    expect(find.textContaining('Utnij 334 mm'), findsWidgets);
    final first = await saved();
    expect(first.mode, TubeBendingMode.single);
    expect(first.singleLegAMm, 200);
    Future<void> manual(String key, String text) async {
      AssistantPanelController.instance.setExpanded(false);
      await settle(t);
      final finder = find.byKey(ValueKey(key));
      final scroll = find
          .descendant(
              of: find.byKey(const ValueKey('tb-list')),
              matching: find.byType(Scrollable))
          .first;
      if (finder.evaluate().isEmpty) {
        await t.scrollUntilVisible(finder, 300,
            scrollable: scroll, maxScrolls: 40);
      }
      await t.ensureVisible(finder);
      await t.pumpAndSettle();
      await t.enterText(finder, text);
      await settle(t);
      AssistantPanelController.instance.setExpanded(true);
      await settle(t);
    }

    await manual('tb-s-a', '400');
    await say(t, 'zmień kąt na 45 stopni');
    expect((await saved()).singleLegAMm, 400,
        reason: 'manual input is newer than the previous conversation');
    expect((await saved()).singleAngleDeg, 45);
    await manual('tb-s-angle', '0');
    await say(t, 'przełącz na cale');
    expect((await saved()).unit.name, 'inch');
    expect((await saved()).singleAngleDeg, 0);
    await say(t, 'zmień kąt na 60 stopni');
    expect((await saved()).singleAngleDeg, 60);
    expect((await saved()).singleLegAMm, 400);
    await say(t, 'a ramię B 300 mm');
    expect((await saved()).singleLegBMm, 300);
    expect((await saved()).singleAngleDeg, 60);
    final prefs = await SharedPreferences.getInstance();
    final before = prefs.getString(TubeBendingStore.key);
    await say(t, 'a CLR 0 mm');
    expect(
        find.textContaining('Jaki promień gięcia po osi CLR'), findsOneWidget);
    expect(prefs.getString(TubeBendingStore.key), before);
    await say(t, '30 mm');
    expect((await saved()).clrMm, 30);
    await say(t,
        'gięcie rurki odsadzka CLR 38 mm wysokość 100 mm kąt 45 stopni ramię A 200 mm ramię B 200 mm');
    expect((await saved()).mode, TubeBendingMode.offset);
    await say(t,
        'gięcie rurki wiele gięć CLR 38 mm odcinki 150 mm 200 mm 250 mm kąty 90 45 obroty 0 180');
    final multi = await saved();
    expect(multi.mode, TubeBendingMode.multi);
    expect(multi.anglesDeg, [90, 45]);
    expect(multi.rotationsDeg, [0, 180]);
    await say(t, 'a odcinki 160 mm 200 mm 250 mm');
    expect((await saved()).segmentsMm, [160, 200, 250]);
    await say(t, 'a jednostki cale');
    expect((await saved()).unit.name, 'inch');
    expect((await saved()).clrMm, 38);
    final last = prefs.getString(TubeBendingStore.key);
    await say(t, 'a kąty 180 45');
    expect(find.textContaining('Podaj listę od 1 do 12 kątów'), findsOneWidget);
    expect(prefs.getString(TubeBendingStore.key), last);
    expect(await FeedbackStore.instance.list(), isEmpty);
    expect(t.takeException(), isNull);
  });
}
