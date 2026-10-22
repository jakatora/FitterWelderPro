import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'account_service.dart';

/// Device preference, separate for each account and disabled by default.
/// The client sends only an opt-in and session; the server selects profile data.
class AiProfessionalContext extends ChangeNotifier {
  AiProfessionalContext._();
  static final instance = AiProfessionalContext._();
  static const _key = 'ai_professional_profile_accounts_v1';
  final Set<String> _enabled = {};
  Future<void>? _loading;
  bool _loaded = false;
  int _revision = 0;
  Future<void>? _saving;

  Future<void> load() {
    if (_loaded) return Future<void>.value();
    return _loading ??= _load().whenComplete(() {
      _loaded = true;
      _loading = null;
    });
  }

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _enabled.addAll(prefs.getStringList(_key) ?? const []);
    } catch (_) {
      // Unreadable consent never opts a user in or blocks ordinary AI use.
      _enabled.clear();
    }
  }

  bool get enabled {
    final id = AccountService.instance.account?['id'];
    return id is String && _enabled.contains(id);
  }

  Future<void> setEnabled(bool value) {
    final account = AccountService.instance;
    final revision = account.sessionRevision;
    final id = account.account?['id'];
    final next = (_saving ?? Future<void>.value())
        .then((_) => _setEnabled(value, account, revision, id));
    _saving = next.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return next;
  }

  Future<void> _setEnabled(
      bool value, AccountService account, int revision, Object? id) async {
    await load();
    if (id is! String || id.isEmpty) {
      throw AccountException('Zaloguj się ponownie. / Please sign in again.');
    }
    final prefs = await SharedPreferences.getInstance();
    if (!identical(account, AccountService.instance) ||
        revision != account.sessionRevision) {
      throw AccountException('Sesja zmieniła się. / Session changed.');
    }
    final next = {..._enabled};
    value ? next.add(id) : next.remove(id);
    if (!await prefs.setStringList(_key, next.toList())) {
      throw AccountException(
          'Nie zapisano ustawienia. / Setting was not saved.');
    }
    _enabled
      ..clear()
      ..addAll(next);
    _revision++;
    notifyListeners();
  }

  Future<AiProfessionalRequest> capture() async {
    final account = AccountService.instance;
    final session = account.sessionRevision;
    await load();
    final capture = AiProfessionalRequest._(account, session, _revision,
        enabled, enabled ? await account.headers() : const {});
    capture.requireCurrent();
    return capture;
  }

  @visibleForTesting
  void resetForTest() {
    _enabled.clear();
    _loading = null;
    _loaded = false;
    _saving = null;
    _revision++;
  }
}

class AiProfessionalRequest {
  AiProfessionalRequest._(
      this._account, this._session, this._revision, this.enabled, this.headers);
  final AccountService _account;
  final int _session, _revision;
  final bool enabled;
  final Map<String, String> headers;
  Map<String, Object> get body =>
      {if (enabled) 'use_professional_profile': true};
  void requireCurrent() {
    if (!identical(_account, AccountService.instance) ||
        _session != _account.sessionRevision ||
        _revision != AiProfessionalContext.instance._revision) {
      throw AccountException(
          'Sesja lub zgoda na profil AI zmieniła się. / Session or AI profile consent changed.');
    }
  }
}
