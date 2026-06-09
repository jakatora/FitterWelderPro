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

/// P1-37: preferred unit system flag sent with every backend request so the
/// model mirrors dual units (SI + imperial) in its answers. Kept here rather
/// than in BackendConfig until that file grows a setting for it. Acceptable
/// values: 'metric', 'imperial', 'both'.
const String _kPreferredUnitSystem = 'both';

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
    try {
      final resp = await http
          .post(
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
              'lang': 'pl',
              // P1-37: ask the backend model to quote dual units (SI + imperial)
              // in every numeric answer. Default 'both' until BackendConfig
              // grows a preferredUnitSystem setting; values: 'metric', 'imperial',
              // 'both'. The system prompt on the server side reads this field
              // and instructs Claude to mirror temps in °C/°F, lengths in
              // mm/in, heat input in kJ/mm + kJ/in, torque in N·m + lbf·ft.
              'units': _kPreferredUnitSystem,
            }),
          )
          .timeout(const Duration(seconds: 25));
      if (resp.statusCode != 200) {
        // Backend is up but the upstream model call failed (most common cause:
        // Anthropic returned model_not_found for a short-alias model ID like
        // 'claude-haiku-4-5' instead of the dated 'claude-haiku-4-5-20251001').
        // Fall through to the demo library so the fitter still gets a useful
        // answer for common questions instead of a 500 in-app.
        return _fallbackReply(trimmed,
            reason: 'backend ${resp.statusCode}');
      }
      final body =
          jsonDecode(utf8.decode(resp.bodyBytes)) as Map<String, dynamic>;
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
    } catch (e) {
      // Network down, timeout, TLS failure, etc. — same fallback path so the
      // user sees something useful instead of a red exception banner.
      return _fallbackReply(trimmed, reason: 'offline: $e');
    }
  }

  /// Used both for the original "demo" mode (flag off) and as a graceful
  /// fallback when the backend errors out. Prepends a single-line apology
  /// so the user knows we couldn't reach the live model.
  ChatMessage _fallbackReply(String userText, {String? reason}) {
    final demo = _demoReply(userText);
    if (reason == null) return demo;
    return ChatMessage(
      role: demo.role,
      text:
          '(Tryb offline — odpowiedź z lokalnej bazy. Spróbuj ponownie za chwilę.)\n\n'
          '${demo.text}',
      citations: demo.citations,
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
      // P1-37: dual units — temp °C/°F, PWHT hold time per mm + per inch wall.
      reply = 'P91 preheat 200-300°C / 390-570°F (wymagany), interpass ≤350°C / ≤660°F, '
          'PWHT 730-760°C / 1345-1400°F × 2.4 min/mm wall (≈1 h per 25 mm / per inch). '
          'Filler: ER90S-B9 / E9015-B9 (low-H). NIE używać B3 filler — creep mismatch. '
          'Pełen tekst: Iteration 75 w bazie wiedzy.';
      citations = ['Iteration 75 — P91/P22 alloy welding'];
    } else if (lower.contains('nace') ||
        lower.contains('mr0175') ||
        lower.contains('sour')) {
      // P1-37: split hardness limits — HRC is the base-metal cap, HV10 the
      // weld+HAZ cap (NOT a unit conversion of HRC, two independent rules).
      reply = 'NACE MR0175 / ISO 15156: H₂S threshold 0.05 psi (0.3 kPa / 0.0035 bar). Wymóg:\n'
          '• Hardness — CS base metal ≤22 HRC; weld metal + HAZ ≤250 HV10 (osobne limity, nie konwersja)\n'
          '• Ni ≤1% w CS, PWHT mandatory (kontrola twardości po PWHT)\n'
          '• Bolts: B7M/L7M (nigdy B7 lub B16)\n'
          '• HIC-tested plate per TM0284 (płyta ≥ 12.7 mm / 0.5 in)';
      citations = ['Iteration 91 — NACE MR0175 sour service'];
    } else if (lower.contains('torque') || lower.contains('moment')) {
      // P1-37: dual-unit torque (N·m + lbf·ft), dual diameter (mm + in),
      // SMYS preload spelled out in MPa + ksi.
      reply = 'Moment śrub flange (ASME PCC-1): T = K × F × d  →  T [N·m] = K × F [N] × d [m]  /  T [lbf·ft] = K × F [lbf] × d [in] / 12.\n'
          '• K = 0.20 (sucha), 0.16 (Cu paste), 0.13 (Ni paste)\n'
          '• F = preload 50-75% SMYS (B7 stud SMYS ≈ 105 ksi / 725 MPa → preload target ≈ 52-79 ksi / 360-545 MPa na rdzeniu)\n'
          '• d = nominalna średnica śruby (np. 1 in = 25.4 mm, 1.25 in = 31.75 mm)\n'
          '• Kolejność: 25/50/75/100% w gwiazdę + final circular pass + relaxation po 20min-4h.\n'
          'Konwersja szybka: 1 N·m ≈ 0.738 lbf·ft, 1 lbf·ft ≈ 1.356 N·m.\n'
          'Użyj kalkulatora "Moment śrub" w menu FITTER dla dokładnych wartości.';
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
          'Otwórz "Saddle / Coping" w menu FITTER — wygeneruje PDF 1:1 do druku (skala 1 mm = 1 mm, 1 in = 1 in).';
      citations = ['Tool: Saddle / Coping (FITTER menu)'];
    } else if (lower.contains('purge') || lower.contains('argon')) {
      // P1-37: standardise to slpm (bracketed scfh), dual temp on trailing shield.
      reply = 'Back purge SS: 3-5 wymian objętości rury między dams, target O₂ <0.1% '
          '(<50 ppm dla Ti, <20 ppm dla Zr). Argon 99.995% welding grade, flow 8-15 slpm [≈17-32 scfh].\n'
          'Trailing shield obowiązkowy dla all-position pipe — weld cools >200°C / >390°F przez sekundy po przejściu palnika.\n'
          'Konwersja: 1 slpm ≈ 2.12 scfh; 1 scfh ≈ 0.472 slpm.';
      citations = ['Iteration 83 — SS back-purge dams', 'Iteration 91 — Ti/Zr welding'];
    } else if (lower.contains('hi') || lower.contains('heat input') || lower.contains('kj')) {
      // P1-37: spell out units in the formula + dual P91 ceiling (kJ/mm + kJ/in).
      reply = 'Heat input: HI [kJ/mm] = (V [V] × I [A] × 60) / (travel [mm/min] × 1000) × η.\n'
          '• Travel in mm/min → HI in kJ/mm. Dla travel w in/min pomnóż najpierw × 25.4 (lub HI [kJ/in] = HI [kJ/mm] × 25.4).\n'
          '• η = 0.80 (SMAW/GMAW/FCAW), 0.60 (GTAW), 0.90 (SAW)\n'
          '• P91 WPS range: 1.0-2.5 kJ/mm (≈ 25-64 kJ/in) — NIE przekraczaj górnej granicy\n'
          'Za wysokie HI = coarse-grain HAZ, niska udarność. Za niskie HI = szybkie chłodzenie, hydrogen cracking.\n'
          'Pełny kalkulator: "Heat Input + CE" w menu SPAWACZ.';
      citations = ['Tool: Heat Input + CE (WELDER menu)'];
    } else {
      // P1-37: catch-all reply also flags dual units so the welder knows
      // every answer below comes with mm/in + °C/°F + kJ/mm/kJ/in mirrored.
      reply = '(Tryb demo — wkrótce podłączamy Claude Haiku 4.5 z RAG ponad bazą wiedzy 270 KB. '
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
