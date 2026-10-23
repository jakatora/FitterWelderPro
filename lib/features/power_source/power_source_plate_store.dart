// Zapis ostatniej tabliczki znamionowej spawarki w SharedPreferences (JSON
// z wersją w kluczu) — bez zmian schematu bazy. Uszkodzony zapis nie
// blokuje ekranu: odczyt zwraca to, co da się odczytać, a surowy zapis
// trafia RAZ pod klucz kopii, zanim następny zapis nadpisze główny klucz.

import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import '../../services/owned_prefs.dart';

import '../../domain/welding/power_source.dart';

class PowerSourcePlateStore {
  const PowerSourcePlateStore({
    this.key = kPowerSourcePlatePrefsKey,
    this.corruptKey = kPowerSourcePlateCorruptPrefsKey,
  });

  final String key;

  /// Kopia surowego zapisu odczytanego ze stratą (tylko pierwsza).
  final String corruptKey;

  /// Zapisane punkty tabliczki; pusta lista — brak zapisu albo nic się nie
  /// dało odczytać.
  Future<List<PlatePoint>> load() async {
    final SharedPreferences prefs;
    final Object? raw;
    try {
      prefs = await OwnedPrefs.instance();
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
    final prefs = await OwnedPrefs.instance();
    await prefs.setString(key, encodePlate(points));
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
