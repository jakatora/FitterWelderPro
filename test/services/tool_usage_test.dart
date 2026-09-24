// Ostatnio używane i przypięte narzędzia — lokalnie, trwale, bez duplikatów.

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:cut_list_app/services/tool_usage.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final store = ToolUsageStore.instance;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    store.resetForTest();
  });

  test('ostatnio otwarte idzie na początek, bez powtórzeń', () async {
    await store.recordOpen('a');
    await store.recordOpen('b');
    await store.recordOpen('a');
    expect(store.recent, ['a', 'b']);
  });

  test('pamięta najwyżej maxRecent pozycji, najnowsze pierwsze', () async {
    for (var i = 0; i < ToolUsageStore.maxRecent + 5; i++) {
      await store.recordOpen('t$i');
    }
    expect(store.recent.length, ToolUsageStore.maxRecent);
    expect(store.recent.first, 't${ToolUsageStore.maxRecent + 4}');
  });

  test('ostatnio używane przeżywają restart', () async {
    await store.recordOpen('dn_mm');
    await store.recordOpen('pipe_slope');
    store.resetForTest();
    await store.load();
    expect(store.recent, ['pipe_slope', 'dn_mm']);
  });

  test('przypinanie i odpinanie jest trwałe', () async {
    expect(await store.toggleFavorite('elbow_takeouts'), isTrue);
    expect(store.isFavorite('elbow_takeouts'), isTrue);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getStringList(ToolUsageStore.favoritesKey), ['elbow_takeouts']);

    store.resetForTest();
    await store.load();
    expect(store.isFavorite('elbow_takeouts'), isTrue);

    expect(await store.toggleFavorite('elbow_takeouts'), isFalse);
    expect(store.favorites, isEmpty);
    expect(prefs.getStringList(ToolUsageStore.favoritesKey), isEmpty);
  });

  test('przypięte w kolejności przypinania; pełna lista wypycha najstarsze',
      () async {
    for (var i = 0; i < ToolUsageStore.maxFavorites + 1; i++) {
      await store.toggleFavorite('f$i');
    }
    expect(store.favorites.length, ToolUsageStore.maxFavorites);
    expect(store.favorites.first, 'f1');
    expect(store.favorites.last, 'f${ToolUsageStore.maxFavorites}');
  });

  test('uszkodzony zapis (puste, powtórki) jest czyszczony przy odczycie',
      () async {
    SharedPreferences.setMockInitialValues({
      ToolUsageStore.recentKey: ['a', '', 'a', ' b '],
      ToolUsageStore.favoritesKey: ['x', 'x'],
    });
    store.resetForTest();
    await store.load();
    expect(store.recent, ['a', 'b']);
    expect(store.favorites, ['x']);
  });

  test('powiadamia UI o zmianie', () async {
    await store.load();
    var calls = 0;
    void listener() => calls++;
    store.addListener(listener);
    addTearDown(() => store.removeListener(listener));
    await store.recordOpen('a');
    await store.toggleFavorite('a');
    expect(calls, 2);
  });
}
