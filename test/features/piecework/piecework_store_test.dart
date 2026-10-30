// Stawki akordu w SharedPreferences: zapis i odczyt, uszkodzony zapis
// kopiowany przed nadpisaniem, minimum z „Ile brać za godzinę" tylko
// gdy kalkulator był zapisany.

import 'dart:convert';
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

import 'package:cut_list_app/domain/piecework/piecework.dart';
import 'package:cut_list_app/domain/quotes/hourly_rate.dart';
import 'package:cut_list_app/domain/quotes/quote_calculator.dart' show toGrosze;
import 'package:cut_list_app/features/piecework/piecework_store.dart';
import 'package:cut_list_app/services/quote_settings.dart' show HourlyRateStore;

class _ControlledPreferences extends InMemorySharedPreferencesStore {
  _ControlledPreferences() : super.empty();

  String? refusedKey;
  String? unpersistedKey;

  @override
  Future<bool> setValue(String valueType, String key, Object value) async {
    if (key == refusedKey) return false;
    if (key == unpersistedKey) return true;
    return super.setValue(valueType, key, value);
  }
}

class _DelayedFirstWrite extends InMemorySharedPreferencesStore {
  _DelayedFirstWrite() : super.empty();

  final entered = Completer<void>();
  final release = Completer<void>();
  final secondEntered = Completer<void>();
  var writes = 0;

  @override
  Future<bool> setValue(String valueType, String key, Object value) async {
    if (key == 'flutter.${PieceworkRatesStore.key}') {
      writes++;
      if (writes == 1) {
        entered.complete();
        await release.future;
      } else if (writes == 2) {
        secondEntered.complete();
      }
    }
    return super.setValue(valueType, key, value);
  }
}

class _TransientReadStore extends PieceworkRatesStore {
  var reads = 0;

  @override
  Future<Object?> readRaw() async {
    if (reads++ == 0) throw StateError('chwilowy błąd odczytu');
    return super.readRaw();
  }
}

void main() {
  const store = PieceworkRatesStore();

  test('stawki: brak zapisu = domyślne, zapis i odczyt bez strat', () async {
    SharedPreferences.setMockInitialValues({});
    final empty = await store.load();
    expect(empty.damaged, isFalse);
    expect(empty.rates, const PieceworkRates());

    const rates = PieceworkRates(
        rateGrosze: 4500, pos6gBp: 2000, minDayGrosze: 50000, hoursPerDay: 10);
    await store.save(rates);
    final back = await store.load();
    expect(back.damaged, isFalse);
    expect(back.rates, rates);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.containsKey(PieceworkRatesStore.corruptKey), isFalse);
  });

  test('uszkodzony zapis: drugi surowy tekst ma osobną kopię', () async {
    SharedPreferences.setMockInitialValues(
        {PieceworkRatesStore.key: '{"rate": 4500, "ss": "dużo"'});
    final load = await store.load();
    expect(load.damaged, isTrue);
    expect(load.rates, const PieceworkRates());

    await store.save(const PieceworkRates(rateGrosze: 5000));
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(PieceworkRatesStore.corruptKey),
        '{"rate": 4500, "ss": "dużo"');
    expect(
        decodePieceworkRates(prefs.getString(PieceworkRatesStore.key))
            .rates
            .rateGrosze,
        5000);

    // Kolejne uszkodzenie nie nadpisuje pierwszej kopii.
    await prefs.setString(PieceworkRatesStore.key, '[1]');
    expect((await store.load()).damaged, isTrue);
    await store.save(const PieceworkRates(rateGrosze: 6000));
    expect(prefs.getString(PieceworkRatesStore.corruptKey),
        '{"rate": 4500, "ss": "dużo"');
    expect(prefs.getString('${PieceworkRatesStore.corruptKey}_2'), '[1]');
  });

  test('pełne kopie blokują nadpisanie trzeciego uszkodzenia', () async {
    SharedPreferences.setMockInitialValues({
      PieceworkRatesStore.key: 'trzecie uszkodzenie',
      PieceworkRatesStore.corruptKey: 'pierwsze',
      '${PieceworkRatesStore.corruptKey}_2': 'drugie',
    });
    await expectLater(store.save(const PieceworkRates(rateGrosze: 5000)),
        throwsA(isA<StateError>()));
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(PieceworkRatesStore.key), 'trzecie uszkodzenie');
  });

  test('odmowa kopii nie nadpisuje uszkodzonych stawek', () async {
    SharedPreferences.setMockInitialValues({});
    final disk = _ControlledPreferences();
    SharedPreferencesStorePlatform.instance = disk;
    await disk.setValue(
        'String', 'flutter.${PieceworkRatesStore.key}', 'uszkodzone stawki');
    disk.refusedKey = 'flutter.${PieceworkRatesStore.corruptKey}';
    expect((await store.load()).damaged, isTrue);
    await expectLater(store.save(const PieceworkRates(rateGrosze: 5000)),
        throwsA(isA<StateError>()));
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    expect(prefs.getString(PieceworkRatesStore.key), 'uszkodzone stawki');
  });

  test('pozorny sukces kopii nie nadpisuje uszkodzonych stawek', () async {
    SharedPreferences.setMockInitialValues({});
    final disk = _ControlledPreferences();
    SharedPreferencesStorePlatform.instance = disk;
    await disk.setValue(
        'String', 'flutter.${PieceworkRatesStore.key}', 'uszkodzone stawki');
    disk.unpersistedKey = 'flutter.${PieceworkRatesStore.corruptKey}';
    await expectLater(store.save(const PieceworkRates(rateGrosze: 5000)),
        throwsA(isA<StateError>()));
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    expect(prefs.getString(PieceworkRatesStore.key), 'uszkodzone stawki');
  });

  test('odmowa głównego zapisu nie zmienia trwałej stawki', () async {
    SharedPreferences.setMockInitialValues({});
    final disk = _ControlledPreferences();
    SharedPreferencesStorePlatform.instance = disk;
    await disk.setValue('String', 'flutter.${PieceworkRatesStore.key}',
        const PieceworkRates(rateGrosze: 4500).encode());
    disk.refusedKey = 'flutter.${PieceworkRatesStore.key}';
    await expectLater(store.save(const PieceworkRates(rateGrosze: 6000)),
        throwsA(isA<StateError>()));
    expect((await store.load()).rates.rateGrosze, 4500);
  });

  test('pozorny sukces głównego zapisu jest wykrywany', () async {
    SharedPreferences.setMockInitialValues({});
    final disk = _ControlledPreferences();
    SharedPreferencesStorePlatform.instance = disk;
    await disk.setValue('String', 'flutter.${PieceworkRatesStore.key}',
        const PieceworkRates(rateGrosze: 4500).encode());
    disk.unpersistedKey = 'flutter.${PieceworkRatesStore.key}';
    await expectLater(store.save(const PieceworkRates(rateGrosze: 6000)),
        throwsA(isA<StateError>()));
    expect((await store.load()).rates.rateGrosze, 4500);
  });

  test('opóźniony starszy zapis nie zastępuje nowszej stawki', () async {
    SharedPreferences.setMockInitialValues({});
    final disk = _DelayedFirstWrite();
    SharedPreferencesStorePlatform.instance = disk;
    final first = store.save(const PieceworkRates(rateGrosze: 4500));
    await disk.entered.future;
    final second = store.save(const PieceworkRates(rateGrosze: 6000));
    await Future.any<void>([
      disk.secondEntered.future,
      Future<void>.delayed(const Duration(milliseconds: 300)),
    ]);
    disk.release.complete();
    await Future.wait([first, second]);
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    expect(
        decodePieceworkRates(prefs.getString(PieceworkRatesStore.key))
            .rates
            .rateGrosze,
        6000);
    expect((await store.load()).rates.rateGrosze, 6000);
  });

  test('po błędzie odczytu poprzednie stawki mają kopię przed zmianą',
      () async {
    const original = PieceworkRates(rateGrosze: 4500);
    SharedPreferences.setMockInitialValues(
        {PieceworkRatesStore.key: original.encode()});
    final transient = _TransientReadStore();
    final loaded = await transient.load();
    expect(loaded.readFailed, isTrue);
    expect(loaded.rates, const PieceworkRates());
    await transient.save(const PieceworkRates(rateGrosze: 6000),
        afterFailedRead: loaded.readFailed);
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    expect(prefs.getString(PieceworkRatesStore.corruptKey), original.encode());
    expect((await transient.load()).rates.rateGrosze, 6000);
  });

  test('zapis innego typu niż tekst: uszkodzony, kopia przed nadpisaniem',
      () async {
    SharedPreferences.setMockInitialValues({PieceworkRatesStore.key: 7});
    expect((await store.load()).damaged, isTrue);
    await store.save(const PieceworkRates(rateGrosze: 100));
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(PieceworkRatesStore.corruptKey), '7');
  });

  test('stawka godzinowa: minimum z zapisanego kalkulatora, bez zapisu null',
      () async {
    SharedPreferences.setMockInitialValues({});
    expect(await loadSavedHourlyMinimum(), isNull);

    const input = HourlyRateInput(netIncome: 10000);
    SharedPreferences.setMockInitialValues(
        {HourlyRateStore.key: jsonEncode(input.toJson())});
    expect(await loadSavedHourlyMinimum(),
        toGrosze(computeHourlyRate(input).recommendedRate));

    // Kalkulator, którego nie da się policzyć (0 godzin) — brak porównania.
    SharedPreferences.setMockInitialValues({
      HourlyRateStore.key:
          jsonEncode(const HourlyRateInput(hoursPerDay: 0).toJson()),
    });
    expect(await loadSavedHourlyMinimum(), isNull);
  });
}
