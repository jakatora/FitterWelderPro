// Historia protokołów „Tolerancje spoola” w SharedPreferences (JSON) — bez
// zmian schematu bazy.
//
// Odporność (jak historia prac pożarowych):
// * nieczytelny zapis ALBO pominięte / uszkodzone wpisy → kopia surowego
//   tekstu PRZED pierwszym nadpisaniem i flaga dla banera na ekranie (nic
//   nie znika po cichu);
// * kopia, której nie udało się zapisać, BLOKUJE zapis: upsert / delete /
//   restore rzucają [SpoolCheckStoreUnavailable] zamiast nadpisać historię
//   (baner „pamięć niedostępna — nic nie zapisano”);
// * operacje szeregowane — odczyt po zapisie zawsze widzi ten zapis;
// * limit [SpoolCheckStore.maxEntries] — przy pełnej historii NOWY protokół
//   jest odrzucany ([SpoolCheckStoreFull]), stare nigdy nie wypadają po
//   cichu; od [SpoolCheckStore.warnAt] ekran ostrzega;
// * przywrócenie usuniętego ([SpoolCheckStore.restore]) jest zawsze
//   dozwolone — także przy pełnej historii i po zamknięciu ekranu.

import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import '../../services/owned_prefs.dart';

import '../../domain/spool_check/spool_check.dart';

/// Wynik odczytu historii.
class SpoolCheckLoad {
  final List<SpoolCheck> checks;

  /// Zapis był nieczytelny w całości (historia pusta).
  final bool unreadable;

  /// Ile protokołów pominięto i ile uszkodzeń w zachowanych protokołach.
  final int droppedChecks;
  final int damagedEntries;

  /// Uszkodzony zapis, a kopii surowego tekstu NIE udało się zrobić —
  /// magazyn nie nadpisze historii, dopóki kopia się nie uda.
  final bool backupFailed;

  const SpoolCheckLoad(
    this.checks, {
    this.unreadable = false,
    this.droppedChecks = 0,
    this.damagedEntries = 0,
    this.backupFailed = false,
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

/// Zapis uszkodzony, a jego kopii nie udało się zapisać — nic nie
/// zapisano, żeby nie nadpisać jedynego egzemplarza danych.
class SpoolCheckStoreUnavailable implements Exception {
  const SpoolCheckStoreUnavailable();
  @override
  String toString() => 'SpoolCheckStoreUnavailable';
}

class SpoolCheckStore {
  static const String key = 'spool_checks_v1';

  /// Tyle protokołów mieści historia; od [warnAt] (90 %) ekran ostrzega.
  static const int maxEntries = 200;
  static const int warnAt = 180;

  /// Kopia PIERWSZEGO nieczytelnego zapisu (nigdy nienadpisywana).
  static const String corruptBackupKey = '${key}_corrupt';

  /// Kopia drugiego, innego nieczytelnego zapisu (nienadpisywana).
  static const String corruptLastBackupKey = '${key}_corrupt_last';

  /// Dostęp do SharedPreferences — wstrzykiwany w testach (np. pamięć,
  /// która odmawia zapisu).
  final Future<SharedPreferences> Function() prefs;

  const SpoolCheckStore({this.prefs = OwnedPrefs.instance});

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
    final p = await prefs();
    final Object? raw = p.get(key);
    if (raw == null || (raw is String && raw.isEmpty)) {
      return const SpoolCheckLoad([]);
    }
    SpoolChecksParse? parsed;
    if (raw is String) {
      try {
        parsed = spoolChecksParse(jsonDecode(raw));
      } catch (_) {
        parsed = null;
      }
    }
    // Kopia POZA odczytem — jej niepowodzenie nie może udawać czystej
    // historii, którą następny zapis by nadpisał.
    final needsBackup = parsed == null || parsed.damaged;
    final backupOk = !needsBackup || await _backup(p, raw);
    if (parsed == null) {
      return SpoolCheckLoad(const [],
          unreadable: true, backupFailed: !backupOk);
    }
    return SpoolCheckLoad(
      sortSpoolChecks(parsed.checks),
      droppedChecks: parsed.droppedChecks,
      damagedEntries: parsed.damagedEntries,
      backupFailed: !backupOk,
    );
  }

  /// Obie kopie zostają nienadpisane. `true` — ten tekst jest w kopii.
  static Future<bool> _backup(SharedPreferences p, Object raw) async {
    final text = raw.toString();
    try {
      final first = p.get(corruptBackupKey);
      if (first == text) return true;
      final last = p.get(corruptLastBackupKey);
      if (last == text) return true;
      final target = first == null
          ? corruptBackupKey
          : last == null
              ? corruptLastBackupKey
              : null;
      if (target == null) return false;
      final ok = await p.setString(target, text);
      return ok && p.get(target) == text;
    } catch (_) {
      return false;
    }
  }

  /// Odczyt przed zapisem: uszkodzony zapis bez kopii → nic nie zapisujemy.
  Future<List<SpoolCheck>> _loadForWrite() async {
    final load = await _loadNow();
    if (load.backupFailed) throw const SpoolCheckStoreUnavailable();
    return [...load.checks];
  }

  Future<void> _write(List<SpoolCheck> list) async {
    final p = await prefs();
    final ok = await p.setString(
        key, jsonEncode(spoolChecksToJson(sortSpoolChecks(list))));
    if (!ok) throw StateError('SharedPreferences.setString($key) failed');
  }

  /// Zapisuje (nowy albo zmieniony) protokół. Pusty protokół nie trafia do
  /// historii — a jeśli był zapisany, znika. Nowy przy pełnej historii →
  /// [SpoolCheckStoreFull].
  Future<void> upsert(SpoolCheck check) => _serial(() async {
        final list = await _loadForWrite();
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
        final list = await _loadForWrite()
          ..removeWhere((c) => c.id == check.id)
          ..add(check);
        await _write(list);
      });

  /// Przywraca usuniętą pozycję w zapisanym protokole (gdy ekranu edycji
  /// już nie ma). Brak protokołu w historii → nic.
  Future<void> restoreItem(String checkId, SpoolItem item, int index) =>
      _serial(() async {
        final list = await _loadForWrite();
        final i = list.indexWhere((c) => c.id == checkId);
        if (i < 0) return;
        final c = list[i];
        if (c.items.any((it) => it.id == item.id)) return;
        final items = [...c.items]
          ..insert(index.clamp(0, c.items.length), item);
        list[i] = c.copyWith(items: items);
        await _write(list);
      });

  Future<void> delete(String id) => _serial(() async {
        final list = await _loadForWrite()
          ..removeWhere((c) => c.id == id);
        await _write(list);
      });
}

/// Najnowsze na górze: data pomiaru malejąco, potem ostatnia zmiana.
List<SpoolCheck> sortSpoolChecks(List<SpoolCheck> list) =>
    [...list]..sort((a, b) {
        final byDate = b.date.compareTo(a.date);
        if (byDate != 0) return byDate;
        return b.updatedAt.compareTo(a.updatedAt);
      });
