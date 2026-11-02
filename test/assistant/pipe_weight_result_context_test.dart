import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cut_list_app/assistant/calculator_question_context.dart';
import 'package:cut_list_app/assistant/core/tool_bridge.dart';
import 'package:cut_list_app/screens/fitter_tools_screen.dart';
import '../support/test_database.dart';
import '../support/test_account.dart';
import 'ai_chat_execution_test.dart' show mount;
import 'global_pipe_slope_flow_test.dart' show settle;

const values = {'od_mm': 60.3, 'wall_mm': 3.91, 'material': 'ss316'};
void main() {
  useTestDatabase();
  useGuestAccount();
  for (final full in [true, false]) {
    testWidgets('pipe weight captures actual rounded native results full=$full',
        (t) async {
      await mount(t,
          home: const FitterToolsScreen(initialTab: 5),
          interpret: (_) async => throw StateError('No AI command expected'));
      final bridge = ToolBridge.instance;
      expect(
          await bridge.current!.apply({
            ...values,
            if (full) ...{'length_mm': 1000, 'quantity': 2}
          }),
          isEmpty);
      await settle(t);
      final context = CalculatorQuestionContext.capture(bridge)!;
      expect(context.toJson(), {
        'tool_id': 'pipe_weight',
        'inputs': {
          ...values,
          'length_mm': full ? 1000.0 : null,
          'quantity': full ? 2.0 : null
        },
        'results': {
          'precision': 'displayed',
          'kg_per_m': 5.541,
          'kg_per_piece': full ? 5.541 : null,
          'kg_total': full ? 11.08 : null
        }
      });
      expect(find.text('5.541 kg/m'), findsOneWidget);
      if (full) {
        expect(find.text('11.08 kg'), findsOneWidget);
        File('build/pipe-weight-native-context.json')
            .writeAsStringSync(jsonEncode(context.toJson()));
      }
      final tabs = bridge.current as TabbedToolHandle;
      tabs.selectTool('elbow_cut');
      await settle(t);
      expect(bridge.calculatorResult('pipe_weight'), isNull);
      expect(CalculatorQuestionContext.capture(bridge), isNull);
      expect(t.takeException(), isNull);
    });
  }
  testWidgets('invalid visible pipe weight clears previous native readback',
      (t) async {
    await mount(t,
        home: const FitterToolsScreen(initialTab: 5),
        interpret: (_) async => throw StateError('No AI command expected'));
    final bridge = ToolBridge.instance;
    expect(
        await bridge.current!
            .apply({...values, 'length_mm': 1000, 'quantity': 2}),
        isEmpty);
    await settle(t);
    final wall = find.byWidgetPredicate((w) =>
        w is TextField && w.decoration?.labelText == 'Gr. ścianki t (mm)');
    await t.ensureVisible(wall);
    await t.enterText(wall, '40');
    await settle(t);
    final context = CalculatorQuestionContext.capture(bridge)!;
    expect(context.inputs['wall_mm'], 40);
    expect(context.results, {
      'precision': 'displayed',
      'kg_per_m': null,
      'kg_per_piece': null,
      'kg_total': null
    });
    expect(find.text('11.08 kg'), findsNothing);
    expect(t.takeException(), isNull);
  });
}
