// Zapis ostatniej tabliczki znamionowej spawarki w SharedPreferences (JSON
// z wersją w kluczu) — bez zmian schematu bazy. Uszkodzony zapis nie
// blokuje ekranu: odczyt zwraca to, co da się odczytać, a surowy zapis
// trafia pod jeden z dwóch kluczy kopii, zanim następny zapis nadpisze
// główny klucz.

import 'dart:convert';
import 'dart:async';

import 'package:shared_preferences/shared_preferences.dart';
import '../../database/local_record_owner.dart';
import '../../services/owned_prefs.dart';

import '../../domain/welding/power_source.dart';

class PowerSourcePlateStore {
  static Future<void>? _writes;
  const PowerSourcePlateStore({
    this.key = kPowerSourcePlatePrefsKey,
    this.corruptKey = kPowerSourcePlateCorruptPrefsKey,
    this.captureOwner,
  });

  final String key;

  /// Pierwsza kopia surowego zapisu odczytanego ze stratą.
  final String corruptKey;

  final Future<LocalRecordOwner> Function()? captureOwner;

  List<String> get _backupKeys => [corruptKey, '${corruptKey}_2'];

  /// Zapisane punkty tabliczki; pusta lista — brak zapisu albo nic się nie
  /// dało odczytać.
  Future<List<PlatePoint>> load() async {
    final SharedPreferences prefs;
    final Object? raw;
    try {
      final pending = _writes;
      if (pending != null) await pending;
      prefs = await OwnedPrefs.instance(captureOwner);
      await prefs.reload();
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

  Future<void> save(List<PlatePoint> points) {
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
    final snapshot = List<PlatePoint>.of(points);
    final previous = _writes;
    final write = () async {
      if (previous != null) await previous;
      final prefs = await prefsReady;
      if (prefs == null) {
        Error.throwWithStackTrace(captureError!, captureStack!);
      }
      await _saveNow(prefs, snapshot);
    }();
    final settled =
        write.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    _writes = settled;
    unawaited(settled.then((_) {
      if (identical(_writes, settled)) _writes = null;
    }));
    return write;
  }

  Future<void> _saveNow(
      SharedPreferences prefs, List<PlatePoint> points) async {
    await prefs.reload();
    final raw = prefs.get(key);
    if (raw != null && (raw is! String || decodePlateDetailed(raw).lossy)) {
      final copy = raw is String ? raw : _describe(raw);
      if (!await _backup(prefs, copy)) {
        throw StateError('Could not back up damaged plate');
      }
    }
    final encoded = encodePlate(points);
    if (!await prefs.setString(key, encoded)) {
      throw StateError('Could not save rating plate');
    }
    await prefs.reload();
    if (prefs.get(key) != encoded) {
      throw StateError('Could not verify rating plate write');
    }
  }

  /// Kopie są nienadpisywane. Brak miejsca albo odmowa zapisu blokują save.
  Future<bool> _backup(SharedPreferences prefs, String raw) async {
    try {
      String? free;
      for (final key in _backupKeys) {
        final value = prefs.get(key);
        if (value == raw) return true;
        if (value == null && free == null) free = key;
      }
      if (free == null || !await prefs.setString(free, raw)) return false;
      await prefs.reload();
      return prefs.get(free) == raw;
    } catch (_) {
      // Odczyt może kontynuować bez kopii; save sprawdza jej wynik.
      return false;
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
