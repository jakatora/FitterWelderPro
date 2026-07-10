import 'dart:async';
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

// Lightweight per-device user profile: first + last name captured on the
// very first launch. Used to sign the user's public chat messages so other
// fitters can see who is writing ("to ja piszę").
//
// Deliberately SEPARATE from WelderIdentity (services/welder_identity.dart),
// which carries the coded-work stamp + GDPR consent + qualification records
// required by ISO 3834 / EN ISO 9606. Onboarding must stay a two-field,
// 10-second step — we don't want a brand-new user forced through the full
// welder-qualification form before they can open a calculator.
//
// Persisted to SharedPreferences (key `user_profile_v1`), mirroring the
// WelderIdentityService pattern so there's no new sqflite migration story.

class UserProfile {
  final String firstName;
  final String lastName;

  const UserProfile({required this.firstName, required this.lastName});

  /// "Jan Kowalski" — full signature used on chat messages / reports.
  String get fullName => '$firstName $lastName'.trim();

  /// Short chat handle seed: "Jan Kowalski" -> "Jan K." so it fits the
  /// 20-char nickname cap in chat_screen.dart without truncation.
  String get shortName {
    final f = firstName.trim();
    final l = lastName.trim();
    if (l.isEmpty) return f;
    return '$f ${l[0].toUpperCase()}.';
  }

  Map<String, Object?> toJson() => {
        'firstName': firstName,
        'lastName': lastName,
      };

  /// Returns null when the stored payload has no usable first name — the
  /// gate treats that as "no profile yet" and re-shows onboarding.
  static UserProfile? fromJson(Map<String, Object?> json) {
    final f = (json['firstName'] as String?)?.trim() ?? '';
    final l = (json['lastName'] as String?)?.trim() ?? '';
    if (f.isEmpty) return null;
    return UserProfile(firstName: f, lastName: l);
  }
}

class UserProfileService {
  UserProfileService._();
  static final UserProfileService instance = UserProfileService._();

  static const _kPrefsKey = 'user_profile_v1';

  UserProfile? _cache;
  bool _hydrated = false;

  final _changes = StreamController<UserProfile?>.broadcast();

  /// Emits the new profile (or null when cleared).
  Stream<UserProfile?> get changes => _changes.stream;

  /// Sync access for hot paths (UI build) — null until [get] has been
  /// awaited at least once.
  UserProfile? get current => _cache;

  bool get hasProfile => _cache != null;

  Future<UserProfile?> get() async {
    if (!_hydrated) await _hydrate();
    return _cache;
  }

  Future<void> _hydrate() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_kPrefsKey);
      if (raw == null || raw.isEmpty) {
        _cache = null;
      } else {
        final decoded = jsonDecode(raw);
        if (decoded is Map) {
          _cache = UserProfile.fromJson(Map<String, Object?>.from(decoded));
        } else {
          _cache = null;
        }
      }
    } catch (_) {
      _cache = null;
    } finally {
      _hydrated = true;
    }
  }

  Future<bool> save(UserProfile profile) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kPrefsKey, jsonEncode(profile.toJson()));
      _cache = profile;
      _hydrated = true;
      _changes.add(profile);
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Test-only: drop cached state so a freshly-set SharedPreferences mock is
  /// re-read on the next [get]. Not used by production code paths.
  void resetForTest() {
    _cache = null;
    _hydrated = false;
  }

  Future<void> clear() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_kPrefsKey);
    } catch (_) {
      // Drop the in-memory cache regardless so the gate re-shows onboarding.
    }
    _cache = null;
    _hydrated = true;
    _changes.add(null);
  }
}
