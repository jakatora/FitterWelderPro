import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cut_list_app/main.dart' as app;
import 'package:cut_list_app/config/backend_config.dart';
import 'package:cut_list_app/screens/consent_screen.dart';
import 'package:cut_list_app/screens/ai_chat_screen.dart';
import 'package:cut_list_app/screens/heat_input_screen.dart';
import 'package:cut_list_app/services/premium_service.dart';
import 'package:cut_list_app/assistant/core/tool_bridge.dart';
import 'package:cut_list_app/assistant/core/calculator_result_readback.dart';
import 'live_assistant_test.dart' show ObservedClient, waitFor;

Future<void> command(WidgetTester t, String text) async {
  final input = find.byKey(const Key('assistant-command'));
  final send = find.byKey(const Key('assistant-go'));
  await waitFor(
      t,
      () =>
          input.evaluate().isNotEmpty &&
          t.widget<TextField>(input).enabled == true &&
          t.widget<IconButton>(send).onPressed != null);
  await t.tap(input);
  await t.pump();
  await t.enterText(input, text);
  expect(t.widget<TextField>(input).controller!.text, text);
  await t.tap(send);
}

void main() {
  if (!const bool.fromEnvironment('FWP_LIVE_AI_QA')) {
    throw StateError('Explicit live QA opt-in required; never skip');
  }
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
      'fresh assistant consent enables real AI navigation and native calculator actions',
      (t) async {
    final report = <String, dynamic>{
      'scope':
          'real AI navigation, native calculator and local clarification; no microphone',
      'maxAiRequests': 1
    };
    binding.reportData = report;
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getKeys(), isEmpty,
        reason: 'Fresh disposable installation only');
    const id = String.fromEnvironment('FWP_QA_DEVICE_ID');
    const secret = String.fromEnvironment('FWP_QA_INSTALL_SECRET');
    expect(RegExp(r'^[a-f0-9]{32}$').hasMatch(id), isTrue);
    expect(secret.length, greaterThanOrEqualTo(40));
    await prefs.setString('fitter_device_id', id);
    await prefs.setString('fitter_install_secret', secret);
    final transport = http.Client();
    final observed = ObservedClient(transport, report,
        maxRequests: 1, allowedPaths: const {'/api/fitter/ai/assistant'});
    try {
      await http.runWithClient(() async {
        await app.main();
        final open = find.byTooltip('Powiedz, co zrobić');
        await waitFor(t, () => open.evaluate().isNotEmpty);
        await t.tap(open);
        const request = 'Przejdźmy teraz do kalkulatora heat input';
        await command(t, request);
        await waitFor(t,
            () => find.textContaining('Włącz AI, aby').evaluate().isNotEmpty);
        final enable = find.byKey(const Key('assistant-enable-ai'));
        final panelScroll = find
            .descendant(
                of: find.byType(AiChatScreen),
                matching: find.byType(Scrollable))
            .first;
        await t.scrollUntilVisible(enable, 120, scrollable: panelScroll);
        expect(observed.aiRequestsSent, 0,
            reason: 'No remote AI before consent');
        report['noRequestBeforeConsent'] = true;
        await t.tap(enable);
        await waitFor(
            t, () => find.byType(ConsentScreen).evaluate().isNotEmpty);
        final consentScroll = find
            .descendant(
                of: find.byType(ConsentScreen),
                matching: find.byType(Scrollable))
            .first;
        final checkbox = find.byType(Checkbox);
        await t.scrollUntilVisible(checkbox, 200, scrollable: consentScroll);
        await t.tap(checkbox);
        await t.pump();
        final accept = find.widgetWithText(FilledButton, 'Akceptuję');
        await t.scrollUntilVisible(accept, 100, scrollable: consentScroll);
        await t.tap(accept);
        await waitFor(t, () => observed.answer != null,
            timeout: const Duration(seconds: 75));
        expect(report['aiStatus'], 200);
        expect(observed.answer!['kind'], 'execute');
        final steps = observed.answer!['steps'] as List;
        expect(steps, hasLength(1));
        expect((steps.single as Map)['skill_id'], 'tool.open');
        expect(observed.requests.single['text'], request);
        expect(observed.requests.single['capabilityIds'], ['tool.open']);
        await waitFor(
            t,
            () =>
                ToolBridge.instance.activeToolId == 'heat_input' &&
                find.byType(HeatInputScreen).evaluate().isNotEmpty &&
                ToolBridge.instance.calculatorResult('heat_input')
                    is HeatInputResultReadback);
        report['aiOpenedActualModule'] = true;
        report['actualModule'] = ToolBridge.instance.activeToolId;
        await command(
            t, 'ustaw heat input TIG EN 24 V 230 A 150 mm/min sprawność 0,6');
        await waitFor(
            t,
            () =>
                ToolBridge.instance.inputFields('heat_input')?['amps'] ==
                230.0);
        final fields = ToolBridge.instance.inputFields('heat_input')!;
        expect(fields['volts'], 24.0);
        expect(fields['travel_mm_min'], 150.0);
        expect(fields['process'], 'GTAW');
        expect(fields['standard'], 'en1011');
        final result = ToolBridge.instance.calculatorResult('heat_input')
            as HeatInputResultReadback;
        expect(result.valueKjPerMm, closeTo(1.3248, 1e-8));
        report['nativeInputs'] = fields;
        report['nativeResult'] = result.toJson();
        report['nativeCalculatorUpdated'] = true;
        await command(t, 'otwórz');
        await waitFor(
            t,
            () => find
                .textContaining('Które narzędzie otworzyć?')
                .evaluate()
                .isNotEmpty);
        expect(ToolBridge.instance.activeToolId, 'heat_input');
        expect(observed.aiAttempts, 1);
        expect(observed.aiRequestsSent, 1);
        report['ambiguousRequestClarifiedLocally'] = true;
        await t.pump(const Duration(seconds: 2));
        expect(t.takeException(), isNull);
      }, () => observed);
    } finally {
      await t.pumpWidget(const SizedBox.shrink());
      await prefs.reload();
      final headers = await PremiumService.instance.authHeaders();
      final deleted = await transport
          .delete(Uri.parse('${BackendConfig.baseUrl}/api/fitter/me'),
              headers: headers)
          .timeout(const Duration(seconds: 25));
      report['cleanupStatus'] = deleted.statusCode;
      report['cleanupOk'] = jsonDecode(deleted.body)['ok'] == true;
      expect(deleted.statusCode, 200);
      expect(report['cleanupOk'], isTrue);
      report['aiRequestAttempts'] = observed.aiAttempts;
      report['aiRequestsSent'] = observed.aiRequestsSent;
      report['blockedAiPaths'] = observed.blockedPaths;
      transport.close();
      final encoded = base64Encode(utf8.encode(jsonEncode(report)));
      final count = (encoded.length + 899) ~/ 900;
      for (var i = 0; i < count; i++) {
        final end =
            (i + 1) * 900 < encoded.length ? (i + 1) * 900 : encoded.length;
        debugPrint(
            'FWP_DEVICE_QA_REPORT $i/$count: ${encoded.substring(i * 900, end)}');
      }
    }
  }, timeout: const Timeout(Duration(minutes: 4)));
}
