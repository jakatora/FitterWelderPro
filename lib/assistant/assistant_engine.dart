// Silnik trybu „Wykonaj": tekst → propozycja → walidator.
//
// Kolejność (spec §6 + decyzja architektoniczna 1):
//   1. parser lokalny (offline, bez zgody);
//   2. dopiero gdy parser nie rozpoznał intencji albo zabrakło pól, a jest
//      zgoda na wysyłanie treści — `POST /ai/intent`;
//   3. KAŻDY wynik (lokalny i z serwera) przechodzi przez ten sam walidator.
//
// Silnik niczego nie zapisuje. Zwraca [AssistantOutcome], a ekran pokazuje
// pytanie, odmowę albo podsumowanie do potwierdzenia.
//
// Intencje tylko lokalne (dziennik spoin, „moje parametry", pytanie do trybu
// „Odpowiedz") NIGDY nie idą na serwer — serwer ich nie zna (kontrakt V1).

import '../config/backend_config.dart';
import '../i18n/app_language.dart';
import '../services/legal_consent.dart';
import 'assistant_intent_client.dart';
import 'assistant_intents.dart';
import 'assistant_parser.dart';
import 'assistant_validator.dart';
import 'core/command_words.dart' show referencesInstruction;
import 'core/utterance.dart';

class AssistantOutcome {
  /// Intencja, której dotyczy wynik ([kIntentUnknown], gdy nic nie rozpoznano).
  final String intent;

  /// Wynik walidatora; `null` = nie zrozumiano polecenia.
  final AssistantCheck? check;

  /// Pola po złączeniu (do przeniesienia w odpowiedzi na pytanie).
  final Map<String, Object?> fields;

  /// Czy odpowiedź serwera wpłynęła na wynik (albo została odrzucona).
  final bool usedRemote;

  /// Serwer odpowiedział, ale walidator odrzucił jego pola.
  final AssistantRejectReason? remoteRejected;

  /// Serwera nie zapytano albo nie odpowiedział.
  final RemoteUnavailableKind? remoteUnavailable;

  /// Pytanie od serwera, gdy ten też nie rozpoznał polecenia.
  final String? remoteQuestion;

  const AssistantOutcome({
    required this.intent,
    required this.check,
    this.fields = const {},
    this.usedRemote = false,
    this.remoteRejected,
    this.remoteUnavailable,
    this.remoteQuestion,
  });
}

/// Pola z serwera → kody aplikacji. Gaz, złącze i pozycja przechodzą przez
/// aliasy kontraktu („Ar 99.996" → AR, „BW" → BUTT); wartość bez aliasu
/// odpada SAMA (pole opcjonalne), zamiast odrzucać całą odpowiedź. Pola spoza
/// kontraktu V1 zostają — walidator odrzuci wtedy całość (extraField).
Map<String, Object?> normalizeRemoteFields(Map<String, Object?> fields) {
  final out = <String, Object?>{};
  for (final e in fields.entries) {
    final v = e.value;
    if (v == null) continue;
    if (e.key == 'gas' || e.key == 'joint' || e.key == 'position') {
      final code = normalizeAssistantCode(e.key, v);
      if (code != null) out[e.key] = code;
      continue;
    }
    out[e.key] = v;
  }
  return out;
}

/// Odrzucenie odpowiedzi serwera: intencja spoza kontraktu V1 albo pole
/// spoza jej listy (np. pole tylko lokalne) — potem zwykły walidator.
AssistantRejected? _remoteContractRejection(
    String intent, Map<String, Object?> fields) {
  final spec = kAssistantIntentsV1[intent];
  if (spec == null) {
    return const AssistantRejected(AssistantRejectReason.unknownIntent);
  }
  for (final key in fields.keys) {
    if (!spec.allFields.contains(key)) {
      return AssistantRejected(AssistantRejectReason.extraField, key);
    }
  }
  return findAssistantRejection(intent, fields);
}

/// Domyślnie: serwer tylko po akceptacji zasad (tej samej, co przy czacie).
Future<bool> _consentGiven() async {
  if (!BackendConfig.aiBackendLive) return false;
  await LegalConsent.instance.load();
  return LegalConsent.instance.isAccepted;
}

class AssistantEngine {
  final AssistantIntentClient remote;
  final Future<bool> Function() remoteAllowed;

  AssistantEngine({
    this.remote = const AssistantIntentClient(),
    Future<bool> Function()? remoteAllowed,
  }) : remoteAllowed = remoteAllowed ?? _consentGiven;

  Future<AssistantOutcome> interpret(
    String text, {
    required AppLanguage lang,
    Map<String, Object?> carried = const {},
    String? carriedIntent,
    String? answeringField,
  }) async {
    if (referencesInstruction(Utterance(text, lang: lang))) {
      final fields = <String, Object?>{'text': text.trim()};
      return AssistantOutcome(
        intent: kIntentAnswerQuestion,
        check: validateAssistantProposal(kIntentAnswerQuestion, fields),
        fields: fields,
      );
    }
    // ── Odpowiedź na nasze pytanie o jedno pole: tylko lokalnie ────────────
    if (answeringField != null && carriedIntent != null) {
      final answer = carriedIntent == kIntentOpenTool
          ? <String, Object?>{'query': text.trim()}
          : parseFieldAnswer(answeringField, text);
      final fields = {...carried, ...answer};
      return AssistantOutcome(
        intent: carriedIntent,
        check: validateAssistantProposal(carriedIntent, fields),
        fields: fields,
      );
    }

    final local = parseAssistantCommand(text);

    if (local.intent != kIntentUnknown) {
      final check = validateAssistantProposal(local.intent, local.fields);
      if (check is! AssistantNeedsField ||
          !kAssistantRemoteIntents.contains(local.intent)) {
        return AssistantOutcome(
            intent: local.intent, check: check, fields: local.fields);
      }
      // Brakuje pola — serwer może je wyczytać ze zdania, jeśli wolno pytać.
      if (!await remoteAllowed()) {
        return AssistantOutcome(
          intent: local.intent,
          check: check,
          fields: local.fields,
          remoteUnavailable: RemoteUnavailableKind.notAllowed,
        );
      }
      final r = await remote.classify(text, lang);
      switch (r) {
        case RemoteIntentUnavailable(:final kind):
          return AssistantOutcome(
            intent: local.intent,
            check: check,
            fields: local.fields,
            remoteUnavailable: kind,
          );
        case RemoteIntentProposal(:final intent, fields: final rawFields):
          final remoteFields = normalizeRemoteFields(rawFields);
          if (intent != local.intent) {
            // Serwer widzi inną operację niż parser — trzymamy się lokalnej i
            // dopytujemy użytkownika, zamiast zgadywać.
            return AssistantOutcome(
                intent: local.intent,
                check: check,
                fields: local.fields,
                usedRemote: true);
          }
          final rejection = _remoteContractRejection(intent, remoteFields);
          if (rejection != null) {
            return AssistantOutcome(
              intent: local.intent,
              check: check,
              fields: local.fields,
              usedRemote: true,
              remoteRejected: rejection.reason,
            );
          }
          // Lokalnie odczytane wartości wygrywają — to dosłownie słowa
          // użytkownika; serwer tylko uzupełnia braki.
          final merged = <String, Object?>{
            for (final e in remoteFields.entries)
              if (e.value != null) e.key: e.value,
            ...local.fields,
          };
          return AssistantOutcome(
            intent: local.intent,
            check: validateAssistantProposal(local.intent, merged),
            fields: merged,
            usedRemote: true,
          );
      }
    }

    // ── Parser nie rozpoznał polecenia ─────────────────────────────────────
    if (!await remoteAllowed()) {
      return const AssistantOutcome(
        intent: kIntentUnknown,
        check: null,
        remoteUnavailable: RemoteUnavailableKind.notAllowed,
      );
    }
    final r = await remote.classify(text, lang);
    switch (r) {
      case RemoteIntentUnavailable(:final kind):
        return AssistantOutcome(
            intent: kIntentUnknown, check: null, remoteUnavailable: kind);
      case RemoteIntentProposal(
          :final intent,
          fields: final rawFields,
          :final question
        ):
        final fields = normalizeRemoteFields(rawFields);
        if (intent == kIntentUnknown) {
          return AssistantOutcome(
            intent: kIntentUnknown,
            check: null,
            usedRemote: true,
            remoteQuestion: question,
          );
        }
        final rejected = _remoteContractRejection(intent, fields);
        if (rejected != null) {
          return AssistantOutcome(
            intent: intent,
            check: rejected,
            usedRemote: true,
            remoteRejected: rejected.reason,
          );
        }
        final check = validateAssistantProposal(intent, fields);
        return AssistantOutcome(
          intent: intent,
          check: check,
          fields: {
            for (final e in fields.entries)
              if (e.value != null) e.key: e.value,
          },
          usedRemote: true,
        );
    }
  }
}
