import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cut_list_app/assistant/assistant_ai_client.dart';
import 'package:cut_list_app/database/db.dart';
import 'package:cut_list_app/database/weld_param_dao.dart';
import 'package:cut_list_app/services/legal_consent.dart';
import '../support/test_database.dart';
import 'ai_chat_execution_test.dart' show mount;
import 'global_pipe_slope_flow_test.dart' show say, settle;

const start =
    'Zachowaj próbę TIG nierdzewka 60 amperów bez spoiwa. Następnie pokaż moje parametry TIG.';
const beginPlan = AiCommandPlan(
    'execute',
    [
      AiCommandStep('legacy.save', 'Zapisz TIG nierdzewka 60 A bez drutu'),
      AiCommandStep('params.saved', 'Pokaż moje parametry TIG'),
    ],
    '');

void main() {
  useTestDatabase();
  setUp(() async => (await AppDatabase.get()).delete('weld_params'));
  testWidgets(
      'natural reply fills only pending field and preserves ordered plan until actual save',
      (t) async {
    var calls = 0;
    final fixture = jsonDecode(
        File('test/fixtures/assistant_ai_actual_haiku_pending_reply.json')
            .readAsStringSync()) as Map;
    await mount(t, interpret: (r) async {
      calls++;
      if (calls == 1) return beginPlan;
      expect((r['capabilities'] as List).length, 1);
      final c = r['context'] as Map;
      expect(c['pending_reply'],
          {'skill_id': 'legacy.save', 'slot': 'wall_mm', 'choices': []});
      expect(c['pending_question'], 'Jaka grubość ścianki w mm?');
      expect(r['text'], fixture['text']);
      return AiCommandPlan.fromJson(fixture['proposal'], {'legacy.save'});
    });
    await say(t, start);
    expect(find.text('Jaka grubość ścianki w mm?'), findsOneWidget);
    await say(t, 'Połowa czterech milimetrów');
    expect(calls, 2);
    expect(await t.runAsync(() => WeldParamDao().listAll()), isEmpty);
    final save = find.byKey(const Key('assistant-local-save'));
    expect(save, findsOneWidget);
    await t.ensureVisible(save);
    await settle(t);
    await t.tap(save);
    await settle(t);
    final row = (await t.runAsync(() => WeldParamDao().listAll()))!.single;
    expect(row.wallThicknessMm, 2);
    expect(row.amps, 60);
    expect(find.textContaining('Zapisane parametry'), findsOneWidget);
    expect(calls, 2);
  });
  testWidgets(
      'AI outage never falls back to a wrong literal number in a natural pending reply',
      (t) async {
    var calls = 0;
    await mount(t, interpret: (_) async {
      if (++calls == 1) return beginPlan;
      throw const AssistantAiUnavailable(503);
    });
    await say(t, start);
    await say(t, 'Połowa czterech milimetrów');
    expect(calls, 2);
    expect(find.byKey(const Key('assistant-local-save')), findsNothing);
    expect(await t.runAsync(() => WeldParamDao().listAll()), isEmpty);
    await say(t, '2 mm');
    expect(calls, 2);
    expect(find.byKey(const Key('assistant-local-save')), findsOneWidget);
  });
  testWidgets('wrong AI reply target preserves the original native question',
      (t) async {
    var calls = 0;
    await mount(t, interpret: (_) async {
      if (++calls == 1) return beginPlan;
      return const AiCommandPlan(
          'reply', [AiCommandStep('params.saved', '2 mm')], '');
    });
    await say(t, start);
    await say(t, 'Połowa czterech milimetrów');
    expect(calls, 2);
    expect(find.byKey(const Key('assistant-local-save')), findsNothing);
    await say(t, '2 mm');
    expect(calls, 2);
    expect(find.byKey(const Key('assistant-local-save')), findsOneWidget);
  });
  testWidgets(
      'revoked consent blocks natural interpretation but a direct value still works offline',
      (t) async {
    var calls = 0;
    await mount(t, interpret: (_) async {
      calls++;
      return beginPlan;
    });
    await say(t, start);
    await t.runAsync(LegalConsent.instance.clear);
    await say(t, 'Połowa czterech milimetrów');
    expect(calls, 1);
    expect(find.byKey(const Key('assistant-local-save')), findsNothing);
    await say(t, '2 mm');
    expect(calls, 1);
    expect(find.byKey(const Key('assistant-local-save')), findsOneWidget);
  });
}
