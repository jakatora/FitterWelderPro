import '../security/credential_text.dart';
import '../domain/iso_notebook/sketch_summary.dart';
import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart' show debugPrint, visibleForTesting;
import 'package:http/http.dart' as http;

import '../config/backend_config.dart';
import '../i18n/app_language.dart';
import 'help_search.dart';
import 'premium_service.dart';
import 'ai_professional_context.dart';
import 'ai_failure.dart';

// AI chat service — tryb „Odpowiedz" asystenta (lib/screens/ai_chat_screen.dart).
//
// 2026-09: asystent jest dostępny BEZ Premium. Backend pilnuje dziennego
// limitu (429) i budżetu AI (503); gdy włączy flagę AI_CHAT_REQUIRES_PREMIUM,
// odpowiada 402. Każdy z tych przypadków dostaje własny komunikat
// ([AiReplyKind]); brak sieci, 404 i inne błędy → wpis z pomocy offline.
// Co wychodzi z telefonu: treść pytania, najwyżej [kChatHistoryMax] ostatnich
// wpisów rozmowy (pary pytanie → odpowiedź modelu lub potwierdzony wynik aplikacji, bez bieżącego pytania —
// [chatHistoryForRequest]), język interfejsu, device_id i nagłówki
// tożsamości instalacji.
//
// Historia fazy 5a:
// Phase 5a (this stub): client-side interface only. `sendMessage()` returns
// a canned response so the chat UI can be developed and reviewed without
// a live backend. The `aiBackendAvailable` constant is checked by the UI
// to decide whether to show "Coming soon" or a real input box.
//
// Phase 5b will wire this up to:
//   - Cloud Function / Railway endpoint that holds the Anthropic API key
//   - Retrieval over `docs/piping_knowledge.md` (270 KB, 100 iteracji wiedzy)
//   - Claude Haiku 4.5 (default) or Sonnet 4.6 (premium tier-2 maybe)
//
// We deliberately keep the API surface narrow (one async send + a stream of
// new messages) so the consumer screen doesn't depend on transport details.

/// Convenience re-export so the UI doesn't have to know about BackendConfig.
/// Source of truth lives in lib/config/backend_config.dart — flip the flag
/// there to switch between demo and live mode.
bool get kAiBackendAvailable => BackendConfig.aiBackendLive;

// Pole `units` (P1-37) zniknęło z żądania: backend waliduje treść schematem
// {message, history, lang, device_id} i nieznanych pól nie czyta. Podwójne
// jednostki (SI + imperialne) to reguła promptu po stronie serwera.

enum ChatRole { user, assistant, system }

/// Skąd pochodzi odpowiedź asystenta — UI i testy odróżniają odpowiedź modelu
/// od pomocy offline i od komunikatu o limicie (spec §11: błąd AI nie jest
/// przedstawiany jako wiarygodna odpowiedź).
enum AiReplyKind {
  /// Verified response from the native app executor, usable as conversation context.
  nativeAction,

  /// Local clarification/status for display, excluded from verified AI context.
  localDialogue,

  /// Odpowiedź modelu z serwera.
  live,

  /// Brak sieci / stary backend / błąd serwera → wpis z pomocy w aplikacji.
  offlineHelp,

  /// 402 PREMIUM_REQUIRED.
  premiumRequired,

  /// 429 — dzienny limit wyczerpany.
  dailyLimit,

  /// 503 (AI_BUDGET_EXCEEDED itp.) — chwilowo niedostępny.
  unavailable,

  /// Tryb demo (backend wyłączony flagą) albo wiadomość powitalna.
  demo,
}

class ChatMessage {
  final ChatRole role;
  final String text;
  final DateTime timestamp;
  final AiReplyKind kind;

  /// Optional citation list — populated in Phase 5b when retrieval is wired up.
  /// Each entry is the heading of the knowledge-base section the response
  /// drew from (e.g. "Iteration 75 — P91 welding").
  final List<String> citations;

  ChatMessage({
    required this.role,
    required this.text,
    DateTime? timestamp,
    this.citations = const [],
    this.kind = AiReplyKind.demo,
  }) : timestamp = timestamp ?? DateTime.now();
}

/// Ile ostatnich wpisów rozmowy (bez bieżącego pytania) idzie do `/ai/chat`.
/// Ten sam limit ma backend (CHAT_HISTORY_MAX) — dłuższą historię przycina.
const int kChatHistoryMax = 6;

/// Historia do wysłania: same pary „pytanie → odpowiedź modelu lub potwierdzony wynik aplikacji" (bez
/// powitania, pomocy offline, komunikatów o limitach i bez pytania, które
/// jeszcze nie ma odpowiedzi — czyli bez bieżącego), najwyżej
/// [kChatHistoryMax] ostatnich wpisów, zawsze od pytania użytkownika.
List<ChatMessage> chatHistoryForRequest(List<ChatMessage> all,
    {int max = kChatHistoryMax}) {
  final pairs = <ChatMessage>[];
  for (var i = 0; i + 1 < all.length; i++) {
    final q = all[i];
    final a = all[i + 1];
    if (q.role == ChatRole.user &&
        a.role == ChatRole.assistant &&
        !containsCredentialValue(q.text) &&
        !containsCredentialValue(a.text) &&
        (a.kind == AiReplyKind.live || a.kind == AiReplyKind.nativeAction)) {
      pairs
        ..add(q)
        ..add(a);
      i++;
    }
  }
  final keep = max - max % 2; // pełne pary
  return pairs.length <= keep ? pairs : pairs.sublist(pairs.length - keep);
}

class AiChatService {
  AiChatService._();
  static final AiChatService instance = AiChatService._();

  /// Send a user message and receive the assistant reply asynchronously.
  /// In Phase 5a we return a stub answer pulled from a static demo map so
  /// the UI flow can be reviewed end-to-end.
  Future<ChatMessage> sendMessage(
    String userText, {
    List<ChatMessage> history = const [],
    SketchSummary? isoSummary,
  }) async {
    final trimmed = userText.trim();
    if (containsCredentialValue(trimmed)) {
      return ChatMessage(
          role: ChatRole.assistant,
          text: credentialInputNoticePl,
          kind: AiReplyKind.localDialogue);
    }
    if (trimmed.isEmpty) {
      return ChatMessage(
        role: ChatRole.assistant,
        text: 'Napisz pytanie — np. "Jaki preheat dla P91?".',
      );
    }

    if (!kAiBackendAvailable) {
      // Simulated latency so the typing indicator feels real.
      await Future<void>.delayed(const Duration(milliseconds: 700));
      return _demoReply(trimmed);
    }

    // Live mode (Phase 5b): POST conversation to Railway backend, which
    // proxies Anthropic Claude Haiku 4.5 with retrieval over the bundled
    // piping_knowledge.md (270 KB, 100 iteracji). Server is responsible for
    // holding the Anthropic API key, doing the embeddings retrieval, and
    // returning a structured response including citations.
    final url = Uri.parse('${BackendConfig.baseUrl}${BackendConfig.aiChat}');
    try {
      // Asystent to płatna funkcja: nowy backend wymaga device_id + sekretu
      // instalacji (tryb strict) i aktywnego Premium.
      final identity = await PremiumService.instance.authHeaders();
      final profile = await AiProfessionalContext.instance.capture();
      final resp = await http
          .post(
            url,
            headers: {
              'Content-Type': 'application/json',
              ...identity,
              ...profile.headers,
            },
            body: jsonEncode({
              ...profile.body,
              'message': trimmed,
              if (isoSummary != null) 'iso_summary': isoSummary.toJson(),
              'history': chatHistoryForRequest(history)
                  .map((m) => {
                        'role': m.role.name,
                        'text': m.text,
                      })
                  .toList(),
              // Bieżący język interfejsu — backend przyjmuje 'pl' albo 'en'.
              'lang': AppLanguageController.current.name,
              'device_id': PremiumService.instance.deviceId,
            }),
          )
          .timeout(const Duration(seconds: 25));
      profile.requireCurrent();
      if (resp.statusCode != 200) {
        debugPrint('AiChatService: backend ${resp.statusCode}');
        final failure = AiFailure.fromHttp(resp.statusCode, resp.bodyBytes);
        switch (resp.statusCode) {
          // Limity i płatność to NIE awaria — mówimy wprost, co się stało i
          // co dalej, zamiast udawać odpowiedź.
          case 402:
            return _notice(AiReplyKind.premiumRequired);
          case 429:
            return _notice(AiReplyKind.dailyLimit);
          case 503:
            return ChatMessage(
                role: ChatRole.assistant,
                text: failure.message(AppLanguageController.current),
                kind: AiReplyKind.unavailable);
        }
        // 401 (brak/zły sekret instalacji), 404 (stary backend bez trasy),
        // inne 4xx/5xx → pomoc offline z aplikacji.
        final help = offlineReply(trimmed);
        return ChatMessage(
            role: ChatRole.assistant,
            text:
                '${failure.message(AppLanguageController.current)}\n\n${help.text}',
            citations: help.citations,
            kind: AiReplyKind.offlineHelp);
      }
      final body =
          jsonDecode(utf8.decode(resp.bodyBytes)) as Map<String, dynamic>;
      if (isoSummary != null && body['iso_summary_used'] != true) {
        return ChatMessage(
            role: ChatRole.assistant,
            text: AppLanguageController.isEnglish
                ? 'The server has not confirmed ISO drawing context support. Update the backend or use the native drawing summary.'
                : 'Serwer nie potwierdził obsługi kontekstu rysunku ISO. Zaktualizuj backend lub użyj podsumowania rysunku w aplikacji.',
            kind: AiReplyKind.unavailable);
      }
      final text = body['text'] as String? ?? '(empty response)';
      final cites =
          (body['citations'] as List?)?.map((c) => c.toString()).toList() ??
              const <String>[];
      return ChatMessage(
        role: ChatRole.assistant,
        text: text,
        citations: cites,
        kind: AiReplyKind.live,
      );
    } catch (e) {
      // Network down, timeout, TLS failure, etc. — pomoc offline, żeby monter
      // dostał coś użytecznego zamiast czerwonego wyjątku.
      debugPrint('AiChatService offline: $e');
      return offlineReply(trimmed);
    }
  }

  ChatMessage _notice(AiReplyKind kind) {
    final en = AppLanguageController.isEnglish;
    final text = switch (kind) {
      AiReplyKind.premiumRequired => en
          ? 'AI answers are currently a Premium feature. The "Do it" mode, '
              'calculators and in-app help stay free.'
          : 'Odpowiedzi AI są teraz dostępne w Premium. Tryb „Wykonaj", '
              'kalkulatory i pomoc w aplikacji działają bez opłat.',
      AiReplyKind.dailyLimit => en
          ? 'Daily question limit reached — try again tomorrow. The "Do it" '
              'mode keeps working offline.'
          : 'Dzienny limit pytań wyczerpany — jutro znowu. Tryb „Wykonaj" '
              'działa dalej, także bez internetu.',
      _ => en
          ? 'The assistant is temporarily unavailable. Try again later.'
          : 'Asystent chwilowo niedostępny. Spróbuj ponownie później.',
    };
    return ChatMessage(role: ChatRole.assistant, text: text, kind: kind);
  }

  /// Odpowiedź bez serwera: najlepiej pasujący wpis z pomocy w aplikacji
  /// (help_entries.dart), wyraźnie opisany jako pomoc offline, nie AI.
  ChatMessage offlineReply(String userText) {
    final lang = AppLanguageController.current;
    final en = lang == AppLanguage.en;
    final prefix = en
        ? '(Offline mode — in-app help, not an AI answer.)'
        : '(Tryb offline — pomoc z aplikacji, nie odpowiedź AI.)';
    final hits = searchHelp(userText, lang, limit: 1);
    if (hits.isEmpty) {
      return ChatMessage(
        role: ChatRole.assistant,
        kind: AiReplyKind.offlineHelp,
        text: '$prefix\n\n${en ? 'I found nothing on this in the offline help. '
            'Ask again when you are online, or open Help (?) on the home screen.' : 'Nie znalazłem tego w pomocy offline. '
            'Zapytaj ponownie, gdy będzie internet, albo otwórz Pomoc (?) na ekranie głównym.'}',
      );
    }
    final hit = hits.first;
    return ChatMessage(
      role: ChatRole.assistant,
      kind: AiReplyKind.offlineHelp,
      text:
          '$prefix\n\n${hit.entry.question(lang)}\n\n${hit.entry.answer(lang)}',
      citations: [hit.category.title(lang)],
    );
  }

  /// Odpowiedzi trybu demo (backend wyłączony flagą) — do testów.
  @visibleForTesting
  ChatMessage demoReplyForTest(String userText) => _demoReply(userText);

  // ── Demo replies ────────────────────────────────────────────────────────
  ChatMessage _demoReply(String userText) {
    final lower = userText.toLowerCase();
    String reply;
    List<String> citations = const [];

    // Deliberately small library — just enough to demo the UX. The full
    // retrieval-augmented model arrives in Phase 5b.
    if (lower.contains('preheat') && lower.contains('p91')) {
      // P1-37: dual units — temp °C/°F, PWHT hold time per mm + per inch wall.
      reply =
          'P91 preheat 200-300°C / 390-570°F (wymagany), interpass ≤350°C / ≤660°F, '
          'PWHT wg B31.3 (2014+): 705-775°C / 1300-1425°F (projekty często zawężają do 730-760°C), '
          '1 h na 25 mm ścianki, min. 30 min — plan cyklu w „Obróbka cieplna po spawaniu”. '
          'Filler: ER90S-B9 / E9015-B9 (low-H). NIE używać B3 filler — creep mismatch. '
          'Pełen tekst: Iteration 75 w bazie wiedzy.';
      citations = ['Iteration 75 — P91/P22 alloy welding'];
    } else if (lower.contains('nace') ||
        lower.contains('mr0175') ||
        lower.contains('sour')) {
      // P1-37: split hardness limits — HRC is the base-metal cap, HV10 the
      // weld+HAZ cap (NOT a unit conversion of HRC, two independent rules).
      reply =
          'NACE MR0175 / ISO 15156: H₂S threshold 0.05 psi (0.3 kPa / 0.0035 bar). Wymóg:\n'
          '• Hardness — CS base metal ≤22 HRC; weld metal + HAZ ≤250 HV10 (osobne limity, nie konwersja)\n'
          '• Ni ≤1% w CS, PWHT mandatory (kontrola twardości po PWHT)\n'
          '• Bolts: B7M/L7M (nigdy B7 lub B16)\n'
          '• HIC-tested plate per TM0284 (płyta ≥ 12.7 mm / 0.5 in)';
      citations = ['Iteration 91 — NACE MR0175 sour service'];
    } else if (lower.contains('torque') || lower.contains('moment')) {
      // P1-37: dual-unit torque (N·m + lbf·ft), dual diameter (mm + in),
      // SMYS preload spelled out in MPa + ksi.
      reply =
          'Moment śrub flange (ASME PCC-1): T = K × F × d  →  T [N·m] = K × F [N] × d [m]  /  T [lbf·ft] = K × F [lbf] × d [in] / 12.\n'
          '• K = 0.20 (sucha), 0.16 (Cu paste), 0.13 (Ni paste)\n'
          '• F = preload 50-75% SMYS (B7 stud SMYS ≈ 105 ksi / 725 MPa → preload target ≈ 52-79 ksi / 360-545 MPa na rdzeniu)\n'
          '• d = nominalna średnica śruby (np. 1 in = 25.4 mm, 1.25 in = 31.75 mm)\n'
          '• Kolejność: 25/50/75/100% w gwiazdę + final circular pass + relaxation po 20min-4h.\n'
          'Konwersja szybka: 1 N·m ≈ 0.738 lbf·ft, 1 lbf·ft ≈ 1.356 N·m.\n'
          'Użyj kalkulatora "Moment śrub" w menu MONTER dla dokładnych wartości.';
      citations = ['Iteration 83 — Hot bolting + ASME PCC-1'];
    } else if (lower.contains('coping') ||
        lower.contains('saddle') ||
        lower.contains('fish')) {
      // P1-37: units gloss — all radii & ODs in mm (in), owijka length dual.
      reply = 'Saddle cut (fish-mouth):\n'
          '• Branch ≤ header OD, kąt 15-90° (standard 90°)\n'
          '• d(φ) [mm | in] = R_h − √(R_h² − R_b²·sin²(φ))   (wszystko w tej samej jednostce — mm lub in)\n'
          '• R_h, R_b = promienie header/branch (np. NPS 4 Sch40: OD 114.3 mm / 4.500 in → R = 57.15 mm / 2.250 in)\n'
          '• Owijka = π × D_branch  (np. D=114.3 mm / 4.500 in → owijka ≈ 359.1 mm / 14.14 in)\n'
          'Otwórz "Szablon siodła do druku" w menu MONTER — wygeneruje PDF 1:1 do druku (skala 1 mm = 1 mm, 1 in = 1 in).';
      citations = ['Narzędzie: Szablon siodła do druku (menu MONTER)'];
    } else if (lower.contains('purge') || lower.contains('argon')) {
      // P1-37: standardise to slpm (bracketed scfh), dual temp on trailing shield.
      reply =
          'Back purge SS: 3-5 wymian objętości rury między dams, target O₂ <0.1% '
          '(<50 ppm dla Ti, <20 ppm dla Zr). Argon 99.995% welding grade, flow 8-15 slpm [≈17-32 scfh].\n'
          'Trailing shield obowiązkowy dla all-position pipe — weld cools >200°C / >390°F przez sekundy po przejściu palnika.\n'
          'Konwersja: 1 slpm ≈ 2.12 scfh; 1 scfh ≈ 0.472 slpm.';
      citations = [
        'Iteration 83 — SS back-purge dams',
        'Iteration 91 — Ti/Zr welding'
      ];
    } else if (lower.contains('hi') ||
        lower.contains('heat input') ||
        lower.contains('kj')) {
      // P1-37: spell out units in the formula + dual P91 ceiling (kJ/mm + kJ/in).
      reply =
          'Heat input: HI [kJ/mm] = (V [V] × I [A] × 60) / (travel [mm/min] × 1000) × η.\n'
          '• Travel in mm/min → HI in kJ/mm. Dla travel w in/min pomnóż najpierw × 25.4 (lub HI [kJ/in] = HI [kJ/mm] × 25.4).\n'
          '• η = 0.80 (SMAW/GMAW/FCAW), 0.60 (GTAW), 0.90 (SAW)\n'
          '• P91 WPS range: 1.0-2.5 kJ/mm (≈ 25-64 kJ/in) — NIE przekraczaj górnej granicy\n'
          'Za wysokie HI = coarse-grain HAZ, niska udarność. Za niskie HI = szybkie chłodzenie, hydrogen cracking.\n'
          'Pełny kalkulator: "Heat input i CE" w menu SPAWACZ.';
      citations = ['Narzędzie: Heat input i CE (menu SPAWACZ)'];
    } else {
      // P1-37: catch-all reply also flags dual units so the welder knows
      // every answer below comes with mm/in + °C/°F + kJ/mm/kJ/in mirrored.
      reply =
          '(Tryb demo — wkrótce podłączamy Claude Haiku 4.5 z RAG ponad bazą wiedzy 270 KB. '
          'Wszystkie odpowiedzi liczbowe podawane są w jednostkach metrycznych ORAZ imperialnych — '
          'mm + in, °C + °F, kJ/mm + kJ/in, N·m + lbf·ft.)\n\n'
          'Spróbuj zapytań typu:\n'
          '• "Jaki preheat dla P91?"  (zwraca °C i °F)\n'
          '• "Co to NACE MR0175?"\n'
          '• "Moment śrub dla flange 4 cale / 4 in class 300"  (zwraca N·m i lbf·ft)\n'
          '• "Jak zrobić saddle cut?"  (wymiary mm i in)\n'
          '• "Czas back purge dla SS DN100 / NPS 4"';
    }

    return ChatMessage(
      role: ChatRole.assistant,
      text: reply,
      citations: citations,
    );
  }
}
