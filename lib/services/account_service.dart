import '../legal/legal_version.dart';
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
  static const _ownerKey = 'railway_account_local_owner_v1';
  Map<String, dynamic>? account;
  String? _token;
  String? _localOwnerId;

  /// Previously verified ID bound to this exact OS-stored session token.
  /// For local data partitioning only; never grants server access/admin role.
  String? get localOwnerId => _localOwnerId;

  Future<void> _writeOwnerCache(String? token, String? id) async {
    try {
      if (token == null || id == null) {
        await _storage.delete(key: _ownerKey);
      } else {
        await _storage.write(
            key: _ownerKey, value: jsonEncode({'token': token, 'id': id}));
      }
    } catch (_) {
      // Optional offline cache: failure must not break sign-in. A stale cache
      // cannot match a different token and is ignored during restoration.
    }
  }

  Future<void>? _loading;
  bool _loaded = false;
  int _sessionRevision = 0;
  int _profileRevision = 0;
  int get profileRevision => _profileRevision;
  int _authEpoch = 0;
  final Set<Future<VoidCallback> Function()> _sessionPreparers = {};
  Future<void>? _sessionChangeTail;

  /// Local editors can flush and freeze their old-owner data before an explicit
  /// session replacement. The returned callback unlocks after success/failure.
  void addSessionPreparer(Future<VoidCallback> Function() prepare) =>
      _sessionPreparers.add(prepare);
  void removeSessionPreparer(Future<VoidCallback> Function() prepare) =>
      _sessionPreparers.remove(prepare);

  Future<List<VoidCallback>> _prepareSessionData(void Function() validate) {
    Future<List<VoidCallback>> prepare() async {
      validate();
      final releases = <VoidCallback>[];
      try {
        for (final prepareEditor in List.of(_sessionPreparers)) {
          releases.add(await prepareEditor());
        }
        validate();
        return releases;
      } catch (_) {
        for (final release in releases.reversed) {
          release();
        }
        rethrow;
      }
    }

    final tail = _sessionChangeTail;
    final result = tail == null
        ? Future<List<VoidCallback>>.sync(prepare)
        : tail.then((_) => prepare());
    _sessionChangeTail = result.then<void>((_) {}, onError: (Object _) {});
    return result;
  }

  Future<T> _withPreparedSession<T>(Future<T> Function() change,
      {required void Function() validate}) async {
    // Serialize local preparation only. A superseding sign-in must not wait
    // for an obsolete logout HTTP response; token writes remain serialized.
    final releases = await _prepareSessionData(validate);
    try {
      validate();
      return await change();
    } finally {
      for (final release in releases.reversed) {
        release();
      }
    }
  }

  void _validateTransition(int epoch, int revision) {
    _requireSession(revision);
    if (epoch != _authEpoch) {
      throw AccountException(
          'Zmiana konta anulowana / Account change cancelled');
    }
  }

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

  /// A retained token whose identity could not yet be verified, e.g. offline.
  bool get needsIdentityRefresh => _token != null && account == null;

  Future<void> refreshIdentity() async {
    await load();
    if (!needsIdentityRefresh) return;
    final revision = _sessionRevision;
    final response = await request('GET', '/me');
    _requireSession(revision);
    account = Map<String, dynamic>.from(response['account'] as Map);
    await _cacheVerifiedOwner(revision);
    notifyListeners();
  }

  Future<void> _cacheVerifiedOwner(int revision) async {
    final id = account?['id'];
    _localOwnerId = id is String && id.isNotEmpty ? id : null;
    await _stored(() async {
      _requireSession(revision);
      await _writeOwnerCache(_token, _localOwnerId);
      if (revision != _sessionRevision) {
        await _writeOwnerCache(_token, _localOwnerId);
      }
    });
    _requireSession(revision);
  }

  Future<void> refreshProfile() async {
    final revision = _sessionRevision, owner = account?['id'];
    if (owner == null) throw AccountException('Zaloguj się / Sign in');
    final response = await request('GET', '/me');
    _requireSession(revision);
    final updated = response['account'];
    if (updated is! Map || updated['id'] != owner) {
      throw AccountException(
          'Nie potwierdzono profilu / Profile was not confirmed');
    }
    account = Map<String, dynamic>.from(updated);
    _profileRevision++;
    notifyListeners();
  }

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
    String? cached;
    try {
      cached = await _stored(() => _storage.read(key: _ownerKey));
    } catch (_) {/* optional */}
    if (epoch != _authEpoch || revision != _sessionRevision) return;
    try {
      final owner = jsonDecode(cached ?? '{}');
      final id = owner is Map && owner['token'] == stored ? owner['id'] : null;
      _localOwnerId = id is String && id.isNotEmpty ? id : null;
    } catch (_) {
      _localOwnerId = null;
    }
    _sessionRevision++;
    final restoredRevision = _sessionRevision;
    notifyListeners();
    try {
      final r = await request('GET', '/me');
      _requireSession(restoredRevision);
      account = Map<String, dynamic>.from(r['account'] as Map);
      await _cacheVerifiedOwner(restoredRevision);
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
        await _eraseSession();
      }
      throw AccountException(
          data['error']?['message'] as String? ?? 'Błąd serwera / Server error',
          status: response.statusCode);
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
        'legalVersion': kLegalVersion
      },
    });
    final token = r['token'] as String;
    final identity = Map<String, dynamic>.from(r['account'] as Map);
    await _withPreparedSession(
        () => _stored(() async {
              _requireSession(revision);
              if (epoch != _authEpoch) {
                throw AccountException(
                    'Logowanie anulowane / Sign-in cancelled');
              }
              await _storage.write(key: _key, value: token);
              final id = identity['id'];
              await _writeOwnerCache(
                  token, id is String && id.isNotEmpty ? id : null);
              if (epoch != _authEpoch || revision != _sessionRevision) {
                // This write cannot race another queued write. Restore the active
                // session if logout/a newer sign-in superseded it while storage waited.
                await _storage.write(key: _key, value: _token);
                await _writeOwnerCache(_token, _localOwnerId);
                throw AccountException(
                    'Logowanie anulowane / Sign-in cancelled');
              }
              _token = token;
              _localOwnerId = id is String && id.isNotEmpty ? id : null;
              _loaded = true;
              account = identity;
              _sessionRevision++;
              notifyListeners();
            }),
        validate: () => _validateTransition(epoch, revision));
  }

  Future<void> saveProfile(Map<String, dynamic> profile) async {
    final revision = _sessionRevision;
    final r = await request('PUT', '/profile', profile);
    _requireSession(revision);
    account = Map<String, dynamic>.from(r['account'] as Map);
    _profileRevision++;
    notifyListeners();
  }

  /// A confirmed professional edit never sends unrelated profile fields.
  Future<void> saveProfessionalProfileField(
      String field, Object value, Object expected) async {
    final revision = _sessionRevision, owner = account?['id'];
    if (owner == null ||
        !const {'profession', 'experienceYears'}.contains(field)) {
      throw AccountException(
          'Nieprawidłowa zmiana profilu / Invalid profile change');
    }
    final response = await request('POST', '/profile/assistant',
        {'field': field, 'value': value, 'expected': expected});
    _requireSession(revision);
    final updated = response['account'];
    if (updated is! Map || updated['id'] != owner || updated[field] != value) {
      throw AccountException(
          'Nie potwierdzono zmiany profilu / Profile change was not confirmed');
    }
    account = Map<String, dynamic>.from(updated);
    _profileRevision++;
    notifyListeners();
  }

  Future<void> signOut() async {
    final epoch = ++_authEpoch, revision = _sessionRevision;
    await _withPreparedSession(() async {
      // Flush succeeds before revoking the only server credential we hold.
      await request('POST', '/logout');
      _validateTransition(epoch, revision);
      await _eraseSession();
    }, validate: () => _validateTransition(epoch, revision));
  }

  Future<void> forgetSession() async {
    final epoch = ++_authEpoch, revision = _sessionRevision;
    await _withPreparedSession(_eraseSession,
        validate: () => _validateTransition(epoch, revision));
  }

  /// The server has already revoked/deleted this identity. Local write errors
  /// must not keep a revoked identity active or block credential erasure.
  Future<void> invalidateSession() => _eraseSession();

  Future<void> _eraseSession() async {
    _authEpoch++;
    _loaded = true;
    _token = null;
    _localOwnerId = null;
    account = null;
    _sessionRevision++;
    final erased = _stored(() async {
      await _storage.delete(key: _key);
      await _writeOwnerCache(null, null);
    });
    notifyListeners();
    await erased;
  }
}

class AccountException implements Exception {
  final String message;
  final int? status;
  AccountException(this.message, {this.status});
  @override
  String toString() => message;
}
