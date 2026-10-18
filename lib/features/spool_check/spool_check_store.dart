// Historia protokołów „Tolerancje spoola” w SharedPreferences (JSON) — bez
// zmian schematu bazy.
//
// Odporność (jak historia prac pożarowych):
// * nieczytelny zapis ALBO pominięte / uszkodzone wpisy → kopia surowego
//   tekstu PRZED pierwszym nadpisaniem i flaga dla banera na ekranie (nic
//   nie znika po cichu);
// * operacje szeregowane — odczyt po zapisie zawsze widzi ten zapis;
// * limit [SpoolCheckStore.maxEntries] — przy pełnej historii NOWY protokół
//   jest odrzucany ([SpoolCheckStoreFull]), stare nigdy nie wypadają po
//   cichu; od [SpoolCheckStore.warnAt] ekran ostrzega;
// * przywrócenie usuniętego ([SpoolCheckStore.restore]) jest zawsze
//   dozwolone — także przy pełnej historii i po zamknięciu ekranu.

import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../domain/spool_check/spool_check.dart';

/// Wynik odczytu historii.
class SpoolCheckLoad {
  final List<SpoolCheck> checks;

  /// Zapis był nieczytelny w całości (historia pusta).
  final bool unreadable;

  /// Ile protokołów pominięto i ile uszkodzeń w zachowanych protokołach.
  final int droppedChecks;
  final int damagedEntries;

  const SpoolCheckLoad(
    this.checks, {
    this.unreadable = false,
    this.droppedChecks = 0,
    this.damagedEntries = 0,
  });

  /// Coś odrzucono — surowy tekst jest w kopii, ekran pokazuje baner.
  bool get damaged => unreadable || droppedChecks > 0 || damagedEntries > 0;
}

/// Historia pełna — nowego protokołu nie zapisano.
class SpoolCheckStoreFull implements Exception {
  const SpoolCheckStoreFull();
  @override
  String toString() => 'SpoolCheckStoreFull(${SpoolCheckStore.maxEntries})';
}

class SpoolCheckStore {
  static const String key = 'spool_checks_v1';

  /// Tyle protokołów mieści historia; od [warnAt] (90 %) ekran ostrzega.
  static const int maxEntries = 200;
  static const int warnAt = 180;

  /// Kopia PIERWSZEGO nieczytelnego zapisu (nigdy nienadpisywana).
  static const String corruptBackupKey = '${key}_corrupt';

  /// Kopia późniejszego, innego nieczytelnego zapisu (ostatnia).
  static const String corruptLastBackupKey = '${key}_corrupt_last';

  const SpoolCheckStore();

  /// Kolejka operacji (wspólna dla wszystkich instancji).
  static Future<void>? _tail;
  static int _inFlight = 0;

  static Future<T> _serial<T>(Future<T> Function() op) {
    final prev = _inFlight > 0 ? _tail : null;
    _inFlight++;
    final result = prev == null ? op() : prev.then((_) => op());
    _tail = result
        .then<void>((_) {}, onError: (Object _) {})
        .whenComplete(() => _inFlight--);
    return result;
  }

  Future<List<SpoolCheck>> load() async => (await loadReport()).checks;

  Future<SpoolCheckLoad> loadReport() => _serial(_loadNow);

  Future<SpoolCheckLoad> _loadNow() async {
    final prefs = await SharedPreferences.getInstance();
    Object? raw;
    try {
      raw = prefs.get(key);
      if (raw == null || (raw is String && raw.isEmpty)) {
        return const SpoolCheckLoad([]);
      }
      if (raw is! String) throw const FormatException('not a string');
      final parsed = spoolChecksParse(jsonDecode(raw));
      if (parsed.damaged) await _backup(prefs, raw);
      return SpoolCheckLoad(
        sortSpoolChecks(parsed.checks),
        droppedChecks: parsed.droppedChecks,
        damagedEntries: parsed.damagedEntries,
      );
    } catch (_) {
      if (raw != null) await _backup(prefs, raw);
      return const SpoolCheckLoad([], unreadable: true);
    }
  }

  static Future<void> _backup(SharedPreferences prefs, Object raw) async {
    final text = raw.toString();
    final first = prefs.get(corruptBackupKey);
    if (first == null) {
      await prefs.setString(corruptBackupKey, text);
    } else if (first != text && prefs.get(corruptLastBackupKey) != text) {
      await prefs.setString(corruptLastBackupKey, text);
    }
  }

  Future<void> _write(List<SpoolCheck> list) async {
    final prefs = await SharedPreferences.getInstance();
    final ok = await prefs.setString(
        key, jsonEncode(spoolChecksToJson(sortSpoolChecks(list))));
    if (!ok) throw StateError('SharedPreferences.setString($key) failed');
  }

  /// Zapisuje (nowy albo zmieniony) protokół. Pusty protokół nie trafia do
  /// historii — a jeśli był zapisany, znika. Nowy przy pełnej historii →
  /// [SpoolCheckStoreFull].
  Future<void> upsert(SpoolCheck check) => _serial(() async {
        final list = [...(await _loadNow()).checks];
        final existed = list.any((c) => c.id == check.id);
        list.removeWhere((c) => c.id == check.id);
        if (!check.isBlank) {
          if (!existed && list.length >= maxEntries) {
            throw const SpoolCheckStoreFull();
          }
          list.add(check);
        }
        await _write(list);
      });

  /// Przywraca usunięty protokół („Cofnij”) — ZAWSZE, także ponad limit:
  /// to nie nowy wpis, tylko odwołanie usunięcia.
  Future<void> restore(SpoolCheck check) => _serial(() async {
        final list = [...(await _loadNow()).checks]
          ..removeWhere((c) => c.id == check.id)
          ..add(check);
        await _write(list);
      });

  /// Przywraca usuniętą pozycję w zapisanym protokole (gdy ekranu edycji
  /// już nie ma). Brak protokołu w historii → nic.
  Future<void> restoreItem(String checkId, SpoolItem item, int index) =>
      _serial(() async {
        final list = [...(await _loadNow()).checks];
        final i = list.indexWhere((c) => c.id == checkId);
        if (i < 0) return;
        final c = list[i];
        if (c.items.any((it) => it.id == item.id)) return;
        final items = [...c.items]..insert(index.clamp(0, c.items.length), item);
        list[i] = c.copyWith(items: items);
        await _write(list);
      });

  Future<void> delete(String id) => _serial(() async {
        final list = [...(await _loadNow()).checks]
          ..removeWhere((c) => c.id == id);
        await _write(list);
      });
}

/// Najnowsze na górze: data pomiaru malejąco, potem ostatnia zmiana.
List<SpoolCheck> sortSpoolChecks(List<SpoolCheck> list) => [...list]
  ..sort((a, b) {
    final byDate = b.date.compareTo(a.date);
    if (byDate != 0) return byDate;
    return b.updatedAt.compareTo(a.updatedAt);
  });
