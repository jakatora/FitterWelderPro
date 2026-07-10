import 'dart:async';
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

// Lokalna lista zablokowanych autorów czatu.
//
// Apple wymaga przy treściach od użytkowników (wytyczna 1.2) DWÓCH mechanizmów:
// zgłaszania treści ORAZ blokowania osób. Aplikacja miała tylko to pierwsze.
//
// Blokujemy po `deviceId`, nie po nazwie — nazwa może się zmienić, a blokada
// ma przetrwać. Lista jest lokalna: nie mówimy serwerowi, kogo nie lubisz,
// więc blokada nie wycieka do zablokowanego ani do nikogo innego.
//
// Trzymamy też nazwę, jaką autor miał w chwili blokady, żeby ekran profilu
// mógł pokazać czytelną listę zamiast surowych identyfikatorów.

class BlockedUser {
  final String deviceId;
  final String name;
  const BlockedUser({required this.deviceId, required this.name});
}

class BlockedUsers {
  BlockedUsers._();
  static final BlockedUsers instance = BlockedUsers._();

  static const _kKey = 'blocked_authors_v1';

  final Map<String, String> _byId = <String, String>{};
  bool _hydrated = false;

  final _changes = StreamController<List<BlockedUser>>.broadcast();
  Stream<List<BlockedUser>> get changes => _changes.stream;

  /// Dostęp synchroniczny dla `build()` — pusty, dopóki [load] nie przejdzie.
  bool isBlocked(String deviceId) => _byId.containsKey(deviceId);

  int get count => _byId.length;

  List<BlockedUser> get all => _byId.entries
      .map((e) => BlockedUser(deviceId: e.key, name: e.value))
      .toList()
    ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

  Future<void> load() async {
    if (_hydrated) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_kKey);
      if (raw != null && raw.isNotEmpty) {
        final decoded = jsonDecode(raw);
        if (decoded is Map) {
          _byId
            ..clear()
            ..addAll(decoded.map((k, v) => MapEntry('$k', '$v')));
        }
      }
    } catch (_) {
      _byId.clear();
    } finally {
      _hydrated = true;
    }
  }

  Future<void> block(String deviceId, String name) async {
    if (deviceId.isEmpty) return;
    _byId[deviceId] = name.trim().isEmpty ? deviceId : name.trim();
    await _persist();
  }

  Future<void> unblock(String deviceId) async {
    _byId.remove(deviceId);
    await _persist();
  }

  Future<void> _persist() async {
    _changes.add(all);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kKey, jsonEncode(_byId));
    } catch (_) {
      // Blokada działa w tej sesji nawet gdy zapis padnie.
    }
  }

  /// Tylko do testów.
  void resetForTest() {
    _byId.clear();
    _hydrated = false;
  }
}
