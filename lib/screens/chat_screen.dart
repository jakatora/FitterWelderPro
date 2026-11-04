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
import 'account_screen.dart';
import '../services/account_service.dart';
import '../theme/app_theme.dart' show kMinTapTarget, kTextMut;

// Public chat (Fitter Welder Pro). Two-screen flow:
//   1. ChatScreen — list of rooms
//   2. _RoomView  — messages + compose for the selected room
// Polling every 8s while a room is on-screen; on send the message is
// optimistically appended so the user sees immediate feedback even before
// the backend confirms (the next poll will dedup against id).

const _kCard = Color(0xFF141821);
const _kAccent =
    Color(0xFFAB47BC); // purple accent — distinct from premium gold
const _kBorder = Color(0xFF2A3140);
const _kTextSec = Color(0xFF9BA3C7);
const _kTextMut = kTextMut;
// P3-13 — chevron polish (brighter than _kTextMut so the affordance reads
// under workshop fluorescents) + brighter edit-nickname icon.
const _kChevron = Color(0xFFB0B7D4);
const _kIconBright = Color(0xFFE0E4F2);

// Kolory tekstu w dymkach — publiczne, bo pilnuje ich test kontrastu
// (test/screens/chat_message_actions_test.dart, WCAG AA ≥ 4,5:1). Fiolet
// akcentu (#AB47BC) na karcie miał 3,7:1, a kTextMut na własnym dymku 3,3:1.

/// Tło własnego dymka: fiolet akcentu w 50% na tle ekranu.
const Color kChatMineBubble = Color(0x80AB47BC);

/// Podpis autora nad cudzą wiadomością (≈ 7,4:1 na karcie).
const Color kChatAuthorName = Color(0xFFCE93D8);

/// Godzina we własnym dymku (≈ 6,9:1 na fiolecie).
const Color kChatTimeOnMine = Color(0xFFD9CCE0);

/// Godzina w cudzym dymku (≈ 5,5:1 na karcie).
const Color kChatTimeOnOthers = kTextMut;

// Podpis pod wiadomością pochodzi z profilu (imię i nazwisko). Nie ma osobnej,
// dowolnie zmiennej ksywki — nie ma więc czego walidować. Kto chce zmienić to,
// co widzą inni, robi to w jednym miejscu: w profilu.

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
    unawaited(AccountService.instance.load().catchError((Object _) {}));
    _loadRooms();
  }

  Future<void> _loadRooms() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final rooms =
          await (widget.loadRooms?.call() ?? ChatService.instance.listRooms());
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
        title: ListenableBuilder(
            listenable: AccountService.instance,
            builder: (_, __) =>
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(context.tr(pl: 'Czat', en: 'Chat'),
                      style: const TextStyle(
                          fontSize: 20, fontWeight: FontWeight.w700)),
                  if (AccountService.instance.account?['displayName']
                      case final String name when name.trim().isNotEmpty)
                    Text(
                        name,
                        style: const TextStyle(fontSize: 12),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                ])),
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
                      final name = context.language == AppLanguage.pl
                          ? r.namePl
                          : r.nameEn;
                      final desc = context.language == AppLanguage.pl
                          ? r.descPl
                          : r.descEn;
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
      MaterialPageRoute(builder: (_) => const AccountScreen()),
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
        title: ListenableBuilder(
            listenable: AccountService.instance,
            builder: (_, __) =>
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(context.tr(pl: 'Czat', en: 'Chat'),
                      style: const TextStyle(
                          fontSize: 20, fontWeight: FontWeight.w700)),
                  if (AccountService.instance.account?['displayName']
                      case final String name when name.trim().isNotEmpty)
                    Text(
                        name,
                        style: const TextStyle(fontSize: 12),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                ])),
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
              context.tr(
                  pl: 'Brak połączenia z czatem', en: 'Chat unreachable'),
              style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFFE7ECF3)),
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
  const _RoomTile(
      {required this.name, required this.desc, required this.onTap});

  @override
  Widget build(BuildContext context) {
    // Margines NA ZEWNĄTRZ InkWell — wcześniej był w środku i rozlew
    // dotknięcia wychodził poza kartę.
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () {
            Haptic.tap();
            onTap();
          },
          child: Container(
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
                          style: const TextStyle(
                              fontSize: 12, color: _kTextSec, height: 1.3)),
                    ],
                  ),
                ),
                // P3-13 — brighter chevron so the affordance reads off the card.
                const Icon(Icons.chevron_right, color: _kChevron),
              ],
            ),
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
  bool _supportsIdCursor = false;
  int _lastFetchedId = 0;

  /// Treść i klucz idempotencji ostatniej NIEUDANEJ wysyłki — patrz [_send].
  String? _pendingText;
  String? _pendingKey;
  AccountService? _pendingAccount;
  int? _pendingRevision;
  late final AccountService _observedAccount;
  late int _observedAccountRevision;

  /// Bramka imienia i zasad jest właśnie na ekranie — drugie stuknięcie
  /// „Wyślij" nie może otworzyć jej drugi raz.
  bool _gating = false;
  // P3-13 — polling loading dot in AppBar. Goes true around each poll so the
  // user can see "the app is alive and watching the channel".
  bool _polling = false;
  int _messageRequestSequence = 0;
  int _lastAppliedMessageRequest = 0;
  bool _pollFailed = false;
  bool _retentionConfirmed = false;
  bool _hasNewMessages = false;
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
    _scroll.addListener(_onScroll);
    _observedAccount = AccountService.instance;
    _observedAccountRevision = _observedAccount.sessionRevision;
    _observedAccount.addListener(_onAccountChanged);
    WidgetsBinding.instance.addObserver(this);
    _bootstrap();
  }

  void _onAccountChanged() {
    final revision = _observedAccount.sessionRevision;
    if (!mounted || revision == _observedAccountRevision) return;
    _observedAccountRevision = revision;
    // Discard responses and per-reader 'mine' flags from the former session.
    _lastAppliedMessageRequest = ++_messageRequestSequence;
    setState(() {
      _messages.clear();
      _seenKeys.clear();
      _pendingText = null;
      _pendingKey = null;
      _pendingAccount = null;
      _pendingRevision = null;
      _lastFetchedId = 0;
      _supportsIdCursor = false;
      _retentionConfirmed = false;
      _hasNewMessages = false;
      _loading = true;
    });
    unawaited(_refresh(initial: true));
  }

  /// Wiadomości bez tych od zablokowanych autorów. Filtrujemy po stronie
  /// klienta i po identyfikatorze autora (`author_id`, a na starym backendzie
  /// device_id), nie po nazwie — nazwę można zmienić, blokada ma przetrwać.
  ///
  /// Wiadomości zgłoszone z tego telefonu też znikają od razu — serwer ukrywa
  /// je wszystkim dopiero po 3 zgłoszeniach.
  List<ChatMessage> get _visibleMessages => _messages
      .where((m) =>
          !BlockedUsers.instance.isBlockedAny([m.authorId, m.deviceId]) &&
          !ReportedMessages.instance.isReported(m.id))
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
    if (!mounted) return;
    await BlockedUsers.instance.load();
    if (!mounted) return;
    await ReportedMessages.instance.load();
    if (!mounted) return;
    // P1-43 — read PremiumService.deviceId (NOT nickname) so the isMine
    // check is stable across nickname edits. Guarded against empty in the
    // bubble too.
    _myDeviceId = PremiumService.instance.deviceId;
    _myAuthorId = PremiumService.instance.authorId;
    await _refresh(initial: true);
    if (!mounted) return;
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
    _observedAccount.removeListener(_onAccountChanged);
    _poller?.cancel();
    _scroll.removeListener(_onScroll);
    _scroll.dispose();
    _ctrl.dispose();
    super.dispose();
  }

  // P1-42 — composite key for dedupe: identical-timestamp messages with
  // distinct ids still get through; identical id+timestamp pairs get
  // filtered as duplicates of the same logical post.
  String _keyOf(ChatMessage m) =>
      '${m.id}|${m.createdAt.toUtc().millisecondsSinceEpoch}';

  int _compareMessages(ChatMessage a, ChatMessage b) {
    final byTime = a.createdAt.compareTo(b.createdAt);
    return byTime != 0 ? byTime : a.id.compareTo(b.id);
  }

  Future<void> _refresh({bool initial = false}) async {
    final request = ++_messageRequestSequence;
    final before = _messages.map(_keyOf).toSet();
    if (mounted) setState(() => _polling = true);
    try {
      final batch = await ChatService.instance
          .listMessageBatch(widget.room.id, limit: 100);
      final cutoff = batch.retainedSince;
      final msgs = batch.messages.where((m) =>
          cutoff == null || !m.createdAt.toUtc().isBefore(cutoff)).toList();
      if (!mounted || request < _lastAppliedMessageRequest) return;
      _lastAppliedMessageRequest = request;
      final firstMessages = _messages.isEmpty && msgs.isNotEmpty;
      setState(() {
        final received = msgs.map(_keyOf).toSet();
        final arrivedDuringRefresh = _messages.where((m) =>
            !before.contains(_keyOf(m)) && !received.contains(_keyOf(m)) &&
            (cutoff == null || !m.createdAt.toUtc().isBefore(cutoff))).toList();
        _retentionConfirmed = cutoff != null;
        _supportsIdCursor = batch.supportsIdCursor;
        _lastFetchedId = batch.messages.fold<int>(
            0, (highest, message) => message.id > highest ? message.id : highest);
        _messages
          ..clear()
          ..addAll(msgs)
          ..addAll(arrivedDuringRefresh)
          ..sort(_compareMessages);
        // P1-42 — rebuild the composite-key seen-set from scratch on full
        // refresh so we don't grow it unbounded across reconnects.
        _seenKeys
          ..clear()
          ..addAll(_messages.map(_keyOf));
        _loading = false;
        _polling = false;
        _pollFailed = false;
        _error = null;
      });
      if (initial || firstMessages) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted || !_scroll.hasClients ||
              _scroll.position.isScrollingNotifier.value) {
            return;
          }
          _scrollToBottom();
        });
      }
    } catch (e) {
      if (!mounted || request < _lastAppliedMessageRequest) return;
      setState(() {
        _error = e.toString();
        _loading = false;
        _polling = false;
        _pollFailed = true;
      });
    }
  }

  void _onScroll() {
    if (!_hasNewMessages || !_scroll.hasClients ||
        _scroll.position.extentAfter > 24) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_hasNewMessages || !_scroll.hasClients ||
          _scroll.position.extentAfter > 24) {
        return;
      }
      setState(() => _hasNewMessages = false);
    });
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
    final request = ++_messageRequestSequence;
    if (mounted) setState(() => _polling = true);
    // The server filters with created_at > since. Re-read the last
    // millisecond so a second message with the same timestamp is not missed;
    // the composite seen-set below removes messages already displayed.
    final last = _messages.last.createdAt.toUtc()
        .subtract(const Duration(milliseconds: 1)).toIso8601String();
    try {
      final batch = await ChatService.instance.listMessageBatch(widget.room.id,
          sinceIso: last, afterId: _supportsIdCursor ? _lastFetchedId : null,
          limit: 100);
      if (!mounted || request < _lastAppliedMessageRequest) return;
      _lastAppliedMessageRequest = request;
      final cutoff = batch.retainedSince;
      // P1-42 — dedupe on composite (id + createdAt) so identical-timestamp
      // burst posts with distinct ids still come through; identical id+ts
      // pairs (the same logical message we already have) get filtered.
      final fresh = batch.messages.where((m) =>
          !_seenKeys.contains(_keyOf(m)) &&
          (cutoff == null || !m.createdAt.toUtc().isBefore(cutoff))).toList();
      final position = _scroll.hasClients ? _scroll.position : null;
      final followLatest = position == null ||
          (position.extentAfter <= 96 && !position.isScrollingNotifier.value);
      final previousOffset = position?.pixels;
      setState(() {
        _retentionConfirmed = cutoff != null;
        if (batch.supportsIdCursor) {
          for (final message in batch.messages) {
            if (message.id > _lastFetchedId) _lastFetchedId = message.id;
          }
        }
        _supportsIdCursor = batch.supportsIdCursor;
        if (followLatest) {
          _hasNewMessages = false;
        } else if (fresh.any((m) =>
            !BlockedUsers.instance.isBlockedAny([m.authorId, m.deviceId]) &&
            !ReportedMessages.instance.isReported(m.id))) {
          _hasNewMessages = true;
        }
        if (cutoff != null) {
          _messages.removeWhere((m) => m.createdAt.toUtc().isBefore(cutoff));
          _seenKeys
            ..clear()
            ..addAll(_messages.map(_keyOf));
        }
        _messages.addAll(fresh);
        _messages.sort(_compareMessages);
        _seenKeys.addAll(fresh.map(_keyOf));
        _polling = false;
        _pollFailed = false;
      });
      if (fresh.isNotEmpty && followLatest) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted || !_scroll.hasClients) return;
          final current = _scroll.position;
          if (current.isScrollingNotifier.value ||
              (previousOffset != null &&
                  (current.pixels - previousOffset).abs() > 1)) {
            return;
          }
          _scrollToBottom();
        });
      }
    } catch (_) {
      if (mounted && request >= _lastAppliedMessageRequest) {
        setState(() {
          _polling = false;
          _pollFailed = true;
        });
      }
    }
  }

  Future<void> _scrollToBottom() async {
    if (!_scroll.hasClients) return;
    final target = _scroll.position.maxScrollExtent;
    await _scroll.animateTo(
      target,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
    );
    if (!mounted || !_scroll.hasClients) return;
    final position = _scroll.position;
    // ListView lazily measures rows, so the estimated end may move during
    // animation. Do not override a gesture that interrupted the animation.
    if (!position.isScrollingNotifier.value &&
        (position.pixels - target).abs() <= 1 && position.extentAfter > 1) {
      _scroll.jumpTo(position.maxScrollExtent);
    }
  }

  Future<void> _send({String? retryText, String? retryDraft, String? retryKey,
      AccountService? retryAccount, int? retryRevision}) async {
    bool retryIsCurrent() => retryKey == null ||
        (identical(AccountService.instance, retryAccount) &&
            retryAccount?.sessionRevision == retryRevision &&
            _pendingText == retryText && _pendingKey == retryKey);
    void notifyStaleRetry() {
      final messenger = ScaffoldMessenger.of(context);
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(SnackBar(content: Text(context.tr(
        pl: 'Nie ponowiono wiadomości — konto lub oczekująca wiadomość się zmieniły.',
        en: 'Message not retried — the account or pending message changed.',
      ))));
    }
    if (!retryIsCurrent()) {
      notifyStaleRetry();
      return;
    }
    await AccountService.instance.load();
    if (!mounted) return;
    if (!retryIsCurrent()) {
      notifyStaleRetry();
      return;
    }
    if (AccountService.instance.account == null) {
      await Navigator.of(context)
          .push(MaterialPageRoute<void>(builder: (_) => const AccountScreen()));
      if (!mounted || AccountService.instance.account == null) return;
    }

    final draft = retryDraft ?? _ctrl.text;
    final text = retryText ?? draft.trim();
    if (text.isEmpty || _sending) return;
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
    if (!retryIsCurrent()) {
      notifyStaleRetry();
      return;
    }
    setState(() => _sending = true);
    // Klucz idempotencji: ta sama treść po nieudanej próbie („Ponów" albo
    // ponowne „Wyślij") idzie z TYM SAMYM kluczem. Jeśli pierwsza próba
    // jednak doszła, serwer zwróci ją zamiast zapisać drugi raz.
    final account = AccountService.instance;
    final accountRevision = account.sessionRevision;
    final sameSession = identical(_pendingAccount, account) &&
        _pendingRevision == accountRevision;
    final key = retryKey ??
        (sameSession && _pendingText == text ? _pendingKey : null) ??
        ChatService.newIdempotencyKey();
    _pendingText = text;
    _pendingKey = key;
    _pendingAccount = account;
    _pendingRevision = accountRevision;
    try {
      final msg = await ChatService.instance
          .postMessage(room: widget.room.id, text: text, idempotencyKey: key);
      if (!mounted) return;
      if (!identical(AccountService.instance, account) ||
          account.sessionRevision != accountRevision) {
        throw StateError('Account changed while sending');
      }
      if (_ctrl.text == draft) _ctrl.clear();
      _pendingText = null;
      _pendingKey = null;
      _pendingAccount = null;
      _pendingRevision = null;
      setState(() {
        // Po ponowieniu serwer może odesłać wiadomość, którą odpytywanie
        // zdążyło już pokazać — drugi raz jej nie dokładamy.
        if (_seenKeys.add(_keyOf(msg))) {
          _messages.add(msg);
          _messages.sort(_compareMessages);
        }
        _sending = false;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
    } catch (e) {
      // Surowy wyjątek tylko do logu — monter dostaje zrozumiały komunikat.
      debugPrint('ChatRoom.send error: $e');
      if (!mounted) return;
      setState(() => _sending = false);
      if (!identical(AccountService.instance, account) ||
          account.sessionRevision != accountRevision) {
        _pendingText = null;
        _pendingKey = null;
        _pendingAccount = null;
        _pendingRevision = null;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(context.tr(
          pl: 'Konto zmieniło się podczas wysyłania. Sprawdź, czy wiadomość dotarła, zanim wyślesz ją ponownie.',
          en: 'The account changed while sending. Check whether the message arrived before sending it again.',
        ))));
        return;
      }
      // Map the most common reasons (rate limit, banned text, rejected
      // install secret) to actionable messages; everything else falls
      // through to a generic retry hint.
      final failure = classifyChatError(e);
      final String message;
      switch (failure) {
        case ChatFailure.accountRequired:
          message = context.tr(
              pl: 'Sesja wygasła. Naciśnij Wyślij, aby zalogować się ponownie.',
              en: 'Session expired. Tap Send to sign in again.');
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
        duration:
            Duration(seconds: failure == ChatFailure.installSecret ? 10 : 6),
        action: isRetryable
            ? SnackBarAction(
                label: context.tr(pl: 'Ponów', en: 'Retry'),
                onPressed: () => _send(retryText: text, retryDraft: draft,
                    retryKey: key, retryAccount: account,
                    retryRevision: accountRevision),
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
                      color: _kTextSec,
                      fontSize: 13,
                      fontWeight: FontWeight.w600),
                ),
              ),
            ),
            ListTile(
              leading:
                  const Icon(Icons.flag_outlined, color: Color(0xFFF5B23D)),
              title:
                  Text(context.tr(pl: 'Zgłoś wiadomość', en: 'Report message')),
              subtitle: Text(
                context.tr(pl: 'Trafi do moderacji', en: 'Sent to moderation'),
                style: const TextStyle(color: _kTextMut, fontSize: 12),
              ),
              onTap: () => Navigator.pop(sctx, 'report'),
            ),
            ListTile(
              leading: const Icon(Icons.block, color: Color(0xFFF0655A)),
              title:
                  Text(context.tr(pl: 'Zablokuj autora', en: 'Block author')),
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
    final persisted = await BlockedUsers.instance.block(m.blockKey, m.nickname);
    if (!mounted) return;
    Haptic.saved();
    setState(() {});
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(persisted
          ? context.tr(pl: 'Zablokowano ${m.nickname}.', en: 'Blocked ${m.nickname}.')
          : context.tr(
              pl: 'Zablokowano w tej sesji. Nie udało się zapisać blokady na później.',
              en: 'Blocked for this session. Could not save the block for later.')),
    ));
  }

  Future<void> _reportMessage(ChatMessage m) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (dctx) => AlertDialog(
        title: Text(context.tr(pl: 'Zgłoś wiadomość', en: 'Report message')),
        content: Text(context.tr(
          pl: 'U Ciebie wiadomość zniknie od razu. Zgłoszenie trafia do '
              'kolejki moderacji, a po 3 zgłoszeniach od różnych osób '
              'wiadomość znika automatycznie dla wszystkich.',
          en: 'The message disappears for you right away. The report goes '
              'to the moderation queue, and after 3 reports from different '
              'people the message is hidden for everyone automatically.',
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
        // Ukrywamy dopiero po przyjęciu zgłoszenia — gdy nie doszło, monter
        // widzi komunikat i wiadomość, którą może zgłosić jeszcze raz.
        final hiddenPersisted = await ReportedMessages.instance.add(m.id);
        if (!mounted) return;
        setState(() {});
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(hiddenPersisted
              ? context.tr(
                  pl: 'Zgłoszono. Ta wiadomość jest już dla Ciebie ukryta.',
                  en: 'Reported. This message is now hidden for you.')
              : context.tr(
                  pl: 'Zgłoszono. Wiadomość ukryta w tej sesji; nie udało się zapisać ukrycia na później.',
                  en: 'Reported. Hidden for this session; could not save it for later.')),
        ));
      } catch (e) {
        debugPrint('ChatRoom.report error: $e');
        if (!mounted) return;
        final failure = classifyChatError(e);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          duration:
              Duration(seconds: failure == ChatFailure.installSecret ? 10 : 4),
          content: Text(switch (failure) {
            ChatFailure.accountRequired => context.tr(
                pl: 'Zaloguj się ponownie w Profil → Konto.',
                en: 'Sign in again under Profile → Account.'),
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
    final visibleMessages = _visibleMessages;
    return Scaffold(
      backgroundColor: const Color(0xFF0B0E13),
      appBar: AppBar(
        backgroundColor: _kCard,
        title: Row(
          children: [
            Icon(Icons.tag, color: _kAccent, size: 18),
            const SizedBox(width: 6),
            // Nazwa pokoju przychodzi z serwera — długa nie może przepełnić
            // paska.
            Flexible(
              child: Text(
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style:
                    const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
              ),
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
          if (_pollFailed && _messages.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: Text(
                context.tr(
                  pl: 'Nie udało się odświeżyć wiadomości. Ponawiam próbę automatycznie.',
                  en: 'Could not refresh messages. Trying again automatically.',
                ),
                textAlign: TextAlign.center,
                style: const TextStyle(color: _kTextSec, fontSize: 12),
              ),
            ),
          if (_retentionConfirmed)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: Text(
                context.tr(
                  pl: 'Wiadomości są cyklicznie usuwane po miesiącu.',
                  en: 'Messages are periodically deleted after one month.',
                ),
                textAlign: TextAlign.center,
                style: const TextStyle(color: _kTextSec, fontSize: 12),
              ),
            ),
          Expanded(
            child: Stack(children: [
              Positioned.fill(child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null && _messages.isEmpty
                    ? _ErrorRetry(onRetry: () => _refresh(initial: true))
                    : RefreshIndicator(
                        onRefresh: () => _refresh(),
                        // P1-42 — render the empty-room CTA inside a
                        // scrollable so pull-to-refresh keeps working at
                        // zero messages.
                        child: visibleMessages.isEmpty
                            ? ListView(
                                physics: const AlwaysScrollableScrollPhysics(),
                                children: [
                                  const SizedBox(height: 80),
                                  // Pokój nie jest pusty, jeśli wszystko
                                  // ukryły blokady i zgłoszenia — „bądź
                                  // pierwszy" wprowadzałoby w błąd.
                                  _EmptyRoomCta(
                                      allHidden: _messages.isNotEmpty),
                                ],
                              )
                            : ListView.builder(
                                key: const Key('chat-message-list'),
                                controller: _scroll,
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 8),
                                itemCount: visibleMessages.length,
                                itemBuilder: (_, i) {
                                  final message = visibleMessages[i];
                                  final date = message.createdAt.toLocal();
                                  final firstOfDay = i == 0 ||
                                      !DateUtils.isSameDay(
                                          date, visibleMessages[i - 1]
                                              .createdAt.toLocal());
                                  return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                                    if (firstOfDay)
                                      _ChatDateSeparator(date: date),
                                    _MessageBubble(
                                      message: message,
                                      // Identity is checked only after the
                                      // current device ID is available.
                                      isMine: _isMine(message),
                                      onActions: () => _messageActions(message),
                                    ),
                                  ]);
                                },
                              ),
                      )),
              if (_hasNewMessages && !_loading)
                Positioned(
                  bottom: 12,
                  left: 0,
                  right: 0,
                  child: Center(
                    child: FilledButton.icon(
                      key: const Key('chat-new-messages'),
                      onPressed: () {
                        setState(() => _hasNewMessages = false);
                        _scrollToBottom();
                      },
                      icon: const Icon(Icons.arrow_downward),
                      label: Text(context.tr(pl: 'Nowe wiadomości', en: 'New messages')),
                    ),
                  ),
                ),
            ]),
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

class _ChatDateSeparator extends StatelessWidget {
  const _ChatDateSeparator({required this.date});
  final DateTime date;

  @override
  Widget build(BuildContext context) {
    final day = date.day.toString().padLeft(2, '0');
    final month = date.month.toString().padLeft(2, '0');
    final label = context.tr(
        pl: '$day.$month.${date.year}', en: '$month/$day/${date.year}');
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 8, 0, 16),
      child: Center(
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: _kCard,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: _kBorder),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: Text(label,
                style: const TextStyle(color: _kTextSec, fontSize: 12)),
          ),
        ),
      ),
    );
  }
}

// P1-42 — empty-room first-message CTA. Renders when _messages.isEmpty so
// the welder knows the channel is alive and that posting first is welcome.
class _EmptyRoomCta extends StatelessWidget {
  /// W pokoju są wiadomości, ale wszystkie ukryły blokady i zgłoszenia.
  final bool allHidden;
  const _EmptyRoomCta({this.allHidden = false});

  @override
  Widget build(BuildContext context) {
    if (allHidden) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
        child: Text(
          context.tr(
            pl: 'Wszystkie wiadomości w tym pokoju są ukryte (zablokowani '
                'autorzy albo Twoje zgłoszenia). Blokady zdejmiesz w profilu.',
            en: 'All messages in this room are hidden (blocked authors or '
                'your reports). You can unblock people in your profile.',
          ),
          style: const TextStyle(fontSize: 13, color: _kTextSec, height: 1.4),
          textAlign: TextAlign.center,
        ),
      );
    }
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

  /// Menu „Zgłoś / Zablokuj" dla cudzej wiadomości — z widocznego przycisku
  /// ⋮ oraz (skrót) z długiego przytrzymania dymka.
  final VoidCallback onActions;
  const _MessageBubble({
    required this.message,
    required this.isMine,
    required this.onActions,
  });

  @override
  Widget build(BuildContext context) {
    final time = _formatTime(message.createdAt.toLocal());
    // P3-13 — bump own-bubble alpha into 0.45-0.55 band so the welder can
    // distinguish their own posts at a glance under workshop lighting; the
    // previous 0.25 was washed-out on AMOLED panels at low brightness.
    final color = isMine ? kChatMineBubble : _kCard;
    final align = isMine ? CrossAxisAlignment.end : CrossAxisAlignment.start;
    final bubble = ConstrainedBox(
      constraints: BoxConstraints(
        maxWidth: (MediaQuery.sizeOf(context).width * 0.72).clamp(0, 560),
      ),
      child: IntrinsicWidth(
        child: _bubbleBody(color, align, time),
      ),
    );
    if (isMine) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Column(crossAxisAlignment: align, children: [bubble]),
      );
    }
    // Cudza wiadomość: widoczny przycisk ⋮ (≥ 48 dp, z etykietą) obok dymka.
    // Długie przytrzymanie zostaje jako skrót — z podpowiedzią dla czytnika
    // ekranu, a nie jako jedyna droga do zgłoszenia (WCAG 2.5.1, Apple 1.2).
    final actionsLabel = context.tr(
      pl: 'Akcje wiadomości: ${message.nickname}',
      en: 'Message actions: ${message.nickname}',
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Flexible(
            child: MergeSemantics(
              child: Semantics(
                onLongPressHint:
                    context.tr(pl: 'Zgłoś lub zablokuj', en: 'Report or block'),
                child: GestureDetector(
                  onLongPress: onActions,
                  child: bubble,
                ),
              ),
            ),
          ),
          IconButton(
            key: ValueKey('chat-actions-${message.id}'),
            onPressed: onActions,
            tooltip: actionsLabel,
            icon: const Icon(Icons.more_vert, color: _kTextSec, size: 22),
            constraints: const BoxConstraints(
                minWidth: kMinTapTarget, minHeight: kMinTapTarget),
          ),
        ],
      ),
    );
  }

  Widget _bubbleBody(Color color, CrossAxisAlignment align, String time) {
    final profile = message.professionalProfile;
    final profession = profile?['profession'];
    final processes = profile?['processes'];
    final processLabel = processes is List
        ? processes.whereType<String>().map((value) => value.trim())
            .where((value) => value.isNotEmpty).join(' / ')
        : '';
    final parts = <String>[
      if (profession is String && profession.trim().isNotEmpty) profession.trim(),
      if (processLabel.isNotEmpty) processLabel,
    ];
    final profileLabel = parts.join(' · ');
    return Container(
      key: ValueKey('chat-bubble-${message.id}'),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.only(
          topLeft: const Radius.circular(16),
          topRight: const Radius.circular(16),
          bottomLeft: Radius.circular(isMine ? 16 : 4),
          bottomRight: Radius.circular(isMine ? 4 : 16),
        ),
        border: Border.all(color: _kBorder.withValues(alpha: 0.7)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: align,
        children: [
          if (profileLabel.isNotEmpty)
            Text(
                profileLabel,
                style: TextStyle(fontSize: 12,
                    color: isMine ? kChatTimeOnMine : kChatTimeOnOthers)),
          if (!isMine)
            Padding(
              padding: const EdgeInsets.only(bottom: 3),
              child: Text(
                message.nickname,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: kChatAuthorName,
                ),
              ),
            ),
          Text(
            message.text,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w400,
              color: Color(0xFFE7ECF3),
              height: 1.35,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            time,
            style: TextStyle(
              fontSize: 12,
              color: isMine ? kChatTimeOnMine : kChatTimeOnOthers,
            ),
          ),
        ],
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
          border:
              Border(top: BorderSide(color: _kBorder.withValues(alpha: 0.8))),
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
                  hintText: context.tr(
                      pl: 'Napisz wiadomość…', en: 'Type a message…'),
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
              // Bez etykiety TalkBack i VoiceOver czytały samo „przycisk".
              tooltip: sending
                  ? context.tr(pl: 'Wysyłanie wiadomości', en: 'Sending message')
                  : context.tr(pl: 'Wyślij', en: 'Send'),
              iconSize: 28,
              constraints: const BoxConstraints(minWidth: 56, minHeight: 56),
              icon: sending
                  ? SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        semanticsLabel: context.tr(
                            pl: 'Wysyłanie wiadomości', en: 'Sending message'),
                      ),
                    )
                  : Icon(Icons.send_rounded, color: _kAccent),
            ),
          ],
        ),
      ),
    );
  }
}
