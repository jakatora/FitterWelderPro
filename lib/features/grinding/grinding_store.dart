// „Moje szlifierki” w SharedPreferences (JSON, wersja w kluczu) — bez zmian
// schematu bazy. Uszkodzony zapis nie blokuje ekranu: odczyt zwraca to,
// co da się odczytać, i mówi, że zapis był uszkodzony; surowa wartość trafia
// RAZ pod klucz kopii — przy odczycie i (na wszelki wypadek) przed każdym
// zapisem — zanim zapis nadpisze klucz główny. Dane nie giną po cichu.

import 'dart:convert';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:shared_preferences/shared_preferences.dart';

import '../../domain/grinding/grinder_profile.dart';

/// Wynik odczytu: szlifierki i to, czy zapis był uszkodzony.
class GrindersLoad {
  final List<GrinderProfile> grinders;
  final bool damaged;
  const GrindersLoad(this.grinders, {this.damaged = false});
}

class GrinderStore {
  const GrinderStore({
    this.key = kGrindersPrefsKey,
    this.corruptKey = kGrindersCorruptPrefsKey,
  });

  final String key;

  /// Kopia surowego zapisu odczytanego ze stratą (tylko pierwsza).
  final String corruptKey;

  /// Nigdy nie rzuca: brak zapisu → pusta lista; uszkodzony → to, co się
  /// da, `damaged: true` i kopia surowej wartości.
  Future<GrindersLoad> load() async {
    final SharedPreferences prefs;
    try {
      prefs = await SharedPreferences.getInstance();
    } catch (e) {
      debugPrint('[grinding] prefs unavailable: $e');
      return const GrindersLoad([], damaged: true);
    }
    // `get`, nie `getString`: pod kluczem może leżeć inny typ (ręczna
    // edycja, stara wersja) — `getString` by wtedy rzucił.
    final Object? raw;
    try {
      raw = prefs.get(key);
    } catch (e) {
      debugPrint('[grinding] read failed: $e');
      return const GrindersLoad([], damaged: true);
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

  Future<void> save(List<GrinderProfile> grinders) async {
    final prefs = await SharedPreferences.getInstance();
    await _backupIfDamaged(prefs);
    await prefs.setString(key, encodeGrinders(grinders));
  }

  /// Przed nadpisaniem: kopia, jeśli pod kluczem leży coś uszkodzonego,
  /// a kopii jeszcze nie ma.
  Future<void> _backupIfDamaged(SharedPreferences prefs) async {
    final Object? raw;
    try {
      raw = prefs.get(key);
    } catch (_) {
      return;
    }
    if (raw == null) return;
    if (raw is String && !decodeGrinders(raw).lossy) return;
    await _backup(prefs, raw is String ? raw : _describe(raw));
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
