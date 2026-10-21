import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cut_list_app/app.dart';
import 'package:cut_list_app/app_navigator.dart';
import 'package:cut_list_app/assistant/assistant_history.dart';
import 'package:cut_list_app/assistant/core/assistant_panel_controller.dart';
import 'package:cut_list_app/assistant/core/tool_bridge.dart';
import 'package:cut_list_app/domain/welding/interpass_log.dart';
import 'package:cut_list_app/features/interpass/interpass_store.dart';
import 'package:cut_list_app/features/interpass/interpass_weld_page.dart';
import '../support/test_database.dart';
import '../test_prefs.dart';

Future<void> settle(WidgetTester t) async {
  for (var i = 0; i < 5; i++) {
    await flushTestDatabase(t);
    await t.pump(const Duration(milliseconds: 100));
  }
  await t.pumpAndSettle();
}

Future<void> say(WidgetTester t, String text) async {
  await t.enterText(find.byKey(const Key('assistant-command')), text);
  await t.tap(find.byKey(const Key('assistant-go')));
  await settle(t);
}

Future<void> tap(WidgetTester t, String key) async {
  final finder = find.byKey(Key(key));
  await t.ensureVisible(finder);
  await t.pumpAndSettle();
  await t.tap(finder);
  await settle(t);
}

void main() {
  useTestDatabase();
  setUp(() {
    seedFreshInstall();
    AssistantHistoryStore.instance.resetForTest();
    ToolBridge.reset();
    AssistantPanelController.instance.setExpanded(false);
  });
  testWidgets(
      'production chat confirms by touch and voice, opens actual weld, keeps context and undoes',
      (t) async {
    t.view.physicalSize = const Size(1080, 2400);
    t.view.devicePixelRatio = 2.5;
    addTearDown(t.view.reset);
    const store = InterpassStore();
    final before = InterpassWeld.blank(id: 'selected-weld', now: DateTime.now())
        .copyWith(
            weldNo: 'W-12',
            description: 'Linia A',
            wpsRef: 'WPS-1',
            passCount: 3,
            limits: const InterpassLimits(
                preheatMin: InterpassTemp.c(100),
                interpassMax: InterpassTemp.c(150)));
    await t.runAsync(() => store.upsert(before));
    await t.pumpWidget(const CutListApp());
    await settle(t);
    await t.tap(find.byTooltip('Powiedz, co zrobić'));
    await settle(t);
    await say(
        t, 'Zapisz pomiar 120 C przed ściegiem 2 pirometr teraz spoina W-12');
    expect(find.byKey(const Key('assistant-touch-only')), findsNothing);
    expect(
        (await t.runAsync(() => store.load()))!.welds.single.readings, isEmpty);
    await tap(t, 'assistant-local-save');
    expect(find.byType(InterpassWeldPage), findsOneWidget);
    expect(ToolBridge.instance.selectedRecordId('interpass'), 'selected-weld');
    expect(appRoutes.assistantAvailable, true);
    final after = (await t.runAsync(() => store.load()))!.welds.single;
    expect(after.readings.single.tempC, 120);
    expect(after.readings.single.method, InterpassMethod.pyrometer);
    expect(after.toJson()['preheatMin'], before.toJson()['preheatMin']);
    expect(after.toJson()['interpassMax'], before.toJson()['interpassMax']);
    // The conversation remains available over the editor. Undo reloads its log.
    await say(t, 'cofnij zapis');
    expect(
        (await t.runAsync(() => store.load()))!.welds.single.readings, isEmpty);
    expect(AssistantHistoryStore.instance.entries.single.undone, true);
    // No weld number: the real selected editor supplies identity.
    await say(
        t, 'Dodaj pomiar 130 C przed ściegiem 3 termometr kontaktowy teraz');
    expect(find.byKey(const Key('assistant-local-save')), findsOneWidget);
    await say(t, 'tak');
    expect(
        (await t.runAsync(() => store.load()))!
            .welds
            .single
            .readings
            .single
            .pass,
        3);
    expect(find.byType(InterpassWeldPage), findsOneWidget);
    await t.pumpWidget(const SizedBox.shrink());
    await settle(t);
  });
}
