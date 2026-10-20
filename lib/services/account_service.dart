import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import '../config/backend_config.dart';

/// Railway identity. Passwords are never persisted; session uses OS storage.
class AccountService extends ChangeNotifier {
  AccountService._()
      : _client = http.Client(),
        _baseUrl = BackendConfig.baseUrl;
  @visibleForTesting
  AccountService.forTesting(this._client, {String baseUrl = 'http://localhost'})
      : _baseUrl = baseUrl;
  final http.Client _client;
  final String _baseUrl;
  static AccountService instance = AccountService._();
  static const _storage = FlutterSecureStorage();
  static const _key = 'railway_account_session_v1';
  Map<String, dynamic>? account;
  String? _token;
  Future<void>? _loading;
  bool _loaded = false;
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
    _token = await _storage.read(key: _key);
    if (_token == null) return;
    try {
      final r = await request('GET', '/me');
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
    final req =
        http.Request(method, Uri.parse('$_baseUrl/api/fitter/account$path'));
    req.headers.addAll({
      'Content-Type': 'application/json',
      if (_token != null) 'Authorization': 'Bearer $_token'
    });
    if (body != null) req.body = jsonEncode(body);
    final response = await http.Response.fromStream(
        await _client.send(req).timeout(const Duration(seconds: 20)));
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    if (response.statusCode >= 400) {
      if (response.statusCode == 401 &&
          path != '/login' &&
          path != '/password' &&
          method != 'DELETE') {
        _token = null;
        account = null;
        await _storage.delete(key: _key);
        notifyListeners();
      }
      throw AccountException(data['error']?['message'] as String? ??
          'Błąd serwera / Server error');
    }
    return data;
  }

  Future<void> signIn(String email, String password,
      {String? displayName}) async {
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
    await _storage.write(key: _key, value: token);
    _token = token;
    _loaded = true;
    account = Map<String, dynamic>.from(r['account'] as Map);
    notifyListeners();
  }

  Future<void> saveProfile(Map<String, dynamic> profile) async {
    final r = await request('PUT', '/profile', profile);
    account = Map<String, dynamic>.from(r['account'] as Map);
    notifyListeners();
  }

  Future<void> signOut() async {
    // Revoke server session before clearing its only local copy.
    await request('POST', '/logout');
    await forgetSession();
  }

  Future<void> forgetSession() async {
    await _storage.delete(key: _key);
    _token = null;
    account = null;
    notifyListeners();
  }
}

class AccountException implements Exception {
  final String message;
  AccountException(this.message);
  @override
  String toString() => message;
}
