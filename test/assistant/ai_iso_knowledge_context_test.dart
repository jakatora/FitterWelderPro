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
}
