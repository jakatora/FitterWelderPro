import 'package:flutter_test/flutter_test.dart';
import 'package:cut_list_app/assistant/assistant_ai_client.dart';
import 'package:cut_list_app/services/ai_chat_service.dart';
import 'package:cut_list_app/database/db.dart';
import 'package:cut_list_app/screens/iso_notebook_screen.dart';
import '../support/test_database.dart';
import 'ai_chat_execution_test.dart' show mount;
import 'global_pipe_slope_flow_test.dart' show say, settle;

void main() {
  useTestDatabase();
  setUp(() async => (await AppDatabase.get()).delete('iso_drawings'));
  for (final intervening in [
    'none',
    'manual',
    'other_sheet',
    'knowledge',
    'expired'
  ]) {
    testWidgets('bare pronoun uses only current unambiguous gap: $intervening',
        (t) async {
      var clock = DateTime(2026, 10, 22, 12), answers = 0, interpretations = 0;
      await mount(t,
          now: () => clock,
          interpret: (request) async {
            if (request['text'] == 'Opowiedz mi o pracy przy rurociągach') {
              return const AiCommandPlan('answer', [], '');
            }
            interpretations++;
            expect((request['context'] as Map)['inputs'], {'gap_mm': 3.0});
            expect(request.toString(), isNot(contains('iso_gap_sheet_id')));
            return const AiCommandPlan('execute',
                [AiCommandStep('iso.gap', 'Ustaw szczelinę ISO na 2 mm')], '');
          },
          chatSender: (_, __) async {
            answers++;
            return ChatMessage(
                role: ChatRole.assistant,
                text: 'Rozmawiamy teraz o montażu rurociągów.',
                kind: AiReplyKind.live);
          });
      await say(t, 'Ustaw szczelinę ISO na 3 mm');
      await settle(t);
      await flushTestDatabase(t);
      final c = IsoNotebookController.active!;
      final originalId = c.sketchId;
      if (intervening == 'manual') {
        await t.runAsync(
            () => c.renameSketch('Manual edit', expectedRevision: c.revision));
      } else if (intervening == 'other_sheet') {
        await t.runAsync(c.startNew);
        await settle(t);
        IsoGapResult? changed;
        final update = c
            .setRootGap(3, expectedRevision: c.revision)
            .then((value) => changed = value);
        for (var i = 0; i < 8 && changed == null; i++) {
          await settle(t);
          await flushTestDatabase(t);
        }
        expect(changed, IsoGapResult.saved);
        await update;
        expect(c.sketchId, isNot(originalId));
      } else if (intervening == 'knowledge') {
        await say(t, 'Opowiedz mi o pracy przy rurociągach');
        expect(answers, 1);
      } else if (intervening == 'expired') {
        clock = clock.add(const Duration(minutes: 3));
      }
      await say(t, 'Zmniejsz ją o 1 mm');
      await settle(t);
      expect(interpretations, 1);
      expect(c.rootGapMm, intervening == 'none' ? 2 : 3);
      if (intervening != 'none') {
        expect(find.textContaining('Podaj pełne polecenie z nazwą pola'),
            findsOneWidget);
      }
      expect(t.takeException(), isNull);
    });
  }
}
