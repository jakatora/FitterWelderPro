import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:cut_list_app/assistant/assistant_ai_client.dart';
import 'package:cut_list_app/database/db.dart';
import 'package:cut_list_app/database/iso_drawing_dao.dart';
import 'package:cut_list_app/screens/iso_notebook_screen.dart';
import 'package:cut_list_app/services/ai_chat_service.dart';
import '../support/test_database.dart';
import 'ai_chat_execution_test.dart' show mount;
import 'global_pipe_slope_flow_test.dart' show say, settle;

void main() {
  useTestDatabase();
  setUp(() async => (await AppDatabase.get()).delete('iso_drawings'));
  for (final scenario in [
    (true, 'A czy możesz zmienić drugi odcinek na 500 mm?', 2, 1),
    (true, 'And could you please set the second pipe to 500 mm?', 2, 1),
    (false, 'A czy możesz zmienić drugi odcinek na 500 mm?', 1, 1),
    (true, 'Ten drugi odcinek powinien mieć pół metra', 2, 1),
    (false, 'Ten drugi odcinek powinien mieć pół metra', 1, 1),
    (true, 'Czy możesz zmienić drugi odcinek na 500 mm?', 2, 1),
    (true, 'Could you please set the second pipe to 500 mm?', 2, 1),
    (false, 'Nie zmieniaj drugiego odcinka na 500 mm', 2, 0),
    (false, 'Jak zmienić drugi odcinek na 500 mm?', 2, 0),
    (false, 'Czy mogę zmienić drugi odcinek na 500 mm?', 2, 0),
  ]) {
    final (correct, source, proposedOrdinal, expectedCalls) = scenario;
    testWidgets(
        'AI proposed dimension edits actual pipe only when original target agrees: $correct $source',
        (t) async {
      var calls = 0;
      var answers = 0;
      await mount(t, chatSender: (text, history) async {
        answers++;
        return ChatMessage(role: ChatRole.assistant,
            text: 'Wyjaśnienie zmiany wymiaru bez wykonania operacji.',
            kind: AiReplyKind.live);
      }, interpret: (request) async {
        calls++;
        final capability = (request['capabilities'] as List)
            .cast<Map>()
            .singleWhere((c) => c['id'] == 'iso.dimension');
        expect(capability['tool_id'], 'iso_notebook');
        return AiCommandPlan(
            'execute',
            [
              AiCommandStep('iso.dimension',
                  'Zmień wymiar ISO rury numer $proposedOrdinal na 500 mm')
            ],
            '');
      });
      await say(t, 'Narysuj rura metr w prawo kolano w górę rura dwa metry');
      final controller = IsoNotebookController.active!;
      for (var i = 0; i < 12 && controller.isBusy; i++) {
        await settle(t);
      }
      expect(calls, 0);
      final afterDiscussion = source.startsWith('A ') || source.startsWith('And ');
      if (afterDiscussion) {
        await say(t, 'Wyjaśnij zmianę wymiaru rury w ISO');
        expect(answers, 1);
      }
      await say(t, source);
      expect(calls, expectedCalls);
      expect(answers, afterDiscussion || source.startsWith('Jak ') || source.startsWith('Czy mogę ') ? 1 : 0);
      await settle(t);
      await flushTestDatabase(t);
      final stored = await t.runAsync(() => IsoDrawingDao().latest());
      final pipes = ((jsonDecode(stored!.json) as Map)['items'] as List)
          .where((e) => e['tool'] == 'pipe');
      expect(pipes.map((e) => e['calc']['iso']),
          correct ? ['1000', '500'] : ['1000', '2000']);
      if (afterDiscussion && correct) {
        await say(t, 'cofnij');
        await flushTestDatabase(t);
        final undone = await t.runAsync(() => IsoDrawingDao().latest());
        final originalPipes = ((jsonDecode(undone!.json) as Map)['items'] as List)
            .where((e) => e['tool'] == 'pipe');
        expect(originalPipes.map((e) => e['calc']['iso']), ['1000', '2000']);
        expect(answers, 1);
      }
      expect(t.takeException(), isNull);
    });
  }
}
