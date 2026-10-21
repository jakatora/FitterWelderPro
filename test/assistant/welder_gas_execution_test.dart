import 'package:flutter/material.dart' show Key;
import 'dart:async';
import 'dart:math' as math;
import 'package:flutter_test/flutter_test.dart';
import 'package:cut_list_app/assistant/assistant_ai_client.dart';
import 'package:cut_list_app/assistant/core/tool_bridge.dart';
import 'package:cut_list_app/assistant/core/skill.dart';
import 'package:cut_list_app/domain/welding/welder_calculator_input.dart';
import 'package:cut_list_app/services/weld_timer_service.dart';
import 'package:cut_list_app/screens/welder_tools_screen.dart';
import '../support/test_database.dart';
import 'ai_chat_execution_test.dart' show mount, FixtureSpeech;
import 'global_pipe_slope_flow_test.dart' show say, settle;
import 'support/assistant_test_support.dart';

const gas =
    'Oblicz zużycie gazu spoiny 10 spawanie 2 min palnik 10 L/min preflow 5 s postflow 10 s purgeflow 8 L/min purgetime 1 min butla 50 L napełnienie 200 bar rezerwa 10 bar';
const purge =
    'Oblicz czas formowania OD 60,3 mm ścianka 2 mm długość 1 m przepływ 10 L/min start 210000 ppm cel 20 ppm';
const gasFields = <String, Object?>{
  'tab': 'gas',
  'welds': 10,
  'weld_minutes': 2,
  'torch_lpm': 10,
  'pre_flow_s': 5,
  'post_flow_s': 10,
  'purge_lpm': 8,
  'purge_minutes': 1,
  'water_l': 50,
  'fill_bar': 200,
  'reserve_bar': 10
};
const purgeFields = <String, Object?>{
  'tab': 'purge',
  'od_mm': 60.3,
  'wall_mm': 2,
  'length_mm': 1000,
  'flow_lpm': 10,
  'initial_ppm': 210000,
  'target_ppm': 20
};
void main() {
  useTestDatabase();
  test(
      'gas and purge models reuse actual domain arithmetic and reject bad payloads',
      () {
    final g = GasCalculatorInput.fromFields(gasFields);
    expect(g.consumption.totalL, 305);
    expect(g.cylinderL, 9500);
    expect(g.bottles, closeTo(305 / 9500, 1e-12));
    final p = PurgeCalculatorInput.fromFields(purgeFields);
    final volume = math.pi * math.pow((60.3 - 4) / 2, 2) * 1000 / 1e6;
    expect(p.estimate.volumeL, closeTo(volume, 1e-12));
    expect(p.estimate.timeSec,
        closeTo(volume / 10 * 60 * math.log(210000 / 20), 1e-10));
    for (final bad in [
      {'purge_minutes': 0},
      {'reserve_bar': 200},
      {'torch_lpm': double.nan},
      {'current_bar': 10},
      {'action': 'clear'},
      {'welds': 1e308}
    ]) {
      expect(() => GasCalculatorInput.fromFields({...gasFields, ...bad}),
          throwsFormatException);
    }
    for (final bad in [
      {'wall_mm': 31},
      {'target_ppm': 0},
      {'target_ppm': 210000},
      {'initial_ppm': double.infinity},
      {'length_mm': 1e308},
      {'timer': 'start'}
    ]) {
      expect(() => PurgeCalculatorInput.fromFields({...purgeFields, ...bad}),
          throwsFormatException);
    }
  });
  test('required target and wrong units ask without inventing values',
      () async {
    final h = BrainHarness();
    addTearDown(h.timer.dispose);
    var reply = await h.say(
        'Oblicz czas formowania OD 60,3 mm ścianka 2 mm długość 1 m przepływ 10 L/min');
    expect((reply.result as AskResult).slot, 'target_ppm');
    reply = await h.say('20 ppm');
    expect(reply.result, isA<AnswerResult>());
    expect((reply.result as AnswerResult).show!.fields, purgeFields);
    reply = await h
        .say('Oblicz zużycie gazu spoiny 5 kg spawanie 2 min palnik 10 L/min');
    expect((reply.result as AskResult).slot, 'welds');
  });
  testWidgets(
      'native chat gas command fills the real calculator without remote AI',
      (t) async {
    await mount(t,
        interpret: (_) async =>
            throw StateError('Native command must remain offline'));
    await say(t, gas);
    expect(find.byType(WelderToolsScreen), findsOneWidget);
    expect(ToolBridge.instance.inputFields('welder_calculators'),
        {...gasFields, 'current_bar': null});
    expect(find.text('305 L'), findsOneWidget);
    expect(find.text('9500 L'), findsOneWidget);
  });
  testWidgets(
      'purge command changes the real tab and leaves the timer stopped; bad input is atomic',
      (t) async {
    await mount(t,
        home: const WelderToolsScreen(),
        interpret: (_) async => throw StateError('Offline command'));
    final running = WeldTimerService.instance.running;
    expect(running, isFalse);
    await say(t, purge);
    expect(ToolBridge.instance.inputFields('welder_calculators'), purgeFields);
    final volume = math.pi * math.pow((60.3 - 4) / 2, 2) * 1000 / 1e6;
    expect(find.text('${volume.toStringAsFixed(3)} L'), findsOneWidget);
    expect(WeldTimerService.instance.running, running);
    expect(
        await ToolBridge.instance.current!
            .apply({...gasFields, 'torch_lpm': -1}),
        isNotEmpty);
    await settle(t);
    expect(ToolBridge.instance.inputFields('welder_calculators'), purgeFields);
  });
  testWidgets(
      'AI current-form command reaches native gas result and preserves other fields',
      (t) async {
    var calls = 0;
    await mount(t, home: const WelderToolsScreen(), interpret: (request) async {
      calls++;
      expect((request['context'] as Map)['inputs'],
          {...gasFields, 'current_bar': null});
      return AiCommandPlan(
          'execute',
          [
            AiCommandStep(
                'gas.consumption', gas.replaceFirst('palnik 10', 'palnik 12'))
          ],
          '');
    });
    expect(await ToolBridge.instance.current!.apply(gasFields), isEmpty);
    await settle(t);
    await say(t,
        'Zwiększ mi tylko przepływ na palniku do dwunastu litrów na minutę, resztę zostaw jak na ekranie');
    expect(calls, 1);
    expect(ToolBridge.instance.inputFields('welder_calculators'),
        {...gasFields, 'torch_lpm': 12, 'current_bar': null});
    expect(find.text('350 L'), findsOneWidget);
  });
  test(
      'ambiguous quantities and incomplete purge pairs retain a typed question',
      () async {
    final h = BrainHarness();
    addTearDown(h.timer.dispose);
    var reply = await h.say(
        'Oblicz zużycie gazu spoiny 10 spawanie 2 min palnik 10 L/min purgeflow 8 L/min');
    expect((reply.result as AskResult).slot, 'purge_minutes');
    reply = await h.say('1 min albo 2 min');
    expect(reply.result, isA<AskResult>());
    reply = await h.say('1 min');
    expect((reply.result as AnswerResult).show!.fields,
        {...gasFields, 'reserve_bar': 0});
    reply = await h.say(
        'Oblicz zużycie gazu spoiny 5 bananów spawanie 2 min palnik 10 L/min');
    expect((reply.result as AskResult).slot, 'welds');
  });
  testWidgets(
      'speech callback executes the actual native gas calculation offline',
      (t) async {
    final speech = FixtureSpeech();
    await mount(t,
        speech: speech,
        interpret: (_) async => throw StateError('Native speech is offline'));
    await t.tap(find.byKey(const Key('assistant-mic')));
    await t.pump();
    speech.emit(gas);
    await settle(t);
    expect(find.text('305 L'), findsOneWidget);
    expect(
        ToolBridge.instance.inputFields('welder_calculators')!['tab'], 'gas');
  });
  testWidgets(
      'AI answers the pending weld duration without replacing already validated gas inputs',
      (t) async {
    var calls = 0;
    await mount(t, interpret: (r) async {
      calls++;
      expect(((r['context'] as Map)['pending_reply'] as Map)['slot'],
          'weld_minutes');
      expect((r['capabilities'] as List), hasLength(1));
      return const AiCommandPlan(
          'reply', [AiCommandStep('gas.consumption', '2 min')], '');
    });
    await say(t, 'Oblicz zużycie gazu spoiny 10 palnik 10 L/min');
    await say(t, 'Połowa czterech minut');
    expect(calls, 1);
    expect(find.text('225 L'), findsOneWidget);
    expect(ToolBridge.instance.inputFields('welder_calculators')!['welds'], 10);
  });
  testWidgets(
      'late gas AI response cannot switch back after the user selects purge on the same handle',
      (t) async {
    final pending = Completer<AiCommandPlan>();
    await mount(t,
        home: const WelderToolsScreen(), interpret: (_) => pending.future);
    expect(await ToolBridge.instance.current!.apply(gasFields), isEmpty);
    await settle(t);
    final handle = ToolBridge.instance.current;
    await t.enterText(find.byKey(const Key('assistant-command')),
        'Zwiększ mi tylko przepływ na palniku, resztę zostaw jak na ekranie');
    await t.tap(find.byKey(const Key('assistant-go')));
    await t.pump(const Duration(milliseconds: 200));
    final switching = handle!.apply(purgeFields);
    await settle(t);
    expect(await switching, isEmpty);
    expect(ToolBridge.instance.current, same(handle));
    pending.complete(const AiCommandPlan(
        'execute', [AiCommandStep('gas.consumption', gas)], ''));
    await settle(t);
    expect(ToolBridge.instance.inputFields('welder_calculators'), purgeFields);
    expect(find.textContaining('dane zmieniły się'), findsOneWidget);
  });
  testWidgets(
      'finite scientific values arrive as native decimal text rather than silently taking a preset',
      (t) async {
    await mount(t,
        home: const WelderToolsScreen(),
        interpret: (_) async => throw StateError('Native input'));
    expect(
        await ToolBridge.instance.current!
            .apply({...gasFields, 'water_l': 1e30}),
        isEmpty);
    await settle(t);
    expect(ToolBridge.instance.inputFields('welder_calculators')!['water_l'],
        1e30);
    expect(find.text('${(1e30 * 190).toStringAsFixed(0)} L'), findsOneWidget);
  });
}
