import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cut_list_app/main.dart' as app;
import 'package:cut_list_app/config/backend_config.dart';
import 'package:cut_list_app/screens/consent_screen.dart';
import 'package:cut_list_app/services/premium_service.dart';
import 'package:cut_list_app/assistant/core/tool_bridge.dart';
import 'package:cut_list_app/screens/fitter_tools_screen.dart';
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
      'native pipe mass command and real AI explain the visible calculator result',
      (t) async {
    final report = <String, dynamic>{
      'scope':
          'real native pipe calculator and contextual AI answer; no microphone',
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
        maxRequests: 1, allowedPaths: const {BackendConfig.aiChat});
    try {
      await http.runWithClient(() async {
        await app.main();
        final open = find.byTooltip('Powiedz, co zrobić');
        await waitFor(t, () => open.evaluate().isNotEmpty);
        await t.tap(open);
        await command(t,
            'Oblicz masę rury OD 60,3 mm ścianka 3,91 mm długość 1 m 316L ilość 2');
        await waitFor(
            t,
            () =>
                ToolBridge.instance.activeToolId == 'pipe_weight' &&
                ToolBridge.instance.inputFields('pipe_weight')?['quantity'] ==
                    2.0);
        expect(observed.aiRequestsSent, 0);
        report['nativeCommandWithoutAi'] = true;
        final expected = {
          'tool_id': 'pipe_weight',
          'inputs': {
            'od_mm': 60.3,
            'wall_mm': 3.91,
            'length_mm': 1000.0,
            'quantity': 2.0,
            'material': 'ss316'
          },
          'results': {
            'precision': 'displayed',
            'kg_per_m': 5.541,
            'kg_per_piece': 5.541,
            'kg_total': 11.08
          },
        };
        await t.tap(find.byTooltip('Zwiń'));
        await t.pump();
        final nativeScroll = find
            .descendant(
                of: find.byType(FitterToolsScreen),
                matching: find.byWidgetPredicate((w) =>
                    w is Scrollable && w.axisDirection == AxisDirection.down))
            .first;
        await t.scrollUntilVisible(find.text('11.08 kg'), 160,
            scrollable: nativeScroll);
        expect(find.text('5.541 kg/m'), findsOneWidget);
        expect(find.text('11.08 kg'), findsOneWidget);
        report['nativeResultDisplayed'] = true;
        await t.pump(const Duration(seconds: 2));
        await t.tap(find.byTooltip('Powiedz, co zrobić'));
        const request =
            'Wyjaśnij, co oznaczają trzy wyświetlone masy z tego kalkulatora. Podaj widoczne wartości oraz jednostki. Nie przeliczaj ponownie.';
        await command(t, request);
        await waitFor(
            t, () => find.byType(ConsentScreen).evaluate().isNotEmpty);
        expect(observed.aiRequestsSent, 0);
        report['noRequestBeforeConsent'] = true;
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
        expect(observed.requests.single['message'], request);
        expect(observed.requests.single['calculatorContext'], expected);
        final answer = observed.answer!;
        expect(answer['calculator_context_used'], isTrue);
        expect(answer['needs_clarification'], isFalse);
        final text = answer['text'] as String;
        final normalized = text.replaceAll(',', '.');
        expect(normalized, contains('5.541'));
        expect(normalized, contains('11.08'));
        for (final key in [
          'kg_per_m',
          'kg_per_piece',
          'kg_total',
          'precision:',
          'displayed',
          'ss316'
        ]) {
          expect(text, isNot(contains(key)));
        }
        final excerpt = text.substring(0, text.length < 70 ? text.length : 70);
        await waitFor(
            t, () => find.textContaining(excerpt).evaluate().isNotEmpty);
        expect(ToolBridge.instance.activeToolId, 'pipe_weight');
        expect(
            ToolBridge.instance.inputFields('pipe_weight'), expected['inputs']);
        expect(observed.aiAttempts, 1);
        expect(observed.aiRequestsSent, 1);
        report['nativeContextSentExactly'] = true;
        report['serverConfirmedCalculatorContext'] = true;
        report['contextualAnswerDisplayed'] = true;
        report['calculatorInputsUnchanged'] = true;
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
