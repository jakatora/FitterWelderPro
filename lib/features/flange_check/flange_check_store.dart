/// Historia protokołów odbioru kołnierzy w SharedPreferences (JSON).
///
/// Celowo bez bazy SQLite: moduł nie zmienia schematu `db.dart`. Klucz ma
/// wersję w nazwie — przy zmianie formatu nowy klucz, stary zostaje do
/// migracji.
///
/// Uszkodzony zapis (nieczytelny JSON, wartość innego typu, wpis pominięty
/// albo poprawiony przy odczycie) NIE ginie przy następnym zapisie: zanim
/// [save] go nadpisze, surowa wartość trafia pod [corruptKey] — tylko raz,
/// istniejąca kopia nie jest nadpisywana.
library;

import 'dart:convert';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:shared_preferences/shared_preferences.dart';
import '../../database/local_record_owner.dart';
import '../../services/owned_prefs.dart';

import '../../domain/flange/flange_check.dart';

/// Wynik odczytu historii: protokoły i to, czy zapis był uszkodzony.
class FlangeHistoryLoad {
  final List<FlangeCheck> checks;
  final bool damaged;
  const FlangeHistoryLoad(this.checks, {this.damaged = false});
}

class FlangeCheckStore {
  static const String key = 'flange_checks_v1';
  static const String corruptKey = 'flange_checks_v1_corrupt';

  final Future<LocalRecordOwner> Function()? captureOwner;

  const FlangeCheckStore({this.captureOwner});

  /// Nigdy nie rzuca: brak, uszkodzony JSON albo błąd odczytu → pusta lista.
  Future<List<FlangeCheck>> load() async => (await loadWithStatus()).checks;

  /// Jak [load], ale mówi też, czy zapis był uszkodzony (ekran pokazuje
  /// wtedy komunikat). Nigdy nie rzuca.
  Future<FlangeHistoryLoad> loadWithStatus() async {
    try {
      final prefs = await OwnedPrefs.instance(captureOwner);
      final raw = prefs.get(key);
      if (raw == null) return const FlangeHistoryLoad([]);
      if (raw is! String) return const FlangeHistoryLoad([], damaged: true);
      final decoded = decodeFlangeChecksReport(raw);
      return FlangeHistoryLoad(decoded.checks, damaged: !decoded.intact);
    } catch (e) {
      debugPrint('[flange_check] read failed: $e');
      return const FlangeHistoryLoad([], damaged: true);
    }
  }

  Future<void> save(List<FlangeCheck> checks) async {
    final prefs = await OwnedPrefs.instance(captureOwner);
    await _backupIfDamaged(prefs);
    await prefs.setString(key, encodeFlangeChecks(checks));
  }

  /// Kopia surowej wartości spod [key], jeśli nie jest nienaruszonym
  /// zapisem tego modułu i kopii jeszcze nie ma.
  static Future<void> _backupIfDamaged(SharedPreferences prefs) async {
    final raw = prefs.get(key);
    if (raw == null) return;
    if (raw is String && decodeFlangeChecksReport(raw).intact) return;
    if (prefs.containsKey(corruptKey)) return;
    await prefs.setString(corruptKey, raw is String ? raw : _describe(raw));
  }

  static String _describe(Object raw) {
    try {
      return jsonEncode(raw);
    } catch (_) {
      return raw.toString();
    }
  }
}
