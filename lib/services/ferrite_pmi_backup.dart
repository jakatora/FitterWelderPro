import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../database/local_record_owner.dart';
import '../features/ferrite_pmi/ferrite_pmi_store.dart';
import 'owned_prefs.dart';

/// Only measurement history and its original recovery copies may travel.
/// Account credentials, Premium, consent and arbitrary preferences cannot.
class FerritePmiBackup {
  static const entry = 'records/ferrite_pmi.json';
  static const keys = {
    FerritePmiStore.key,
    FerritePmiStore.corruptBackupKey,
    FerritePmiStore.corruptLastBackupKey,
  };

  static Map<String, Object?> decode(List<int> bytes) {
    final raw = jsonDecode(utf8.decode(bytes));
    if (raw is! Map || raw.keys.any((key) => !keys.contains(key))) {
      throw const FormatException('Invalid measurement history keys');
    }
    final result = <String, Object?>{};
    for (final key in raw.keys.cast<String>()) {
      final value = raw[key];
      if (value != null &&
          value is! String &&
          value is! bool &&
          value is! int &&
          !(value is double && value.isFinite) &&
          !(value is List && value.every((e) => e is String))) {
        throw const FormatException('Invalid measurement history value');
      }
      result[key] = value is List ? value.cast<String>().toList() : value;
    }
    return result;
  }

  static Future<FerritePmiBackup> capture(LocalRecordOwner owner) async {
    owner.requireCurrent();
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    owner.requireCurrent();
    final values = <String, Object?>{
      for (final key in keys) key: prefs.get(OwnedPrefs.keyFor(key, owner)),
    };
    // Validate even damaged values without interpreting or deleting their data.
    decode(utf8.encode(jsonEncode(values)));
    return FerritePmiBackup._(prefs, owner, values);
  }

  FerritePmiBackup._(this._prefs, this._owner, this.values);
  final SharedPreferences _prefs;
  final LocalRecordOwner _owner;
  final Map<String, Object?> values;
  List<int> encode() => utf8.encode(jsonEncode(values));

  Future<void> apply(Map<String, Object?> incoming) =>
      _write(incoming, validateSession: true);

  /// Roll back the original owner's exact keys even if the account changed.
  /// Never resolve the current owner's identity during compensation.
  Future<void> rollback() => _write(values, validateSession: false);

  Future<void> _write(Map<String, Object?> values,
      {required bool validateSession}) async {
    for (final base in keys) {
      if (validateSession) _owner.requireCurrent();
      final key = OwnedPrefs.keyFor(base, _owner);
      final value = values[base];
      final bool ok;
      if (value == null) {
        ok = await _prefs.remove(key);
      } else if (value is String) {
        ok = await _prefs.setString(key, value);
      } else if (value is bool) {
        ok = await _prefs.setBool(key, value);
      } else if (value is int) {
        ok = await _prefs.setInt(key, value);
      } else if (value is double) {
        ok = await _prefs.setDouble(key, value);
      } else {
        ok = await _prefs.setStringList(key, (value as List).cast<String>());
      }
      if (!ok) throw StateError('Could not restore measurement history');
    }
    await _prefs.reload();
    for (final base in keys) {
      final actual = _prefs.get(OwnedPrefs.keyFor(base, _owner));
      if (jsonEncode(actual) != jsonEncode(values[base])) {
        throw StateError('Measurement history was not persisted');
      }
    }
    if (validateSession) _owner.requireCurrent();
  }
}
