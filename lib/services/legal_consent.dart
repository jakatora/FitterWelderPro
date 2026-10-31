import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../legal/legal_texts.dart';

// Zapis akceptacji regulaminu i polityki prywatności.
//
// Apple przy treściach od użytkowników (wytyczna 1.2) wymaga, żeby użytkownik
// zgodził się na zasady ZANIM cokolwiek opublikuje. Trzymamy wersję zaakceptowanego
// dokumentu — podniesienie [kLegalVersion] wymusza ponowną zgodę u wszystkich,
// bo inaczej „akceptacja" dotyczyłaby tekstu, którego nikt nie widział.

class LegalConsent {
  LegalConsent._();
  static final LegalConsent instance = LegalConsent._();

  static const _kKey = 'legal_consent_v1';

  int? _acceptedVersion;
  DateTime? _acceptedAt;
  bool _hydrated = false;
  bool withdrawalPending = false;
  int _revision = 0;
  Future<void>? _writes;

  Future<T> _serial<T>(Future<T> Function() operation) {
    final previous = _writes;
    final pending =
        previous == null ? operation() : previous.then((_) => operation());
    final settled =
        pending.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    _writes = settled;
    settled.then((_) {
      if (identical(_writes, settled)) _writes = null;
    });
    return pending;
  }

  /// Dostęp synchroniczny dla `build()` — false, dopóki [load] nie przejdzie.
  bool get isAccepted =>
      _acceptedVersion != null && _acceptedVersion! >= kLegalVersion;

  DateTime? get acceptedAt => _acceptedAt;

  Future<void> load() async {
    if (_hydrated) return;
    final revision = _revision;
    try {
      final prefs = await SharedPreferences.getInstance();
      if (revision != _revision) return;
      final raw = prefs.getString(_kKey);
      if (raw != null && raw.isNotEmpty) {
        final decoded = jsonDecode(raw);
        if (decoded is Map) {
          final version = decoded['version'];
          final at = decoded['acceptedAt'];
          final acceptedAt = at is String ? DateTime.tryParse(at) : null;
          if (version is int && version > 0 && acceptedAt != null) {
            _acceptedVersion = version;
            _acceptedAt = acceptedAt;
          }
        }
      }
    } catch (_) {
      _acceptedVersion = null;
      _acceptedAt = null;
    } finally {
      _hydrated = true;
    }
  }

  Future<bool> accept() {
    _revision++;
    final now = DateTime.now();
    withdrawalPending = false;
    _acceptedVersion = kLegalVersion;
    _acceptedAt = now;
    _hydrated = true;
    return _serial(() async {
      try {
        final prefs = await SharedPreferences.getInstance();
        final raw = jsonEncode(
            {'version': kLegalVersion, 'acceptedAt': now.toIso8601String()});
        if (!await prefs.setString(_kKey, raw)) return false;
        await prefs.reload();
        return prefs.getString(_kKey) == raw;
      } catch (_) {
        // Zgoda obowiązuje w tej sesji nawet, gdy zapis padnie — nie blokujemy
        // użytkownika, ale przy następnym starcie zapytamy ponownie.
        return false;
      }
    });
  }

  Future<bool> clear() {
    final revision = ++_revision;
    withdrawalPending = true;
    _acceptedVersion = null;
    _acceptedAt = null;
    _hydrated = true;
    return _serial(() async {
      try {
        final prefs = await SharedPreferences.getInstance();
        if (!await prefs.remove(_kKey)) return false;
        await prefs.reload();
        final cleared = !prefs.containsKey(_kKey);
        if (revision == _revision) withdrawalPending = !cleared;
        return cleared;
      } catch (_) {
        return false;
      }
    });
  }

  /// Tylko do testów.
  void resetForTest() {
    _acceptedVersion = null;
    _acceptedAt = null;
    _hydrated = false;
    withdrawalPending = false;
    _revision = 0;
    _writes = null;
  }
}
