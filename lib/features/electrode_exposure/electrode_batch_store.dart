// Zapis partii elektrod w SharedPreferences (JSON z wersją w kluczu) — bez
// zmian schematu bazy. Uszkodzony zapis nie blokuje ekranu: odczyt zwraca
// to, co da się odczytać, a gdy cokolwiek stracono albo naprawiono —
// surowy zapis trafia do jednej z trzech kopii, zanim następny zapis
// nadpisze główny klucz (dziennik QC nie znika po cichu).

import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import '../../database/local_record_owner.dart';
import '../../services/owned_prefs.dart';

import '../../domain/welding/electrode_exposure.dart';

class ElectrodeBatchStore {
  const ElectrodeBatchStore({
    this.key = kElectrodeBatchesPrefsKey,
    this.corruptKey = kElectrodeBatchesCorruptPrefsKey,
    this.captureOwner,
  });

  final String key;

  /// Pierwsza kopia surowego zapisu odczytanego ze stratą.
  final String corruptKey;

  final Future<LocalRecordOwner> Function()? captureOwner;

  List<String> get _backupKeys =>
      [corruptKey, '${corruptKey}_2', '${corruptKey}_3'];

  static Future<void>? _tail;
  static int _inFlight = 0;

  Future<List<ElectrodeBatch>> load() async {
    final pending = _inFlight > 0 ? _tail : null;
    if (pending != null) await pending;
    final prefs = await OwnedPrefs.instance(captureOwner);
    // `get`, nie `getString`: pod kluczem może leżeć inny typ (ręczna
    // edycja, stara wersja) — `getString` by wtedy rzucił.
    final Object? raw;
    try {
      await prefs.reload();
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

  /// Zachowuje kolejność szybkich zmian, także gdy starszy zapis kończy się
  /// później. Właściciel jest uchwycony przed oczekiwaniem w kolejce.
  Future<void> save(List<ElectrodeBatch> batches) {
    final ownerFuture = (captureOwner ?? LocalRecordOwner.capture)();
    final previous = _inFlight > 0 ? _tail : null;
    final snapshot = List<ElectrodeBatch>.of(batches);
    _inFlight++;
    final Future<void> result;
    if (previous == null) {
      result = _saveCaptured(snapshot, ownerFuture);
    } else {
      result = Future.wait<Object?>([previous, ownerFuture]).then((values) {
        final owner = values[1]! as LocalRecordOwner;
        owner.requireCurrent();
        return _saveNow(snapshot, owner);
      });
    }
    _tail = result
        .then<void>((_) {}, onError: (Object _) {})
        .whenComplete(() => _inFlight--);
    return result;
  }

  Future<void> _saveCaptured(List<ElectrodeBatch> batches,
      Future<LocalRecordOwner> ownerFuture) async {
    final owner = await ownerFuture;
    owner.requireCurrent();
    await _saveNow(batches, owner);
  }

  Future<void> _saveNow(
      List<ElectrodeBatch> batches, LocalRecordOwner owner) async {
    final prefs = await OwnedPrefs.instance(() async => owner);
    // setString może zwrócić false, zostawiając w pamięci podręcznej
    // optymistyczną wartość. Przed ochroną starego zapisu czytamy dysk.
    await prefs.reload();
    final raw = prefs.get(key);
    if (raw != null && (raw is! String || decodeBatchesDetailed(raw).lossy)) {
      final text = raw is String ? raw : _describe(raw);
      if (!await _backup(prefs, text)) {
        throw StateError('Nie można zabezpieczyć dziennika elektrod.');
      }
    }
    final encoded = encodeBatches(batches);
    if (!await prefs.setString(key, encoded)) {
      throw StateError('Nie można zapisać dziennika elektrod.');
    }
    await prefs.reload();
    if (prefs.get(key) != encoded) {
      throw StateError('Nie można potwierdzić zapisu dziennika elektrod.');
    }
  }

  /// Kopie są niezmienne. Brak miejsca albo odmowa zapisu blokuje save.
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
      // Odczyt ekranu może się udać bez kopii; save musi wtedy odmówić.
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
