import '../../services/account_service.dart';
import '../../database/local_record_owner.dart';
// Rejestr temperatury podgrzania i międzyściegowej w SharedPreferences
// (JSON z wersją w kluczu i w treści) — bez zmian schematu bazy.
//
// Odporność: odczyt przez `prefs.get` (inny typ pod kluczem nie wywraca
// ekranu), uszkodzony zapis albo pominięte wpisy → kopia surowego tekstu
// pod osobnym kluczem PRZED pierwszym nadpisaniem; operacje szeregowane
// (zapis przy każdej zmianie, odczyt po powrocie zawsze widzi ostatni zapis).

import 'dart:convert';
import 'package:flutter/foundation.dart';

import 'package:shared_preferences/shared_preferences.dart';

import '../../domain/welding/interpass_log.dart';

/// Wynik odczytu rejestru.
class InterpassLoad {
  final List<InterpassWeld> welds;

  /// Zapis był (całkiem albo częściowo) nieczytelny — surowy tekst jest
  /// w [InterpassStore.corruptBackupKey].
  final bool corrupt;
  const InterpassLoad(this.welds, {this.corrupt = false});
}

/// Rejestr pełny — nowej spoiny nie zapisano (stare nie wypadają po cichu:
/// to dowody dla QC).
class InterpassStoreFull implements Exception {
  const InterpassStoreFull();
  @override
  String toString() => 'InterpassStoreFull(${InterpassStore.maxWelds})';
}

class InterpassStore {
  static final changes = ValueNotifier<int>(0);

  static const String key = 'interpass_log_v1';

  /// Kopia nieczytelnego zapisu — zanim pierwszy zapis go nadpisze.
  static const String corruptBackupKey = '${key}_corrupt';

  /// Wszystkie miejsca na kopie (maks. 3): kolejna, INNA nieczytelna treść
  /// trafia do następnego wolnego; przy komplecie zastępuje tylko ostatnią
  /// (pierwsza — najstarsza uszkodzona treść — zostaje zawsze).
  static const List<String> corruptBackupKeys = [
    corruptBackupKey,
    '${key}_corrupt_2',
    '${key}_corrupt_3',
  ];

  /// Jednostka wyświetlania (`c` / `f`) — osobno od danych.
  static const String unitKey = 'interpass_unit_v1';

  /// Tyle spoin mieści rejestr; od [warnAt] ekran ostrzega.
  static const int maxWelds = 200;
  static const int warnAt = 180;

  const InterpassStore({Future<LocalRecordOwner> Function()? captureOwner})
      : _captureOwner = captureOwner;
  final Future<LocalRecordOwner> Function()? _captureOwner;

  InterpassStore scoped(Future<LocalRecordOwner> Function() capture) =>
      InterpassStore(captureOwner: () async {
        final previous = _captureOwner == null ? null : await _captureOwner();
        previous?.requireCurrent();
        final owner = await capture();
        previous?.requireCurrent();
        owner.requireCurrent();
        if (previous != null && previous.key != owner.key) {
          throw AccountException('Sesja rejestru temperatury zmieniła się.');
        }
        return owner;
      });

  static String ownerKey(String base, LocalRecordOwner owner) =>
      owner.key == LocalRecordOwner.guest
          ? base
          : '$base.owner.${Uri.encodeComponent(owner.key)}';

  Future<T> _owned<T>(Future<T> Function(LocalRecordOwner) op,
      {LocalRecordOwner? expectedOwner}) async {
    expectedOwner?.requireCurrent();
    final owner = await (_captureOwner ?? LocalRecordOwner.capture)();
    owner.requireCurrent();
    expectedOwner?.requireCurrent();
    if (expectedOwner != null && expectedOwner.key != owner.key) {
      throw AccountException('Właściciel rejestru temperatury zmienił się.');
    }
    return _serial(() async {
      owner.requireCurrent();
      expectedOwner?.requireCurrent();
      final result = await op(owner);
      owner.requireCurrent();
      expectedOwner?.requireCurrent();
      return result;
    });
  }

  static Future<void>? _tail;
  static int _inFlight = 0;

  static Future<T> _serial<T>(Future<T> Function() op) {
    final prev = _inFlight > 0 ? _tail : null;
    _inFlight++;
    final result = prev == null ? op() : prev.then((_) => op());
    _tail = result
        .then<void>((_) {}, onError: (Object _) {})
        .whenComplete(() => _inFlight--);
    return result;
  }

  /// Spoiny od ostatnio zmienionej.
  Future<InterpassLoad> load() => _owned(_loadNow);

  Future<InterpassLoad> _loadNow(LocalRecordOwner owner) async {
    final prefs = await SharedPreferences.getInstance();
    owner.requireCurrent();
    Object? raw;
    try {
      raw = prefs.get(ownerKey(key, owner));
      if (raw == null || (raw is String && raw.isEmpty)) {
        return const InterpassLoad([]);
      }
      if (raw is! String) throw const FormatException('not a string');
      final parsed = interpassLogFromJson(jsonDecode(raw));
      // Pominięte spoiny, pomiary albo nieczytelne pola — pierwszy zapis
      // usunąłby je na stałe, więc najpierw kopia surowego tekstu.
      if (parsed.lossy) {
        await _backup(prefs, raw, owner);
        return InterpassLoad(sortInterpassWelds(parsed.welds), corrupt: true);
      }
      return InterpassLoad(sortInterpassWelds(parsed.welds));
    } on AccountException {
      rethrow;
    } catch (_) {
      if (raw != null) await _backup(prefs, raw, owner);
      return const InterpassLoad([], corrupt: true);
    }
  }

  /// Kopia surowego tekstu: ta sama treść — bez nowej kopii; inna — do
  /// następnego wolnego miejsca, a przy komplecie zamiast ostatniej.
  static Future<void> _backup(
      SharedPreferences prefs, Object raw, LocalRecordOwner owner) async {
    owner.requireCurrent();
    final text = raw.toString();
    String? free;
    for (final base in corruptBackupKeys) {
      final k = ownerKey(base, owner);
      final saved = prefs.get(k);
      if (saved == null) {
        free ??= k;
      } else if (saved.toString() == text) {
        return;
      }
    }
    await prefs.setString(
        free ?? ownerKey(corruptBackupKeys.last, owner), text);
    owner.requireCurrent();
  }

  Future<void> _write(List<InterpassWeld> list, LocalRecordOwner owner) async {
    owner.requireCurrent();
    final prefs = await SharedPreferences.getInstance();
    owner.requireCurrent();
    final ok = await prefs.setString(ownerKey(key, owner),
        jsonEncode(interpassLogToJson(sortInterpassWelds(list))));
    if (!ok) throw StateError('SharedPreferences.setString($key) failed');
    owner.requireCurrent();
    changes.value++;
  }

  /// Zapisuje (nową albo zmienioną) spoinę. Pusta spoina (nic nie wpisano)
  /// nie trafia do rejestru — a jeśli była zapisana, znika. Nowa spoina
  /// przy pełnym rejestrze → [InterpassStoreFull].
  Future<void> upsert(InterpassWeld weld) => _owned((owner) async {
        final list = [...(await _loadNow(owner)).welds];
        final existed = list.any((w) => w.id == weld.id);
        list.removeWhere((w) => w.id == weld.id);
        if (!weld.isBlank) {
          if (!existed && list.length >= maxWelds) {
            throw const InterpassStoreFull();
          }
          list.add(weld);
        }
        await _write(list, owner);
      });

  /// Zmienia zapisaną spoinę [id] (np. „Cofnij” po zamknięciu jej ekranu).
  /// `false`, gdy spoiny już nie ma.
  Future<bool> update(
          String id, InterpassWeld Function(InterpassWeld w) change) =>
      _owned((owner) async {
        final list = [...(await _loadNow(owner)).welds];
        final i = list.indexWhere((w) => w.id == id);
        if (i < 0) return false;
        list[i] = change(list[i]);
        await _write(list, owner);
        return true;
      });

  /// Optimistic, serialised replacement for a previewed assistant operation.
  /// A corrupt log, removed record or later manual edit must never be replaced.
  Future<bool> replaceIfUnchanged(
          InterpassWeld expected, InterpassWeld replacement,
          {LocalRecordOwner? expectedOwner}) =>
      _owned((owner) async {
        expectedOwner?.requireCurrent();
        if (expected.id != replacement.id || replacement.isBlank) return false;
        final load = await _loadNow(owner);
        expectedOwner?.requireCurrent();
        if (load.corrupt) return false;
        final list = [...load.welds];
        final matches =
            list.indexed.where((e) => e.$2.id == expected.id).toList();
        if (matches.length != 1 ||
            jsonEncode(matches.single.$2.toJson()) !=
                jsonEncode(expected.toJson())) {
          return false;
        }
        list[matches.single.$1] = replacement;
        await _write(list, owner);
        return true;
      }, expectedOwner: expectedOwner);

  Future<void> delete(String id) => _owned((owner) async {
        final list = [...(await _loadNow(owner)).welds]
          ..removeWhere((w) => w.id == id);
        await _write(list, owner);
      });

  Future<InterpassUnit> loadUnit() => _owned((owner) async {
        final prefs = await SharedPreferences.getInstance();
        owner.requireCurrent();
        return InterpassUnit.byName(prefs.get(ownerKey(unitKey, owner))) ??
            InterpassUnit.c;
      });

  Future<void> saveUnit(InterpassUnit unit) => _owned((owner) async {
        final prefs = await SharedPreferences.getInstance();
        owner.requireCurrent();
        final ok = await prefs.setString(ownerKey(unitKey, owner), unit.name);
        owner.requireCurrent();
        if (!ok) {
          throw StateError('SharedPreferences.setString($unitKey) failed');
        }
      });
}
