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
///
/// Nieudany ODCZYT (wyjątek platformy) to co innego niż uszkodzony zapis:
/// wartość w pamięci może być zupełnie dobra, tylko ekran jej nie zna. Wtedy
/// [BoltKitLoad.readFailed] i pierwszy [save] z `afterFailedRead: true`
/// najpierw kopiuje surową wartość pod [corruptKey] (nawet nienaruszoną),
/// a gdy kopia już jest i jest inna — odmawia zapisu ([BoltKitSaveBlocked]),
/// zamiast nadpisać listę po cichu.
library;

import 'dart:convert';

import 'package:flutter/foundation.dart' show debugPrint, protected;
import 'package:shared_preferences/shared_preferences.dart';

import '../../domain/bolting/bolt_kit.dart';

/// Wynik odczytu: stan i to, czy zapis był uszkodzony.
class BoltKitLoad {
  final BoltKitState state;
  final bool damaged;

  /// Odczyt rzucił wyjątek — [state] jest pusty, ale w pamięci telefonu
  /// może leżeć dobra lista. Pierwszy zapis musi ją zachować.
  final bool readFailed;

  const BoltKitLoad(this.state,
      {this.damaged = false, this.readFailed = false});
}

/// Zapis wstrzymany: odczyt się nie udał, a miejsce na kopię jest zajęte
/// inną wartością — nadpisanie skasowałoby listę bez kopii.
class BoltKitSaveBlocked implements Exception {
  const BoltKitSaveBlocked();

  @override
  String toString() => 'BoltKitSaveBlocked';
}

class BoltKitStore {
  static const String key = 'bolt_kit_v1';
  static const String corruptKey = 'bolt_kit_v1_corrupt';

  const BoltKitStore();

  /// Surowa wartość spod [key] (punkt podmiany w teście: odczyt, który
  /// rzuca).
  @protected
  Future<Object?> readRaw() async =>
      (await SharedPreferences.getInstance()).get(key);

  /// Nigdy nie rzuca: brak, uszkodzony JSON albo błąd odczytu → pusty stan
  /// (z flagą `damaged`, gdy coś było, a nie dało się odczytać; przy
  /// wyjątku także `readFailed`).
  Future<BoltKitLoad> load() async {
    try {
      final raw = await readRaw();
      if (raw == null) return const BoltKitLoad(BoltKitState());
      if (raw is! String) {
        return const BoltKitLoad(BoltKitState(), damaged: true);
      }
      final decoded = decodeBoltKitReport(raw);
      return BoltKitLoad(decoded.state, damaged: !decoded.intact);
    } catch (e) {
      debugPrint('[bolt_kit] read failed: $e');
      return const BoltKitLoad(BoltKitState(), damaged: true, readFailed: true);
    }
  }

  /// [afterFailedRead] — pierwszy zapis po nieudanym odczycie: zachowaj
  /// surową wartość niezależnie od tego, czy jest nienaruszona (patrz opis
  /// biblioteki). Może rzucić [BoltKitSaveBlocked].
  Future<void> save(BoltKitState state, {bool afterFailedRead = false}) async {
    final prefs = await SharedPreferences.getInstance();
    if (afterFailedRead) {
      await _backupUnread(prefs);
    } else {
      await _backupIfDamaged(prefs);
    }
    await prefs.setString(key, encodeBoltKit(state));
  }

  /// Kopia wartości, której ekran nie odczytał. Pusta lista albo brak
  /// zapisu — nie ma czego chronić. Kopia już jest: ta sama wartość — OK,
  /// inna — [BoltKitSaveBlocked].
  static Future<void> _backupUnread(SharedPreferences prefs) async {
    final raw = prefs.get(key);
    if (raw == null) return;
    if (raw is String) {
      final d = decodeBoltKitReport(raw);
      if (d.intact && d.state.joints.isEmpty) return;
    }
    final copy = raw is String ? raw : _describe(raw);
    final existing = prefs.get(corruptKey);
    if (existing == null) {
      await prefs.setString(corruptKey, copy);
      return;
    }
    if (existing != copy) throw const BoltKitSaveBlocked();
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
