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
  testWidgets('natural bend answer fills only the pending spatial plane',
      (t) async {
    var calls = 0;
    await mount(t, interpret: (r) async {
      calls++;
      expect(
          ((r['context'] as Map)['pending_reply'] as Map)['slot'], 'iso_bend');
      expect(r['capabilities'] as List, hasLength(1));
      return const AiCommandPlan(
          'reply', [AiCommandStep('iso.draw', 'up')], '');
    });
    await say(
        t, 'Narysuj rura metr w prawo kolano 45 stopni DN50 rura dwa metry');
    expect(calls, 0);
    expect(IsoNotebookController.active, isNull);
    await say(t, 'Chcę, żeby trasa skręciła pionowo do góry');
    expect(calls, 1);
    final c = IsoNotebookController.active!;
    for (var i = 0; i < 10 && c.isBusy; i++) {
      await settle(t);
    }
    expect(c.debugPipeAxisTags, hasLength(2));
    expect(c.debugPipeAxisTags.last, '3D');
    await t.pump(const Duration(milliseconds: 600));
    await flushTestDatabase(t);
    final saved = await t.runAsync(() => IsoDrawingDao().latest());
    final items = (jsonDecode(saved!.json) as Map)['items'] as List;
    expect(items.singleWhere((x) => x['tool'] == 'elbow45')['dn'], 50);
    expect(items.where((x) => x['tool'] == 'pipe').map((x) => x['calc']['iso']),
        orderedEquals(['1000', '2000']));
  });
  testWidgets('natural branch answer preserves the tee and pending pipe length',
      (t) async {
    var calls = 0;
    await mount(t, interpret: (r) async {
      calls++;
      expect(((r['context'] as Map)['pending_reply'] as Map)['slot'],
          'iso_branch');
      return const AiCommandPlan(
          'reply', [AiCommandStep('iso.draw', 'up')], '');
    });
    await say(t, 'Narysuj rura metr w prawo trójnik DN50 na DN25 rura 500 mm');
    final c = IsoNotebookController.active!;
    await say(t, 'Od trójnika rura 200 mm');
    expect(calls, 0);
    expect(c.debugPipeAxisTags, hasLength(2));
    await say(t, 'Chcę, żeby odgałęzienie poszło pionowo do góry');
    expect(calls, 1);
    for (var i = 0; i < 10 && c.isBusy; i++) {
      await settle(t);
    }
    expect(c.debugPipeAxisTags, hasLength(3));
    await t.pump(const Duration(milliseconds: 600));
    await flushTestDatabase(t);
    final saved = await t.runAsync(() => IsoDrawingDao().latest());
    final items = (jsonDecode(saved!.json) as Map)['items'] as List;
    expect(items.singleWhere((x) => x['tool'] == 'tee')['dnOut'], 25);
    expect(items.where((x) => x['tool'] == 'pipe').map((x) => x['calc']['iso']),
        orderedEquals(['1000', '500', '200']));
  });
}
