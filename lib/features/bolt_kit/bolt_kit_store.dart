/// Lista połączeń do kompletu śrub w SharedPreferences (JSON).
///
/// Celowo bez bazy SQLite: moduł nie zmienia schematu `db.dart`. Klucz ma
/// wersję w nazwie — przy zmianie formatu nowy klucz, stary zostaje do
/// migracji.
///
/// Uszkodzony zapis (nieczytelny JSON, wartość innego typu, wpis pominięty
/// przy odczycie) NIE ginie przy następnym zapisie: zanim [save] go
/// nadpisze, surowa wartość trafia pod [corruptKey] — tylko raz, istniejąca
/// kopia nie jest nadpisywana. Ta sama mechanika co `flange_check_store.dart`.
library;

import 'dart:convert';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:shared_preferences/shared_preferences.dart';

import '../../domain/bolting/bolt_kit.dart';

/// Wynik odczytu: stan i to, czy zapis był uszkodzony.
class BoltKitLoad {
  final BoltKitState state;
  final bool damaged;
  const BoltKitLoad(this.state, {this.damaged = false});
}

class BoltKitStore {
  static const String key = 'bolt_kit_v1';
  static const String corruptKey = 'bolt_kit_v1_corrupt';

  const BoltKitStore();

  /// Nigdy nie rzuca: brak, uszkodzony JSON albo błąd odczytu → pusty stan
  /// (z flagą `damaged`, gdy coś było, a nie dało się odczytać).
  Future<BoltKitLoad> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.get(key);
      if (raw == null) return const BoltKitLoad(BoltKitState());
      if (raw is! String) {
        return const BoltKitLoad(BoltKitState(), damaged: true);
      }
      final decoded = decodeBoltKitReport(raw);
      return BoltKitLoad(decoded.state, damaged: !decoded.intact);
    } catch (e) {
      debugPrint('[bolt_kit] read failed: $e');
      return const BoltKitLoad(BoltKitState(), damaged: true);
    }
  }

  Future<void> save(BoltKitState state) async {
    final prefs = await SharedPreferences.getInstance();
    await _backupIfDamaged(prefs);
    await prefs.setString(key, encodeBoltKit(state));
  }

  /// Kopia surowej wartości spod [key], jeśli nie jest nienaruszonym
  /// zapisem tego modułu i kopii jeszcze nie ma.
  static Future<void> _backupIfDamaged(SharedPreferences prefs) async {
    final raw = prefs.get(key);
    if (raw == null) return;
    if (raw is String && decodeBoltKitReport(raw).intact) return;
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
