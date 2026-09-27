import 'dart:convert';

import 'package:crypto/crypto.dart';

/// A very simple authentication service that stores users in memory.
///
/// In a real application you would back this with a secure database or
/// authentication provider. Passwords are hashed using SHA-256 before
/// storage.
///
/// Relikt prototypu: ekran rejestracji jest dziś nieosiągalny (rejestr
/// narzędzi go pomija), a o usunięciu modułu decyduje właściciel. Zaszyty
/// użytkownik demo (e-mail i hasło w kodzie) został usunięty 2026-09-26 —
/// żadnych kont wbudowanych w kod.
class AuthService {
  /// In-memory map of users and their hashed passwords. Keys are
  /// normalized to lowercase email addresses. Starts empty.
  static final Map<String, String> _users = {};

  /// Returns the SHA-256 hash of the provided [password] as a hex string.
  static String _hash(String password) {
    return sha256.convert(utf8.encode(password)).toString();
  }

  /// Attempts to authenticate a user with [email] and [password].
  ///
  /// Returns `true` if the email exists and the hashed password matches,
  /// otherwise returns `false`. Email comparison is case-insensitive.
  static Future<bool> authenticate(String email, String password) async {
    final hashed = _users[email.toLowerCase()];
    return hashed != null && hashed == _hash(password);
  }

  /// Registers a new user with [email] and [password].
  ///
  /// Returns `true` if registration succeeded. If a user with the same
  /// email already exists, the registration will fail and `false` will be
  /// returned. Email comparison is case-insensitive.
  static Future<bool> register(String email, String password) async {
    final lower = email.toLowerCase();
    if (_users.containsKey(lower)) return false;
    _users[lower] = _hash(password);
    return true;
  }
}