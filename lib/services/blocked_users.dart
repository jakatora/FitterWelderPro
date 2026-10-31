import 'dart:async';
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

// Lokalna lista zablokowanych autorów czatu.
//
// Apple wymaga przy treściach od użytkowników (wytyczna 1.2) DWÓCH mechanizmów:
// zgłaszania treści ORAZ blokowania osób. Aplikacja miała tylko to pierwsze.
//
// Blokujemy po identyfikatorze autora, nie po nazwie — nazwa może się zmienić,
// a blokada ma przetrwać. Lista jest lokalna: nie mówimy serwerowi, kogo nie
// lubisz, więc blokada nie wycieka do zablokowanego ani do nikogo innego.
//
// Klucz blokady (`ChatMessage.blockKey`):
//   • nowy backend (2026-09-24) — `author_id`, nieodwracalny pseudonim autora
//     (serwer przestał wydawać cudze surowe device_id);
//   • stary backend — surowy device_id, jak dotąd.
// Blokady zapisane wcześniej po surowym device_id ZOSTAJĄ na liście (nie
// kasujemy cudzych decyzji), ale na nowym backendzie przestają pasować, bo
// autorzy przychodzą już z author_id. Nowe blokady zapisujemy po author_id.
// Pole nazywa się dalej `deviceId`, żeby nie migrować zapisanej mapy.
//
// Trzymamy też nazwę, jaką autor miał w chwili blokady, żeby ekran profilu
// mógł pokazać czytelną listę zamiast surowych identyfikatorów.

class BlockedUser {
  /// Klucz blokady: `author_id` albo (stare wpisy, stary backend) device_id.
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

  /// Czy którykolwiek z kluczy autora jest zablokowany — dla wiadomości z
  /// `author_id` i `device_id` naraz (patrz `ChatMessage.blockKey`).
  bool isBlockedAny(Iterable<String?> keys) =>
      keys.any((k) => k != null && k.isNotEmpty && _byId.containsKey(k));

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

/// Wiadomości zgłoszone z TEGO telefonu — ukrywane u zgłaszającego od razu,
/// a nie dopiero po 3 zgłoszeniach od różnych osób (wtedy ukrywa je serwer
/// wszystkim). Kto zgłosił wyzwisko, nie powinien go dalej oglądać.
///
/// Lokalnie, jak blokady: serwer wie tylko, że zgłoszenie przyszło. Lista ma
/// limit [maxEntries] (najstarsze wypadają) — to identyfikatory wiadomości,
/// nie treść.
class ReportedMessages {
  ReportedMessages._();
  static final ReportedMessages instance = ReportedMessages._();

  static const String prefsKey = 'chat_reported_ids_v1';
  static const int maxEntries = 500;

  final List<int> _ids = <int>[];
  bool _hydrated = false;
  bool _readFailed = false;
  bool _dirty = false;
  Future<void>? _loading;
  Future<void>? _writes;

  Future<T> _serial<T>(Future<T> Function() operation) {
    final previous = _writes;
    final result =
        previous == null ? operation() : previous.then((_) => operation());
    final settled =
        result.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    _writes = settled;
    unawaited(settled.then((_) {
      if (identical(_writes, settled)) _writes = null;
    }));
    return result;
  }

  bool isReported(int messageId) => _ids.contains(messageId);

  Future<void> load() {
    if (_hydrated) return Future.value();
    return _loading ??= _loadNow().whenComplete(() => _loading = null);
  }

  Future<void> _loadNow() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.reload();
      final raw = prefs.getString(prefsKey);
      if (raw != null && raw.isNotEmpty) {
        final decoded = jsonDecode(raw);
        if (decoded is List) {
          _readFailed = decoded.any((value) => value is! int);
          _ids
            ..clear()
            ..addAll(decoded.whereType<int>());
        } else {
          _readFailed = true;
        }
      }
    } catch (_) {
      _readFailed = true;
      _ids.clear();
    } finally {
      _hydrated = true;
    }
  }

  Future<bool> add(int messageId) => _serial(() async {
        await load();
        if (!_ids.contains(messageId)) {
          _ids.add(messageId);
          _dirty = true;
        }
        if (!_dirty) return !_readFailed;
        if (_ids.length > maxEntries) {
          _ids.removeRange(0, _ids.length - maxEntries);
        }
        // Keep hiding new reports in this session without destroying unread data.
        if (_readFailed) return false;
        try {
          final prefs = await SharedPreferences.getInstance();
          final encoded = jsonEncode(_ids);
          if (!await prefs.setString(prefsKey, encoded)) return false;
          await prefs.reload();
          if (prefs.getString(prefsKey) != encoded) return false;
          _dirty = false;
          return true;
        } catch (_) {
          // Ukrycie działa w tej sesji nawet gdy zapis padnie.
          return false;
        }
      });

  /// „Usuń moje dane".
  Future<bool> clear() => _serial(() async {
        final loading = _loading;
        if (loading != null) await loading;
        _ids.clear();
        _hydrated = true;
        try {
          final prefs = await SharedPreferences.getInstance();
          final removed = await prefs.remove(prefsKey);
          await prefs.reload();
          _readFailed = !removed || prefs.containsKey(prefsKey);
        } catch (_) {
          _readFailed = true;
        }
        return !_readFailed;
      });

  /// Tylko do testów.
  void resetForTest() {
    _ids.clear();
    _hydrated = false;
    _readFailed = false;
    _dirty = false;
    _loading = null;
    _writes = null;
  }
}
