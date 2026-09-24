// DELETE /api/fitter/me — każdy wynik serwera (nowy i stary backend) daje
// konkretny status, nigdy wyjątek. Atrapa HTTP, zero prawdziwych połączeń.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:cut_list_app/services/api_client.dart';
import 'package:cut_list_app/services/premium_service.dart';
import 'package:cut_list_app/services/server_data_deletion.dart';

const _deviceId = '0123456789abcdef0123456789abcdef';
const _secret = 'AbCdEfGhIjKlMnOpQrStUvWxYz0123456789-_AbCdE';

http.Response _json(int status, Object body) => http.Response(
      jsonEncode(body),
      status,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );

void main() {
  final requests = <http.Request>[];

  void backend(Future<http.Response> Function(http.Request) respond) {
    ApiClient.instance.debugSetClient(MockClient((r) async {
      requests.add(r);
      return respond(r);
    }));
  }

  setUp(() {
    requests.clear();
    SharedPreferences.setMockInitialValues({
      'fitter_device_id': _deviceId,
      'fitter_install_secret': _secret,
    });
    PremiumService.instance.resetForTest();
  });

  tearDown(() => ApiClient.instance.debugSetClient(null));

  test('200: DELETE /api/fitter/me z nagłówkami, liczniki z odpowiedzi',
      () async {
    backend((_) async => _json(200, {
          'ok': true,
          'deleted': {
            'chat_messages': 2,
            'chat_reports': 1,
            'job_listings': 0,
            'device_secret': 1,
            'rate_counters': 3,
            'premium': 0,
          },
          'premium_retained': false,
          'message': 'Usunęliśmy Twoje dane z serwera.',
        }));

    final r = await ServerDataDeletion.deleteMyServerData();

    expect(r.status, ServerDeletionStatus.deleted);
    expect(r.serverDataDeleted, isTrue);
    expect(r.count('chat_messages'), 2);
    expect(r.count('chat_reports'), 1);
    expect(r.count('device_secret'), 1);
    expect(r.premiumRetained, isFalse);
    final req = requests.single;
    expect(req.method, 'DELETE');
    expect(req.url.path, '/api/fitter/me');
    expect(req.headers[kDeviceIdHeader], _deviceId);
    expect(req.headers[kInstallSecretHeader], _secret);
  });

  test('premium_retained przechodzi do wyniku', () async {
    backend((_) async => _json(200, {
          'ok': true,
          'deleted': {'chat_messages': 0},
          'premium_retained': true,
          'message': 'x',
        }));
    final r = await ServerDataDeletion.deleteMyServerData();
    expect(r.premiumRetained, isTrue);
  });

  test('404 starego backendu → notSupported', () async {
    backend((_) async => http.Response('Cannot DELETE /api/fitter/me', 404));
    final r = await ServerDataDeletion.deleteMyServerData();
    expect(r.status, ServerDeletionStatus.notSupported);
  });

  test('429 → rateLimited', () async {
    backend((_) async => _json(429, {
          'error': {'code': 'RATE_LIMITED', 'message': 'Za dużo żądań'}
        }));
    final r = await ServerDataDeletion.deleteMyServerData();
    expect(r.status, ServerDeletionStatus.rateLimited);
  });

  test('401 INSTALL_SECRET_INVALID → rejected', () async {
    backend((_) async => _json(401, {
          'error': {'code': 'INSTALL_SECRET_INVALID', 'message': 'x'}
        }));
    final r = await ServerDataDeletion.deleteMyServerData();
    expect(r.status, ServerDeletionStatus.rejected);
  });

  test('brak sieci → offline, bez wyjątku', () async {
    backend((_) async => throw http.ClientException('brak zasięgu'));
    final r = await ServerDataDeletion.deleteMyServerData();
    expect(r.status, ServerDeletionStatus.offline);
  });

  test('500 → failed', () async {
    backend((_) async => _json(500, {
          'error': {'code': 'SERVER_ERROR', 'message': 'x'}
        }));
    final r = await ServerDataDeletion.deleteMyServerData();
    expect(r.status, ServerDeletionStatus.failed);
  });

  test('bez zapisanego device_id nic nie wysyła', () async {
    SharedPreferences.setMockInitialValues({});
    PremiumService.instance.resetForTest();
    backend((_) async => _json(200, {'ok': true}));
    final r = await ServerDataDeletion.deleteMyServerData();
    expect(r.status, ServerDeletionStatus.nothingToDelete);
    expect(requests, isEmpty);
  });
}
