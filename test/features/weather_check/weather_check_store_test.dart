import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

import 'package:cut_list_app/domain/welding/weather_conditions.dart';
import 'package:cut_list_app/features/weather_check/weather_check_store.dart';

class _ControlledPreferences extends InMemorySharedPreferencesStore {
  _ControlledPreferences() : super.empty();

  String? refusedWriteKey;
  String? unpersistedWriteKey;
  String? unpersistedRemoveKey;

  @override
  Future<bool> setValue(String valueType, String key, Object value) async {
    if (key == refusedWriteKey) return false;
    if (key == unpersistedWriteKey) return true;
    return super.setValue(valueType, key, value);
  }

  @override
  Future<bool> remove(String key) async {
    if (key == unpersistedRemoveKey) return true;
    return super.remove(key);
  }
}

WeatherCheckRecord _record(String id) => WeatherCheckRecord(
      id: id,
      takenAt: DateTime(2026, 10, 30),
      input: const WeatherInput(ambientC: 10, rhPct: 60, windMs: 1),
      verdict: WeatherVerdict.conditional,
    );

void main() {
  const store = WeatherCheckStore();

  test('drugi uszkodzony zapis dostaje osobną kopię', () async {
    SharedPreferences.setMockInitialValues({
      WeatherCheckStore.historyKey: 'drugie uszkodzenie',
      WeatherCheckStore.corruptHistoryKey: 'pierwsze uszkodzenie',
    });
    await store.saveHistory([_record('nowy')]);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(WeatherCheckStore.corruptHistoryKey),
        'pierwsze uszkodzenie');
    expect(prefs.getString('${WeatherCheckStore.corruptHistoryKey}_2'),
        'drugie uszkodzenie');
  });

  test('pełne kopie blokują nadpisanie trzeciego uszkodzenia', () async {
    SharedPreferences.setMockInitialValues({
      WeatherCheckStore.historyKey: 'trzecie uszkodzenie',
      WeatherCheckStore.corruptHistoryKey: 'pierwsze',
      '${WeatherCheckStore.corruptHistoryKey}_2': 'drugie',
    });
    await expectLater(
        store.saveHistory([_record('nowy')]), throwsA(isA<StateError>()));
    final prefs = await SharedPreferences.getInstance();
    expect(
        prefs.getString(WeatherCheckStore.historyKey), 'trzecie uszkodzenie');
  });

  test('odmowa kopii po odczycie nie nadpisuje historii', () async {
    SharedPreferences.setMockInitialValues({});
    final disk = _ControlledPreferences();
    SharedPreferencesStorePlatform.instance = disk;
    await disk.setValue('String', 'flutter.${WeatherCheckStore.historyKey}',
        'uszkodzona historia');
    disk.refusedWriteKey = 'flutter.${WeatherCheckStore.corruptHistoryKey}';
    expect((await store.loadHistoryDetailed()).damaged, isTrue);
    await expectLater(
        store.saveHistory([_record('nowy')]), throwsA(isA<StateError>()));
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    expect(
        prefs.getString(WeatherCheckStore.historyKey), 'uszkodzona historia');
  });

  test('pozorny zapis kopii nie nadpisuje historii', () async {
    SharedPreferences.setMockInitialValues({});
    final disk = _ControlledPreferences();
    SharedPreferencesStorePlatform.instance = disk;
    await disk.setValue('String', 'flutter.${WeatherCheckStore.historyKey}',
        'uszkodzona historia');
    disk.unpersistedWriteKey = 'flutter.${WeatherCheckStore.corruptHistoryKey}';
    await expectLater(
        store.saveHistory([_record('nowy')]), throwsA(isA<StateError>()));
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    expect(
        prefs.getString(WeatherCheckStore.historyKey), 'uszkodzona historia');
  });

  test('odmowa głównego zapisu nie pokazuje nowej historii', () async {
    SharedPreferences.setMockInitialValues({});
    final disk = _ControlledPreferences();
    SharedPreferencesStorePlatform.instance = disk;
    await disk.setValue('String', 'flutter.${WeatherCheckStore.historyKey}',
        encodeWeatherHistory([_record('stary')]));
    disk.refusedWriteKey = 'flutter.${WeatherCheckStore.historyKey}';
    await expectLater(
        store.saveHistory([_record('nowy')]), throwsA(isA<StateError>()));
    expect((await store.loadHistory()).single.id, 'stary');
  });

  test('pozorny sukces głównego zapisu jest wykrywany', () async {
    SharedPreferences.setMockInitialValues({});
    final disk = _ControlledPreferences();
    SharedPreferencesStorePlatform.instance = disk;
    await disk.setValue('String', 'flutter.${WeatherCheckStore.historyKey}',
        encodeWeatherHistory([_record('stary')]));
    disk.unpersistedWriteKey = 'flutter.${WeatherCheckStore.historyKey}';
    await expectLater(
        store.saveHistory([_record('nowy')]), throwsA(isA<StateError>()));
    expect((await store.loadHistory()).single.id, 'stary');
  });

  test('odmowa zapisu progów nie zmienia kolejnego odczytu', () async {
    SharedPreferences.setMockInitialValues({});
    final disk = _ControlledPreferences();
    SharedPreferencesStorePlatform.instance = disk;
    disk.refusedWriteKey = 'flutter.${WeatherCheckStore.thresholdsKey}';
    await expectLater(
        store.saveThresholds(const WeatherThresholds(maxWindGasMs: 1.5)),
        throwsA(isA<StateError>()));
    expect((await store.loadThresholds()).maxWindGasMs,
        WeatherThresholds.kDefaultMaxWindGasMs);
  });

  test('pozorny sukces zapisu progów jest wykrywany', () async {
    SharedPreferences.setMockInitialValues({});
    final disk = _ControlledPreferences();
    SharedPreferencesStorePlatform.instance = disk;
    disk.unpersistedWriteKey = 'flutter.${WeatherCheckStore.thresholdsKey}';
    await expectLater(
        store.saveThresholds(const WeatherThresholds(maxWindGasMs: 1.5)),
        throwsA(isA<StateError>()));
    expect((await store.loadThresholds()).maxWindGasMs,
        WeatherThresholds.kDefaultMaxWindGasMs);
  });

  test('pozorny sukces przywrócenia domyślnych progów jest wykrywany',
      () async {
    SharedPreferences.setMockInitialValues({});
    final disk = _ControlledPreferences();
    SharedPreferencesStorePlatform.instance = disk;
    await disk.setValue('String', 'flutter.${WeatherCheckStore.thresholdsKey}',
        encodeWeatherThresholds(const WeatherThresholds(maxWindGasMs: 1.5)));
    disk.unpersistedRemoveKey = 'flutter.${WeatherCheckStore.thresholdsKey}';
    await expectLater(store.saveThresholds(WeatherThresholds.defaults),
        throwsA(isA<StateError>()));
    expect((await store.loadThresholds()).maxWindGasMs, 1.5);
  });
}
