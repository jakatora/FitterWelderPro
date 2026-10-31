// Ostatnie wejścia ekranu „Dymy spawalnicze i odciąg” w SharedPreferences
// (JSON z wersją w kluczu) — bez zmian schematu bazy. Uszkodzony zapis nie
// blokuje ekranu: odczyt zwraca wartości domyślne z flagą `corrupt`, a ekran
// mówi o tym spawaczowi. Lista kontrolna nie jest zapisywana.

import 'dart:async';
import 'package:shared_preferences/shared_preferences.dart';
import '../../services/owned_prefs.dart';
import '../../database/local_record_owner.dart';

import '../../domain/fume/fume_inputs.dart';

class FumeInputStore {
  static Future<void>? _writes;
  const FumeInputStore({
    this.key = kFumeInputsPrefsKey,
    this.captureOwner,
  });

  final String key;
  final Future<LocalRecordOwner> Function()? captureOwner;

  Future<FumeDecoded> load() async {
    final Object? raw;
    try {
      final pending = _writes;
      if (pending != null) await pending;
      final prefs = await OwnedPrefs.instance(captureOwner);
      await prefs.reload();
      // `get`, nie `getString`: pod kluczem może leżeć inny typ.
      raw = prefs.get(key);
    } catch (_) {
      return const FumeDecoded(FumeInputs(), corrupt: true, readFailed: true);
    }
    if (raw == null) return decodeFumeInputs(null);
    if (raw is! String) return const FumeDecoded(FumeInputs(), corrupt: true);
    return decodeFumeInputs(raw);
  }

  Future<void> save(FumeInputs inputs) {
    Object? captureError;
    StackTrace? captureStack;
    final prefsReady =
        OwnedPrefs.instance(captureOwner).then<SharedPreferences?>(
      (prefs) => prefs,
      onError: (Object error, StackTrace stack) {
        captureError = error;
        captureStack = stack;
        return null;
      },
    );
    final encoded = encodeFumeInputs(inputs);
    final previous = _writes;
    final write = () async {
      if (previous != null) await previous;
      final prefs = await prefsReady;
      if (prefs == null) {
        Error.throwWithStackTrace(captureError!, captureStack!);
      }
      if (!await prefs.setString(key, encoded)) {
        throw StateError('Could not save fume settings');
      }
      await prefs.reload();
      if (prefs.getString(key) != encoded) {
        throw StateError('Fume settings were not persisted');
      }
    }();
    final settled =
        write.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    _writes = settled;
    unawaited(settled.then((_) {
      if (identical(_writes, settled)) _writes = null;
    }));
    return write;
  }
}
