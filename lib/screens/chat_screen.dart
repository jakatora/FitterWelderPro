import 'dart:async';

import 'package:flutter/material.dart';

import '../config/backend_config.dart';
import '../i18n/app_language.dart';
import '../services/chat_service.dart';
import '../services/premium_service.dart';
import '../utils/haptic.dart';

// Public chat (Fitter Welder Pro). Two-screen flow:
//   1. ChatScreen — list of rooms
//   2. _RoomView  — messages + compose for the selected room
// Polling every 8s while a room is on-screen; on send the message is
// optimistically appended so the user sees immediate feedback even before
// the backend confirms (the next poll will dedup against id).

const _kCard = Color(0xFF1A1D26);
const _kAccent = Color(0xFFAB47BC); // purple accent — distinct from premium gold
const _kBorder = Color(0xFF2C3354);
const _kTextSec = Color(0xFF9BA3C7);
const _kTextMut = Color(0xFF55607A);

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  List<ChatRoom>? _rooms;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadRooms();
  }

  Future<void> _loadRooms() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final rooms = await ChatService.instance.listRooms();
      if (!mounted) return;
      setState(() {
        _rooms = rooms;
        _loading = false;
      });
    } catch (e) {
      debugPrint('ChatScreen.loadRooms error: $e');
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!BackendConfig.chatBackendLive) {
      return _ChatComingSoon();
    }
    return Scaffold(
      backgroundColor: const Color(0xFF0F1117),
      appBar: AppBar(
        backgroundColor: _kCard,
        title: Text(
          context.tr(pl: 'Czat', en: 'Chat'),
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.person_outline),
            tooltip: context.tr(pl: 'Ksywka', en: 'Nickname'),
            onPressed: _editNickname,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? _ErrorRetry(onRetry: _loadRooms)
              : RefreshIndicator(
                  onRefresh: _loadRooms,
                  child: ListView.builder(
                    itemCount: _rooms?.length ?? 0,
                    itemBuilder: (_, i) {
                      final r = _rooms![i];
                      final name = context.language == AppLanguage.pl ? r.namePl : r.nameEn;
                      final desc = context.language == AppLanguage.pl ? r.descPl : r.descEn;
                      return _RoomTile(
                        name: name,
                        desc: desc,
                        onTap: () => _openRoom(r),
                      );
                    },
                  ),
                ),
    );
  }

  Future<void> _openRoom(ChatRoom room) async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => _RoomView(room: room)),
    );
  }

  Future<void> _editNickname() async {
    final current = await ChatService.instance.getNickname();
    if (!mounted) return;
    final ctrl = TextEditingController(text: current);
    try {
      final res = await showDialog<String>(
        context: context,
        builder: (dctx) => AlertDialog(
          title: Text(context.tr(pl: 'Twoja ksywka', en: 'Your nickname')),
          content: TextField(
            controller: ctrl,
            autofocus: true,
            maxLength: 32,
            decoration: InputDecoration(
              hintText: context.tr(pl: 'np. Krzysiek 304L', en: 'e.g. Mike 304L'),
              counterText: '',
            ),
            onSubmitted: (v) => Navigator.pop(dctx, v.trim()),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dctx, null),
              child: Text(context.tr(pl: 'Anuluj', en: 'Cancel')),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(dctx, ctrl.text.trim()),
              child: const Text('OK'),
            ),
          ],
        ),
      );
      if (res != null && res.isNotEmpty) {
        await ChatService.instance.setNickname(res);
      }
    } finally {
      ctrl.dispose();
    }
  }
}

class _ChatComingSoon extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F1117),
      appBar: AppBar(
        backgroundColor: _kCard,
        title: Text(
          context.tr(pl: 'Czat', en: 'Chat'),
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
        ),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.forum_outlined, size: 56, color: _kAccent),
              const SizedBox(height: 16),
              Text(
                context.tr(pl: 'Czat wkrótce', en: 'Chat coming soon'),
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFFE8ECF0),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                context.tr(
                  pl: 'Backend nie jest jeszcze włączony.',
                  en: 'Backend is not yet enabled.',
                ),
                style: const TextStyle(fontSize: 13, color: _kTextSec),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ErrorRetry extends StatelessWidget {
  final VoidCallback onRetry;
  const _ErrorRetry({required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off, color: _kTextMut, size: 40),
            const SizedBox(height: 12),
            Text(
              context.tr(pl: 'Brak połączenia z czatem', en: 'Chat unreachable'),
              style: const TextStyle(
                  fontSize: 15, fontWeight: FontWeight.w700, color: Color(0xFFE8ECF0)),
            ),
            const SizedBox(height: 4),
            Text(
              context.tr(
                pl: 'Sprawdź połączenie internetowe i spróbuj ponownie.',
                en: 'Check your internet connection and try again.',
              ),
              style: const TextStyle(fontSize: 12, color: _kTextSec),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 14),
            ElevatedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: Text(context.tr(pl: 'Spróbuj ponownie', en: 'Retry')),
            ),
          ],
        ),
      ),
    );
  }
}

class _RoomTile extends StatelessWidget {
  final String name;
  final String desc;
  final VoidCallback onTap;
  const _RoomTile({required this.name, required this.desc, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () {
          Haptic.tap();
          onTap();
        },
        child: Container(
        margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: _kCard,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: _kBorder),
        ),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: _kAccent.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(Icons.tag, color: _kAccent, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name,
                      style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFFE8ECF0))),
                  const SizedBox(height: 2),
                  Text(desc,
                      style: const TextStyle(fontSize: 12, color: _kTextSec, height: 1.3)),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: _kTextMut),
          ],
        ),
        ),
      ),
    );
  }
}

// ─── Room view ────────────────────────────────────────────────────────────

class _RoomView extends StatefulWidget {
  final ChatRoom room;
  const _RoomView({required this.room});

  @override
  State<_RoomView> createState() => _RoomViewState();
}

class _RoomViewState extends State<_RoomView> {
  final _scroll = ScrollController();
  final _ctrl = TextEditingController();
  final List<ChatMessage> _messages = [];
  bool _loading = true;
  bool _sending = false;
  String? _error;
  Timer? _poller;
  String _myDeviceId = '';

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    await PremiumService.instance.init();
    _myDeviceId = PremiumService.instance.deviceId;
    await _refresh(initial: true);
    _poller = Timer.periodic(const Duration(seconds: 8), (_) => _pollDelta());
  }

  @override
  void dispose() {
    _poller?.cancel();
    _scroll.dispose();
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _refresh({bool initial = false}) async {
    try {
      final msgs = await ChatService.instance
          .listMessages(widget.room.id, limit: 100);
      if (!mounted) return;
      setState(() {
        _messages
          ..clear()
          ..addAll(msgs);
        _loading = false;
        _error = null;
      });
      if (initial) {
        WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _pollDelta() async {
    if (!mounted || _messages.isEmpty) return;
    final last = _messages.last.createdAt.toUtc().toIso8601String();
    try {
      final delta = await ChatService.instance
          .listMessages(widget.room.id, sinceIso: last, limit: 50);
      if (delta.isEmpty || !mounted) return;
      // Dedup by id — a posted message may already be in the list.
      final knownIds = _messages.map((m) => m.id).toSet();
      final fresh = delta.where((m) => !knownIds.contains(m.id)).toList();
      if (fresh.isEmpty) return;
      setState(() => _messages.addAll(fresh));
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
    } catch (_) {
      // Quiet failure — next poll might succeed.
    }
  }

  void _scrollToBottom() {
    if (!_scroll.hasClients) return;
    _scroll.animateTo(
      _scroll.position.maxScrollExtent,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
    );
  }

  Future<void> _send() async {
    final text = _ctrl.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() => _sending = true);
    try {
      final msg = await ChatService.instance
          .postMessage(room: widget.room.id, text: text);
      _ctrl.clear();
      if (!mounted) return;
      setState(() {
        _messages.add(msg);
        _sending = false;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
    } catch (e) {
      debugPrint('ChatRoom.send error: $e');
      if (!mounted) return;
      setState(() => _sending = false);
      // Map the most common reasons (rate limit, banned text) to actionable
      // messages; everything else falls through to a generic retry hint.
      final raw = e.toString().toLowerCase();
      String message;
      if (raw.contains('429') || raw.contains('zwolnij')) {
        message = context.tr(
          pl: 'Zwolnij — max 8 wiadomości na minutę.',
          en: 'Slow down — max 8 messages per minute.',
        );
      } else if (raw.contains('niedozwol') || raw.contains('banned') || raw.contains('400')) {
        message = context.tr(
          pl: 'Wiadomość odrzucona (link lub niedozwolone słowo). Spróbuj inaczej.',
          en: 'Message rejected (link or banned word). Try rewording.',
        );
      } else {
        message = context.tr(
          pl: 'Nie udało się wysłać. Sprawdź połączenie i spróbuj ponownie.',
          en: 'Send failed. Check your connection and try again.',
        );
      }
      // For retryable errors (network / generic) add a "Spróbuj ponownie"
      // SnackBarAction so the user can re-send without re-typing — the text
      // is still in the input field because we don't clear it until the
      // post succeeds. Rate-limit (429) and banned-word errors don't get
      // the action because they need the user to wait or rephrase, not
      // mash retry.
      final isRetryable = !(raw.contains('429') ||
          raw.contains('zwolnij') ||
          raw.contains('niedozwol') ||
          raw.contains('banned') ||
          raw.contains('400'));
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(message),
        duration: const Duration(seconds: 6),
        action: isRetryable
            ? SnackBarAction(
                label: context.tr(pl: 'Ponów', en: 'Retry'),
                onPressed: _send,
              )
            : null,
      ));
    }
  }

  Future<void> _reportMessage(ChatMessage m) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (dctx) => AlertDialog(
        title: Text(context.tr(pl: 'Zgłoś wiadomość', en: 'Report message')),
        content: Text(context.tr(
          pl: 'Wiadomość zostanie ukryta po 3 zgłoszeniach od różnych użytkowników.',
          en: 'A message gets hidden after 3 reports from distinct devices.',
        )),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dctx, false),
            child: Text(context.tr(pl: 'Anuluj', en: 'Cancel')),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(dctx, true),
            child: Text(context.tr(pl: 'Zgłoś', en: 'Report')),
          ),
        ],
      ),
    );
    if (confirm == true) {
      try {
        await ChatService.instance.report(m.id);
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(context.tr(pl: 'Zgłoszono.', en: 'Reported.')),
        ));
      } catch (e) {
        debugPrint('ChatRoom.report error: $e');
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(context.tr(
            pl: 'Nie udało się zgłosić. Spróbuj ponownie.',
            en: 'Report failed. Try again.',
          )),
        ));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final name = context.language == AppLanguage.pl
        ? widget.room.namePl
        : widget.room.nameEn;
    return Scaffold(
      backgroundColor: const Color(0xFF0F1117),
      appBar: AppBar(
        backgroundColor: _kCard,
        title: Row(
          children: [
            Icon(Icons.tag, color: _kAccent, size: 18),
            const SizedBox(width: 6),
            Text(
              name,
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null && _messages.isEmpty
                    ? _ErrorRetry(onRetry: () => _refresh(initial: true))
                    : RefreshIndicator(
                        onRefresh: () => _refresh(),
                        child: ListView.builder(
                          controller: _scroll,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 8),
                          itemCount: _messages.length,
                          itemBuilder: (_, i) => _MessageBubble(
                            message: _messages[i],
                            isMine: _messages[i].deviceId == _myDeviceId,
                            onLongPress: () => _reportMessage(_messages[i]),
                          ),
                        ),
                      ),
          ),
          _Composer(
            controller: _ctrl,
            sending: _sending,
            onSend: _send,
          ),
        ],
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  final ChatMessage message;
  final bool isMine;
  final VoidCallback onLongPress;
  const _MessageBubble({
    required this.message,
    required this.isMine,
    required this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final time = _formatTime(message.createdAt.toLocal());
    final color = isMine ? _kAccent.withValues(alpha: 0.25) : _kCard;
    final align = isMine ? CrossAxisAlignment.end : CrossAxisAlignment.start;
    return GestureDetector(
      onLongPress: isMine ? null : onLongPress,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Column(
          crossAxisAlignment: align,
          children: [
            ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: MediaQuery.of(context).size.width * 0.78,
              ),
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.only(
                    topLeft: const Radius.circular(12),
                    topRight: const Radius.circular(12),
                    bottomLeft: Radius.circular(isMine ? 12 : 2),
                    bottomRight: Radius.circular(isMine ? 2 : 12),
                  ),
                  border: Border.all(color: _kBorder.withValues(alpha: 0.7)),
                ),
                child: Column(
                  crossAxisAlignment: align,
                  children: [
                    if (!isMine)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 3),
                        child: Text(
                          message.nickname,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            color: _kAccent,
                          ),
                        ),
                      ),
                    Text(
                      message.text,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                        color: Color(0xFFE8ECF0),
                        height: 1.35,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      time,
                      style: const TextStyle(fontSize: 12, color: _kTextMut),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _formatTime(DateTime t) {
    final h = t.hour.toString().padLeft(2, '0');
    final m = t.minute.toString().padLeft(2, '0');
    final now = DateTime.now();
    if (t.year == now.year && t.month == now.month && t.day == now.day) {
      return '$h:$m';
    }
    final d = t.day.toString().padLeft(2, '0');
    final mo = t.month.toString().padLeft(2, '0');
    return '$d.$mo $h:$m';
  }
}

class _Composer extends StatelessWidget {
  final TextEditingController controller;
  final bool sending;
  final VoidCallback onSend;
  const _Composer({
    required this.controller,
    required this.sending,
    required this.onSend,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(8, 4, 4, 6),
        decoration: BoxDecoration(
          color: _kCard,
          border: Border(top: BorderSide(color: _kBorder.withValues(alpha: 0.8))),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: TextField(
                controller: controller,
                maxLines: 4,
                minLines: 1,
                maxLength: 400,
                textInputAction: TextInputAction.send,
                style: const TextStyle(fontSize: 15),
                onSubmitted: (_) => onSend(),
                decoration: InputDecoration(
                  hintText: context.tr(pl: 'Napisz wiadomość…', en: 'Type a message…'),
                  hintStyle: const TextStyle(fontSize: 15, color: _kTextMut),
                  counterText: '',
                  isDense: true,
                  border: const OutlineInputBorder(
                    borderRadius: BorderRadius.all(Radius.circular(20)),
                  ),
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                ),
              ),
            ),
            const SizedBox(width: 4),
            IconButton(
              onPressed: sending ? null : onSend,
              iconSize: 28,
              constraints: const BoxConstraints(minWidth: 56, minHeight: 56),
              icon: sending
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Icon(Icons.send_rounded, color: _kAccent),
            ),
          ],
        ),
      ),
    );
  }
}
