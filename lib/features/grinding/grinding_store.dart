// „Moje szlifierki” w SharedPreferences (JSON, wersja w kluczu) — bez zmian
// schematu bazy.
//
// Odporność:
// * uszkodzony zapis nie blokuje ekranu: odczyt zwraca to, co da się
//   odczytać, i mówi, że zapis był uszkodzony; surowa wartość trafia RAZ
//   pod klucz kopii — przy odczycie i przed każdym zapisem — zanim zapis
//   nadpisze klucz główny. Dane nie giną po cichu;
// * niedostępna pamięć (SharedPreferences nie wstaje) to INNY stan niż
//   uszkodzony zapis — nic nie skopiowano, nic nie nadpisano;
// * operacje szeregowane (kolejka), a każda zmiana liczona od listy
//   ZAPISANEJ w chwili zapisu — dwa szybkie usunięcia nie wskrzeszają
//   pierwszego, „Cofnij” przywraca tylko usunięty element (na dawne
//   miejsce) i nie gubi zmian z międzyczasu; działa też po zamknięciu
//   ekranu, bo nie zależy od jego stanu.

import 'dart:convert';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:shared_preferences/shared_preferences.dart';
import '../../services/owned_prefs.dart';

import '../../domain/grinding/grinder_profile.dart';

/// Wynik odczytu.
class GrindersLoad {
  final List<GrinderProfile> grinders;

  /// Zapis był uszkodzony — część albo całość pominięta, kopia zachowana.
  final bool damaged;

  /// Pamięć aplikacji niedostępna — nic nie wczytano (ani nie usunięto).
  final bool unavailable;

  const GrindersLoad(
    this.grinders, {
    this.damaged = false,
    this.unavailable = false,
  });
}

/// Lista pełna ([kMaxGrinders]) — nowej szlifierki nie zapisano.
class GrinderStoreFull implements Exception {
  const GrinderStoreFull();
  @override
  String toString() => 'GrinderStoreFull($kMaxGrinders)';
}

/// Usunięta szlifierka i jej dawne miejsce — do „Cofnij”.
class GrinderRemoval {
  final GrinderProfile profile;
  final int index;
  final List<GrinderProfile> remaining;
  const GrinderRemoval(this.profile, this.index, this.remaining);
}

class GrinderStore {
  const GrinderStore({
    this.key = kGrindersPrefsKey,
    this.corruptKey = kGrindersCorruptPrefsKey,
    this.openPrefs = OwnedPrefs.instance,
  });

  final String key;

  /// Kopia surowego zapisu odczytanego ze stratą (tylko pierwsza).
  final String corruptKey;

  /// Dostęp do pamięci — test podmienia na niedostępną.
  final Future<SharedPreferences> Function() openPrefs;

  // ── Kolejka ─────────────────────────────────────────────────────────────
  // Gdy nic nie czeka, nowa operacja startuje od razu — bez trzymania
  // starej przyszłości (z innej strefy, np. poprzedniego testu).
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

  // ── Odczyt ──────────────────────────────────────────────────────────────

  /// Nigdy nie rzuca: brak zapisu → pusta lista; uszkodzony → to, co się
  /// da, `damaged` i kopia; brak pamięci → `unavailable`.
  Future<GrindersLoad> load() => _serial(() async {
        final SharedPreferences prefs;
        try {
          prefs = await openPrefs();
        } catch (e) {
          debugPrint('[grinding] prefs unavailable: $e');
          return const GrindersLoad([], unavailable: true);
        }
        return _read(prefs);
      });

  Future<GrindersLoad> _read(SharedPreferences prefs) async {
    // `get`, nie `getString`: pod kluczem może leżeć inny typ (ręczna
    // edycja, stara wersja) — `getString` by wtedy rzucił.
    final Object? raw;
    try {
      raw = prefs.get(key);
    } catch (e) {
      debugPrint('[grinding] read failed: $e');
      return const GrindersLoad([], unavailable: true);
    }
    if (raw == null) return const GrindersLoad([]);
    if (raw is! String) {
      await _backup(prefs, _describe(raw));
      return const GrindersLoad([], damaged: true);
    }
    final decoded = decodeGrinders(raw);
    if (decoded.lossy) await _backup(prefs, raw);
    return GrindersLoad(decoded.grinders, damaged: decoded.lossy);
  }

  // ── Zmiany (każda od listy zapisanej w chwili zapisu) ──────────────────

  /// Zmiana w miejscu po `id` albo dopisanie na końcu (przy pełnej liście
  /// nowy wpis → [GrinderStoreFull]). Zwraca zapisaną listę.
  Future<List<GrinderProfile>> upsert(GrinderProfile g) => _mutate((list) {
        final i = list.indexWhere((x) => x.id == g.id);
        if (i >= 0) {
          list[i] = g;
        } else {
          if (list.length >= kMaxGrinders) throw const GrinderStoreFull();
          list.add(g);
        }
        return list;
      });

  /// Usuwa po `id`. `null`, gdy takiej szlifierki już nie ma.
  Future<GrinderRemoval?> delete(String id) => _serial(() async {
        final prefs = await openPrefs();
        final list = [...(await _readForWrite(prefs))];
        final i = list.indexWhere((x) => x.id == id);
        if (i < 0) return null;
        final removed = list.removeAt(i);
        await _write(prefs, list);
        return GrinderRemoval(removed, i, List.unmodifiable(list));
      });

  /// „Cofnij”: przywraca TYLKO [g], na dawne miejsce [index] (albo na
  /// koniec, gdy lista się skróciła). Gdy `id` już jest — nic nie dubluje.
  Future<List<GrinderProfile>> restore(GrinderProfile g, int index) =>
      _mutate((list) {
        if (list.any((x) => x.id == g.id)) return list;
        list.insert(index.clamp(0, list.length), g);
        return list;
      });

  /// Zapis całej listy (nadpisuje — do migracji i testów).
  Future<void> save(List<GrinderProfile> grinders) => _serial(() async {
        final prefs = await openPrefs();
        await _write(prefs, grinders);
      });

  Future<List<GrinderProfile>> _mutate(
          List<GrinderProfile> Function(List<GrinderProfile> list) change) =>
      _serial(() async {
        final prefs = await openPrefs();
        final next = change([...(await _readForWrite(prefs))]);
        await _write(prefs, next);
        return List.unmodifiable(next);
      });

  /// Lista do zmiany. Nieczytelna pamięć → wyjątek: zapis „od pustej
  /// listy” skasowałby wszystko, czego nie dało się przeczytać.
  Future<List<GrinderProfile>> _readForWrite(SharedPreferences prefs) async {
    final r = await _read(prefs);
    if (r.unavailable) {
      throw StateError('SharedPreferences.get($key) failed');
    }
    return r.grinders;
  }

  Future<void> _write(
      SharedPreferences prefs, List<GrinderProfile> grinders) async {
    await _backupIfDamaged(prefs);
    final ok = await prefs.setString(key, encodeGrinders(grinders));
    if (!ok) throw StateError('SharedPreferences.setString($key) failed');
  }

  /// Przed nadpisaniem: zachowaj dokładnie bieżący uszkodzony zapis.
  /// Jeśli miejsce kopii zawiera inną wartość albo zapis kopii się nie uda,
  /// nie wolno nadpisać jedynej pozostałej surowej wartości.
  Future<void> _backupIfDamaged(SharedPreferences prefs) async {
    final raw = prefs.get(key);
    if (raw == null) return;
    if (raw is String && !decodeGrinders(raw).lossy) return;
    final copy = raw is String ? raw : _describe(raw);
    final existing = prefs.get(corruptKey);
    if (existing != null) {
      if (existing == copy) return;
      throw StateError('Backup for $key contains different data');
    }
    final ok = await prefs.setString(corruptKey, copy);
    if (!ok || prefs.get(corruptKey) != copy) {
      throw StateError('Could not preserve damaged $key before writing');
    }
  }

  /// Zapis kopii tylko wtedy, gdy jej jeszcze nie ma — pierwsza uszkodzona
  /// wersja jest najcenniejsza (późniejsze to już nadpisane resztki).
  Future<void> _backup(SharedPreferences prefs, String raw) async {
    try {
      if (prefs.containsKey(corruptKey)) return;
      await prefs.setString(corruptKey, raw);
    } catch (e) {
      // Kopia to zabezpieczenie — jej brak nie może zablokować ekranu.
      debugPrint('[grinding] backup failed: $e');
    }
  }

  static String _describe(Object raw) {
    try {
      return jsonEncode(raw);
    } catch (_) {
      return raw.toString();
    }
  }
}
