// Magazyn „Moje szlifierki”: uszkodzony zapis nie znika po cichu — surowa
// wartość trafia RAZ pod klucz kopii (przy odczycie i przed zapisem);
// inny typ wartości w SharedPreferences nie wywala odczytu; pamięć
// niedostępna to osobny stan; zapisy szeregowane i liczone od listy
// zapisanej w chwili zapisu (szybkie usunięcia, „Cofnij” na dawne miejsce,
// zmiana po id bez duplikatu).

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

import 'package:cut_list_app/domain/grinding/grinder_profile.dart';
import 'package:cut_list_app/features/grinding/grinding_store.dart';

class _Disk extends InMemorySharedPreferencesStore {
  _Disk() : super.empty();
  String? pretendKey;
  @override
  Future<bool> setValue(String type, String key, Object value) async {
    if (pretendKey == null || pretendKey == key) return true;
    return super.setValue(type, key, value);
  }
}

const _a = GrinderProfile(id: 'a', name: 'A', maxRpm: 11000, diameterMm: 125);
const _b = GrinderProfile(id: 'b', name: 'B', maxRpm: 8500, diameterMm: 180);
const _c = GrinderProfile(id: 'c', name: 'C', maxRpm: 6600, diameterMm: 230);
const _d = GrinderProfile(id: 'd', name: 'D', maxRpm: 13000, diameterMm: 115);

Future<List<String>> _ids() async {
  final prefs = await SharedPreferences.getInstance();
  return decodeGrinders(prefs.getString(kGrindersPrefsKey)!)
      .grinders
      .map((g) => g.id)
      .toList();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const store = GrinderStore();

  test('pozorny sukces zapisu szlifierki jest wykrywany', () async {
    SharedPreferences.setMockInitialValues({});
    SharedPreferencesStorePlatform.instance = _Disk();
    await expectLater(store.save([_a]), throwsStateError);
  });

  test('pozorna kopia nie pozwala nadpisać uszkodzonych profili', () async {
    SharedPreferences.setMockInitialValues({});
    final disk = _Disk()..pretendKey = 'flutter.${store.corruptKey}';
    SharedPreferencesStorePlatform.instance = disk;
    const damaged = '{broken grinders';
    await disk.setValue('String', 'flutter.${store.key}', damaged);
    await expectLater(store.save([_a]), throwsStateError);
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    expect(prefs.get(store.key), damaged);
  });

  group('kolejka i zmiany po id', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    test('dwa szybkie usunięcia (bez czekania) nie wskrzeszają pierwszego',
        () async {
      await store.save([_a, _b, _c]);
      final first = store.delete('a');
      final second = store.delete('b');
      final r = await Future.wait([first, second]);
      expect(r[0]!.profile, _a);
      expect(r[1]!.profile, _b);
      expect(r[1]!.remaining, [_c]);
      expect(await _ids(), ['c']);
    });

    test(
        '„Cofnij” przywraca tylko usunięty element na dawne miejsce i nie '
        'gubi zmian z międzyczasu', () async {
      await store.save([_a, _b, _c]);
      final removed = (await store.delete('b'))!;
      expect(removed.index, 1);
      // W międzyczasie: nowa szlifierka i usunięcie innej.
      await store.upsert(_d);
      await store.delete('a');
      expect(await _ids(), ['c', 'd']);
      final list = await store.restore(removed.profile, removed.index);
      expect(list.map((g) => g.id), ['c', 'b', 'd']);
      expect(await _ids(), ['c', 'b', 'd']);
      // Ponowne „Cofnij” niczego nie dubluje.
      await store.restore(removed.profile, removed.index);
      expect(await _ids(), ['c', 'b', 'd']);
    });

    test('„Cofnij” na krótszej liście trafia na koniec', () async {
      await store.save([_a, _b, _c]);
      final removed = (await store.delete('c'))!;
      await store.delete('a');
      await store.restore(removed.profile, removed.index);
      expect(await _ids(), ['b', 'c']);
    });

    test('zmiana po id — w miejscu, bez duplikatu; nowe id — na koniec',
        () async {
      await store.save([_a, _b]);
      const edited =
          GrinderProfile(id: 'a', name: 'A2', maxRpm: 10000, diameterMm: 125);
      final list = await store.upsert(edited);
      expect(list, [edited, _b]);
      await store.upsert(_c);
      expect(await _ids(), ['a', 'b', 'c']);
    });

    test('usunięcie nieistniejącego id → null, lista bez zmian', () async {
      await store.save([_a]);
      expect(await store.delete('x'), isNull);
      expect(await _ids(), ['a']);
    });

    test('lista pełna → GrinderStoreFull, zmiana istniejącego nadal działa',
        () async {
      await store.save([
        for (var i = 0; i < kMaxGrinders; i++)
          GrinderProfile(
              id: 'g$i', name: 'G$i', maxRpm: 11000, diameterMm: 125),
      ]);
      await expectLater(store.upsert(_a), throwsA(isA<GrinderStoreFull>()));
      await store.upsert(const GrinderProfile(
          id: 'g0', name: 'G0b', maxRpm: 9000, diameterMm: 125));
      expect((await _ids()).length, kMaxGrinders);
    });
  });

  test('pamięć niedostępna → osobny stan (nie „uszkodzony”), zapis rzuca',
      () async {
    SharedPreferences.setMockInitialValues({});
    final broken = GrinderStore(
        openPrefs: () => Future<SharedPreferences>.error(
            StateError('platform channel down')));
    final r = await broken.load();
    expect(r.unavailable, isTrue);
    expect(r.damaged, isFalse);
    expect(r.grinders, isEmpty);
    await expectLater(broken.upsert(_a), throwsA(isA<StateError>()));
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getKeys(), isEmpty);
  });

  test('brak zapisu → pusta lista, nieuszkodzony', () async {
    SharedPreferences.setMockInitialValues({});
    final r = await store.load();
    expect(r.grinders, isEmpty);
    expect(r.damaged, isFalse);
  });

  test('zapis i odczyt', () async {
    SharedPreferences.setMockInitialValues({});
    await store.save([_a]);
    final r = await store.load();
    expect(r.grinders, [_a]);
    expect(r.damaged, isFalse);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.containsKey(kGrindersCorruptPrefsKey), isFalse);
  });

  test('uszkodzony JSON: pusta lista, damaged i kopia surowego zapisu',
      () async {
    SharedPreferences.setMockInitialValues({kGrindersPrefsKey: '[{"id":'});
    final r = await store.load();
    expect(r.grinders, isEmpty);
    expect(r.damaged, isTrue);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(kGrindersCorruptPrefsKey), '[{"id":');
  });

  test('kopia tylko raz — kolejne uszkodzenie jej nie nadpisuje', () async {
    SharedPreferences.setMockInitialValues({
      kGrindersPrefsKey: 'drugie uszkodzenie',
      kGrindersCorruptPrefsKey: 'pierwsze uszkodzenie',
    });
    expect((await store.load()).damaged, isTrue);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(kGrindersCorruptPrefsKey), 'pierwsze uszkodzenie');
  });

  test('wartość innego typu → damaged i kopia, bez wyjątku', () async {
    SharedPreferences.setMockInitialValues({kGrindersPrefsKey: 42});
    final r = await store.load();
    expect(r.grinders, isEmpty);
    expect(r.damaged, isTrue);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(kGrindersCorruptPrefsKey), '42');
  });

  test('zapis po uszkodzeniu nie gubi oryginału (kopia przed nadpisaniem)',
      () async {
    const broken = '[{"id":"a","name":"A","rpm":11000,"d":125},{"id":';
    SharedPreferences.setMockInitialValues({kGrindersPrefsKey: broken});
    // Zapis bez wcześniejszego odczytu — kopia i tak powstaje.
    await store.save([_a]);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(kGrindersCorruptPrefsKey), broken);
    expect((await store.load()).grinders, [_a]);
  });

  test('zajęta kopia blokuje nadpisanie innego uszkodzonego zapisu', () async {
    const broken = 'drugie uszkodzenie';
    const earlier = 'pierwsze uszkodzenie';
    SharedPreferences.setMockInitialValues({
      kGrindersPrefsKey: broken,
      kGrindersCorruptPrefsKey: earlier,
    });

    await expectLater(store.save([_a]), throwsA(isA<StateError>()));
    await expectLater(store.upsert(_b), throwsA(isA<StateError>()));
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(kGrindersPrefsKey), broken);
    expect(prefs.getString(kGrindersCorruptPrefsKey), earlier);
  });
}
