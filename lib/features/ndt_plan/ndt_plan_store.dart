/// Reguły planu badań NDT w SharedPreferences (JSON, klucz z wersją), osobno
/// dla każdego projektu dziennika — bez zmian schematu bazy: dziennik spoin
/// zostaje jedynym źródłem tego, co zbadane.
///
/// Uszkodzony zapis (nieczytelny JSON, zła wersja, reguła złego typu albo
/// spoza zakresu) NIE ginie przy następnym zapisie: zanim [NdtPlanStore.save]
/// go nadpisze, surowa wartość trafia pod [NdtPlanStore.corruptKeyFor] —
/// tylko raz, istniejąca kopia nie jest nadpisywana (jak w akordzie).
///
/// Błąd ODCZYTU (wyjątek magazynu) to co innego niż uszkodzony zapis: nie
/// wiadomo, co jest zapisane — load zwraca `readFailed`, a ekran nie
/// zapisuje niczego, dopóki ponowny odczyt się nie uda (inaczej nienaruszone
/// reguły zostałyby nadpisane bez kopii).
library;

import 'dart:convert';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:shared_preferences/shared_preferences.dart';

import '../../domain/ndt/ndt_plan.dart';

/// Dostęp do SharedPreferences — wstrzykiwany w testach (np. błąd odczytu).
typedef NdtPrefsGetter = Future<SharedPreferences> Function();

class NdtPlanStore {
  static const String prefix = 'ndt_plan.rules_v1.';
  static const String corruptPrefix = 'ndt_plan.rules_v1_corrupt.';

  final NdtPrefsGetter prefs;

  const NdtPlanStore({this.prefs = SharedPreferences.getInstance});

  /// Klucz projektu: nazwa bez spacji na brzegach, małymi literami (jak
  /// ustawienia projektu w dzienniku).
  static String projectKey(String project) => project.trim().toLowerCase();

  static String keyFor(String project) => '$prefix${projectKey(project)}';
  static String corruptKeyFor(String project) =>
      '$corruptPrefix${projectKey(project)}';

  /// Nigdy nie rzuca: brak zapisu = brak reguł (`saved == false`);
  /// nieczytelny = `intact == false`; wyjątek odczytu = `readFailed`.
  Future<NdtRuleSetDecode> load(String project) async {
    try {
      final p = await prefs();
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
  Future<void> save(String project, NdtRuleSet set) async {
    final p = await prefs();
    await _backupIfDamaged(p, project);
    final ok = await p.setString(keyFor(project), set.encode());
    if (!ok) throw StateError('SharedPreferences.setString failed');
  }

  /// Kopia surowej wartości, jeśli nie jest nienaruszonym zapisem reguł i
  /// kopii jeszcze nie ma.
  static Future<void> _backupIfDamaged(
      SharedPreferences prefs, String project) async {
    final raw = prefs.get(keyFor(project));
    if (raw == null) return;
    if (raw is String && decodeNdtRuleSet(raw).intact) return;
    final backup = corruptKeyFor(project);
    if (prefs.containsKey(backup)) return;
    await prefs.setString(backup, raw is String ? raw : _describe(raw));
  }

  static String _describe(Object raw) {
    try {
      return jsonEncode(raw);
    } catch (_) {
      return raw.toString();
    }
  }
}
