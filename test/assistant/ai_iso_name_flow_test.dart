import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:cut_list_app/assistant/assistant_ai_client.dart';
import 'package:cut_list_app/database/db.dart';
import 'package:cut_list_app/database/iso_drawing_dao.dart';
import '../support/test_database.dart';
import 'ai_chat_execution_test.dart' show mount;
import 'global_pipe_slope_flow_test.dart' show say, settle;

void main() {
  useTestDatabase();
  setUp(() async => (await AppDatabase.get()).delete('iso_drawings'));
  for (final correct in [true, false]) {
    testWidgets(
        'AI names the actual sheet only with the exact user title: $correct',
        (t) async {
      var calls = 0;
      await mount(t, interpret: (request) async {
        calls++;
        expect(
            (request['capabilities'] as List)
                .cast<Map>()
                .any((c) => c['id'] == 'iso.name'),
            isTrue);
        return AiCommandPlan(
            'execute',
            [
              AiCommandStep('iso.name',
                  'Nazwij rysunek ${correct ? 'Łódź CW-123' : 'Lodz CW-123'}')
            ],
            '');
      });
      await say(t, 'Narysuj rura metr w prawo');
      await settle(t);
      await flushTestDatabase(t);
      final before = await t.runAsync(() => IsoDrawingDao().latest());
      expect(calls, 0);
      await say(t, 'Chciałbym nazwać ten rysunek „Łódź CW-123”');
      await settle(t);
      await flushTestDatabase(t);
      expect(calls, 1);
      final after = await t.runAsync(() => IsoDrawingDao().latest());
      expect(after!.id, before!.id);
      expect(after.name, correct ? 'Łódź CW-123' : before.name);
      expect((jsonDecode(after.json) as Map)['items'],
          (jsonDecode(before.json) as Map)['items']);
      expect(t.takeException(), isNull);
    });
  }
}
