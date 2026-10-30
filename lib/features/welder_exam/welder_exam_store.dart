/// Statystyki egzaminu spawacza w SharedPreferences (JSON, wersja w kluczu).
///
/// Bez bazy SQLite — moduł nie zmienia schematu. Uszkodzony zapis
/// (nieczytelny JSON, inna wersja, wartość innego typu, wpis pominięty przy
/// odczycie) NIE ginie przy następnym zapisie: zanim [save] go nadpisze,
/// surowa wartość trafia pod [corruptKey]. Istniejąca kopia nie jest
/// nadpisywana, a inne uszkodzenie blokuje nowy zapis.
///
/// Nieudany ODCZYT (wyjątek platformy) to co innego: wartość w pamięci może
/// być dobra, tylko ekran jej nie zna. Wtedy pierwszy [save] z
/// `afterFailedRead: true` kopiuje surową wartość pod [corruptKey] nawet
/// nienaruszoną; jeśli miejsce kopii zajmuje inny zapis, wstrzymuje zapis.
library;

import 'dart:convert';

import 'package:flutter/foundation.dart' show debugPrint, protected;
import '../../database/local_record_owner.dart';
import '../../services/owned_prefs.dart';

import '../../domain/exam/exam_session.dart';

/// Wynik odczytu.
class WelderExamLoad {
  const WelderExamLoad(this.stats,
      {this.damaged = false, this.readFailed = false});

  final ExamStats stats;

  /// Coś było zapisane, ale nie dało się tego (w całości) odczytać.
  final bool damaged;

  /// Odczyt rzucił wyjątek.
  final bool readFailed;
}

class WelderExamStore {
  const WelderExamStore({this.captureOwner});

  final Future<LocalRecordOwner> Function()? captureOwner;

  static const String key = 'welder_exam_v1';
  static const String corruptKey = 'welder_exam_v1_corrupt';

  /// Surowa wartość spod [key] (punkt podmiany w teście).
  @protected
  Future<Object?> readRaw() async =>
      (await OwnedPrefs.instance(captureOwner)).get(key);

  /// Nigdy nie rzuca.
  Future<WelderExamLoad> load() async {
    try {
      final raw = await readRaw();
      if (raw == null) return const WelderExamLoad(ExamStats());
      if (raw is! String) {
        return const WelderExamLoad(ExamStats(), damaged: true);
      }
      final d = decodeExamStats(raw);
      return WelderExamLoad(d.stats, damaged: !d.intact);
    } catch (e) {
      debugPrint('[welder_exam] read failed: $e');
      return const WelderExamLoad(ExamStats(), damaged: true, readFailed: true);
    }
  }

  Future<void> save(ExamStats stats, {bool afterFailedRead = false}) async {
    final prefs = await OwnedPrefs.instance(captureOwner);
    final raw = prefs.get(key);
    if (raw != null &&
        (afterFailedRead || raw is! String || !decodeExamStats(raw).intact)) {
      final copy = raw is String ? raw : _describe(raw);
      final existing = prefs.get(corruptKey);
      if (existing != null && existing != copy) {
        throw StateError('Different exam stats are already backed up');
      }
      if (existing == null && !await prefs.setString(corruptKey, copy)) {
        throw StateError('Could not back up exam stats');
      }
    }
    if (!await prefs.setString(key, encodeExamStats(stats))) {
      throw StateError('Could not save exam stats');
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
