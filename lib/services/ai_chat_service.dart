import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config/backend_config.dart';

// AI chat service — Premium feature.
//
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

enum ChatRole { user, assistant, system }

class ChatMessage {
  final ChatRole role;
  final String text;
  final DateTime timestamp;

  /// Optional citation list — populated in Phase 5b when retrieval is wired up.
  /// Each entry is the heading of the knowledge-base section the response
  /// drew from (e.g. "Iteration 75 — P91 welding").
  final List<String> citations;

  ChatMessage({
    required this.role,
    required this.text,
    DateTime? timestamp,
    this.citations = const [],
  }) : timestamp = timestamp ?? DateTime.now();
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
  }) async {
    final trimmed = userText.trim();
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
    final url =
        Uri.parse('${BackendConfig.baseUrl}${BackendConfig.aiChat}');
    final resp = await http.post(
      url,
      headers: const {'Content-Type': 'application/json'},
      body: jsonEncode({
        'message': trimmed,
        'history': history
            .map((m) => {
                  'role': m.role.name,
                  'text': m.text,
                })
            .toList(),
        // Server should auth via Bearer token from premium status check, but
        // for now we send a soft identifier; backend can ignore or use it
        // for rate-limiting per device.
        'lang': 'pl',
      }),
    );
    if (resp.statusCode != 200) {
      throw Exception(
          'AI request failed: ${resp.statusCode} ${resp.body}');
    }
    final body = jsonDecode(utf8.decode(resp.bodyBytes)) as Map<String, dynamic>;
    final text = body['text'] as String? ?? '(empty response)';
    final cites = (body['citations'] as List?)
            ?.map((c) => c.toString())
            .toList() ??
        const <String>[];
    return ChatMessage(
      role: ChatRole.assistant,
      text: text,
      citations: cites,
    );
  }

  // ── Demo replies ────────────────────────────────────────────────────────
  ChatMessage _demoReply(String userText) {
    final lower = userText.toLowerCase();
    String reply;
    List<String> citations = const [];

    // Deliberately small library — just enough to demo the UX. The full
    // retrieval-augmented model arrives in Phase 5b.
    if (lower.contains('preheat') && lower.contains('p91')) {
      reply = 'P91 preheat 200-300°C (wymagany), interpass ≤350°C, PWHT 730-760°C × 1h per inch wall. '
          'Filler: ER90S-B9 / E9015-B9 (low-H). NIE używać B3 filler — creep mismatch. '
          'Pełen tekst: Iteration 75 w bazie wiedzy.';
      citations = ['Iteration 75 — P91/P22 alloy welding'];
    } else if (lower.contains('nace') ||
        lower.contains('mr0175') ||
        lower.contains('sour')) {
      reply = 'NACE MR0175 / ISO 15156: H₂S threshold 0.05 psi (0.3 kPa). Wymóg:\n'
          '• Hardness ≤22 HRC (~250 HV10) na CS + welds + HAZ\n'
          '• Ni ≤1% w CS, PWHT mandatory\n'
          '• Bolts: B7M/L7M (nigdy B7 lub B16)\n'
          '• HIC-tested plate per TM0284';
      citations = ['Iteration 91 — NACE MR0175 sour service'];
    } else if (lower.contains('torque') || lower.contains('moment')) {
      reply = 'Moment śrub flange (ASME PCC-1): T = K × F × d.\n'
          '• K = 0.20 (sucha), 0.16 (Cu paste), 0.13 (Ni paste)\n'
          '• F = preload (50-75% SMYS dla typical service)\n'
          '• Kolejność: 25/50/75/100% w gwiazdę + final circular pass + relaxation po 20min-4h.\n'
          'Użyj kalkulatora "Moment śrub" w menu FITTER dla dokładnych wartości.';
      citations = ['Iteration 83 — Hot bolting + ASME PCC-1'];
    } else if (lower.contains('coping') ||
        lower.contains('saddle') ||
        lower.contains('fish')) {
      reply = 'Saddle cut (fish-mouth):\n'
          '• Branch ≤ header OD, kąt 15-90° (standard 90°)\n'
          '• d(φ) = R_h − √(R_h² − R_b²·sin²(φ))\n'
          '• Owijka = π × D_branch\n'
          'Otwórz "Saddle / Coping" w menu FITTER — wygeneruje PDF 1:1 do druku.';
      citations = ['Tool: Saddle / Coping (FITTER menu)'];
    } else if (lower.contains('purge') || lower.contains('argon')) {
      reply = 'Back purge SS: 3-5 wymian objętości rury między dams, target O₂ <0.1% '
          '(<50 ppm dla Ti, <20 ppm dla Zr). Argon 99.995% welding grade, flow 8-15 L/min.\n'
          'Trailing shield obowiązkowy dla all-position pipe — weld cools >200°C przez sekundy po przejściu palnika.';
      citations = ['Iteration 83 — SS back-purge dams', 'Iteration 91 — Ti/Zr welding'];
    } else if (lower.contains('hi') || lower.contains('heat input') || lower.contains('kj')) {
      reply = 'Heat input: HI = (V × I × 60) / (travel × 1000) × η.\n'
          '• η = 0.80 (SMAW/GMAW/FCAW), 0.60 (GTAW), 0.90 (SAW)\n'
          '• P91 WPS range: 1.0-2.5 kJ/mm (NIE przekraczaj)\n'
          'Za wysokie HI = coarse-grain HAZ, niska udarność. Za niskie HI = szybkie chłodzenie, hydrogen cracking.\n'
          'Pełny kalkulator: "Heat Input + CE" w menu SPAWACZ.';
      citations = ['Tool: Heat Input + CE (WELDER menu)'];
    } else {
      reply = '(Tryb demo — wkrótce podłączamy Claude Haiku 4.5 z RAG ponad bazą wiedzy 270 KB.)\n\n'
          'Spróbuj zapytań typu:\n'
          '• "Jaki preheat dla P91?"\n'
          '• "Co to NACE MR0175?"\n'
          '• "Moment śrub dla flange 4 cale class 300"\n'
          '• "Jak zrobić saddle cut?"\n'
          '• "Czas back purge dla SS DN100"';
    }

    return ChatMessage(
      role: ChatRole.assistant,
      text: reply,
      citations: citations,
    );
  }
}
