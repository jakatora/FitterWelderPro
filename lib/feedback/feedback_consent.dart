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

  Future<FeedbackConsentState> read() async {
    try {
      final prefs = await SharedPreferences.getInstance();
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
  Future<bool> grant({DateTime? now}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return await prefs.setString(
        prefsKey,
        jsonEncode({
          'granted': true,
          'at': (now ?? DateTime.now()).toUtc().toIso8601String(),
          'policy': kLegalUpdated,
        }),
      );
    } catch (e) {
      debugPrint('FeedbackConsent.grant: ${e.runtimeType}');
      return false;
    }
  }

  /// Cofnięcie zgody: od teraz nic nie jest wysyłane. Kolejka i identyfikator
  /// zostają (identyfikator jest potrzebny do skasowania danych na serwerze).
  Future<void> revoke() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(prefsKey);
    } catch (e) {
      debugPrint('FeedbackConsent.revoke: ${e.runtimeType}');
    }
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

  /// „Usuń moje dane”: zgoda, identyfikator i cała kolejka (z kopią
  /// uszkodzonego zapisu). Kasowanie na serwerze woła UI WCZEŚNIEJ, z
  /// [storedInstallId].
  Future<void> clearAll() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(prefsKey);
      await prefs.remove(installIdKey);
    } catch (e) {
      debugPrint('FeedbackConsent.clearAll: ${e.runtimeType}');
    }
    await FeedbackStore.instance.clear();
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
  }
}

/// Skrót: identyfikator instalacji do feedbacku (lazy, losowy).
Future<String> feedbackInstallId() => FeedbackConsent.instance.installId();
