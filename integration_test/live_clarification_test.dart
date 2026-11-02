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
      'real AI asks essential details and answers the original knowledge question',
      (t) async {
    final report = <String, dynamic>{
      'scope': 'real model clarification and contextual answer; no microphone',
      'maxAiRequests': 2
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
        maxRequests: 2, allowedPaths: const {BackendConfig.aiChat});
    try {
      await http.runWithClient(() async {
        await app.main();
        final open = find.byTooltip('Powiedz, co zrobić');
        await waitFor(t, () => open.evaluate().isNotEmpty);
        await t.tap(open);
        const request = 'Jaki gaz dobrać do spawania?';
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
        final first = observed.answer!;
        expect(first['needs_clarification'], isTrue);
        final firstText = first['text'] as String;
        expect(
            RegExp(r'metod|proces|materia', caseSensitive: false)
                .hasMatch(firstText),
            isTrue);
        expect(
            RegExp(r'moduł|module', caseSensitive: false).hasMatch(firstText),
            isFalse);
        final firstExcerpt = firstText.substring(
            0, firstText.length < 70 ? firstText.length : 70);
        await waitFor(
            t, () => find.textContaining(firstExcerpt).evaluate().isNotEmpty);
        report['modelClarificationDisplayed'] = true;
        await t.pump(const Duration(seconds: 2));
        const detail = 'TIG, stal nierdzewna 316L, chodzi o gaz osłonowy.';
        await command(t, detail);
        await waitFor(t, () => observed.answers.length == 2,
            timeout: const Duration(seconds: 75));
        expect(report['aiStatus'], 200);
        expect(observed.requests[0]['message'], request);
        expect(observed.requests[1]['message'], detail);
        expect(observed.requests[1]['questionClarification'], {
          'user_turns': [request]
        });
        final answer = observed.answer!;
        expect(answer['question_clarification_used'], isTrue);
        expect(answer['needs_clarification'], isFalse);
        final text = answer['text'] as String;
        expect(text.toLowerCase(), contains('argon'));
        final excerpt = text.substring(0, text.length < 70 ? text.length : 70);
        await waitFor(
            t, () => find.textContaining(excerpt).evaluate().isNotEmpty);
        expect(find.textContaining('Tryb offline'), findsNothing);
        expect(find.textContaining('Które narzędzie otworzyć'), findsNothing);
        expect(observed.aiAttempts, 2);
        expect(observed.aiRequestsSent, 2);
        report['originalQuestionPreservedInRequest'] = true;
        report['serverConfirmedClarificationContext'] = true;
        report['contextualAnswerDisplayed'] = true;
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
