// Historia pomiarów „Warunki do spawania” i progi w SharedPreferences
// (JSON) — bez zmian schematu bazy.
//
// Uszkodzenia nie znikają po cichu:
//  • historia — przed PIERWSZYM nadpisaniem uszkodzonego zapisu jego surowy
//    tekst trafia pod [WeatherCheckStore.corruptHistoryKey] (tylko gdy kopii
//    jeszcze nie ma), a ekran mówi, ile wpisów pominięto;
//  • progi — odczyt zwraca flagę „naprawiono”, ekran pokazuje baner.
// Wartości czytane przez `prefs.get` — wartość złego typu (np. liczba pod
// kluczem tekstu) nie rzuca, tylko liczy się jako uszkodzenie.

import 'package:shared_preferences/shared_preferences.dart';

import '../../domain/welding/weather_conditions.dart';

class WeatherCheckStore {
  static const String historyKey = 'weather_checks_v1';
  static const String corruptHistoryKey = 'weather_checks_v1_corrupt';
  static const String thresholdsKey = 'weather_thresholds_v1';

  /// Najstarsze wpisy ponad limit są usuwane przy zapisie (ekran uprzedza
  /// od [warnRecords] i mówi, ile usunięto).
  static const int maxRecords = 300;
  static const int warnRecords = 270;

  const WeatherCheckStore();

  Future<WeatherHistoryDecode> loadHistoryDetailed() async {
    final prefs = await SharedPreferences.getInstance();
    return decodeWeatherHistoryDetailed(prefs.get(historyKey));
  }

  Future<List<WeatherCheckRecord>> loadHistory() async =>
      (await loadHistoryDetailed()).records;

  /// Kopia surowego, uszkodzonego zapisu — tylko raz (pierwsza kopia
  /// zostaje, kolejne nadpisania jej nie ruszają).
  static Future<void> _backupIfDamaged(SharedPreferences prefs) async {
    final raw = prefs.get(historyKey);
    if (!decodeWeatherHistoryDetailed(raw).damaged) return;
    if (prefs.get(corruptHistoryKey) != null) return;
    await prefs.setString(corruptHistoryKey, raw is String ? raw : '$raw');
  }

  /// Zapisuje historię (najnowsze pierwsze, najwyżej [maxRecords]).
  /// Zwraca liczbę usuniętych najstarszych wpisów.
  Future<int> saveHistory(List<WeatherCheckRecord> records) async {
    final prefs = await SharedPreferences.getInstance();
    await _backupIfDamaged(prefs);
    final sorted = [...records]..sort((a, b) => b.takenAt.compareTo(a.takenAt));
    final kept = sorted.take(maxRecords).toList(growable: false);
    await prefs.setString(historyKey, encodeWeatherHistory(kept));
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
    final prefs = await SharedPreferences.getInstance();
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
    final prefs = await SharedPreferences.getInstance();
    final ok = t.isDefault
        ? await prefs.remove(thresholdsKey)
        : await prefs.setString(thresholdsKey, encodeWeatherThresholds(t));
    if (!ok) throw StateError('weather: nie zapisano progów');
  }
}
