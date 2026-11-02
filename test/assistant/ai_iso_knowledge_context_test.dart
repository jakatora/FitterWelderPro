import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cut_list_app/assistant/assistant_ai_client.dart';
import 'package:cut_list_app/database/db.dart';
import 'package:cut_list_app/screens/iso_notebook_screen.dart';
import 'package:cut_list_app/services/ai_chat_service.dart';
import '../support/test_database.dart';
import 'ai_chat_execution_test.dart' show mount;
import 'global_pipe_slope_flow_test.dart' show say, settle;

void main() {
  useTestDatabase();
  setUp(() async => (await AppDatabase.get()).delete('iso_drawings'));
  for (final scenario in ['same', 'edited', 'no_iso']) {
    testWidgets(
        'knowledge receives current numeric ISO and discards stale answer: $scenario',
        (t) async {
      final pending = Completer<ChatMessage>();
      var calls = 0;
      await mount(t,
          interpret: (_) async => const AiCommandPlan('answer', [], ''),
          contextChatSender: (text, history, summary) {
            calls++;
            if (scenario == 'no_iso') {
              expect(summary, isNull);
            } else {
              expect(summary!.toJson().keys.toSet(), {
                'pipe_count',
                'computed_cut_count',
                'computed_cut_total_mm',
                'gap_mm'
              });
              expect(summary.pipeCount, 2);
              expect(summary.computedCutCount, 2);
              expect(
                  summary.computedCutTotalMm,
                  closeTo(
                      IsoNotebookController.active!.debugPipeCutsMm
                          .reduce((a, b) => a + b),
                      1e-9));
            }
            return pending.future;
          });
      if (scenario != 'no_iso') {
        await say(t, 'Narysuj rura metr w prawo kolano DN50 w górę rura metr');
        await settle(t);
        await flushTestDatabase(t);
      }
      await t.enterText(find.byKey(const Key('assistant-command')),
          'Pomóż mi zinterpretować ten wynik');
      await t.tap(find.byKey(const Key('assistant-go')));
      for (var i = 0; i < 8 && calls == 0; i++) {
        await t.pump(const Duration(milliseconds: 200));
      }
      expect(calls, 1);
      if (scenario == 'edited') {
        await t.runAsync(() => IsoNotebookController.active!.renameSketch(
            'Changed while answering',
            expectedRevision: IsoNotebookController.active!.revision));
        await t.pump(const Duration(milliseconds: 200));
      }
      pending.complete(ChatMessage(
          role: ChatRole.assistant,
          text: 'Fixture actual answer',
          kind: AiReplyKind.live));
      await settle(t);
      expect(find.text('Fixture actual answer'),
          scenario == 'edited' ? findsNothing : findsOneWidget);
      if (scenario == 'edited') {
        expect(find.textContaining('Rysunek zmienił się'), findsOneWidget);
      }
      expect(t.takeException(), isNull);
    });
  }
  for (final edit in [false, true]) {
    testWidgets('retry respects the original ISO revision edit=$edit',
        (t) async {
      var calls = 0;
      await mount(t,
          interpret: (_) async => const AiCommandPlan('answer', [], ''),
          contextChatSender: (_, __, summary) async {
            calls++;
            expect(summary, isNotNull);
            return ChatMessage(
                role: ChatRole.assistant,
                text: calls == 1 ? 'Fixture unavailable' : 'Fixture answer',
                kind: calls == 1 ? AiReplyKind.unavailable : AiReplyKind.live);
          });
      await say(t, 'Narysuj rura metr w prawo kolano DN50 w górę rura metr');
      await settle(t);
      await flushTestDatabase(t);
      await say(t, 'Pomóż mi zinterpretować ten wynik');
      expect(calls, 1);
      if (edit) {
        await t.runAsync(() => IsoNotebookController.active!.renameSketch(
            'Changed after failure',
            expectedRevision: IsoNotebookController.active!.revision));
        await settle(t);
      }
      final retry = find.byKey(const Key('assistant-persistent-retry'));
      await t.ensureVisible(retry);
      await t.tap(retry);
      await settle(t);
      expect(calls, edit ? 1 : 2);
      if (edit) {
        expect(find.textContaining('Dane kalkulatora lub rysunku zmieniły się'),
            findsWidgets);
      } else {
        expect(find.text('Fixture answer'), findsOneWidget);
      }
      expect(t.takeException(), isNull);
    });
  }
}
