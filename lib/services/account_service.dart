import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import '../config/backend_config.dart';

/// Railway identity. Passwords are never persisted; session uses OS storage.
class AccountService extends ChangeNotifier {
  AccountService._()
      : _client = http.Client(),
        _storage = const FlutterSecureStorage(),
        _baseUrl = BackendConfig.baseUrl;
  @visibleForTesting
  AccountService.forTesting(this._client,
      {String baseUrl = 'http://localhost',
      FlutterSecureStorage storage = const FlutterSecureStorage()})
      : _baseUrl = baseUrl,
        _storage = storage;
  final http.Client _client;
  final String _baseUrl;
  static AccountService instance = AccountService._();
  final FlutterSecureStorage _storage;
  static const _key = 'railway_account_session_v1';
  Map<String, dynamic>? account;
  String? _token;
  Future<void>? _loading;
  bool _loaded = false;
  int _sessionRevision = 0;
  int _authEpoch = 0;
  Future<void>? _storageTail;

  Future<T> _stored<T>(Future<T> Function() operation) {
    final tail = _storageTail;
    final next = tail == null
        ? Future<T>.sync(operation)
        : tail.then((_) => operation());
    _storageTail =
        next.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return next;
  }

  void _requireSession(int revision) {
    if (revision != _sessionRevision) {
      throw AccountException(
          'Sesja zmieniła się. Spróbuj ponownie. / Session changed. Please try again.');
    }
  }

  /// Changes only when the authenticated session changes, never on profile edits.
  int get sessionRevision => _sessionRevision;
  bool get isAdmin => account?['role'] == 'admin';
  Future<void> load() {
    if (_loaded) return Future.value();
    return _loading ??= _restore().then((_) {
      _loaded = true;
    }).whenComplete(() {
      _loading = null;
    });
  }

  Future<void> _restore() async {
    final epoch = _authEpoch, revision = _sessionRevision;
    final stored = await _stored(() => _storage.read(key: _key));
    if (epoch != _authEpoch || revision != _sessionRevision) return;
    _token = stored;
    if (_token == null) return;
    _sessionRevision++;
    final restoredRevision = _sessionRevision;
    notifyListeners();
    try {
      final r = await request('GET', '/me');
      _requireSession(restoredRevision);
      account = Map<String, dynamic>.from(r['account'] as Map);
      notifyListeners();
    } catch (_) {
      // A network failure must not erase a valid session.
    }
  }

  Future<Map<String, String>> headers() async {
    await load();
    return {if (_token != null) 'Authorization': 'Bearer $_token'};
  }

  Future<Map<String, dynamic>> request(String method, String path,
      [Map<String, dynamic>? body]) async {
    final revision = _sessionRevision;
    final epoch = _authEpoch;
    final credentials = path == '/login' || path == '/register';
    final req =
        http.Request(method, Uri.parse('$_baseUrl/api/fitter/account$path'));
    req.headers.addAll({
      'Content-Type': 'application/json',
      if (_token != null) 'Authorization': 'Bearer $_token'
    });
    if (body != null) req.body = jsonEncode(body);
    final response = await http.Response.fromStream(
        await _client.send(req).timeout(const Duration(seconds: 20)));
    if (!credentials) _requireSession(revision);
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    if (response.statusCode >= 400) {
      if (response.statusCode == 401 &&
          !credentials &&
          epoch == _authEpoch &&
          path != '/password' &&
          method != 'DELETE') {
        await forgetSession();
      }
      throw AccountException(data['error']?['message'] as String? ??
          'Błąd serwera / Server error');
    }
    return data;
  }

  Future<void> signIn(String email, String password,
      {String? displayName}) async {
    final epoch = ++_authEpoch, revision = _sessionRevision;
    final r =
        await request('POST', displayName == null ? '/login' : '/register', {
      'email': email.trim(),
      'password': password,
      if (displayName != null) ...{
        'displayName': displayName.trim(),
        'legalVersion': 4
      },
    });
    final token = r['token'] as String;
    final identity = Map<String, dynamic>.from(r['account'] as Map);
    await _stored(() async {
      _requireSession(revision);
      if (epoch != _authEpoch) {
        throw AccountException('Logowanie anulowane / Sign-in cancelled');
      }
      await _storage.write(key: _key, value: token);
      if (epoch != _authEpoch || revision != _sessionRevision) {
        // This write cannot race another queued write. Restore the active
        // session if logout/a newer sign-in superseded it while storage waited.
        await _storage.write(key: _key, value: _token);
        throw AccountException('Logowanie anulowane / Sign-in cancelled');
      }
      _token = token;
      _loaded = true;
      account = identity;
      _sessionRevision++;
      notifyListeners();
    });
  }

  Future<void> saveProfile(Map<String, dynamic> profile) async {
    final revision = _sessionRevision;
    final r = await request('PUT', '/profile', profile);
    _requireSession(revision);
    account = Map<String, dynamic>.from(r['account'] as Map);
    notifyListeners();
  }

  Future<void> signOut() async {
    _authEpoch++;
    final revision = _sessionRevision;
    // Revoke server session before clearing its only local copy.
    await request('POST', '/logout');
    _requireSession(revision);
    await forgetSession();
  }

  Future<void> forgetSession() async {
    _authEpoch++;
    _loaded = true;
    _token = null;
    account = null;
    _sessionRevision++;
    final erased = _stored(() => _storage.delete(key: _key));
    notifyListeners();
    await erased;
  }
}

class AccountException implements Exception {
  final String message;
  AccountException(this.message);
  @override
  String toString() => message;
}
