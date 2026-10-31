// Wysyłka kolejki feedbacku: `POST {baseUrl}/api/fitter/feedback`.
//
// - [FeedbackUploader.flush] (wysyłka automatyczna): bez zgody
//   (feedback_consent.dart) — ZERO żądań; zgoda sprawdzana też przed każdą
//   kolejną partią (cofnięcie w trakcie zatrzymuje wysyłkę).
// - [FeedbackUploader.sendExplicit] („Wyślij” przy jednym jawnym zgłoszeniu):
//   zgoda per zgłoszenie — wysyła TYLKO ten element, reszty kolejki nie rusza.
// - Partie po ≤ 20, od najstarszych; nagłówek `X-Feedback-Id` (nigdy
//   `X-Device-Id` ani `X-Install-Secret` czatu); timeout 15 s.
// - Pule limitów serwera: jawne i automatyczne liczą się osobno, a partia
//   mieszana podlega obu. Dlatego jawne idą OSOBNYMI partiami i PIERWSZE;
//   429 w puli jawnych nie wstrzymuje automatycznych (i odwrotnie).
// - Przed wysyłką elementy niezgodne z kontraktem
//   (FeedbackSignal.contractViolation) odpadają: automatyczne są usuwane
//   (`rejected`), jawne dostają blokadę — serwer odrzuca całą partię, gdy
//   choć jeden element jest zły.
// - 200 {"accepted","duplicates"} → elementy usunięte z kolejki (markSent).
// - 400 z `error.code` = [kFeedbackInvalidItemCode] → wina elementów
//   wskazanych w `error.indices` (albo `error.index`): automatyczne są
//   usuwane (`rejected`), jawne blokowane, reszta partii idzie ponownie.
//   Bez poprawnych indeksów → błąd protokołu.
// - KAŻDE inne 400 (BAD_FEEDBACK_ID, UNSUPPORTED_VERSION, BAD_REQUEST,
//   BAD_JSON) i 413 (PAYLOAD_TOO_LARGE) to wina żądania: nic nie jest
//   kasowane, wysyłka się kończy ([UploadStatus.protocolError]).
// - 404 (stary backend), 429, 503 (FEEDBACK_FULL), inne 5xx/4xx, brak sieci,
//   timeout → nic nie jest usuwane, wysyłka się kończy, kolejka czeka.
//   `Retry-After` (sekundy) z 429/503 trafia do [UploadOutcome.retryAfter].
// - Uploader NIGDY nie kasuje jawnego zgłoszenia.
// - [eraseAllFeedback]: „Usuń moje dane” bez wyścigu z wysyłką w toku.
// - Ciało ≤ ~70 KB przy najgorszej partii (limit serwera 128 KB).
// - Nigdy nie rzuca.

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../config/backend_config.dart';
import 'feedback_consent.dart';
import 'feedback_signal.dart';
import 'feedback_store.dart';

/// `error.code` w odpowiedzi 400, które znaczy „zły jest element partii”.
const String kFeedbackInvalidItemCode = 'INVALID_ITEM';

enum UploadStatus {
  /// Brak zgody — nie wysłano nic.
  noConsent,

  /// Kolejka była pusta — nie wysłano nic.
  empty,

  /// Wszystko, co było do wysłania, zostało obsłużone.
  done,

  /// Brak sieci albo timeout.
  offline,

  /// 404 — backend bez tej trasy.
  notDeployed,

  /// 429 — limit dzienny serwera.
  rateLimited,

  /// 503 — serwer nie przyjmuje zgłoszeń (np. FEEDBACK_FULL).
  serverFull,

  /// Inny błąd serwera (5xx, nieoczekiwany 4xx).
  serverError,

  /// 400 bez wskazania elementu albo 413 — rozjazd protokołu; nic nie
  /// zostało skasowane.
  protocolError,

  /// Wyczerpany limit żądań na jedną wysyłkę — reszta przy następnej.
  requestLimit,

  /// Nie udało się zapisać kolejki na telefonie (SharedPreferences).
  storageError,

  /// [FeedbackUploader.sendExplicit]: nie ma takiego jawnego zgłoszenia.
  notFound,

  /// [FeedbackUploader.sendExplicit]: zgłoszenie zablokowane (serwer go nie
  /// przyjmie w tej postaci); zostaje na liście.
  blocked,

  /// Trwa „Usuń moje dane” — nic nie jest wysyłane.
  erasing,
}

@immutable
class UploadOutcome {
  const UploadOutcome({
    required this.status,
    this.requests = 0,
    this.sent = 0,
    this.accepted = 0,
    this.duplicates = 0,
    this.rejected = 0,
    this.blocked = 0,
    this.remaining = 0,
    this.retryAfter,
  });

  final UploadStatus status;

  /// Liczba wykonanych żądań HTTP.
  final int requests;

  /// Sygnały usunięte z kolejki po 200.
  final int sent;

  /// Suma `accepted` z odpowiedzi serwera.
  final int accepted;

  /// Suma `duplicates` z odpowiedzi serwera.
  final int duplicates;

  /// Automatyczne sygnały odrzucone (niezgodne z kontraktem) i usunięte.
  final int rejected;

  /// Jawne zgłoszenia zablokowane w tej wysyłce (zostają w kolejce).
  final int blocked;

  /// Sygnały, które zostały w kolejce (razem z zablokowanymi).
  final int remaining;

  /// `Retry-After` z 429/503 (tylko postać w sekundach), inaczej null.
  final Duration? retryAfter;

  @override
  String toString() => 'UploadOutcome(${status.name}, requests: $requests, '
      'sent: $sent, rejected: $rejected, blocked: $blocked, '
      'remaining: $remaining)';
}

/// Wynik [eraseAllFeedback].
enum FeedbackEraseResult {
  /// Serwer skasował zgłoszenia; lokalnie wszystko usunięte (zgoda,
  /// identyfikator, kolejka).
  erased,

  /// Ta instalacja nie miała identyfikatora — na serwerze nic nie ma;
  /// lokalnie wszystko usunięte.
  nothingOnServer,

  /// Serwer nie potwierdził kasowania. Zgoda cofnięta, kolejka usunięta,
  /// ale identyfikator ZOSTAJE, żeby można było ponowić kasowanie.
  serverFailed,

  /// Nie potwierdzono usunięcia lokalnych danych. Można ponowić operację.
  localFailed,
}

class FeedbackUploader {
  FeedbackUploader({
    FeedbackStore? store,
    FeedbackConsent? consent,
    this.timeout = const Duration(seconds: 15),
    this.maxRequests = 40,
  })  : _store = store ?? FeedbackStore.instance,
        _consent = consent ?? FeedbackConsent.instance;

  static final FeedbackUploader instance = FeedbackUploader();

  final FeedbackStore _store;
  final FeedbackConsent _consent;
  final Duration timeout;
  final int maxRequests;

  Future<UploadOutcome>? _inFlight;
  final Set<Future<void>> _active = {};
  bool _erasing = false;

  static Uri get endpoint =>
      Uri.parse('${BackendConfig.baseUrl}${BackendConfig.feedback}');

  /// Śledzi operację do [waitIdle].
  Future<T> _track<T>(Future<T> op) {
    final settled = op.then<void>((_) {}, onError: (Object _) {});
    _active.add(settled);
    settled.whenComplete(() => _active.remove(settled));
    return op;
  }

  /// Kończy się, gdy nie trwa żadna wysyłka ([flush], [sendExplicit]) —
  /// także te, które ruszyły w trakcie czekania.
  Future<void> waitIdle() async {
    while (_active.isNotEmpty) {
      await Future.wait(_active.toList());
    }
  }

  static const UploadOutcome _erasingOutcome =
      UploadOutcome(status: UploadStatus.erasing);

  /// Wysyła kolejkę (tylko ze zgodą). Równoległe wywołanie dostaje wynik
  /// trwającej wysyłki. [client] — do testów (`MockClient`); bez niego
  /// tworzony i zamykany własny klient.
  Future<UploadOutcome> flush({http.Client? client}) {
    if (_erasing) return Future.value(_erasingOutcome);
    return _inFlight ??=
        _track(_flush(client)).whenComplete(() => _inFlight = null);
  }

  /// „Wyślij” przy jednym jawnym zgłoszeniu: wysyła TYLKO element [id]
  /// (`kind = explicit`), bez sprawdzania ogólnej zgody — zgodą jest to
  /// kliknięcie. Pozostałych elementów kolejki nie dotyka.
  Future<UploadOutcome> sendExplicit(String id, {http.Client? client}) {
    if (_erasing) return Future.value(_erasingOutcome);
    return _track(_sendExplicit(id, client));
  }

  /// Gotowa procedura „Usuń moje dane” dla zgłoszeń:
  /// 1. cofnięcie zgody (nowe partie już nie ruszą) i blokada wysyłek;
  /// 2. [waitIdle] — żądanie wysłane PRZED kasowaniem musi dojść wcześniej,
  ///    inaczej jego zgłoszenia zostałyby na serwerze bez identyfikatora;
  /// 3. [deleteOnServer] z zapisanym `X-Feedback-Id` (pomijane, gdy go nie ma);
  /// 4. dopiero po sukcesie — skasowanie zgody, identyfikatora i kolejki.
  /// Gdy serwer zawiedzie (false albo wyjątek), identyfikator zostaje.
  Future<FeedbackEraseResult> eraseAll({
    required Future<bool> Function(String feedbackId) deleteOnServer,
  }) async {
    _erasing = true;
    try {
      await _consent.revoke();
      await waitIdle();
      final String? id;
      try {
        id = await _consent.storedInstallId();
      } catch (e) {
        debugPrint('FeedbackUploader.eraseAll read ID: ${e.runtimeType}');
        return FeedbackEraseResult.localFailed;
      }
      var serverOk = true;
      if (id != null) {
        try {
          serverOk = await deleteOnServer(id);
        } catch (e) {
          debugPrint('FeedbackUploader.eraseAll: ${e.runtimeType}');
          serverOk = false;
        }
      }
      final localOk = await _store.clear();
      if (!serverOk) return FeedbackEraseResult.serverFailed;
      if (!localOk || !await _consent.clearAll()) {
        return FeedbackEraseResult.localFailed;
      }
      return id == null
          ? FeedbackEraseResult.nothingOnServer
          : FeedbackEraseResult.erased;
    } finally {
      _erasing = false;
    }
  }

  Future<UploadOutcome> _flush(http.Client? client) async {
    final run = _Run();
    try {
      if (!await _consent.isGranted()) {
        return const UploadOutcome(status: UploadStatus.noConsent);
      }
      if ((await _store.takeBatch(1)).isEmpty) {
        return UploadOutcome(
            status: UploadStatus.empty,
            remaining: (await _store.list()).length);
      }
      final feedbackId = await _consent.installId();
      final http.Client c = client ?? http.Client();
      try {
        run.status = await _loop(c, feedbackId, run);
      } finally {
        if (client == null) c.close();
      }
    } catch (e) {
      debugPrint('FeedbackUploader: ${e.runtimeType}');
      run.status = UploadStatus.serverError;
    }
    return run.outcome((await _store.list()).length);
  }

  Future<UploadOutcome> _sendExplicit(String id, http.Client? client) async {
    final run = _Run();
    try {
      FeedbackSignal? item;
      for (final s in await _store.list()) {
        if (s.id == id) item = s;
      }
      if (item == null || !item.isExplicit) {
        run.status = UploadStatus.notFound;
      } else if (!item.isValidForUpload) {
        run.blocked += await _store.markBlocked([id]);
        run.status = UploadStatus.blocked;
      } else {
        final feedbackId = await _consent.installId();
        final http.Client c = client ?? http.Client();
        try {
          final stop = await _deliver(c, feedbackId, [item], run);
          run.status = stop ??
              ((await _store.blockedIds()).contains(id)
                  ? UploadStatus.blocked
                  : UploadStatus.done);
        } finally {
          if (client == null) c.close();
        }
      }
    } catch (e) {
      debugPrint('FeedbackUploader.sendExplicit: ${e.runtimeType}');
      run.status = UploadStatus.serverError;
    }
    return run.outcome((await _store.list()).length);
  }

  /// Najpierw pula jawnych, potem automatycznych — osobnymi partiami.
  Future<UploadStatus> _loop(http.Client c, String feedbackId, _Run run) async {
    final explicitStop = await _pool(c, feedbackId, run, explicit: true);
    // 429 to limit TEJ puli — automatyczne mają własny. Każdy inny powód
    // (brak sieci, protokół, pełna skrzynka, cofnięta zgoda…) dotyczy obu.
    if (explicitStop != null && explicitStop != UploadStatus.rateLimited) {
      return explicitStop;
    }
    final autoStop = await _pool(c, feedbackId, run, explicit: false);
    return autoStop ?? explicitStop ?? UploadStatus.done;
  }

  /// Wysyła jedną pulę; null = pula opróżniona, inaczej powód przerwania.
  Future<UploadStatus?> _pool(http.Client c, String feedbackId, _Run run,
      {required bool explicit}) async {
    while (true) {
      if (!await _consent.isGranted()) return UploadStatus.noConsent;
      final batch = await _store.takePoolBatch(explicit: explicit);
      if (batch.isEmpty) return null;

      final invalid = [
        for (final s in batch)
          if (!s.isValidForUpload) s,
      ];
      if (invalid.isNotEmpty) {
        final progress = await _dropOrBlock(invalid, run);
        // Bez postępu kręcilibyśmy się w miejscu bez żadnego żądania.
        if (progress == 0) return UploadStatus.storageError;
        continue;
      }

      final stop = await _deliver(c, feedbackId, batch, run);
      if (stop != null) return stop;
    }
  }

  /// Automatyczne → usunięte (rejected), jawne → zablokowane. Zwraca liczbę
  /// zmienionych elementów.
  Future<int> _dropOrBlock(List<FeedbackSignal> items, _Run run) async {
    final explicitIds = [
      for (final s in items)
        if (s.isExplicit) s.id,
    ];
    final autoIds = [
      for (final s in items)
        if (!s.isExplicit) s.id,
    ];
    final blocked =
        explicitIds.isEmpty ? 0 : await _store.markBlocked(explicitIds);
    final removed = autoIds.isEmpty ? 0 : await _store.markRejected(autoIds);
    run.blocked += blocked;
    run.rejected += removed;
    return blocked + removed;
  }

  /// Wysyła [items]; null = obsłużone (wysłane, odrzucone albo zablokowane),
  /// inaczej powód przerwania wysyłki.
  Future<UploadStatus?> _deliver(http.Client c, String feedbackId,
      List<FeedbackSignal> items, _Run run) async {
    if (run.requests >= maxRequests) return UploadStatus.requestLimit;
    run.requests++;

    final http.Response resp;
    try {
      resp = await c
          .post(
            endpoint,
            headers: {
              'Content-Type': 'application/json',
              'X-Feedback-Id': feedbackId,
            },
            body: jsonEncode(feedbackPayload(items)),
          )
          .timeout(timeout);
    } catch (e) {
      debugPrint('FeedbackUploader offline: ${e.runtimeType}');
      return UploadStatus.offline;
    }

    final code = resp.statusCode;
    if (code == 200) {
      final counts = _parseCounts(resp, items.length);
      run.accepted += counts.accepted;
      run.duplicates += counts.duplicates;
      run.sent += await _store.markSent(items.map((e) => e.id));
      return null;
    }
    final error = code == 400 || code == 413 ? _ErrorBody.parse(resp) : null;
    if (code == 400 && error?.code == kFeedbackInvalidItemCode) {
      final bad = error!.invalidIndices(items.length);
      if (bad.isEmpty) {
        debugPrint('FeedbackUploader: INVALID_ITEM bez indeksów');
        return UploadStatus.protocolError;
      }
      // Zablokowany jawny wypada z takePoolBatch, usunięty automatyczny
      // z kolejki; ewentualną awarię zapisu ogranicza limit żądań.
      await _dropOrBlock([for (final i in bad) items[i]], run);
      final rest = [
        for (var i = 0; i < items.length; i++)
          if (!bad.contains(i)) items[i],
      ];
      if (rest.isEmpty) return null;
      return _deliver(c, feedbackId, rest, run);
    }
    if (code == 400 || code == 413) {
      debugPrint('FeedbackUploader: HTTP $code ${error?.code}');
      return UploadStatus.protocolError;
    }
    if (code == 404) return UploadStatus.notDeployed;
    if (code == 429 || code == 503) {
      final seconds = int.tryParse(resp.headers['retry-after']?.trim() ?? '');
      if (seconds != null && seconds >= 0) {
        run.retryAfter = Duration(seconds: seconds);
      }
      return code == 429 ? UploadStatus.rateLimited : UploadStatus.serverFull;
    }
    debugPrint('FeedbackUploader: HTTP $code');
    return UploadStatus.serverError;
  }

  static ({int accepted, int duplicates}) _parseCounts(
      http.Response resp, int fallback) {
    try {
      final body = jsonDecode(utf8.decode(resp.bodyBytes));
      if (body is Map) {
        final a = body['accepted'];
        final d = body['duplicates'];
        if (a is int && d is int) return (accepted: a, duplicates: d);
      }
    } catch (_) {}
    return (accepted: fallback, duplicates: 0);
  }

  @visibleForTesting
  void resetForTest() {
    _inFlight = null;
    _active.clear();
    _erasing = false;
  }
}

/// „Usuń moje dane” dla zgłoszeń — patrz [FeedbackUploader.eraseAll].
/// [deleteOnServer] dostaje `X-Feedback-Id` i zwraca true, gdy serwer
/// potwierdził kasowanie (DELETE /api/fitter/me z nagłówkiem X-Feedback-Id).
Future<FeedbackEraseResult> eraseAllFeedback({
  required Future<bool> Function(String feedbackId) deleteOnServer,
}) =>
    FeedbackUploader.instance.eraseAll(deleteOnServer: deleteOnServer);

/// `{"error":{"code":"…","index":n,"indices":[…]}}` z odpowiedzi błędu.
class _ErrorBody {
  _ErrorBody(this.code, this.index, this.indices);

  final String? code;
  final Object? index;
  final Object? indices;

  static _ErrorBody? parse(http.Response resp) {
    try {
      final body = jsonDecode(utf8.decode(resp.bodyBytes));
      if (body is! Map) return null;
      final error = body['error'];
      if (error is Map) {
        final code = error['code'];
        return _ErrorBody(
            code is String ? code : null, error['index'], error['indices']);
      }
      if (error is String) return _ErrorBody(error, null, null);
    } catch (_) {}
    return null;
  }

  /// Indeksy złych elementów w partii długości [n] (`indices`, a bez nich
  /// `index`); spoza zakresu są pomijane.
  Set<int> invalidIndices(int n) {
    bool ok(Object? i) => i is int && i >= 0 && i < n;
    final list = indices;
    if (list is List) {
      final out = {
        for (final i in list)
          if (ok(i)) i as int
      };
      if (out.isNotEmpty) return out;
    }
    return ok(index) ? {index as int} : const <int>{};
  }
}

class _Run {
  UploadStatus status = UploadStatus.done;
  int requests = 0;
  int sent = 0;
  int accepted = 0;
  int duplicates = 0;
  int rejected = 0;
  int blocked = 0;
  Duration? retryAfter;

  UploadOutcome outcome(int remaining) => UploadOutcome(
        status: status,
        requests: requests,
        sent: sent,
        accepted: accepted,
        duplicates: duplicates,
        rejected: rejected,
        blocked: blocked,
        remaining: remaining,
        retryAfter: retryAfter,
      );
}
