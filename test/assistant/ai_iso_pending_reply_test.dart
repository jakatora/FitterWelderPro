import 'dart:convert';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cut_list_app/assistant/assistant_ai_client.dart';
import 'package:cut_list_app/database/db.dart';
import 'package:cut_list_app/database/iso_drawing_dao.dart';
import 'package:cut_list_app/screens/iso_notebook_screen.dart';
import 'package:cut_list_app/screens/ai_chat_screen.dart';
import '../support/test_database.dart';
import 'ai_chat_execution_test.dart' show mount;
import 'global_pipe_slope_flow_test.dart' show say, settle;

const isoStart =
    'Narysuj rura metr w prawo zawór DN50 rura 500 mm. Następnie dorysuj rura 200 mm w górę.';

const drawPlan = AiCommandPlan(
    'execute',
    [
      AiCommandStep(
          'iso.draw', 'Narysuj rura metr w prawo zawór DN50 rura 500 mm'),
      AiCommandStep('iso.draw', 'Dorysuj rura 200 mm w górę'),
    ],
    '');

void main() {
  useTestDatabase();
  setUp(() async => (await AppDatabase.get()).delete('iso_drawings'));
  testWidgets(
      'ISO valve clarification pauses ordered AI drawing then preserves native route and DN',
      (t) async {
    var calls = 0;
    await mount(t, interpret: (r) async {
      if (++calls == 1) return drawPlan;
      final context = r['context'] as Map;
      expect((context['pending_reply'] as Map)['slot'], 'iso_valve');
      expect((r['capabilities'] as List), hasLength(1));
      return const AiCommandPlan(
          'reply', [AiCommandStep('iso.draw', 'check')], '');
    });
    await say(t, isoStart);
    expect(IsoNotebookController.active, isNull);
    expect(find.textContaining('Jaki rodzaj zaworu'), findsOneWidget);
    await say(t, 'Taki, który zapobiega cofnięciu medium');
    expect(calls, 2);
    final c = IsoNotebookController.active!;
    for (var i = 0; i < 10 && c.isBusy; i++) {
      await settle(t);
    }
    expect(c.debugPipeAxisTags, hasLength(3));
    await t.pump(const Duration(milliseconds: 600));
    await flushTestDatabase(t);
    final saved = await t.runAsync(() => IsoDrawingDao().latest());
    final items = (jsonDecode(saved!.json) as Map)['items'] as List;
    expect(items.where((x) => x['tool'] == 'checkValve'), hasLength(1));
    expect(items.singleWhere((x) => x['tool'] == 'checkValve')['dn'], 50);
    expect(items.where((x) => x['tool'] == 'pipe').map((x) => x['calc']['iso']),
        orderedEquals(['1000', '500', '200']));
  });
  testWidgets(
      'cancelling an ISO question discards remaining planned drawing steps',
      (t) async {
    var calls = 0;
    await mount(t, interpret: (_) async {
      calls++;
      return drawPlan;
    });
    await say(t, 'Ogarnij mi układ z zaworem na kartce.');
    await say(t, 'anuluj');
    expect(IsoNotebookController.active, isNull);
    expect(await t.runAsync(() => IsoDrawingDao().latest()), isNull);
    expect(calls, 1);
  });
  testWidgets(
      'natural cancellation of ISO question never executes remaining drawing',
      (t) async {
    var calls = 0;
    await mount(t, interpret: (_) async {
      if (++calls == 1) return drawPlan;
      return const AiCommandPlan(
          'reply', [AiCommandStep('iso.draw', 'cancel')], '');
    });
    await say(t, 'Ogarnij mi układ na kartce.');
    await say(t, 'Zostawmy to jednak na później');
    expect(calls, 2);
    expect(IsoNotebookController.active, isNull);
    expect(await t.runAsync(() => IsoDrawingDao().latest()), isNull);
  });
  testWidgets(
      'new explicit drawing supersedes the old question and its queued tail',
      (t) async {
    var calls = 0;
    await mount(t, interpret: (_) async {
      calls++;
      return drawPlan;
    });
    await say(t, 'Ogarnij mi układ na kartce.');
    await say(t, 'Narysuj rura 700 mm w prawo');
    expect(calls, 1);
    expect(IsoNotebookController.active!.debugPipeAxisTags, hasLength(1));
    await flushTestDatabase(t);
    final saved = await t.runAsync(() => IsoDrawingDao().latest());
    final items = (jsonDecode(saved!.json) as Map)['items'] as List;
    expect(items.where((x) => x['tool'] == 'pipe'), hasLength(1));
    expect(items.where((x) => x['tool'] == 'checkValve'), isEmpty);
  });
  testWidgets(
      'a refused native drawing step does not run the rest of the AI plan',
      (t) async {
    await mount(t,
        interpret: (_) async => const AiCommandPlan(
            'execute',
            [
              AiCommandStep('iso.draw',
                  'Narysuj rura metr w prawo kolano 30 stopni w górę rura metr'),
              AiCommandStep('iso.draw', 'Dorysuj rura 200 mm w górę'),
            ],
            ''));
    await say(t, 'Ułóż mi ten układ na kartce.');
    expect(IsoNotebookController.active, isNull);
    expect(await t.runAsync(() => IsoDrawingDao().latest()), isNull);
  });
  testWidgets(
      'late valve answer cannot mutate the sketch after a manual native undo',
      (t) async {
    final pending = Completer<AiCommandPlan>();
    var calls = 0;
    await mount(t, interpret: (_) async {
      if (++calls == 1) {
        return const AiCommandPlan(
            'execute',
            [
              AiCommandStep('iso.draw',
                  'Dorysuj rura metr w prawo zawór DN50 rura 500 mm'),
            ],
            '');
      }
      return pending.future;
    });
    await say(t, 'Narysuj rura 300 mm w prawo');
    final c = IsoNotebookController.active!;
    await say(t, 'Ogarnij mi kolejną rzecz proszę');
    expect(calls, 1);
    await t.enterText(find.byKey(const Key('assistant-command')),
        'Taki, który zapobiega cofnięciu medium');
    await t.tap(find.byKey(const Key('assistant-go')));
    await t.pump(const Duration(milliseconds: 200));
    expect(calls, 2);
    final before = c.revision;
    c.undo();
    expect(c.revision, greaterThan(before));
    await t.pump(const Duration(milliseconds: 200));
    pending.complete(
        const AiCommandPlan('reply', [AiCommandStep('iso.draw', 'check')], ''));
    await settle(t);
    expect(c.hasContent, isFalse);
    await t.scrollUntilVisible(find.textContaining('dane zmieniły się'), 120,
        scrollable: find
            .descendant(
                of: find.byType(AiChatScreen).last,
                matching: find.byType(Scrollable))
            .first);
    expect(find.textContaining('dane zmieniły się'), findsOneWidget);
  });
  testWidgets(
      'model-added DN is rejected while the user can explicitly change it',
      (t) async {
    var calls = 0;
    await mount(t, interpret: (_) async {
      if (++calls == 1) return drawPlan;
      return const AiCommandPlan(
          'reply', [AiCommandStep('iso.draw', 'check DN80')], '');
    });
    await say(t, 'Ogarnij mi układ na kartce.');
    await say(t, 'Taki, który zapobiega cofnięciu medium');
    expect(calls, 2);
    expect(IsoNotebookController.active, isNull);
    await say(t, 'check');
    for (var i = 0; i < 10 && IsoNotebookController.active!.isBusy; i++) {
      await settle(t);
    }
    await t.pump(const Duration(milliseconds: 600));
    await flushTestDatabase(t);
    final saved = await t.runAsync(() => IsoDrawingDao().latest());
    final items = (jsonDecode(saved!.json) as Map)['items'] as List;
    expect(items.singleWhere((x) => x['tool'] == 'checkValve')['dn'], 50);
    expect(calls, 2);
  });
  testWidgets(
      'explicit DN in natural reply is accepted by the native valve dialogue',
      (t) async {
    var calls = 0;
    await mount(t, interpret: (_) async {
      if (++calls == 1) return drawPlan;
      return const AiCommandPlan(
          'reply', [AiCommandStep('iso.draw', 'check DN80')], '');
    });
    await say(t, 'Ogarnij mi układ na kartce.');
    await say(t, 'Taki, który zapobiega cofnięciu medium, DN80');
    expect(calls, 2);
    for (var i = 0; i < 10 && IsoNotebookController.active!.isBusy; i++) {
      await settle(t);
    }
    await t.pump(const Duration(milliseconds: 600));
    await flushTestDatabase(t);
    final saved = await t.runAsync(() => IsoDrawingDao().latest());
    final items = (jsonDecode(saved!.json) as Map)['items'] as List;
    expect(items.singleWhere((x) => x['tool'] == 'checkValve')['dn'], 80);
  });
  testWidgets(
      'natural append choice retains the existing sketch and adds only the pending segment',
      (t) async {
    var calls = 0;
    await mount(t, interpret: (r) async {
      if (++calls == 1) {
        return const AiCommandPlan(
            'execute',
            [
              AiCommandStep('iso.draw', 'Narysuj rura 500 mm w górę'),
            ],
            '');
      }
      expect(
          ((r['context'] as Map)['pending_reply'] as Map)['slot'], 'iso_mode');
      return const AiCommandPlan(
          'reply', [AiCommandStep('iso.draw', 'append')], '');
    });
    await say(t, 'Narysuj rura 300 mm w prawo');
    await say(t, 'Ogarnij mi kolejną rzecz proszę');
    expect(IsoNotebookController.active!.debugPipeAxisTags, hasLength(1));
    await say(t, 'Dołącz to do bieżącego szkicu');
    expect(calls, 2);
    expect(IsoNotebookController.active!.debugPipeAxisTags, hasLength(2));
    await flushTestDatabase(t);
    final saved = await t.runAsync(() => IsoDrawingDao().latest());
    final items = (jsonDecode(saved!.json) as Map)['items'] as List;
    expect(items.where((x) => x['tool'] == 'pipe').map((x) => x['calc']['iso']),
        orderedEquals(['300', '500']));
  });
}
