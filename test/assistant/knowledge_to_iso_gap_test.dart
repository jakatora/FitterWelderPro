import 'dart:convert';
import 'package:cut_list_app/assistant/assistant_ai_client.dart';
import 'package:cut_list_app/database/db.dart';
import 'package:cut_list_app/database/iso_drawing_dao.dart';
import 'package:cut_list_app/screens/iso_notebook_screen.dart';
import 'package:cut_list_app/services/ai_chat_service.dart';
import 'package:flutter_test/flutter_test.dart';
import '../support/test_account.dart';
import '../support/test_database.dart';
import 'ai_chat_execution_test.dart' show mount;
import 'global_pipe_slope_flow_test.dart' show say, settle;

void main() {
  useGuestAccount();
  useTestDatabase();
  setUp(() async => (await AppDatabase.get()).delete('iso_drawings'));
  testWidgets('AI discussion then relative ISO edit persists CUT and supports undo', (t) async {
    var chats = 0, interpretations = 0;
    await mount(t, interpret: (_) async {
      interpretations++;
      return const AiCommandPlan('execute', [AiCommandStep('iso.gap', 'Ustaw szczelinę ISO na 2 mm')], '');
    }, chatSender: (_, __) async {
      chats++;
      return ChatMessage(role: ChatRole.assistant, text: 'Szczelina wpływa na długość cięcia.', kind: AiReplyKind.live);
    });
    await say(t, 'Narysuj rura metr w prawo kolano DN50 w górę rura metr');
    final controller = IsoNotebookController.active!;
    for (var i = 0; i < 12 && controller.isBusy; i++) { await settle(t); }
    await say(t, 'Ustaw szczelinę ISO na 3 mm');
    await flushTestDatabase(t);
    final before = await t.runAsync(() => IsoDrawingDao().latest());
    final geometry = (jsonDecode(before!.json) as Map)['items'];
    final cuts = List.of(controller.debugPipeCutsMm);
    await say(t, 'Wyjaśnij wpływ szczeliny na długość cięcia');
    expect(chats, 1);
    expect(controller.rootGapMm, 3);
    await say(t, 'A zmniejsz szczelinę w ISO o 1 mm');
    expect(chats, 1);
    expect(interpretations, 1);
    expect(controller.rootGapMm, 2);
    expect(controller.debugPipeCutsMm, [for (final cut in cuts) closeTo(cut + 1, 1e-9)]);
    await settle(t);
    await flushTestDatabase(t);
    final after = await t.runAsync(() => IsoDrawingDao().latest());
    expect(after!.id, before.id);
    expect((jsonDecode(after.json) as Map)['items'], geometry);
    expect((jsonDecode(after.json) as Map)['gapMm'], 2);
    await say(t, 'cofnij');
    expect(controller.rootGapMm, 3);
    expect(controller.debugPipeCutsMm, cuts);
    expect(chats, 1);
    expect(t.takeException(), isNull);
  });
}
