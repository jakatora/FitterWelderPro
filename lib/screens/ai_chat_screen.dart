// ignore_for_file: prefer_const_constructors

import 'package:flutter/material.dart';

import '../i18n/app_language.dart';
import '../services/ai_chat_service.dart';
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
  bool _typing = false;

  @override
  void initState() {
    super.initState();
    // Welcome message — seeded into the conversation so the UI never looks
    // empty. Stored as an assistant message so the styling matches.
    _messages.add(ChatMessage(
      role: ChatRole.assistant,
      text:
          'Cześć! 👋 Jestem AI asystentem od piping + welding (Claude Haiku 4.5).\n\n'
          'Pytaj o WPS, preheat, NACE, ASME, NDT, kalkulacje — odpowiadam z bazy 270 KB '
          'skondensowanej wiedzy z prawdziwych norm.\n\n'
          'Cytuję sekcję z której pochodzi odpowiedź — kliknij, by zobaczyć kontekst.',
    ));
  }

  @override
  void dispose() {
    _inputCtrl.dispose();
    _scrollCtrl.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _inputCtrl.text.trim();
    if (text.isEmpty || _typing) return;

    setState(() {
      _messages.add(ChatMessage(role: ChatRole.user, text: text));
      _typing = true;
      _inputCtrl.clear();
    });
    _scrollToBottom();

    try {
      final reply = await AiChatService.instance.sendMessage(text, history: _messages);
      if (!mounted) return;
      setState(() {
        _messages.add(reply);
        _typing = false;
      });
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
        _typing = false;
      });
      _scrollToBottom();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(context.tr(
          pl: 'Połączenie z AI nie powiodło się.',
          en: 'AI connection failed.',
        )),
        duration: const Duration(seconds: 4),
        action: SnackBarAction(
          label: context.tr(pl: 'Ponów', en: 'Retry'),
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
                  color: _kAccentBlue.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: _kAccentBlue.withValues(alpha: 0.3)),
                ),
                child: Text(
                  context.tr(pl: 'DEMO', en: 'DEMO'),
                  style: TextStyle(
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
            icon: const Icon(Icons.refresh, color: _kTextSec),
            tooltip: context.tr(pl: 'Wyczyść rozmowę', en: 'Clear chat'),
            onPressed: () {
              setState(() {
                _messages.clear();
                _messages.add(ChatMessage(
                  role: ChatRole.assistant,
                  text: context.tr(
                    pl: 'Cześć! 👋 Co chcesz wiedzieć?',
                    en: 'Hi! 👋 What can I help with?',
                  ),
                ));
              });
            },
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView.builder(
                controller: _scrollCtrl,
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 16),
                itemCount: _messages.length + (_typing ? 1 : 0),
                itemBuilder: (context, i) {
                  if (i == _messages.length && _typing) {
                    return const _TypingIndicator();
                  }
                  return _MessageBubble(message: _messages[i]);
                },
              ),
            ),
            if (_messages.length <= 1) _SuggestionStrip(onPick: _useSuggestion),
            _Composer(
              controller: _inputCtrl,
              focusNode: _focus,
              onSend: _send,
              enabled: !_typing,
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
  const _MessageBubble({required this.message});

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
              decoration: BoxDecoration(
                color: _kAccent.withValues(alpha: 0.15),
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
                color: isUser
                    ? _kAccentBlue.withValues(alpha: 0.18)
                    : _kCard,
                borderRadius: BorderRadius.circular(14).copyWith(
                  topLeft: Radius.circular(isUser ? 14 : 4),
                  topRight: Radius.circular(isUser ? 4 : 14),
                ),
                border: Border.all(
                  color: isUser ? _kAccentBlue.withValues(alpha: 0.3) : _kBorder,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SelectableText(
                    message.text,
                    style: const TextStyle(
                      color: Color(0xFFE8ECF0),
                      fontSize: 14,
                      height: 1.5,
                    ),
                  ),
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
                                    color: _kAccent.withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(6),
                                    border: Border.all(
                                      color: _kAccent.withValues(alpha: 0.25),
                                      width: 0.6,
                                    ),
                                  ),
                                  child: Text(
                                    '📖 $c',
                                    style: TextStyle(
                                      fontSize: 10,
                                      color: _kAccent,
                                      fontWeight: FontWeight.w600,
                                    ),
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
              decoration: BoxDecoration(
                color: _kAccentBlue.withValues(alpha: 0.15),
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
            decoration: BoxDecoration(
              color: _kAccent.withValues(alpha: 0.15),
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
                        child: Container(
                          width: 6,
                          height: 6,
                          decoration: BoxDecoration(
                            color: _kAccent.withValues(alpha: 0.7),
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
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: GestureDetector(
              onTap: () => onPick(suggestions[i]),
              child: Container(
                constraints: const BoxConstraints(minHeight: 48),
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: _kCard,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: _kBorder),
                ),
                alignment: Alignment.center,
                child: Text(
                  suggestions[i],
                  style: const TextStyle(fontSize: 12, color: _kTextSec),
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
                hintStyle: const TextStyle(color: _kTextMut, fontSize: 13),
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
              onPressed: enabled ? onSend : null,
            ),
          ),
        ],
      ),
    );
  }
}
