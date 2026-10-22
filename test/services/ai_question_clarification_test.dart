import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:cut_list_app/assistant/ai_clarification.dart';
import 'package:cut_list_app/services/ai_chat_service.dart';
import 'package:cut_list_app/services/premium_service.dart';
import '../support/test_account.dart';
import '../test_prefs.dart';

void main() {
  useGuestAccount();
  final requests = <http.Request>[];
  final c = AiClarification(
      question: 'Metoda?',
      userTurns: ['Wyjaśnij temperaturę międzyściegową', 'dla spoiny rurowej']);
  setUp(() {
    requests.clear();
    seedFreshInstall(extra: {
      'fitter_device_id': '0123456789abcdef0123456789abcdef',
      'fitter_install_secret': 'AbCdEfGhIjKlMnOpQrStUvWxYz0123456789-_AbCdE'
    });
    PremiumService.instance.resetForTest();
  });
  Future<ChatMessage> send(http.Client client, {AiClarification? context}) =>
      http.runWithClient(
          () => AiChatService.instance.sendMessage('termometrem kontaktowym',
              questionClarification: context ?? c),
          () => client);
  test('old server response is not displayed as a context-aware answer',
      () async {
    final reply = await send(MockClient((r) async {
      requests.add(r);
      return http.Response(jsonEncode({'text': 'Ignored context'}), 200);
    }));
    expect(reply.kind, AiReplyKind.localDialogue);
    expect(reply.text, contains('Zadaj całe pytanie ponownie'));
    expect(reply.text, isNot(contains('Ignored context')));
    expect(requests, hasLength(1));
  });
  test('acknowledged user context is sent verbatim without the model question',
      () async {
    final reply = await send(MockClient((r) async {
      requests.add(r);
      return http.Response(
          jsonEncode({'text': 'OK', 'question_clarification_used': true}), 200);
    }));
    final body = jsonDecode(requests.single.body) as Map;
    expect(body['question_clarification'], {'user_turns': c.userTurns});
    expect(jsonEncode(body), isNot(contains('Metoda?')));
    expect(reply.kind, AiReplyKind.live);
    expect(reply.text, 'OK');
  });
  test(
      'network fallback searches the complete question instead of the last detail',
      () async {
    final expected = AiChatService.instance
        .offlineReply(c.sourceWithReply('termometrem kontaktowym')!);
    final short =
        AiChatService.instance.offlineReply('termometrem kontaktowym');
    expect(expected.text, isNot(short.text),
        reason: 'fixture must distinguish complete and detail-only help');
    final reply = await send(MockClient((r) async {
      requests.add(r);
      throw const SocketException('offline');
    }));
    expect(reply.kind, AiReplyKind.offlineHelp);
    expect(reply.text, expected.text);
    expect(requests, hasLength(1));
  });
  test('credentials in prior answers are blocked before HTTP', () async {
    final reply = await send(MockClient((r) async {
      requests.add(r);
      throw StateError('unexpected');
    }),
        context: AiClarification(
            question: '?', userTurns: ['password=secret12345']));
    expect(reply.kind, AiReplyKind.localDialogue);
    expect(requests, isEmpty);
  });
  test(
      'exhausted question context refuses instead of sending a detail-only question',
      () async {
    final reply = await send(MockClient((r) async {
      requests.add(r);
      throw StateError('unexpected');
    }),
        context:
            AiClarification(question: '?', userTurns: List.filled(32, 'turn')));
    expect(reply.kind, AiReplyKind.localDialogue);
    expect(requests, isEmpty);
  });
}
