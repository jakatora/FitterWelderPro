// Historia protokołów „Przestrzeń zamknięta” w SharedPreferences (JSON
// z wersją w kluczu i w treści) — bez zmian schematu bazy.
//
// Odporność (wzór: prace pożarowe, rejestr międzyściegowy):
// * odczyt przez `prefs.get` — inny typ pod kluczem nie wywraca ekranu;
// * nieczytelny zapis ALBO pominięte protokoły / pomiary → kopia surowego
//   tekstu PRZED pierwszym nadpisaniem i flaga dla banera na ekranie
//   (odrzucony pomiar nie znika po cichu);
// * operacje szeregowane — odczyt po zapisie zawsze widzi ten zapis;
// * [update] działa na zapisanym protokole — „Cofnij” po zamknięciu ekranu
//   nie zależy od tego, czy ekran jeszcze istnieje.

import 'dart:convert';

import 'package:flutter/foundation.dart' show ValueNotifier;
import 'package:shared_preferences/shared_preferences.dart';

import '../../domain/confined_space/confined_space_record.dart';

/// Wynik odczytu historii.
class ConfinedSpaceLoad {
  final List<ConfinedSpaceRecord> records;

  /// Zapis był nieczytelny w całości (historia pusta).
  final bool unreadable;

  /// Ile protokołów i pomiarów pominięto jako uszkodzone.
  final int droppedRecords;
  final int droppedMeasurements;

  const ConfinedSpaceLoad(
    this.records, {
    this.unreadable = false,
    this.droppedRecords = 0,
    this.droppedMeasurements = 0,
  });

  /// Coś odrzucono — surowy tekst jest w kopii, ekran pokazuje baner.
  bool get damaged =>
      unreadable || droppedRecords > 0 || droppedMeasurements > 0;
}

class ConfinedSpaceStore {
  static const String key = 'confined_space_records_v1';

  /// Kopia PIERWSZEGO nieczytelnego zapisu (nigdy nienadpisywana).
  static const String corruptBackupKey = '${key}_corrupt';

  /// Kopia późniejszego, innego nieczytelnego zapisu (ostatnia).
  static const String corruptLastBackupKey = '${key}_corrupt_last';

  /// Tyle ostatnich protokołów trzymamy w historii (najstarsze wypadają).
  static const int maxEntries = 60;

  const ConfinedSpaceStore();

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

  /// Protokoły od najnowszego (data, potem czas zapisu).
  Future<ConfinedSpaceLoad> load() => _serial(_loadNow);

  Future<ConfinedSpaceLoad> _loadNow() async {
    final prefs = await SharedPreferences.getInstance();
    Object? raw;
    try {
      raw = prefs.get(key);
      if (raw == null || (raw is String && raw.isEmpty)) {
        return const ConfinedSpaceLoad([]);
      }
      if (raw is! String) throw const FormatException('not a string');
      final parsed = confinedSpaceRecordsFromJson(jsonDecode(raw));
      if (parsed.damaged) await _backup(prefs, raw);
      return ConfinedSpaceLoad(
        sortConfinedSpaceRecords(parsed.records),
        droppedRecords: parsed.droppedRecords,
        droppedMeasurements: parsed.droppedMeasurements,
      );
    } catch (_) {
      if (raw != null) await _backup(prefs, raw);
      return const ConfinedSpaceLoad([], unreadable: true);
    }
  }

  /// Pierwsza kopia zostaje na zawsze; inny, późniejszy uszkodzony zapis
  /// trafia do [corruptLastBackupKey].
  static Future<void> _backup(SharedPreferences prefs, Object raw) async {
    final text = raw.toString();
    final first = prefs.get(corruptBackupKey);
    if (first == null) {
      await prefs.setString(corruptBackupKey, text);
    } else if (first != text && prefs.get(corruptLastBackupKey) != text) {
      await prefs.setString(corruptLastBackupKey, text);
    }
  }

  /// [keepId] — protokół właśnie zapisywany nie wypada przy przycinaniu
  /// historii, nawet jeśli ma najstarszą datę.
  Future<void> _write(List<ConfinedSpaceRecord> list, {String? keepId}) async {
    final prefs = await SharedPreferences.getInstance();
    final sorted = sortConfinedSpaceRecords(list);
    var kept =
        sorted.length > maxEntries ? sorted.sublist(0, maxEntries) : sorted;
    if (keepId != null && !kept.any((r) => r.id == keepId)) {
      final saved = sorted.where((r) => r.id == keepId);
      if (saved.isNotEmpty) {
        kept = [...kept.sublist(0, kept.length - 1), saved.first];
      }
    }
    final ok = await prefs.setString(
        key, jsonEncode(confinedSpaceRecordsToJson(kept)));
    if (!ok) throw StateError('SharedPreferences.setString($key) failed');
    changes.value++;
  }

  /// Rośnie po każdym zapisie — lista odświeża się np. po „Cofnij”
  /// wykonanym już po zamknięciu ekranu protokołu.
  static final ValueNotifier<int> changes = ValueNotifier<int>(0);

  Future<void> _upsertNow(ConfinedSpaceRecord record) async {
    final list = [...(await _loadNow()).records]
      ..removeWhere((r) => r.id == record.id);
    if (!record.isBlank) list.add(record);
    await _write(list, keepId: record.id);
  }

  /// Zapisuje (nowy albo zmieniony) protokół. Pusty protokół (nic nie
  /// wpisano) nie trafia do historii — a jeśli był zapisany, znika.
  Future<void> upsert(ConfinedSpaceRecord record) =>
      _serial(() => _upsertNow(record));

  /// Zmiana ZAPISANEGO protokołu [id] (np. „Cofnij” usunięcia pomiaru po
  /// zamknięciu ekranu). Gdy protokołu już nie ma (np. zrobił się pusty
  /// i wypadł), zapisuje [orElse] po zmianie.
  Future<void> update(
    String id,
    ConfinedSpaceRecord Function(ConfinedSpaceRecord r) change, {
    ConfinedSpaceRecord? orElse,
  }) =>
      _serial(() async {
        final records = (await _loadNow()).records;
        final current = records.where((r) => r.id == id);
        final base = current.isNotEmpty ? current.first : orElse;
        if (base == null) return;
        await _upsertNow(change(base));
      });

  Future<void> delete(String id) => _serial(() async {
        final list = [...(await _loadNow()).records]
          ..removeWhere((r) => r.id == id);
        await _write(list);
      });
}

/// Najnowsze na górze: data pracy malejąco, potem ostatnia zmiana.
List<ConfinedSpaceRecord> sortConfinedSpaceRecords(
        List<ConfinedSpaceRecord> list) =>
    [...list]..sort((a, b) {
        final byDate = b.date.compareTo(a.date);
        if (byDate != 0) return byDate;
        return b.updatedAt.compareTo(a.updatedAt);
      });
