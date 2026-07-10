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

  /// Dostęp synchroniczny dla `build()` — false, dopóki [load] nie przejdzie.
  bool get isAccepted =>
      _acceptedVersion != null && _acceptedVersion! >= kLegalVersion;

  DateTime? get acceptedAt => _acceptedAt;

  Future<void> load() async {
    if (_hydrated) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_kKey);
      if (raw != null && raw.isNotEmpty) {
        final decoded = jsonDecode(raw);
        if (decoded is Map) {
          _acceptedVersion = (decoded['version'] as num?)?.toInt();
          final at = decoded['acceptedAt'] as String?;
          _acceptedAt = at == null ? null : DateTime.tryParse(at);
        }
      }
    } catch (_) {
      _acceptedVersion = null;
      _acceptedAt = null;
    } finally {
      _hydrated = true;
    }
  }

  Future<bool> accept() async {
    final now = DateTime.now();
    _acceptedVersion = kLegalVersion;
    _acceptedAt = now;
    _hydrated = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _kKey,
        jsonEncode({'version': kLegalVersion, 'acceptedAt': now.toIso8601String()}),
      );
      return true;
    } catch (_) {
      // Zgoda obowiązuje w tej sesji nawet, gdy zapis padnie — nie blokujemy
      // użytkownika, ale przy następnym starcie zapytamy ponownie.
      return false;
    }
  }

  Future<void> clear() async {
    _acceptedVersion = null;
    _acceptedAt = null;
    _hydrated = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_kKey);
    } catch (_) {}
  }

  /// Tylko do testów.
  void resetForTest() {
    _acceptedVersion = null;
    _acceptedAt = null;
    _hydrated = false;
  }
}
