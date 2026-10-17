// Historia protokołów „Przestrzeń zamknięta” w SharedPreferences (JSON
// z wersją w kluczu i w treści) — bez zmian schematu bazy.
//
// Odporność (wzór: prace pożarowe, rejestr międzyściegowy):
// * odczyt przez `prefs.get` — inny typ pod kluczem nie wywraca ekranu;
// * nieczytelny zapis ALBO pominięte protokoły / pomiary (także pomiary
//   z przyszłości względem zegara) → kopia surowego tekstu PRZED pierwszym
//   nadpisaniem i flaga dla banera na ekranie (nic nie znika po cichu);
// * operacje szeregowane — odczyt po zapisie zawsze widzi ten zapis;
// * [update] działa na zapisanym protokole — „Cofnij” po zamknięciu ekranu
//   nie zależy od tego, czy ekran jeszcze istnieje;
// * historia ma limit [ConfinedSpaceStore.maxEntries] — przy pełnej NOWY
//   protokół jest odrzucany ([ConfinedSpaceStoreFull]), stare nigdy nie
//   wypadają po cichu; od [ConfinedSpaceStore.warnAt] ekran ostrzega.

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

/// Historia pełna — nowego protokołu nie zapisano (stare nie wypadają po
/// cichu: to dowody dla nadzoru).
class ConfinedSpaceStoreFull implements Exception {
  const ConfinedSpaceStoreFull();
  @override
  String toString() =>
      'ConfinedSpaceStoreFull(${ConfinedSpaceStore.maxEntries})';
}

class ConfinedSpaceStore {
  static const String key = 'confined_space_records_v1';

  /// Kopia PIERWSZEGO nieczytelnego zapisu (nigdy nienadpisywana).
  static const String corruptBackupKey = '${key}_corrupt';

  /// Kopia późniejszego, innego nieczytelnego zapisu (ostatnia).
  static const String corruptLastBackupKey = '${key}_corrupt_last';

  /// Tyle protokołów mieści historia; od [warnAt] (90 %) ekran ostrzega.
  static const int maxEntries = 200;
  static const int warnAt = 180;

  /// Zegar do odrzucania pomiarów „z przyszłości” przy odczycie; `null` =
  /// zegar systemowy. Ekrany podają swój (wstrzykiwany w testach).
  final DateTime Function()? clock;

  const ConfinedSpaceStore({this.clock});

  /// Ten sam magazyn z zegarem [c], jeśli nie ma własnego.
  ConfinedSpaceStore withClock(DateTime Function() c) =>
      clock == null ? ConfinedSpaceStore(clock: c) : this;

  DateTime _now() => (clock ?? DateTime.now)();

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

  /// Rośnie po każdym zapisie — lista odświeża się np. po „Cofnij”
  /// wykonanym już po zamknięciu ekranu protokołu.
  static final ValueNotifier<int> changes = ValueNotifier<int>(0);

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
      final parsed =
          confinedSpaceRecordsFromJson(jsonDecode(raw), now: _now());
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

  /// Zapis całej listy — bez przycinania (limit pilnuje [_upsertNow]).
  Future<void> _write(List<ConfinedSpaceRecord> list) async {
    final prefs = await SharedPreferences.getInstance();
    final ok = await prefs.setString(key,
        jsonEncode(confinedSpaceRecordsToJson(sortConfinedSpaceRecords(list))));
    if (!ok) throw StateError('SharedPreferences.setString($key) failed');
    changes.value++;
  }

  Future<void> _upsertNow(ConfinedSpaceRecord record) async {
    final list = [...(await _loadNow()).records];
    final existed = list.any((r) => r.id == record.id);
    list.removeWhere((r) => r.id == record.id);
    if (!record.isBlank) {
      if (!existed && list.length >= maxEntries) {
        throw const ConfinedSpaceStoreFull();
      }
      list.add(record);
    }
    await _write(list);
  }

  /// Zapisuje (nowy albo zmieniony) protokół. Pusty protokół (nic nie
  /// wpisano) nie trafia do historii — a jeśli był zapisany, znika. Nowy
  /// protokół przy pełnej historii → [ConfinedSpaceStoreFull].
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
