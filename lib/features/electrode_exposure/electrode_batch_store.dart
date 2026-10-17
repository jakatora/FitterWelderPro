// Zapis partii elektrod w SharedPreferences (JSON z wersją w kluczu) — bez
// zmian schematu bazy. Uszkodzony JSON nie blokuje ekranu: odczyt zwraca
// to, co da się odczytać.

import 'package:shared_preferences/shared_preferences.dart';

import '../../domain/welding/electrode_exposure.dart';

class ElectrodeBatchStore {
  const ElectrodeBatchStore({this.key = kElectrodeBatchesPrefsKey});

  final String key;

  Future<List<ElectrodeBatch>> load() async {
    final prefs = await SharedPreferences.getInstance();
    try {
      return decodeBatches(prefs.getString(key));
    } catch (_) {
      // Pod kluczem nie-tekst (np. po ręcznej edycji) — traktuj jak pusty.
      return [];
    }
  }

  Future<void> save(List<ElectrodeBatch> batches) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(key, encodeBatches(batches));
  }
}
