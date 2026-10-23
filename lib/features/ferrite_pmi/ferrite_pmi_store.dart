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
import '../../services/owned_prefs.dart';

import '../../domain/ferrite_pmi/ferrite_pmi_protocol.dart';

/// Wynik odczytu historii.
class FerritePmiLoad {
  final List<FerritePmiProtocol> protocols;

  /// Zapis był nieczytelny w całości (historia pusta).
  final bool unreadable;
  final int droppedProtocols;
  final int droppedItems;

  const FerritePmiLoad(
    this.protocols, {
    this.unreadable = false,
    this.droppedProtocols = 0,
    this.droppedItems = 0,
  });

  bool get damaged => unreadable || droppedProtocols > 0 || droppedItems > 0;
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

  /// Kopia późniejszego, innego nieczytelnego zapisu (ostatnia).
  static const String corruptLastBackupKey = '${key}_corrupt_last';

  /// Tyle protokołów mieści historia; od [warnAt] (90 %) ekran ostrzega.
  static const int maxEntries = 200;
  static const int warnAt = 180;

  const FerritePmiStore();

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
    final prefs = await OwnedPrefs.instance();
    Object? raw;
    try {
      raw = prefs.get(key);
      if (raw == null || (raw is String && raw.isEmpty)) {
        return const FerritePmiLoad([]);
      }
      if (raw is! String) throw const FormatException('not a string');
      final parsed = ferritePmiParse(jsonDecode(raw));
      if (parsed.damaged) await _backup(prefs, raw);
      return FerritePmiLoad(
        sortFerritePmi(parsed.protocols),
        droppedProtocols: parsed.droppedProtocols,
        droppedItems: parsed.droppedItems,
      );
    } catch (_) {
      if (raw != null) await _backup(prefs, raw);
      return const FerritePmiLoad([], unreadable: true);
    }
  }

  static Future<void> _backup(SharedPreferences prefs, Object raw) async {
    final text = raw.toString();
    final first = prefs.get(corruptBackupKey);
    if (first == null) {
      await prefs.setString(corruptBackupKey, text);
    } else if (first != text && prefs.get(corruptLastBackupKey) != text) {
      await prefs.setString(corruptLastBackupKey, text);
    }
  }

  Future<void> _write(List<FerritePmiProtocol> list) async {
    final prefs = await OwnedPrefs.instance();
    final ok = await prefs.setString(
        key, jsonEncode(ferritePmiToJson(sortFerritePmi(list))));
    if (!ok) throw StateError('SharedPreferences.setString($key) failed');
  }

  /// Zapisuje nowy albo zmieniony protokół. Pusty (nic nie wpisano) nie
  /// trafia do historii — a jeśli był zapisany, znika. NOWY protokół przy
  /// pełnej historii → [FerritePmiStoreFull] (nic nie jest przycinane).
  Future<void> upsert(FerritePmiProtocol p) => _serial(() async {
        final list = [...(await _loadNow()).protocols];
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
        final list = [...(await _loadNow()).protocols]
          ..removeWhere((e) => e.id == p.id)
          ..add(p);
        await _write(list);
      });

  Future<void> delete(String id) => _serial(() async {
        final list = [...(await _loadNow()).protocols]
          ..removeWhere((e) => e.id == id);
        await _write(list);
      });
}
