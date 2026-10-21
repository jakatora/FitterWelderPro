import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cut_list_app/app.dart';
import 'package:cut_list_app/app_navigator.dart';
import 'package:cut_list_app/assistant/assistant_history.dart';
import 'package:cut_list_app/assistant/core/assistant_panel_controller.dart';
import 'package:cut_list_app/assistant/core/tool_bridge.dart';
import 'package:cut_list_app/features/confined_space/confined_space_store.dart';
import 'package:cut_list_app/features/confined_space/confined_space_edit_page.dart';
import 'package:cut_list_app/screens/ai_chat_screen.dart';

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
  final f = find.byKey(Key(key));
  await t.ensureVisible(f);
  await t.pumpAndSettle();
  await t.tap(f);
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
      'production chat creates a safe draft after touch, opens its editor, then undoes',
      (t) async {
    t.view.physicalSize = const Size(1080, 2400);
    t.view.devicePixelRatio = 2.5;
    addTearDown(t.view.reset);
    await t.pumpWidget(const CutListApp());
    await settle(t);
    await t.tap(find.byTooltip('Powiedz, co zrobić'));
    await settle(t);
    const store = ConfinedSpaceStore();
    await say(t, 'przygotuj protokół przestrzeni zamkniętej');
    expect(find.text('Gdzie mają być prowadzone prace?'), findsOneWidget);
    await say(t, 'Zbiornik A');
    expect(find.text('Jaki jest opis prac?'), findsOneWidget);
    await say(t, 'Spawanie podpory');
    expect(find.byKey(const Key('assistant-touch-only')), findsOneWidget);
    expect(await t.runAsync(() async => (await store.load()).records), isEmpty);
    await say(t, 'tak');
    expect(await t.runAsync(() async => (await store.load()).records), isEmpty);
    await t.scrollUntilVisible(find.textContaining('dotknięcia przycisku'), 150,
        scrollable: find
            .descendant(
                of: find.byType(AiChatScreen).last,
                matching: find.byType(Scrollable))
            .first);
    await t.pumpAndSettle();
    expect(find.textContaining('dotknięcia przycisku'), findsOneWidget);
    await tap(t, 'assistant-local-save');
    expect(find.byType(ConfinedSpaceEditPage), findsOneWidget);
    final editor =
        t.widget<ConfinedSpaceEditPage>(find.byType(ConfinedSpaceEditPage));
    expect(editor.initial.location, 'Zbiornik A');
    expect(editor.initial.description, 'Spawanie podpory');
    expect(editor.initial.checked, isEmpty);
    expect(editor.initial.na, isEmpty);
    expect(editor.initial.measurements, isEmpty);
    expect(editor.initial.assess(now: DateTime.now()).readyToEnter, isFalse);
    expect(await t.runAsync(() async => (await store.load()).records),
        hasLength(1));
    await appNavigatorKey.currentState!.maybePop();
    await settle(t);
    await say(t, 'cofnij zapis');
    expect(await t.runAsync(() async => (await store.load()).records), isEmpty);
    expect(AssistantHistoryStore.instance.entries.single.undone, isTrue);
    await say(t,
        'przygotuj protokół przestrzeni zamkniętej, miejsce: B; opis: Cięcie');
    await tap(t, 'assistant-local-cancel');
    expect(await t.runAsync(() async => (await store.load()).records), isEmpty);
    await t.pumpWidget(const SizedBox.shrink());
    await settle(t);
  });
}
