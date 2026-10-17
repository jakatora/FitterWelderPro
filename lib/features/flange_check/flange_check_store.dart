/// Historia protokołów odbioru kołnierzy w SharedPreferences (JSON).
///
/// Celowo bez bazy SQLite: moduł nie zmienia schematu `db.dart`. Klucz ma
/// wersję w nazwie — przy zmianie formatu nowy klucz, stary zostaje do
/// migracji.
library;

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:shared_preferences/shared_preferences.dart';

import '../../domain/flange/flange_check.dart';

class FlangeCheckStore {
  static const String key = 'flange_checks_v1';

  const FlangeCheckStore();

  /// Nigdy nie rzuca: brak, uszkodzony JSON albo błąd odczytu → pusta lista.
  Future<List<FlangeCheck>> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return decodeFlangeChecks(prefs.getString(key));
    } catch (e) {
      debugPrint('[flange_check] read failed: $e');
      return [];
    }
  }

  Future<void> save(List<FlangeCheck> checks) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(key, encodeFlangeChecks(checks));
  }
}
