import 'dart:async';

import 'package:flutter/material.dart';

import '../config/app_links.dart';
import '../config/backend_config.dart';
import '../i18n/app_language.dart';
import '../services/blocked_users.dart';
import '../services/chat_service.dart';
import '../services/content_filter.dart';
import '../services/premium_service.dart';
import '../utils/haptic.dart';
import '../widgets/community_gate.dart';
import 'profile_screen.dart';
import '../theme/app_theme.dart' show kTextMut;

// Public chat (Fitter Welder Pro). Two-screen flow:
//   1. ChatScreen — list of rooms
//   2. _RoomView  — messages + compose for the selected room
// Polling every 8s while a room is on-screen; on send the message is
// optimistically appended so the user sees immediate feedback even before
// the backend confirms (the next poll will dedup against id).

const _kCard = Color(0xFF141821);
const _kAccent = Color(0xFFAB47BC); // purple accent — distinct from premium gold
const _kBorder = Color(0xFF2A3140);
const _kTextSec = Color(0xFF9BA3C7);
const _kTextMut = kTextMut;
// P3-13 — chevron polish (brighter than _kTextMut so the affordance reads
// under workshop fluorescents) + brighter edit-nickname icon.
const _kChevron = Color(0xFFB0B7D4);
const _kIconBright = Color(0xFFE0E4F2);

// Podpis pod wiadomością pochodzi z profilu (imię i nazwisko). Nie ma osobnej,
// dowolnie zmiennej ksywki — nie ma więc czego walidować. Kto chce zmienić to,
// co widzą inni, robi to w jednym miejscu: w profilu.

// P1-43 — minimum visible message length. Single-character "k" / "ok!" feels
// like accidental keyboard mash and rate-limits faster than it informs.
const int _kMinMessageChars = 2;

// P1-42 — 30s heartbeat throttle while the app is in background. When the
// Timer fires AppLifecycleState.paused we instead schedule a single
// poll at most every 30s so we keep up with light traffic without
// draining a backgrounded phone.
const Duration _kBackgroundHeartbeat = Duration(seconds: 30);

class ChatScreen extends StatefulWidget {
  final Future<List<ChatRoom>> Function()? loadRooms;

  const ChatScreen({super.key, this.loadRooms});

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
    // Wejście na czat = moment na powiązanie sekretu instalacji z device_id
    // (POST /device/register). Tylko po zgodzie na zasady — sprawdza to
    // registerDeviceIfConsented. Stary backend (404) i brak sieci: po cichu.
    unawaited(ChatService.instance.registerDeviceIfConsented());
    _loadRooms();
  }

  Future<void> _loadRooms() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final rooms = await (widget.loadRooms?.call() ??
          ChatService.instance.listRooms());
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
      backgroundColor: const Color(0xFF0B0E13),
      appBar: AppBar(
        backgroundColor: _kCard,
        title: Text(
          context.tr(pl: 'Czat', en: 'Chat'),
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.person_outline, color: _kIconBright),
            tooltip: context.tr(pl: 'Twój profil', en: 'Your profile'),
            onPressed: _openProfile,
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
                    // P1-42 — keep pull-to-refresh active even when the
                    // rooms list is empty (zero-rooms cold-start state).
                    physics: const AlwaysScrollableScrollPhysics(),
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

  /// Tożsamość na czacie edytuje się w profilu — nie ma osobnej ksywki.
  Future<void> _openProfile() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const ProfileScreen()),
    );
    if (mounted) setState(() {});
  }
}

class _ChatComingSoon extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0B0E13),
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
                  color: Color(0xFFE7ECF3),
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
                  fontSize: 15, fontWeight: FontWeight.w700, color: Color(0xFFE7ECF3)),
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
                          color: Color(0xFFE7ECF3))),
                  const SizedBox(height: 2),
                  Text(desc,
                      style: const TextStyle(fontSize: 12, color: _kTextSec, height: 1.3)),
                ],
              ),
            ),
            // P3-13 — brighter chevron so the affordance reads off the card.
            const Icon(Icons.chevron_right, color: _kChevron),
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

class _RoomViewState extends State<_RoomView> with WidgetsBindingObserver {
  final _scroll = ScrollController();
  final _ctrl = TextEditingController();
  final List<ChatMessage> _messages = [];
  // P1-42 — composite (id + createdAt-iso) seen-set so identical-timestamp
  // burst posts from different ids still dedupe correctly even if the
  // backend recycles ids or returns the same message across two polls.
  final Set<String> _seenKeys = <String>{};
  bool _loading = true;
  bool _sending = false;

  /// Treść i klucz idempotencji ostatniej NIEUDANEJ wysyłki — patrz [_send].
  String? _pendingText;
  String? _pendingKey;

  /// Bramka imienia i zasad jest właśnie na ekranie — drugie stuknięcie
  /// „Wyślij" nie może otworzyć jej drugi raz.
  bool _gating = false;
  // P3-13 — polling loading dot in AppBar. Goes true around each poll so the
  // user can see "the app is alive and watching the channel".
  bool _polling = false;
  String? _error;
  Timer? _poller;
  String _myDeviceId = '';
  String? _myAuthorId;
  // P1-42 — lifecycle pause + 30s heartbeat throttle while backgrounded.
  AppLifecycleState _lifecycle = AppLifecycleState.resumed;
  DateTime? _lastBackgroundPoll;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _bootstrap();
  }

  /// Wiadomości bez tych od zablokowanych autorów. Filtrujemy po stronie
  /// klienta i po identyfikatorze autora (`author_id`, a na starym backendzie
  /// device_id), nie po nazwie — nazwę można zmienić, blokada ma przetrwać.
  List<ChatMessage> get _visibleMessages => _messages
      .where((m) =>
          !BlockedUsers.instance.isBlockedAny([m.authorId, m.deviceId]))
      .toList();

  /// Własna wiadomość: pole `mine` od serwera, a na starym backendzie
  /// porównanie device_id (patrz [ChatMessage.isMine]).
  bool _isMine(ChatMessage m) =>
      m.isMine(myDeviceId: _myDeviceId, myAuthorId: _myAuthorId);

  Future<void> _bootstrap() async {
    // Pokój otwiera się po bramce zgody, a odpytywanie i tak wysyła
    // identyfikator — tworzymy go (jeśli trzeba) i zapisujemy od razu, żeby
    // porównanie „moje / cudze" nie trafiło na tymczasowy.
    await PremiumService.instance.ensureIdentity();
    await BlockedUsers.instance.load();
    await ReportedMessages.instance.load();
    // P1-43 — read PremiumService.deviceId (NOT nickname) so the isMine
    // check is stable across nickname edits. Guarded against empty in the
    // bubble too.
    _myDeviceId = PremiumService.instance.deviceId;
    _myAuthorId = PremiumService.instance.authorId;
    await _refresh(initial: true);
    _poller = Timer.periodic(const Duration(seconds: 8), (_) => _onTick());
  }

  // P1-42 — pause polling on AppLifecycleState.paused, resume on resumed
  // with an immediate delta poll then the regular periodic cadence.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _lifecycle = state;
    if (state == AppLifecycleState.resumed) {
      // Fire one immediate catch-up; the periodic Timer keeps running.
      _pollDelta();
    }
  }

  // The 8s Timer always fires; we route through _onTick to skip work when
  // the app is paused/inactive (battery) and throttle background polls to
  // a 30s heartbeat.
  void _onTick() {
    if (!mounted) return;
    if (_lifecycle == AppLifecycleState.paused ||
        _lifecycle == AppLifecycleState.inactive ||
        _lifecycle == AppLifecycleState.hidden) {
      final last = _lastBackgroundPoll;
      if (last != null &&
          DateTime.now().difference(last) < _kBackgroundHeartbeat) {
        return; // throttle: at most one poll per 30 s while backgrounded
      }
      _lastBackgroundPoll = DateTime.now();
    }
    _pollDelta();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _poller?.cancel();
    _scroll.dispose();
    _ctrl.dispose();
    super.dispose();
  }

  // P1-42 — composite key for dedupe: identical-timestamp messages with
  // distinct ids still get through; identical id+timestamp pairs get
  // filtered as duplicates of the same logical post.
  String _keyOf(ChatMessage m) =>
      '${m.id}|${m.createdAt.toUtc().millisecondsSinceEpoch}';

  Future<void> _refresh({bool initial = false}) async {
    if (mounted) setState(() => _polling = true);
    try {
      final msgs = await ChatService.instance
          .listMessages(widget.room.id, limit: 100);
      if (!mounted) return;
      setState(() {
        _messages
          ..clear()
          ..addAll(msgs);
        // P1-42 — rebuild the composite-key seen-set from scratch on full
        // refresh so we don't grow it unbounded across reconnects.
        _seenKeys
          ..clear()
          ..addAll(msgs.map(_keyOf));
        _loading = false;
        _polling = false;
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
        _polling = false;
      });
    }
  }

  Future<void> _pollDelta() async {
    if (!mounted) return;
    // P1-42 — empty-room first-message: if we have no messages yet, do a
    // full refresh instead of bailing. Otherwise the first post ever made
    // to a brand-new room is invisible until the user pulls-to-refresh.
    if (_messages.isEmpty) {
      await _refresh();
      return;
    }
    if (mounted) setState(() => _polling = true);
    final last = _messages.last.createdAt.toUtc().toIso8601String();
    try {
      final delta = await ChatService.instance
          .listMessages(widget.room.id, sinceIso: last, limit: 50);
      if (!mounted) return;
      if (delta.isEmpty) {
        setState(() => _polling = false);
        return;
      }
      // P1-42 — dedupe on composite (id + createdAt) so identical-timestamp
      // burst posts with distinct ids still come through; identical id+ts
      // pairs (the same logical message we already have) get filtered.
      final fresh = delta.where((m) => !_seenKeys.contains(_keyOf(m))).toList();
      if (fresh.isEmpty) {
        setState(() => _polling = false);
        return;
      }
      setState(() {
        _messages.addAll(fresh);
        _seenKeys.addAll(fresh.map(_keyOf));
        _polling = false;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
    } catch (_) {
      // Quiet failure — next poll might succeed.
      if (mounted) setState(() => _polling = false);
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
    // P1-43 — minimum 2 visible characters. Single-character mash usually
    // means a gloved misfire; refuse and tell the user how to fix it
    // instead of burning a 429 budget on noise.
    if (text.length < _kMinMessageChars) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(context.tr(
          pl: 'Za krótka wiadomość — napisz przynajmniej $_kMinMessageChars znaki.',
          en: 'Message too short — write at least $_kMinMessageChars characters.',
        )),
        duration: const Duration(seconds: 4),
      ));
      return;
    }
    // Filtr treści obraźliwych — pierwsza z trzech rzeczy, których Apple wymaga
    // przy treściach od użytkowników (obok zgłaszania i blokowania). Zatrzymujemy
    // przy wysyłce, żeby taka wiadomość w ogóle nie trafiła do innych.
    if (ContentFilter.isObjectionable(text)) {
      Haptic.error();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        backgroundColor: const Color(0xFFF0655A),
        content: Text(context.tr(
          pl: 'Ta wiadomość łamie zasady czatu. Bez wyzwisk.',
          en: 'This message breaks the chat rules. No insults.',
        )),
        duration: const Duration(seconds: 4),
      ));
      return;
    }
    // Ostatnia linia obrony przed wysłaniem bez podpisu i bez zasad. Zwykle
    // przepuszcza od razu — wejście na czat (ekran główny) już przeszło
    // bramkę. Łapie wejścia z pominięciem bramki i zmianę zasad (podniesione
    // kLegalVersion) w trakcie sesji.
    if (!hasCommunityAccess) {
      if (_gating) return;
      _gating = true;
      final ok = await ensureCommunityAccess(context);
      _gating = false;
      if (!ok || !mounted) return;
    }
    setState(() => _sending = true);
    // Klucz idempotencji: ta sama treść po nieudanej próbie („Ponów" albo
    // ponowne „Wyślij") idzie z TYM SAMYM kluczem. Jeśli pierwsza próba
    // jednak doszła, serwer zwróci ją zamiast zapisać drugi raz.
    final key = (_pendingText == text ? _pendingKey : null) ??
        ChatService.newIdempotencyKey();
    _pendingText = text;
    _pendingKey = key;
    try {
      final msg = await ChatService.instance
          .postMessage(room: widget.room.id, text: text, idempotencyKey: key);
      _ctrl.clear();
      _pendingText = null;
      _pendingKey = null;
      if (!mounted) return;
      setState(() {
        // Po ponowieniu serwer może odesłać wiadomość, którą odpytywanie
        // zdążyło już pokazać — drugi raz jej nie dokładamy.
        if (_seenKeys.add(_keyOf(msg))) _messages.add(msg);
        _sending = false;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
    } catch (e) {
      // Surowy wyjątek tylko do logu — monter dostaje zrozumiały komunikat.
      debugPrint('ChatRoom.send error: $e');
      if (!mounted) return;
      setState(() => _sending = false);
      // Map the most common reasons (rate limit, banned text, rejected
      // install secret) to actionable messages; everything else falls
      // through to a generic retry hint.
      final failure = classifyChatError(e);
      final String message;
      switch (failure) {
        case ChatFailure.rateLimited:
          message = context.tr(
            pl: 'Zwolnij — max 8 wiadomości na minutę.',
            en: 'Slow down — max 8 messages per minute.',
          );
        case ChatFailure.rejected:
          message = context.tr(
            pl: 'Wiadomość odrzucona (link lub niedozwolone słowo). Spróbuj inaczej.',
            en: 'Message rejected (link or banned word). Try rewording.',
          );
        case ChatFailure.installSecret:
          message = _installSecretMessage(context);
        case ChatFailure.offline:
        case ChatFailure.server:
          message = context.tr(
            pl: 'Nie udało się wysłać. Sprawdź połączenie i spróbuj ponownie.',
            en: 'Send failed. Check your connection and try again.',
          );
      }
      // For retryable errors (network / generic) add a "Spróbuj ponownie"
      // SnackBarAction so the user can re-send without re-typing — the text
      // is still in the input field because we don't clear it until the
      // post succeeds. Rate-limit (429), rejected text and a rejected install
      // secret don't get the action: they need the user to wait, rephrase or
      // contact us, not mash retry.
      final isRetryable =
          failure == ChatFailure.offline || failure == ChatFailure.server;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(message),
        duration: Duration(
            seconds: failure == ChatFailure.installSecret ? 10 : 6),
        action: isRetryable
            ? SnackBarAction(
                label: context.tr(pl: 'Ponów', en: 'Retry'),
                onPressed: _send,
              )
            : null,
      ));
    }
  }

  /// Przytrzymanie wiadomości daje realny wybór. Apple przy treściach od
  /// użytkowników (wytyczna 1.2) wymaga i zgłaszania treści, i blokowania
  /// osób — apka miała tylko to pierwsze. Monter powiedziałby prościej:
  /// „chcę tego gościa po prostu nie widzieć".
  Future<void> _messageActions(ChatMessage m) async {
    if (_isMine(m)) return; // nie zgłasza się i nie blokuje samego siebie

    final action = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: _kCard,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (sctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  m.nickname,
                  style: const TextStyle(
                      color: _kTextSec, fontSize: 13, fontWeight: FontWeight.w600),
                ),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.flag_outlined, color: Color(0xFFF5B23D)),
              title: Text(context.tr(
                  pl: 'Zgłoś wiadomość', en: 'Report message')),
              subtitle: Text(
                context.tr(
                    pl: 'Trafi do moderacji', en: 'Sent to moderation'),
                style: const TextStyle(color: _kTextMut, fontSize: 12),
              ),
              onTap: () => Navigator.pop(sctx, 'report'),
            ),
            ListTile(
              leading: const Icon(Icons.block, color: Color(0xFFF0655A)),
              title: Text(context.tr(
                  pl: 'Zablokuj autora', en: 'Block author')),
              subtitle: Text(
                context.tr(
                    pl: 'Przestaniesz widzieć jego wiadomości',
                    en: 'You stop seeing their messages'),
                style: const TextStyle(color: _kTextMut, fontSize: 12),
              ),
              onTap: () => Navigator.pop(sctx, 'block'),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );

    if (!mounted || action == null) return;
    if (action == 'report') {
      await _reportMessage(m);
    } else if (action == 'block') {
      await _blockAuthor(m);
    }
  }

  Future<void> _blockAuthor(ChatMessage m) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dctx) => AlertDialog(
        title: Text(context.tr(
            pl: 'Zablokować ${m.nickname}?', en: 'Block ${m.nickname}?')),
        content: Text(context.tr(
          pl: 'Nie zobaczysz więcej jego wiadomości. Blokada zostaje na Twoim '
              'telefonie — on się o niej nie dowie. Odblokujesz go w profilu.',
          en: 'You will no longer see their messages. The block stays on your '
              'phone — they are not told. Undo it in your profile.',
        )),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dctx, false),
            child: Text(context.tr(pl: 'Anuluj', en: 'Cancel')),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFF0655A),
                foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(dctx, true),
            child: Text(context.tr(pl: 'Zablokuj', en: 'Block')),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    // Nowy backend: author_id (stabilny pseudonim). Stary: device_id.
    await BlockedUsers.instance.block(m.blockKey, m.nickname);
    if (!mounted) return;
    Haptic.saved();
    setState(() {});
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(context.tr(
        pl: 'Zablokowano ${m.nickname}.',
        en: 'Blocked ${m.nickname}.',
      )),
    ));
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
        final failure = classifyChatError(e);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          duration: Duration(
              seconds: failure == ChatFailure.installSecret ? 10 : 4),
          content: Text(switch (failure) {
            ChatFailure.installSecret => _installSecretMessage(context),
            ChatFailure.rateLimited => context.tr(
                pl: 'Wyczerpano dzienny limit zgłoszeń. Spróbuj jutro.',
                en: 'Daily report limit reached. Try tomorrow.',
              ),
            _ => context.tr(
                pl: 'Nie udało się zgłosić. Spróbuj ponownie.',
                en: 'Report failed. Try again.',
              ),
          }),
        ));
      }
    }
  }

  /// Serwer odrzucił sekret instalacji (401 `INSTALL_SECRET_*`): ktoś inny
  /// podał się za ten identyfikator albo telefon zgubił sekret. Ponowienie nic
  /// nie da, więc mówimy wprost, co zrobić.
  String _installSecretMessage(BuildContext context) => context.tr(
        pl: 'Serwer czatu nie rozpoznał tej instalacji aplikacji i nie przyjął '
            'wiadomości. Uruchom aplikację ponownie. Jeśli to nie pomoże, '
            'napisz do nas: ${AppLinks.supportEmail}.',
        en: 'The chat server did not recognise this app installation and '
            'refused the message. Restart the app. If that does not help, '
            'write to us: ${AppLinks.supportEmail}.',
      );

  @override
  Widget build(BuildContext context) {
    final name = context.language == AppLanguage.pl
        ? widget.room.namePl
        : widget.room.nameEn;
    return Scaffold(
      backgroundColor: const Color(0xFF0B0E13),
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
            // P3-13 — polling loading dot in AppBar (visible only while a
            // poll is in flight). Tells the user the channel is being
            // watched without dominating the title row.
            if (_polling) ...[
              const SizedBox(width: 10),
              SizedBox(
                width: 12,
                height: 12,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(_kAccent),
                ),
              ),
            ],
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
                        // P1-42 — render the empty-room CTA inside a
                        // scrollable so pull-to-refresh keeps working at
                        // zero messages.
                        child: _visibleMessages.isEmpty
                            ? ListView(
                                physics:
                                    const AlwaysScrollableScrollPhysics(),
                                children: const [
                                  SizedBox(height: 80),
                                  _EmptyRoomCta(),
                                ],
                              )
                            : ListView.builder(
                                controller: _scroll,
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 8),
                                itemCount: _visibleMessages.length,
                                itemBuilder: (_, i) => _MessageBubble(
                                  message: _visibleMessages[i],
                                  // P1-43 — guard isMine against the race
                                  // where _myDeviceId hasn't loaded yet
                                  // (PremiumService init in progress); an
                                  // empty deviceId on both sides would
                                  // otherwise falsely flag every message
                                  // as mine.
                                  isMine: _isMine(_visibleMessages[i]),
                                  onLongPress: () =>
                                      _messageActions(_visibleMessages[i]),
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

// P1-42 — empty-room first-message CTA. Renders when _messages.isEmpty so
// the welder knows the channel is alive and that posting first is welcome.
class _EmptyRoomCta extends StatelessWidget {
  const _EmptyRoomCta();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.forum_outlined, size: 48, color: _kAccent),
            const SizedBox(height: 12),
            Text(
              context.tr(
                pl: 'Witaj — bądź pierwszy',
                en: 'Welcome — be the first',
              ),
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: Color(0xFFE7ECF3),
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 6),
            Text(
              context.tr(
                pl: 'Napisz pierwszą wiadomość w tym kanale.',
                en: 'Post the first message in this channel.',
              ),
              style: const TextStyle(fontSize: 13, color: _kTextSec),
              textAlign: TextAlign.center,
            ),
          ],
        ),
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
    // P3-13 — bump own-bubble alpha into 0.45-0.55 band so the welder can
    // distinguish their own posts at a glance under workshop lighting; the
    // previous 0.25 was washed-out on AMOLED panels at low brightness.
    final color = isMine ? _kAccent.withValues(alpha: 0.50) : _kCard;
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
                        color: Color(0xFFE7ECF3),
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
                // P3-13 — composer font 15 → 16 for outdoor readability
                // (sweat / tinted visor / direct sun).
                style: const TextStyle(fontSize: 16),
                onSubmitted: (_) => onSend(),
                decoration: InputDecoration(
                  hintText: context.tr(pl: 'Napisz wiadomość…', en: 'Type a message…'),
                  hintStyle: const TextStyle(fontSize: 16, color: _kTextMut),
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
