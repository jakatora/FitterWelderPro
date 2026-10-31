// Lokalna kolejka sygnałów feedbacku (SharedPreferences `feedback_queue_v1`).
//
// Zapis: {"v":1,"items":[<sygnał>...],"blocked":[<id>...],"dropped":n,
//         "rejected":n,"sent":n,"corrupt":bool} — elementy od najstarszego.
//
// Zasady:
//   - limit [FeedbackStore.capacity] = 300; przy przepełnieniu wypada
//     najstarszy sygnał AUTOMATYCZNY (licznik `dropped`), jawne zgłoszenie
//     (`explicit`) nigdy. Gdy cała kolejka to jawne zgłoszenia, nowy sygnał
//     nie wchodzi (`add` → false; automatyczny liczy się do `dropped`);
//   - `add` przyjmuje tylko sygnał zgodny z kontraktem (po ponownym
//     maskowaniu); element zapisany wcześniej, który przestał spełniać reguły
//     serwera, zostaje — uploader odsiewa go przed wysyłką;
//   - jawnego zgłoszenia NIC poza użytkownikiem nie kasuje: zamiast
//     odrzucenia dostaje blokadę (`blocked`) — zostaje na liście „Moje
//     zgłoszenia”, a automatyczna wysyłka go pomija ([takeBatch]);
//   - uszkodzony zapis (zły JSON albo element o złej STRUKTURZE): surowy
//     tekst idzie RAZ pod `feedback_queue_v1_corrupt` (pierwsza kopia nie jest
//     nadpisywana), ocalałe elementy zostają, flaga `corrupt` = true;
//   - wszystkie operacje idą przez jedną kolejkę (bez wyścigów odczyt–zapis);
//   - żadna metoda nie rzuca: feedback nie może wywrócić aplikacji.

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'feedback_signal.dart';

/// Liczniki kolejki (do „Moje zgłoszenia” i diagnostyki, nie są wysyłane).
@immutable
class FeedbackQueueStats {
  const FeedbackQueueStats({
    required this.count,
    required this.explicitCount,
    required this.blocked,
    required this.dropped,
    required this.rejected,
    required this.sent,
    required this.corrupt,
  });

  static const FeedbackQueueStats empty = FeedbackQueueStats(
    count: 0,
    explicitCount: 0,
    blocked: 0,
    dropped: 0,
    rejected: 0,
    sent: 0,
    corrupt: false,
  );

  /// Sygnały w kolejce (razem z zablokowanymi).
  final int count;

  /// W tym jawne zgłoszenia.
  final int explicitCount;

  /// Jawne zgłoszenia zablokowane (serwer ich nie przyjmie w tej postaci).
  final int blocked;

  /// Automatyczne sygnały, które wypadły przy przepełnieniu.
  final int dropped;

  /// Automatyczne sygnały odrzucone (niezgodne z kontraktem) i usunięte.
  final int rejected;

  /// Sygnały przyjęte przez serwer (200) i usunięte z kolejki.
  final int sent;

  /// Zapis był kiedyś uszkodzony (kopia pod [FeedbackStore.corruptKey]).
  final bool corrupt;
}

class FeedbackStore {
  FeedbackStore._();
  static final FeedbackStore instance = FeedbackStore._();

  static const String prefsKey = 'feedback_queue_v1';
  static const String corruptKey = 'feedback_queue_v1_corrupt';
  static const int capacity = 300;

  Future<void> _tail = Future<void>.value();

  /// Wykonuje [op] po zakończeniu wszystkich wcześniejszych operacji.
  Future<T> _serial<T>(Future<T> Function() op) {
    final result = _tail.then((_) => op());
    _tail = result.then<void>((_) {}, onError: (Object _) {});
    return result;
  }

  Future<T> _guarded<T>(String what, T fallback,
      Future<T> Function(SharedPreferences prefs, _QueueDoc doc) op) {
    return _serial(() async {
      try {
        final prefs = await SharedPreferences.getInstance();
        final doc = await _load(prefs);
        return await op(prefs, doc);
      } catch (e) {
        debugPrint('FeedbackStore.$what: ${e.runtimeType}');
        return fallback;
      }
    });
  }

  /// Wszystkie sygnały w kolejce (także zablokowane), od najstarszego.
  Future<List<FeedbackSignal>> list() => _guarded('list',
      const <FeedbackSignal>[], (_, doc) async => List.unmodifiable(doc.items));

  /// Identyfikatory zablokowanych jawnych zgłoszeń.
  Future<Set<String>> blockedIds() => _guarded('blockedIds', const <String>{},
      (_, doc) async => Set.unmodifiable(doc.blocked));

  /// Pierwsze [max] NIEZABLOKOWANYCH sygnałów (najstarsze) BEZ usuwania —
  /// usuwa [markSent] albo [markRejected] po odpowiedzi serwera.
  Future<List<FeedbackSignal>> takeBatch([int max = kFeedbackBatchMax]) =>
      _take('takeBatch', max, null);

  /// Jak [takeBatch], ale tylko z jednej puli: jawne ([explicit] = true) albo
  /// automatyczne. Serwer liczy limity obu pul osobno, a partia mieszana
  /// podlega obu — dlatego uploader nie miesza ich w jednym żądaniu.
  Future<List<FeedbackSignal>> takePoolBatch({
    required bool explicit,
    int max = kFeedbackBatchMax,
  }) =>
      _take('takePoolBatch', max, explicit);

  Future<List<FeedbackSignal>> _take(String what, int max, bool? explicit) =>
      _guarded(what, const <FeedbackSignal>[], (_, doc) async {
        if (max <= 0) return const <FeedbackSignal>[];
        return List.unmodifiable(doc.items
            .where((e) => !doc.blocked.contains(e.id))
            .where((e) => explicit == null || e.isExplicit == explicit)
            .take(max));
      });

  /// Dodaje sygnał (tekst jeszcze raz maskowany — [FeedbackSignal.sanitized]).
  /// false = nie wszedł (niezgodny z kontraktem albo kolejka pełna jawnych
  /// zgłoszeń). Ponowne dodanie tego samego `id` nic nie zmienia.
  Future<bool> add(FeedbackSignal raw) =>
      _guarded('add', false, (prefs, doc) async {
        final signal = raw.sanitized();
        if (!signal.isValidForUpload) return false;
        if (doc.items.any((e) => e.id == signal.id)) return true;

        while (doc.items.length >= capacity) {
          final oldestAuto = doc.items.indexWhere((e) => !e.isExplicit);
          if (oldestAuto < 0) break;
          doc.items.removeAt(oldestAuto);
          doc.dropped++;
        }
        if (doc.items.length >= capacity) {
          // Same jawne zgłoszenia — żadne nie wypada.
          if (signal.isExplicit) return false;
          doc.dropped++;
          await _save(prefs, doc);
          return false;
        }
        doc.items.add(signal);
        await _save(prefs, doc);
        return true;
      });

  /// Usuwa jeden sygnał — decyzja użytkownika (np. „Moje zgłoszenia”).
  Future<bool> remove(String id) =>
      _guarded('remove', false, (prefs, doc) async {
        final before = doc.items.length;
        doc.items.removeWhere((e) => e.id == id);
        if (doc.items.length == before) return false;
        doc.blocked.remove(id);
        await _save(prefs, doc);
        return true;
      });

  /// Usuwa sygnały przyjęte przez serwer. Zwraca liczbę usuniętych.
  Future<int> markSent(Iterable<String> ids) {
    final set = ids.toSet();
    return _guarded('markSent', 0, (prefs, doc) async {
      final before = doc.items.length;
      doc.items.removeWhere((e) => set.contains(e.id));
      final removed = before - doc.items.length;
      if (removed == 0) return 0;
      doc.blocked.removeAll(set);
      doc.sent += removed;
      await _save(prefs, doc);
      return removed;
    });
  }

  /// Odrzucone sygnały: AUTOMATYCZNE są usuwane (licznik `rejected`), jawne
  /// NIGDY — dostają blokadę jak w [markBlocked]. Zwraca liczbę usuniętych.
  Future<int> markRejected(Iterable<String> ids) {
    final set = ids.toSet();
    return _guarded('markRejected', 0, (prefs, doc) async {
      var changed = false;
      for (final e in doc.items) {
        if (e.isExplicit && set.contains(e.id) && doc.blocked.add(e.id)) {
          changed = true;
        }
      }
      final before = doc.items.length;
      doc.items.removeWhere((e) => !e.isExplicit && set.contains(e.id));
      final removed = before - doc.items.length;
      doc.rejected += removed;
      if (removed > 0 || changed) await _save(prefs, doc);
      return removed;
    });
  }

  /// Blokuje jawne zgłoszenia (serwer ich nie przyjmie w tej postaci):
  /// zostają w kolejce, automatyczna wysyłka je pomija. Zwraca liczbę nowo
  /// zablokowanych. Sygnały automatyczne są ignorowane.
  Future<int> markBlocked(Iterable<String> ids) {
    final set = ids.toSet();
    return _guarded('markBlocked', 0, (prefs, doc) async {
      var n = 0;
      for (final e in doc.items) {
        if (e.isExplicit && set.contains(e.id) && doc.blocked.add(e.id)) n++;
      }
      if (n > 0) await _save(prefs, doc);
      return n;
    });
  }

  Future<FeedbackQueueStats> stats() => _guarded(
        'stats',
        FeedbackQueueStats.empty,
        (_, doc) async => FeedbackQueueStats(
          count: doc.items.length,
          explicitCount: doc.items.where((e) => e.isExplicit).length,
          blocked: doc.blocked.length,
          dropped: doc.dropped,
          rejected: doc.rejected,
          sent: doc.sent,
          corrupt: doc.corrupt,
        ),
      );

  /// Usuwa kolejkę, liczniki i kopię uszkodzonego zapisu („Usuń moje dane”).
  Future<void> clear() => _serial(() async {
        try {
          final prefs = await SharedPreferences.getInstance();
          await prefs.remove(prefsKey);
          await prefs.remove(corruptKey);
        } catch (e) {
          debugPrint('FeedbackStore.clear: ${e.runtimeType}');
        }
      });

  /// Tylko do testów: nowa kolejka operacji (stan jest w SharedPreferences).
  @visibleForTesting
  void resetForTest() {
    _tail = Future<void>.value();
  }

  // ── zapis / odczyt ──────────────────────────────────────────────────────

  Future<_QueueDoc> _load(SharedPreferences prefs) async {
    await prefs.reload();
    final doc = _QueueDoc();
    var damaged = false;
    String? raw;
    try {
      raw = prefs.getString(prefsKey);
    } catch (_) {
      // Pod kluczem leży wartość innego typu niż tekst.
      raw = '${prefs.get(prefsKey)}';
      damaged = true;
    }
    if (raw == null || raw.isEmpty) return doc;
    if (!damaged) damaged = !_parseInto(raw, doc);

    if (damaged) {
      final existing = prefs.get(corruptKey);
      if (existing != null && existing != raw) {
        throw StateError('Different feedback queue is already backed up');
      }
      if (existing == null && !await prefs.setString(corruptKey, raw)) {
        throw StateError('Could not back up feedback queue');
      }
      await prefs.reload();
      if (prefs.get(corruptKey) != raw) {
        throw StateError('Feedback queue backup was not persisted');
      }
      doc.corrupt = true;
      await _save(prefs, doc);
    }
    return doc;
  }

  Future<void> _save(SharedPreferences prefs, _QueueDoc doc) async {
    final encoded = jsonEncode(doc.toJson());
    final ok = await prefs.setString(prefsKey, encoded);
    if (!ok) throw StateError('prefs write failed');
    await prefs.reload();
    if (prefs.getString(prefsKey) != encoded) {
      throw StateError('feedback queue was not persisted');
    }
  }

  /// Wypełnia [doc] z zapisu. false = coś było uszkodzone (ocalałe elementy
  /// i liczniki zostają w [doc]).
  static bool _parseInto(String raw, _QueueDoc doc) {
    var intact = true;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return false;
      doc.dropped = _count(decoded['dropped']);
      doc.rejected = _count(decoded['rejected']);
      doc.sent = _count(decoded['sent']);
      doc.corrupt = decoded['corrupt'] == true;
      final items = decoded['items'];
      if (items is! List) return false;
      final seen = <String>{};
      for (final e in items) {
        try {
          if (e is! Map) throw const FormatException('item');
          final s = FeedbackSignal.fromJson(Map<String, Object?>.from(e));
          if (seen.add(s.id)) doc.items.add(s);
        } on FormatException {
          intact = false;
        } on TypeError {
          intact = false;
        }
      }
      final blocked = decoded['blocked'];
      if (blocked is List) {
        final explicitIds = {
          for (final s in doc.items)
            if (s.isExplicit) s.id,
        };
        doc.blocked
            .addAll(blocked.whereType<String>().where(explicitIds.contains));
      }
    } on FormatException {
      return false;
    }
    return intact;
  }

  static int _count(Object? v) => v is int && v >= 0 ? v : 0;
}

class _QueueDoc {
  final List<FeedbackSignal> items = [];
  final Set<String> blocked = {};
  int dropped = 0;
  int rejected = 0;
  int sent = 0;
  bool corrupt = false;

  Map<String, Object?> toJson() => {
        'v': 1,
        'items': [for (final s in items) s.toJson()],
        'blocked': [
          for (final s in items)
            if (blocked.contains(s.id)) s.id,
        ],
        'dropped': dropped,
        'rejected': rejected,
        'sent': sent,
        'corrupt': corrupt,
      };
}
