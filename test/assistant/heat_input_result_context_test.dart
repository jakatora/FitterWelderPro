import 'package:cut_list_app/app_navigator.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:cut_list_app/assistant/assistant_ai_client.dart';
import 'package:cut_list_app/assistant/calculator_question_context.dart';
import 'package:cut_list_app/assistant/core/assistant_panel_controller.dart';
import 'package:cut_list_app/assistant/core/tool_bridge.dart';
import 'package:cut_list_app/domain/welding/heat_input.dart';
import 'package:cut_list_app/screens/heat_input_screen.dart';
import 'package:cut_list_app/services/ai_chat_service.dart';
import 'package:cut_list_app/services/premium_service.dart';
import '../support/test_account.dart';
import '../support/test_database.dart';
import 'ai_chat_execution_test.dart' show mount;
import 'global_pipe_slope_flow_test.dart' show say, settle;
import 'rolling_offset_current_test.dart' show input;

Future<void> pumpSteps(WidgetTester t) async {
  for (var i = 0; i < 8; i++) {
    await t.pump(const Duration(milliseconds: 100));
  }
}

Finder heatScroll() => find
    .descendant(
        of: find.byType(HeatInputScreen),
        matching: find.byWidgetPredicate(
            (w) => w is Scrollable && w.axisDirection == AxisDirection.down))
    .first;

const fields = {
  'process': 'GTAW',
  'standard': 'en1011',
  'volts': 24,
  'amps': 230,
  'travel_mm_min': 150
};
void main() {
  useTestDatabase();
  useGuestAccount();
  for (final scenario in ['default', 'override', 'asme']) {
    testWidgets(
        'native heat output has correct standard and efficiency provenance $scenario',
        (t) async {
      await mount(t,
          home: const HeatInputScreen(),
          interpret: (_) async => throw StateError('No AI needed'));
      final bridge = ToolBridge.instance;
      expect(
          await bridge.current!.apply({
            ...fields,
            if (scenario != 'default') 'efficiency': 0.7,
            if (scenario == 'asme') 'standard': 'asmeIx'
          }),
          isEmpty);
      await settle(t);
      final context = CalculatorQuestionContext.capture(bridge)!;
      final result = context.results!;
      final native = heatInputKJPerMm(
          volts: 24,
          amps: 230,
          travelMmPerMin: 150,
          standard: scenario == 'asme'
              ? HeatInputStandard.asmeIx
              : HeatInputStandard.en1011,
          efficiency: scenario == 'default' ? 0.6 : 0.7)!;
      expect(result['value_kj_per_mm'], closeTo(native, 1e-12));
      expect(result['display_value'],
          double.parse(HeatInputUnit.kjPerMm.format(native)));
      expect(result['display_unit'], 'kjPerMm');
      expect(
          result['efficiency_source'],
          scenario == 'default'
              ? 'process_default'
              : scenario == 'override'
                  ? 'explicit_override'
                  : 'not_used');
      expect(
          result['efficiency_used'],
          scenario == 'asme'
              ? isNull
              : scenario == 'default'
                  ? 0.6
                  : 0.7);
      expect(context.toJson().keys,
          unorderedEquals(['tool_id', 'inputs', 'results']));
      expect(() => context.results!['value_kj_per_mm'] = 0,
          throwsUnsupportedError);
      AssistantPanelController.instance.setExpanded(false);
      await settle(t);
      await t.scrollUntilVisible(
          find.text(HeatInputUnit.kjPerMm.format(native)), 300,
          scrollable: heatScroll());
      expect(find.text(HeatInputUnit.kjPerMm.format(native)), findsWidgets);
      expect(t.takeException(), isNull);
    });
  }
  testWidgets('invalid manual current is a missing native result, never zero',
      (t) async {
    await mount(t,
        home: const HeatInputScreen(),
        interpret: (_) async => throw StateError('No AI needed'));
    expect(await ToolBridge.instance.current!.apply(fields), isEmpty);
    await settle(t);
    AssistantPanelController.instance.setExpanded(false);
    await settle(t);
    await t.enterText(input('Prąd'), '');
    await settle(t);
    final context = CalculatorQuestionContext.capture(ToolBridge.instance)!;
    expect(context.inputs['amps'], isNull);
    expect(context.results!['value_kj_per_mm'], isNull);
    expect(context.results!['display_value'], isNull);
    expect(context.results!['efficiency_used'], isNull);
    expect(jsonEncode(context.toJson()), isNot(contains('NaN')));
  });
  testWidgets(
      'a display-unit change invalidates a deferred answer even with identical inputs',
      (t) async {
    final deferred = Completer<ChatMessage>();
    var calls = 0;
    await mount(t,
        home: const HeatInputScreen(),
        interpret: (_) async => const AiCommandPlan('answer', [], ''),
        chatSender: (_, __) {
          calls++;
          return deferred.future;
        });
    expect(await ToolBridge.instance.current!.apply(fields), isEmpty);
    await pumpSteps(t);
    final before = CalculatorQuestionContext.capture(ToolBridge.instance)!;
    await t.enterText(find.byKey(const Key('assistant-command')),
        'Pomóż mi zinterpretować ten wynik');
    await t.tap(find.byKey(const Key('assistant-go')));
    for (var i = 0; i < 12 && calls == 0; i++) {
      await t.pump(const Duration(milliseconds: 100));
    }
    expect(calls, 1);
    AssistantPanelController.instance.setExpanded(false);
    await pumpSteps(t);
    await t.scrollUntilVisible(find.text('J/in').first, 350,
        scrollable: heatScroll());
    await t.ensureVisible(find.text('J/in').first);
    await pumpSteps(t);
    await t.tap(find.text('J/in').first);
    await pumpSteps(t);
    final after = CalculatorQuestionContext.capture(ToolBridge.instance)!;
    expect(after.inputs, before.inputs);
    expect(after.results!['display_unit'], 'jPerIn');
    expect(
        after.results!['value_kj_per_mm'], before.results!['value_kj_per_mm']);
    AssistantPanelController.instance.setExpanded(true);
    await pumpSteps(t);
    deferred.complete(ChatMessage(
        role: ChatRole.assistant,
        text: 'Stale unit answer',
        kind: AiReplyKind.live));
    await pumpSteps(t);
    expect(find.text('Stale unit answer'), findsNothing);
    expect(
        find.textContaining('Kalkulator lub dane zmieniły się'), findsWidgets);
    expect(t.takeException(), isNull);
  });
  testWidgets(
      'actual heat result reaches the chat service without changing its form',
      (t) async {
    Map<String, dynamic>? sent;
    var calls = 0;
    PremiumService.instance.resetForTest();
    await http.runWithClient(() async {
      await mount(t,
          home: const HeatInputScreen(),
          interpret: (_) async => const AiCommandPlan('answer', [], ''));
      expect(await ToolBridge.instance.current!.apply(fields), isEmpty);
      await settle(t);
      final before = Map<String, Object?>.of(
          ToolBridge.instance.inputFields('heat_input')!);
      await say(t, 'Pomóż mi zinterpretować ten wynik');
      expect(calls, 1);
      final result = (sent!['calculator_context'] as Map)['results'] as Map;
      expect(result['value_kj_per_mm'], closeTo(1.3248, 1e-12));
      expect(result['display_value'], 1.32);
      expect(result['efficiency_source'], 'process_default');
      expect(ToolBridge.instance.inputFields('heat_input'), before);
      expect(find.text('Fixture native heat explanation'), findsOneWidget);
    },
        () => MockClient((r) async {
              calls++;
              expectSync(r.url.path, '/api/fitter/ai/chat');
              sent = jsonDecode(r.body) as Map<String, dynamic>;
              File('build/assistant-heat-result-widget-wire.json')
                  .writeAsStringSync(r.body);
              return http.Response(
                  jsonEncode({
                    'text': 'Fixture native heat explanation',
                    'citations': [],
                    'calculator_context_used': true
                  }),
                  200,
                  headers: {'content-type': 'application/json; charset=utf-8'});
            }));
  });
  testWidgets('popup hides both input and result ports until dismissed',
      (t) async {
    await mount(t,
        home: const HeatInputScreen(),
        interpret: (_) async => throw StateError('No AI expected'));
    expect(ToolBridge.instance.calculatorResult('heat_input'), isNotNull);
    unawaited(showDialog<void>(
        context: appNavigatorKey.currentState!.overlay!.context,
        builder: (context) => AlertDialog(
                content: const Text('Fixture private dialog'),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('Close fixture'))
                ])));
    await settle(t);
    expect(ToolBridge.instance.calculatorResult('heat_input'), isNull);
    expect(CalculatorQuestionContext.capture(ToolBridge.instance), isNull);
    await t.tap(find.text('Close fixture'));
    await settle(t);
    expect(ToolBridge.instance.calculatorResult('heat_input'), isNotNull);
  });
}
