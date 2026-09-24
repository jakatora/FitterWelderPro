// Tożsamość instalacji pod zabezpieczony backend (kontrakt z 2026-09-24):
// device_id + sekret instalacji, rejestracja TOFU i to, że NIC nie wychodzi na
// serwer przed zgodą na zasady czatu.
//
// Transport HTTP to atrapa (MockClient) — żaden test nie łączy się z serwerem.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:cut_list_app/config/feature_flags.dart';
import 'package:cut_list_app/legal/legal_texts.dart';
import 'package:cut_list_app/services/api_client.dart';
import 'package:cut_list_app/services/chat_service.dart';
import 'package:cut_list_app/services/legal_consent.dart';
import 'package:cut_list_app/services/premium_service.dart';
import 'package:cut_list_app/services/user_profile.dart';

/// Ten sam wzorzec, którego używa backend (`deviceAuth.js`).
final _backendSecretFormat = RegExp(r'^[A-Za-z0-9_\-+/=]{32,256}$');

const _deviceId = '0123456789abcdef0123456789abcdef';
const _secret = 'AbCdEfGhIjKlMnOpQrStUvWxYz0123456789-_AbCdE';

/// Atrapa backendu: zapisuje żądania, odpowiada tym, co zwróci [respond].
class _FakeBackend {
  _FakeBackend(this.respond);

  final Future<http.Response> Function(http.Request request) respond;
  final List<http.Request> requests = [];

  MockClient get client => MockClient((request) async {
        requests.add(request);
        return respond(request);
      });
}

http.Response _json(int status, Object body) => http.Response(
      jsonEncode(body),
      status,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );

void _seed(Map<String, Object> values) {
  SharedPreferences.setMockInitialValues(values);
  PremiumService.instance.resetForTest();
  UserProfileService.instance.resetForTest();
  LegalConsent.instance.resetForTest();
}

void main() {
  tearDown(() => ApiClient.instance.debugSetClient(null));

  group('sekret instalacji', () {
    test('32 losowe bajty w base64url = 43 znaki, format akceptowany przez backend',
        () {
      final a = PremiumService.generateInstallSecret();
      final b = PremiumService.generateInstallSecret();
      expect(a.length, 43);
      expect(a, matches(RegExp(r'^[A-Za-z0-9_-]{43}$')));
      expect(_backendSecretFormat.hasMatch(a), isTrue);
      expect(base64Url.decode('$a='), hasLength(32));
      expect(a, isNot(b), reason: 'dwa sekrety nie mogą być takie same');
    });

    test('świeża instalacja: device_id i sekret powstają razem i są trwałe',
        () async {
      _seed({});
      await PremiumService.instance.init();
      final id = PremiumService.instance.deviceId;
      final secret = PremiumService.instance.installSecret;
      expect(id, matches(RegExp(r'^[0-9a-f]{32}$')));
      expect(PremiumService.isValidInstallSecret(secret), isTrue);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('fitter_device_id'), id);
      expect(prefs.getString('fitter_install_secret'), secret);

      // Zimny start: ta sama para z dysku.
      PremiumService.instance.resetForTest();
      await PremiumService.instance.init();
      expect(PremiumService.instance.deviceId, id);
      expect(PremiumService.instance.installSecret, secret);
    });

    test('aktualizacja z 0.2.0: device_id zostaje, sekret dochodzi', () async {
      _seed({'fitter_device_id': _deviceId});
      await PremiumService.instance.init();
      expect(PremiumService.instance.deviceId, _deviceId);
      expect(PremiumService.isValidInstallSecret(
          PremiumService.instance.installSecret), isTrue);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('fitter_install_secret'),
          PremiumService.instance.installSecret);
    });

    test('zgubiony device_id = nowa tożsamość, także nowy sekret', () async {
      _seed({'fitter_install_secret': _secret});
      await PremiumService.instance.init();
      expect(PremiumService.instance.installSecret, isNot(_secret));
      expect(PremiumService.instance.deviceId, isNot(_deviceId));
    });

    test('współbieżne init() widzą ten sam, zapisany device_id', () async {
      _seed({});
      final ids = <String>[];
      await Future.wait(List.generate(5, (_) async {
        await PremiumService.instance.init();
        ids.add(PremiumService.instance.deviceId);
      }));
      expect(ids.toSet(), hasLength(1));
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('fitter_device_id'), ids.first);
    });

    test('nagłówki X-Device-Id i X-Install-Secret', () async {
      _seed({'fitter_device_id': _deviceId, 'fitter_install_secret': _secret});
      final headers = await PremiumService.instance.authHeaders();
      expect(headers, {
        kDeviceIdHeader: _deviceId,
        kInstallSecretHeader: _secret,
      });
    });

    test('resetIdentity: nowa para, author_id znika — bez żadnego żądania',
        () async {
      final backend = _FakeBackend((_) async => _json(500, {}));
      ApiClient.instance.debugSetClient(backend.client);
      _seed({
        'fitter_device_id': _deviceId,
        'fitter_install_secret': _secret,
        'fitter_author_id': 'a_0123',
      });
      await PremiumService.instance.init();
      expect(PremiumService.instance.authorId, 'a_0123');

      await PremiumService.instance.resetIdentity();
      expect(PremiumService.instance.deviceId, isNot(_deviceId));
      expect(PremiumService.instance.installSecret, isNot(_secret));
      expect(PremiumService.instance.authorId, isNull);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('fitter_device_id'), PremiumService.instance.deviceId);
      expect(prefs.getString('fitter_author_id'), isNull);
      expect(backend.requests, isEmpty);
    });
  });

  group('rejestracja urządzenia (POST /api/fitter/device/register)', () {
    setUp(() => _seed({
          'fitter_device_id': _deviceId,
          'fitter_install_secret': _secret,
        }));

    test('201: wysyła oba nagłówki i device_id, zapisuje author_id', () async {
      final backend = _FakeBackend((_) async =>
          _json(201, {'registered': true, 'author_id': 'a_${'f' * 32}'}));
      ApiClient.instance.debugSetClient(backend.client);

      final result = await PremiumService.instance.registerDevice();

      expect(result, DeviceRegistration.registered);
      final req = backend.requests.single;
      expect(req.method, 'POST');
      expect(req.url.path, '/api/fitter/device/register');
      expect(req.headers[kDeviceIdHeader], _deviceId);
      expect(req.headers[kInstallSecretHeader], _secret);
      expect(jsonDecode(req.body), {'device_id': _deviceId});
      expect(PremiumService.instance.authorId, 'a_${'f' * 32}');
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('fitter_author_id'), 'a_${'f' * 32}');
    });

    test('200 registered:false — już powiązane; drugi raz w sesji nie pyta',
        () async {
      final backend = _FakeBackend((_) async =>
          _json(200, {'registered': false, 'author_id': 'a_1'}));
      ApiClient.instance.debugSetClient(backend.client);

      expect(await PremiumService.instance.registerDevice(),
          DeviceRegistration.alreadyRegistered);
      expect(await PremiumService.instance.registerDevice(),
          DeviceRegistration.alreadyRegistered);
      expect(backend.requests, hasLength(1));
    });

    test('404 starego backendu: po cichu, bez wyjątku', () async {
      final backend = _FakeBackend((_) async => _json(404, {
            'error': {'code': 'NOT_FOUND', 'message': 'Nie znaleziono zasobu'}
          }));
      ApiClient.instance.debugSetClient(backend.client);

      expect(await PremiumService.instance.registerDevice(),
          DeviceRegistration.legacyBackend);
      expect(PremiumService.instance.authorId, isNull);
    });

    test('401 INSTALL_SECRET_INVALID: odrzucone, bez wyjątku', () async {
      final backend = _FakeBackend((_) async => _json(401, {
            'error': {
              'code': 'INSTALL_SECRET_INVALID',
              'message': 'Nieprawidłowy sekret instalacji dla tego urządzenia.'
            }
          }));
      ApiClient.instance.debugSetClient(backend.client);

      expect(await PremiumService.instance.registerDevice(),
          DeviceRegistration.rejected);
    });

    test('błąd sieci: failed, a następne wejście próbuje ponownie', () async {
      var calls = 0;
      final backend = _FakeBackend((_) async {
        calls++;
        if (calls == 1) throw http.ClientException('brak zasięgu');
        return _json(200, {'registered': false, 'author_id': 'a_2'});
      });
      ApiClient.instance.debugSetClient(backend.client);

      expect(await PremiumService.instance.registerDevice(),
          DeviceRegistration.failed);
      expect(await PremiumService.instance.registerDevice(),
          DeviceRegistration.alreadyRegistered);
      expect(calls, 2);
    });
  });

  group('nic nie wychodzi przed zgodą', () {
    late _FakeBackend backend;

    setUp(() {
      backend = _FakeBackend(
          (_) async => _json(201, {'registered': true, 'author_id': 'a_3'}));
      ApiClient.instance.debugSetClient(backend.client);
    });

    test('start aplikacji bez zgody na czat: zero żądań', () async {
      _seed({
        'fitter_device_id': _deviceId,
        'fitter_install_secret': _secret,
        // Profil jest (np. imię wpisane w profilu), zgody nie ma.
        'user_profile_v1': jsonEncode({'firstName': 'Jan', 'lastName': 'Nowak'}),
      });
      expect(await ChatService.instance.registerDeviceIfConsented(), isNull);
      expect(backend.requests, isEmpty);
    });

    test('zgoda na STARĄ wersję zasad też nie wystarcza', () async {
      _seed({
        'fitter_device_id': _deviceId,
        'fitter_install_secret': _secret,
        'user_profile_v1': jsonEncode({'firstName': 'Jan', 'lastName': 'Nowak'}),
        'legal_consent_v1': jsonEncode({
          'version': kLegalVersion - 1,
          'acceptedAt': '2026-07-09T12:00:00.000',
        }),
      });
      expect(await ChatService.instance.registerDeviceIfConsented(), isNull);
      expect(backend.requests, isEmpty);
    });

    test('po zgodzie: dokładnie jedna rejestracja z nagłówkami', () async {
      _seed({
        'fitter_device_id': _deviceId,
        'fitter_install_secret': _secret,
        'user_profile_v1': jsonEncode({'firstName': 'Jan', 'lastName': 'Nowak'}),
        'legal_consent_v1': jsonEncode({
          'version': kLegalVersion,
          'acceptedAt': '2026-09-24T12:00:00.000',
        }),
      });
      expect(await ChatService.instance.registerDeviceIfConsented(),
          DeviceRegistration.registered);
      expect(backend.requests.single.url.path, '/api/fitter/device/register');
      expect(backend.requests.single.headers[kInstallSecretHeader], _secret);
    });

    test('płatny plan wyłączony: odświeżenie Premium przy starcie nic nie wysyła',
        () async {
      expect(kPaidFeaturesEnabled, isFalse,
          reason: 'ten test pinuje zachowanie przy wyłączonych płatnościach');
      _seed({'fitter_device_id': _deviceId, 'fitter_install_secret': _secret});
      await PremiumService.instance.init();
      await PremiumService.instance.refreshFromBackend();
      expect(
        await PremiumService.instance.createCheckoutSession(
          plan: PremiumPlan.monthly,
          deviceId: _deviceId,
        ),
        isNull,
      );
      expect(await PremiumService.instance.createPortalSession(), isNull);
      expect(await PremiumService.instance.reactivateSubscription(), isFalse);
      expect(backend.requests, isEmpty);
    });
  });
}
