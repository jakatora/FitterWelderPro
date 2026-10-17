/// Statystyki egzaminu spawacza w SharedPreferences (JSON, wersja w kluczu).
///
/// Bez bazy SQLite — moduł nie zmienia schematu. Uszkodzony zapis
/// (nieczytelny JSON, inna wersja, wartość innego typu, wpis pominięty przy
/// odczycie) NIE ginie przy następnym zapisie: zanim [save] go nadpisze,
/// surowa wartość trafia pod [corruptKey] — tylko raz, istniejąca kopia nie
/// jest nadpisywana (ta sama mechanika co bolt_kit_store.dart).
///
/// Nieudany ODCZYT (wyjątek platformy) to co innego: wartość w pamięci może
/// być dobra, tylko ekran jej nie zna. Wtedy pierwszy [save] z
/// `afterFailedRead: true` kopiuje surową wartość pod [corruptKey] nawet
/// nienaruszoną (jeśli kopii jeszcze nie ma).
library;

import 'dart:convert';

import 'package:flutter/foundation.dart' show debugPrint, protected;
import 'package:shared_preferences/shared_preferences.dart';

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
  const WelderExamStore();

  static const String key = 'welder_exam_v1';
  static const String corruptKey = 'welder_exam_v1_corrupt';

  /// Surowa wartość spod [key] (punkt podmiany w teście).
  @protected
  Future<Object?> readRaw() async =>
      (await SharedPreferences.getInstance()).get(key);

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
    final prefs = await SharedPreferences.getInstance();
    await _backup(prefs, always: afterFailedRead);
    await prefs.setString(key, encodeExamStats(stats));
  }

  /// Kopia surowej wartości spod [key] — gdy nie jest nienaruszonym zapisem
  /// tego modułu (albo [always]) i kopii jeszcze nie ma.
  static Future<void> _backup(SharedPreferences prefs,
      {required bool always}) async {
    try {
      final raw = prefs.get(key);
      if (raw == null) return;
      if (!always && raw is String && decodeExamStats(raw).intact) return;
      if (prefs.containsKey(corruptKey)) return;
      await prefs.setString(corruptKey, raw is String ? raw : _describe(raw));
    } catch (e) {
      // Kopia to zabezpieczenie — jej brak nie może zablokować zapisu.
      debugPrint('[welder_exam] backup failed: $e');
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
