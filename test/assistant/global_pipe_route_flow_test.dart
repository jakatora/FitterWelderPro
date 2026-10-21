import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cut_list_app/app.dart';
import 'package:cut_list_app/assistant/core/assistant_panel_controller.dart';
import 'package:cut_list_app/assistant/core/tool_bridge.dart';
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

Future<void> say(WidgetTester t, String s) async {
  await t.enterText(find.byKey(const Key('assistant-command')), s);
  await t.tap(find.byKey(const Key('assistant-go')));
  await settle(t);
}

void main() {
  useTestDatabase();
  testWidgets(
      'actual conversation uses current route, end welds, recalc, clear and private gaps',
      (t) async {
    seedFreshInstall();
    ToolBridge.reset();
    expect(
        await FeedbackConsent.instance.grant(now: DateTime.utc(2026, 10, 21)),
        true);
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
    await say(t, 'oblicz trasę rur');
    expect(find.textContaining('Podaj H1'), findsOneWidget);
    await say(t, '2 m');
    await say(t, '50 cm');
    await say(t, '1 m');
    await say(t, '80 cm');
    await say(t, 'DN100');
    await say(t, '3 mm');
    expect(find.textContaining('Czy X i Y są mierzone'), findsOneWidget);
    await say(t, 'nie');
    expect(ToolBridge.instance.current?.toolId, 'pipe_route');
    expect(find.textContaining('2680 mm'), findsWidgets);
    final prefs = await SharedPreferences.getInstance();
    Future<void> manual(String label, String value) async {
      AssistantPanelController.instance.setExpanded(false);
      await settle(t);
      final f = find.byWidgetPredicate(
          (w) => w is TextField && w.decoration?.labelText == label);
      await t.ensureVisible(f);
      await t.pumpAndSettle();
      await t.enterText(f, value);
      await settle(t);
      AssistantPanelController.instance.setExpanded(true);
      await settle(t);
    }

    await manual('X – bieg poziomy 1', '2000');
    await say(t, 'zmień szczelinę na 2 mm');
    expect(prefs.getString('pipe_route.x'), '2000.0');
    expect(prefs.getString('pipe_route.gap'), '2.0');
    expect(find.textContaining('3684 mm'), findsWidgets);
    await say(t, 'a spoiny końcowe tak');
    expect(prefs.getBool('pipe_route.end_welds'), true);
    expect(find.textContaining('3680 mm'), findsWidgets);
    await manual('R – takeout kolanka 90° (C-F)', '100');
    await say(t, 'oblicz aktualną trasę');
    expect(prefs.getInt('pipe_route.dn'), isNull);
    expect(prefs.getString('pipe_route.r'), '100.0');
    expect(find.textContaining('3888 mm'), findsWidgets);
    final before = prefs.getString('pipe_route.h1');
    await say(t, 'a H1 500 mm');
    expect(find.textContaining('Podaj różne H1 i H2'), findsOneWidget);
    expect(prefs.getString('pipe_route.h1'), before);
    await say(t, 'H1 2000 mm');
    expect(prefs.getString('pipe_route.h1'), '2000.0');
    expect(await FeedbackStore.instance.list(), isEmpty);
    await say(t, 'oblicz trasę rur trzy kolana 90 stopni');
    expect(find.textContaining('dokładnie dwa kolana 90'), findsOneWidget);
    final reports = await FeedbackStore.instance.list();
    expect(reports, hasLength(1));
    expect(reports.single.skill, 'pipe.route');
    expect(prefs.getString('pipe_route.h1'), '2000.0');
    await say(t, 'wyczyść trasę rur');
    expect(prefs.getString('pipe_route.h1'), '');
    expect(prefs.getString('pipe_route.r'), '');
    await say(t, 'oblicz aktualną trasę');
    expect(find.textContaining('Podaj H1'), findsOneWidget);
    expect(await FeedbackStore.instance.list(), hasLength(1));
    expect(t.takeException(), isNull);
  });
}
