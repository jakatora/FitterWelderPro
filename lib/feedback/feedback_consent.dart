// Zgoda „Pomóż ulepszać aplikację” i identyfikator instalacji do feedbacku.
//
// - `feedback_consent_v1`: domyślnie BRAK zgody. Przy zgodzie zapisujemy
//   {"granted":true,"at":<ISO UTC>,"policy":<kLegalUpdated>} — datę polityki,
//   którą użytkownik widział. Zgoda jest osobna: `kLegalVersion` się nie
//   zmienia (podniesienie zablokowałoby czat i skaner wszystkim).
// - `feedback_install_id`: losowy identyfikator (Random.secure, base64url,
//   32 znaki) wysyłany jako nagłówek `X-Feedback-Id`. To NIE jest `device_id`
//   czatu i nie da się go z nim powiązać; służy tylko limitom serwera
//   i kasowaniu zgłoszeń („Usuń moje dane”).

import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../legal/legal_texts.dart';
import 'feedback_store.dart';

@immutable
class FeedbackConsentState {
  const FeedbackConsentState({required this.granted, this.at, this.policy});

  static const FeedbackConsentState none = FeedbackConsentState(granted: false);

  final bool granted;

  /// Kiedy udzielono zgody (UTC).
  final DateTime? at;

  /// `kLegalUpdated` z chwili udzielenia zgody.
  final String? policy;
}

class FeedbackConsent {
  FeedbackConsent._();
  static final FeedbackConsent instance = FeedbackConsent._();

  static const String prefsKey = 'feedback_consent_v1';
  static const String installIdKey = 'feedback_install_id';

  /// Format identyfikatora przyjmowany przez backend.
  static final RegExp installIdFormat = RegExp(r'^[A-Za-z0-9_-]{22,64}$');

  Future<String>? _pendingId;
  bool _revoked = false;
  int _consentRevision = 0;
  Future<void>? _consentWrites;

  Future<T> _serialConsent<T>(Future<T> Function() operation) {
    final previous = _consentWrites;
    final result =
        previous == null ? operation() : previous.then((_) => operation());
    final settled =
        result.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    _consentWrites = settled;
    unawaited(settled.then((_) {
      if (identical(_consentWrites, settled)) _consentWrites = null;
    }));
    return result;
  }

  Future<FeedbackConsentState> read() async {
    if (_revoked) return FeedbackConsentState.none;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.reload();
      if (_revoked) return FeedbackConsentState.none;
      final raw = prefs.getString(prefsKey);
      if (raw == null || raw.isEmpty) return FeedbackConsentState.none;
      final decoded = jsonDecode(raw);
      if (decoded is! Map || decoded['granted'] != true) {
        return FeedbackConsentState.none;
      }
      final at = decoded['at'];
      final policy = decoded['policy'];
      return FeedbackConsentState(
        granted: true,
        at: at is String ? DateTime.tryParse(at)?.toUtc() : null,
        policy: policy is String ? policy : null,
      );
    } catch (e) {
      // Nieczytelny zapis = brak zgody (bezpieczna strona).
      debugPrint('FeedbackConsent.read: ${e.runtimeType}');
      return FeedbackConsentState.none;
    }
  }

  Future<bool> isGranted() async => (await read()).granted;

  /// Zapisuje zgodę z datą polityki [kLegalUpdated]. false = zapis się nie udał.
  Future<bool> grant({DateTime? now}) {
    final revision = ++_consentRevision;
    return _serialConsent(() async {
      try {
        final prefs = await SharedPreferences.getInstance();
        final encoded = jsonEncode({
          'granted': true,
          'at': (now ?? DateTime.now()).toUtc().toIso8601String(),
          'policy': kLegalUpdated,
        });
        if (!await prefs.setString(prefsKey, encoded)) return false;
        await prefs.reload();
        final persisted = prefs.getString(prefsKey) == encoded;
        if (revision != _consentRevision) return false;
        if (persisted) _revoked = false;
        return persisted;
      } catch (e) {
        debugPrint('FeedbackConsent.grant: ${e.runtimeType}');
        return false;
      }
    });
  }

  /// Cofnięcie zgody: od teraz nic nie jest wysyłane. Kolejka i identyfikator
  /// zostają (identyfikator jest potrzebny do skasowania danych na serwerze).
  Future<bool> revoke() {
    _revoked = true;
    _consentRevision++;
    return _serialConsent(() async {
      try {
        final prefs = await SharedPreferences.getInstance();
        final removed = await prefs.remove(prefsKey);
        await prefs.reload();
        return removed && !prefs.containsKey(prefsKey);
      } catch (e) {
        debugPrint('FeedbackConsent.revoke: ${e.runtimeType}');
        return false;
      }
    });
  }

  /// Identyfikator do nagłówka `X-Feedback-Id`; tworzony przy pierwszym użyciu.
  Future<String> installId() {
    return _pendingId ??= _loadOrCreateId().whenComplete(() {
      _pendingId = null;
    });
  }

  Future<String> _loadOrCreateId() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString(installIdKey);
    if (stored != null && installIdFormat.hasMatch(stored)) return stored;
    final id = generateInstallId();
    await prefs.setString(installIdKey, id);
    return id;
  }

  /// Zapisany identyfikator BEZ tworzenia nowego (np. do kasowania na
  /// serwerze: null = ta instalacja nic nie wysłała pod identyfikatorem).
  Future<String?> storedInstallId() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final stored = prefs.getString(installIdKey);
      return stored != null && installIdFormat.hasMatch(stored) ? stored : null;
    } catch (_) {
      return null;
    }
  }

  /// Lokalne skasowanie wszystkiego: zgoda, identyfikator i cała kolejka (z
  /// kopią uszkodzonego zapisu). NIE wołaj tego wprost z „Usuń moje dane” —
  /// użyj `eraseAllFeedback` (feedback_uploader.dart), które najpierw czeka na
  /// wysyłkę w toku i kasuje dane na serwerze, a identyfikator usuwa dopiero
  /// po sukcesie.
  Future<bool> clearAll() {
    _revoked = true;
    _consentRevision++;
    return _serialConsent(() async {
      if (!await FeedbackStore.instance.clear()) return false;
      try {
        final prefs = await SharedPreferences.getInstance();
        if (!await prefs.remove(prefsKey)) return false;
        await prefs.reload();
        if (prefs.containsKey(prefsKey)) return false;
        if (!await prefs.remove(installIdKey)) return false;
        await prefs.reload();
        return !prefs.containsKey(installIdKey);
      } catch (e) {
        debugPrint('FeedbackConsent.clearAll: ${e.runtimeType}');
        return false;
      }
    });
  }

  /// 24 bajty z `Random.secure()` w base64url bez dopełnienia = 32 znaki.
  @visibleForTesting
  static String generateInstallId([math.Random? random]) {
    final r = random ?? math.Random.secure();
    final bytes = List<int>.generate(24, (_) => r.nextInt(256));
    return base64Url.encode(bytes).replaceAll('=', '');
  }

  @visibleForTesting
  void resetForTest() {
    _pendingId = null;
    _revoked = false;
    _consentRevision = 0;
    _consentWrites = null;
  }
}

/// Skrót: identyfikator instalacji do feedbacku (lazy, losowy).
Future<String> feedbackInstallId() => FeedbackConsent.instance.installId();
