import '../security/credential_text.dart';
// Klient `POST /api/fitter/ai/intent` — klasyfikacja polecenia przez model na
// serwerze, gdy parser lokalny nie dał rady.
//
// Kontrakt (backend robi osobny agent):
//   nagłówki X-Device-Id, X-Install-Secret (PremiumService.authHeaders),
//   body {"text", "lang": "pl"|"en", "intents_version": 1},
//   200 {"intent", "fields": {...}, "question": null|"..."},
//   401/402/429/503 — błędy jak w /ai/chat; 404 = stary backend → jak brak sieci.
//
// Klient NIE ufa odpowiedzi: zwraca surowe pola, a o tym, czy cokolwiek z nich
// trafi na ekran podsumowania, decyduje assistant_validator.dart.

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:http/http.dart' as http;

import '../config/backend_config.dart';
import '../i18n/app_language.dart';
import '../services/premium_service.dart';
import '../services/ai_failure.dart';
import 'assistant_intents.dart';

enum RemoteUnavailableKind {
  /// Brak sieci, timeout, stary backend (404).
  offline,

  /// 402 PREMIUM_REQUIRED.
  premiumRequired,

  /// 429 — dzienny limit wyczerpany.
  dailyLimit,

  /// 503 (AI_BUDGET_EXCEEDED i inne) — asystent chwilowo niedostępny.
  busy,

  /// 401 — serwer nie przyjął tożsamości instalacji.
  unauthorized,

  /// 200, ale odpowiedź nie ma kształtu z kontraktu.
  malformed,

  /// Inny błąd serwera (5xx, 400).
  error,

  /// Nie pytaliśmy: brak zgody na wysyłanie treści na serwer.
  notAllowed,
}

sealed class RemoteIntentResult {
  const RemoteIntentResult();
}

class RemoteIntentProposal extends RemoteIntentResult {
  final String intent;
  final Map<String, Object?> fields;
  final String? question;
  const RemoteIntentProposal(this.intent, this.fields, this.question);
}

class RemoteIntentUnavailable extends RemoteIntentResult {
  final RemoteUnavailableKind kind;
  const RemoteIntentUnavailable(this.kind);
}

class AssistantIntentClient {
  const AssistantIntentClient();

  Future<RemoteIntentResult> classify(String text, AppLanguage lang) async {
    if (containsCredentialValue(text)) {
      return const RemoteIntentUnavailable(RemoteUnavailableKind.notAllowed);
    }
    final url = Uri.parse('${BackendConfig.baseUrl}${BackendConfig.aiIntent}');
    http.Response resp;
    try {
      final identity = await PremiumService.instance.authHeaders();
      resp = await http
          .post(
            url,
            headers: {'Content-Type': 'application/json', ...identity},
            body: jsonEncode({
              'text': text,
              'lang': lang.name,
              'intents_version': kAssistantIntentsVersion,
            }),
          )
          .timeout(const Duration(seconds: 15));
    } catch (e) {
      debugPrint('AssistantIntentClient offline: ${e.runtimeType}');
      return const RemoteIntentUnavailable(RemoteUnavailableKind.offline);
    }

    switch (resp.statusCode) {
      case 200:
        break;
      case 404:
        return const RemoteIntentUnavailable(RemoteUnavailableKind.offline);
      case 401:
        return const RemoteIntentUnavailable(
            RemoteUnavailableKind.unauthorized);
      case 402:
        return const RemoteIntentUnavailable(
            RemoteUnavailableKind.premiumRequired);
      case 429:
        if (AiFailure.fromHttp(resp.statusCode, resp.bodyBytes).code ==
            'API_RATE_LIMITED') {
          return const RemoteIntentUnavailable(RemoteUnavailableKind.busy);
        }
        return const RemoteIntentUnavailable(RemoteUnavailableKind.dailyLimit);
      case 503:
        return const RemoteIntentUnavailable(RemoteUnavailableKind.busy);
      default:
        debugPrint('AssistantIntentClient: HTTP ${resp.statusCode}');
        return const RemoteIntentUnavailable(RemoteUnavailableKind.error);
    }

    try {
      final body = jsonDecode(utf8.decode(resp.bodyBytes));
      if (body is! Map) throw const FormatException('not an object');
      final intent = body['intent'];
      final fields = body['fields'] ?? const <String, Object?>{};
      final question = body['question'];
      if (intent is! String || fields is! Map) {
        throw const FormatException('bad intent/fields');
      }
      return RemoteIntentProposal(
        intent,
        {for (final e in fields.entries) e.key.toString(): e.value},
        question is String && question.trim().isNotEmpty
            ? question.trim()
            : null,
      );
    } catch (e) {
      debugPrint('AssistantIntentClient: malformed response ($e)');
      return const RemoteIntentUnavailable(RemoteUnavailableKind.malformed);
    }
  }
}
