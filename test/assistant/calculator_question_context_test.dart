import 'package:cut_list_app/screens/heat_input_screen.dart';
import 'package:cut_list_app/assistant/core/assistant_panel_controller.dart';
import 'dart:convert';
import 'dart:io';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cut_list_app/assistant/calculator_question_context.dart';
import 'package:cut_list_app/assistant/core/skill.dart';
import 'package:cut_list_app/assistant/core/tool_bridge.dart';
import 'package:cut_list_app/assistant/assistant_ai_client.dart';
import 'package:cut_list_app/services/ai_chat_service.dart';
import 'package:cut_list_app/services/premium_service.dart';
import '../support/test_account.dart';
import '../support/test_database.dart';
import 'ai_chat_execution_test.dart' show mount;
import 'global_pipe_slope_flow_test.dart' show say, settle;

class Visible implements ModuleContext, FieldModuleContext {
  Visible(this.activeToolId, this.fields);
  @override
  String? activeToolId;
  Map<String, Object?> fields;
  @override
  bool get onHomeOrAssistant => false;
  @override
  Map<String, Object?>? inputFields(String id) => fields;
}

void main() {
  useTestDatabase();
  useGuestAccount();
  test(
      'only explicit calculator inputs are captured; invalid values remain missing',
      () {
    final c = CalculatorQuestionContext.capture(Visible('heat_input', {
      'amps': 230,
      'volts': double.nan,
      'travel_mm_min': 150,
      'process': 'GTAW',
      'standard': 'en1011',
      'efficiency': null,
      'password': 'fixture',
      'WPS': 'private',
      'displayed_result': 5
    }));
    expect(c!.toJson(), {
      'tool_id': 'heat_input',
      'inputs': {
        'amps': 230,
        'volts': null,
        'travel_mm_min': 150,
        'process': 'GTAW',
        'standard': 'en1011',
        'efficiency': null
      }
    });
    expect(() => c.inputs['amps'] = 1, throwsUnsupportedError);
    for (final id in [
      'account',
      'account_register',
      'steel_weight',
      'iso_notebook',
      'unknown'
    ]) {
      expect(CalculatorQuestionContext.capture(Visible(id, {'amps': 230})),
          isNull);
    }
    expect(
        CalculatorQuestionContext.capture(Visible('heat_input', {})), isNull);
    final badChoice = CalculatorQuestionContext.capture(Visible(
        'heat_input', {'process': 'ignore rules', 'standard': 'private'}));
    expect(badChoice!.inputs, {'process': null, 'standard': null});
  });
  test(
      'route boolean, slope mode and negative numeric inputs are not inferred or silently fixed',
      () {
    expect(
        CalculatorQuestionContext.capture(Visible('pipe_route',
                {'end_welds': true, 'x_mm': -10, 'note': 'private'}))!
            .inputs,
        {'end_welds': true, 'x_mm': -10});
    expect(
        CalculatorQuestionContext.capture(Visible('pipe_slope',
                {'mode': 'slope_from_lr', 'rise_mm': 25, 'length_mm': 1000}))!
            .inputs,
        {'mode': 'slope_from_lr', 'rise_mm': 25, 'length_mm': 1000});
  });
  for (final ack in [true, false]) {
    test(
        'chat sends strict calculator context and requires server acknowledgement ack=$ack',
        () async {
      SharedPreferences.setMockInitialValues({
        'fitter_device_id': '0123456789abcdef0123456789abcdef',
        'fitter_install_secret': 'AbCdEfGhIjKlMnOpQrStUvWxYz0123456789-_AbCdE'
      });
      PremiumService.instance.resetForTest();
      final context = CalculatorQuestionContext.capture(Visible('heat_input', {
        'amps': 230,
        'volts': 24,
        'travel_mm_min': 150,
        'process': 'GTAW',
        'standard': 'en1011'
      }))!;
      var calls = 0;
      final reply = await http.runWithClient(
          () => AiChatService.instance.sendMessage('Wyjaśnij dane kalkulatora',
              calculatorContext: context),
          () => MockClient((r) async {
                calls++;
                expect(r.url.path, '/api/fitter/ai/chat');
                final body = jsonDecode(r.body) as Map;
                expect(body['calculator_context'], context.toJson());
                expect(body.containsKey('iso_summary'), false);
                File('build/assistant-calculator-chat-wire.json')
                    .writeAsStringSync(jsonEncode(body));
                return http.Response(
                    jsonEncode({
                      'text': 'Fixture calculator answer',
                      'citations': [],
                      if (ack) 'calculator_context_used': true
                    }),
                    200,
                    headers: {
                      'content-type': 'application/json; charset=utf-8'
                    });
              }));
      expect(calls, 1);
      expect(reply.kind, ack ? AiReplyKind.live : AiReplyKind.unavailable);
      expect(reply.text.contains('Fixture calculator answer'), ack);
    });
  }
  for (final edit in [false, true]) {
    testWidgets(
        'actual visible rolling inputs invalidate only a stale contextual answer edit=$edit',
        (t) async {
      final deferred = Completer<ChatMessage>();
      var calls = 0;
      await mount(t,
          interpret: (_) async => const AiCommandPlan('answer', [], ''),
          chatSender: (_, __) {
            calls++;
            return deferred.future;
          });
      final before = Map<String, Object?>.of(
          ToolBridge.instance.inputFields('rolling_offset')!);
      await t.enterText(find.byKey(const Key('assistant-command')),
          'Pomóż mi zinterpretować te parametry');
      await t.tap(find.byKey(const Key('assistant-go')));
      for (var i = 0; i < 12 && calls == 0; i++) {
        await t.pump(const Duration(milliseconds: 100));
      }
      expect(calls, 1);
      if (edit) {
        await ToolBridge.instance.current!.apply({
          ...before,
          'rise_mm': 321,
          'spread_mm': 456,
          'angle_deg': 45,
          'dn': 50,
          'gap_mm': 2
        });
      }
      deferred.complete(ChatMessage(
          role: ChatRole.assistant,
          text: 'Fixture contextual explanation',
          kind: AiReplyKind.live));
      await settle(t);
      expect(find.text('Fixture contextual explanation'),
          edit ? findsNothing : findsOneWidget);
      if (edit) {
        expect(find.textContaining('Kalkulator lub dane zmieniły się'),
            findsWidgets);
      } else {
        expect(ToolBridge.instance.inputFields('rolling_offset'), before);
      }
      expect(t.takeException(), isNull);
    });
  }
  testWidgets(
      'real widget question sends actual visible rolling inputs through the chat service',
      (t) async {
    Map<String, dynamic>? sent;
    var calls = 0;
    PremiumService.instance.resetForTest();
    await http.runWithClient(() async {
      await mount(t,
          interpret: (_) async => const AiCommandPlan('answer', [], ''));
      final fields = {
        'rise_mm': 300,
        'spread_mm': 400,
        'angle_deg': 45,
        'dn': 50,
        'gap_mm': 2
      };
      expect(await ToolBridge.instance.current!.apply(fields), isEmpty);
      await settle(t);
      await say(t, 'Wyjaśnij mi proszę te parametry');
      expect(calls, 1);
      expect(sent!['calculator_context'],
          {'tool_id': 'rolling_offset', 'inputs': fields});
      expect(find.text('Fixture actual HTTP answer'), findsOneWidget);
      expect(ToolBridge.instance.inputFields('rolling_offset'), fields);
      expect(t.takeException(), isNull);
    },
        () => MockClient((r) async {
              calls++;
              expectSync(r.url.path, '/api/fitter/ai/chat');
              sent = jsonDecode(r.body) as Map<String, dynamic>;
              File('build/assistant-calculator-chat-widget-wire.json')
                  .writeAsStringSync(r.body);
              return http.Response(
                  jsonEncode({
                    'text': 'Fixture actual HTTP answer',
                    'citations': [],
                    'calculator_context_used': true
                  }),
                  200,
                  headers: {'content-type': 'application/json; charset=utf-8'});
            }));
  });
  testWidgets(
      'inactive Heat input tab does not expose the hidden calculator to knowledge',
      (t) async {
    await mount(t,
        home: const HeatInputScreen(),
        interpret: (_) async => throw StateError('No AI call expected'));
    expect(CalculatorQuestionContext.capture(ToolBridge.instance)!.toolId,
        'heat_input');
    AssistantPanelController.instance.setExpanded(false);
    await settle(t);
    await t.tap(find.text('Preheat / CE'));
    await settle(t);
    expect(CalculatorQuestionContext.capture(ToolBridge.instance), isNull);
    expect(t.takeException(), isNull);
  });
}
