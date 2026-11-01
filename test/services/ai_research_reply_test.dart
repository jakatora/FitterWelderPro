import 'dart:convert';
import 'package:cut_list_app/services/ai_chat_service.dart';
import 'package:cut_list_app/services/premium_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import '../support/test_account.dart';
import '../test_prefs.dart';

void main() {
  useGuestAccount();
  setUp(() {
    seedFreshInstall(extra: {
      'fitter_device_id': '0123456789abcdef0123456789abcdef',
      'fitter_install_secret': 'AbCdEfGhIjKlMnOpQrStUvWxYz0123456789-_AbCdE',
    });
    PremiumService.instance.resetForTest();
  });
  Future<ChatMessage> receive(Map<String, Object?> body) => http.runWithClient(
      () => AiChatService.instance.sendMessage('Wyjaśnij temat'),
      () => MockClient((_) async => http.Response(jsonEncode(body), 200,
          headers: {'content-type': 'application/json; charset=utf-8'})));
  test('external references are visible in the answer and source chips',
      () async {
    final reply = await receive({
      'text': 'Informacja z dokumentacji.',
      'research_status': 'verified_sources',
      'web_sources': [
        {
          'title': 'TWI guidance',
          'url': 'https://www.twi-global.com/technical-knowledge/example'
        }
      ]
    });
    expect(reply.kind, AiReplyKind.live);
    expect(reply.text, contains('TWI guidance'));
    expect(reply.text, contains('https://www.twi-global.com/'));
    expect(reply.citations.single, contains('TWI guidance'));
  });
  test('source labels match the inline research references in order', () async {
    final reply = await receive({
      'text': 'First finding [1]. Second finding [2].',
      'web_sources': [
        {'title': 'TWI paper', 'url': 'https://www.twi-global.com/paper'},
        {'title': 'ISO summary', 'url': 'https://www.iso.org/standard/example'},
      ]
    });
    expect(reply.text, contains('First finding [1]. Second finding [2].'));
    expect(reply.citations, [
      '[1] TWI paper\nhttps://www.twi-global.com/paper',
      '[2] ISO summary\nhttps://www.iso.org/standard/example',
    ]);
  });
  for (final url in [
    'javascript:alert(1)',
    'http://example.com',
    'https://user:secret@example.com'
  ]) {
    test('invalid web source $url is rejected', () async {
      final reply = await receive({
        'text': 'Answer',
        'web_sources': [
          {'title': 'Source', 'url': url}
        ]
      });
      expect(reply.kind, AiReplyKind.unavailable);
      expect(reply.text, isNot(contains(url)));
    });
  }
  test('malformed clarification flag is rejected', () async {
    expect(
        (await receive({'text': 'Answer', 'needs_clarification': 'true'})).kind,
        AiReplyKind.unavailable);
  });
  test('unverified research retains explanation and enables explicit retry',
      () async {
    final reply = await receive({
      'text': 'Nie udało się potwierdzić odpowiedzi.',
      'research_status': 'unverified',
      'web_sources': []
    });
    expect(reply.kind, AiReplyKind.unavailable);
    expect(reply.text, 'Nie udało się potwierdzić odpowiedzi.');
    expect(reply.citations, isEmpty);
    expect(reply.needsClarification, isFalse);
  });
  for (final status in ['verified_sources', 'unverified', 'unknown', 7]) {
    test('inconsistent research result is rejected: $status', () async {
      final reply = await receive({
        'text': 'Untrusted technical claim',
        'research_status': status,
        'web_sources': status == 'unverified'
            ? [
                {'title': 'Source', 'url': 'https://www.twi-global.com/paper'}
              ]
            : []
      });
      expect(reply.kind, AiReplyKind.unavailable);
      expect(reply.text, isNot(contains('Untrusted technical claim')));
    });
  }
}
