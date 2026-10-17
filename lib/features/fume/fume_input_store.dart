// Ostatnie wejścia ekranu „Dymy spawalnicze i odciąg” w SharedPreferences
// (JSON z wersją w kluczu) — bez zmian schematu bazy. Uszkodzony zapis nie
// blokuje ekranu: odczyt zwraca wartości domyślne z flagą `corrupt`, a ekran
// mówi o tym spawaczowi. Lista kontrolna nie jest zapisywana.

import 'package:shared_preferences/shared_preferences.dart';

import '../../domain/fume/fume_inputs.dart';

class FumeInputStore {
  const FumeInputStore({this.key = kFumeInputsPrefsKey});

  final String key;

  Future<FumeDecoded> load() async {
    final Object? raw;
    try {
      final prefs = await SharedPreferences.getInstance();
      // `get`, nie `getString`: pod kluczem może leżeć inny typ.
      raw = prefs.get(key);
    } catch (_) {
      return const FumeDecoded(FumeInputs(), corrupt: false);
    }
    if (raw == null) return decodeFumeInputs(null);
    if (raw is! String) return const FumeDecoded(FumeInputs(), corrupt: true);
    return decodeFumeInputs(raw);
  }

  Future<void> save(FumeInputs inputs) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(key, encodeFumeInputs(inputs));
    } catch (_) {
      // Zapis to wygoda — jego brak nie może zablokować ekranu.
    }
  }
}
