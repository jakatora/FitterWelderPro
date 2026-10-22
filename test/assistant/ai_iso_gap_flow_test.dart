import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:cut_list_app/assistant/assistant_ai_client.dart';
import 'package:cut_list_app/assistant/core/tool_bridge.dart';
import 'package:cut_list_app/database/db.dart';
import 'package:cut_list_app/database/iso_drawing_dao.dart';
import 'package:cut_list_app/screens/iso_notebook_screen.dart';
import '../support/test_database.dart';
import 'ai_chat_execution_test.dart' show mount;
import 'global_pipe_slope_flow_test.dart' show say, settle;

void main() {
  useTestDatabase();
  setUp(() async => (await AppDatabase.get()).delete('iso_drawings'));
  testWidgets('invalid explicit ISO gap never changes the visible calculator',
      (t) async {
    var calls = 0;
    await mount(t, interpret: (_) async {
      calls++;
      throw StateError('must stay native');
    });
    final before = Map.of(ToolBridge.instance.inputFields('rolling_offset')!);
    await say(t, 'Ustaw szczelinę ISO na 11 mm');
    expect(calls, 0);
    expect(IsoNotebookController.active, isNull);
    expect(ToolBridge.instance.inputFields('rolling_offset'), before);
    expect(find.textContaining('Podaj jedną szczelinę ISO od 0 do 10 mm'),
        findsOneWidget);
  });
  for (final scenario in [
    (true, false),
    (false, false),
    (true, true),
    (false, true),
  ]) {
    final (correct, polite) = scenario;
    testWidgets(
        'relative ISO gap uses native form and CUT engine: $correct polite: $polite',
        (t) async {
      var calls = 0;
      await mount(t, interpret: (request) async {
        calls++;
        expect((request['context'] as Map)['inputs'], {'gap_mm': 3.0});
        return AiCommandPlan(
            'execute',
            [
              AiCommandStep(
                  'iso.gap', 'Ustaw szczelinę ISO na ${correct ? 2 : 1} mm')
            ],
            '');
      });
      await say(t, 'Narysuj rura metr w prawo kolano DN50 w górę rura metr');
      final c = IsoNotebookController.active!;
      for (var i = 0; i < 12 && c.isBusy; i++) {
        await settle(t);
      }
      await settle(t);
      await flushTestDatabase(t);
      final cuts = List.of(c.debugPipeCutsMm);
      final before = await t.runAsync(() => IsoDrawingDao().latest());
      final geometry = (jsonDecode(before!.json) as Map)['items'];
      await say(t, 'Ustaw szczelinę ISO na 3 mm');
      expect(calls, 0);
      expect(c.rootGapMm, 3);
      expect(
          c.debugPipeCutsMm, [for (final cut in cuts) closeTo(cut - 3, 1e-9)]);
      expect(ToolBridge.instance.inputFields('iso_notebook'), {'gap_mm': 3.0});
      await say(
          t,
          polite
              ? 'Czy możesz zmniejszyć szczelinę w ISO o 1 mm'
              : 'Zmniejsz szczelinę w ISO o 1 mm');
      expect(calls, 1);
      expect(c.rootGapMm, correct ? 2 : 3);
      await settle(t);
      await flushTestDatabase(t);
      final after = await t.runAsync(() => IsoDrawingDao().latest());
      expect(after!.id, before.id);
      expect((jsonDecode(after.json) as Map)['items'], geometry);
      expect((jsonDecode(after.json) as Map)['gapMm'], correct ? 2 : 3);
      await say(t, 'cofnij');
      expect(c.rootGapMm, correct ? 3 : 0);
      expect(c.debugPipeAxisTags, hasLength(2));
      expect(t.takeException(), isNull);
    });
  }
  testWidgets(
      'gap-only sheet is persisted before drawing and preserved when starting another sheet',
      (t) async {
    await mount(t, interpret: (_) async => throw StateError('native only'));
    await say(t, 'Ustaw szczelinę ISO na 3 mm');
    await settle(t);
    await flushTestDatabase(t);
    expect(IsoNotebookController.active, isNotNull);
    final c = IsoNotebookController.active!;
    final saved = await t.runAsync(() => IsoDrawingDao().latest());
    expect(saved, isNotNull);
    expect((jsonDecode(saved!.json) as Map)['gapMm'], 3);
    expect((jsonDecode(saved.json) as Map)['items'], isEmpty);
    await t.runAsync(c.startNew);
    await settle(t);
    expect(c.rootGapMm, 0);
    expect((await t.runAsync(() => IsoDrawingDao().listAll()))!.single.id,
        saved.id);
  });
  testWidgets(
      'failed gap write is reported separately from the on-screen change',
      (t) async {
    await mount(t, interpret: (_) async => throw StateError('native only'));
    await say(t, 'Narysuj rura metr w prawo');
    await settle(t);
    await flushTestDatabase(t);
    await t.runAsync(() async => (await AppDatabase.get()).execute(
        "CREATE TRIGGER fail_gap BEFORE UPDATE ON iso_drawings BEGIN SELECT RAISE(FAIL, 'gap write failure'); END"));
    try {
      await say(t, 'Ustaw szczelinę ISO na 3 mm');
      expect(IsoNotebookController.active!.rootGapMm, 3);
      final stored = await t.runAsync(() => IsoDrawingDao().latest());
      expect((jsonDecode(stored!.json) as Map)['gapMm'], isNull);
      expect(
          find.textContaining(
              'Szczelina zmieniła się na ekranie, ale zapis rysunku nie powiódł się'),
          findsOneWidget);
      expect(find.textContaining('Szczelina spoiny w szkicu: 3.0 mm'),
          findsNothing);
    } finally {
      await t.runAsync(() async =>
          (await AppDatabase.get()).execute('DROP TRIGGER fail_gap'));
    }
  });
}
