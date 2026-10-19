// Wysyłka kolejki feedbacku: `POST {baseUrl}/api/fitter/feedback`.
//
// - Bez zgody (feedback_consent.dart) — ZERO żądań; zgoda sprawdzana też przed
//   każdą kolejną partią (cofnięcie w trakcie zatrzymuje wysyłkę).
// - Partie po ≤ 20, od najstarszych; nagłówek `X-Feedback-Id` (nigdy
//   `X-Device-Id` czatu); timeout 15 s.
// - Przed wysyłką elementy niezgodne z kontraktem
//   (FeedbackSignal.contractViolation) są usuwane z licznikiem `rejected` —
//   serwer odrzuca całą partię, gdy choć jeden element jest zły.
// - 200 {"accepted","duplicates"} → elementy usunięte z kolejki (markSent).
// - 400 mimo odsiewu → partię dzielimy na pół, aż zostaną pojedyncze
//   odrzucone elementy — te są usuwane z licznikiem `rejected`, reszta idzie
//   normalnie (jeden zły element nie kasuje 19 dobrych).
// - 404 (stary backend), 429, 503 (FEEDBACK_FULL), inne 5xx/4xx, brak sieci,
//   timeout → nic nie jest usuwane, wysyłka się kończy, kolejka czeka.
//   `Retry-After` (sekundy) z 429/503 trafia do [UploadOutcome.retryAfter].
// - Ciało ≤ ~70 KB przy najgorszej partii (limit serwera 128 KB).
// - Limit żądań na jedno [FeedbackUploader.flush] (domyślnie 40).
// - Nigdy nie rzuca.

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../config/backend_config.dart';
import 'feedback_consent.dart';
import 'feedback_signal.dart';
import 'feedback_store.dart';

enum UploadStatus {
  /// Brak zgody — nie wysłano nic.
  noConsent,

  /// Kolejka była pusta — nie wysłano nic.
  empty,

  /// Wszystko, co było w kolejce, zostało obsłużone.
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

  /// Wyczerpany limit żądań na jedną wysyłkę — reszta przy następnej.
  requestLimit,

  /// Nie udało się zapisać kolejki na telefonie (SharedPreferences).
  storageError,
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
    this.remaining = 0,
    this.retryAfter,
  });

  final UploadStatus status;

  /// `Retry-After` z 429/503 (tylko postać w sekundach), inaczej null.
  final Duration? retryAfter;

  /// Liczba wykonanych żądań HTTP.
  final int requests;

  /// Sygnały usunięte z kolejki po 200.
  final int sent;

  /// Suma `accepted` z odpowiedzi serwera.
  final int accepted;

  /// Suma `duplicates` z odpowiedzi serwera.
  final int duplicates;

  /// Sygnały odrzucone (niezgodne z kontraktem albo 400) i usunięte.
  final int rejected;

  /// Sygnały, które zostały w kolejce.
  final int remaining;

  @override
  String toString() => 'UploadOutcome(${status.name}, requests: $requests, '
      'sent: $sent, rejected: $rejected, remaining: $remaining)';
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

  static Uri get endpoint =>
      Uri.parse('${BackendConfig.baseUrl}${BackendConfig.feedback}');

  /// Wysyła kolejkę. Równoległe wywołanie dostaje wynik trwającej wysyłki.
  /// [client] — do testów (`MockClient`); bez niego tworzony i zamykany
  /// własny klient.
  Future<UploadOutcome> flush({http.Client? client}) {
    return _inFlight ??= _flush(client).whenComplete(() => _inFlight = null);
  }

  Future<UploadOutcome> _flush(http.Client? client) async {
    final run = _Run();
    try {
      if (!await _consent.isGranted()) {
        return const UploadOutcome(status: UploadStatus.noConsent);
      }
      if ((await _store.takeBatch(1)).isEmpty) {
        return const UploadOutcome(status: UploadStatus.empty);
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
    return UploadOutcome(
      status: run.status,
      requests: run.requests,
      sent: run.sent,
      accepted: run.accepted,
      duplicates: run.duplicates,
      rejected: run.rejected,
      remaining: (await _store.list()).length,
      retryAfter: run.retryAfter,
    );
  }

  Future<UploadStatus> _loop(http.Client c, String feedbackId, _Run run) async {
    while (true) {
      if (!await _consent.isGranted()) return UploadStatus.noConsent;
      final batch = await _store.takeBatch(kFeedbackBatchMax);
      if (batch.isEmpty) return UploadStatus.done;

      final invalid = [
        for (final s in batch)
          if (!s.isValidForUpload) s.id,
      ];
      if (invalid.isNotEmpty) {
        final removed = await _store.markRejected(invalid);
        run.rejected += removed;
        // Bez postępu kręcilibyśmy się w miejscu bez żadnego żądania.
        if (removed == 0) return UploadStatus.storageError;
        continue;
      }

      final stop = await _deliver(c, feedbackId, batch, run);
      if (stop != null) return stop;
    }
  }

  /// Wysyła [items]; null = obsłużone (wysłane albo odrzucone), inaczej powód
  /// przerwania wysyłki.
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
    if (code == 400) {
      if (items.length == 1) {
        run.rejected += await _store.markRejected([items.single.id]);
        return null;
      }
      final mid = items.length ~/ 2;
      final first = await _deliver(c, feedbackId, items.sublist(0, mid), run);
      if (first != null) return first;
      return _deliver(c, feedbackId, items.sublist(mid), run);
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
}

class _Run {
  UploadStatus status = UploadStatus.done;
  int requests = 0;
  int sent = 0;
  int accepted = 0;
  int duplicates = 0;
  int rejected = 0;
  Duration? retryAfter;
}
