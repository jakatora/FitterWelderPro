// Tryb „Odpowiedz": historia wysyłana do POST /ai/chat. Dawniej szła CAŁA
// rozmowa (z powitaniem, komunikatami offline i bieżącym pytaniem) — backend
// przyjmował najwyżej 20 wpisów, więc od 11. pytania przychodziło 400 i
// aplikacja po cichu przechodziła na pomoc offline, a pytanie szło 2×.
// Teraz: najwyżej 6 ostatnich wpisów, same pary pytanie → odpowiedź modelu,
// bez bieżącego pytania. Transport to atrapa — zero połączeń.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:cut_list_app/services/ai_chat_service.dart';
import 'package:cut_list_app/services/premium_service.dart';

ChatMessage _user(String t) => ChatMessage(role: ChatRole.user, text: t);
ChatMessage _ai(String t, [AiReplyKind kind = AiReplyKind.live]) =>
    ChatMessage(role: ChatRole.assistant, text: t, kind: kind);

List<ChatMessage> _conversation(int questions) => [
      _ai('Witaj! Zapytaj o spawanie.', AiReplyKind.demo),
      for (var i = 1; i <= questions; i++) ...[
        _user('pytanie $i'),
        _ai('odpowiedź $i'),
      ],
    ];

void main() {
  group('chatHistoryForRequest', () {
    test('limit jest jawny: 6 wpisów', () {
      expect(kChatHistoryMax, 6);
    });

    test('długa rozmowa → 6 ostatnich wpisów, od pytania użytkownika', () {
      final h = chatHistoryForRequest(_conversation(12));
      expect(h.map((m) => m.text), [
        'pytanie 10', 'odpowiedź 10', //
        'pytanie 11', 'odpowiedź 11', //
        'pytanie 12', 'odpowiedź 12',
      ]);
    });

    test('bez powitania, pomocy offline, limitów i pytań bez odpowiedzi', () {
      final h = chatHistoryForRequest([
        _ai('Witaj!', AiReplyKind.demo),
        _user('q1'),
        _ai('pomoc offline', AiReplyKind.offlineHelp),
        _user('lokalne pytanie'),
        _ai('Jaki prąd w amperach?', AiReplyKind.localDialogue),
        _user('q2'),
        _ai('a2'),
        _user('q3'),
        _ai('limit', AiReplyKind.dailyLimit),
        _user('q4 — bieżące, jeszcze bez odpowiedzi'),
      ]);
      expect(h.map((m) => m.text), ['q2', 'a2']);
    });

    test('pusta rozmowa → pusta historia', () {
      expect(chatHistoryForRequest(const []), isEmpty);
      expect(chatHistoryForRequest([_ai('Witaj!', AiReplyKind.demo)]), isEmpty);
    });
  });

  group('sendMessage', () {
    final requests = <http.Request>[];

    setUp(() {
      requests.clear();
      SharedPreferences.setMockInitialValues({
        'fitter_device_id': '0123456789abcdef0123456789abcdef',
        'fitter_install_secret': 'AbCdEfGhIjKlMnOpQrStUvWxYz0123456789-_AbCdE',
      });
      PremiumService.instance.resetForTest();
    });

    Future<ChatMessage> send(String text, List<ChatMessage> history) =>
        http.runWithClient(
          () => AiChatService.instance.sendMessage(text, history: history),
          () => MockClient((r) async {
            requests.add(r);
            return http.Response(jsonEncode({'text': 'OK'}), 200,
                headers: {'content-type': 'application/json; charset=utf-8'});
          }),
        );

    test('11. pytanie: ≤ 6 wpisów historii, bez bieżącego pytania', () async {
      // Stary ekran doklejał bieżące pytanie do historii — serwis i tak je
      // odcina (pytanie bez odpowiedzi nie jest parą).
      final history = [..._conversation(10), _user('pytanie 11')];
      final reply = await send('pytanie 11', history);
      expect(reply.kind, AiReplyKind.live);

      final body = jsonDecode(requests.single.body) as Map<String, dynamic>;
      expect(body['message'], 'pytanie 11');
      final sent = (body['history'] as List).cast<Map<String, dynamic>>();
      expect(sent.length, lessThanOrEqualTo(6));
      expect(sent.map((m) => m['text']), isNot(contains('pytanie 11')));
      expect(sent.first['role'], 'user');
      expect(sent.map((m) => m['role']).toSet(), {'user', 'assistant'});
      expect(sent.last['text'], 'odpowiedź 10');
    });
  });
}
