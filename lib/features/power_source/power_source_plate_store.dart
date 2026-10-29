// Zapis ostatniej tabliczki znamionowej spawarki w SharedPreferences (JSON
// z wersją w kluczu) — bez zmian schematu bazy. Uszkodzony zapis nie
// blokuje ekranu: odczyt zwraca to, co da się odczytać, a surowy zapis
// trafia RAZ pod klucz kopii, zanim następny zapis nadpisze główny klucz.

import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import '../../database/local_record_owner.dart';
import '../../services/owned_prefs.dart';

import '../../domain/welding/power_source.dart';

class PowerSourcePlateStore {
  const PowerSourcePlateStore({
    this.key = kPowerSourcePlatePrefsKey,
    this.corruptKey = kPowerSourcePlateCorruptPrefsKey,
    this.captureOwner,
  });

  final String key;

  /// Kopia surowego zapisu odczytanego ze stratą (tylko pierwsza).
  final String corruptKey;

  final Future<LocalRecordOwner> Function()? captureOwner;

  /// Zapisane punkty tabliczki; pusta lista — brak zapisu albo nic się nie
  /// dało odczytać.
  Future<List<PlatePoint>> load() async {
    final SharedPreferences prefs;
    final Object? raw;
    try {
      prefs = await OwnedPrefs.instance(captureOwner);
      // `get`, nie `getString`: pod kluczem może leżeć inny typ.
      raw = prefs.get(key);
    } catch (_) {
      return const [];
    }
    if (raw == null) return const [];
    if (raw is! String) {
      await _backup(prefs, _describe(raw));
      return const [];
    }
    final result = decodePlateDetailed(raw);
    if (result.lossy) await _backup(prefs, raw);
    return result.points;
  }

  Future<void> save(List<PlatePoint> points) async {
    final prefs = await OwnedPrefs.instance(captureOwner);
    final raw = prefs.get(key);
    if (raw != null && (raw is! String || decodePlateDetailed(raw).lossy)) {
      final copy = raw is String ? raw : _describe(raw);
      final existing = prefs.get(corruptKey);
      if (existing != null && existing != copy) {
        throw StateError('Different damaged plate is already backed up');
      }
      if (existing == null && !await prefs.setString(corruptKey, copy)) {
        throw StateError('Could not back up damaged plate');
      }
    }
    if (!await prefs.setString(key, encodePlate(points))) {
      throw StateError('Could not save rating plate');
    }
  }

  Future<void> _backup(SharedPreferences prefs, String raw) async {
    try {
      if (prefs.containsKey(corruptKey)) return;
      await prefs.setString(corruptKey, raw);
    } catch (_) {
      // Kopia to zabezpieczenie — jej brak nie może zablokować ekranu.
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
