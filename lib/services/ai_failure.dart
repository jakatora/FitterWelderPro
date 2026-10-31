import 'dart:convert';
import '../i18n/app_language.dart';

/// Only known server error codes become user-facing diagnostics. Never display
/// upstream response text (which may contain credentials or injected content).
class AiFailure {
  const AiFailure(this.status, {this.code});
  final int? status;
  final String? code;
  static const _known = {
    'AI_BUDGET_EXCEEDED',
    'AI_BUSY',
    'AI_CONFIG',
    'AI_PLAN_INVALID',
    'AI_CONTEXT_CHANGED',
    'API_RATE_LIMITED',
    'PREMIUM_REQUIRED',
    'INSTALL_SECRET_REQUIRED',
    'INSTALL_SECRET_INVALID',
    'DEVICE_REQUIRED',
    'UNAUTHORIZED',
  };

  factory AiFailure.fromHttp(int status, List<int> body) {
    String? code;
    if (body.length <= 16384) {
      try {
        final decoded = jsonDecode(utf8.decode(body));
        final error = decoded is Map ? decoded['error'] : null;
        final value = error is Map ? error['code'] : null;
        if (value is String && _known.contains(value)) code = value;
      } catch (_) {
        /* HTML proxy errors and malformed bodies are not trusted. */
      }
    }
    return AiFailure(status, code: code);
  }

  String message(AppLanguage lang, {bool commands = false}) {
    final en = lang == AppLanguage.en;
    if (code == 'AI_CONTEXT_CHANGED') {
      return en
          ? 'Your account or AI settings changed. Repeat the request.'
          : 'Konto lub ustawienia AI zmieniły się. Powtórz polecenie.';
    }
    if (status == 503 && code == 'AI_BUDGET_EXCEEDED') {
      return en
          ? 'The monthly AI cost limit has been reached. AI will be available when the budget renews.'
          : 'Osiągnięto miesięczny limit kosztów AI. AI będzie dostępne po odnowieniu budżetu.';
    }
    if (status == 404) {
      return en
          ? 'AI is not running in this version of the service yet.'
          : 'AI nie jest jeszcze uruchomione w tej wersji usługi.';
    }
    if (status == 401 || status == 403) {
      return en
          ? 'The AI connection could not be authenticated. Try again; if you enabled your professional profile, check your account session.'
          : 'Nie udało się uwierzytelnić połączenia z AI. Spróbuj ponownie; jeśli włączono profil zawodowy dla AI, sprawdź sesję konta.';
    }
    if (status == 429) {
      if (code == 'API_RATE_LIMITED') {
        return en
            ? 'Too many requests at once. Wait a moment and try again.'
            : 'Zbyt wiele żądań naraz. Odczekaj chwilę i spróbuj ponownie.';
      }
      return en
          ? 'Daily AI limit reached. Try again tomorrow.'
          : 'Osiągnięto dzienny limit AI. Spróbuj jutro.';
    }
    if (status == 402) {
      return en
          ? 'AI currently requires Premium. Local commands and calculators remain available.'
          : 'AI wymaga teraz Premium. Polecenia lokalne i kalkulatory są nadal dostępne.';
    }
    if (code == 'AI_PLAN_INVALID') {
      return en
          ? 'AI did not return a valid proposal. Try clarifying the request.'
          : 'AI nie zwróciło poprawnej propozycji. Spróbuj doprecyzować polecenie.';
    }
    if (status == 400 || status == 502 || code == 'AI_CONFIG') {
      return en
          ? 'AI requires a service update or configuration fix. Try again later.'
          : 'AI wymaga aktualizacji lub poprawienia konfiguracji usługi. Spróbuj później.';
    }
    if (status == null) {
      return en
          ? 'Could not connect to AI. Check your internet connection and try again.'
          : 'Nie udało się połączyć z AI. Sprawdź internet i spróbuj ponownie.';
    }
    return commands
        ? (en
            ? 'AI command interpretation is temporarily unavailable.'
            : 'Interpretacja poleceń AI jest chwilowo niedostępna.')
        : (en
            ? 'The assistant is temporarily unavailable. Try again later.'
            : 'Asystent chwilowo niedostępny. Spróbuj ponownie później.');
  }
}
