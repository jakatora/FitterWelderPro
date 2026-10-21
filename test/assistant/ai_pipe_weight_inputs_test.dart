import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cut_list_app/assistant/assistant_ai_client.dart';
import 'package:cut_list_app/assistant/core/assistant_panel_controller.dart';
import 'package:cut_list_app/assistant/core/tool_bridge.dart';
import 'package:cut_list_app/screens/fitter_tools_screen.dart';
import '../support/test_database.dart';
import 'ai_chat_execution_test.dart' show mount;
import 'global_pipe_slope_flow_test.dart' show say, settle;

const fields = <String, Object?>{
  'od_mm': 60.3,
  'wall_mm': 3.91,
  'length_mm': 1000,
  'quantity': 1,
  'material': 'ss316'
};
const plan = AiCommandPlan(
    'execute',
    [
      AiCommandStep('pipe.weight',
          'Oblicz masę rury OD 60,3 mm ścianka 3,91 mm długość 6 m 316L ilość 5')
    ],
    '');
Finder field(String label) => find.byWidgetPredicate(
    (w) => w is TextField && w.decoration?.labelText == label);
Future<void> prepare(WidgetTester t,
    Future<AiCommandPlan> Function(Map<String, Object?>) interpret) async {
  await mount(t,
      home: const FitterToolsScreen(initialTab: 5), interpret: interpret);
  expect(await ToolBridge.instance.current!.apply(fields), isEmpty);
  await settle(t);
}

Future<void> edit(WidgetTester t, String label, String value) async {
  AssistantPanelController.instance.setExpanded(false);
  await settle(t);
  await t.enterText(field(label), value);
  await settle(t);
  AssistantPanelController.instance.setExpanded(true);
  await settle(t);
}

void main() {
  useTestDatabase();
  testWidgets(
      'pipe weight publishes actual manual inputs only on its selected tab',
      (t) async {
    await prepare(t, (_) async => plan);
    await edit(t, 'Długość (mm)', '6000');
    await edit(t, 'Ilość szt.', '3');
    expect(ToolBridge.instance.inputFields('pipe_weight'),
        {...fields, 'length_mm': 6000, 'quantity': 3});
    final tab = ToolBridge.instance.current! as TabbedToolHandle;
    expect(tab.selectTool('slope_cut'), isTrue);
    await settle(t);
    expect(ToolBridge.instance.inputFields('pipe_weight'), isNull);
    expect(ToolBridge.instance.inputFields('slope_cut'),
        {'od_mm': null, 'slope_pct': null});
    expect(tab.selectTool('pipe_weight'), isTrue);
    await settle(t);
    expect(ToolBridge.instance.inputFields('pipe_weight')!['quantity'], 3);
  });
  testWidgets(
      'AI sees real pipe inputs and changes only requested quantity through the native calculator',
      (t) async {
    var calls = 0;
    await prepare(t, (r) async {
      calls++;
      expect((r['context'] as Map)['active_tool'], 'pipe_weight');
      expect((r['context'] as Map)['inputs'],
          {...fields, 'length_mm': 6000, 'quantity': 3});
      return plan;
    });
    await edit(t, 'Długość (mm)', '6000');
    await edit(t, 'Ilość szt.', '3');
    await say(t,
        'Zmień mi tylko liczbę sztuk na pięć, resztę zostaw jak na ekranie.');
    expect(calls, 1);
    expect(ToolBridge.instance.inputFields('pipe_weight'),
        {...fields, 'length_mm': 6000, 'quantity': 5});
    final total = math.pi * (60.3 - 3.91) * 3.91 * 8000 / 1000000 * 6 * 5;
    expect(find.text('${total.toStringAsFixed(2)} kg'), findsOneWidget);
  });
  testWidgets(
      'empty or malformed pipe inputs are never exported as invented defaults',
      (t) async {
    await prepare(t, (_) async => plan);
    await edit(t, 'Długość (mm)', '');
    await edit(t, 'Ilość szt.', '');
    await edit(t, 'Gr. ścianki t (mm)', '.');
    expect(
        t.widget<TextField>(field('Gr. ścianki t (mm)')).controller!.text, '.');
    expect(ToolBridge.instance.inputFields('pipe_weight'),
        {...fields, 'wall_mm': null, 'length_mm': null, 'quantity': null});
  });
  testWidgets(
      'delayed pipe proposal cannot overwrite a newer manual wall value',
      (t) async {
    final pending = Completer<AiCommandPlan>();
    var calls = 0;
    await prepare(t, (_) {
      calls++;
      return pending.future;
    });
    await t.enterText(find.byKey(const Key('assistant-command')),
        'Zmień mi tylko liczbę sztuk na pięć, resztę zostaw jak na ekranie.');
    await t.tap(find.byKey(const Key('assistant-go')));
    await t.pump(const Duration(milliseconds: 200));
    expect(calls, 1);
    await edit(t, 'Gr. ścianki t (mm)', '2');
    pending.complete(plan);
    await settle(t);
    expect(ToolBridge.instance.inputFields('pipe_weight'),
        {...fields, 'wall_mm': 2});
    expect(find.textContaining('dane zmieniły się'), findsOneWidget);
  });
}
