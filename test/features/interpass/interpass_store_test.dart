// Zapis rejestru temperatur w SharedPreferences: kopia surowego zapisu
// przed pierwszym nadpisaniem (uszkodzony JSON, inny typ pod kluczem,
// pojedyncze nieczytelne wpisy), limit spoin bez cichego wypadania,
// pusta spoina nie trafia do rejestru, jednostka osobno od danych.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:cut_list_app/domain/welding/interpass_log.dart';
import 'package:cut_list_app/features/interpass/interpass_store.dart';

InterpassWeld _weld(String id, {int updatedAt = 1}) => InterpassWeld(
      id: id,
      weldNo: 'S-$id',
      limits: InterpassLimits.celsius(preheatMinC: 100, interpassMaxC: 250),
      readings: const [
        InterpassReading(
            pass: 1, temp: InterpassTemp.c(120), at: 1000, recordedAt: 1000),
      ],
      createdAt: 1,
      updatedAt: updatedAt,
    );

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('uszkodzony JSON: kopia surowego zapisu przed nadpisaniem', () async {
    SharedPreferences.setMockInitialValues(
        {InterpassStore.key: '{"v":1,"welds":[{"id":'});
    const store = InterpassStore();
    final first = await store.load();
    expect(first.welds, isEmpty);
    expect(first.corrupt, isTrue);
    await store.upsert(_weld('a'));
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(InterpassStore.corruptBackupKey),
        '{"v":1,"welds":[{"id":');
    final after = await store.load();
    expect(after.corrupt, isFalse);
    expect(after.welds.single.id, 'a');
    // Kolejny, INNY uszkodzony zapis nie nadpisuje pierwszej kopii — trafia
    // do następnego miejsca.
    await prefs.setString(InterpassStore.key, 'znowu źle');
    await store.load();
    expect(prefs.getString(InterpassStore.corruptBackupKey),
        '{"v":1,"welds":[{"id":');
    expect(prefs.getString(InterpassStore.corruptBackupKeys[1]), 'znowu źle');
  });

  test('inny typ pod kluczem (liczba, lista) — bez wyjątku, kopia zapisu',
      () async {
    SharedPreferences.setMockInitialValues({InterpassStore.key: 42});
    const store = InterpassStore();
    final load = await store.load();
    expect(load.welds, isEmpty);
    expect(load.corrupt, isTrue);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(InterpassStore.corruptBackupKey), '42');

    SharedPreferences.setMockInitialValues({
      InterpassStore.key: <String>['a', 'b'],
    });
    expect((await store.load()).welds, isEmpty);
    await store.upsert(_weld('b'));
    expect((await store.load()).welds.single.id, 'b');
  });

  test('nieczytelna spoina w środku: reszta wczytana, kopia całości', () async {
    final raw = jsonEncode({
      'v': 1,
      'welds': [
        _weld('ok').toJson(),
        {'bez': 'id'},
      ],
    });
    SharedPreferences.setMockInitialValues({InterpassStore.key: raw});
    const store = InterpassStore();
    final load = await store.load();
    expect(load.welds.single.id, 'ok');
    expect(load.corrupt, isTrue);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(InterpassStore.corruptBackupKey), raw);
  });

  test('pominięty uszkodzony pomiar: kopia zapisu, baner i blokada zieleni',
      () async {
    final good = _weld('w').copyWith(passCount: 1).toJson();
    final raw = jsonEncode({
      'v': 2,
      'welds': [
        {
          ...good,
          'readings': [
            ...(good['readings'] as List),
            {'pass': 1, 'temp': 'zepsute', 'bound': 'exact'},
          ],
        },
      ],
    });
    SharedPreferences.setMockInitialValues({InterpassStore.key: raw});
    const store = InterpassStore();
    final load = await store.load();
    expect(load.corrupt, isTrue);
    final w = load.welds.single;
    expect(w.lostReadings, 1);
    expect(w.assess().status, InterpassWeldStatus.lostReadings);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(InterpassStore.corruptBackupKey), raw);

    // Pierwszy zapis usuwa uszkodzony pomiar, ale nie blokadę.
    await store.upsert(w.copyWith(weldNo: 'S-zmiana'));
    final after = await store.load();
    expect(after.corrupt, isFalse);
    expect(after.welds.single.lostReadings, 1);
    expect(after.welds.single.assess().ok, isFalse);
  });

  test('kopie uszkodzonego zapisu: ta sama treść raz, inna — kolejna, maks. 3',
      () async {
    const store = InterpassStore();
    final prefs = await SharedPreferences.getInstance();
    Future<void> corrupt(String raw) async {
      await prefs.setString(InterpassStore.key, raw);
      await store.load();
    }

    await corrupt('zły-1');
    await corrupt('zły-1'); // ta sama treść — bez nowej kopii
    expect(prefs.get(InterpassStore.corruptBackupKeys[1]), isNull);
    await corrupt('zły-2');
    await corrupt('zły-3');
    await corrupt('zły-4'); // komplet — zastępuje ostatnią, pierwsza zostaje
    expect([for (final k in InterpassStore.corruptBackupKeys) prefs.get(k)],
        ['zły-1', 'zły-2', 'zły-4']);
    await corrupt('zły-1'); // już zachowana
    expect(prefs.get(InterpassStore.corruptBackupKeys.last), 'zły-4');
  });

  test('update: zmiana zapisanej spoiny bez jej ekranu', () async {
    const store = InterpassStore();
    await store.upsert(_weld('a'));
    expect(
        await store.update('a', (w) => w.copyWith(weldNo: 'S-nowy')), isTrue);
    expect((await store.load()).welds.single.weldNo, 'S-nowy');
    expect(await store.update('brak', (w) => w), isFalse);
  });

  test('zapisy po kolei: równoległe zmiany nie gubią się', () async {
    const store = InterpassStore();
    await Future.wait([
      for (var i = 0; i < 10; i++) store.upsert(_weld('w$i', updatedAt: i)),
    ]);
    final load = await store.load();
    expect(load.welds, hasLength(10));
    // Najnowsze na górze.
    expect(load.welds.first.id, 'w9');
  });

  test('pełny rejestr: nowa spoina odrzucona, istniejąca zapisuje się',
      () async {
    final full = [
      for (var i = 0; i < InterpassStore.maxWelds; i++) _weld('w$i'),
    ];
    SharedPreferences.setMockInitialValues(
        {InterpassStore.key: jsonEncode(interpassLogToJson(full))});
    const store = InterpassStore();
    await expectLater(
        store.upsert(_weld('nowa')), throwsA(isA<InterpassStoreFull>()));
    await store.upsert(_weld('w0').copyWith(weldNo: 'S-zmiana'));
    final load = await store.load();
    expect(load.welds, hasLength(InterpassStore.maxWelds));
    expect(load.welds.firstWhere((w) => w.id == 'w0').weldNo, 'S-zmiana');
    expect(load.welds.any((w) => w.id == 'nowa'), isFalse);
  });

  test('pusta spoina nie trafia do rejestru; usunięcie', () async {
    const store = InterpassStore();
    await store.upsert(InterpassWeld.blank(id: 'x', now: DateTime(2026)));
    expect((await store.load()).welds, isEmpty);
    await store.upsert(_weld('a'));
    await store.delete('a');
    expect((await store.load()).welds, isEmpty);
  });

  test('jednostka osobno od danych; nieznana wartość → °C', () async {
    const store = InterpassStore();
    await store.upsert(_weld('a'));
    final prefs = await SharedPreferences.getInstance();
    final before = prefs.getString(InterpassStore.key);
    expect(await store.loadUnit(), InterpassUnit.c);
    await store.saveUnit(InterpassUnit.f);
    expect(await store.loadUnit(), InterpassUnit.f);
    expect(prefs.getString(InterpassStore.key), before);
    await prefs.setInt(InterpassStore.unitKey, 7);
    expect(await store.loadUnit(), InterpassUnit.c);
  });
}
