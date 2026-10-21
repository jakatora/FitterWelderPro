import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cut_list_app/assistant/assistant_ai_client.dart';
import 'package:cut_list_app/assistant/core/assistant_panel_controller.dart';
import 'package:cut_list_app/assistant/core/tool_bridge.dart';
import 'package:cut_list_app/screens/heat_input_screen.dart';
import '../support/test_database.dart';
import 'ai_chat_execution_test.dart' show mount;
import 'global_pipe_slope_flow_test.dart' show say, settle;
import 'rolling_offset_current_test.dart' show input;

const initial = {
  'process': 'GTAW',
  'standard': 'en1011',
  'volts': 22,
  'amps': 110,
  'travel_mm_min': 200,
  'efficiency': 0.7
};

void main() {
  useTestDatabase();
  testWidgets(
      'AI sees current manual heat inputs and native partial calculation preserves WPS efficiency',
      (t) async {
    var calls = 0;
    final fixture = jsonDecode(
        File('test/fixtures/assistant_ai_actual_haiku_heat_input.json')
            .readAsStringSync()) as Map;
    await mount(t, home: const HeatInputScreen(), interpret: (r) async {
      calls++;
      expect((r['context'] as Map)['inputs'],
          {...initial, 'volts': 24, 'travel_mm_min': 150});
      return AiCommandPlan.fromJson(fixture['proposal'], {'heat.input'});
    });
    final b = ToolBridge.instance;
    expect(await b.current!.apply(initial), isEmpty);
    await settle(t);
    AssistantPanelController.instance.setExpanded(false);
    await settle(t);
    await t.enterText(input('Napięcie'), '24');
    await t.enterText(input('Prędkość spawania'), '150');
    AssistantPanelController.instance.setExpanded(true);
    await settle(t);
    await say(t,
        'Pozostałe wartości zostaw jak w formularzu, potrzebuję tylko dwustu amperów i wyniku.');
    expect(calls, 1);
    expect(b.inputFields('heat_input'),
        {...initial, 'volts': 24, 'amps': 200, 'travel_mm_min': 150});
    expect(find.textContaining('1,34 kJ/mm'), findsWidgets);
  });
  testWidgets(
      'invalid manual current remains invalid and hidden preheat tab exposes no heat inputs',
      (t) async {
    await mount(t,
        home: const HeatInputScreen(),
        interpret: (_) async =>
            throw StateError('Exact native calculation stays offline'));
    final b = ToolBridge.instance;
    await b.current!.apply(initial);
    await settle(t);
    AssistantPanelController.instance.setExpanded(false);
    await settle(t);
    await t.enterText(input('Prąd'), '');
    AssistantPanelController.instance.setExpanded(true);
    await settle(t);
    await say(t, 'Oblicz energię liniową');
    expect(find.text('Podaj dodatnią wartość z jednostką.'), findsOneWidget);
    expect(b.inputFields('heat_input')!['amps'], isNull);
    AssistantPanelController.instance.setExpanded(false);
    await settle(t);
    await t.tap(find.text('Preheat / CE'));
    await settle(t);
    expect(b.inputFields('heat_input'), isEmpty);
  });
  testWidgets(
      'recalculate uses manual changes over history and process change resets old WPS efficiency',
      (t) async {
    await mount(t,
        home: const HeatInputScreen(),
        interpret: (_) async =>
            throw StateError('Native request must remain offline'));
    final b = ToolBridge.instance;
    await b.current!.apply(initial);
    await settle(t);
    await say(t, 'Oblicz energię liniową 200 A');
    expect(b.inputFields('heat_input')!['amps'], 200);
    AssistantPanelController.instance.setExpanded(false);
    await settle(t);
    await t.enterText(input('Napięcie'), '30');
    await t.enterText(input('Prędkość spawania'), '180');
    AssistantPanelController.instance.setExpanded(true);
    await settle(t);
    await say(t, 'Przelicz to');
    expect(b.inputFields('heat_input'),
        {...initial, 'volts': 30, 'amps': 200, 'travel_mm_min': 180});
    expect(find.textContaining('1,4 kJ/mm'), findsWidgets);
    await say(t, 'Oblicz energię liniową MMA');
    expect(b.inputFields('heat_input'), {
      'process': 'SMAW',
      'standard': 'en1011',
      'volts': 30,
      'amps': 200,
      'travel_mm_min': 180
    });
    expect(find.textContaining('1,6 kJ/mm'), findsWidgets);
  });
  testWidgets(
      'cooling command on visible heat form uses its explicit Q rather than form quantities',
      (t) async {
    await mount(t,
        home: const HeatInputScreen(),
        interpret: (_) async =>
            throw StateError('Native cooling request stays offline'));
    await ToolBridge.instance.current!.apply(initial);
    await settle(t);
    await say(
        t, 'Oblicz t8/5 Q 1 kJ/mm temperatura 100 C grubość 20 mm wypełnienie');
    expect(ToolBridge.instance.activeToolId, 'cooling_time');
    final q = t.widget<TextField>(input('Energia liniowa Q')).controller!.text;
    expect(double.parse(q.replaceAll(',', '.')), 1);
    expect(find.textContaining('5,98'), findsWidgets);
  });
}
