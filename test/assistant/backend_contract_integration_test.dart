import 'dart:convert';
import 'dart:io';

import 'package:cut_list_app/assistant/ai_clarification.dart';
import 'package:cut_list_app/assistant/correction_memory.dart';
import 'package:cut_list_app/services/account_service.dart';
import 'package:cut_list_app/services/ai_chat_service.dart';
import 'package:cut_list_app/services/premium_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/test_account.dart';

class _LocalHttpOverrides extends HttpOverrides {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  useGuestAccount();
  final server = Platform.environment['FWP_CONTRACT_SERVER'];
  test('Flutter sends voice and correction context to a real local backend', () async {
    final base = Uri.parse(server!);
    expect(base.scheme, 'http');
    expect(base.host, '127.0.0.1');
    SharedPreferences.setMockInitialValues({});
    PremiumService.instance.resetForTest();
    await AccountService.instance.load();
    await CorrectionMemoryStore.instance.remember(const RememberedCorrection(
      question: 'Jak spawać TIG aluminium?', correction: 'Chodzi mi o aluminium 3 mm'));
    final actualHttp = HttpOverrides.runWithHttpOverrides(
        () => IOClient(HttpClient()), _LocalHttpOverrides());
    addTearDown(actualHttp.close);
    var requests = 0;
    await http.runWithClient(() async {
      final reply = await AiChatService.instance.sendMessage('3 mm',
          questionClarification: AiClarification(question: 'Jaka grubość?',
              userTurns: ['Jak spawać TIG aluminium?']), speechTranscript: true);
      expect(reply.kind, AiReplyKind.live);
      expect(reply.text, startsWith('Sprawdź WPS dla aluminium.'));
      expect(requests, 1);
    }, () => MockClient((request) async {
      expect(request.url.path, '/api/fitter/ai/chat');
      requests++;
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      expect(body['message'], '3 mm');
      expect(body['speech_transcript'], true);
      expect(body['question_clarification'], {'user_turns': ['Jak spawać TIG aluminium?']});
      expect(body['remembered_corrections'], [{
        'question': 'Jak spawać TIG aluminium?',
        'correction': 'Chodzi mi o aluminium 3 mm',
      }]);
      final register = await actualHttp.post(base.resolve('/api/fitter/device/register'),
          headers: request.headers, body: '{}');
      expect(register.statusCode, anyOf(200, 201));
      return actualHttp.post(base.resolve(request.url.path),
          headers: request.headers, body: request.body);
    }));
  }, skip: server == null ? 'Requires a locally started fake-model backend' : false);

  test('Flutter receives a sourced research answer from the local backend', () async {
    final base = Uri.parse(server!);
    expect(base.scheme, 'http');
    expect(base.host, '127.0.0.1');
    SharedPreferences.setMockInitialValues({});
    PremiumService.instance.resetForTest();
    await AccountService.instance.load();
    final actualHttp = HttpOverrides.runWithHttpOverrides(
        () => IOClient(HttpClient()), _LocalHttpOverrides());
    addTearDown(actualHttp.close);
    var requests = 0;
    await http.runWithClient(() async {
      final reply = await AiChatService.instance.sendMessage(
          'FixtureResearch: jak faza sigma wpływa na korozję duplex?');
      expect(reply.kind, AiReplyKind.live);
      expect(reply.text, contains('Faza sigma'));
      expect(reply.citations, hasLength(1));
      expect(reply.citations.single, contains('TWI fixture source'));
      expect(reply.citations.single, contains('https://www.twi-global.com/technical-knowledge/example'));
      expect(requests, 1);
    }, () => MockClient((request) async {
      expect(request.url.path, '/api/fitter/ai/chat');
      requests++;
      final register = await actualHttp.post(base.resolve('/api/fitter/device/register'),
          headers: request.headers, body: '{}');
      expect(register.statusCode, anyOf(200, 201));
      return actualHttp.post(base.resolve(request.url.path),
          headers: request.headers, body: request.body);
    }));
  }, skip: server == null ? 'Requires a locally started fake-model backend' : false);
}
