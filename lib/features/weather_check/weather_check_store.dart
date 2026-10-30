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

  Future<WeatherHistoryDecode> loadHistoryDetailed() async {
    final prefs = await OwnedPrefs.instance(captureOwner);
    await prefs.reload();
    return decodeWeatherHistoryDetailed(prefs.get(historyKey));
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
  Future<int> saveHistory(List<WeatherCheckRecord> records) async {
    final prefs = await OwnedPrefs.instance(captureOwner);
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
      WeatherCheckRecord record) async {
    final list = [record, ...(await loadHistoryDetailed()).records];
    final dropped = await saveHistory(list);
    return (records: await loadHistory(), dropped: dropped);
  }

  Future<List<WeatherCheckRecord>> remove(String id) async {
    final list =
        (await loadHistoryDetailed()).records.where((r) => r.id != id).toList();
    await saveHistory(list);
    return list;
  }

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
