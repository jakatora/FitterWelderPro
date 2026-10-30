/// Reguły planu badań NDT w SharedPreferences (JSON, klucz z wersją), osobno
/// dla każdego projektu dziennika — bez zmian schematu bazy: dziennik spoin
/// zostaje jedynym źródłem tego, co zbadane.
///
/// Uszkodzony zapis (nieczytelny JSON, zła wersja, reguła złego typu albo
/// spoza zakresu) NIE ginie przy następnym zapisie: zanim [NdtPlanStore.save]
/// go nadpisze, surowa wartość trafia do jednej z dwóch nienadpisywanych
/// kopii. Brak wolnej kopii wstrzymuje zapis.
///
/// Błąd ODCZYTU (wyjątek magazynu) to co innego niż uszkodzony zapis: nie
/// wiadomo, co jest zapisane — load zwraca `readFailed`, a ekran nie
/// zapisuje niczego, dopóki ponowny odczyt się nie uda (inaczej nienaruszone
/// reguły zostałyby nadpisane bez kopii).
library;

import 'dart:convert';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:shared_preferences/shared_preferences.dart';
import '../../services/owned_prefs.dart';

import '../../domain/ndt/ndt_plan.dart';

/// Dostęp do SharedPreferences — wstrzykiwany w testach (np. błąd odczytu).
typedef NdtPrefsGetter = Future<SharedPreferences> Function();

class NdtPlanStore {
  static const String prefix = 'ndt_plan.rules_v1.';
  static const String corruptPrefix = 'ndt_plan.rules_v1_corrupt.';
  static const String secondCorruptPrefix = 'ndt_plan.rules_v1_corrupt_2.';

  final NdtPrefsGetter prefs;

  const NdtPlanStore({this.prefs = OwnedPrefs.instance});

  /// Klucz projektu: nazwa bez spacji na brzegach, małymi literami (jak
  /// ustawienia projektu w dzienniku).
  static String projectKey(String project) => project.trim().toLowerCase();

  static String keyFor(String project) => '$prefix${projectKey(project)}';
  static String corruptKeyFor(String project) =>
      '$corruptPrefix${projectKey(project)}';
  static String secondCorruptKeyFor(String project) =>
      '$secondCorruptPrefix${projectKey(project)}';

  static Future<void>? _writeTail;
  static int _writesInFlight = 0;

  /// Nigdy nie rzuca: brak zapisu = brak reguł (`saved == false`);
  /// nieczytelny = `intact == false`; wyjątek odczytu = `readFailed`.
  Future<NdtRuleSetDecode> load(String project) async {
    try {
      final p = await prefs();
      await p.reload();
      final raw = p.get(keyFor(project));
      if (raw == null) return decodeNdtRuleSet(null);
      if (raw is! String) {
        return const NdtRuleSetDecode(NdtRuleSet(), intact: false);
      }
      return decodeNdtRuleSet(raw);
    } catch (e) {
      debugPrint('[ndt_plan] read rules failed: $e');
      return const NdtRuleSetDecode(NdtRuleSet(),
          intact: false, readFailed: true);
    }
  }

  /// Rzuca, gdy zapis się nie uda — ekran pokazuje komunikat.
  Future<void> save(String project, NdtRuleSet set) {
    // OwnedPrefs przechwytuje konto w chwili żądania, przed kolejką zapisów.
    final prefsFuture = prefs();
    final previous = _writesInFlight > 0 ? _writeTail : null;
    _writesInFlight++;
    final Future<void> result;
    if (previous == null) {
      result = _saveCaptured(project, set, prefsFuture);
    } else {
      result = Future.wait<Object?>([previous, prefsFuture]).then(
          (values) => _saveNow(project, set, values[1]! as SharedPreferences));
    }
    _writeTail = result
        .then<void>((_) {}, onError: (Object _) {})
        .whenComplete(() => _writesInFlight--);
    return result;
  }

  Future<void> _saveCaptured(String project, NdtRuleSet set,
      Future<SharedPreferences> prefsFuture) async {
    await _saveNow(project, set, await prefsFuture);
  }

  Future<void> _saveNow(
      String project, NdtRuleSet set, SharedPreferences p) async {
    await p.reload();
    final raw = p.get(keyFor(project));
    if (raw != null && (raw is! String || !decodeNdtRuleSet(raw).intact)) {
      await _backupRaw(p, project, raw);
    }
    final encoded = set.encode();
    if (!await p.setString(keyFor(project), encoded)) {
      throw StateError('Nie udało się zapisać reguł NDT');
    }
    await p.reload();
    if (p.getString(keyFor(project)) != encoded) {
      throw StateError('Nie potwierdzono zapisu reguł NDT');
    }
  }

  /// Kopia surowej wartości przed nadpisaniem; każdą potwierdzamy po odczycie.
  static Future<void> _backupRaw(
      SharedPreferences prefs, String project, Object raw) async {
    final value = raw is String ? raw : _describe(raw);
    for (final backupKey in [
      corruptKeyFor(project),
      secondCorruptKeyFor(project),
    ]) {
      final existing = prefs.get(backupKey);
      if (existing == value) return;
      if (existing != null) continue;
      if (!await prefs.setString(backupKey, value)) {
        throw StateError('Nie udało się zachować kopii reguł NDT');
      }
      await prefs.reload();
      if (prefs.getString(backupKey) != value) {
        throw StateError('Nie potwierdzono kopii reguł NDT');
      }
      return;
    }
    throw StateError('Brak miejsca na kopię uszkodzonych reguł NDT');
  }

  static String _describe(Object raw) {
    try {
      return jsonEncode(raw);
    } catch (_) {
      return raw.toString();
    }
  }
}
