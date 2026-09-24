import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:uuid/uuid.dart';

import '../assistant/assistant_engine.dart';
import '../assistant/assistant_history.dart';
import '../assistant/assistant_intent_client.dart';
import '../assistant/assistant_intents.dart';
import '../assistant/assistant_tools.dart';
import '../assistant/assistant_validator.dart';
import '../assistant/speech_io.dart';
import '../database/weld_param_dao.dart';
import '../i18n/app_language.dart';
import '../services/ai_chat_service.dart';
import '../services/legal_consent.dart';
import '../theme/app_theme.dart' show kTextMut;
import '../utils/haptic.dart';
import '../widgets/community_gate.dart';
import '../widgets/tool_registry.dart';

// Asystent tekstowy i głosowy (spec 2026-08-30 §6). Dwa tryby:
//
//   • „Wykonaj" — przygotowanie DOZWOLONEJ operacji (kAssistantIntentsV1):
//     zapis parametru spawania do „Moje parametry" albo otwarcie narzędzia.
//     mowa → tekst (widoczny, edytowalny) → parser lokalny (offline) →
//     [serwer /ai/intent tylko po zgodzie, gdy parser nie dał rady] →
//     walidator → jedno pytanie przy braku pola → podsumowanie → „Zapisz" →
//     zapis lokalny → SnackBar „Zapisano" z „Cofnij". Bez „Zapisz" nic się nie
//     zapisuje.
//   • „Odpowiedz" — pytania do modelu (/ai/chat). Treść wychodzi na serwer,
//     więc przed pierwszym pytaniem bramka zgody (ensureServerConsent). Bez
//     sieci — wpis z pomocy offline.
//
// Asystent jest dostępny BEZ Premium (dawny PremiumGate zdjęty; limity pilnuje
// backend: 402 / 429 / 503 mają własne komunikaty).
//
// Mikrofon tylko po naciśnięciu (≥ 72 dp — rękawice), widoczny stan
// nasłuchiwania, stop, transkrypcja zostaje po przerwaniu. Czytanie na głos:
// ustawienie, domyślnie wyłączone, milknie w tle.

const _kBg = Color(0xFF0B0E13);
const _kCard = Color(0xFF141821);
const _kBorder = Color(0xFF2A3140);
const _kAccent = Color(0xFFE8C14B);
const _kAccentBlue = Color(0xFF4A9EFF);
const _kTextSec = Color(0xFF9BA3C7);
const _kTextMut = kTextMut;
const _kTextPrimary = Color(0xFFE7ECF3);
const _kListen = Color(0xFFF0655A);
const _kOk = Color(0xFF35C88B);

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

enum AssistantMode { act, answer }

/// Wysyłka pytania w trybie „Odpowiedz" — do podmiany w testach.
typedef AssistantChatSender = Future<ChatMessage> Function(
    String text, List<ChatMessage> history);

class AiChatScreen extends StatefulWidget {
  const AiChatScreen({
    super.key,
    this.initialMode = AssistantMode.act,
    this.speechInput,
    this.speechOutput,
    this.engine,
    this.chatSender,
    this.now,
  });

  final AssistantMode initialMode;

  /// Rozpoznawanie mowy (domyślnie system telefonu).
  final SpeechInput? speechInput;

  /// Czytanie na głos (domyślnie flutter_tts).
  final SpeechOutput? speechOutput;

  /// Parser + walidator + ewentualnie serwer.
  final AssistantEngine? engine;

  final AssistantChatSender? chatSender;

  /// Zegar do notatki źródłowej (testy).
  final DateTime Function()? now;

  @override
  State<AiChatScreen> createState() => _AiChatScreenState();
}

class _AiChatScreenState extends State<AiChatScreen>
    with WidgetsBindingObserver {
  late final SpeechInput _speech = widget.speechInput ?? SystemSpeechInput();
  late final SpeechOutput _voice = widget.speechOutput ?? SystemSpeechOutput();
  late final AssistantEngine _engine = widget.engine ?? AssistantEngine();
  final _dao = WeldParamDao();
  final _history = AssistantHistoryStore.instance;
  static const _uuid = Uuid();

  late AssistantMode _mode = widget.initialMode;
  bool _listening = false;

  // ── „Wykonaj" ───────────────────────────────────────────────────────────
  final _cmdCtrl = TextEditingController();
  bool _busy = false;
  bool _voiceUsed = false;
  String? _pendingIntent;
  String? _pendingField;
  Map<String, Object?> _carried = const {};

  /// Całe polecenie razem z odpowiedziami na pytania — wraca do pola po
  /// „Popraw", żeby nie trzeba było dyktować wszystkiego od nowa.
  String _commandSoFar = '';
  String? _question;
  String? _notice;
  bool _noticeIsError = false;
  bool _offerServer = false;
  bool _offerAsk = false;

  // ── „Odpowiedz" ─────────────────────────────────────────────────────────
  final _inputCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  final _focus = FocusNode();
  final _messages = <ChatMessage>[];
  final ValueNotifier<bool> _typing = ValueNotifier<bool>(false);
  bool _welcomeSeeded = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _history.load();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_welcomeSeeded) {
      _welcomeSeeded = true;
      _messages.add(_buildWelcomeMessage(context));
      return;
    }
    if (_messages.length == 1 && _messages.first.role == ChatRole.assistant) {
      final next = _buildWelcomeMessage(context);
      if (next.text != _messages.first.text) {
        setState(() => _messages[0] = next);
      }
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Nigdy w tle: ani mikrofon, ani czytanie na głos.
    if (state != AppLifecycleState.resumed) {
      if (_listening) {
        _speech.cancel();
        if (mounted) setState(() => _listening = false);
      }
      _voice.stop();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    if (_listening) _speech.cancel();
    _voice.stop();
    _cmdCtrl.dispose();
    _inputCtrl.dispose();
    _scrollCtrl.dispose();
    _focus.dispose();
    _typing.dispose();
    super.dispose();
  }

  String _tr(String pl, String en) => context.tr(pl: pl, en: en);

  ChatMessage _buildWelcomeMessage(BuildContext ctx) {
    final headline = ctx.tr(
      pl: 'Zapytaj o spawanie, montaż albo moduły aplikacji',
      en: 'Ask about welding, fit-up or the app modules',
    );
    final body = ctx.tr(
      pl: 'Odpowiada model AI na serwerze (wymaga internetu i zgody na '
          'zasady). Pytaj o WPS, preheat, NACE, ASME, NDT, kalkulacje.\n\n'
          'Bez internetu dostaniesz najbliższy wpis z pomocy w aplikacji — '
          'wyraźnie oznaczony. Wynik to pomoc, nie zamiennik WPS.',
      en: 'Answers come from an AI model on the server (needs internet and '
          'accepting the rules). Ask about WPS, preheat, NACE, ASME, NDT, '
          'calculations.\n\nOffline you get the closest in-app help entry — '
          'clearly marked. Guidance only, not a substitute for the WPS.',
    );
    return ChatMessage(role: ChatRole.assistant, text: '$headline\n\n$body');
  }

  // ═════════════════════════════════════════════════════════════════════════
  // Mikrofon (oba tryby)
  // ═════════════════════════════════════════════════════════════════════════

  Future<void> _toggleMic(TextEditingController target) async {
    if (_listening) {
      await _speech.stop();
      if (mounted) setState(() => _listening = false);
      return;
    }
    final lang = context.language;
    final messenger = ScaffoldMessenger.of(context);
    final noMic = _tr(
      'Brak dostępu do mikrofonu albo rozpoznawania mowy. Wpisz polecenie '
          'albo zezwól na mikrofon w ustawieniach telefonu.',
      'No access to the microphone or speech recognition. Type the command '
          'or allow the microphone in the phone settings.',
    );
    final interrupted = _tr(
      'Rozpoznawanie przerwane — tekst zostaje, możesz go poprawić.',
      'Recognition stopped — the text stays, you can edit it.',
    );
    await _voice.stop(); // nie mówimy do własnego mikrofonu
    final ok = await _speech.initialize();
    if (!mounted) return;
    if (!ok) {
      messenger.showSnackBar(SnackBar(content: Text(noMic)));
      return;
    }
    final before = target.text.trim();
    setState(() {
      _listening = true;
      _voiceUsed = true;
    });
    await _speech.listen(
      language: lang,
      onResult: (text, isFinal) {
        if (!mounted) return;
        final joined = before.isEmpty ? text : '$before $text';
        setState(() {
          target.value = TextEditingValue(
            text: joined,
            selection: TextSelection.collapsed(offset: joined.length),
          );
        });
      },
      onDone: (error) {
        if (!mounted) return;
        setState(() => _listening = false);
        if (error != null) {
          messenger.showSnackBar(SnackBar(content: Text(interrupted)));
        }
      },
    );
  }

  Future<void> _speak(String text) async {
    if (!_history.speakReplies) return;
    await _voice.speak(text, context.language);
  }

  // ═════════════════════════════════════════════════════════════════════════
  // „Wykonaj"
  // ═════════════════════════════════════════════════════════════════════════

  void _resetAct({bool clearText = true}) {
    _pendingIntent = null;
    _pendingField = null;
    _carried = const {};
    _question = null;
    _offerServer = false;
    _offerAsk = false;
    if (clearText) {
      _cmdCtrl.clear();
      _voiceUsed = false;
    }
  }

  Future<void> _submitCommand() async {
    final text = _cmdCtrl.text.trim();
    if (text.isEmpty || _busy) return;
    if (_listening) {
      await _speech.stop();
      if (!mounted) return;
      setState(() => _listening = false);
    }
    final lang = context.language;
    setState(() {
      _busy = true;
      _notice = null;
      _offerServer = false;
      _offerAsk = false;
      _commandSoFar =
          _pendingField == null ? text : '$_commandSoFar, $text';
    });
    AssistantOutcome out;
    try {
      out = await _engine.interpret(
        text,
        lang: lang,
        carried: _carried,
        carriedIntent: _pendingIntent,
        answeringField: _pendingField,
      );
    } catch (e) {
      debugPrint('Assistant.interpret: $e');
      if (!mounted) return;
      setState(() {
        _busy = false;
        _notice = _tr('Coś poszło nie tak. Tekst zostaje — spróbuj ponownie.',
            'Something went wrong. The text stays — try again.');
        _noticeIsError = true;
      });
      return;
    }
    if (!mounted) return;
    setState(() => _busy = false);
    await _handleOutcome(out);
  }

  Future<void> _handleOutcome(AssistantOutcome out) async {
    final check = out.check;
    final lang = context.language;
    switch (check) {
      case AssistantReadyToSave(:final draft):
        setState(() {
          _question = null;
          _pendingField = null;
        });
        final confirmed = await Navigator.of(context).push<bool>(
          MaterialPageRoute(
            builder: (_) => _SaveSummaryPage(
              draft: draft,
              note: draft.sourceNote(
                  at: _now(), byVoice: _voiceUsed, lang: lang),
            ),
          ),
        );
        if (!mounted) return;
        if (confirmed == true) {
          await _save(draft);
        } else {
          // „Popraw": wraca całe polecenie (z odpowiedziami) do edycji.
          setState(() {
            _resetAct(clearText: false);
            _cmdCtrl.text = _commandSoFar;
            _notice = _tr('Nic nie zapisano. Popraw polecenie i stuknij „Dalej".',
                'Nothing saved. Edit the command and tap "Next".');
            _noticeIsError = false;
          });
        }
      case AssistantReadyToOpen(:final query):
        final tool = resolveToolQuery(query, lang);
        if (tool == null) {
          setState(() {
            _resetAct(clearText: false);
            _notice = _tr('Nie znalazłem narzędzia „$query". Spróbuj inną nazwą.',
                'No tool found for "$query". Try another name.');
            _noticeIsError = true;
          });
          return;
        }
        setState(() => _resetAct());
        await openTool(context, tool);
      case AssistantNeedsField(:final intent, :final field):
        final q = assistantQuestionFor(field, lang);
        setState(() {
          _pendingIntent = intent;
          _pendingField = field;
          _carried = out.fields;
          _question = q;
          _cmdCtrl.clear();
          _notice = out.remoteRejected != null ? _remoteRejectedText() : null;
          _noticeIsError = out.remoteRejected != null;
        });
        await _speak(q);
      case AssistantRejected(:final reason, :final field):
        setState(() {
          _resetAct(clearText: false);
          _notice = [
            _rejectText(reason, field, lang),
            if (out.remoteRejected != null) _remoteRejectedText(),
          ].join('\n');
          _noticeIsError = true;
        });
        Haptic.error();
      case null:
        setState(() {
          _resetAct(clearText: false);
          _notice = _notUnderstoodText(out);
          _noticeIsError = true;
          _offerServer = out.remoteUnavailable == RemoteUnavailableKind.notAllowed &&
              !LegalConsent.instance.isAccepted;
          _offerAsk = true;
        });
    }
  }

  DateTime _now() => (widget.now ?? DateTime.now)();

  Future<void> _save(WeldParamDraft draft) async {
    final lang = context.language;
    final messenger = ScaffoldMessenger.of(context);
    final at = _now();
    final record = draft.toWeldParam(
        id: _uuid.v4(), at: at, byVoice: _voiceUsed, lang: lang);
    try {
      await _dao.insert(record);
    } catch (e) {
      debugPrint('Assistant save failed: $e');
      if (!mounted) return;
      setState(() {
        _notice = _tr('Nie udało się zapisać — nic nie zostało zmienione.',
            'Could not save — nothing was changed.');
        _noticeIsError = true;
      });
      return;
    }
    final entry = AssistantHistoryEntry(
      id: _uuid.v4(),
      kind: kIntentSaveWeldParameter,
      summary: _summaryLine(draft, lang),
      recordId: record.id,
      at: at,
      byVoice: _voiceUsed,
    );
    await _history.add(entry);
    Haptic.saved();
    if (!mounted) return;
    final savedText = _tr(
      'Zapisano w „Parametry — rury" → Moje',
      'Saved to "Pipe parameters" → Mine',
    );
    final undoLabel = _tr('Cofnij', 'Undo');
    final undoneText = _tr('Cofnięto — rekord usunięty.', 'Undone — record removed.');
    setState(() {
      _resetAct();
      _notice = null;
    });
    unawaited(_speak(savedText));
    messenger.showSnackBar(SnackBar(
      content: Text(savedText),
      duration: const Duration(seconds: 8),
      action: SnackBarAction(
        label: undoLabel,
        onPressed: () async {
          await _dao.deleteById(entry.recordId);
          await _history.markUndone(entry.id);
          messenger.showSnackBar(SnackBar(content: Text(undoneText)));
        },
      ),
    ));
  }

  String _fieldLabel(String? field, AppLanguage lang) {
    final en = lang == AppLanguage.en;
    return switch (field) {
      'material' => en ? 'material' : 'materiał',
      'process' => en ? 'process' : 'metoda',
      'filler' => en ? 'filler' : 'drut',
      'wall_mm' => en ? 'wall thickness' : 'grubość ścianki',
      'current_a' => en ? 'current' : 'prąd',
      'diameter_mm' => en ? 'diameter' : 'średnica',
      'flow_lpm' => en ? 'gas flow' : 'przepływ gazu',
      'electrode_mm' => en ? 'electrode' : 'elektroda',
      'position' => en ? 'position' : 'pozycja',
      'gas' => en ? 'gas' : 'gaz',
      'joint' => en ? 'joint' : 'złącze',
      'query' => en ? 'tool' : 'narzędzie',
      _ => field ?? '?',
    };
  }

  String _rejectText(
      AssistantRejectReason reason, String? field, AppLanguage lang) {
    final label = _fieldLabel(field, lang);
    switch (reason) {
      case AssistantRejectReason.outOfRange:
        final r = kAssistantRanges[field];
        if (r != null) {
          final min = assistantNumber(r.min, lang);
          final max = assistantNumber(r.max, lang);
          return _tr(
            'Wartość poza zakresem: $label musi mieścić się w $min–$max ${r.unit}. Nic nie zapisano.',
            'Out of range: $label must be $min–$max ${r.unit}. Nothing saved.',
          );
        }
        return _tr('Wartość poza zakresem ($label). Nic nie zapisano.',
            'Value out of range ($label). Nothing saved.');
      case AssistantRejectReason.inconsistent:
        return _tr(
          'MIG/MAG i elektroda otulona zawsze idą ze spoiwem — „bez drutu" '
              'tu nie pasuje. Nic nie zapisano.',
          'MIG/MAG and stick always use filler — "without filler" does not '
              'fit. Nothing saved.',
        );
      case AssistantRejectReason.notAllowed:
        return _tr('Nieznana wartość ($label). Nic nie zapisano.',
            'Unknown value ($label). Nothing saved.');
      case AssistantRejectReason.unknownIntent:
      case AssistantRejectReason.extraField:
      case AssistantRejectReason.wrongType:
        return _tr(
          'Tej operacji asystent nie może wykonać ($label). Nic nie zapisano.',
          'The assistant cannot perform this operation ($label). Nothing saved.',
        );
    }
  }

  String _remoteRejectedText() => _tr(
        'Odpowiedź serwera nie przeszła kontroli aplikacji i została odrzucona.',
        'The server answer failed the app checks and was rejected.',
      );

  String _notUnderstoodText(AssistantOutcome out) {
    final base = _tr(
      'Nie rozpoznałem polecenia. Spróbuj np. „Zapisz TIG bez drutu, '
          'nierdzewka, ścianka 2 mm, 60 A" albo „Otwórz heat input".',
      'Command not recognised. Try e.g. "Save TIG without filler, stainless, '
          '2 mm wall, 60 A" or "Open heat input".',
    );
    final extra = switch (out.remoteUnavailable) {
      RemoteUnavailableKind.offline => _tr(
          'Serwer jest nieosiągalny — parser offline nie dał rady.',
          'The server is unreachable — the offline parser could not help.'),
      RemoteUnavailableKind.premiumRequired => _tr(
          'Rozpoznawanie na serwerze jest teraz w Premium.',
          'Server recognition is currently a Premium feature.'),
      RemoteUnavailableKind.dailyLimit => _tr(
          'Dzienny limit zapytań na serwerze wyczerpany — jutro znowu.',
          'Daily server limit reached — try again tomorrow.'),
      RemoteUnavailableKind.busy => _tr(
          'Asystent na serwerze chwilowo niedostępny.',
          'The server assistant is temporarily unavailable.'),
      _ => null,
    };
    return [
      base,
      if (out.remoteQuestion != null) out.remoteQuestion!,
      if (extra != null) extra,
    ].join('\n');
  }

  String _summaryLine(WeldParamDraft d, AppLanguage lang) {
    final en = lang == AppLanguage.en;
    final filler = d.filler
        ? (en ? 'with filler' : 'z drutem')
        : (en ? 'no filler' : 'bez drutu');
    final process = switch (d.process) {
      'MIG_MAG' => 'MIG/MAG',
      'MMA' => 'MMA',
      _ => d.process,
    };
    return [
      '$process $filler',
      d.material,
      't ${assistantNumber(d.wallMm, lang)} mm',
      '${assistantNumber(d.currentA, lang)} A',
      if (d.diameterMm != null) 'Ø ${assistantNumber(d.diameterMm!, lang)}',
    ].join(' · ');
  }

  Future<void> _useServer() async {
    final ok = await ensureServerConsent(context);
    if (!ok || !mounted) return;
    await _submitCommand();
  }

  void _askAsQuestion() {
    final text = _cmdCtrl.text.trim();
    setState(() {
      _mode = AssistantMode.answer;
      _inputCtrl.text = text;
      _resetAct();
      _notice = null;
    });
  }

  // ═════════════════════════════════════════════════════════════════════════
  // „Odpowiedz"
  // ═════════════════════════════════════════════════════════════════════════

  Future<void> _send() async {
    final text = _inputCtrl.text.trim();
    if (text.isEmpty || _typing.value) return;
    if (_listening) {
      await _speech.stop();
      if (!mounted) return;
      setState(() => _listening = false);
    }
    // Treść pytania wychodzi na serwer — najpierw zgoda (bez wymogu imienia).
    if (!await ensureServerConsent(context)) return;
    if (!mounted) return;

    setState(() {
      _messages.add(ChatMessage(role: ChatRole.user, text: text));
      _inputCtrl.clear();
      _voiceUsed = false;
    });
    _typing.value = true;
    _scrollToBottom();

    try {
      final sender = widget.chatSender ??
          (t, h) => AiChatService.instance.sendMessage(t, history: h);
      final reply = await sender(text, List.of(_messages));
      if (!mounted) return;
      setState(() => _messages.add(reply));
      _typing.value = false;
      _scrollToBottom();
      await _speak(reply.text);
    } catch (e) {
      debugPrint('AiChatScreen.send error: $e');
      if (!mounted) return;
      setState(() {
        _messages.add(ChatMessage(
          role: ChatRole.assistant,
          text: _tr(
              'Nie udało się pobrać odpowiedzi. Sprawdź połączenie i spróbuj ponownie.',
              "Couldn't fetch a reply. Check your connection and try again."),
        ));
      });
      _typing.value = false;
      _scrollToBottom();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(_tr('Połączenie z AI nie powiodło się.',
            'AI connection failed.')),
        duration: const Duration(seconds: 6),
        behavior: SnackBarBehavior.floating,
        backgroundColor: _kCard,
        action: SnackBarAction(
          label: _tr('Ponów', 'Retry'),
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

  Future<void> _clearChat() async {
    if (_messages.length > 1) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dctx) => AlertDialog(
          backgroundColor: _kCard,
          title: Text(
            _tr('Wyczyścić rozmowę?', 'Clear chat?'),
            style: const TextStyle(color: _kTextPrimary),
          ),
          content: Text(
            _tr(
              'Wszystkie wiadomości w tym wątku zostaną usunięte. Tej operacji nie można cofnąć.',
              'All messages in this thread will be deleted. This cannot be undone.',
            ),
            style: const TextStyle(color: _kTextSec),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dctx, false),
              child: Text(_tr('Anuluj', 'Cancel')),
            ),
            TextButton(
              onPressed: () => Navigator.pop(dctx, true),
              child: Text(
                _tr('Wyczyść', 'Clear'),
                style: const TextStyle(color: _kAccent),
              ),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
    }
    setState(() {
      _messages
        ..clear()
        ..add(_buildWelcomeMessage(context));
    });
  }

  // ═════════════════════════════════════════════════════════════════════════
  // Widok
  // ═════════════════════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kBg,
      appBar: AppBar(
        backgroundColor: _kCard,
        title: Row(
          children: [
            const Icon(Icons.record_voice_over_outlined,
                color: _kAccent, size: 20),
            const SizedBox(width: 8),
            Flexible(child: Text(_tr('Asystent', 'Assistant'))),
            if (!kAiBackendAvailable) ...[
              const SizedBox(width: 8),
              const _DemoChip(),
            ],
          ],
        ),
        actions: [
          ListenableBuilder(
            listenable: _history,
            builder: (context, _) {
              final on = _history.speakReplies;
              return IconButton(
                key: const Key('assistant-tts-toggle'),
                icon: Icon(on
                    ? Icons.volume_up_outlined
                    : Icons.volume_off_outlined),
                color: on ? _kAccent : _kTextSec,
                tooltip: on
                    ? _tr('Czytanie na głos: włączone',
                        'Read aloud: on')
                    : _tr('Czytanie na głos: wyłączone',
                        'Read aloud: off'),
                onPressed: () {
                  if (on) _voice.stop();
                  _history.setSpeakReplies(!on);
                },
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.history, color: _kTextSec),
            tooltip: _tr('Historia operacji', 'Operation history'),
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => const _HistoryPage())),
          ),
          if (_mode == AssistantMode.answer)
            IconButton(
              icon: const Icon(Icons.delete_sweep_outlined, color: _kTextSec),
              tooltip: _tr('Wyczyść rozmowę', 'Clear chat'),
              onPressed: _clearChat,
            ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
              child: SizedBox(
                width: double.infinity,
                child: SegmentedButton<AssistantMode>(
                  showSelectedIcon: false,
                  style: const ButtonStyle(
                    minimumSize: WidgetStatePropertyAll(Size(0, 52)),
                  ),
                  segments: [
                    ButtonSegment(
                      value: AssistantMode.act,
                      icon: const Icon(Icons.task_alt),
                      label: Text(_tr('Wykonaj', 'Do it'),
                          key: const Key('assistant-mode-act')),
                    ),
                    ButtonSegment(
                      value: AssistantMode.answer,
                      icon: const Icon(Icons.question_answer_outlined),
                      label: Text(_tr('Odpowiedz', 'Answer'),
                          key: const Key('assistant-mode-answer')),
                    ),
                  ],
                  selected: {_mode},
                  onSelectionChanged: (s) {
                    if (_listening) {
                      _speech.stop();
                      _listening = false;
                    }
                    setState(() => _mode = s.first);
                  },
                ),
              ),
            ),
            Expanded(
              child: _mode == AssistantMode.act
                  ? _buildActBody()
                  : _buildAnswerBody(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActBody() {
    final answering = _question != null;
    return ListView(
      padding: EdgeInsets.fromLTRB(
          12, 8, 12, 24 + MediaQuery.viewPaddingOf(context).bottom),
      children: [
        if (!answering)
          _InfoCard(
            children: [
              Text(
                _tr('Powiedz albo wpisz, co zapisać lub otworzyć.',
                    'Say or type what to save or open.'),
                style: const TextStyle(
                    color: _kTextPrimary,
                    fontSize: 15,
                    fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              for (final example in [
                _tr('Zapisz, że spawam stal nierdzewną, ściankę 2 mm, TIG bez drutu na 60 amperach',
                    'Save stainless steel, 2 mm wall, TIG without filler at 60 amps'),
                _tr('Otwórz heat input', 'Open heat input'),
              ])
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(8),
                    onTap: () => setState(() {
                      _cmdCtrl.text = example;
                      _voiceUsed = false;
                    }),
                    child: Container(
                      constraints: const BoxConstraints(minHeight: 48),
                      alignment: Alignment.centerLeft,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 8),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: _kBorder),
                      ),
                      child: Text('„$example"',
                          style: const TextStyle(
                              color: _kTextSec, fontSize: 14)),
                    ),
                  ),
                ),
              const SizedBox(height: 10),
              Text(
                _tr(
                  'Działa bez internetu. Nic nie zapisze się bez Twojego „Zapisz". '
                      'Mowę na tekst zamienia system telefonu (Google / Apple).',
                  'Works offline. Nothing is saved until you tap "Save". '
                      'Speech is turned into text by the phone system (Google / Apple).',
                ),
                style: const TextStyle(color: _kTextMut, fontSize: 12.5),
              ),
            ],
          ),
        if (answering)
          _InfoCard(
            key: const Key('assistant-question'),
            border: _kAccent,
            children: [
              Row(
                children: [
                  const Icon(Icons.help_outline, color: _kAccent),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _question!,
                      style: const TextStyle(
                          color: _kTextPrimary,
                          fontSize: 17,
                          fontWeight: FontWeight.w800),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () => setState(() => _resetAct()),
                  child: Text(_tr('Anuluj polecenie', 'Cancel command')),
                ),
              ),
            ],
          ),
        const SizedBox(height: 12),
        TextField(
          key: const Key('assistant-command'),
          controller: _cmdCtrl,
          minLines: 2,
          maxLines: 5,
          enabled: !_busy,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => _submitCommand(),
          style: const TextStyle(color: _kTextPrimary, fontSize: 16),
          decoration: InputDecoration(
            labelText: answering
                ? _tr('Odpowiedź', 'Answer')
                : _tr('Polecenie (możesz poprawić)', 'Command (you can edit it)'),
            filled: true,
            fillColor: _kCard,
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            if (_speech.isSupported) ...[
              _MicButton(
                key: const Key('assistant-mic'),
                listening: _listening,
                onPressed: _busy ? null : () => _toggleMic(_cmdCtrl),
              ),
              const SizedBox(width: 12),
            ],
            Expanded(
              child: SizedBox(
                height: 72,
                child: FilledButton.icon(
                  key: const Key('assistant-go'),
                  onPressed: _busy ? null : _submitCommand,
                  icon: _busy
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.arrow_forward),
                  label: Text(
                    _tr('Dalej', 'Next'),
                    style: const TextStyle(
                        fontSize: 18, fontWeight: FontWeight.w800),
                  ),
                ),
              ),
            ),
          ],
        ),
        if (_listening)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Row(
              children: [
                const Icon(Icons.hearing, color: _kListen),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _tr('Słucham… stuknij mikrofon, żeby zatrzymać.',
                        'Listening… tap the microphone to stop.'),
                    key: const Key('assistant-listening'),
                    style: const TextStyle(
                        color: _kListen,
                        fontSize: 15,
                        fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
          ),
        if (_notice != null) ...[
          const SizedBox(height: 12),
          _InfoCard(
            key: const Key('assistant-notice'),
            border: _noticeIsError ? _kListen : _kBorder,
            children: [
              Text(_notice!,
                  style: const TextStyle(
                      color: _kTextPrimary, fontSize: 14.5, height: 1.4)),
              if (_offerServer || _offerAsk) const SizedBox(height: 8),
              if (_offerServer)
                OutlinedButton.icon(
                  onPressed: _useServer,
                  style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(48)),
                  icon: const Icon(Icons.cloud_outlined),
                  label: Text(_tr('Rozpoznaj na serwerze (wymaga zgody)',
                      'Recognise on the server (needs consent)')),
                ),
              if (_offerAsk) ...[
                const SizedBox(height: 6),
                OutlinedButton.icon(
                  onPressed: _askAsQuestion,
                  style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(48)),
                  icon: const Icon(Icons.question_answer_outlined),
                  label: Text(_tr('Zadaj jako pytanie', 'Ask as a question')),
                ),
              ],
            ],
          ),
        ],
      ],
    );
  }

  Widget _buildAnswerBody() {
    return Column(
      children: [
        Expanded(
          child: ValueListenableBuilder<bool>(
            valueListenable: _typing,
            builder: (context, typing, _) {
              return ListView.builder(
                controller: _scrollCtrl,
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 16),
                itemCount: _messages.length + (typing ? 1 : 0),
                itemBuilder: (context, i) {
                  if (i == _messages.length && typing) {
                    return const RepaintBoundary(child: _TypingIndicator());
                  }
                  return RepaintBoundary(
                    key: ValueKey<int>(i),
                    child: _MessageBubble(message: _messages[i]),
                  );
                },
              );
            },
          ),
        ),
        if (_messages.length <= 1)
          _SuggestionStrip(onPick: (s) {
            _inputCtrl.text = s;
            _focus.requestFocus();
          }),
        if (_listening)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
            child: Text(
              _tr('Słucham… stuknij mikrofon, żeby zatrzymać.',
                  'Listening… tap the microphone to stop.'),
              style: const TextStyle(
                  color: _kListen, fontSize: 14, fontWeight: FontWeight.w700),
            ),
          ),
        RepaintBoundary(
          child: ValueListenableBuilder<bool>(
            valueListenable: _typing,
            builder: (context, typing, _) {
              return _Composer(
                controller: _inputCtrl,
                focusNode: _focus,
                onSend: _send,
                enabled: !typing,
                mic: _speech.isSupported
                    ? _MicButton(
                        listening: _listening,
                        onPressed:
                            typing ? null : () => _toggleMic(_inputCtrl),
                      )
                    : null,
              );
            },
          ),
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Podsumowanie przed zapisem
// ═══════════════════════════════════════════════════════════════════════════

class _SaveSummaryPage extends StatelessWidget {
  final WeldParamDraft draft;
  final String note;
  const _SaveSummaryPage({required this.draft, required this.note});

  @override
  Widget build(BuildContext context) {
    final lang = context.language;
    String tr(String pl, String en) => context.tr(pl: pl, en: en);
    String n(double v) => assistantNumber(v, lang);
    final notGiven = tr('nie podano', 'not given');
    final rows = <(String, String)>[
      (tr('Materiał', 'Material'), assistantMaterialLabel(draft.material, lang)),
      (tr('Metoda', 'Process'), assistantProcessLabel(draft.process, lang)),
      (
        tr('Spoiwo', 'Filler'),
        draft.filler ? tr('z drutem', 'with filler') : tr('bez drutu', 'without filler')
      ),
      (tr('Grubość ścianki', 'Wall thickness'), '${n(draft.wallMm)} mm'),
      (tr('Prąd', 'Current'), '${n(draft.currentA)} A'),
      (
        tr('Średnica', 'Diameter'),
        draft.diameterMm == null ? notGiven : '${n(draft.diameterMm!)} mm'
      ),
      if (draft.position != null) (tr('Pozycja', 'Position'), draft.position!),
      if (draft.gas != null) (tr('Gaz', 'Gas'), assistantGasLabel(draft.gas!, lang)),
      if (draft.flowLpm != null)
        (tr('Przepływ gazu', 'Gas flow'), '${n(draft.flowLpm!)} l/min'),
      if (draft.electrodeMm != null)
        (tr('Elektroda', 'Electrode'), '${n(draft.electrodeMm!)} mm'),
      if (draft.joint != null)
        (tr('Złącze', 'Joint'), assistantJointLabel(draft.joint!, lang)),
      (tr('Notatka', 'Note'), note),
    ];
    return Scaffold(
      backgroundColor: _kBg,
      appBar: AppBar(
        backgroundColor: _kCard,
        title: Text(tr('Sprawdź i zapisz', 'Check and save')),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(12),
                children: [
                  Text(
                    tr('Zapiszę dokładnie to w „Parametry — rury" → Moje:',
                        'I will save exactly this to "Pipe parameters" → Mine:'),
                    style: const TextStyle(
                        color: _kTextPrimary,
                        fontSize: 15,
                        fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 10),
                  _InfoCard(
                    children: [
                      for (final (label, value) in rows)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              SizedBox(
                                width: 130,
                                child: Text(label,
                                    style: const TextStyle(
                                        color: _kTextSec, fontSize: 14)),
                              ),
                              Expanded(
                                child: Text(value,
                                    style: const TextStyle(
                                        color: _kTextPrimary,
                                        fontSize: 16,
                                        fontWeight: FontWeight.w700)),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(
                    tr('Parametr z asystenta to pomoc — wiąże WPS / specyfikacja projektu.',
                        'Assistant parameters are guidance — the WPS / project specification is binding.'),
                    style: const TextStyle(color: _kTextMut, fontSize: 12.5),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
              child: Row(
                children: [
                  Expanded(
                    child: SizedBox(
                      height: 64,
                      child: OutlinedButton(
                        key: const Key('assistant-edit'),
                        onPressed: () => Navigator.pop(context, false),
                        child: Text(tr('Popraw', 'Edit'),
                            style: const TextStyle(fontSize: 17)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: SizedBox(
                      height: 64,
                      child: FilledButton.icon(
                        key: const Key('assistant-save'),
                        onPressed: () => Navigator.pop(context, true),
                        icon: const Icon(Icons.save_outlined),
                        label: Text(tr('Zapisz', 'Save'),
                            style: const TextStyle(
                                fontSize: 17, fontWeight: FontWeight.w800)),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Historia zatwierdzonych operacji
// ═══════════════════════════════════════════════════════════════════════════

class _HistoryPage extends StatelessWidget {
  const _HistoryPage();

  @override
  Widget build(BuildContext context) {
    final store = AssistantHistoryStore.instance;
    String tr(String pl, String en) => context.tr(pl: pl, en: en);
    String two(int v) => v.toString().padLeft(2, '0');
    return Scaffold(
      backgroundColor: _kBg,
      appBar: AppBar(
        backgroundColor: _kCard,
        title: Text(tr('Historia operacji', 'Operation history')),
      ),
      body: ListenableBuilder(
        listenable: store,
        builder: (context, _) {
          final entries = store.entries;
          if (entries.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  tr('Brak zatwierdzonych operacji. Każdy zapis z asystenta pojawi się tutaj.',
                      'No confirmed operations yet. Every assistant save shows up here.'),
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: _kTextSec),
                ),
              ),
            );
          }
          return ListView.separated(
            padding: EdgeInsets.fromLTRB(
                12, 12, 12, 12 + MediaQuery.viewPaddingOf(context).bottom),
            itemCount: entries.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (context, i) {
              final e = entries[i];
              final at =
                  '${e.at.year}-${two(e.at.month)}-${two(e.at.day)} ${two(e.at.hour)}:${two(e.at.minute)}';
              final source =
                  e.byVoice ? tr('głosowo', 'by voice') : tr('tekstem', 'typed');
              return _InfoCard(
                children: [
                  Row(
                    children: [
                      Icon(e.undone ? Icons.undo : Icons.check_circle_outline,
                          color: e.undone ? _kTextSec : _kOk),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          e.undone
                              ? tr('Zapis parametru — cofnięty',
                                  'Parameter saved — undone')
                              : tr('Zapis parametru', 'Parameter saved'),
                          style: const TextStyle(
                              color: _kTextPrimary,
                              fontWeight: FontWeight.w800),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(e.summary,
                      style:
                          const TextStyle(color: _kTextPrimary, fontSize: 15)),
                  const SizedBox(height: 4),
                  Text('$at · $source',
                      style: const TextStyle(color: _kTextMut, fontSize: 12.5)),
                ],
              );
            },
          );
        },
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Elementy wspólne
// ═══════════════════════════════════════════════════════════════════════════

class _InfoCard extends StatelessWidget {
  final List<Widget> children;
  final Color border;
  const _InfoCard({super.key, required this.children, this.border = _kBorder});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _kCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: children,
      ),
    );
  }
}

/// Mikrofon ≥ 72 dp — trafialny w rękawicy. Czerwony + „stop" w trakcie
/// nasłuchu.
class _MicButton extends StatelessWidget {
  final bool listening;
  final VoidCallback? onPressed;
  const _MicButton({super.key, required this.listening, this.onPressed});

  @override
  Widget build(BuildContext context) {
    final color = listening ? _kListen : _kAccent;
    return Semantics(
      button: true,
      label: listening
          ? context.tr(pl: 'Zatrzymaj nasłuch', en: 'Stop listening')
          : context.tr(pl: 'Mów', en: 'Speak'),
      child: SizedBox(
        width: 72,
        height: 72,
        child: Material(
          color: onPressed == null ? _kBorder : color,
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onPressed,
            child: Icon(
              listening ? Icons.stop_rounded : Icons.mic_none_rounded,
              size: 36,
              color: Colors.black,
            ),
          ),
        ),
      ),
    );
  }
}

class _DemoChip extends StatelessWidget {
  const _DemoChip();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: _kBlueSoft,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: _kBlueBubbleBorder),
      ),
      child: const Text(
        'DEMO',
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w900,
          color: _kAccentBlue,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Message bubble
/// Opens a small read-only dialog with the citation tag (e.g. "Iteration 27 §C").
void _showCitation(BuildContext context, String citation) {
  final cs = Theme.of(context).colorScheme;
  showDialog<void>(
    context: context,
    builder: (dctx) => AlertDialog(
      backgroundColor: _kCard,
      title: Row(
        children: [
          const Icon(Icons.menu_book_outlined, size: 20, color: _kAccent),
          const SizedBox(width: 8),
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
          pl: 'Cytat wskazuje sekcję bazy wiedzy albo pomocy, z której pochodzi '
              'odpowiedź.',
          en: 'The citation points to the knowledge-base or help section the '
              'answer came from.',
        ),
        style: const TextStyle(fontSize: 12, color: _kTextPrimary, height: 1.5),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dctx),
          child: const Text('OK'),
        ),
      ],
    ),
  );
}

class _MessageBubble extends StatelessWidget {
  final ChatMessage message;
  const _MessageBubble({required this.message});

  @override
  Widget build(BuildContext context) {
    final isUser = message.role == ChatRole.user;
    final isNotice = message.kind == AiReplyKind.dailyLimit ||
        message.kind == AiReplyKind.premiumRequired ||
        message.kind == AiReplyKind.unavailable;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment:
            isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        children: [
          if (!isUser)
            Container(
              width: 32,
              height: 32,
              decoration: const BoxDecoration(
                color: _kAccentSoft,
                shape: BoxShape.circle,
              ),
              child: Icon(
                  message.kind == AiReplyKind.offlineHelp
                      ? Icons.cloud_off_outlined
                      : Icons.smart_toy_outlined,
                  color: _kAccent,
                  size: 18),
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
                  color: isUser
                      ? _kBlueBubbleBorder
                      : (isNotice ? _kListen : _kBorder),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SelectableText(message.text, style: _kMessageTextStyle),
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
                                  child: Text(c, style: _kCitationTextStyle),
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
              borderRadius: BorderRadius.circular(14)
                  .copyWith(topLeft: const Radius.circular(4)),
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
      context.tr(
          pl: 'Moment śrub flange 4" Class 300',
          en: 'Bolt torque 4" Class 300 flange'),
      context.tr(pl: 'Jak zrobić saddle cut?', en: 'How to do a saddle cut?'),
    ];
    // Każdy chip ≥ 48 dp — trafialny w rękawicy.
    return SizedBox(
      height: 64,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        itemCount: suggestions.length,
        itemBuilder: (context, i) {
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
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
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
// Composer (text input + mic + send button)
// ═══════════════════════════════════════════════════════════════════════════
class _Composer extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final VoidCallback onSend;
  final bool enabled;
  final Widget? mic;
  const _Composer({
    required this.controller,
    required this.focusNode,
    required this.onSend,
    required this.enabled,
    this.mic,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      decoration: const BoxDecoration(
        color: _kCard,
        border: Border(top: BorderSide(color: _kBorder)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: TextField(
              key: const Key('assistant-question-input'),
              controller: controller,
              focusNode: focusNode,
              enabled: enabled,
              minLines: 1,
              maxLines: 4,
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => onSend(),
              style: const TextStyle(color: _kTextPrimary, fontSize: 14),
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
                  borderSide: const BorderSide(color: _kBorder),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(22),
                  borderSide: const BorderSide(color: _kBorder),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(22),
                  borderSide: const BorderSide(color: _kAccent, width: 1.2),
                ),
              ),
            ),
          ),
          if (mic != null) ...[
            const SizedBox(width: 8),
            mic!,
          ],
          const SizedBox(width: 8),
          Container(
            decoration: BoxDecoration(
              color: enabled ? _kAccent : _kBorder,
              shape: BoxShape.circle,
            ),
            child: IconButton(
              key: const Key('assistant-send'),
              icon: const Icon(Icons.send_rounded),
              color: Colors.black,
              iconSize: 28,
              tooltip: context.tr(pl: 'Wyślij', en: 'Send'),
              constraints: const BoxConstraints(minWidth: 56, minHeight: 56),
              onPressed: enabled ? onSend : null,
            ),
          ),
        ],
      ),
    );
  }
}
