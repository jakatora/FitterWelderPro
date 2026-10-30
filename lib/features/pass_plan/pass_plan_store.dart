// Zapis ostatnich wejść planu ściegów w SharedPreferences (JSON z wersją
// w kluczu) — bez zmian schematu bazy. Uszkodzony zapis nie blokuje
// ekranu: odczyt zwraca wartości domyślne (albo to, co da się odczytać)
// z flagą `lossy`, a surowy zapis trafia pod jeden z kluczy kopii, zanim
// następny zapis nadpisze główny klucz.

import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import '../../database/local_record_owner.dart';
import '../../services/owned_prefs.dart';

import '../../domain/pass_plan/pass_plan_form.dart';

class PassPlanStore {
  const PassPlanStore({
    this.key = kPassPlanPrefsKey,
    this.corruptKey = kPassPlanCorruptPrefsKey,
    this.captureOwner,
  });

  final String key;

  /// Pierwsza kopia surowego zapisu odczytanego ze stratą.
  final String corruptKey;

  final Future<LocalRecordOwner> Function()? captureOwner;

  List<String> get _backupKeys => [corruptKey, '${corruptKey}_2'];

  static Future<void>? _tail;
  static int _inFlight = 0;

  /// Zapisany formularz; `null` — nic nie zapisano albo prefs niedostępne.
  Future<({Map<String, String> form, bool lossy})?> load() async {
    final SharedPreferences prefs;
    final Object? raw;
    try {
      prefs = await OwnedPrefs.instance(captureOwner);
      await prefs.reload();
      // `get`, nie `getString`: pod kluczem może leżeć inny typ.
      raw = prefs.get(key);
    } catch (_) {
      return null;
    }
    if (raw == null) return null;
    if (raw is! String) {
      await _backup(prefs, _describe(raw));
      return (form: passPlanDefaultForm(), lossy: true);
    }
    final result = decodePassPlanFormDetailed(raw);
    if (result.lossy) await _backup(prefs, raw);
    return result;
  }

  /// Autozapisy muszą kończyć się w kolejności zgłoszenia: późny zapis
  /// wcześniejszego znaku nie może zastąpić nowszego formularza.
  Future<void> save(Map<String, String> form) {
    final ownerFuture = (captureOwner ?? LocalRecordOwner.capture)();
    final previous = _inFlight > 0 ? _tail : null;
    final snapshot = Map<String, String>.of(form);
    _inFlight++;
    final Future<void> result;
    if (previous == null) {
      result = _saveCaptured(snapshot, ownerFuture);
    } else {
      result = Future.wait<Object?>([previous, ownerFuture]).then((values) {
        final owner = values[1]! as LocalRecordOwner;
        owner.requireCurrent();
        return _saveNow(snapshot, owner);
      });
    }
    _tail = result
        .then<void>((_) {}, onError: (Object _) {})
        .whenComplete(() => _inFlight--);
    return result;
  }

  Future<void> _saveCaptured(Map<String, String> form,
      Future<LocalRecordOwner> ownerFuture) async {
    final owner = await ownerFuture;
    owner.requireCurrent();
    await _saveNow(form, owner);
  }

  /// Uszkodzony surowiec musi mieć trwałą kopię przed nadpisaniem.
  Future<void> _saveNow(
      Map<String, String> form, LocalRecordOwner owner) async {
    final prefs = await OwnedPrefs.instance(() async => owner);
    await prefs.reload();
    final raw = prefs.get(key);
    if (raw != null) {
      if (raw is! String) {
        if (!await _backup(prefs, _describe(raw))) {
          throw StateError('Nie można zabezpieczyć planu ściegów.');
        }
      } else if (decodePassPlanFormDetailed(raw).lossy) {
        if (!await _backup(prefs, raw)) {
          throw StateError('Nie można zabezpieczyć planu ściegów.');
        }
      }
    }
    final encoded = encodePassPlanForm(form);
    if (!await prefs.setString(key, encoded)) {
      throw StateError('Nie można zapisać planu ściegów.');
    }
    await prefs.reload();
    if (prefs.get(key) != encoded) {
      throw StateError('Nie można potwierdzić zapisu planu ściegów.');
    }
  }

  /// Kopie są nienadpisywane; load może kontynuować mimo braku miejsca,
  /// ale save musi wtedy odmówić nadpisania głównego klucza.
  Future<bool> _backup(SharedPreferences prefs, String raw) async {
    try {
      String? free;
      for (final key in _backupKeys) {
        final value = prefs.get(key);
        if (value == raw) return true;
        if (value == null && free == null) free = key;
      }
      if (free == null || !await prefs.setString(free, raw)) return false;
      await prefs.reload();
      return prefs.get(free) == raw;
    } catch (_) {
      // Nie blokujemy odczytu formularza; save sprawdza wynik kopii.
      return false;
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
