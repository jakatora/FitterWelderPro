// Historia protokołów „Prace pożarowo niebezpieczne” w SharedPreferences
// (JSON) — bez zmian schematu bazy.
//
// Odporność:
// * nieczytelny zapis ALBO pominięte protokoły / pomiary (także pomiary
//   z przyszłości względem zegara) → kopia surowego tekstu PRZED pierwszym
//   nadpisaniem i flaga dla banera na ekranie (nic nie znika po cichu);
// * operacje szeregowane — odczyt po zapisie zawsze widzi ten zapis;
// * historia ma limit [HotWorkStore.maxEntries] — przy pełnej NOWY protokół
//   jest odrzucany ([HotWorkStoreFull]), stare nigdy nie wypadają po
//   cichu; od [HotWorkStore.warnAt] ekran ostrzega.

import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../domain/hot_work/hot_work_permit.dart';

/// Wynik odczytu historii.
class HotWorkLoad {
  final List<HotWorkPermit> permits;

  /// Zapis był nieczytelny w całości (historia pusta).
  final bool unreadable;

  /// Ile protokołów i pomiarów pominięto jako uszkodzone.
  final int droppedPermits;
  final int droppedMeasurements;

  const HotWorkLoad(
    this.permits, {
    this.unreadable = false,
    this.droppedPermits = 0,
    this.droppedMeasurements = 0,
  });

  /// Coś odrzucono — surowy tekst jest w kopii, ekran pokazuje baner.
  bool get damaged =>
      unreadable || droppedPermits > 0 || droppedMeasurements > 0;
}

/// Historia pełna — nowego protokołu nie zapisano (stare nie wypadają po
/// cichu: to dowody dla nadzoru).
class HotWorkStoreFull implements Exception {
  const HotWorkStoreFull();
  @override
  String toString() => 'HotWorkStoreFull(${HotWorkStore.maxEntries})';
}

class HotWorkStore {
  static const String key = 'hot_work_permits_v1';

  /// Tyle protokołów mieści historia; od [warnAt] (90 %) ekran ostrzega.
  /// Wcześniej było 60 z cichym przycinaniem najstarszych — już nie.
  static const int maxEntries = 200;
  static const int warnAt = 180;

  /// Zegar do odrzucania pomiarów „z przyszłości” przy odczycie; `null` =
  /// zegar systemowy. Ekrany podają swój (wstrzykiwany w testach).
  final DateTime Function()? clock;

  const HotWorkStore({this.clock});

  /// Ten sam magazyn z zegarem [c], jeśli nie ma własnego.
  HotWorkStore withClock(DateTime Function() c) =>
      clock == null ? HotWorkStore(clock: c) : this;

  DateTime _now() => (clock ?? DateTime.now)();

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
  Future<List<HotWorkPermit>> load() async => (await loadReport()).permits;

  /// Protokoły i raport, czy coś pominięto (baner na ekranie).
  Future<HotWorkLoad> loadReport() => _serial(_loadNow);

  /// Kopia PIERWSZEGO nieczytelnego zapisu (nigdy nienadpisywana).
  static const String corruptBackupKey = '${key}_corrupt';

  /// Kopia późniejszego, innego nieczytelnego zapisu (ostatnia).
  static const String corruptLastBackupKey = '${key}_corrupt_last';

  Future<HotWorkLoad> _loadNow() async {
    final prefs = await SharedPreferences.getInstance();
    Object? raw;
    try {
      raw = prefs.get(key);
      if (raw == null || (raw is String && raw.isEmpty)) {
        return const HotWorkLoad([]);
      }
      if (raw is! String) throw const FormatException('not a string');
      final parsed = hotWorkPermitsParse(jsonDecode(raw), now: _now());
      if (parsed.damaged) await _backup(prefs, raw);
      return HotWorkLoad(
        sortHotWorkPermits(parsed.permits),
        droppedPermits: parsed.droppedPermits,
        droppedMeasurements: parsed.droppedMeasurements,
      );
    } catch (_) {
      if (raw != null) await _backup(prefs, raw);
      return const HotWorkLoad([], unreadable: true);
    }
  }

  /// Pierwsza kopia zostaje na zawsze; inny, późniejszy uszkodzony zapis
  /// trafia do [corruptLastBackupKey].
  static Future<void> _backup(SharedPreferences prefs, Object raw) async {
    final text = raw.toString();
    final first = prefs.get(corruptBackupKey);
    if (first == null) {
      await prefs.setString(corruptBackupKey, text);
    } else if (first != text && prefs.get(corruptLastBackupKey) != text) {
      await prefs.setString(corruptLastBackupKey, text);
    }
  }

  /// Zapis całej listy — bez przycinania (limit pilnuje [upsert]).
  Future<void> _write(List<HotWorkPermit> list) async {
    final prefs = await SharedPreferences.getInstance();
    final ok = await prefs.setString(
        key, jsonEncode(hotWorkPermitsToJson(sortHotWorkPermits(list))));
    if (!ok) throw StateError('SharedPreferences.setString($key) failed');
  }

  /// Zapisuje (nowy albo zmieniony) protokół. Pusty protokół (nic nie
  /// wpisano) nie trafia do historii — a jeśli był zapisany, znika. Nowy
  /// protokół przy pełnej historii → [HotWorkStoreFull].
  Future<void> upsert(HotWorkPermit permit) => _serial(() async {
        final list = [...(await _loadNow()).permits];
        final existed = list.any((p) => p.id == permit.id);
        list.removeWhere((p) => p.id == permit.id);
        if (!permit.isBlank) {
          if (!existed && list.length >= maxEntries) {
            throw const HotWorkStoreFull();
          }
          list.add(permit);
        }
        await _write(list);
      });

  Future<void> delete(String id) => _serial(() async {
        final list = [...(await _loadNow()).permits]
          ..removeWhere((p) => p.id == id);
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
