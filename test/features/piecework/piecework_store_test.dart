// Stawki akordu w SharedPreferences: zapis i odczyt, uszkodzony zapis
// kopiowany raz przed nadpisaniem, minimum z „Ile brać za godzinę" tylko
// gdy kalkulator był zapisany.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:cut_list_app/domain/piecework/piecework.dart';
import 'package:cut_list_app/domain/quotes/hourly_rate.dart';
import 'package:cut_list_app/domain/quotes/quote_calculator.dart'
    show toGrosze;
import 'package:cut_list_app/features/piecework/piecework_store.dart';
import 'package:cut_list_app/services/quote_settings.dart'
    show HourlyRateStore;

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

  test('uszkodzony zapis: kopia surowego tekstu przed nadpisaniem, tylko raz',
      () async {
    SharedPreferences.setMockInitialValues(
        {PieceworkRatesStore.key: '{"rate": 4500, "ss": "dużo"'});
    final load = await store.load();
    expect(load.damaged, isTrue);
    expect(load.rates, const PieceworkRates());

    await store.save(const PieceworkRates(rateGrosze: 5000));
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(PieceworkRatesStore.corruptKey),
        '{"rate": 4500, "ss": "dużo"');
    expect(decodePieceworkRates(prefs.getString(PieceworkRatesStore.key))
        .rates
        .rateGrosze, 5000);

    // Kolejne uszkodzenie nie nadpisuje pierwszej kopii.
    await prefs.setString(PieceworkRatesStore.key, '[1]');
    expect((await store.load()).damaged, isTrue);
    await store.save(const PieceworkRates(rateGrosze: 6000));
    expect(prefs.getString(PieceworkRatesStore.corruptKey),
        '{"rate": 4500, "ss": "dużo"');
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
