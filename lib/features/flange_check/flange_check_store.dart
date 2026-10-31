/// Historia protokołów odbioru kołnierzy w SharedPreferences (JSON).
///
/// Celowo bez bazy SQLite: moduł nie zmienia schematu `db.dart`. Klucz ma
/// wersję w nazwie — przy zmianie formatu nowy klucz, stary zostaje do
/// migracji.
///
/// Uszkodzony zapis (nieczytelny JSON, wartość innego typu, wpis pominięty
/// albo poprawiony przy odczycie) NIE ginie przy następnym zapisie: zanim
/// [save] go nadpisze, surowa wartość trafia pod jeden z dwóch kluczy kopii.
/// Istniejące kopie nie są nadpisywane.
library;

import 'dart:convert';
import 'dart:async';

import 'package:flutter/foundation.dart' show debugPrint, protected;
import 'package:shared_preferences/shared_preferences.dart';
import '../../database/local_record_owner.dart';
import '../../services/owned_prefs.dart';

import '../../domain/flange/flange_check.dart';

/// Wynik odczytu historii: protokoły i to, czy zapis był uszkodzony.
class FlangeHistoryLoad {
  final List<FlangeCheck> checks;
  final bool damaged;
  final bool readFailed;
  const FlangeHistoryLoad(this.checks,
      {this.damaged = false, this.readFailed = false});
}

class FlangeCheckStore {
  static Future<void>? _writes;
  static const String key = 'flange_checks_v1';
  static const String corruptKey = 'flange_checks_v1_corrupt';
  static const String secondCorruptKey = '${corruptKey}_2';

  final Future<LocalRecordOwner> Function()? captureOwner;

  const FlangeCheckStore({this.captureOwner});

  @protected
  Future<Object?> readRaw() async {
    final prefs = await OwnedPrefs.instance(captureOwner);
    await prefs.reload();
    return prefs.get(key);
  }

  /// Nigdy nie rzuca: brak, uszkodzony JSON albo błąd odczytu → pusta lista.
  Future<List<FlangeCheck>> load() async => (await loadWithStatus()).checks;

  /// Jak [load], ale mówi też, czy zapis był uszkodzony (ekran pokazuje
  /// wtedy komunikat). Nigdy nie rzuca.
  Future<FlangeHistoryLoad> loadWithStatus() async {
    try {
      final pending = _writes;
      if (pending != null) await pending;
      final raw = await readRaw();
      if (raw == null) return const FlangeHistoryLoad([]);
      if (raw is! String) return const FlangeHistoryLoad([], damaged: true);
      final decoded = decodeFlangeChecksReport(raw);
      return FlangeHistoryLoad(decoded.checks, damaged: !decoded.intact);
    } catch (e) {
      debugPrint('[flange_check] read failed: $e');
      return const FlangeHistoryLoad([], damaged: true, readFailed: true);
    }
  }

  Future<void> save(List<FlangeCheck> checks, {bool afterFailedRead = false}) {
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
    final snapshot = List<FlangeCheck>.of(checks);
    final previous = _writes;
    final write = () async {
      if (previous != null) await previous;
      final prefs = await prefsReady;
      if (prefs == null) {
        Error.throwWithStackTrace(captureError!, captureStack!);
      }
      await _saveNow(prefs, snapshot, afterFailedRead: afterFailedRead);
    }();
    final settled =
        write.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    _writes = settled;
    unawaited(settled.then((_) {
      if (identical(_writes, settled)) _writes = null;
    }));
    return write;
  }

  Future<void> _saveNow(SharedPreferences prefs, List<FlangeCheck> checks,
      {required bool afterFailedRead}) async {
    await prefs.reload();
    if (afterFailedRead) {
      await _backupUnread(prefs);
    } else {
      await _backupIfDamaged(prefs);
    }
    final encoded = encodeFlangeChecks(checks);
    if (!await prefs.setString(key, encoded)) {
      throw StateError('Could not save flange history');
    }
    await prefs.reload();
    if (prefs.get(key) != encoded) {
      throw StateError('Could not verify flange history write');
    }
  }

  /// Po nieudanym odczycie zachowaj także poprawną historię, której ekran
  /// nie widział. Pusta poprawna historia nie wymaga kopii.
  static Future<void> _backupUnread(SharedPreferences prefs) async {
    final raw = prefs.get(key);
    if (raw == null) return;
    if (raw is String) {
      final decoded = decodeFlangeChecksReport(raw);
      if (decoded.intact && decoded.checks.isEmpty) return;
    }
    await _backupRaw(prefs, raw is String ? raw : _describe(raw));
  }

  /// Kopia surowej wartości spod [key], jeśli nie jest nienaruszonym
  /// zapisem tego modułu.
  static Future<void> _backupIfDamaged(SharedPreferences prefs) async {
    final raw = prefs.get(key);
    if (raw == null) return;
    if (raw is String && decodeFlangeChecksReport(raw).intact) return;
    await _backupRaw(prefs, raw is String ? raw : _describe(raw));
  }

  static Future<void> _backupRaw(SharedPreferences prefs, String copy) async {
    String? free;
    for (final backupKey in [corruptKey, secondCorruptKey]) {
      final existing = prefs.get(backupKey);
      if (existing == copy) return;
      if (existing == null && free == null) free = backupKey;
    }
    if (free == null || !await prefs.setString(free, copy)) {
      throw StateError('Could not back up flange history');
    }
    await prefs.reload();
    if (prefs.get(free) != copy) {
      throw StateError('Could not verify flange history backup');
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
