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

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart' show debugPrint, protected;
import 'package:shared_preferences/shared_preferences.dart';
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
  static Future<void>? _writes;
  const WelderExamStore({this.captureOwner});

  final Future<LocalRecordOwner> Function()? captureOwner;

  static const String key = 'welder_exam_v1';
  static const String corruptKey = 'welder_exam_v1_corrupt';

  /// Surowa wartość spod [key] (punkt podmiany w teście).
  @protected
  Future<Object?> readRaw() async {
    final prefs = await OwnedPrefs.instance(captureOwner);
    await prefs.reload();
    return prefs.get(key);
  }

  /// Nigdy nie rzuca.
  Future<WelderExamLoad> load() async {
    try {
      final pending = _writes;
      if (pending != null) await pending;
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

  Future<void> save(ExamStats stats, {bool afterFailedRead = false}) {
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
    final encoded = encodeExamStats(stats);
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
      await prefs.reload();
      if (prefs.get(corruptKey) != copy) {
        throw StateError('Exam stats backup was not persisted');
      }
    }
    if (!await prefs.setString(key, encoded)) {
      throw StateError('Could not save exam stats');
    }
    await prefs.reload();
    if (prefs.get(key) != encoded) {
      throw StateError('Exam stats were not persisted');
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
