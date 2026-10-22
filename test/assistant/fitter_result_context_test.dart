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
import 'package:cut_list_app/domain/fitter/rolling_offset.dart';
import 'package:cut_list_app/domain/fitter/pipe_slope.dart';
import 'package:cut_list_app/screens/rolling_offset_screen.dart';
import 'package:cut_list_app/screens/pipe_slope_screen.dart';
import 'package:cut_list_app/services/ai_chat_service.dart';
import 'package:cut_list_app/services/premium_service.dart';
import '../support/test_account.dart';
import '../support/test_database.dart';
import 'ai_chat_execution_test.dart' show mount, FixtureSpeech;
import 'global_pipe_slope_flow_test.dart' show settle;
import 'rolling_offset_current_test.dart' show input;

const rollingFields = {
  'rise_mm': 300,
  'spread_mm': 400,
  'angle_deg': 45,
  'dn': 100,
  'gap_mm': 3
};
Finder vertical(Type screen) => find
    .descendant(
        of: find.byType(screen),
        matching: find.byWidgetPredicate(
            (w) => w is Scrollable && w.axisDirection == AxisDirection.down))
    .first;
Finder output(String prefix) => find.byWidgetPredicate((w) =>
    w is TextField &&
    w.readOnly &&
    (w.decoration?.labelText ?? '').startsWith(prefix));
Future<void> pumpSteps(WidgetTester t) async {
  for (var i = 0; i < 8; i++) {
    await t.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  useTestDatabase();
  useGuestAccount();
  testWidgets(
      'rolling native readout matches displayed geometry and native CUT without recalculation',
      (t) async {
    await mount(t, interpret: (_) async => throw StateError('No AI expected'));
    expect(await ToolBridge.instance.current!.apply(rollingFields), isEmpty);
    await settle(t);
    final c = CalculatorQuestionContext.capture(ToolBridge.instance)!;
    final r = c.results!;
    final native = rollingOffset(riseMm: 300, spreadMm: 400, angleDeg: 45)!;
    final cut = rollingOffsetCut(
        travelMm: native.travelMm, angleDeg: 45, dn: 100, gapMm: 3)!;
    expect(r['precision'], 'displayed');
    expect(r['true_offset_mm'], 500);
    expect(r['travel_mm'], double.parse(native.travelMm.toStringAsFixed(1)));
    expect(r['cut_mm'], double.parse(cut.cutMm.toStringAsFixed(1)));
    expect(r['takeout_mm'], cut.takeout.mm);
    expect(r['cut_elbows_overlap'], false);
    expect(() => r['cut_mm'] = 0, throwsUnsupportedError);
    AssistantPanelController.instance.setExpanded(false);
    await settle(t);
    await t.scrollUntilVisible(output('Travel'), 300,
        scrollable: vertical(RollingOffsetScreen));
    expect(t.widget<TextField>(output('Travel')).controller!.text,
        r['travel_mm'].toString());
  });
  testWidgets(
      'manual edit clears rolling result readback until explicit calculation',
      (t) async {
    await mount(t, interpret: (_) async => throw StateError('No AI expected'));
    expect(await ToolBridge.instance.current!.apply(rollingFields), isEmpty);
    await settle(t);
    AssistantPanelController.instance.setExpanded(false);
    await settle(t);
    await t.enterText(input('Rise'), '350');
    await settle(t);
    final c = CalculatorQuestionContext.capture(ToolBridge.instance)!;
    expect(c.inputs['rise_mm'], 350);
    expect(
        c.results!.entries
            .where((e) => e.key != 'precision')
            .every((e) => e.value == null),
        true);
  });
  testWidgets(
      'manual rolling overlap remains an explicit native warning and negative CUT',
      (t) async {
    await mount(t, interpret: (_) async => throw StateError('No AI expected'));
    expect(await ToolBridge.instance.current!.apply(rollingFields), isEmpty);
    await settle(t);
    AssistantPanelController.instance.setExpanded(false);
    await settle(t);
    await t.enterText(input('Rise'), '10');
    await t.enterText(input('Spread'), '10');
    await t.scrollUntilVisible(find.text('OBLICZ'), 250,
        scrollable: vertical(RollingOffsetScreen));
    await t.ensureVisible(find.text('OBLICZ'));
    await t.pumpAndSettle();
    await t.tap(find.text('OBLICZ'));
    await settle(t);
    final r = CalculatorQuestionContext.capture(ToolBridge.instance)!.results!;
    expect(r['cut_elbows_overlap'], true);
    expect(r['cut_mm'], lessThan(0));
  });
  for (final mode in ['length_to_rise', 'rise_to_length', 'slope_from_lr']) {
    testWidgets(
        'pipe slope native displayed results respect selected mode $mode',
        (t) async {
      await mount(t,
          home: const PipeSlopeScreen(),
          interpret: (_) async => throw StateError('No AI expected'));
      final data = mode == 'length_to_rise'
          ? {'length_mm': 6000, 'slope_pct': 1}
          : mode == 'rise_to_length'
              ? {'rise_mm': 50, 'slope_pct': 1.5}
              : {'length_mm': 1234, 'rise_mm': 15};
      expect(await ToolBridge.instance.current!.apply({'mode': mode, ...data}),
          isEmpty);
      await settle(t);
      final c = CalculatorQuestionContext.capture(ToolBridge.instance)!;
      final native = mode == 'length_to_rise'
          ? slopeRiseFromLength(lengthMm: 6000, slopePct: 1)!
          : mode == 'rise_to_length'
              ? slopeLengthFromRise(riseMm: 50, slopePct: 1.5)!
              : slopeFromLengthAndRise(lengthMm: 1234, riseMm: 15)!;
      expect(c.inputs['mode'], mode);
      expect(c.results!['precision'], 'displayed');
      expect(c.results!['angle_deg'],
          double.parse(native.angleDeg.toStringAsFixed(3)));
      expect(c.results!['mm_per_m'],
          double.parse(native.mmPerM.toStringAsFixed(1)));
      if (mode == 'length_to_rise') {
        expect(c.results!['rise_mm'],
            double.parse(native.riseMm.toStringAsFixed(1)));
      }
      if (mode == 'rise_to_length') {
        expect(c.results!['length_mm'],
            double.parse(native.lengthMm.toStringAsFixed(1)));
      }
      if (mode == 'slope_from_lr') {
        expect(c.results!['slope_pct'],
            double.parse(native.slopePct.toStringAsFixed(3)));
      }
    });
  }
  for (final tool in ['rolling_offset', 'pipe_slope']) {
    testWidgets(
        'actual simulated voice sends $tool native results through knowledge HTTP',
        (t) async {
      final speech = FixtureSpeech();
      Map<String, dynamic>? sent;
      var calls = 0;
      PremiumService.instance.resetForTest();
      await http.runWithClient(() async {
        await mount(t,
            home: tool == 'pipe_slope'
                ? const PipeSlopeScreen()
                : const RollingOffsetScreen(),
            speech: speech,
            interpret: (_) async => const AiCommandPlan('answer', [], ''));
        expect(
            await ToolBridge.instance.current!.apply(tool == 'pipe_slope'
                ? {'mode': 'length_to_rise', 'length_mm': 6000, 'slope_pct': 1}
                : rollingFields),
            isEmpty);
        await settle(t);
        final before =
            Map<String, Object?>.of(ToolBridge.instance.inputFields(tool)!);
        await t.tap(find.byKey(const Key('assistant-mic')));
        await settle(t);
        speech.emit('Pomóż mi zinterpretować ten wynik');
        await settle(t);
        expect(calls, 1);
        final context = sent!['calculator_context'] as Map;
        expect(context['tool_id'], tool);
        expect((context['results'] as Map)['precision'], 'displayed');
        expect(ToolBridge.instance.inputFields(tool), before);
        expect(find.text('Fixture fitter explanation'), findsOneWidget);
      },
          () => MockClient((r) async {
                calls++;
                expectSync(r.url.path, '/api/fitter/ai/chat');
                sent = jsonDecode(r.body) as Map<String, dynamic>;
                File('build/assistant-$tool-result-widget-wire.json')
                    .writeAsStringSync(r.body);
                return http.Response(
                    jsonEncode({
                      'text': 'Fixture fitter explanation',
                      'citations': [],
                      'calculator_context_used': true
                    }),
                    200,
                    headers: {
                      'content-type': 'application/json; charset=utf-8'
                    });
              }));
    });
  }
  testWidgets(
      'calculation with identical inputs invalidates an answer that started before any result existed',
      (t) async {
    final deferred = Completer<ChatMessage>();
    var calls = 0;
    await mount(t,
        interpret: (_) async => const AiCommandPlan('answer', [], ''),
        chatSender: (_, __) {
          calls++;
          return deferred.future;
        });
    AssistantPanelController.instance.setExpanded(false);
    await settle(t);
    await t.enterText(input('Rise'), '300');
    await t.enterText(input('Spread'), '400');
    await settle(t);
    final before = CalculatorQuestionContext.capture(ToolBridge.instance)!;
    expect(before.results!['travel_mm'], isNull);
    AssistantPanelController.instance.setExpanded(true);
    await settle(t);
    await t.enterText(find.byKey(const Key('assistant-command')),
        'Pomóż mi zinterpretować ten wynik');
    await t.tap(find.byKey(const Key('assistant-go')));
    for (var i = 0; i < 12 && calls == 0; i++) {
      await t.pump(const Duration(milliseconds: 100));
    }
    expect(calls, 1);
    AssistantPanelController.instance.setExpanded(false);
    await pumpSteps(t);
    await t.scrollUntilVisible(find.text('OBLICZ'), 250,
        scrollable: vertical(RollingOffsetScreen));
    await t.ensureVisible(find.text('OBLICZ'));
    await pumpSteps(t);
    await t.tap(find.text('OBLICZ'));
    await pumpSteps(t);
    final after = CalculatorQuestionContext.capture(ToolBridge.instance)!;
    expect(after.inputs, before.inputs);
    expect(after.results!['travel_mm'], 707.1);
    AssistantPanelController.instance.setExpanded(true);
    await pumpSteps(t);
    deferred.complete(ChatMessage(
        role: ChatRole.assistant,
        text: 'Stale missing-result answer',
        kind: AiReplyKind.live));
    await settle(t);
    expect(find.text('Stale missing-result answer'), findsNothing);
    expect(
        find.textContaining('Kalkulator lub dane zmieniły się'), findsWidgets);
  });
}
