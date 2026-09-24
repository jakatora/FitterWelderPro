// Czat na starym i nowym backendzie: kto jest autorem („moja" wiadomość),
// po czym blokujemy i jakie nagłówki idą na serwer. Atrapa HTTP — zero
// prawdziwych połączeń.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:cut_list_app/services/api_client.dart';
import 'package:cut_list_app/services/blocked_users.dart';
import 'package:cut_list_app/services/chat_service.dart';
import 'package:cut_list_app/services/premium_service.dart';
import 'package:cut_list_app/services/user_profile.dart';

const _myDevice = '0123456789abcdef0123456789abcdef';
const _secret = 'AbCdEfGhIjKlMnOpQrStUvWxYz0123456789-_AbCdE';
const _otherAuthor = 'a_11111111111111111111111111111111';

Map<String, dynamic> _newBackendMessage({
  required int id,
  required String deviceId,
  required bool mine,
  String authorId = _otherAuthor,
}) =>
    {
      'id': id,
      'room': 'general',
      'device_id': deviceId,
      'author_id': authorId,
      'nickname': 'Zbigniew Hałas',
      'text': 'Jaki preheat na P91?',
      'flags': 0,
      'created_at': '2026-09-24T10:00:00.000Z',
      'mine': mine,
    };

http.Response _json(int status, Object body) => http.Response(
      jsonEncode(body),
      status,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );

void main() {
  group('ChatMessage — nowy backend', () {
    test('cudza wiadomość: author_id zamiast device_id, mine=false', () {
      final m = ChatMessage.fromJson(_newBackendMessage(
          id: 1, deviceId: _otherAuthor, mine: false));
      expect(m.authorId, _otherAuthor);
      expect(m.mine, isFalse);
      expect(m.blockKey, _otherAuthor);
      expect(m.isMine(myDeviceId: _myDevice), isFalse);
    });

    test('własna wiadomość rozpoznana po mine, nie po porównaniu', () {
      final m = ChatMessage.fromJson(_newBackendMessage(
          id: 2, deviceId: _myDevice, mine: true, authorId: 'a_me'));
      expect(m.isMine(myDeviceId: _myDevice), isTrue);
      // Nawet zanim tożsamość jest w pamięci — serwer wie, kto pyta.
      expect(m.isMine(myDeviceId: ''), isTrue);
    });

    test('mine=false wygrywa z przypadkową zgodnością device_id', () {
      final m = ChatMessage.fromJson(
          _newBackendMessage(id: 3, deviceId: _myDevice, mine: false));
      expect(m.isMine(myDeviceId: _myDevice), isFalse);
    });
  });

  group('ChatMessage — stary backend (bez author_id i mine)', () {
    Map<String, dynamic> legacy(String deviceId) => {
          'id': 7,
          'room': 'general',
          'device_id': deviceId,
          'nickname': 'Jan',
          'text': 'Cześć',
          'flags': 1,
          'created_at': '2026-09-01T10:00:00.000Z',
        };

    test('własna po porównaniu device_id, blokada po device_id', () {
      final mine = ChatMessage.fromJson(legacy(_myDevice));
      expect(mine.authorId, isNull);
      expect(mine.mine, isNull);
      expect(mine.isMine(myDeviceId: _myDevice), isTrue);

      final other = ChatMessage.fromJson(legacy('dev-cudzy-123'));
      expect(other.isMine(myDeviceId: _myDevice), isFalse);
      expect(other.blockKey, 'dev-cudzy-123');
    });

    test('pusty własny device_id nie oznacza wszystkiego jako „moje"', () {
      final m = ChatMessage.fromJson(legacy(''));
      expect(m.isMine(myDeviceId: ''), isFalse);
    });

    test('author_id z rejestracji rozpoznaje własną wiadomość bez mine', () {
      final m = ChatMessage.fromJson({
        ...legacy('a_me'),
        'author_id': 'a_me',
      });
      expect(m.isMine(myDeviceId: _myDevice, myAuthorId: 'a_me'), isTrue);
    });
  });

  group('blokady po author_id', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
      BlockedUsers.instance.resetForTest();
    });

    test('stara blokada po device_id zostaje, nowa działa po author_id',
        () async {
      await BlockedUsers.instance.load();
      // Blokada sprzed zmiany — surowy device_id autora.
      await BlockedUsers.instance.block('dev-surowy-abc', 'Zbigniew Hałas');

      final fresh = ChatMessage.fromJson(_newBackendMessage(
          id: 9, deviceId: _otherAuthor, mine: false));
      // Nowy backend nie wydaje już surowych device_id — stara blokada nie
      // pasuje, ale NIE znika z listy.
      expect(
          BlockedUsers.instance.isBlockedAny([fresh.authorId, fresh.deviceId]),
          isFalse);
      expect(BlockedUsers.instance.isBlocked('dev-surowy-abc'), isTrue);

      await BlockedUsers.instance.block(fresh.blockKey, fresh.nickname);
      expect(
          BlockedUsers.instance.isBlockedAny([fresh.authorId, fresh.deviceId]),
          isTrue);
      expect(BlockedUsers.instance.all.map((u) => u.name),
          ['Zbigniew Hałas', 'Zbigniew Hałas']);
    });
  });

  group('nagłówki i błędy zapisu', () {
    final requests = <http.Request>[];

    setUp(() {
      requests.clear();
      SharedPreferences.setMockInitialValues({
        'fitter_device_id': _myDevice,
        'fitter_install_secret': _secret,
        'user_profile_v1':
            jsonEncode({'firstName': 'Marek', 'lastName': 'Kowalczyk'}),
      });
      PremiumService.instance.resetForTest();
      UserProfileService.instance.resetForTest();
    });

    tearDown(() => ApiClient.instance.debugSetClient(null));

    void backend(Future<http.Response> Function(http.Request) respond) {
      ApiClient.instance.debugSetClient(MockClient((r) async {
        requests.add(r);
        return respond(r);
      }));
    }

    test('odczyt pokoju wysyła X-Device-Id i X-Install-Secret (pole mine)',
        () async {
      backend((_) async => _json(200, {
            'messages': [
              _newBackendMessage(id: 1, deviceId: _myDevice, mine: true),
            ]
          }));
      final msgs = await ChatService.instance.listMessages('general');
      expect(msgs.single.mine, isTrue);
      expect(requests.single.method, 'GET');
      expect(requests.single.headers[kDeviceIdHeader], _myDevice);
      expect(requests.single.headers[kInstallSecretHeader], _secret);
    });

    test('wysłanie wiadomości: nagłówki + device_id i podpis w treści',
        () async {
      backend((r) async => _json(200, {
            'message': _newBackendMessage(
                id: 5, deviceId: _myDevice, mine: true, authorId: 'a_me'),
          }));
      final msg = await ChatService.instance
          .postMessage(room: 'general', text: 'Dzień dobry');
      final req = requests.single;
      expect(req.headers[kDeviceIdHeader], _myDevice);
      expect(req.headers[kInstallSecretHeader], _secret);
      expect(jsonDecode(req.body), {
        'room': 'general',
        'device_id': _myDevice,
        'nickname': 'Marek Kowalczyk',
        'text': 'Dzień dobry',
      });
      expect(msg.isMine(myDeviceId: _myDevice), isTrue);
    });

    test('401 INSTALL_SECRET_REQUIRED przy zgłoszeniu nie jest połykany',
        () async {
      backend((_) async => _json(401, {
            'error': {
              'code': 'INSTALL_SECRET_REQUIRED',
              'message': 'To urządzenie ma zarejestrowany sekret instalacji.'
            }
          }));
      Object? caught;
      try {
        await ChatService.instance.report(42);
      } catch (e) {
        caught = e;
      }
      expect(caught, isA<ApiException>());
      expect(classifyChatError(caught!), ChatFailure.installSecret);
      expect(requests.single.headers[kInstallSecretHeader], _secret);
      expect(jsonDecode(requests.single.body), {'id': 42, 'device_id': _myDevice});
    });

    test('klasyfikacja błędów czatu', () {
      ApiException api(int status, [String? code]) =>
          ApiException(statusCode: status, path: '/x', backendCode: code);
      expect(classifyChatError(api(401, 'INSTALL_SECRET_INVALID')),
          ChatFailure.installSecret);
      expect(classifyChatError(api(400, 'INSTALL_SECRET_MALFORMED')),
          ChatFailure.installSecret);
      expect(classifyChatError(api(429, 'RATE_LIMITED')),
          ChatFailure.rateLimited);
      expect(classifyChatError(api(400, 'BAD_REQUEST')), ChatFailure.rejected);
      expect(classifyChatError(api(500)), ChatFailure.server);
      expect(classifyChatError(api(401, 'UNAUTHORIZED')), ChatFailure.server);
      expect(classifyChatError(const SocketException('offline')),
          ChatFailure.offline);
      expect(classifyChatError(http.ClientException('x')), ChatFailure.offline);
    });
  });
}
