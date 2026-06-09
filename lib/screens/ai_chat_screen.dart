import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../i18n/app_language.dart';
import '../services/ai_chat_service.dart';
import '../services/premium_service.dart';
import '../widgets/premium_gate.dart';

// AI Chat screen — Premium feature wrapped in PremiumGate. Live against
// Claude Haiku 4.5 via /api/fitter/ai/chat with keyword-retrieval RAG
// over data/piping_knowledge.md (270 KB curated standards). The screen
// itself is dumb pipe: it owns the message list, scroll behaviour and the
// typing indicator; AiChatService handles everything network/model-side.

const _kBg = Color(0xFF0F1117);
const _kCard = Color(0xFF1A1D26);
const _kBorder = Color(0xFF2C3354);
const _kAccent = Color(0xFFE8C14B);
const _kAccentBlue = Color(0xFF4A9EFF);
const _kTextSec = Color(0xFF9BA3C7);
const _kTextMut = Color(0xFF55607A);
const _kTextPrimary = Color(0xFFE8ECF0);

// P1-20: cache the alpha-modulated palette derivatives as top-level const so
// each rebuild (and every message bubble repaint) re-uses the same Color
// objects instead of recomputing `withValues(alpha: ...)` per frame.
const _kAccentSoft = Color(0x26E8C14B); // ~0.15 alpha — assistant avatar
const _kAccentChipFill = Color(0x1AE8C14B); // ~0.10 alpha — citation chip fill
const _kAccentChipBorder = Color(0x40E8C14B); // ~0.25 alpha — citation chip border
const _kAccentDot = Color(0xB3E8C14B); // ~0.70 alpha — typing dot
const _kBlueSoft = Color(0x264A9EFF); // ~0.15 alpha — user avatar
const _kBlueBubble = Color(0x2E4A9EFF); // ~0.18 alpha — user bubble fill
const _kBlueBubbleBorder = Color(0x4D4A9EFF); // ~0.30 alpha — user bubble border

// P1-20: hoist message TextStyles to top-level const so every bubble shares
// the same StyleSpan; saves an allocation per rebuild and lets the engine
// short-circuit text-layout equality checks.
const _kMessageTextStyle = TextStyle(
  color: _kTextPrimary,
  fontSize: 15,
  fontWeight: FontWeight.w500,
  height: 1.5,
);
const _kCitationTextStyle = TextStyle(
  fontSize: 12,
  color: _kTextSec,
  fontWeight: FontWeight.w600,
);

class AiChatScreen extends StatelessWidget {
  const AiChatScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return PremiumGate(
      featureName: context.tr(pl: 'AI Asystent', en: 'AI Assistant'),
      child: const _AiChatBody(),
    );
  }
}

class _AiChatBody extends StatefulWidget {
  const _AiChatBody();

  @override
  State<_AiChatBody> createState() => _AiChatBodyState();
}

class _AiChatBodyState extends State<_AiChatBody> {
  final _inputCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  final _focus = FocusNode();
  final _messages = <ChatMessage>[];
  // P1-20: hoist the typing flag to a ValueNotifier so the typing-indicator
  // toggle only repaints the ListView footer (via ValueListenableBuilder)
  // instead of the entire body Column. Send-button enabled state listens to
  // the same notifier.
  final ValueNotifier<bool> _typing = ValueNotifier<bool>(false);

  // P1-36: welcome message is locale-aware. We can't reach context.tr from
  // initState, so seed lazily on the first didChangeDependencies (and re-seed
  // if the user toggles language while the welcome is still the only message
  // on screen — auditor and welder must see the same language in a snapshot).
  bool _welcomeSeeded = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // First-paint seed: nothing in the thread yet.
    if (!_welcomeSeeded) {
      _welcomeSeeded = true;
      _messages.add(_buildWelcomeMessage(context));
      return;
    }
    // Locale flipped while the welcome is still the only thing on screen —
    // re-render it in the new language. We do NOT touch real conversation
    // once the user has sent anything, to preserve auditability.
    if (_messages.length == 1 && _messages.first.role == ChatRole.assistant) {
      final next = _buildWelcomeMessage(context);
      if (next.text != _messages.first.text) {
        setState(() {
          _messages[0] = next;
        });
      }
    }
  }

  // P1-36: PL/EN welcome text per backlog hint. The full text retains the
  // existing tone (Claude Haiku 4.5 + 270 KB knowledge base + citation tap),
  // with the trigger headline localised exactly as the backlog calls out.
  ChatMessage _buildWelcomeMessage(BuildContext ctx) {
    final headline = ctx.tr(
      pl: 'Cześć — zapytaj o spawanie / fit-up',
      en: 'Hi — ask me about welding / fit-up',
    );
    final body = ctx.tr(
      pl: 'Jestem AI asystentem od piping + welding (Claude Haiku 4.5).\n\n'
          'Pytaj o WPS, preheat, NACE, ASME, NDT, kalkulacje — odpowiadam z bazy 270 KB '
          'skondensowanej wiedzy z prawdziwych norm.\n\n'
          'Cytuję sekcję z której pochodzi odpowiedź — kliknij, by zobaczyć kontekst.',
      en: "I'm the AI assistant for piping + welding (Claude Haiku 4.5).\n\n"
          'Ask about WPS, preheat, NACE, ASME, NDT, calculations — I answer from a 270 KB '
          'condensed library of real standards.\n\n'
          'Each reply cites the source section — tap to see the context.',
    );
    return ChatMessage(
      role: ChatRole.assistant,
      text: '$headline\n\n$body',
    );
  }

  @override
  void dispose() {
    _inputCtrl.dispose();
    _scrollCtrl.dispose();
    _focus.dispose();
    _typing.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _inputCtrl.text.trim();
    if (text.isEmpty || _typing.value) return;

    setState(() {
      _messages.add(ChatMessage(role: ChatRole.user, text: text));
      _inputCtrl.clear();
    });
    _typing.value = true;
    _scrollToBottom();

    try {
      final reply = await AiChatService.instance.sendMessage(text, history: _messages);
      if (!mounted) return;
      setState(() {
        _messages.add(reply);
      });
      _typing.value = false;
      _scrollToBottom();
    } catch (e) {
      // The previous build silently left `_typing = true` on any backend
      // hiccup — the typing indicator just spun forever. Surface a clear
      // failure bubble + a SnackBar Retry action that re-runs the same
      // question (user no longer has to retype it).
      debugPrint('AiChatScreen.send error: $e');
      if (!mounted) return;
      setState(() {
        _messages.add(ChatMessage(
          role: ChatRole.assistant,
          text: context.language == AppLanguage.pl
              ? '⚠️ Nie udało się pobrać odpowiedzi. Sprawdź połączenie i spróbuj ponownie.'
              : "⚠️ Couldn't fetch a reply. Check your connection and try again.",
        ));
      });
      _typing.value = false;
      _scrollToBottom();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(context.tr(
          pl: 'Połączenie z AI nie powiodło się.',
          en: 'AI connection failed.',
        )),
        duration: const Duration(seconds: 6),
        behavior: SnackBarBehavior.floating,
        backgroundColor: _kCard,
        action: SnackBarAction(
          label: context.tr(pl: 'Ponów', en: 'Retry'),
          textColor: _kAccent,
          onPressed: () {
            _inputCtrl.text = text;
            _send();
          },
        ),
      ));
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollCtrl.hasClients) return;
      _scrollCtrl.animateTo(
        _scrollCtrl.position.maxScrollExtent,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
    });
  }

  void _useSuggestion(String s) {
    _inputCtrl.text = s;
    _focus.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kBg,
      appBar: AppBar(
        backgroundColor: _kCard,
        title: Row(
          children: [
            const Icon(Icons.smart_toy_outlined, color: _kAccent, size: 20),
            const SizedBox(width: 8),
            Text(context.tr(pl: 'AI Asystent', en: 'AI Assistant')),
            const SizedBox(width: 8),
            if (!kAiBackendAvailable)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  // P1-20: const colors instead of per-build `withValues`.
                  color: _kBlueSoft,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: _kBlueBubbleBorder),
                ),
                child: Text(
                  context.tr(pl: 'DEMO', en: 'DEMO'),
                  style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w900,
                    color: _kAccentBlue,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_sweep_outlined, color: _kTextSec),
            tooltip: context.tr(pl: 'Wyczyść rozmowę', en: 'Clear chat'),
            onPressed: () async {
              // P1-05: only prompt when there's something to lose (more than
              // the seeded welcome message). Refresh→delete_sweep swap makes
              // the icon semantics match destruction (was "reload" everywhere
              // else in the app).
              if (_messages.length > 1) {
                final confirmed = await showDialog<bool>(
                  context: context,
                  builder: (dctx) => AlertDialog(
                    backgroundColor: _kCard,
                    title: Text(
                      context.tr(
                        pl: 'Wyczyścić rozmowę?',
                        en: 'Clear chat?',
                      ),
                      style: const TextStyle(color: Color(0xFFE8ECF0)),
                    ),
                    content: Text(
                      context.tr(
                        pl: 'Wszystkie wiadomości w tym wątku zostaną usunięte. Tej operacji nie można cofnąć.',
                        en: 'All messages in this thread will be deleted. This cannot be undone.',
                      ),
                      style: const TextStyle(color: _kTextSec),
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(dctx, false),
                        child: Text(context.tr(pl: 'Anuluj', en: 'Cancel')),
                      ),
                      TextButton(
                        onPressed: () => Navigator.pop(dctx, true),
                        child: Text(
                          context.tr(pl: 'Wyczyść', en: 'Clear'),
                          style: const TextStyle(color: _kAccent),
                        ),
                      ),
                    ],
                  ),
                );
                if (confirmed != true) return;
                if (!mounted) return;
              }
              setState(() {
                _messages.clear();
                // P1-36: re-seed with the same locale-aware welcome the
                // initial paint uses, so both code paths render identical
                // copy in the user's current language.
                _messages.add(_buildWelcomeMessage(context));
              });
            },
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              // P1-20: rebuilds the list only when `_typing` flips so the
              // surrounding Scaffold / AppBar / SafeArea stay still. The
              // composer below listens to the same notifier independently.
              child: ValueListenableBuilder<bool>(
                valueListenable: _typing,
                builder: (context, typing, _) {
                  // P1-36: surface a DEMO chip on the welcome bubble while
                  // the user is on the free plan — telegraphs the upsell
                  // without nagging copy. The chip disappears as soon as
                  // the welder sends anything (`_messages.length > 1`) so
                  // it never interrupts a real conversation.
                  final showDemoOnWelcome = _messages.length == 1 &&
                      !PremiumService.instance.isPremium;
                  return ListView.builder(
                    controller: _scrollCtrl,
                    padding: const EdgeInsets.fromLTRB(12, 12, 12, 16),
                    itemCount: _messages.length + (typing ? 1 : 0),
                    itemBuilder: (context, i) {
                      if (i == _messages.length && typing) {
                        return const RepaintBoundary(child: _TypingIndicator());
                      }
                      final msg = _messages[i];
                      // P1-20: stable ValueKey on the bubble lets the
                      // ListView short-circuit element diff/rebuild when
                      // the list grows by one. RepaintBoundary isolates the
                      // bubble's paint to its own layer so a new bubble
                      // doesn't repaint the entire scroll viewport.
                      return RepaintBoundary(
                        key: ValueKey<int>(i),
                        child: _MessageBubble(
                          message: msg,
                          showDemoChip: i == 0 && showDemoOnWelcome,
                        ),
                      );
                    },
                  );
                },
              ),
            ),
            if (_messages.length <= 1) _SuggestionStrip(onPick: _useSuggestion),
            // P1-20: composer is its own repaint layer; the only thing it
            // depends on is the `_typing` notifier (controls enabled state).
            RepaintBoundary(
              child: ValueListenableBuilder<bool>(
                valueListenable: _typing,
                builder: (context, typing, _) {
                  return _Composer(
                    controller: _inputCtrl,
                    focusNode: _focus,
                    onSend: _send,
                    enabled: !typing,
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Message bubble
/// Opens a small read-only dialog with the citation tag (e.g. "Iteration 27 §C").
/// Today this just surfaces what the model returned in `citations`; once the
/// knowledge base is exposed via an endpoint we can replace the dialog body
/// with the actual section text without touching the call sites.
void _showCitation(BuildContext context, String citation) {
  final cs = Theme.of(context).colorScheme;
  showDialog<void>(
    context: context,
    builder: (dctx) => AlertDialog(
      backgroundColor: const Color(0xFF1A1D26),
      title: Row(
        children: [
          const Text('📖  ', style: TextStyle(fontSize: 18)),
          Expanded(
            child: Text(
              citation,
              style: TextStyle(
                color: cs.primary,
                fontSize: 14,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
      content: Text(
        context.tr(
          pl: 'Cytat wskazuje sekcję z bazy wiedzy (data/piping_knowledge.md), '
              'którą AI wykorzystała do udzielenia odpowiedzi. '
              'Pełny tekst sekcji udostępnimy w kolejnej wersji.',
          en: 'The citation points to the knowledge-base section '
              '(data/piping_knowledge.md) that grounded this answer. '
              'Full section text will be browsable in a future build.',
        ),
        style: const TextStyle(
          fontSize: 12,
          color: Color(0xFFE8ECF0),
          height: 1.5,
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dctx),
          child: Text(context.tr(pl: 'OK', en: 'OK')),
        ),
      ],
    ),
  );
}

// ═══════════════════════════════════════════════════════════════════════════
class _MessageBubble extends StatelessWidget {
  final ChatMessage message;
  // P1-36: when true, render a small DEMO chip inside the welcome bubble so
  // the welder sees they're on the free plan without a separate banner.
  final bool showDemoChip;
  const _MessageBubble({
    required this.message,
    this.showDemoChip = false,
  });

  @override
  Widget build(BuildContext context) {
    final isUser = message.role == ChatRole.user;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        children: [
          if (!isUser)
            Container(
              width: 32,
              height: 32,
              decoration: const BoxDecoration(
                color: _kAccentSoft,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.smart_toy_outlined,
                  color: _kAccent, size: 18),
            ),
          if (!isUser) const SizedBox(width: 8),
          Flexible(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: isUser ? _kBlueBubble : _kCard,
                borderRadius: BorderRadius.circular(14).copyWith(
                  topLeft: Radius.circular(isUser ? 14 : 4),
                  topRight: Radius.circular(isUser ? 4 : 14),
                ),
                border: Border.all(
                  color: isUser ? _kBlueBubbleBorder : _kBorder,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // P1-20: hoisted top-level const TextStyle — shared across
                  // every bubble so the engine can short-circuit equality.
                  SelectableText(
                    message.text,
                    style: _kMessageTextStyle,
                  ),
                  if (showDemoChip) ...[
                    const SizedBox(height: 8),
                    const _DemoBadge(),
                  ],
                  if (message.citations.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 4,
                      runSpacing: 4,
                      children: message.citations
                          .map((c) => InkWell(
                                onTap: () => _showCitation(context, c),
                                borderRadius: BorderRadius.circular(6),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 3),
                                  decoration: BoxDecoration(
                                    color: _kAccentChipFill,
                                    borderRadius: BorderRadius.circular(6),
                                    border: Border.all(
                                      color: _kAccentChipBorder,
                                      width: 0.6,
                                    ),
                                  ),
                                  child: Text(
                                    '📖 $c',
                                    style: _kCitationTextStyle,
                                  ),
                                ),
                              ))
                          .toList(),
                    ),
                  ],
                ],
              ),
            ),
          ),
          if (isUser) const SizedBox(width: 8),
          if (isUser)
            Container(
              width: 32,
              height: 32,
              decoration: const BoxDecoration(
                color: _kBlueSoft,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.person_outline,
                  color: _kAccentBlue, size: 18),
            ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// P1-36: small inline DEMO badge rendered on the welcome bubble when the
// user is on the free plan. Sized to remain glance-readable in sunlight but
// not steal the eye from the welcome copy itself.
// ═══════════════════════════════════════════════════════════════════════════
class _DemoBadge extends StatelessWidget {
  const _DemoBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: _kAccentChipFill,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: _kAccentChipBorder, width: 0.6),
      ),
      child: Text(
        context.tr(
          pl: 'DEMO · tryb darmowy',
          en: 'DEMO · free tier',
        ),
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w800,
          color: _kAccent,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Typing indicator (3 pulsing dots)
// ═══════════════════════════════════════════════════════════════════════════
class _TypingIndicator extends StatefulWidget {
  const _TypingIndicator();

  @override
  State<_TypingIndicator> createState() => _TypingIndicatorState();
}

class _TypingIndicatorState extends State<_TypingIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctl;
  @override
  void initState() {
    super.initState();
    _ctl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat();
  }

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: const BoxDecoration(
              color: _kAccentSoft,
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.smart_toy_outlined,
                color: _kAccent, size: 18),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            decoration: BoxDecoration(
              color: _kCard,
              borderRadius: BorderRadius.circular(14).copyWith(topLeft: Radius.circular(4)),
              border: Border.all(color: _kBorder),
            ),
            child: AnimatedBuilder(
              animation: _ctl,
              builder: (_, __) {
                return Row(
                  mainAxisSize: MainAxisSize.min,
                  children: List.generate(3, (i) {
                    final phase = (_ctl.value - i * 0.2) % 1.0;
                    final scale = phase < 0.5 ? 1.0 + phase : 1.5 - phase;
                    return Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 2),
                      child: Transform.scale(
                        scale: scale,
                        // P1-20: const color (hoisted) instead of per-frame
                        // `withValues(alpha:)` allocation.
                        child: Container(
                          width: 6,
                          height: 6,
                          decoration: const BoxDecoration(
                            color: _kAccentDot,
                            shape: BoxShape.circle,
                          ),
                        ),
                      ),
                    );
                  }),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Suggested prompts (shown only when conversation is empty)
// ═══════════════════════════════════════════════════════════════════════════
class _SuggestionStrip extends StatelessWidget {
  final void Function(String) onPick;
  const _SuggestionStrip({required this.onPick});

  @override
  Widget build(BuildContext context) {
    final suggestions = [
      context.tr(pl: 'Jaki preheat dla P91?', en: 'What preheat for P91?'),
      context.tr(pl: 'Co to NACE MR0175?', en: 'What is NACE MR0175?'),
      context.tr(pl: 'Heat input dla SMAW 110A', en: 'Heat input for SMAW 110A'),
      context.tr(pl: 'Moment śrub flange 4" Class 300', en: 'Bolt torque 4" Class 300 flange'),
      context.tr(pl: 'Jak zrobić saddle cut?', en: 'How to do a saddle cut?'),
    ];
    // Glove-friendly: strip height + chip vertical padding bumped so each
     // suggestion chip exposes a >=48dp tap target (was ~38dp, missed gloved
     // fingertips). Horizontal padding also raised slightly for the same reason.
     return SizedBox(
      height: 64,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        itemCount: suggestions.length,
        itemBuilder: (context, i) {
          // P1-07 + P1-09: Material+InkWell ripple (was bare GestureDetector),
          // haptic selectionClick on tap, vertical padding bumped to 14dp and
          // font to 14pt for gloved-fingertip readability.
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Material(
              color: _kCard,
              borderRadius: BorderRadius.circular(24),
              child: InkWell(
                borderRadius: BorderRadius.circular(24),
                onTap: () {
                  HapticFeedback.selectionClick();
                  onPick(suggestions[i]);
                },
                child: Container(
                  constraints: const BoxConstraints(minHeight: 48),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 14),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: _kBorder),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    suggestions[i],
                    style: const TextStyle(fontSize: 14, color: _kTextSec),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Composer (text input + send button)
// ═══════════════════════════════════════════════════════════════════════════
class _Composer extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final VoidCallback onSend;
  final bool enabled;
  const _Composer({
    required this.controller,
    required this.focusNode,
    required this.onSend,
    required this.enabled,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      decoration: BoxDecoration(
        color: _kCard,
        border: Border(top: BorderSide(color: _kBorder)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: TextField(
              controller: controller,
              focusNode: focusNode,
              enabled: enabled,
              minLines: 1,
              maxLines: 4,
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => onSend(),
              style: const TextStyle(color: Color(0xFFE8ECF0), fontSize: 14),
              decoration: InputDecoration(
                hintText: context.tr(
                  pl: 'Zapytaj o WPS, preheat, NACE…',
                  en: 'Ask about WPS, preheat, NACE…',
                ),
                hintStyle: const TextStyle(color: _kTextMut, fontSize: 15),
                filled: true,
                fillColor: _kBg,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(22),
                  borderSide: BorderSide(color: _kBorder),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(22),
                  borderSide: BorderSide(color: _kBorder),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(22),
                  borderSide: BorderSide(color: _kAccent, width: 1.2),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Container(
            decoration: BoxDecoration(
              color: enabled ? _kAccent : _kBorder,
              shape: BoxShape.circle,
            ),
            child: IconButton(
              icon: const Icon(Icons.send_rounded),
              color: Colors.black,
              iconSize: 28,
              constraints: const BoxConstraints(minWidth: 56, minHeight: 56),
              onPressed: enabled ? onSend : null,
            ),
          ),
        ],
      ),
    );
  }
}
