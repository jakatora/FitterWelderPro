import 'package:cut_list_app/assistant/assistant_ai_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cut_list_app/database/db.dart';
import 'package:cut_list_app/database/iso_drawing_dao.dart';
import 'package:cut_list_app/screens/iso_notebook_screen.dart';
import '../support/test_database.dart';
import 'ai_chat_execution_test.dart' show mount;
import 'global_pipe_slope_flow_test.dart' show say, settle;

void main() {
  useTestDatabase();
  setUp(() async => (await AppDatabase.get()).delete('iso_drawings'));
  for (final scenario in [
    (true, 'Podsumuj rysunek ISO', 0),
    (false, 'Podsumuj rysunek ISO', 0),
    (true, 'Czy możesz podsumować aktualny rysunek ISO?', 0),
    (true, 'Could you please summarize the current ISO drawing?', 0),
    (true, 'Zrób zestawienie ile rur mam w aktualnym rysunku ISO', 1),
  ]) {
    final (measured, request, expectedCalls) = scenario;
    testWidgets(
        'summary reads current native CUT without changing sheet: $measured request: $request',
        (t) async {
      var calls = 0;
      await mount(t, interpret: (_) async {
        calls++;
        return const AiCommandPlan('execute',
            [AiCommandStep('iso.summary', 'Podsumuj rysunek ISO')], '');
      });
      await say(
          t,
          measured
              ? 'Narysuj rura metr w prawo kolano DN50 w górę rura metr'
              : 'Narysuj rura kolanko rura');
      final c = IsoNotebookController.active!;
      for (var i = 0; i < 12 && c.isBusy; i++) {
        await settle(t);
      }
      await settle(t);
      await flushTestDatabase(t);
      final before = await t.runAsync(() => IsoDrawingDao().latest());
      final revision = c.revision;
      final snapshot = c.summary!;
      expect(snapshot.pipeCount, 2);
      expect(snapshot.computedCutCount, measured ? 2 : 0);
      final expected = c.debugPipeCutsMm
          .where((v) => v.isFinite && v >= 0)
          .fold<double>(0, (a, b) => a + b);
      expect(snapshot.computedCutTotalMm, closeTo(expected, 1e-9));
      expect(calls, 0);
      await say(t, request);
      expect(calls, expectedCalls);
      expect(find.textContaining('Odcinki rur: 2'), findsOneWidget);
      expect(find.textContaining('ich suma: ${expected.toStringAsFixed(1)} mm'),
          findsOneWidget);
      expect(find.textContaining('bez obliczalnego CUT: ${measured ? 0 : 2}'),
          findsOneWidget);
      await flushTestDatabase(t);
      final after = await t.runAsync(() => IsoDrawingDao().latest());
      expect(after!.id, before!.id);
      expect(after.json, before.json);
      expect(c.revision, revision);
      expect(t.takeException(), isNull);
    });
  }
}
