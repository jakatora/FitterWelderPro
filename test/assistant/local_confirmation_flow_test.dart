import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cut_list_app/app.dart';
import 'package:cut_list_app/app_navigator.dart';
import 'package:cut_list_app/assistant/assistant_history.dart';
import 'package:cut_list_app/assistant/core/assistant_panel_controller.dart';
import 'package:cut_list_app/assistant/core/skill.dart';
import 'package:cut_list_app/assistant/core/tool_bridge.dart';
import 'package:cut_list_app/features/hot_work/hot_work_store.dart';
import 'package:cut_list_app/features/hot_work/hot_work_edit_page.dart';
import 'package:cut_list_app/i18n/app_language.dart';
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

class _ControlledWrite extends AssistantSkill {
  _ControlledWrite(this.save, {this.touchOnly = true});
  final Future<UndoAction?> Function() save;
  final bool touchOnly;
  @override
  String get id => 'test.write';
  @override
  String? get toolId => null;
  @override
  AssistantTier get tier => AssistantTier.c;
  @override
  List<SkillExample> get examples => const [];
  @override
  SkillMatch? match(Utterance u, AssistantContext ctx) =>
      u.folded == 'prepare test' ? SkillMatch(this, 1) : null;
  @override
  Future<SkillResult> run(SkillMatch m, AssistantContext ctx) async =>
      ConfirmResult(
          const AssistantAnswer(
              text: AssistantText.same('Review draft'),
              lines: [AnswerLine(AssistantText.same('Location'), 'Hall A')]),
          save,
          touchOnly: touchOnly);
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
    const store = HotWorkStore();
    await say(t, 'przygotuj protokół prac gorących');
    expect(find.text('Gdzie mają być prowadzone prace?'), findsOneWidget);
    await say(t, 'Hala A');
    expect(find.text('Jaki jest opis prac?'), findsOneWidget);
    await say(t, 'Spawanie podpory');
    expect(find.byKey(const Key('assistant-touch-only')), findsOneWidget);
    expect(await t.runAsync(store.load), isEmpty);
    await say(t, 'tak');
    expect(await t.runAsync(store.load), isEmpty);
    await t.scrollUntilVisible(find.textContaining('dotknięcia przycisku'), 150,
        scrollable: find
            .descendant(
                of: find.byType(AiChatScreen).last,
                matching: find.byType(Scrollable))
            .first);
    await t.pumpAndSettle();
    expect(find.textContaining('dotknięcia przycisku'), findsOneWidget);
    await tap(t, 'assistant-local-save');
    expect(find.byType(HotWorkEditPage), findsOneWidget);
    final editor = t.widget<HotWorkEditPage>(find.byType(HotWorkEditPage));
    expect(editor.initial.location, 'Hala A');
    expect(editor.initial.description, 'Spawanie podpory');
    expect(editor.initial.checked, isEmpty);
    expect(editor.initial.na, isEmpty);
    expect(editor.initial.measurements, isEmpty);
    expect(editor.initial.assess(now: DateTime.now()).readyToStart, isFalse);
    expect(await t.runAsync(store.load), hasLength(1));
    await appNavigatorKey.currentState!.maybePop();
    await settle(t);
    await say(t, 'cofnij zapis');
    expect(await t.runAsync(store.load), isEmpty);
    expect(AssistantHistoryStore.instance.entries.single.undone, isTrue);
    await say(t, 'przygotuj protokół prac gorących, miejsce: B; opis: Cięcie');
    await tap(t, 'assistant-local-cancel');
    expect(await t.runAsync(store.load), isEmpty);
    await t.pumpWidget(const SizedBox.shrink());
    await settle(t);
  });

  testWidgets(
      'pending save blocks double execution, sanitizes failure and can retry or undo',
      (t) async {
    final gate = Completer<UndoAction?>();
    var saves = 0, undos = 0;
    final skill = _ControlledWrite(() async {
      saves++;
      if (saves == 1) return gate.future;
      return () async {
        undos++;
      };
    });
    await t.pumpWidget(AppLanguageScope(
        controller: AppLanguageController(AppLanguage.en),
        child: MaterialApp(
            home: Scaffold(
                body: AiChatScreen(embedded: true, skills: [skill])))));
    await settle(t);
    await say(t, 'prepare test');
    expect(find.text('Hall A'), findsOneWidget);
    await say(t, 'yes');
    expect(saves, 0);
    final button = find.byKey(const Key('assistant-local-save'));
    await t.ensureVisible(button);
    await t.pumpAndSettle();
    await t.tap(button);
    await t.pump(const Duration(milliseconds: 50));
    expect(saves, 1);
    expect(t.widget<FilledButton>(button).onPressed, isNull);
    await t.tap(button);
    await t.pump();
    expect(saves, 1);
    gate.completeError(StateError('private-storage-path'));
    await settle(t);
    expect(find.textContaining('Could not confirm the save'), findsOneWidget);
    expect(find.textContaining('private-storage-path'), findsNothing);
    expect(find.text('Saved.'), findsNothing);
    await tap(t, 'assistant-local-save');
    expect(saves, 2);
    expect(find.text('Saved.'), findsOneWidget);
    await tap(t, 'assistant-local-undo');
    expect(undos, 1);
    expect(find.text('Save undone.'), findsOneWidget);
    await t.pumpWidget(const SizedBox.shrink());
    await settle(t);
  });

  testWidgets('ordinary confirmation accepts an explicit yes after review',
      (t) async {
    var writes = 0;
    final skill = _ControlledWrite(() async {
      writes++;
      return null;
    }, touchOnly: false);
    await t.pumpWidget(AppLanguageScope(
        controller: AppLanguageController(AppLanguage.en),
        child: MaterialApp(
            home: Scaffold(
                body: AiChatScreen(embedded: true, skills: [skill])))));
    await settle(t);
    await say(t, 'prepare test');
    expect(writes, 0);
    await say(t, 'yes');
    expect(writes, 1);
    expect(find.text('Saved.'), findsOneWidget);
    await t.pumpWidget(const SizedBox.shrink());
    await settle(t);
  });
}
