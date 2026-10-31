import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../legal/legal_texts.dart';

/// Zapis zgody na wysyłkę zdjęć do skanera.
class ScanConsent {
  ScanConsent._();

  static const String prefsKey = 'iso_scan_consent_v1';

  static int? _acceptedVersion;
  static DateTime? _acceptedAt;
  static bool _hydrated = false;
  static int _revision = 0;
  static bool withdrawalPending = false;
  static Future<void>? _writes;

  static Future<T> _serial<T>(Future<T> Function() operation) {
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

  static bool get isAccepted =>
      _acceptedVersion != null && _acceptedVersion! >= kLegalVersion;

  /// Kiedy monter zgodził się na wysyłkę zdjęć (do sekcji „Zgody" w profilu).
  static DateTime? get acceptedAt => isAccepted ? _acceptedAt : null;

  static Future<void> load() async {
    if (_hydrated) return;
    final revision = _revision;
    try {
      final prefs = await SharedPreferences.getInstance();
      if (revision != _revision) return;
      final raw = prefs.getString(prefsKey);
      if (raw != null && raw.isNotEmpty) {
        final decoded = jsonDecode(raw);
        if (decoded is Map) {
          final version = decoded['version'];
          final at = decoded['acceptedAt'];
          final acceptedAt = at is String ? DateTime.tryParse(at) : null;
          // Incomplete or malformed records do not prove prior consent.
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

  static Future<void> accept() {
    _revision++;
    withdrawalPending = false;
    _acceptedVersion = kLegalVersion;
    final acceptedAt = DateTime.now();
    _acceptedAt = acceptedAt;
    _hydrated = true;
    return _serial(() async {
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(
          prefsKey,
          jsonEncode({
            'version': kLegalVersion,
            'acceptedAt': acceptedAt.toIso8601String(),
          }),
        );
      } catch (_) {
        // Zgoda obowiązuje w tej sesji; przy następnym starcie zapytamy znowu.
      }
    });
  }

  /// Wycofanie blokuje zgodę od razu; usunięcie czeka na wcześniejsze zapisy.
  static Future<bool> clear() {
    final revision = ++_revision;
    withdrawalPending = true;
    _acceptedVersion = null;
    _acceptedAt = null;
    _hydrated = true;
    return _serial(() async {
      try {
        final prefs = await SharedPreferences.getInstance();
        if (!await prefs.remove(prefsKey)) return false;
        await prefs.reload();
        final cleared = !prefs.containsKey(prefsKey);
        if (revision == _revision) withdrawalPending = !cleared;
        return cleared;
      } catch (_) {
        // Stan w pamięci już wyczyszczony — w tej sesji skaner zapyta znowu.
        return false;
      }
    });
  }

  /// Tylko do testów.
  static void resetForTest() {
    _acceptedAt = null;
    _acceptedVersion = null;
    _hydrated = false;
    _revision = 0;
    withdrawalPending = false;
    _writes = null;
  }
}
