// Zapis ostatnich wejść planu ściegów w SharedPreferences (JSON z wersją
// w kluczu) — bez zmian schematu bazy. Uszkodzony zapis nie blokuje
// ekranu: odczyt zwraca wartości domyślne (albo to, co da się odczytać)
// z flagą `lossy`, a surowy zapis trafia RAZ pod klucz kopii, zanim
// następny zapis nadpisze główny klucz.

import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../domain/pass_plan/pass_plan_form.dart';

class PassPlanStore {
  const PassPlanStore({
    this.key = kPassPlanPrefsKey,
    this.corruptKey = kPassPlanCorruptPrefsKey,
  });

  final String key;

  /// Kopia surowego zapisu odczytanego ze stratą (tylko pierwsza).
  final String corruptKey;

  /// Zapisany formularz; `null` — nic nie zapisano albo prefs niedostępne.
  Future<({Map<String, String> form, bool lossy})?> load() async {
    final SharedPreferences prefs;
    final Object? raw;
    try {
      prefs = await SharedPreferences.getInstance();
      // `get`, nie `getString`: pod kluczem może leżeć inny typ.
      raw = prefs.get(key);
    } catch (_) {
      return null;
    }
    if (raw == null) return null;
    if (raw is! String) {
      await _backup(prefs, _describe(raw));
      return (form: passPlanDefaultForm(), lossy: true);
    }
    final result = decodePassPlanFormDetailed(raw);
    if (result.lossy) await _backup(prefs, raw);
    return result;
  }

  /// Zapis. Jeśli pod kluczem leży coś, czego nie da się odczytać bez strat
  /// (np. zapis nie zdążył się wczytać), najpierw trafia to pod klucz kopii
  /// — nadpisanie nie może zgubić surowego zapisu.
  Future<void> save(Map<String, String> form) async {
    final prefs = await SharedPreferences.getInstance();
    Object? raw;
    try {
      raw = prefs.get(key);
    } catch (_) {
      raw = null;
    }
    if (raw != null) {
      if (raw is! String) {
        await _backup(prefs, _describe(raw));
      } else if (decodePassPlanFormDetailed(raw).lossy) {
        await _backup(prefs, raw);
      }
    }
    await prefs.setString(key, encodePassPlanForm(form));
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
