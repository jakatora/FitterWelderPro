import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Ostatnio używane i przypięte narzędzia — tylko na tym telefonie.
//
// Trzymamy wyłącznie identyfikatory z rejestru narzędzi
// (lib/widgets/tool_registry.dart), nigdy tytuły: po zmianie nazwy albo
// usunięciu narzędzia stary identyfikator po prostu przestaje się wyświetlać,
// zamiast pokazać martwy kafel.
//
// Nic z tego nie wychodzi z telefonu i nie jest danymi osobowymi: to lista
// w rodzaju „kolana, spadek, konwerter".

class ToolUsageStore extends ChangeNotifier {
  ToolUsageStore._();
  static final ToolUsageStore instance = ToolUsageStore._();

  static const String recentKey = 'tools_recent_v1';
  static const String favoritesKey = 'tools_favorites_v1';

  /// Ile ostatnio otwartych pamiętamy. Ekran główny pokazuje mniej
  /// ([kRecentShown]), ale zapas pozwala pominąć narzędzia chwilowo ukryte.
  static const int maxRecent = 12;

  /// Ile przypiętych mieści się bez zamieniania ekranu głównego w drugie menu.
  static const int maxFavorites = 12;

  List<String> _recent = const [];
  List<String> _favorites = const [];
  bool _loaded = false;
  Future<void>? _loading;

  bool get isLoaded => _loaded;

  /// Najnowsze pierwsze.
  List<String> get recent => List.unmodifiable(_recent);

  /// W kolejności przypinania.
  List<String> get favorites => List.unmodifiable(_favorites);

  bool isFavorite(String id) => _favorites.contains(id);

  Future<void> load() {
    if (_loaded) return Future.value();
    return _loading ??= _hydrate();
  }

  Future<void> _hydrate() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _recent = _clean(prefs.getStringList(recentKey), maxRecent);
      _favorites = _clean(prefs.getStringList(favoritesKey), maxFavorites);
    } catch (_) {
      _recent = const [];
      _favorites = const [];
    } finally {
      _loaded = true;
      _loading = null;
      notifyListeners();
    }
  }

  static List<String> _clean(List<String>? raw, int cap) {
    if (raw == null) return const [];
    final seen = <String>{};
    final out = <String>[];
    for (final id in raw) {
      final t = id.trim();
      if (t.isEmpty || !seen.add(t)) continue;
      out.add(t);
      if (out.length >= cap) break;
    }
    return out;
  }

  /// Zapamiętuje otwarcie narzędzia: przesuwa je na początek listy.
  Future<void> recordOpen(String id) async {
    await load();
    final next = [id, ..._recent.where((e) => e != id)];
    _recent = next.length > maxRecent ? next.sublist(0, maxRecent) : next;
    notifyListeners();
    await _write(recentKey, _recent);
  }

  /// Przypina albo odpina. Zwraca nowy stan: true = przypięte.
  Future<bool> toggleFavorite(String id) async {
    await load();
    final pinned = !_favorites.contains(id);
    if (pinned) {
      final next = [..._favorites, id];
      // Najstarsze przypięcie wypada, gdy lista jest pełna — lepsze niż
      // odmowa, której monter w rękawicy nawet nie zauważy.
      _favorites = next.length > maxFavorites
          ? next.sublist(next.length - maxFavorites)
          : next;
    } else {
      _favorites = _favorites.where((e) => e != id).toList();
    }
    notifyListeners();
    await _write(favoritesKey, _favorites);
    return pinned;
  }

  Future<void> _write(String key, List<String> value) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(key, value);
    } catch (_) {
      // Lista działa w tej sesji; po restarcie wróci ostatni udany zapis.
    }
  }

  /// Tylko do testów: zapomina stan, żeby następny [load] czytał od nowa.
  @visibleForTesting
  void resetForTest() {
    _recent = const [];
    _favorites = const [];
    _loaded = false;
    _loading = null;
  }
}
