import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:cut_list_app/assistant/assistant_ai_client.dart';
import 'package:cut_list_app/database/db.dart';
import 'package:cut_list_app/database/iso_drawing_dao.dart';
import 'package:cut_list_app/screens/iso_notebook_screen.dart';
import '../support/test_database.dart';
import 'ai_chat_execution_test.dart' show mount;
import 'global_pipe_slope_flow_test.dart' show say, settle;

void main() {
  useTestDatabase();
  setUp(() async => (await AppDatabase.get()).delete('iso_drawings'));
  for (final correct in [true, false]) {
    testWidgets(
        'AI proposed dimension edits actual pipe only when original target agrees: $correct',
        (t) async {
      var calls = 0;
      await mount(t, interpret: (request) async {
        calls++;
        final capability = (request['capabilities'] as List)
            .cast<Map>()
            .singleWhere((c) => c['id'] == 'iso.dimension');
        expect(capability['tool_id'], 'iso_notebook');
        return AiCommandPlan(
            'execute',
            [
              AiCommandStep('iso.dimension',
                  'Zmień wymiar ISO rury numer ${correct ? 2 : 1} na 500 mm')
            ],
            '');
      });
      await say(t, 'Narysuj rura metr w prawo kolano w górę rura dwa metry');
      final controller = IsoNotebookController.active!;
      for (var i = 0; i < 12 && controller.isBusy; i++) {
        await settle(t);
      }
      expect(calls, 0);
      await say(t, 'Ten drugi odcinek powinien mieć pół metra');
      expect(calls, 1);
      await settle(t);
      await flushTestDatabase(t);
      final stored = await t.runAsync(() => IsoDrawingDao().latest());
      final pipes = ((jsonDecode(stored!.json) as Map)['items'] as List)
          .where((e) => e['tool'] == 'pipe');
      expect(pipes.map((e) => e['calc']['iso']),
          correct ? ['1000', '500'] : ['1000', '2000']);
      expect(t.takeException(), isNull);
    });
  }
}
