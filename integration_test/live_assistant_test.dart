import 'dart:async';
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

// Real network pass-through: no response, provider or platform mocking.
class ObservedClient extends http.BaseClient {
  ObservedClient(this.delegate, this.report, {this.maxRequests = 1});
  final int maxRequests;
  final requests = <Map<String, dynamic>>[];
  final answers = <Map<String, dynamic>>[];
  final http.Client delegate;
  final Map<String, dynamic> report;
  int paidRequests = 0;
  Map<String, dynamic>? answer;
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final ai = request.method == 'POST' &&
        (request.url.path.contains('/ai/') ||
            request.url.path.contains('/assistant/'));
    if (ai) {
      paidRequests++;
      if (paidRequests > maxRequests ||
          request.url.path != BackendConfig.aiChat) {
        throw StateError(
            'Explicit knowledge request budget exceeded; no retries');
      }
      report['aiRequestPath'] = request.url.path;
      if (request is! http.Request) {
        throw StateError('Expected the real chat JSON request');
      }
      final body = jsonDecode(request.body) as Map;
      // Keep conversation evidence only; never identity or request headers.
      requests.add({'message': body['message'], 'history': body['history']});
      report['conversationRequests'] = requests;
    }
    final response =
        await http.Response.fromStream(await delegate.send(request));
    if (ai) {
      report['aiStatus'] = response.statusCode;
      final decoded = jsonDecode(response.body);
      answer = Map<String, dynamic>.from(decoded as Map);
      report['aiAnswer'] = answer;
      answers.add(answer!);
      report['conversationAnswers'] = answers;
    }
    return http.StreamedResponse(
        Stream.value(response.bodyBytes), response.statusCode,
        headers: response.headers,
        request: request,
        reasonPhrase: response.reasonPhrase);
  }
}

Future<void> waitFor(WidgetTester tester, bool Function() ready,
    {Duration timeout = const Duration(seconds: 25)}) async {
  final deadline = DateTime.now().add(timeout);
  while (!ready() && DateTime.now().isBefore(deadline)) {
    await tester.pump(const Duration(milliseconds: 200));
  }
  expect(ready(), isTrue,
      reason: 'The real app did not reach the expected state');
}

void main() {
  if (!const bool.fromEnvironment('FWP_LIVE_AI_QA')) {
    throw StateError(
        'Explicit FWP_LIVE_AI_QA=true is required; never silently skip');
  }
  const followUp = bool.fromEnvironment('FWP_QA_FOLLOWUP');
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
      followUp
          ? 'real assistant UI preserves conversation context across two turns'
          : 'fresh installation displays a real AI answer through the assistant UI',
      (tester) async {
    final report = <String, dynamic>{
      'scope': 'real app UI and backend; no microphone',
      'maxAiRequests': followUp ? 2 : 1,
      'startedAt': DateTime.now().toUtc().toIso8601String()
    };
    binding.reportData = report;
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getKeys(), isEmpty,
        reason: 'Fresh disposable installation only');
    const fixtureId = String.fromEnvironment('FWP_QA_DEVICE_ID');
    const fixtureSecret = String.fromEnvironment('FWP_QA_INSTALL_SECRET');
    expect(RegExp(r'^[a-f0-9]{32}$').hasMatch(fixtureId), isTrue);
    expect(fixtureSecret.length, greaterThanOrEqualTo(40));
    // Fixture values are supplied from a private file, never from a user account.
    // The orchestrator retains them for cleanup even if the device test crashes.
    await prefs.setString('fitter_device_id', fixtureId);
    await prefs.setString('fitter_install_secret', fixtureSecret);
    final transport = http.Client();
    final observed =
        ObservedClient(transport, report, maxRequests: followUp ? 2 : 1);
    try {
      await http.runWithClient(() async {
        await app.main();
        final open = find.byTooltip('Powiedz, co zrobić');
        await waitFor(tester, () => open.evaluate().isNotEmpty);
        await tester.tap(open);
        final input = find.byKey(const Key('assistant-command'));
        await waitFor(tester, () => input.evaluate().isNotEmpty);
        await tester.enterText(input, 'Co oznacza DN na rurze?');
        await tester.tap(find.byKey(const Key('assistant-go')));
        await waitFor(
            tester, () => find.byType(ConsentScreen).evaluate().isNotEmpty);
        final checkbox = find.byType(Checkbox);
        await tester.ensureVisible(checkbox);
        await tester.tap(checkbox);
        await tester.pump();
        final accept = find.widgetWithText(FilledButton, 'Akceptuję');
        await tester.ensureVisible(accept);
        await tester.tap(accept);
        await waitFor(tester, () => observed.answer != null,
            timeout: const Duration(seconds: 75));
        expect(report['aiStatus'], 200);
        expect(observed.paidRequests, 1);
        expect(observed.answer!['needs_clarification'], isFalse);
        final text = observed.answer!['text'] as String;
        expect(text.toLowerCase(), contains('nominal'));
        final excerpt = text.substring(0, text.length < 70 ? text.length : 70);
        await waitFor(
            tester, () => find.textContaining(excerpt).evaluate().isNotEmpty);
        expect(find.textContaining('Tryb offline'), findsNothing);
        report['answerDisplayedInRealUi'] = true;
        if (followUp) {
          const question = 'Czyli to zmierzona średnica w milimetrach?';
          await tester.enterText(input, question);
          await tester.tap(find.byKey(const Key('assistant-go')));
          await waitFor(tester, () => observed.answers.length == 2,
              timeout: const Duration(seconds: 75));
          expect(report['aiStatus'], 200);
          expect(observed.paidRequests, 2);
          expect(observed.requests[1]['message'], question);
          expect(
              observed.requests[1]['history'],
              [
                {'role': 'user', 'text': 'Co oznacza DN na rurze?'},
                {'role': 'assistant', 'text': text},
              ],
              reason:
                  'The actual second request must carry the first exchange');
          expect(observed.answer!['needs_clarification'], isFalse);
          final followUpText = observed.answer!['text'] as String;
          expect(followUpText.toLowerCase(), contains('nominal'));
          final followUpExcerpt = followUpText.substring(
              0, followUpText.length < 70 ? followUpText.length : 70);
          await waitFor(tester,
              () => find.textContaining(followUpExcerpt).evaluate().isNotEmpty);
          expect(find.textContaining('Tryb offline'), findsNothing);
          report['followUpDisplayedInRealUi'] = true;
          report['previousExchangeSentAsContext'] = true;
        }
        await tester.pump(const Duration(seconds: 2));
        expect(tester.takeException(), isNull);
      }, () => observed);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      await prefs.reload();
      if (prefs.getString('fitter_device_id')?.isNotEmpty == true) {
        final headers = await PremiumService.instance.authHeaders();
        final deleted = await transport
            .delete(Uri.parse('${BackendConfig.baseUrl}/api/fitter/me'),
                headers: headers)
            .timeout(const Duration(seconds: 25));
        report['cleanupStatus'] = deleted.statusCode;
        report['cleanupOk'] = jsonDecode(deleted.body)['ok'] == true;
        expect(deleted.statusCode, 200,
            reason: 'Own disposable fixture cleanup');
        expect(report['cleanupOk'], isTrue);
      }
      report['aiRequests'] = observed.paidRequests;
      transport.close();
      final encodedReport = base64Encode(utf8.encode(jsonEncode(report)));
      final count = (encodedReport.length + 899) ~/ 900;
      for (var i = 0; i < count; i++) {
        final end = (i + 1) * 900 < encodedReport.length
            ? (i + 1) * 900
            : encodedReport.length;
        debugPrint('FWP_DEVICE_QA_REPORT $i/$count: '
            '${encodedReport.substring(i * 900, end)}');
      }
    }
  }, timeout: const Timeout(Duration(minutes: 4)));
}
