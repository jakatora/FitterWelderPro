import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:shared_preferences/shared_preferences.dart';

// Lightweight per-device user profile: first + last name. NOT asked for on
// first launch — the app opens straight on the tools (calculators, projects
// and the journal work offline without an account). The name is collected by
// the gate in front of the chat (lib/widgets/community_gate.dart), the first
// time the user opens it, and it signs the user's public chat messages so
// other fitters can see who is writing ("to ja piszę"). It can be edited in
// ProfileScreen.
//
// Deliberately SEPARATE from WelderIdentity (services/welder_identity.dart),
// which carries the coded-work stamp + GDPR consent + qualification records
// required by ISO 3834 / EN ISO 9606. The chat gate must stay a two-field,
// 10-second step — nobody should be forced through the full
// welder-qualification form just to post a message.
//
// Persisted to SharedPreferences (key `user_profile_v1`), mirroring the
// WelderIdentityService pattern so there's no new sqflite migration story.

// ─── Walidacja imienia i nazwiska (wspólna: onboarding i profil) ──────────

/// Najdłuższe imię albo nazwisko (pole tekstowe ma ten `maxLength`).
const int kNamePartMaxLength = 32;

/// Podpis na czacie („Imię Nazwisko") — serwer i ChatService przycinają go
/// do tylu znaków, więc dłuższego nie przyjmujemy, zamiast po cichu ciąć.
const int kFullNameMaxLength = 32;

enum NameProblem {
  /// Puste pole.
  empty,

  /// Mniej niż 2 litery albo znaki spoza liter, spacji, apostrofu i myślnika.
  invalid,

  /// Dłuższe niż [kNamePartMaxLength].
  tooLong,
}

final RegExp _nameChars = RegExp(r"^[\p{L} '\-]+$", unicode: true);
final RegExp _letter = RegExp(r'\p{L}', unicode: true);

/// `null` = poprawne. Litery (także polskie), spacja, apostrof i myślnik
/// („Anna-Maria", „O'Brien"), co najmniej 2 LITERY — „--" nie przejdzie.
NameProblem? checkNamePart(String value) {
  final v = value.trim();
  if (v.isEmpty) return NameProblem.empty;
  if (v.length > kNamePartMaxLength) return NameProblem.tooLong;
  if (!_nameChars.hasMatch(v) || _letter.allMatches(v).length < 2) {
    return NameProblem.invalid;
  }
  return null;
}

/// Czy „Imię Nazwisko" przekracza [kFullNameMaxLength] znaków.
bool fullNameTooLong(String firstName, String lastName) =>
    '${firstName.trim()} ${lastName.trim()}'.trim().length > kFullNameMaxLength;

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
  /// chat gate treats that as "no profile yet" and asks for the name again.
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

  Future<void>? _operations;

  Future<T> _serial<T>(Future<T> Function() operation) {
    final previous = _operations;
    final pending =
        previous == null ? operation() : previous.then((_) => operation());
    final settled =
        pending.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    _operations = settled;
    settled.then((_) {
      if (identical(_operations, settled)) _operations = null;
    });
    return pending;
  }

  Future<UserProfile?> get() => _serial(_getNow);

  Future<UserProfile?> _getNow() async {
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

  /// Tylko do testów: podmienia zapis (np. symuluje awarię dysku).
  @visibleForTesting
  static Future<bool> Function(UserProfile profile)? debugSaveOverride;

  Future<bool> save(UserProfile profile) => _serial(() => _saveNow(profile));

  Future<bool> _saveNow(UserProfile profile) async {
    final override = debugSaveOverride;
    if (override != null) return override(profile);
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = jsonEncode(profile.toJson());
      if (!await prefs.setString(_kPrefsKey, raw)) return false;
      await prefs.reload();
      if (prefs.getString(_kPrefsKey) != raw) return false;
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
    _operations = null;
  }

  Future<bool> clear() => _serial(_clearNow);

  Future<bool> _clearNow() async {
    var cleared = false;
    try {
      final prefs = await SharedPreferences.getInstance();
      if (await prefs.remove(_kPrefsKey)) {
        await prefs.reload();
        cleared = !prefs.containsKey(_kPrefsKey);
      }
    } catch (_) {
      // Drop the in-memory cache regardless so the chat gate asks again.
    }
    _cache = null;
    _hydrated = true;
    _changes.add(null);
    return cleared;
  }
}
