/// Lista połączeń do kompletu śrub w SharedPreferences (JSON).
///
/// Celowo bez bazy SQLite: moduł nie zmienia schematu `db.dart`. Klucz ma
/// wersję w nazwie — przy zmianie formatu nowy klucz, stary zostaje do
/// migracji.
///
/// Uszkodzony zapis (nieczytelny JSON, wartość innego typu, wpis pominięty
/// przy odczycie) NIE ginie przy następnym zapisie: zanim [save] go
/// nadpisze, surowa wartość trafia pod jeden z dwóch kluczy kopii. Istniejące
/// kopie nie są nadpisywane.
///
/// Nieudany ODCZYT (wyjątek platformy) to co innego niż uszkodzony zapis:
/// wartość w pamięci może być zupełnie dobra, tylko ekran jej nie zna. Wtedy
/// [BoltKitLoad.readFailed] i pierwszy [save] z `afterFailedRead: true`
/// najpierw kopiuje surową wartość pod [corruptKey] (nawet nienaruszoną),
/// a gdy obie kopie są zajęte — odmawia zapisu ([BoltKitSaveBlocked]), zamiast
/// nadpisać listę po cichu.
library;

import 'dart:convert';
import 'dart:async';

import 'package:flutter/foundation.dart' show debugPrint, protected;
import 'package:shared_preferences/shared_preferences.dart';
import '../../database/local_record_owner.dart';
import '../../services/owned_prefs.dart';

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

/// Zapis wstrzymany: nie można potwierdzić kopii wcześniejszej listy.
class BoltKitSaveBlocked implements Exception {
  const BoltKitSaveBlocked();

  @override
  String toString() => 'BoltKitSaveBlocked';
}

class BoltKitStore {
  static Future<void>? _writes;
  static const String key = 'bolt_kit_v1';
  static const String corruptKey = 'bolt_kit_v1_corrupt';
  static const String secondCorruptKey = '${corruptKey}_2';

  const BoltKitStore({this.captureOwner});

  final Future<LocalRecordOwner> Function()? captureOwner;

  /// Surowa wartość spod [key] (punkt podmiany w teście: odczyt, który
  /// rzuca).
  @protected
  Future<Object?> readRaw() async {
    final prefs = await OwnedPrefs.instance(captureOwner);
    await prefs.reload();
    return prefs.get(key);
  }

  /// Nigdy nie rzuca: brak, uszkodzony JSON albo błąd odczytu → pusty stan
  /// (z flagą `damaged`, gdy coś było, a nie dało się odczytać; przy
  /// wyjątku także `readFailed`).
  Future<BoltKitLoad> load() async {
    try {
      final pending = _writes;
      if (pending != null) await pending;
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
  Future<void> save(BoltKitState state, {bool afterFailedRead = false}) {
    Object? captureError;
    StackTrace? captureStack;
    final prefsReady =
        OwnedPrefs.instance(captureOwner).then<SharedPreferences?>(
      (prefs) => prefs,
      onError: (Object error, StackTrace stack) {
        captureError = error;
        captureStack = stack;
        return null;
      },
    );
    final encoded = encodeBoltKit(state);
    final previous = _writes;
    final write = () async {
      if (previous != null) await previous;
      final prefs = await prefsReady;
      if (prefs == null) {
        Error.throwWithStackTrace(captureError!, captureStack!);
      }
      await _saveNow(prefs, encoded, afterFailedRead: afterFailedRead);
    }();
    final settled =
        write.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    _writes = settled;
    unawaited(settled.then((_) {
      if (identical(_writes, settled)) _writes = null;
    }));
    return write;
  }

  Future<void> _saveNow(SharedPreferences prefs, String encoded,
      {required bool afterFailedRead}) async {
    await prefs.reload();
    if (afterFailedRead) {
      await _backupUnread(prefs);
    } else {
      await _backupIfDamaged(prefs);
    }
    if (!await prefs.setString(key, encoded)) {
      throw StateError('Could not save bolt kit');
    }
    await prefs.reload();
    if (prefs.get(key) != encoded) {
      throw StateError('Could not verify bolt kit write');
    }
  }

  /// Kopia wartości, której ekran nie odczytał. Pusta lista albo brak
  /// zapisu — nie ma czego chronić. Kopia tej samej wartości — OK;
  /// obie kopie zajęte innymi wartościami — [BoltKitSaveBlocked].
  static Future<void> _backupUnread(SharedPreferences prefs) async {
    final raw = prefs.get(key);
    if (raw == null) return;
    if (raw is String) {
      final d = decodeBoltKitReport(raw);
      if (d.intact && d.state.joints.isEmpty) return;
    }
    await _backupRaw(prefs, raw is String ? raw : _describe(raw));
  }

  /// Kopia surowej wartości spod [key], jeśli nie jest nienaruszonym
  /// zapisem tego modułu.
  static Future<void> _backupIfDamaged(SharedPreferences prefs) async {
    final raw = prefs.get(key);
    if (raw == null) return;
    if (raw is String && decodeBoltKitReport(raw).intact) return;
    await _backupRaw(prefs, raw is String ? raw : _describe(raw));
  }

  /// Nie nadpisuj wcześniejszych kopii. Wynik `setString` i cache nie
  /// wystarczają: sprawdź kopię po ponownym odczycie z platformy.
  static Future<void> _backupRaw(SharedPreferences prefs, String copy) async {
    String? free;
    for (final backupKey in [corruptKey, secondCorruptKey]) {
      final existing = prefs.get(backupKey);
      if (existing == copy) return;
      if (existing == null && free == null) free = backupKey;
    }
    if (free == null) throw const BoltKitSaveBlocked();
    try {
      if (!await prefs.setString(free, copy)) {
        throw const BoltKitSaveBlocked();
      }
      await prefs.reload();
      if (prefs.get(free) != copy) throw const BoltKitSaveBlocked();
    } on BoltKitSaveBlocked {
      rethrow;
    } catch (_) {
      throw const BoltKitSaveBlocked();
    }
  }

  static String _describe(Object raw) {
    try {
      return jsonEncode(raw);
    } catch (_) {
      return raw.toString();
    }
  }
}
