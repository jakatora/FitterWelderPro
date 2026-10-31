import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cut_list_app/assistant/assistant_ai_client.dart';
import 'package:cut_list_app/services/ai_failure.dart';
import 'package:cut_list_app/services/ai_chat_service.dart';
import 'package:cut_list_app/services/ai_professional_context.dart';
import 'package:cut_list_app/services/premium_service.dart';
import 'package:cut_list_app/i18n/app_language.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    SharedPreferences.setMockInitialValues({
      'fitter_device_id': '0123456789abcdef0123456789abcdef',
      'fitter_install_secret': 'AbCdEfGhIjKlMnOpQrStUvWxYz0123456789-_AbCdE',
    });
    PremiumService.instance.resetForTest();
    AiProfessionalContext.instance.resetForTest();
    AppLanguageController.current = AppLanguage.pl;
  });
  test(
      'only bounded allowlisted codes are accepted; server prose never reaches UI',
      () {
    for (final raw in [
      '<html>LEAKED_TOKEN</html>',
      jsonEncode({
        'error': {'code': 'LEAKED_TOKEN', 'message': 'LEAKED_TOKEN'}
      }),
      jsonEncode({
        'error': {'code': 'AI_BUDGET_EXCEEDED'},
        'padding': 'x' * 17000
      })
    ]) {
      final failure = AiFailure.fromHttp(503, utf8.encode(raw));
      expect(failure.code, isNull);
      expect(failure.message(AppLanguage.pl), isNot(contains('LEAKED_TOKEN')));
    }
    expect(
        AiFailure.fromHttp(
                503, utf8.encode('{"error":{"code":"AI_BUDGET_EXCEEDED"}}'))
            .code,
        'AI_BUDGET_EXCEEDED');
  });
  for (final (status, code, pl, en) in [
    (404, null, 'nie jest jeszcze uruchomione', 'not running'),
    (401, null, 'uwierzytelnić', 'authenticated'),
    (
      503,
      'AI_BUDGET_EXCEEDED',
      'miesięczny limit kosztów',
      'monthly AI cost limit'
    ),
    (503, 'AI_BUSY', 'chwilowo niedostępny', 'temporarily unavailable'),
    (502, 'AI_CONFIG', 'konfiguracji', 'configuration'),
    (200, 'AI_PLAN_INVALID', 'poprawnej propozycji', 'valid proposal'),
    (429, null, 'dzienny limit', 'Daily AI limit'),
    (429, 'API_RATE_LIMITED', 'chwilę', 'a moment'),
  ]) {
    test('diagnostic $status/$code is distinct in both languages', () {
      final failure = AiFailure(status, code: code);
      expect(failure.message(AppLanguage.pl), contains(pl));
      expect(failure.message(AppLanguage.en), contains(en));
    });
  }
  test('interpreter retains safe reason code from actual HTTP response',
      () async {
    final client = AssistantAiClient(
        identity: () async => {},
        client: MockClient((_) async => http.Response(
            '{"error":{"code":"AI_BUDGET_EXCEEDED","message":"LEAKED_TOKEN"}}',
            503)));
    addTearDown(client.close);
    await expectLater(
        client.interpret({
          'capabilities': [
            {'id': 'fixture'}
          ]
        }),
        throwsA(isA<AssistantAiUnavailable>()
            .having((e) => e.code, 'code', 'AI_BUDGET_EXCEEDED')));
  });
  test(
      'malformed successful model response is not described as a network failure',
      () async {
    final client = AssistantAiClient(
        identity: () async => {},
        client: MockClient((_) async => http.Response('bad json', 200)));
    addTearDown(client.close);
    await expectLater(
        client.interpret({
          'capabilities': [
            {'id': 'fixture'}
          ]
        }),
        throwsA(isA<AssistantAiUnavailable>()
            .having((e) => e.code, 'code', 'AI_PLAN_INVALID')));
  });
  for (final (status, code, kind, needle) in [
    (
      503,
      'AI_BUDGET_EXCEEDED',
      AiReplyKind.unavailable,
      'miesięczny limit kosztów'
    ),
    (404, 'NOT_FOUND', AiReplyKind.offlineHelp, 'nie jest jeszcze uruchomione'),
    (401, 'INSTALL_SECRET_INVALID', AiReplyKind.offlineHelp, 'uwierzytelnić'),
  ]) {
    test(
        'knowledge chat $status distinguishes cause and is never a live model answer',
        () async {
      var calls = 0;
      final reply = await http.runWithClient(
          () => AiChatService.instance.sendMessage('Jak działa TIG?'),
          () => MockClient((_) async {
                calls++;
                return http.Response(
                    jsonEncode({
                      'error': {'code': code, 'message': 'LEAKED_TOKEN'}
                    }),
                    status);
              }));
      expect(calls, 1);
      expect(reply.kind, kind);
      expect(reply.text, contains(needle));
      expect(reply.text, isNot(contains('LEAKED_TOKEN')));
      expect(
          chatHistoryForRequest(
              [ChatMessage(role: ChatRole.user, text: 'Q'), reply]),
          isEmpty);
    });
  }
}
