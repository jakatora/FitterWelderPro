// Historia pomiarów „Warunki do spawania” i progi w SharedPreferences
// (JSON) — bez zmian schematu bazy.
//
// Uszkodzenia nie znikają po cichu:
//  • historia — przed nadpisaniem uszkodzonego zapisu jego surowy tekst
//    trafia pod jeden z dwóch nienadpisywanych kluczy kopii, a ekran mówi,
//    ile wpisów pominięto;
//  • progi — odczyt zwraca flagę „naprawiono”, ekran pokazuje baner.
// Wartości czytane przez `prefs.get` — wartość złego typu (np. liczba pod
// kluczem tekstu) nie rzuca, tylko liczy się jako uszkodzenie.

import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import '../../database/local_record_owner.dart';
import '../../services/owned_prefs.dart';

import '../../domain/welding/weather_conditions.dart';

class WeatherCheckStore {
  static const String historyKey = 'weather_checks_v1';
  static const String corruptHistoryKey = 'weather_checks_v1_corrupt';
  static const String secondCorruptHistoryKey = '${corruptHistoryKey}_2';
  static const String thresholdsKey = 'weather_thresholds_v1';

  /// Najstarsze wpisy ponad limit są usuwane przy zapisie (ekran uprzedza
  /// od [warnRecords] i mówi, ile usunięto).
  static const int maxRecords = 300;
  static const int warnRecords = 270;

  const WeatherCheckStore({this.captureOwner});

  final Future<LocalRecordOwner> Function()? captureOwner;

  static Future<void>? _historyTail;
  static int _historyInFlight = 0;

  /// Odczyt i zapis jednej zmiany historii muszą pozostać razem. Właściciel
  /// jest uchwycony przed oczekiwaniem, aby kolejka nie przeszła na inne konto.
  Future<T> _mutateHistory<T>(
      Future<T> Function(LocalRecordOwner owner) operation) {
    final ownerFuture = (captureOwner ?? LocalRecordOwner.capture)();
    final previous = _historyInFlight > 0 ? _historyTail : null;
    _historyInFlight++;
    final result = _runHistoryMutation(ownerFuture, previous, operation);
    _historyTail = result
        .then<void>((_) {}, onError: (Object _) {})
        .whenComplete(() => _historyInFlight--);
    return result;
  }

  static Future<T> _runHistoryMutation<T>(
      Future<LocalRecordOwner> ownerFuture,
      Future<void>? previous,
      Future<T> Function(LocalRecordOwner owner) operation) async {
    final LocalRecordOwner owner;
    if (previous == null) {
      owner = await ownerFuture;
    } else {
      // Czekaj na oba Future nawet gdy uchwycenie konta się nie uda.
      // Odrzucona środkowa operacja nie może przepuścić następnej przed
      // zakończeniem wcześniejszego zapisu.
      final ready = await Future.wait<Object?>([previous, ownerFuture]);
      owner = ready[1]! as LocalRecordOwner;
    }
    owner.requireCurrent();
    return operation(owner);
  }

  static Future<WeatherHistoryDecode> _loadHistoryFor(
      LocalRecordOwner owner) async {
    final prefs = await OwnedPrefs.instance(() async => owner);
    await prefs.reload();
    return decodeWeatherHistoryDetailed(prefs.get(historyKey));
  }

  Future<WeatherHistoryDecode> loadHistoryDetailed() async {
    final owner = await (captureOwner ?? LocalRecordOwner.capture)();
    return _loadHistoryFor(owner);
  }

  Future<List<WeatherCheckRecord>> loadHistory() async =>
      (await loadHistoryDetailed()).records;

  /// Zachowaj każde nowe uszkodzenie w wolnym miejscu; pełne kopie blokują
  /// nadpisanie bieżącej surowej wartości.
  static Future<void> _backupIfDamaged(SharedPreferences prefs) async {
    final raw = prefs.get(historyKey);
    if (!decodeWeatherHistoryDetailed(raw).damaged) return;
    final copy = raw is String ? raw : jsonEncode(raw);
    String? free;
    for (final backupKey in [corruptHistoryKey, secondCorruptHistoryKey]) {
      final existing = prefs.get(backupKey);
      if (existing == copy) return;
      if (existing == null && free == null) free = backupKey;
    }
    if (free == null || !await prefs.setString(free, copy)) {
      throw StateError('weather: nie zapisano kopii historii');
    }
    await prefs.reload();
    if (prefs.get(free) != copy) {
      throw StateError('weather: nie potwierdzono kopii historii');
    }
  }

  /// Zapisuje historię (najnowsze pierwsze, najwyżej [maxRecords]).
  /// Zwraca liczbę usuniętych najstarszych wpisów.
  Future<int> saveHistory(List<WeatherCheckRecord> records) {
    final snapshot = List<WeatherCheckRecord>.of(records);
    return _mutateHistory((owner) => _saveHistoryFor(snapshot, owner));
  }

  static Future<int> _saveHistoryFor(
      List<WeatherCheckRecord> records, LocalRecordOwner owner) async {
    final prefs = await OwnedPrefs.instance(() async => owner);
    await prefs.reload();
    await _backupIfDamaged(prefs);
    final sorted = [...records]..sort((a, b) => b.takenAt.compareTo(a.takenAt));
    final kept = sorted.take(maxRecords).toList(growable: false);
    final encoded = encodeWeatherHistory(kept);
    if (!await prefs.setString(historyKey, encoded)) {
      throw StateError('weather: nie zapisano historii');
    }
    await prefs.reload();
    if (prefs.get(historyKey) != encoded) {
      throw StateError('weather: nie potwierdzono zapisu historii');
    }
    return sorted.length - kept.length;
  }

  /// Dopisuje [record] na początek historii. `dropped` — ile najstarszych
  /// wpisów usunięto przez limit.
  Future<({List<WeatherCheckRecord> records, int dropped})> add(
          WeatherCheckRecord record) =>
      _mutateHistory((owner) async {
        final list = [record, ...(await _loadHistoryFor(owner)).records];
        final dropped = await _saveHistoryFor(list, owner);
        return (
          records: (await _loadHistoryFor(owner)).records,
          dropped: dropped
        );
      });

  Future<List<WeatherCheckRecord>> remove(String id) =>
      _mutateHistory((owner) async {
        final list = (await _loadHistoryFor(owner))
            .records
            .where((r) => r.id != id)
            .toList();
        await _saveHistoryFor(list, owner);
        return (await _loadHistoryFor(owner)).records;
      });

  Future<({WeatherThresholds thresholds, bool repaired})>
      loadThresholdsDetailed() async {
    final prefs = await OwnedPrefs.instance(captureOwner);
    await prefs.reload();
    final raw = prefs.get(thresholdsKey);
    if (raw != null && raw is! String) {
      return (thresholds: WeatherThresholds.defaults, repaired: true);
    }
    return decodeWeatherThresholdsDetailed(raw as String?);
  }

  Future<WeatherThresholds> loadThresholds() async =>
      (await loadThresholdsDetailed()).thresholds;

  /// Rzuca, gdy zapis się nie uda — ekran pokazuje to spawaczowi.
  Future<void> saveThresholds(WeatherThresholds t) async {
    final prefs = await OwnedPrefs.instance(captureOwner);
    await prefs.reload();
    final encoded = t.isDefault ? null : encodeWeatherThresholds(t);
    final ok = t.isDefault
        ? await prefs.remove(thresholdsKey)
        : await prefs.setString(thresholdsKey, encoded!);
    if (!ok) throw StateError('weather: nie zapisano progów');
    await prefs.reload();
    if (prefs.get(thresholdsKey) != encoded) {
      throw StateError('weather: nie potwierdzono zapisu progów');
    }
  }
}
