/// Stawki akordu w SharedPreferences (JSON, klucz z wersją) — bez zmian
/// schematu bazy: dziennik spoin zostaje jedynym źródłem tego, co zrobione.
///
/// Uszkodzony zapis (nieczytelny JSON, pole złego typu albo spoza zakresu)
/// NIE ginie przy następnym zapisie: zanim [PieceworkRatesStore.save] go
/// nadpisze, surowa wartość trafia do jednej z dwóch kopii. Gdy obie są
/// zajęte innymi danymi, zapis jest wstrzymany.
library;

import 'dart:convert';

import 'package:flutter/foundation.dart' show debugPrint, protected;
import 'package:shared_preferences/shared_preferences.dart';
import '../../database/local_record_owner.dart';
import '../../services/owned_prefs.dart';

import '../../domain/piecework/piecework.dart';
import '../../domain/quotes/hourly_rate.dart';
import '../../domain/quotes/quote_calculator.dart' show toGrosze;
import '../../services/quote_settings.dart' show HourlyRateStore;

/// Wynik odczytu stawek i informacja o uszkodzeniu lub błędzie odczytu.
class PieceworkRatesLoad {
  final PieceworkRates rates;
  final bool damaged;
  final bool readFailed;
  const PieceworkRatesLoad(this.rates,
      {this.damaged = false, this.readFailed = false});
}

class PieceworkRatesStore {
  static const String key = 'piecework_rates_v1';
  static const String corruptKey = 'piecework_rates_v1_corrupt';
  static const String secondCorruptKey = '${corruptKey}_2';

  // SharedPreferences utrzymuje osobny cache. Kolejka chroni kolejność
  // rzeczywistych zapisów także przy szybkiej edycji kilku pól.
  static Future<void>? _writeTail;
  static int _writesInFlight = 0;

  final Future<LocalRecordOwner> Function()? captureOwner;

  const PieceworkRatesStore({this.captureOwner});

  @protected
  Future<Object?> readRaw() async {
    final prefs = await OwnedPrefs.instance(captureOwner);
    await prefs.reload();
    return prefs.get(key);
  }

  /// Nigdy nie rzuca: brak zapisu = stawki domyślne; uszkodzony = domyślne
  /// w uszkodzonych polach i `damaged`.
  Future<PieceworkRatesLoad> load() async {
    try {
      final raw = await readRaw();
      if (raw == null) return const PieceworkRatesLoad(PieceworkRates());
      if (raw is! String) {
        return const PieceworkRatesLoad(PieceworkRates(), damaged: true);
      }
      final d = decodePieceworkRates(raw);
      return PieceworkRatesLoad(d.rates, damaged: !d.intact);
    } catch (e) {
      debugPrint('[piecework] read rates failed: $e');
      return const PieceworkRatesLoad(PieceworkRates(),
          damaged: true, readFailed: true);
    }
  }

  Future<void> save(PieceworkRates rates, {bool afterFailedRead = false}) {
    // Tożsamość przechwytujemy w chwili żądania, nie po poprzednim zapisie.
    final ownerFuture = (captureOwner ?? LocalRecordOwner.capture)();
    final previous = _writesInFlight > 0 ? _writeTail : null;
    _writesInFlight++;
    final result = (previous ?? Future<void>.value()).then((_) async {
      final owner = await ownerFuture;
      owner.requireCurrent();
      final prefs = await OwnedPrefs.instance(() async => owner);
      await prefs.reload();
      final raw = prefs.get(key);
      if (raw != null &&
          (afterFailedRead ||
              raw is! String ||
              !decodePieceworkRates(raw).intact)) {
        await _backupRaw(prefs, raw);
      }
      final encoded = rates.encode();
      if (!await prefs.setString(key, encoded)) {
        throw StateError('Nie udało się zapisać stawek akordowych');
      }
      await prefs.reload();
      if (prefs.getString(key) != encoded) {
        throw StateError('Nie potwierdzono zapisu stawek akordowych');
      }
    });
    _writeTail = result
        .then<void>((_) {}, onError: (Object _) {})
        .whenComplete(() => _writesInFlight--);
    return result;
  }

  /// Kopia surowej wartości przed nadpisaniem; nie gubi kolejnych uszkodzeń.
  static Future<void> _backupRaw(SharedPreferences prefs, Object raw) async {
    final value = raw is String ? raw : _describe(raw);
    for (final backupKey in [corruptKey, secondCorruptKey]) {
      final existing = prefs.get(backupKey);
      if (existing == value) return;
      if (existing != null) continue;
      if (!await prefs.setString(backupKey, value)) {
        throw StateError('Nie udało się zachować kopii stawek akordowych');
      }
      await prefs.reload();
      if (prefs.getString(backupKey) != value) {
        throw StateError('Nie potwierdzono kopii stawek akordowych');
      }
      return;
    }
    throw StateError('Brak miejsca na kopię uszkodzonych stawek akordowych');
  }

  static String _describe(Object raw) {
    try {
      return jsonEncode(raw);
    } catch (_) {
      return raw.toString();
    }
  }
}

/// Minimalna stawka (zł/h netto, z rezerwą) z kalkulatora „Ile brać za
/// godzinę" w groszach — tylko gdy kalkulator był zapisany i da się ją
/// policzyć; inaczej null. Nigdy nie rzuca.
Future<int?> loadSavedHourlyMinimum() async {
  try {
    final prefs = await OwnedPrefs.instance();
    await prefs.reload();
    final raw = prefs.getString(HourlyRateStore.key);
    if (raw == null || raw.trim().isEmpty) return null;
    final r = computeHourlyRate(await const HourlyRateStore().load());
    if (r.problem != null || !(r.recommendedRate > 0)) return null;
    return toGrosze(r.recommendedRate);
  } catch (e) {
    debugPrint('[piecework] read hourly rate failed: $e');
    return null;
  }
}
