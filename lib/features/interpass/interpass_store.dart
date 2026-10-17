// Rejestr temperatury podgrzania i międzyściegowej w SharedPreferences
// (JSON z wersją w kluczu i w treści) — bez zmian schematu bazy.
//
// Odporność: odczyt przez `prefs.get` (inny typ pod kluczem nie wywraca
// ekranu), uszkodzony zapis albo pominięte wpisy → kopia surowego tekstu
// pod osobnym kluczem PRZED pierwszym nadpisaniem; operacje szeregowane
// (zapis przy każdej zmianie, odczyt po powrocie zawsze widzi ostatni zapis).

import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../domain/welding/interpass_log.dart';

/// Wynik odczytu rejestru.
class InterpassLoad {
  final List<InterpassWeld> welds;

  /// Zapis był (całkiem albo częściowo) nieczytelny — surowy tekst jest
  /// w [InterpassStore.corruptBackupKey].
  final bool corrupt;
  const InterpassLoad(this.welds, {this.corrupt = false});
}

/// Rejestr pełny — nowej spoiny nie zapisano (stare nie wypadają po cichu:
/// to dowody dla QC).
class InterpassStoreFull implements Exception {
  const InterpassStoreFull();
  @override
  String toString() => 'InterpassStoreFull(${InterpassStore.maxWelds})';
}

class InterpassStore {
  static const String key = 'interpass_log_v1';

  /// Kopia nieczytelnego zapisu — zanim pierwszy zapis go nadpisze.
  static const String corruptBackupKey = '${key}_corrupt';

  /// Jednostka wyświetlania (`c` / `f`) — osobno od danych.
  static const String unitKey = 'interpass_unit_v1';

  /// Tyle spoin mieści rejestr; od [warnAt] ekran ostrzega.
  static const int maxWelds = 200;
  static const int warnAt = 180;

  const InterpassStore();

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

  /// Spoiny od ostatnio zmienionej.
  Future<InterpassLoad> load() => _serial(_loadNow);

  Future<InterpassLoad> _loadNow() async {
    final prefs = await SharedPreferences.getInstance();
    Object? raw;
    try {
      raw = prefs.get(key);
      if (raw == null || (raw is String && raw.isEmpty)) {
        return const InterpassLoad([]);
      }
      if (raw is! String) throw const FormatException('not a string');
      final parsed = interpassLogFromJson(jsonDecode(raw));
      if (parsed.dropped > 0) {
        await _backup(prefs, raw);
        return InterpassLoad(sortInterpassWelds(parsed.welds), corrupt: true);
      }
      return InterpassLoad(sortInterpassWelds(parsed.welds));
    } catch (_) {
      if (raw != null) await _backup(prefs, raw);
      return const InterpassLoad([], corrupt: true);
    }
  }

  /// Tylko pierwsza kopia — kolejne odczyty jej nie nadpisują.
  static Future<void> _backup(SharedPreferences prefs, Object raw) async {
    if (prefs.containsKey(corruptBackupKey)) return;
    await prefs.setString(corruptBackupKey, raw.toString());
  }

  Future<void> _write(List<InterpassWeld> list) async {
    final prefs = await SharedPreferences.getInstance();
    final ok = await prefs.setString(
        key, jsonEncode(interpassLogToJson(sortInterpassWelds(list))));
    if (!ok) throw StateError('SharedPreferences.setString($key) failed');
  }

  /// Zapisuje (nową albo zmienioną) spoinę. Pusta spoina (nic nie wpisano)
  /// nie trafia do rejestru — a jeśli była zapisana, znika. Nowa spoina
  /// przy pełnym rejestrze → [InterpassStoreFull].
  Future<void> upsert(InterpassWeld weld) => _serial(() async {
        final list = [...(await _loadNow()).welds];
        final existed = list.any((w) => w.id == weld.id);
        list.removeWhere((w) => w.id == weld.id);
        if (!weld.isBlank) {
          if (!existed && list.length >= maxWelds) {
            throw const InterpassStoreFull();
          }
          list.add(weld);
        }
        await _write(list);
      });

  Future<void> delete(String id) => _serial(() async {
        final list = [...(await _loadNow()).welds]
          ..removeWhere((w) => w.id == id);
        await _write(list);
      });

  Future<InterpassUnit> loadUnit() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return InterpassUnit.byName(prefs.get(unitKey)) ?? InterpassUnit.c;
    } catch (_) {
      return InterpassUnit.c;
    }
  }

  Future<void> saveUnit(InterpassUnit unit) async {
    final prefs = await SharedPreferences.getInstance();
    final ok = await prefs.setString(unitKey, unit.name);
    if (!ok) throw StateError('SharedPreferences.setString($unitKey) failed');
  }
}
