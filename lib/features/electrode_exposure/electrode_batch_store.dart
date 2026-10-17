// Zapis partii elektrod w SharedPreferences (JSON z wersją w kluczu) — bez
// zmian schematu bazy. Uszkodzony zapis nie blokuje ekranu: odczyt zwraca
// to, co da się odczytać, a gdy cokolwiek stracono albo naprawiono —
// surowy zapis trafia RAZ pod klucz kopii, zanim następny zapis nadpisze
// główny klucz (dziennik QC nie znika po cichu).

import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../domain/welding/electrode_exposure.dart';

class ElectrodeBatchStore {
  const ElectrodeBatchStore({
    this.key = kElectrodeBatchesPrefsKey,
    this.corruptKey = kElectrodeBatchesCorruptPrefsKey,
  });

  final String key;

  /// Kopia surowego zapisu odczytanego ze stratą (tylko pierwsza).
  final String corruptKey;

  Future<List<ElectrodeBatch>> load() async {
    final prefs = await SharedPreferences.getInstance();
    // `get`, nie `getString`: pod kluczem może leżeć inny typ (ręczna
    // edycja, stara wersja) — `getString` by wtedy rzucił.
    final Object? raw;
    try {
      raw = prefs.get(key);
    } catch (_) {
      return [];
    }
    if (raw == null) return [];
    if (raw is! String) {
      await _backup(prefs, _describe(raw));
      return [];
    }
    final result = decodeBatchesDetailed(raw);
    if (result.lossy) await _backup(prefs, raw);
    return result.batches;
  }

  Future<void> save(List<ElectrodeBatch> batches) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(key, encodeBatches(batches));
  }

  /// Zapis kopii tylko wtedy, gdy jej jeszcze nie ma — pierwsza uszkodzona
  /// wersja jest najcenniejsza (późniejsze to już nadpisane resztki).
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
