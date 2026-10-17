// Historia protokołów „Prace pożarowo niebezpieczne” w SharedPreferences
// (JSON) — bez zmian schematu bazy.

import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../domain/hot_work/hot_work_permit.dart';

class HotWorkStore {
  static const String key = 'hot_work_permits_v1';

  /// Tyle ostatnich protokołów trzymamy w historii (najstarsze wypadają).
  static const int maxEntries = 60;

  const HotWorkStore();

  /// Kolejka operacji: odczyt po zapisie zawsze widzi ten zapis (formularz
  /// zapisuje się sam przy każdej zmianie, lista czyta po powrocie).
  /// Gdy nic nie czeka, nowa operacja startuje od razu — bez trzymania
  /// starej przyszłości (z innej strefy, np. poprzedniego testu).
  static Future<void>? _tail;
  static int _inFlight = 0;

  static Future<T> _serial<T>(Future<T> Function() op) {
    final prev = _inFlight > 0 ? _tail : null;
    _inFlight++;
    final result = prev == null ? op() : prev.then((_) => op());
    _tail = result
        .then<void>((_) {}, onError: (Object _) {})
        .whenComplete(() => _inFlight--);
    return result;
  }

  /// Protokoły od najnowszego (data, potem czas zapisu).
  Future<List<HotWorkPermit>> load() => _serial(_loadNow);

  Future<List<HotWorkPermit>> _loadNow() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(key);
    if (raw == null || raw.isEmpty) return const [];
    try {
      return sortHotWorkPermits(hotWorkPermitsFromJson(jsonDecode(raw)));
    } on FormatException {
      return const [];
    }
  }

  Future<void> _write(List<HotWorkPermit> list) async {
    final prefs = await SharedPreferences.getInstance();
    final sorted = sortHotWorkPermits(list);
    final kept =
        sorted.length > maxEntries ? sorted.sublist(0, maxEntries) : sorted;
    await prefs.setString(key, jsonEncode(hotWorkPermitsToJson(kept)));
  }

  /// Zapisuje (nowy albo zmieniony) protokół. Pusty protokół (nic nie
  /// wpisano) nie trafia do historii — a jeśli był zapisany, znika.
  Future<void> upsert(HotWorkPermit permit) => _serial(() async {
        final list = [...await _loadNow()]
          ..removeWhere((p) => p.id == permit.id);
        if (!permit.isBlank) list.add(permit);
        await _write(list);
      });

  Future<void> delete(String id) => _serial(() async {
        final list = [...await _loadNow()]..removeWhere((p) => p.id == id);
        await _write(list);
      });
}

/// Najnowsze na górze: data pracy malejąco, potem ostatnia zmiana.
List<HotWorkPermit> sortHotWorkPermits(List<HotWorkPermit> list) =>
    [...list]..sort((a, b) {
        final byDate = b.date.compareTo(a.date);
        if (byDate != 0) return byDate;
        return b.updatedAt.compareTo(a.updatedAt);
      });
