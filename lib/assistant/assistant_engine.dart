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

import '../config/backend_config.dart';
import '../i18n/app_language.dart';
import '../services/legal_consent.dart';
import 'assistant_intent_client.dart';
import 'assistant_intents.dart';
import 'assistant_parser.dart';
import 'assistant_validator.dart';

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
      if (check is! AssistantNeedsField) {
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
        case RemoteIntentProposal(:final intent, fields: final remoteFields):
          if (intent != local.intent) {
            // Serwer widzi inną operację niż parser — trzymamy się lokalnej i
            // dopytujemy użytkownika, zamiast zgadywać.
            return AssistantOutcome(
                intent: local.intent,
                check: check,
                fields: local.fields,
                usedRemote: true);
          }
          final rejection = findAssistantRejection(intent, remoteFields);
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
      case RemoteIntentProposal(:final intent, :final fields, :final question):
        if (intent == kIntentUnknown) {
          return AssistantOutcome(
            intent: kIntentUnknown,
            check: null,
            usedRemote: true,
            remoteQuestion: question,
          );
        }
        final check = validateAssistantProposal(intent, fields);
        if (check is AssistantRejected) {
          return AssistantOutcome(
            intent: intent,
            check: check,
            usedRemote: true,
            remoteRejected: check.reason,
          );
        }
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
