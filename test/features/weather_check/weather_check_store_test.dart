import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:cut_list_app/database/local_record_owner.dart';
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

class _DelayedFirstHistoryWrite extends InMemorySharedPreferencesStore {
  _DelayedFirstHistoryWrite() : super.empty();

  final firstEntered = Completer<void>();
  final releaseFirst = Completer<void>();
  final secondEntered = Completer<void>();
  var writes = 0;
  var armed = true;

  @override
  Future<bool> setValue(String valueType, String key, Object value) async {
    if (armed && key == 'flutter.${WeatherCheckStore.historyKey}') {
      writes++;
      if (writes == 1) {
        firstEntered.complete();
        await releaseFirst.future;
      } else if (writes == 2) {
        secondEntered.complete();
      }
    }
    return super.setValue(valueType, key, value);
  }
}

WeatherCheckRecord _record(String id) => WeatherCheckRecord(
      id: id,
      takenAt: DateTime(2026, 10, 30),
      input: const WeatherInput(ambientC: 10, rhPct: 60, windMs: 1),
      verdict: WeatherVerdict.conditional,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const store = WeatherCheckStore();

  test('opóźniony właściciel nie przywraca starszych progów pogody', () async {
    SharedPreferences.setMockInitialValues({});
    final owner = await LocalRecordOwner.capture();
    final entered = Completer<void>();
    final release = Completer<void>();
    var calls = 0;
    final delayed = WeatherCheckStore(captureOwner: () async {
      if (++calls == 1) {
        entered.complete();
        await release.future;
      }
      return owner;
    });
    final older =
        delayed.saveThresholds(const WeatherThresholds(maxWindGasMs: 1.5));
    await entered.future;
    final newer =
        delayed.saveThresholds(const WeatherThresholds(maxWindGasMs: 1));
    final reading = store.loadThresholds();
    await Future<void>.delayed(Duration.zero);
    release.complete();
    await Future.wait([older, newer]);
    expect((await reading).maxWindGasMs, 1);
    expect((await store.loadThresholds()).maxWindGasMs, 1);
  });

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

  test('opóźniony pierwszy pomiar nie usuwa drugiego z historii', () async {
    SharedPreferences.setMockInitialValues({});
    final disk = _DelayedFirstHistoryWrite();
    SharedPreferencesStorePlatform.instance = disk;

    final first = store.add(_record('pierwszy'));
    await disk.firstEntered.future;
    final second = store.add(_record('drugi'));
    await Future.any<void>([
      disk.secondEntered.future,
      Future<void>.delayed(const Duration(milliseconds: 300)),
    ]);
    disk.releaseFirst.complete();
    await Future.wait([first, second]);

    expect((await store.loadHistory()).map((r) => r.id).toSet(),
        {'pierwszy', 'drugi'});
  });

  test('dodanie po opóźnionym usunięciu nie gubi nowego pomiaru', () async {
    SharedPreferences.setMockInitialValues({});
    final disk = _DelayedFirstHistoryWrite()..armed = false;
    SharedPreferencesStorePlatform.instance = disk;
    await disk.setValue('String', 'flutter.${WeatherCheckStore.historyKey}',
        encodeWeatherHistory([_record('stary')]));
    disk.armed = true;

    final deletion = store.remove('stary');
    await disk.firstEntered.future;
    final addition = store.add(_record('nowy'));
    await Future.any<void>([
      disk.secondEntered.future,
      Future<void>.delayed(const Duration(milliseconds: 300)),
    ]);
    disk.releaseFirst.complete();
    await Future.wait([deletion, addition]);

    expect((await store.loadHistory()).map((r) => r.id).toList(), ['nowy']);
  });

  test('błąd środkowej operacji nie omija wcześniejszego zapisu', () async {
    SharedPreferences.setMockInitialValues({});
    final disk = _DelayedFirstHistoryWrite();
    SharedPreferencesStorePlatform.instance = disk;

    final first = store.add(_record('pierwszy'));
    await disk.firstEntered.future;
    final rejected = WeatherCheckStore(
            captureOwner: () async => throw StateError('brak sesji'))
        .add(_record('odrzucony'));
    final rejectedCheck = expectLater(rejected, throwsA(isA<StateError>()));
    final third = store.add(_record('trzeci'));
    await Future.any<void>([
      disk.secondEntered.future,
      Future<void>.delayed(const Duration(milliseconds: 300)),
    ]);
    disk.releaseFirst.complete();
    await Future.wait([first, third]);
    await rejectedCheck;

    expect((await store.loadHistory()).map((r) => r.id).toSet(),
        {'pierwszy', 'trzeci'});
  });
}
