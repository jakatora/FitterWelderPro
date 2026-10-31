import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:cut_list_app/assistant/assistant_ai_client.dart';
import 'package:cut_list_app/services/ai_chat_service.dart';
import 'package:cut_list_app/database/db.dart';
import 'package:cut_list_app/database/iso_drawing_dao.dart';
import '../support/test_database.dart';
import 'ai_chat_execution_test.dart' show mount;
import 'global_pipe_slope_flow_test.dart' show say, settle;

void main() {
  useTestDatabase();
  setUp(() async => (await AppDatabase.get()).delete('iso_drawings'));
  for (final scenario in [
    (true, 'Chciałbym nazwać ten rysunek „Łódź CW-123”'),
    (false, 'Chciałbym nazwać ten rysunek „Łódź CW-123”'),
    (true, 'Czy możesz nazwać ten rysunek „Łódź CW-123”?'),
    (false, 'Czy możesz nazwać ten rysunek „Łódź CW-123”?'),
    (true, 'Could you please name this drawing “Łódź CW-123”?'),
    (false, 'Czy możesz nazwać projekt „Łódź CW-123”?'),
    (false, 'Czy mogę nazwać rysunek „Łódź CW-123”?'),
  ]) {
    final (correct, source) = scenario;
    testWidgets(
        'AI names the actual sheet only with the exact user title: $correct $source',
        (t) async {
      var calls = 0;
      var answers = 0;
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
                  'Nazwij rysunek ${source.contains('projekt') || source.contains('mogę') || correct ? 'Łódź CW-123' : 'Lodz CW-123'}')
            ],
            '');
      }, chatSender: (text, history) async {
        answers++;
        return ChatMessage(role: ChatRole.assistant, kind: AiReplyKind.live, text: 'Możesz nadać nazwę rysunkowi.');
      });
      await say(t, 'Narysuj rura metr w prawo');
      await settle(t);
      await flushTestDatabase(t);
      final before = await t.runAsync(() => IsoDrawingDao().latest());
      expect(calls, 0);
      await say(t, source);
      await settle(t);
      await flushTestDatabase(t);
      expect(calls, source.contains('Czy mogę') ? 0 : 1);
      expect(answers, source.contains('Czy mogę') ? 1 : 0);
      final after = await t.runAsync(() => IsoDrawingDao().latest());
      expect(after!.id, before!.id);
      expect(after.name, correct ? 'Łódź CW-123' : before.name);
      expect((jsonDecode(after.json) as Map)['items'],
          (jsonDecode(before.json) as Map)['items']);
      expect(t.takeException(), isNull);
    });
  }
}
