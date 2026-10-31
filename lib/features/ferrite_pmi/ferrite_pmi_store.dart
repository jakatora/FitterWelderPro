// Historia protokołów „Ferryt i PMI” w SharedPreferences (JSON) — bez
// zmian schematu bazy.
//
// Odporność:
// * nieczytelny zapis ALBO pominięte protokoły / elementy → kopia surowego
//   tekstu PRZED pierwszym nadpisaniem (raz; późniejszy inny uszkodzony
//   zapis w drugim kluczu) i flaga dla banera na ekranie;
// * operacje szeregowane — odczyt po zapisie zawsze widzi ten zapis;
// * limit [FerritePmiStore.maxEntries]: przy pełnej historii NOWY protokół
//   jest odrzucany ([FerritePmiStoreFull]); stare NIGDY nie wypadają po
//   cichu; od [FerritePmiStore.warnAt] ekran ostrzega;
// * przywrócenie usuniętego protokołu ([FerritePmiStore.restore], „Cofnij”)
//   jest zawsze dozwolone — także przy pełnej historii.

import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import '../../database/local_record_owner.dart';
import '../../services/owned_prefs.dart';

import '../../domain/ferrite_pmi/ferrite_pmi_protocol.dart';

/// Wynik odczytu historii.
class FerritePmiLoad {
  final List<FerritePmiProtocol> protocols;

  /// Zapis był nieczytelny w całości (historia pusta).
  final bool unreadable;
  final bool readFailed;
  final bool backupFailed;
  final int droppedProtocols;
  final int droppedItems;
  final int recoveredProtocols;

  const FerritePmiLoad(
    this.protocols, {
    this.unreadable = false,
    this.readFailed = false,
    this.backupFailed = false,
    this.droppedProtocols = 0,
    this.droppedItems = 0,
    this.recoveredProtocols = 0,
  });

  bool get damaged =>
      unreadable ||
      droppedProtocols > 0 ||
      droppedItems > 0 ||
      recoveredProtocols > 0;
}

/// Historia pełna — nowego protokołu nie zapisano.
class FerritePmiStoreFull implements Exception {
  const FerritePmiStoreFull();
  @override
  String toString() => 'FerritePmiStoreFull(${FerritePmiStore.maxEntries})';
}

class FerritePmiStore {
  static const String key = 'ferrite_pmi_protocols_v1';

  /// Kopia PIERWSZEGO nieczytelnego zapisu (nigdy nienadpisywana).
  static const String corruptBackupKey = '${key}_corrupt';

  /// Kopia drugiego, innego nieczytelnego zapisu (nienadpisywana).
  static const String corruptLastBackupKey = '${key}_corrupt_last';

  /// Tyle protokołów mieści historia; od [warnAt] (90 %) ekran ostrzega.
  static const int maxEntries = 200;
  static const int warnAt = 180;

  const FerritePmiStore({this.captureOwner});

  final Future<LocalRecordOwner> Function()? captureOwner;

  static Future<void>? _tail;
  static int _inFlight = 0;

  static Future<T> _serial<T>(Future<T> Function() op) {
    final prev = _inFlight > 0 ? _tail : null;
    _inFlight++;
    final result = prev == null ? op() : prev.then((_) => op());
    _tail = result
        .then<void>((_) {}, onError: (Object _) {})
        .whenComplete(() => _inFlight--);
    return result;
  }

  Future<List<FerritePmiProtocol>> load() async =>
      (await loadReport()).protocols;

  Future<FerritePmiLoad> loadReport() => _serial(_loadNow);

  Future<FerritePmiLoad> _loadNow() async {
    final prefs = await OwnedPrefs.instance(captureOwner);
    final Object? raw;
    try {
      await prefs.reload();
      raw = prefs.get(key);
    } catch (_) {
      return const FerritePmiLoad([], unreadable: true, readFailed: true);
    }
    if (raw == null || (raw is String && raw.isEmpty)) {
      return const FerritePmiLoad([]);
    }
    try {
      if (raw is! String) throw const FormatException('not a string');
      final parsed = ferritePmiParse(jsonDecode(raw));
      final backedUp = !parsed.damaged || await _backup(prefs, raw);
      return FerritePmiLoad(
        sortFerritePmi(parsed.protocols),
        backupFailed: !backedUp,
        droppedProtocols: parsed.droppedProtocols,
        droppedItems: parsed.droppedItems,
        recoveredProtocols: parsed.recoveredProtocols,
      );
    } catch (_) {
      final backedUp = await _backup(prefs, raw);
      return FerritePmiLoad([], unreadable: true, backupFailed: !backedUp);
    }
  }

  static Future<bool> _backup(SharedPreferences prefs, Object raw) async {
    final text = raw.toString();
    try {
      await prefs.reload();
      final first = prefs.get(corruptBackupKey);
      if (first == text) return true;
      final last = prefs.get(corruptLastBackupKey);
      if (last == text) return true;
      if (first == null) {
        final ok = await prefs.setString(corruptBackupKey, text);
        await prefs.reload();
        return ok && prefs.get(corruptBackupKey) == text;
      }
      if (last == null) {
        final ok = await prefs.setString(corruptLastBackupKey, text);
        await prefs.reload();
        return ok && prefs.get(corruptLastBackupKey) == text;
      }
    } catch (_) {
      return false;
    }
    return false;
  }

  static bool _damaged(Object raw) {
    if (raw is! String) return true;
    try {
      return ferritePmiParse(jsonDecode(raw)).damaged;
    } catch (_) {
      return true;
    }
  }

  Future<void> _write(List<FerritePmiProtocol> list) async {
    final prefs = await OwnedPrefs.instance(captureOwner);
    await prefs.reload();
    final raw = prefs.get(key);
    if (raw != null && (raw is! String || raw.isNotEmpty) && _damaged(raw)) {
      if (!await _backup(prefs, raw)) {
        throw StateError('Could not preserve damaged $key before writing');
      }
    }
    final encoded = jsonEncode(ferritePmiToJson(sortFerritePmi(list)));
    final ok = await prefs.setString(key, encoded);
    if (!ok) throw StateError('SharedPreferences.setString($key) failed');
    await prefs.reload();
    if (prefs.get(key) != encoded) {
      throw StateError('Ferrite PMI history was not persisted');
    }
  }

  /// Zapisuje nowy albo zmieniony protokół. Pusty (nic nie wpisano) nie
  /// trafia do historii — a jeśli był zapisany, znika. NOWY protokół przy
  /// pełnej historii → [FerritePmiStoreFull] (nic nie jest przycinane).
  Future<void> upsert(FerritePmiProtocol p) => _serial(() async {
        final load = await _loadNow();
        if (load.readFailed) throw StateError('Could not read $key');
        final list = [...load.protocols];
        final existed = list.any((e) => e.id == p.id);
        list.removeWhere((e) => e.id == p.id);
        if (!p.isBlank) {
          if (!existed && list.length >= maxEntries) {
            throw const FerritePmiStoreFull();
          }
          list.add(p);
        }
        await _write(list);
      });

  /// „Cofnij” po usunięciu: przywraca protokół ZAWSZE, także przy pełnej
  /// historii (to dane, które już były zapisane).
  Future<void> restore(FerritePmiProtocol p) => _serial(() async {
        final load = await _loadNow();
        if (load.readFailed) throw StateError('Could not read $key');
        final list = [...load.protocols]
          ..removeWhere((e) => e.id == p.id)
          ..add(p);
        await _write(list);
      });

  Future<void> delete(String id) => _serial(() async {
        final load = await _loadNow();
        if (load.readFailed) throw StateError('Could not read $key');
        final list = [...load.protocols]..removeWhere((e) => e.id == id);
        await _write(list);
      });
}
