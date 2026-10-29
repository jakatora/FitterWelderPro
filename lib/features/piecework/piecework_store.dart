/// Stawki akordu w SharedPreferences (JSON, klucz z wersją) — bez zmian
/// schematu bazy: dziennik spoin zostaje jedynym źródłem tego, co zrobione.
///
/// Uszkodzony zapis (nieczytelny JSON, pole złego typu albo spoza zakresu)
/// NIE ginie przy następnym zapisie: zanim [PieceworkRatesStore.save] go
/// nadpisze, surowa wartość trafia pod [PieceworkRatesStore.corruptKey] —
/// tylko raz, istniejąca kopia nie jest nadpisywana (jak w kołnierzach).
library;

import 'dart:convert';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:shared_preferences/shared_preferences.dart';
import '../../database/local_record_owner.dart';
import '../../services/owned_prefs.dart';

import '../../domain/piecework/piecework.dart';
import '../../domain/quotes/hourly_rate.dart';
import '../../domain/quotes/quote_calculator.dart' show toGrosze;
import '../../services/quote_settings.dart' show HourlyRateStore;

/// Wynik odczytu stawek: stawki i to, czy zapis był uszkodzony.
class PieceworkRatesLoad {
  final PieceworkRates rates;
  final bool damaged;
  const PieceworkRatesLoad(this.rates, {this.damaged = false});
}

class PieceworkRatesStore {
  static const String key = 'piecework_rates_v1';
  static const String corruptKey = 'piecework_rates_v1_corrupt';

  final Future<LocalRecordOwner> Function()? captureOwner;

  const PieceworkRatesStore({this.captureOwner});

  /// Nigdy nie rzuca: brak zapisu = stawki domyślne; uszkodzony = domyślne
  /// w uszkodzonych polach i `damaged`.
  Future<PieceworkRatesLoad> load() async {
    try {
      final prefs = await OwnedPrefs.instance(captureOwner);
      final raw = prefs.get(key);
      if (raw == null) return const PieceworkRatesLoad(PieceworkRates());
      if (raw is! String) {
        return const PieceworkRatesLoad(PieceworkRates(), damaged: true);
      }
      final d = decodePieceworkRates(raw);
      return PieceworkRatesLoad(d.rates, damaged: !d.intact);
    } catch (e) {
      debugPrint('[piecework] read rates failed: $e');
      return const PieceworkRatesLoad(PieceworkRates(), damaged: true);
    }
  }

  Future<void> save(PieceworkRates rates) async {
    final prefs = await OwnedPrefs.instance(captureOwner);
    await _backupIfDamaged(prefs);
    await prefs.setString(key, rates.encode());
  }

  /// Kopia surowej wartości spod [key], jeśli nie jest nienaruszonym
  /// zapisem stawek i kopii jeszcze nie ma.
  static Future<void> _backupIfDamaged(SharedPreferences prefs) async {
    final raw = prefs.get(key);
    if (raw == null) return;
    if (raw is String && decodePieceworkRates(raw).intact) return;
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

/// Minimalna stawka (zł/h netto, z rezerwą) z kalkulatora „Ile brać za
/// godzinę" w groszach — tylko gdy kalkulator był zapisany i da się ją
/// policzyć; inaczej null. Nigdy nie rzuca.
Future<int?> loadSavedHourlyMinimum() async {
  try {
    final prefs = await OwnedPrefs.instance();
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
