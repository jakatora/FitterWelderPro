// Zapis ostatniej tabliczki spawarki: uszkodzony zapis nie znika po cichu —
// surowy tekst trafia raz pod klucz kopii; inny typ wartości w prefs nie
// wywala odczytu.

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:cut_list_app/domain/welding/power_source.dart';
import 'package:cut_list_app/features/power_source/power_source_plate_store.dart';

void main() {
  const store = PowerSourcePlateStore();

  test('zapis i odczyt tabliczki', () async {
    SharedPreferences.setMockInitialValues({});
    expect(await store.load(), isEmpty);
    await store.save(const [PlatePoint(200, 35), PlatePoint(160, 60)]);
    expect(
        await store.load(), const [PlatePoint(200, 35), PlatePoint(160, 60)]);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.containsKey(kPowerSourcePlateCorruptPrefsKey), isFalse);
  });

  test('zapis zachowuje kopię uszkodzonej tabliczki nawet bez odczytu',
      () async {
    SharedPreferences.setMockInitialValues(
        {kPowerSourcePlatePrefsKey: 'zepsute'});
    await store.save(const [PlatePoint(200, 35)]);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(kPowerSourcePlateCorruptPrefsKey), 'zepsute');
    expect(await store.load(), const [PlatePoint(200, 35)]);
  });

  test('zajęta kopia blokuje nadpisanie innego uszkodzonego zapisu', () async {
    SharedPreferences.setMockInitialValues({
      kPowerSourcePlatePrefsKey: 'drugie uszkodzenie',
      kPowerSourcePlateCorruptPrefsKey: 'pierwsze uszkodzenie',
    });
    await expectLater(
        store.save(const [PlatePoint(200, 35)]), throwsA(isA<StateError>()));
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(kPowerSourcePlatePrefsKey), 'drugie uszkodzenie');
    expect(prefs.getString(kPowerSourcePlateCorruptPrefsKey),
        'pierwsze uszkodzenie');
  });

  test('uszkodzony JSON: pusta lista i kopia surowego zapisu', () async {
    SharedPreferences.setMockInitialValues(
        {kPowerSourcePlatePrefsKey: '{"v":1,"points":[{"i":'});
    expect(await store.load(), isEmpty);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(kPowerSourcePlateCorruptPrefsKey),
        '{"v":1,"points":[{"i":');
  });

  test('kopia tylko raz — kolejne uszkodzenie jej nie nadpisuje', () async {
    SharedPreferences.setMockInitialValues({
      kPowerSourcePlatePrefsKey: 'drugie uszkodzenie',
      kPowerSourcePlateCorruptPrefsKey: 'pierwsze uszkodzenie',
    });
    expect(await store.load(), isEmpty);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(kPowerSourcePlateCorruptPrefsKey),
        'pierwsze uszkodzenie');
  });

  test('częściowo uszkodzony zapis: dobre punkty zostają, kopia zapisana',
      () async {
    const raw = '{"v":1,"points":[{"i":200,"x":35},{"i":-1,"x":60}]}';
    SharedPreferences.setMockInitialValues({kPowerSourcePlatePrefsKey: raw});
    expect(await store.load(), const [PlatePoint(200, 35)]);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(kPowerSourcePlateCorruptPrefsKey), raw);
  });

  test('inny typ wartości w prefs (liczba, lista) nie wywala odczytu',
      () async {
    for (final value in <Object>[
      5,
      true,
      <String>['a', 'b']
    ]) {
      SharedPreferences.setMockInitialValues(
          {kPowerSourcePlatePrefsKey: value});
      expect(await store.load(), isEmpty, reason: '$value');
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(kPowerSourcePlateCorruptPrefsKey), isNotNull,
          reason: '$value');
    }
  });
}
