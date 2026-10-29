// Ostatnie wejścia ekranu „Dymy spawalnicze i odciąg” w SharedPreferences
// (JSON z wersją w kluczu) — bez zmian schematu bazy. Uszkodzony zapis nie
// blokuje ekranu: odczyt zwraca wartości domyślne z flagą `corrupt`, a ekran
// mówi o tym spawaczowi. Lista kontrolna nie jest zapisywana.

import '../../services/owned_prefs.dart';
import '../../database/local_record_owner.dart';

import '../../domain/fume/fume_inputs.dart';

class FumeInputStore {
  const FumeInputStore({
    this.key = kFumeInputsPrefsKey,
    this.captureOwner,
  });

  final String key;
  final Future<LocalRecordOwner> Function()? captureOwner;

  Future<FumeDecoded> load() async {
    final Object? raw;
    try {
      final prefs = await OwnedPrefs.instance(captureOwner);
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
      final prefs = await OwnedPrefs.instance(captureOwner);
      await prefs.setString(key, encodeFumeInputs(inputs));
    } catch (_) {
      // Zapis to wygoda — jego brak nie może zablokować ekranu.
    }
  }
}
