import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:http/http.dart' as http;

import '../config/backend_config.dart';

/// Thin HTTP wrapper used by every service that talks to the Railway backend.
///
/// What it adds on top of `package:http`:
///   - one place to enforce a sensible timeout per call (default 10 s),
///   - automatic retry (1 attempt) on transient failures: 5xx, socket reset,
///     `SocketException`, `HandshakeException`, `TimeoutException`,
///   - exponential back-off between attempts (500 ms → ~1.5 s with jitter),
///   - structured `debugPrint` of failures so support has something useful,
///   - small `_isTransient` helper kept private to avoid services replicating
///     the same `e.toString().contains(...)` check.
///
/// Non-goals: this is not an OpenAPI client. JSON parsing stays inside each
/// service (`AiChatService`, `JobsService`, etc.) so the model shape lives
/// next to where it's consumed.
class ApiClient {
  ApiClient._({http.Client? client}) : _client = client ?? http.Client();

  static final ApiClient instance = ApiClient._();

  final http.Client _client;

  /// GET → JSON map. Throws [ApiException] with the actual status code on
  /// non-2xx response after retries are exhausted.
  Future<Map<String, dynamic>> getJson(
    String path, {
    Map<String, String>? query,
    Duration timeout = const Duration(seconds: 10),
    Map<String, String>? headers,
  }) async {
    final uri = Uri.parse('${BackendConfig.baseUrl}$path')
        .replace(queryParameters: query);
    final resp = await _withRetry(
      'GET $path',
      () => _client.get(uri, headers: {
        'Accept': 'application/json',
        ...?headers,
      }).timeout(timeout),
    );
    return _decode(resp, path);
  }

  /// POST JSON body → JSON map.
  Future<Map<String, dynamic>> postJson(
    String path, {
    required Map<String, dynamic> body,
    Duration timeout = const Duration(seconds: 12),
    Map<String, String>? headers,
  }) async {
    final uri = Uri.parse('${BackendConfig.baseUrl}$path');
    final resp = await _withRetry(
      'POST $path',
      () => _client
          .post(
            uri,
            headers: {
              'Content-Type': 'application/json',
              ...?headers,
            },
            body: jsonEncode(body),
          )
          .timeout(timeout),
    );
    return _decode(resp, path);
  }

  /// Runs [send] once. On transient failure waits ~500 ms + jitter and tries
  /// again. We intentionally cap at one retry — a backend issue lasting more
  /// than a second is going to take human attention; spinning won't help.
  Future<http.Response> _withRetry(
    String label,
    Future<http.Response> Function() send,
  ) async {
    try {
      final resp = await send();
      if (_isRetryableStatus(resp.statusCode)) {
        debugPrint('ApiClient $label → ${resp.statusCode}, retrying once');
        await _backoff(0);
        return await send();
      }
      return resp;
    } catch (e) {
      if (_isTransient(e)) {
        debugPrint('ApiClient $label → transient ${e.runtimeType}, retrying once');
        await _backoff(0);
        return await send();
      }
      rethrow;
    }
  }

  static bool _isRetryableStatus(int code) =>
      code == 502 || code == 503 || code == 504;

  static bool _isTransient(Object e) =>
      e is SocketException ||
      e is HandshakeException ||
      e is TimeoutException ||
      (e is http.ClientException &&
          e.toString().toLowerCase().contains('connection'));

  static Future<void> _backoff(int attempt) {
    // Half a second base, ±25% jitter so we don't synchronise retries with
    // every other client when the backend hiccups.
    final base = 500 * math.pow(2, attempt).toInt();
    final jitter = math.Random().nextInt((base * 0.25).toInt());
    return Future.delayed(Duration(milliseconds: base + jitter));
  }

  Map<String, dynamic> _decode(http.Response resp, String path) {
    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      // Try to surface the backend's `error.message` if present; otherwise
      // fall back to the status code. The raw body goes to debugPrint so
      // services don't have to.
      String? backendMessage;
      try {
        final body = jsonDecode(resp.body) as Map<String, dynamic>;
        final err = body['error'];
        if (err is Map && err['message'] is String) {
          backendMessage = err['message'] as String;
        }
      } catch (_) {}
      debugPrint(
          'ApiClient $path failed ${resp.statusCode}: ${resp.body.substring(0, math.min(resp.body.length, 200))}');
      throw ApiException(
        statusCode: resp.statusCode,
        path: path,
        backendMessage: backendMessage,
      );
    }
    return jsonDecode(resp.body) as Map<String, dynamic>;
  }
}

/// Backend response surfaced as a typed exception so services can map status
/// codes to friendly messages (429 → rate-limited, 401 → re-auth, etc.).
class ApiException implements Exception {
  final int statusCode;
  final String path;
  final String? backendMessage;
  ApiException({
    required this.statusCode,
    required this.path,
    this.backendMessage,
  });

  @override
  String toString() =>
      'ApiException($statusCode on $path${backendMessage == null ? '' : ': $backendMessage'})';
}
