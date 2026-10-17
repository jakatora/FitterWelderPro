// Historia pomiarów „Warunki do spawania” i progi w SharedPreferences
// (JSON) — bez zmian schematu bazy. Uszkodzony JSON nie wywraca ekranu:
// historia wraca pusta (albo bez uszkodzonych wpisów), progi — domyślne.

import 'package:shared_preferences/shared_preferences.dart';

import '../../domain/welding/weather_conditions.dart';

class WeatherCheckStore {
  static const String historyKey = 'weather_checks_v1';
  static const String thresholdsKey = 'weather_thresholds_v1';

  /// Najstarsze wpisy ponad limit są usuwane przy zapisie.
  static const int maxRecords = 300;

  const WeatherCheckStore();

  Future<List<WeatherCheckRecord>> loadHistory() async {
    final prefs = await SharedPreferences.getInstance();
    return decodeWeatherHistory(prefs.getString(historyKey));
  }

  Future<void> saveHistory(List<WeatherCheckRecord> records) async {
    final prefs = await SharedPreferences.getInstance();
    final sorted = [...records]..sort((a, b) => b.takenAt.compareTo(a.takenAt));
    await prefs.setString(historyKey,
        encodeWeatherHistory(sorted.take(maxRecords).toList(growable: false)));
  }

  /// Dopisuje [record] na początek historii.
  Future<List<WeatherCheckRecord>> add(WeatherCheckRecord record) async {
    final list = [record, ...await loadHistory()];
    await saveHistory(list);
    return loadHistory();
  }

  Future<List<WeatherCheckRecord>> remove(String id) async {
    final list = (await loadHistory()).where((r) => r.id != id).toList();
    await saveHistory(list);
    return list;
  }

  Future<WeatherThresholds> loadThresholds() async {
    final prefs = await SharedPreferences.getInstance();
    return decodeWeatherThresholds(prefs.getString(thresholdsKey));
  }

  Future<void> saveThresholds(WeatherThresholds t) async {
    final prefs = await SharedPreferences.getInstance();
    if (t.isDefault) {
      await prefs.remove(thresholdsKey);
    } else {
      await prefs.setString(thresholdsKey, encodeWeatherThresholds(t));
    }
  }
}
