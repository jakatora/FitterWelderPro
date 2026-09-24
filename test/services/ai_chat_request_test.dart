// Asystent AI: kształt żądania pod nowy backend (nagłówki tożsamości, bieżący
// język, bez pola `units`) i aktualne nazwy narzędzi w odpowiedziach demo.
// Transport to atrapa (http.runWithClient + MockClient) — zero połączeń.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:cut_list_app/i18n/app_language.dart';
import 'package:cut_list_app/services/ai_chat_service.dart';
import 'package:cut_list_app/services/api_client.dart';
import 'package:cut_list_app/services/premium_service.dart';

const _deviceId = '0123456789abcdef0123456789abcdef';
const _secret = 'AbCdEfGhIjKlMnOpQrStUvWxYz0123456789-_AbCdE';

void main() {
  final requests = <http.Request>[];

  Future<ChatMessage> send(String text, http.Response response) =>
      http.runWithClient(
        () => AiChatService.instance.sendMessage(text),
        () => MockClient((r) async {
          requests.add(r);
          return response;
        }),
      );

  setUp(() {
    requests.clear();
    SharedPreferences.setMockInitialValues({
      'fitter_device_id': _deviceId,
      'fitter_install_secret': _secret,
    });
    PremiumService.instance.resetForTest();
  });

  tearDown(() => AppLanguageController.current = AppLanguage.pl);

  test('wysyła bieżący język, device_id i nagłówki; bez pola units', () async {
    expect(kAiBackendAvailable, isTrue,
        reason: 'test sprawdza ścieżkę z prawdziwym żądaniem');
    AppLanguageController.current = AppLanguage.en;
    final reply = await send(
      'Preheat for P91?',
      http.Response(jsonEncode({'text': 'OK', 'citations': []}), 200,
          headers: {'content-type': 'application/json; charset=utf-8'}),
    );
    expect(reply.text, 'OK');

    final req = requests.single;
    expect(req.url.path, '/api/fitter/ai/chat');
    expect(req.headers[kDeviceIdHeader], _deviceId);
    expect(req.headers[kInstallSecretHeader], _secret);
    final body = jsonDecode(req.body) as Map<String, dynamic>;
    expect(body['lang'], 'en');
    expect(body['device_id'], _deviceId);
    expect(body.containsKey('units'), isFalse,
        reason: 'backend nie zna pola units');
  });

  test('po polsku wysyła lang=pl', () async {
    AppLanguageController.current = AppLanguage.pl;
    await send('Preheat P91?',
        http.Response(jsonEncode({'text': 'OK'}), 200));
    expect((jsonDecode(requests.single.body) as Map)['lang'], 'pl');
  });

  test('401 (brak sekretu / Premium) → tryb offline z lokalnej bazy', () async {
    final reply = await send(
      'Jak zrobić saddle cut?',
      http.Response(
          jsonEncode({
            'error': {'code': 'INSTALL_SECRET_REQUIRED', 'message': 'x'}
          }),
          401),
    );
    expect(reply.text, startsWith('(Tryb offline'));
    expect(reply.text, isNot(contains('INSTALL_SECRET')));
  });

  test('odpowiedzi demo odsyłają do aktualnych nazw narzędzi', () async {
    final saddle = await send('Jak zrobić saddle cut?',
        http.Response('{}', 500));
    expect(saddle.text, contains('Szablon siodła do druku'));
    expect(saddle.text, contains('menu MONTER'));
    expect(saddle.text, isNot(contains('FITTER')));
    expect(saddle.text, isNot(contains('Saddle / Coping')));
    expect(saddle.citations.single, contains('Szablon siodła do druku'));

    final torque = await send('moment śrub flange',
        http.Response('{}', 500));
    expect(torque.text, contains('"Moment śrub" w menu MONTER'));
    expect(torque.text, isNot(contains('menu FITTER')));
  });
}
