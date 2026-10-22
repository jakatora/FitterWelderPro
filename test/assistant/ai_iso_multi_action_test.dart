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
  for (final scenario in ['correct', 'negated', 'cardinality', 'wrong_value']) {
    testWidgets(
        'one AI request edits ISO only from bound source clauses: $scenario',
        (t) async {
      var calls = 0;
      await mount(t, interpret: (_) async {
        calls++;
        return AiCommandPlan(
            'execute',
            [
              AiCommandStep('iso.gap',
                  'Ustaw szczelinę ISO na ${scenario == 'wrong_value' ? 4 : 3} mm'),
              AiCommandStep(
                  'iso.dimension', 'Zmień wymiar ISO rury numer 2 na 500 mm'),
            ],
            '');
      });
      await say(t, 'Narysuj rura metr w prawo kolano w górę rura dwa metry');
      final c = IsoNotebookController.active!;
      for (var i = 0; i < 12 && c.isBusy; i++) {
        await settle(t);
      }
      await say(
          t,
          scenario == 'negated'
              ? 'Ustaw szczelinę ISO na 3 mm i nie zmieniaj wymiaru ISO rury numer 2 na 500 mm'
              : 'Ustaw szczelinę ISO na 3 mm i zmień wymiar ISO rury numer 2 na 500 mm${scenario == 'cardinality' ? ' i otwórz czat' : ''}');
      await settle(t);
      await flushTestDatabase(t);
      expect(calls, scenario == 'negated' ? 0 : 1);
      expect(c.rootGapMm, scenario == 'correct' ? 3 : 0);
      final stored = await t.runAsync(() => IsoDrawingDao().latest());
      final pipes = ((jsonDecode(stored!.json) as Map)['items'] as List)
          .where((e) => e['tool'] == 'pipe');
      expect(pipes.map((e) => e['calc']['iso']),
          scenario == 'correct' ? ['1000', '500'] : ['1000', '2000']);
      if (scenario == 'correct') {
        await say(t, 'cofnij');
        await flushTestDatabase(t);
        final undone = await t.runAsync(() => IsoDrawingDao().latest());
        final undonePipes = ((jsonDecode(undone!.json) as Map)['items'] as List)
            .where((e) => e['tool'] == 'pipe');
        expect(undonePipes.map((e) => e['calc']['iso']), ['1000', '2000']);
        expect(c.rootGapMm, 3);
        await say(t, 'cofnij');
        expect(c.rootGapMm, 0);
        expect(calls, 1);
      }
      expect(t.takeException(), isNull);
    });
  }
}
