// Duplikaty wiadomości na słabym zasięgu.
//
// ApiClient ponawiał KAŻDE żądanie po timeoucie, także POST. Serwer mógł
// przyjąć wiadomość, a klient nie zdążył dostać odpowiedzi — ponowienie
// wysyłało ją drugi raz. Teraz POST jest ponawiany tylko wtedy, gdy niesie
// `Idempotency-Key` (serwer deduplikuje po nim), i to z TYM SAMYM kluczem.
//
// Transport HTTP to atrapa (MockClient) — zero prawdziwych połączeń.

import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:cut_list_app/services/api_client.dart';
import 'package:cut_list_app/services/chat_service.dart';
import 'package:cut_list_app/services/premium_service.dart';
import 'package:cut_list_app/services/user_profile.dart';

http.Response _json(int status, Object body) => http.Response(
      jsonEncode(body),
      status,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );

final _uuidV4 = RegExp(
    r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$');

Map<String, Object> _message(int id) => {
      'message': {
        'id': id,
        'room': 'general',
        'device_id': '0123456789abcdef0123456789abcdef',
        'nickname': 'Jan Nowak',
        'text': 'Jaki preheat na P91?',
        'created_at': '2026-09-26T10:00:00.000Z',
        'flags': 0,
        'mine': true,
      }
    };

void main() {
  final requests = <http.Request>[];

  /// Pierwsze żądanie „ginie" (timeout po stronie klienta — serwer mógł je
  /// już przyjąć), kolejne dostają [ok].
  void flakyBackend(http.Response Function() ok) {
    var calls = 0;
    ApiClient.instance.debugSetClient(MockClient((r) async {
      requests.add(r);
      calls++;
      if (calls == 1) throw TimeoutException('brak odpowiedzi w 8 s');
      return ok();
    }));
  }

  setUp(() {
    requests.clear();
    SharedPreferences.setMockInitialValues({
      'fitter_device_id': '0123456789abcdef0123456789abcdef',
      'fitter_install_secret': 'AbCdEfGhIjKlMnOpQrStUvWxYz0123456789-_AbCdE',
      'user_profile_v1': jsonEncode({'firstName': 'Jan', 'lastName': 'Nowak'}),
    });
    PremiumService.instance.resetForTest();
    UserProfileService.instance.resetForTest();
  });

  tearDown(() => ApiClient.instance.debugSetClient(null));

  group('ApiClient.postJson', () {
    test('bez Idempotency-Key: timeout NIE jest ponawiany', () async {
      flakyBackend(() => _json(201, {'ok': true}));
      await expectLater(
        ApiClient.instance.postJson('/api/fitter/x', body: {'a': 1}),
        throwsA(isA<TimeoutException>()),
      );
      expect(requests, hasLength(1),
          reason: 'drugi POST mógłby zdublować zapis na serwerze');
    });

    test('bez Idempotency-Key: 503 też nie jest ponawiany', () async {
      ApiClient.instance.debugSetClient(MockClient((r) async {
        requests.add(r);
        return _json(503, {});
      }));
      await expectLater(
        ApiClient.instance.postJson('/api/fitter/x', body: {'a': 1}),
        throwsA(isA<ApiException>()),
      );
      expect(requests, hasLength(1));
    });

    test('z Idempotency-Key: jedno ponowienie z TYM SAMYM kluczem', () async {
      flakyBackend(() => _json(201, {'ok': true}));
      final body = await ApiClient.instance.postJson(
        '/api/fitter/x',
        body: {'a': 1},
        headers: {kIdempotencyKeyHeader: 'klucz-1'},
      );
      expect(body['ok'], isTrue);
      expect(requests, hasLength(2));
      expect(requests[0].headers[kIdempotencyKeyHeader], 'klucz-1');
      expect(requests[1].headers[kIdempotencyKeyHeader], 'klucz-1');
      expect(requests[1].body, requests[0].body);
    });

    test('GET dalej ponawia po timeoucie (odczyt jest bezpieczny)', () async {
      flakyBackend(() => _json(200, {'rooms': []}));
      await ApiClient.instance.getJson('/api/fitter/chat/rooms');
      expect(requests, hasLength(2));
    });
  });

  group('czat wysyła klucz idempotencji', () {
    test('wiadomość: UUID v4 w nagłówku, ten sam przy ponowieniu', () async {
      flakyBackend(() => _json(201, _message(7)));
      final msg = await ChatService.instance
          .postMessage(room: 'general', text: 'Jaki preheat na P91?');
      expect(msg.id, 7);
      expect(requests, hasLength(2), reason: 'jedno ponowienie po timeoucie');
      final key = requests.first.headers[kIdempotencyKeyHeader];
      expect(key, matches(_uuidV4));
      expect(requests.last.headers[kIdempotencyKeyHeader], key);
      expect(requests.first.url.path, '/api/fitter/chat/messages');
    });

    test('ponowienie z ekranu („Ponów") może podać ten sam klucz', () async {
      ApiClient.instance.debugSetClient(MockClient((r) async {
        requests.add(r);
        return _json(201, _message(8));
      }));
      await ChatService.instance.postMessage(
          room: 'general', text: 'Jaki preheat?', idempotencyKey: 'stały-klucz');
      expect(requests.single.headers[kIdempotencyKeyHeader], 'stały-klucz');
    });

    test('dwie różne wiadomości mają różne klucze', () async {
      ApiClient.instance.debugSetClient(MockClient((r) async {
        requests.add(r);
        return _json(201, _message(9));
      }));
      await ChatService.instance.postMessage(room: 'general', text: 'raz');
      await ChatService.instance.postMessage(room: 'general', text: 'dwa');
      expect(requests[0].headers[kIdempotencyKeyHeader],
          isNot(requests[1].headers[kIdempotencyKeyHeader]));
    });

    test('zgłoszenie: POST /chat/report z kluczem', () async {
      flakyBackend(() => _json(201, {'ok': true}));
      await ChatService.instance.report(42);
      expect(requests, hasLength(2));
      expect(requests.first.url.path, '/api/fitter/chat/report');
      final key = requests.first.headers[kIdempotencyKeyHeader];
      expect(key, matches(_uuidV4));
      expect(requests.last.headers[kIdempotencyKeyHeader], key);
    });
  });
}
