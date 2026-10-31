import '../assistant/ai_clarification.dart';
import '../assistant/knowledge_question.dart';
import '../assistant/skills/core/account_sign_out_skill.dart';
import '../assistant/calculator_question_context.dart';
import '../security/credential_text.dart';
import '../assistant/navigation_plan_guard.dart';
import '../domain/iso_notebook/sketch_summary.dart';
import '../assistant/assistant_actions.dart';
import '../assistant/core/assistant_actions_port.dart';
import 'package:flutter/foundation.dart' show mapEquals;
import '../assistant/assistant_ai_client.dart';
import '../assistant/ai_execution_queue.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../assistant/assistant_engine.dart';
import '../assistant/assistant_parser.dart' show parseAssistantCommand;
import '../assistant/assistant_history.dart';
import '../assistant/assistant_intent_client.dart';
import '../assistant/assistant_intents.dart';
import '../assistant/assistant_local_ops.dart';
import '../assistant/assistant_tools.dart';
import '../assistant/assistant_validator.dart';
import '../assistant/speech_io.dart';
import '../assistant/core/brain.dart';
import '../assistant/core/command_words.dart';
import '../app_navigator.dart';
import '../assistant/core/assistant_panel_controller.dart';
import '../assistant/core/assistant_feedback_recorder.dart';
import '../feedback/complaint_detector.dart';
import '../feedback/feedback_signal.dart';
import '../assistant/core/tool_bridge.dart';
import '../assistant/skills/welder_calc/heat_input_skill.dart';
import '../assistant/skills/iso/iso_command_parser.dart';
import '../assistant/skills/iso/iso_draw_skill.dart';
import 'iso_notebook_screen.dart';
import '../assistant/core/skill.dart';
import '../assistant/skills/skill_catalog.dart';
import '../database/weld_journal_dao.dart';
import '../database/weld_param_dao.dart';
import '../domain/weld_journal/weld_defaults.dart';
import '../domain/weld_journal/weld_entry.dart';
import '../i18n/app_language.dart';
import '../models/weld_param.dart';
import '../services/ai_chat_service.dart';
import '../services/account_service.dart';
import '../services/user_profile.dart';
import '../services/legal_consent.dart';
import '../services/welder_identity.dart';
import '../theme/app_theme.dart' show kTextMut;
import '../utils/haptic.dart';
import '../widgets/community_gate.dart';
import '../widgets/tool_registry.dart';

// Asystent tekstowy i głosowy (spec 2026-08-30 §6). Dwa tryby:
//
//   • „Wykonaj" — przygotowanie DOZWOLONEJ operacji (kAssistantIntents):
//     zapis parametru spawania do „Moje parametry", wpis do dziennika spoin,
//     odczyt „Moich parametrów" (offline) albo otwarcie narzędzia. Pytanie
//     („jaki prąd na…") przechodzi do trybu „Odpowiedz" — nigdy do zapisu.
//     mowa → tekst (widoczny, edytowalny) → parser lokalny (offline) →
//     [serwer /ai/intent tylko po zgodzie, gdy parser nie dał rady] →
//     walidator → jedno pytanie przy braku pola → podsumowanie → „Zapisz" →
//     zapis lokalny → SnackBar „Zapisano" z „Cofnij". Bez „Zapisz" nic się nie
//     zapisuje.
//   • „Odpowiedz" — pytania do modelu (/ai/chat). Treść wychodzi na serwer,
//     więc przed pierwszym pytaniem bramka zgody (ensureServerConsent). Bez
//     zgody albo bez sieci — wpis z pomocy offline (lokalnie, nic nie
//     wychodzi). Do serwera idzie najwyżej 6 ostatnich wpisów rozmowy, bez
//     bieżącego pytania (chatHistoryForRequest).
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
const _kAccentChipBorder =
    Color(0x40E8C14B); // ~0.25 alpha — citation chip border
const _kAccentDot = Color(0xB3E8C14B); // ~0.70 alpha — typing dot
const _kBlueSoft = Color(0x264A9EFF); // ~0.15 alpha — user avatar
const _kBlueBubble = Color(0x2E4A9EFF); // ~0.18 alpha — user bubble fill
const _kBlueBubbleBorder =
    Color(0x4D4A9EFF); // ~0.30 alpha — user bubble border

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
typedef AssistantContextChatSender = Future<ChatMessage> Function(
    String text, List<ChatMessage> history, SketchSummary? isoSummary);

typedef AssistantChatSender = Future<ChatMessage> Function(
    String text, List<ChatMessage> history);

typedef _CalculatorActionState = ({
  ToolHandle? handle,
  String? toolId,
  Map<String, Object?>? inputs,
});

class AiChatScreen extends StatefulWidget {
  const AiChatScreen({
    super.key,
    this.initialMode = AssistantMode.act,
    this.embedded = false,
    this.speechInput,
    this.speechOutput,
    this.engine,
    this.chatSender,
    this.contextChatSender,
    this.aiInterpreter,
    this.now,
    this.welderStamp,
    this.skills,
  });

  final AssistantMode initialMode;
  final bool embedded;

  /// Rozpoznawanie mowy (domyślnie system telefonu).
  final SpeechInput? speechInput;

  /// Czytanie na głos (domyślnie flutter_tts).
  final SpeechOutput? speechOutput;

  /// Parser + walidator + ewentualnie serwer.
  final AssistantEngine? engine;

  final AssistantChatSender? chatSender;
  final AssistantContextChatSender? contextChatSender;

  /// Real cloud interpretation by default; replace transport in integration tests.
  final Future<AiCommandPlan> Function(Map<String, Object?>)? aiInterpreter;

  /// Zegar do notatki źródłowej (testy).
  final DateTime Function()? now;

  /// Stempel spawacza do wpisu w dzienniku (domyślnie tożsamość spawacza
  /// zapisana w telefonie).
  final Future<String> Function()? welderStamp;

  /// Session catalog override, for isolated integrations and previews.
  final List<AssistantSkill>? skills;

  @override
  State<AiChatScreen> createState() => _AiChatScreenState();
}

class _AiChatScreenState extends State<AiChatScreen>
    with WidgetsBindingObserver {
  final _aiQueue = AiExecutionQueue();
  final _aiHistory = <Map<String, String>>[];
  AssistantAiClient? _aiClient;
  bool _runningAiPlan = false;
  bool _aiThinking = false;
  int _aiEpoch = 0;
  int _conversationEpoch = 0;
  late final _account = AccountService.instance;
  int _sessionRevision = 0;
  StreamSubscription<UserProfile?>? _profileChanges;
  final _conversationRoutes = <Route<bool>>{};
  AssistantAiUnavailable? _aiUnavailable;
  AiClarification? _aiClarification;
  AiClarification? _knowledgeClarification;
  String? get _aiQuestion => _aiClarification?.question;
  void _rememberAi(String text, String response,
      {bool addMessages = true, AiReplyKind kind = AiReplyKind.nativeAction}) {
    String bounded(String v) {
      final safe = redactCredentialText(v);
      return safe.length <= 1000 ? safe : safe.substring(0, 1000);
    }

    if (addMessages) {
      _messages.add(ChatMessage(role: ChatRole.user, text: bounded(text)));
      _messages.add(ChatMessage(
          role: ChatRole.assistant, text: bounded(response), kind: kind));
    }
    _aiHistory.addAll([
      {'role': 'user', 'text': bounded(text)},
      {'role': 'assistant', 'text': bounded(response)}
    ]);
    if (_aiHistory.length > 6) _aiHistory.removeRange(0, _aiHistory.length - 6);
  }

  late final SpeechInput _speech = widget.speechInput ?? SystemSpeechInput();
  late final SpeechOutput _voice = widget.speechOutput ?? SystemSpeechOutput();
  late final AssistantEngine _engine =
      widget.engine ?? AssistantEngine(remoteAllowed: () async => false);
  late final _isoPort = CallbackIsoDrawingPort(
    isForeground: () =>
        appRoutes.toolId == 'iso_notebook' ||
        (!widget.embedded && IsoNotebookController.active != null),
    hasPendingQuestion: () =>
        _pendingIsoBranch != null ||
        _pendingIsoBend != null ||
        _pendingIsoValve != null ||
        _awaitingIsoChoice,
    pendingQuestion: _isoQuestion,
    summary: () => IsoNotebookController.active?.summary,
    reference: () {
      final controller=IsoNotebookController.active;
      final id=controller?.sketchId;
      return id==null ? null : IsoDrawingReference(id,controller!.revision);
    },
    acceptsReply: _acceptsIsoReply,
    acceptsProposalReply: _acceptsIsoProposalReply,
    execute: _executeIsoSkill,
  );
  AssistantActions _createActions() {
    final epoch = _conversationEpoch;
    return AssistantActions(
        parameters: _dao,
        journal: _journalDao,
        history: _history,
        now: _now,
        stamp: _stamp,
        projectContext: () => _lastProject,
        onProjectSaved: (p) {
          if (mounted && epoch == _conversationEpoch) _lastProject = p;
        });
  }

  late AssistantActions _actions = _createActions();
  AssistantBrain _createBrain() => AssistantBrain(
      skills:
          widget.skills ?? buildSkillCatalog(iso: _isoPort, actions: _actions));
  late AssistantBrain _brain = _createBrain();
  bool _collectIsoReply = false;
  bool _isoDidExecute = false;
  SkillResult? _isoSkillResult;
  AssistantText? _isoPendingText;
  List<FollowUp> _isoPendingChoices = const [];
  IsoDrawingQuestion? _isoQuestion() {
    final text = _isoPendingText;
    if (text == null) return null;
    final slot = _pendingIsoBend != null
        ? 'iso_bend'
        : _pendingIsoBranch != null
            ? 'iso_branch'
            : _pendingIsoValve != null
                ? 'iso_valve'
                : _awaitingIsoChoice
                    ? 'iso_mode'
                    : null;
    if (slot == null) return null;
    final choices = _isoPendingChoices.isNotEmpty
        ? _isoPendingChoices
        : slot == 'iso_mode'
            ? const [
                FollowUp(AssistantText('Dorysuj', 'Append'), 'append'),
                FollowUp(AssistantText('Nowy', 'New'), 'new'),
                FollowUp(AssistantText('Anuluj', 'Cancel'), 'cancel'),
              ]
            : slot == 'iso_bend' || slot == 'iso_branch'
                ? const [
                    FollowUp(AssistantText('Góra', 'Up'), 'up'),
                    FollowUp(AssistantText('Dół', 'Down'), 'down'),
                    FollowUp(AssistantText('Prawo', 'Right'), 'right'),
                    FollowUp(AssistantText('Lewo', 'Left'), 'left'),
                    FollowUp(AssistantText('Przód', 'Forward'), 'forward'),
                    FollowUp(AssistantText('Tył', 'Back'), 'back'),
                  ]
                : const <FollowUp>[];
    return IsoDrawingQuestion(slot, text, choices: choices);
  }

  bool _acceptsIsoReply(Utterance u) {
    if (const {'anuluj', 'cancel', 'stop', 'nie', 'no'}.contains(u.folded)) {
      return false;
    }
    if (_pendingIsoBend != null || _pendingIsoBranch != null) {
      return u.tokens.length <= 3 &&
          (isoDirectionOf(u) != null || isoCompassOf(u) != null);
    }
    if (_pendingIsoValve case final pending?) {
      final command = parseIsoCommand(u);
      final singleValve = command != null &&
          command.kind == IsoCommandKind.draw &&
          !command.newSketch &&
          command.steps.length == 1 &&
          command.steps.single is IsoFitting &&
          kIsoValveTools.contains((command.steps.single as IsoFitting).tool);
      return (command?.explicit != true || singleValve) &&
          pending.chooseValve(u) != null;
    }
    return _awaitingIsoChoice &&
        const {'dorysuj', 'append', 'nowy', 'new'}.contains(u.folded);
  }

  bool _acceptsIsoProposalReply(Utterance command, Utterance original) {
    if (!_acceptsIsoReply(command)) return false;
    final pending = _pendingIsoValve;
    if (pending == null) return true;
    final index =
        pending.firstWarning(IsoParseWarningKind.valveTypeMissing)?.step;
    final resolved = pending.chooseValve(command);
    if (index == null || resolved == null) return false;
    final before = pending.steps[index] as IsoFitting;
    final after = resolved.steps[index] as IsoFitting;
    if (after.dn != before.dn) {
      final name = const {
        'ballValve': 'ball',
        'gateValve': 'gate',
        'checkValve': 'check',
        'globeValve': 'globe',
        'butterflyValve': 'butterfly'
      }[after.tool];
      if (name == null) return false;
      final fromSource = pending
          .chooseValve(Utterance('$name ${original.raw}', lang: original.lang));
      if (fromSource == null ||
          (fromSource.steps[index] as IsoFitting).dn != after.dn) {
        return false;
      }
    }
    if (after.dir != before.dir && isoDirectionOf(original) != after.dir) {
      return false;
    }
    final compass = resolved.compassAt[index];
    if (compass != pending.compassAt[index] &&
        isoCompassOf(original) != compass) {
      return false;
    }
    return true;
  }

  Future<void> _isoTail = Future<void>.value();
  int _isoExecutionEpoch = -1;
  Future<SkillResult> _executeIsoSkill(Utterance u) {
    final epoch = _conversationEpoch;
    final next = _isoTail.then<SkillResult>((_) async {
      if (!mounted || epoch != _conversationEpoch) {
        return const FailedResult(
            AssistantText('Polecenie anulowane.', 'Request cancelled.'),
            reportMissingCapability: false);
      }
      _isoSkillResult = null;
      _isoDidExecute = false;
      _isoExecutionEpoch = epoch;
      _collectIsoReply = true;
      try {
        final handled = await _tryIsoCommand(u.raw, u.lang);
        if (!mounted || epoch != _conversationEpoch) {
          return const FailedResult(
              AssistantText('Polecenie anulowane.', 'Request cancelled.'),
              reportMissingCapability: false);
        }
        return _isoSkillResult ??
            (handled
                ? const AnswerResult(
                    AssistantAnswer(
                        text: AssistantText(
                            'Polecenie przekazano do Zeszytu ISO.',
                            'Command sent to the ISO notebook.')),
                    actionCompleted: false)
                : const FailedResult(
                    AssistantText('Nie rozpoznałem polecenia rysowania.',
                        'I did not recognise the drawing command.'),
                    reportMissingCapability: false));
      } finally {
        _collectIsoReply = false;
      }
    });
    _isoTail = next.then((_) {}, onError: (Object _) {});
    return next;
  }

  void _clearIsoQuestion() {
    _isoPendingText = null;
    _isoPendingChoices = const [];
    _pendingIso = null;
    _pendingIsoBend = null;
    _pendingIsoValve = null;
    _pendingIsoBranch = null;
    _awaitingIsoChoice = false;
  }

  late AssistantContext _brainContext = AssistantContext(
      lang: AppLanguage.pl,
      modules:
          widget.embedded ? ToolBridge.instance : const FixedModuleContext(),
      now: widget.now);
  SkillResult? _localResult;
  String? _pendingKnowledgeAnswer;
  UndoAction? _localUndo;
  bool _localCommitting = false;
  final _feedback = AssistantFeedbackRecorder();
  IsoCommand? _pendingIso;
  bool _awaitingIsoChoice = false;
  IsoCommand? _pendingIsoValve;
  IsoCommand? _pendingIsoBranch;
  IsoCommand? _pendingIsoBend;
  BuildContext get _navigationContext => widget.embedded
      ? (appNavigatorKey.currentState?.overlay?.context ?? context)
      : context;

  Future<void> _receiveCommand(String text) async {
    if (_busy) return;
    _cmdCtrl.text = text;
    await _submitCommand();
  }

  final _dao = WeldParamDao();
  final _journalDao = WeldJournalDao();
  final _history = AssistantHistoryStore.instance;

  late AssistantMode _mode = widget.initialMode;
  bool _listening = false;
  bool _startingMic = false;
  int _micEpoch = 0;

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

  /// [_commandSoFar] sprzed ostatniej odpowiedzi — wraca po odmowie.
  String _commandBeforeAnswer = '';

  /// Ostatni projekt dziennika (podpowiedź „ten sam" przy pytaniu o projekt).
  String _lastProject = '';

  /// Wynik „Moich parametrów" (query_my_params); null = nie pokazujemy.
  List<WeldParam>? _queryResults;
  String _queryTitle = '';
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
    _sessionRevision = _account.sessionRevision;
    _account.addListener(_accountChanged);
    _profileChanges = UserProfileService.instance.changes.listen((profile) {
      if (profile == null && mounted) _clearConversation();
    });
    _history.load();
    if (widget.embedded) {
      AssistantPanelController.instance.onCommand = _receiveCommand;
      AssistantPanelController.instance.addListener(_panelChanged);
      appRoutes.addListener(_panelChanged);
    }
  }

  void _accountChanged() {
    if (_sessionRevision == _account.sessionRevision) return;
    _sessionRevision = _account.sessionRevision;
    if (mounted) _clearConversation();
  }

  void _clearConversation() {
    _conversationEpoch++;
    for (final route in List.of(_conversationRoutes)) {
      route.navigator?.removeRoute(route, false);
    }
    _conversationRoutes.clear();
    ScaffoldMessenger.maybeOf(context)?.clearSnackBars();
    _resetAct();
    _aiClient?.close();
    _aiClient = null;
    _cancelMic();
    _voice.stop();
    _actions = _createActions();
    _brain = _createBrain();
    _brainContext = AssistantContext(
        lang: context.language,
        modules:
            widget.embedded ? ToolBridge.instance : const FixedModuleContext(),
        now: widget.now);
    setState(() {
      _aiHistory.clear();
      _messages
        ..clear()
        ..add(_buildWelcomeMessage(context));
      _inputCtrl.clear();
      _typing.value = false;
      _commandSoFar = '';
      _commandBeforeAnswer = '';
      _lastProject = '';
      _listening = false;
      _runningAiPlan = false;
      _busy = false;
      _notice = null;
      _noticeIsError = false;
      _aiUnavailable = null;
    });
  }

  void _panelChanged() {
    if (!mounted ||
        (AssistantPanelController.instance.expanded &&
            appRoutes.assistantAvailable)) {
      return;
    }
    if (_listening || _startingMic) {
      _cancelMic();
      setState(() => _listening = false);
    }
    _voice.stop();
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
      if (_listening || _startingMic) {
        _cancelMic();
        if (mounted) setState(() => _listening = false);
      }
      _voice.stop();
    }
  }

  @override
  void dispose() {
    _account.removeListener(_accountChanged);
    _profileChanges?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    if (widget.embedded) {
      AssistantPanelController.instance.onCommand = null;
      AssistantPanelController.instance.removeListener(_panelChanged);
      appRoutes.removeListener(_panelChanged);
    }
    if (_listening || _startingMic) _cancelMic();
    _voice.stop();
    _aiClient?.close();
    _aiQueue.cancel();
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

  void _cancelMic() {
    _micEpoch++;
    _startingMic = false;
    _speech.cancel();
  }

  Future<void> _toggleMic(TextEditingController target) async {
    final epoch = _conversationEpoch;
    if (_startingMic) return;
    if (_listening) {
      final micEpoch = _micEpoch;
      await _speech.stop();
      if (mounted && micEpoch == _micEpoch) {
        setState(() => _listening = false);
      }
      return;
    }
    final micEpoch = ++_micEpoch;
    _startingMic = true;
    bool current() =>
        mounted && epoch == _conversationEpoch && micEpoch == _micEpoch;
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
    bool ok;
    try {
      await _voice.stop(); // nie mówimy do własnego mikrofonu
      if (!current()) return;
      ok = await _speech.initialize();
    } catch (_) {
      ok = false;
    }
    if (!current()) return;
    _startingMic = false;
    if (!ok) {
      messenger.showSnackBar(SnackBar(content: Text(noMic)));
      return;
    }
    final before = target.text.trim();
    setState(() {
      _listening = true;
      _voiceUsed = true;
    });
    var submitted = false;
    void done(String? error) {
      if (!current()) return;
      setState(() => _listening = false);
      if (error != null) {
        messenger.showSnackBar(SnackBar(content: Text(interrupted)));
      }
    }
    try {
      await _speech.listen(
        language: lang,
        onResult: (text, isFinal) {
          if (!current() || submitted) return;
          final joined = before.isEmpty ? text : '$before $text';
          setState(() {
            target.value = TextEditingValue(
              text: joined,
              selection: TextSelection.collapsed(offset: joined.length),
            );
          });
          if (widget.embedded && isFinal && joined.trim().isNotEmpty) {
            submitted = true;
            scheduleMicrotask(() {
              if (current()) _submitCommand();
            });
          }
        },
        onDone: done,
      );
    } catch (_) {
      done('recognition_failed');
    }
  }

  Future<void> _speak(String text) async {
    if (!_history.speakReplies) return;
    await _voice.speak(text, context.language);
  }

  // ═════════════════════════════════════════════════════════════════════════
  // „Wykonaj"
  // ═════════════════════════════════════════════════════════════════════════

  void _cancelAiThinking() {
    _aiEpoch++;
    _aiQueue.cancel();
    _aiClarification = null;
    _knowledgeClarification = null;
    _aiClient?.close();
    _aiClient = null;
    setState(() {
      _aiThinking = false;
      _busy = false;
      _notice =
          _tr('Anulowano interpretację AI.', 'AI interpretation cancelled.');
      _noticeIsError = false;
    });
  }

  void _resetAct({bool clearText = true}) {
    _aiEpoch++;
    _aiThinking = false;
    _aiQueue.cancel();
    _aiClarification = null;
    _knowledgeClarification = null;
    _pendingKnowledgeAnswer = null;
    _pendingIntent = null;
    _pendingField = null;
    _carried = const {};
    _question = null;
    _offerServer = false;
    _offerAsk = false;
    _queryResults = null;
    _localResult = null;
    _localUndo = null;
    _brain.cancelPending();
    _pendingIso = null;
    _pendingIsoBend = null;
    _pendingIsoValve = null;
    _pendingIsoBranch = null;
    _awaitingIsoChoice = false;
    if (clearText) {
      _cmdCtrl.clear();
      _voiceUsed = false;
    }
  }

  static final _compoundAction = RegExp(
      r'\b(?:nastepnie|potem|pozniej|then|after that|oraz|i|and)\s+(?:mi\s+)?'
      r'(?:przypomnij|pokaz|zapisz|zachowaj|dodaj|dopisz|otworz|narysuj|'
      r'dorysuj|oblicz|policz|ustaw|zmien|usun|wyjasnij|odczytaj|uruchom|wlacz|zatrzymaj|wznow|kopiuj|skopiuj|wyczysc|wyzeruj|'
      r'show|save|add|open|draw|calculate|set|change|delete|explain|read|remind|start|pause|stop|resume|copy|clear|reset|przygotuj|eksportuj|wydrukuj|prepare|export|print|udostepnij|share)\b');

  bool _compoundNeedsAi({bool needsConsent = false}) {
    if (!mounted) return true;
    setState(() {
      _busy = false;
      _offerServer = needsConsent;
      _noticeIsError = !needsConsent;
      _notice = needsConsent
          ? _tr(
              'Polecenie zawiera kilka działań. Włącz AI, aby wykonać je po kolei. Nic nie wykonano.',
              'This request contains several actions. Enable AI to run them in order. Nothing was executed.')
          : _tr(
              'Nie można teraz zaplanować całego polecenia. Nie wykonano żadnego działania. Spróbuj ponownie lub podaj działania osobno.',
              'The complete request could not be planned. No action was executed. Retry or request each action separately.');
    });
    if (!needsConsent) _showAiFallbackNotice();
    return true;
  }

  bool _pendingReplyNeedsAi(
      {bool needsConsent = false, bool taskSwitch = false}) {
    if (!mounted) return true;
    setState(() {
      _busy = false;
      _offerServer = needsConsent;
      _noticeIsError = !needsConsent;
      _notice = taskSwitch
          ? needsConsent
              ? _tr(
                  'Włącz AI, aby zmienić zadanie. Poprzednie pytanie i dane zostają.',
                  'Enable AI to switch tasks. The previous question and inputs remain.')
              : _tr(
                  'Nie udało się zmienić zadania. Poprzednie pytanie zostaje; odpowiedz na nie albo ponów nowe polecenie.',
                  'Could not switch tasks. The previous question remains; answer it or retry the new request.')
          : needsConsent
              ? _tr(
                  'Włącz AI, aby zinterpretować tę odpowiedź, albo podaj wartość wprost. Pytanie i poprzednie dane zostają.',
                  'Enable AI to interpret this reply, or give a direct value. The question and previous inputs remain.')
              : _tr(
                  'Nie udało się zinterpretować tej odpowiedzi. Podaj wartość wprost albo spróbuj ponownie. Nie zmieniłem poprzednich danych.',
                  'Could not interpret this reply. Give a direct value or retry. Previous inputs are unchanged.');
    });
    if (!needsConsent) _showAiFallbackNotice();
    return true;
  }

  bool _boundedRequestNeedsAi({bool needsConsent = false}) {
    if (!mounted) return true;
    setState(() {
      _busy = false;
      _offerServer = needsConsent;
      _noticeIsError = !needsConsent;
      _notice = needsConsent
          ? _tr(
              'Włącz AI, aby zinterpretować to polecenie, albo podaj je wprost. Dane pozostają bez zmian.',
              'Enable AI to interpret this request, or give a direct command. Inputs remain unchanged.')
          : _tr(
              'Nie udało się zinterpretować polecenia. Ponów je albo podaj wprost. Nie wykonałem zmian.',
              'Could not interpret the request. Retry or give a direct command. Nothing was changed.');
    });
    if (!needsConsent) _showAiFallbackNotice();
    return true;
  }

  Future<bool> _tryAiCommand(String text, AppLanguage lang) async {
    final conversationEpoch = _conversationEpoch;
    final u = Utterance(text, lang: lang, byVoice: _voiceUsed);
    if (isNegatedCommand(u) ||
        referencesInstruction(u) ||
        (_isoPort.hasPendingQuestion &&
            _brain.pending?.partial.skill.id != 'iso.draw') ||
        _localResult is ConfirmResult ||
        _pendingField != null ||
        const {
          'cofnij zapis',
          'undo save',
          'anuluj',
          'cancel',
          'stop',
          'nie',
          'no'
        }.contains(u.folded)) {
      return false;
    }
    final sequence = _compoundAction.firstMatch(u.folded);
    final compound = sequence != null && sequence.start > 0;
    final currentPending = _brain.pending;
    _brainContext.lang = lang;
    final switchCandidates = compound
        ? <AssistantSkill>[]
        : _brain.aiNormalizationCandidates(u, _brainContext);
    final boundedRequest = switchCandidates.isNotEmpty;
    final supersedesPending = currentPending != null &&
        !boundedRequest &&
        _brain.requiresInterpretation(u, _brainContext);
    if (supersedesPending) {
      _aiQueue.cancel();
      _brain.cancelPending();
      _clearIsoQuestion();
      setState(() {
        _localResult = null;
        _aiClarification = null;
        _question = null;
      });
    }
    final taskSwitch = boundedRequest && currentPending != null;
    // Keep the old native question and queued remainder until AI's bounded
    // new step passes independent native validation. No cancellation on outage.
    final observedPending = supersedesPending ? null : currentPending;
    final pending = supersedesPending || boundedRequest ? null : currentPending;
    final relational = pendingReplyNeedsInterpretation(u);
    if (pending != null &&
        (_brain.canAnswerPendingDirectly(u, _brainContext) ||
            !relational && _brain.recognizesNewCommand(u, _brainContext))) {
      return false;
    }
    if (pending == null &&
        !boundedRequest &&
        !compound &&
        (_aiQuestion == null ||
            _brain.recognizesNewCommand(u, _brainContext)) &&
        _brain.recognizesLocalRequest(u, _brainContext)) {
      _aiClarification = null;
      _aiQueue.cancel();
      return false;
    }
    // Existing local write/query parsers keep native summaries and confirmations.
    final legacy = parseAssistantCommand(text).intent;
    if (pending == null &&
        !boundedRequest &&
        !compound &&
        const {
          kIntentSaveWeldParameter,
          kIntentAddWeldJournalEntry,
          kIntentQueryMyParams
        }.contains(legacy)) {
      return false;
    }
    final awaitingAiClarification =
        pending == null && _aiQuestion != null && !boundedRequest &&
        !_brain.recognizesNewCommand(u, _brainContext);
    final questionClarification = awaitingAiClarification ? _aiClarification : null;
    final executionSource = awaitingAiClarification
        ? _aiClarification!.sourceWithReply(text)
        : text;
    if (executionSource == null) {
      setState(() {
        _aiClarification = null;
        _aiHistory.clear();
        _busy = false;
        _cmdCtrl.clear();
        _notice = null;
        _localResult = FailedResult(AssistantText(
            'Doprecyzowanie jest zbyt długie. Podaj teraz całe polecenie z potrzebnymi szczegółami.',
            'This clarification is too long. Give the complete request with the necessary details now.'));
      });
      return true;
    }
    final executionTurns = awaitingAiClarification
        ? [..._aiClarification!.userTurns, text] : [text];
    await LegalConsent.instance.load();
    if (!mounted || conversationEpoch != _conversationEpoch) return true;
    if (!LegalConsent.instance.isAccepted) {
      if (observedPending != null) {
        return _pendingReplyNeedsAi(needsConsent: true, taskSwitch: taskSwitch);
      }
      if (boundedRequest || awaitingAiClarification) {
        return _boundedRequestNeedsAi(needsConsent: true);
      }
      return compound ? _compoundNeedsAi(needsConsent: true) : false;
    }
    final question =
        boundedRequest ? null : pending?.question.of(lang) ?? _aiQuestion;
    final request = assistantAiRequest(
        text: text,
        context: _brainContext,
        skills: boundedRequest
            ? switchCandidates
            : pending == null
                ? _brain.skills
                : _brain.skills.where((s) => s.id == pending.partial.skill.id),
        pendingQuestion: question?.substring(0, question.length.clamp(0, 500)),
        pendingReply: pending,
        clarification: awaitingAiClarification ? _aiClarification : null,
        history: List.of(_aiHistory));
    final consentAt = LegalConsent.instance.acceptedAt;
    final epoch = _aiEpoch;
    setState(() => _aiThinking = true);
    final originHandle = ToolBridge.instance.current;
    final originIso = IsoNotebookController.active;
    final originIsoRevision = originIso?.revision;
    final originContext = request['context'] as Map;
    AiCommandPlan plan;
    try {
      final interpret =
          widget.aiInterpreter ?? (_aiClient ??= AssistantAiClient()).interpret;
      plan = await interpret(request);
      // Validate injected transports just as strictly as real HTTP responses.
      plan = AiCommandPlan.fromJson({
        'kind': plan.kind,
        'steps': [
          for (final step in plan.steps)
            {'skill_id': step.skillId, 'command': step.command}
        ],
        'message': plan.message
      }, _brain.skills.map((s) => s.id).toSet());
      if (plan.kind == 'execute' &&
          !validNavigationPrerequisites(text, plan.steps, lang)) {
        throw const FormatException('incomplete navigation prerequisite');
      }
      if (boundedRequest &&
          (plan.kind != 'execute' ||
              plan.steps.length != 1 ||
              !switchCandidates.any((s) => s.id == plan.steps.single.skillId) ||
              !_brain.acceptsAiTaskSwitch(
                  plan.steps.single.skillId,
                  u,
                  Utterance(plan.steps.single.command,
                      lang: lang, byVoice: _voiceUsed),
                  _brainContext))) {
        throw const FormatException('unverified task switch');
      }
      if (pending != null && plan.kind == 'execute' ||
          plan.kind == 'reply' &&
              (pending == null ||
                  plan.steps.single.skillId != pending.partial.skill.id)) {
        throw const FormatException('pending reply target');
      }
    } on AssistantAiUnavailable catch (e) {
      if (epoch == _aiEpoch) _aiUnavailable = e;
      if (observedPending != null && mounted && epoch == _aiEpoch) {
        return _pendingReplyNeedsAi(taskSwitch: taskSwitch);
      }
      if ((boundedRequest || awaitingAiClarification) &&
          mounted && epoch == _aiEpoch) {
        return _boundedRequestNeedsAi();
      }
      if (compound && mounted && epoch == _aiEpoch) return _compoundNeedsAi();
      return !mounted || epoch != _aiEpoch;
    } on FormatException {
      if (observedPending != null && mounted && epoch == _aiEpoch) {
        return _pendingReplyNeedsAi(taskSwitch: taskSwitch);
      }
      if ((boundedRequest || awaitingAiClarification) &&
          mounted && epoch == _aiEpoch) {
        return _boundedRequestNeedsAi();
      }
      if (compound && mounted && epoch == _aiEpoch) return _compoundNeedsAi();
      return !mounted || epoch != _aiEpoch;
    } finally {
      if (mounted && epoch == _aiEpoch) setState(() => _aiThinking = false);
    }
    if (!mounted || epoch != _aiEpoch) return true;
    if (!LegalConsent.instance.isAccepted ||
        LegalConsent.instance.acceptedAt != consentAt) {
      setState(() {
        _busy = false;
        _notice = _tr('Zgoda na AI zmieniła się. Nie wykonano polecenia.',
            'AI consent changed. The command was not executed.');
        _noticeIsError = false;
      });
      return true;
    }
    final currentContext = assistantAiRequest(
        text: text,
        context: _brainContext,
        skills: _brain.skills)['context'] as Map;
    final isoRelevant = pending?.partial.skill.id == 'iso.draw' ||
        originContext['active_tool'] == 'iso_notebook';
    if (isoRelevant &&
            (!identical(originIso, IsoNotebookController.active) ||
                originIsoRevision != IsoNotebookController.active?.revision) ||
        !identical(originHandle, ToolBridge.instance.current) ||
        originContext['active_tool'] != currentContext['active_tool'] ||
        !mapEquals(
            originContext['inputs'] as Map, currentContext['inputs'] as Map)) {
      setState(() {
        _busy = false;
        _notice = _tr(
            'Ekran lub dane zmieniły się podczas odpowiedzi AI. Powtórz polecenie.',
            'The screen or inputs changed while AI was responding. Please repeat the request.');
        _noticeIsError = false;
      });
      return true;
    }
    if (observedPending != null &&
        !identical(observedPending, _brain.pending)) {
      return _pendingReplyNeedsAi(taskSwitch: taskSwitch);
    }
    if (plan.kind == 'reply') {
      final command =
          Utterance(plan.steps.single.command, lang: lang, byVoice: _voiceUsed);
      final reply = await _brain.answerProposal(
          expected: pending!,
          skillId: plan.steps.single.skillId,
          command: command,
          original: u,
          context: _brainContext);
      if (!mounted || conversationEpoch != _conversationEpoch) return true;
      _aiClarification = null;
      return _presentBrainReply(reply, command, text, lang, aiExecution: true);
    }
    if (pending == null) {
      _aiQueue.cancel();
      _aiClarification = null;
    }
    if (plan.kind == 'execute') {
      if (!_aiQueue.start(executionSource, plan.steps)) {
        final notice = _tr(
            'Nie mogę jednoznacznie przypisać kroków do części polecenia. Podaj je jako osobne polecenia; niczego nie zmieniłem.',
            'I cannot unambiguously match the steps to the request clauses. Give separate requests; nothing was changed.');
        setState(() {
          _busy = false;
          _cmdCtrl.clear();
          _notice = notice;
          _noticeIsError = false;
          _localResult = FailedResult(AssistantText.same(notice));
        });
        await _speak(notice);
        return true;
      }
      await _runAiPlan(lang);
      return true;
    }
    if (plan.kind == 'answer') {
      setState(() {
        if (pending != null) _commandSoFar = _commandBeforeAnswer;
        _busy = true;
        _inputCtrl.text = text;
        _cmdCtrl.clear();
      });
      try {
        await _send(questionClarification: questionClarification);
      } finally {
        if (mounted && epoch == _aiEpoch) setState(() => _busy = false);
      }
      return true;
    }
    var message = plan.message;
    if (plan.kind == 'unsupported') {
      final tool = _brainContext.modules.activeToolId;
      final reported = classifyFeedback(text, lastTurnFailed: false);
      if (reported == null || reported == FeedbackKind.notUnderstood) {
        unawaited(_feedback.missing(text, tool: tool, lang: lang));
      } else {
        // A problem report for the author: the receipt says what really
        // happened to it, whatever the model wrote.
        final sent =
            await _feedback.report(text, reported, tool: tool, lang: lang);
        if (!mounted || epoch != _aiEpoch) return true;
        if (sent != null) message = _reportReceipt(sent);
      }
    }
    _brainContext.invalidateActionReference();
    _rememberAi(text, message, kind: AiReplyKind.live);
    if (plan.kind == 'clarify') {
      _aiClarification = AiClarification(
          question: plan.message, userTurns: executionTurns);
    }
    setState(() {
      _busy = false;
      _cmdCtrl.clear();
      _question = null;
      _notice = null;
      _localResult =
          AnswerResult(AssistantAnswer(text: AssistantText.same(message)));
    });
    await _speak(message);
    return true;
  }

  /// Records an explicit problem report without a paid AI call and without
  /// touching the current module or its pending question.
  Future<void> _reportProblem(String text, AppLanguage lang) async {
    final epoch = _conversationEpoch;
    final sent = await _feedback.report(text, FeedbackKind.explicit,
        tool: _brainContext.modules.activeToolId, lang: lang);
    if (!mounted || epoch != _conversationEpoch) return;
    final message = sent == null
        ? _tr('Nie udało się zapisać zgłoszenia. Spróbuj ponownie.',
            'The report could not be saved. Please try again.')
        : _reportReceipt(sent);
    _rememberAi(text, message, kind: AiReplyKind.localDialogue);
    setState(() {
      _busy = false;
      _cmdCtrl.clear();
      _notice = null;
      _localResult = sent == null
          ? FailedResult(AssistantText.same(message))
          : AnswerResult(AssistantAnswer(text: AssistantText.same(message)));
    });
    await _speak(message);
  }

  String _reportReceipt(bool sent) => sent
      ? _tr(
          'Zapisałem zgłoszenie dla twórcy aplikacji. Dziękuję — to pomaga ją poprawić.',
          'I logged this report for the app author. Thank you — it helps improve the app.')
      : _tr(
          'Zapisałem zgłoszenie na tym telefonie. Twórca je zobaczy, gdy włączysz „Pomóż ulepszać asystenta” w ekranie Konto.',
          'I saved this report on this phone. The author will see it once you turn on "Help improve the assistant" on the Account screen.');

  _CalculatorActionState _calculatorActionState() {
    final bridge = ToolBridge.instance;
    final id = bridge.activeToolId;
    final fields = id == null ? null : bridge.inputFields(id);
    return (
      handle: bridge.current,
      toolId: id,
      inputs: fields == null ? null : Map.of(fields)
    );
  }

  bool _sameCalculatorActionState(
          _CalculatorActionState a, _CalculatorActionState b) =>
      identical(a.handle, b.handle) &&
      a.toolId == b.toolId &&
      mapEquals(a.inputs, b.inputs);

  Future<void> _runAiPlan(AppLanguage lang) async {
    if (_runningAiPlan) return;
    final epoch = _conversationEpoch;
    final consentAt = LegalConsent.instance.acceptedAt;
    _runningAiPlan = true;
    try {
      AiCommandStep? step;
      while (mounted && (step = _aiQueue.takeNext()) != null) {
        if (!LegalConsent.instance.isAccepted ||
            LegalConsent.instance.acceptedAt != consentAt) {
          _aiQueue.cancel();
          setState(() {
            _notice = _tr(
                'Zgoda na AI zmieniła się. Pozostałe kroki anulowano.',
                'AI consent changed. The remaining steps were cancelled.');
            _noticeIsError = false;
          });
          return;
        }
        final current = step!;
        final beforeAction = current.skillId == 'calculator.action'
            ? _calculatorActionState()
            : null;
        final original = _aiQueue.original!;
        final u = Utterance(current.command, lang: lang, byVoice: _voiceUsed);
        final reply = await _brain.executeProposal(
            skillId: current.skillId,
            command: u,
            original: Utterance(current.sourceClause ?? original, lang: lang, byVoice: _voiceUsed),
            context: _brainContext);
        if (!mounted || epoch != _conversationEpoch) return;
        final afterAction =
            beforeAction == null ? null : _calculatorActionState();
        final handled = await _presentBrainReply(reply, u, original, lang,
            aiExecution: true);
        if (!mounted || epoch != _conversationEpoch) return;
        if (!handled ||
            reply.result is FailedResult ||
            reply.result is AnswerResult &&
                !(reply.result as AnswerResult).actionCompleted ||
            _noticeIsError == true) {
          _aiQueue.cancel();
          if (!handled) {
            setState(() {
              _busy = false;
              _localResult = const FailedResult(AssistantText(
                  'Nie udało się wykonać tej interpretacji. Doprecyzuj polecenie.',
                  'Could not execute that interpretation. Please clarify the request.'));
            });
          }
          return;
        }
        // Copy may await a platform callback while the user switches tabs or
        // edits inputs. A later clear must never follow them to the new form.
        if (_aiQueue.hasNext &&
            beforeAction != null &&
            afterAction != null &&
            (reply.match?.slots['module_action'] == 'copy' &&
                    !_sameCalculatorActionState(beforeAction, afterAction) ||
                !_sameCalculatorActionState(
                    afterAction, _calculatorActionState()))) {
          _aiQueue.cancel();
          setState(() {
            _notice = _tr(
                'Ekran lub dane zmieniły się. Pozostałe kroki anulowano.',
                'The screen or inputs changed. The remaining steps were cancelled.');
            _noticeIsError = false;
          });
          return;
        }
        if (reply.result is AskResult || reply.result is ConfirmResult) {
          _aiQueue.pause(current.skillId);
          return;
        }
      }
    } finally {
      if (epoch == _conversationEpoch) {
        _runningAiPlan = false;
        if (mounted) setState(() => _busy = false);
      }
    }
  }

  void _showAiFallbackNotice() {
    if (!mounted || _aiUnavailable == null) return;
    final message = '${_aiUnavailable!.failure.message(context.language, commands: true)} '
        '${_tr('Polecenia lokalne nadal działają.', 'Local commands remain available.')}';
    setState(() => _notice = _notice == null ? message : '$message\n$_notice');
  }

  bool _blockCredentialInput(String text) {
    if (!containsCredentialValue(text)) return false;
    _cancelMic();
    final notice = _tr(credentialInputNoticePl, credentialInputNoticeEn);
    setState(() {
      _listening = false;
      _cmdCtrl.clear();
      _inputCtrl.clear();
      _voiceUsed = false;
      _notice = notice;
      _noticeIsError = false;
      _offerServer = false;
      _offerAsk = false;
      _messages.add(ChatMessage(
          role: ChatRole.assistant,
          text: notice,
          kind: AiReplyKind.localDialogue));
    });
    unawaited(_speak(notice));
    return true;
  }

  Future<void> _submitCommand() async {
    final text = _cmdCtrl.text.trim();
    if (text.isEmpty || _busy || _runningAiPlan) return;
    if (_blockCredentialInput(text)) return;
    final epoch = _conversationEpoch, before = _messages.length;
    try {
      await _submitCommandImpl();
    } finally {
      if (mounted &&
          epoch == _conversationEpoch &&
          _messages.length == before) {
        final response = [
          if (_question?.isNotEmpty == true) _question!,
          if (_notice?.isNotEmpty == true) _notice!,
          if (_queryResults != null)
            '${_tr('Moje parametry', 'My parameters')}: $_queryTitle (${_queryResults!.length})',
        ].join('\n');
        if (response.isNotEmpty) {
          _messages.addAll([
            ChatMessage(role: ChatRole.user, text: text),
            ChatMessage(
                role: ChatRole.assistant,
                text: response,
                kind: AiReplyKind.localDialogue),
          ]);
        }
      }
    }
  }

  Future<void> _submitCommandImpl() async {
    final epoch = _conversationEpoch;
    var text = _cmdCtrl.text.trim();
    if (text.isEmpty || _busy || _runningAiPlan) return;
    // „Ten sam" na pytanie o projekt = ostatni projekt dziennika.
    if (_pendingField == 'project' &&
        _lastProject.isNotEmpty &&
        RegExp(r'^(?:ten sam(?: projekt)?|tak|ostatni|the same|same|yes)[.!]?$',
                caseSensitive: false)
            .hasMatch(text)) {
      text = _lastProject;
    }
    if (_listening) {
      await _speech.stop();
      if (!mounted) return;
      setState(() => _listening = false);
    }
    final lang = context.language;
    setState(() {
      _busy = true;
      _pendingKnowledgeAnswer = null;
      _notice = null;
      _aiUnavailable = null;
      _offerServer = false;
      _offerAsk = false;
      _queryResults = null;
      _commandBeforeAnswer = _commandSoFar;
      _commandSoFar = _pendingField == null ? text : '$_commandSoFar, $text';
    });
    AssistantOutcome out;
    try {
      // An explicit report for the author is not a module command, even when
      // it names one („zgłoś problem: kalkulator spadku źle liczy”).
      if (_pendingField == null &&
          classifyFeedback(text, lastTurnFailed: false) ==
              FeedbackKind.explicit) {
        await _reportProblem(text, lang);
        return;
      }
      if (_pendingField == null && await _tryKnowledgeQuestion(text, lang)) {
        return;
      }
      // Negation and existing native workflows retain ownership. Unknown
      // free-form requests reach AI before generic deterministic fallbacks.
      if (_pendingField == null && await _tryAiCommand(text, lang)) return;
      if (!mounted || epoch != _conversationEpoch) return;
      // A pending legacy save owns its replies until its summary is ready.
      if (_pendingField == null && await _tryLocalCommand(text, lang)) {
        _showAiFallbackNotice();
        return;
      }
      out = await _engine.interpret(
        text,
        lang: lang,
        carried: _carried,
        carriedIntent: _pendingIntent,
        answeringField: _pendingField,
      );
    } catch (e) {
      debugPrint('Assistant.interpret: $e');
      if (!mounted || epoch != _conversationEpoch) return;
      setState(() {
        _busy = false;
        _notice = _tr('Coś poszło nie tak. Tekst zostaje — spróbuj ponownie.',
            'Something went wrong. The text stays — try again.');
        _noticeIsError = true;
      });
      return;
    }
    if (!mounted || epoch != _conversationEpoch) return;
    setState(() => _busy = false);
    await _handleOutcome(out);
    _showAiFallbackNotice();
  }

  void _isoReply(String pl, String en, {List<FollowUp> choices = const [],
      Map<String,Object?>? contextSlots}) {
    _isoPendingText = AssistantText(pl, en);
    _isoPendingChoices = List.unmodifiable(choices);
    if (_collectIsoReply && _isoExecutionEpoch == _conversationEpoch) {
      _isoSkillResult = AnswerResult(
          AssistantAnswer(text: AssistantText(pl, en)),
          actionCompleted: _isoDidExecute,
          contextSlots: contextSlots,
          followUps: choices);
      return;
    }
    if (!mounted) return;
    setState(() {
      _busy = false;
      _cmdCtrl.clear();
      _localResult = AnswerResult(AssistantAnswer(text: AssistantText(pl, en)),
          followUps: choices);
      _notice = null;
      _question = null;
    });
    _speak(_tr(pl, en));
  }

  void _askIsoValve() {
    _isoReply(
        'Jaki rodzaj zaworu w tym poleceniu? Wybierz kulowy, zasuwę, zwrotny, grzybkowy albo przepustnicę. Zachowam resztę rysunku i DN; możesz też jawnie podać nowe DN.',
        'Which valve type in this command: ball, gate, check, globe or butterfly? I will keep the rest of the drawing and DN; you may explicitly give a new DN.',
        choices: const [
          FollowUp(AssistantText('Kulowy', 'Ball'), 'ball'),
          FollowUp(AssistantText('Zasuwa', 'Gate'), 'gate'),
          FollowUp(AssistantText('Zwrotny', 'Check'), 'check'),
          FollowUp(AssistantText('Grzybkowy', 'Globe'), 'globe'),
          FollowUp(AssistantText('Przepustnica', 'Butterfly'), 'butterfly'),
          FollowUp(AssistantText('Anuluj', 'Cancel'), 'anuluj'),
        ]);
  }

  Future<bool> _tryIsoCommand(String text, AppLanguage lang) async {
    final epoch = _conversationEpoch;
    final u = Utterance(text, lang: lang, byVoice: _voiceUsed);
    _brainContext.lang = lang;
    var command = parseIsoCommand(u);
    final onIso = appRoutes.toolId == 'iso_notebook' ||
        (!widget.embedded && IsoNotebookController.active != null);
    if (_pendingIsoBend case final pending?) {
      if (const {'anuluj', 'cancel', 'stop', 'nie', 'no'}.contains(u.folded)) {
        _pendingIsoBend = null;
        _isoReply('Nic nie zmieniłem.', 'Nothing changed.');
        return true;
      }
      final direction = isoDirectionOf(u), compass = isoCompassOf(u);
      final index = pending.missingSpatialTurnDirection;
      if (index != null &&
          u.tokens.length <= 3 &&
          (direction != null || compass != null)) {
        command = pending.withSpatialTurnDirection(index, direction, compass);
        _pendingIsoBend = null;
      } else if (command?.explicit == true ||
          _brain.recognizesNewCommand(u, _brainContext,
              exceptSkillId: 'iso.draw') ||
          parseAssistantCommand(text).intent != kIntentUnknown) {
        _pendingIsoBend = null;
      } else {
        _isoReply(
            'W którą stronę skręcić kolano 45°? Podaj np. „w górę” albo „do tyłu”; możesz też powiedzieć „anuluj”.',
            'Which way should the 45° elbow turn? Say e.g. “up” or “back”, or say “cancel”.');
        return true;
      }
    }
    if (_pendingIsoBranch case final pending?) {
      if (u.hasAny(const ['anuluj', 'cancel', 'stop', 'nie', 'no']) &&
          u.tokens.length == 1) {
        _pendingIsoBranch = null;
        _isoReply('Nic nie zmieniłem.', 'Nothing changed.');
        return true;
      }
      final direction = isoDirectionOf(u);
      final compass = isoCompassOf(u);
      if (u.tokens.length <= 3 && (direction != null || compass != null)) {
        final pipe = pending.steps.first as IsoPipe;
        command = pending.copyWith(
            steps: [
              IsoPipe(dir: direction, lengthMm: pipe.lengthMm),
              ...pending.steps.skip(1)
            ],
            compassAt: compass == null
                ? pending.compassAt
                : {...pending.compassAt, 0: compass});
        _pendingIsoBranch = null;
      } else if (command?.explicit == true ||
          _brain.recognizesNewCommand(u, _brainContext,
              exceptSkillId: 'iso.draw') ||
          parseAssistantCommand(text).intent != kIntentUnknown) {
        _pendingIsoBranch = null;
      } else {
        _isoReply('Podaj kierunek odgałęzienia albo „anuluj”.',
            'Give the branch direction or say “cancel”.');
        return true;
      }
    }
    if (_pendingIsoValve case final pending?) {
      if (u.hasAny(const ['anuluj', 'cancel', 'stop', 'nie', 'no']) &&
          u.tokens.length == 1) {
        _pendingIsoValve = null;
        _pendingIsoBranch = null;
        _isoReply('Nic nie zmieniłem.', 'Nothing changed.');
        return true;
      }
      final singleValveAnswer = command != null &&
          command.kind == IsoCommandKind.draw &&
          !command.newSketch &&
          command.steps.length == 1 &&
          command.steps.single is IsoFitting &&
          kIsoValveTools.contains((command.steps.single as IsoFitting).tool);
      if (command?.explicit == true && !singleValveAnswer) {
        _pendingIsoValve = null;
        _pendingIsoBranch = null;
      } else if (!singleValveAnswer &&
          (_brain.recognizesNewCommand(u, _brainContext,
                  exceptSkillId: 'iso.draw') ||
              parseAssistantCommand(text).intent != kIntentUnknown)) {
        _pendingIsoValve = null;
        _pendingIsoBranch = null;
        return false;
      } else {
        command = pending.chooseValve(u);
        if (command == null) {
          _askIsoValve();
          return true;
        }
        _pendingIsoValve = null;
        _pendingIsoBranch = null;
      }
    }
    if (_awaitingIsoChoice) {
      final folded = u.folded;
      if (const {'anuluj', 'cancel', 'stop', 'nie', 'no'}.contains(folded)) {
        _pendingIso = null;
        _awaitingIsoChoice = false;
        _isoReply('Nic nie zmieniłem.', 'Nothing changed.');
        return true;
      }
      if (folded == 'dorysuj' ||
          folded == 'append' ||
          folded == 'nowy' ||
          folded == 'new') {
        if ((folded == 'dorysuj' || folded == 'append') &&
            _pendingIso?.kind == IsoCommandKind.newSketch) {
          _pendingIso = null;
          _awaitingIsoChoice = false;
          _isoReply('Pozostajemy na obecnym rysunku.',
              'Keeping the current drawing.');
          return true;
        }
        command = _pendingIso?.copyWith(
            newSketch: folded == 'nowy' || folded == 'new');
        _pendingIso = command;
        _awaitingIsoChoice = false;
      } else if (command == null || !command.explicit) {
        if (_brain.recognizesNewCommand(u, _brainContext,
                exceptSkillId: 'iso.draw') ||
            parseAssistantCommand(text).intent != kIntentUnknown) {
          _pendingIso = null;
          _awaitingIsoChoice = false;
          return false;
        }
        _isoReply('Powiedz „dorysuj”, „nowy” albo „anuluj”.',
            'Say "append", "new", or "cancel".');
        return true;
      } else {
        _pendingIso = null;
        _awaitingIsoChoice = false;
      }
    }
    if (command == null && onIso && u.tokens.length <= 3) {
      final dir = isoDirectionOf(u);
      final compass = isoCompassOf(u);
      if (dir != null || compass != null) {
        command = IsoCommand(
            kind: IsoCommandKind.changeLastTurn,
            turnDir: dir,
            turnCompass: compass,
            explicit: true,
            strong: true);
      }
    }
    if (command == null || (!command.explicit && !onIso)) return false;
    if (!widget.embedded &&
        AssistantPanelController.instance.onCommand != null) {
      setState(() => _busy = false);
      unawaited(AssistantPanelController.instance.submit(text));
      return true;
    }
    if (command.has(IsoParseWarningKind.invalidSymbolSize)) {
      _isoReply(
          'Nie wykonałem polecenia. Podaj jedno dodatnie DN; przy trójniku DN przelotu oraz odgałęzienia.',
          'Command not executed. Give one positive DN; for a tee give the run and branch DN.');
      return true;
    }
    if (command.has(IsoParseWarningKind.directionAmbiguous)) {
      _isoReply(
          'Nie zmieniłem rysunku. Podaj jeden kierunek dla każdego elementu; np. „w górę” albo „na północ”.',
          'Drawing unchanged. Specify one direction per element, e.g. “up” or “north”.');
      return true;
    }
    if (command.has(IsoParseWarningKind.axialDirectionRequiresPipe)) {
      _isoReply(
          'Nie zmieniłem rysunku. Zawór lub kołnierz w trasie biegnie wzdłuż rury. Jeśli trasa skręca, podaj kolano i kierunek następnej rury; sam element ustaw poleceniem „narysuj symbol…”.',
          'Drawing unchanged. An axial fitting follows its pipe. For a route turn, specify an elbow and the next pipe direction; to orient just the fitting, say “draw symbol…”.');
      return true;
    }
    final unsafe = command.warnings.where((w) =>
        w.kind != IsoParseWarningKind.lengthAssumedMeters &&
        w.kind != IsoParseWarningKind.valveTypeMissing);
    if (unsafe.isNotEmpty) {
      unawaited(_feedback.missing(text,
          tool: 'iso_notebook', skill: 'iso.unsupported', lang: lang));
      if (command.has(IsoParseWarningKind.unsupported45)) {
        _isoReply(
            'Nie zmieniłem rysunku. Trasy obsługują kolana 45° i 90°; podany inny kąt nie jest jeszcze obsługiwany.',
            'Drawing unchanged. Routes support 45° and 90° elbows; the other specified angle is not supported yet.');
      } else if (command.has(IsoParseWarningKind.unsupportedSegmentedBend)) {
        _isoReply(
            'Nie zmieniłem rysunku. Zeszyt ISO nie ma jeszcze symbolu kolana segmentowego. Jego wymiary obliczysz poleceniem „oblicz kolano segmentowe”.',
            'Drawing unchanged. The ISO notebook does not have a mitred bend symbol yet. Calculate its dimensions with “calculate mitred bend”.');
      } else {
        _isoReply(
            'Nie zmieniłem rysunku. Najpierw narysuj przelot trójnika, a kierunek gałęzi podaj osobno poleceniem „od trójnika rura…”. Sam element dodasz poleceniem „wstaw symbol trójnika DN50”.',
            'Drawing unchanged. Draw the tee run first, then specify its branch with “from the tee pipe…”. For just the fitting, say “place tee symbol DN50”.');
      }
      return true;
    }
    if (command.has(IsoParseWarningKind.valveTypeMissing)) {
      _pendingIsoValve = command;
      _askIsoValve();
      return true;
    }
    if (command.missingSpatialTurnDirection != null) {
      _pendingIsoBend = command;
      _isoReply(
          'W którą stronę skręcić kolano 45°? Podaj np. „w górę” albo „do tyłu”; możesz też powiedzieć „anuluj”.',
          'Which way should the 45° elbow turn? Say e.g. “up” or “back”, or say “cancel”.');
      return true;
    }
    if (command.fromLastTee &&
        command.steps.firstOrNull is IsoPipe &&
        (command.steps.first as IsoPipe).dir == null) {
      if (!command.compassAt.containsKey(0)) {
        _pendingIsoBranch = command;
        _isoReply(
            'W jakim kierunku ma iść odgałęzienie od trójnika? Podaj np. „w górę” albo „do tyłu”.',
            'Which direction should the branch leave the tee? Say e.g. “up” or “back”.');
        return true;
      }
    }
    var controller = onIso ? IsoNotebookController.active : null;
    if (controller == null) {
      final tool = toolById('iso_notebook')!;
      unawaited(openTool(_navigationContext, tool));
      final ready = Completer<IsoNotebookController>();
      void changed() {
        final active = IsoNotebookController.active;
        if (active != null && !ready.isCompleted) ready.complete(active);
      }

      IsoNotebookController.activeListenable.addListener(changed);
      changed();
      try {
        controller = await ready.future.timeout(const Duration(seconds: 5));
      } on TimeoutException {
        if (!mounted || epoch != _conversationEpoch) return true;
        _isoReply('Nie udało się otworzyć Zeszytu ISO. Spróbuj ponownie.',
            'Could not open the ISO notebook. Please try again.');
        return true;
      } finally {
        IsoNotebookController.activeListenable.removeListener(changed);
      }
    }
    if (!mounted || epoch != _conversationEpoch) return true;
    await controller.ready;
    if (!mounted || epoch != _conversationEpoch) return true;
    if (_pendingIso != command &&
        controller.hasContent &&
        !command.append &&
        (command.kind == IsoCommandKind.draw ||
            command.kind == IsoCommandKind.newSketch)) {
      _pendingIso = command;
      _awaitingIsoChoice = true;
      _isoReply(
          'Na arkuszu jest już rysunek. Powiedz „dorysuj” albo „nowy”. '
              '„Anuluj” pozostawi go bez zmian.',
          'There is already a drawing. Say "append" or "new". '
              '"Cancel" leaves it unchanged.');
      return true;
    }
    if (command.compassAt.isNotEmpty || command.turnCompass != null) {
      final resolved = command.newSketch
          ? null
          : command.resolveCompass(controller.dirForCompass);
      if (resolved == null) {
        _pendingIso = null;
        _isoReply(
            'Nie zmieniłem rysunku. Kierunki świata wymagają strzałki północy na docelowym arkuszu. Ustaw ją albo podaj kierunek: prawo, lewo, góra, dół, przód lub tył.',
            'Drawing unchanged. Compass directions require a north arrow on the target sheet. Place it or give a direction: right, left, up, down, forward or back.');
        return true;
      }
      command = resolved;
    }
    if(command.kind==IsoCommandKind.setRootGap) {
      final result=await controller.setRootGap(command.gapMm!,expectedRevision:controller.revision);
      if(!mounted || epoch!=_conversationEpoch) return true;
      _pendingIso=null;
      switch(result) {
        case IsoGapResult.saved:
          _isoDidExecute=true;
          _isoReply('Szczelina spoiny w szkicu: ${command.gapMm} mm. Długości CUT korzystają z tej wartości i istniejących połączeń.',
            'Drawing weld gap: ${command.gapMm} mm. CUT lengths use this value and the existing connections.',
            contextSlots:{'gap_mm':controller.rootGapMm,
              'iso_gap_sheet_id':controller.sketchId,
              'iso_gap_sheet_revision':controller.revision,
              'iso_gap_reference_generation':_brainContext.actionReferenceGeneration});
        case IsoGapResult.rejected:
          _isoReply('Nie potwierdziłem zmiany szczeliny. Rysunek zmienił się albo wartość jest poza zakresem edytora.',
            'Gap change not confirmed. The drawing changed or the value is outside the editor range.');
        case IsoGapResult.unsaved:
          _isoReply('Szczelina zmieniła się na ekranie, ale zapis rysunku nie powiódł się. Pozostaw edytor otwarty i ponów zapis.',
            'The gap changed on screen, but saving failed. Keep the editor open and retry saving.');
      }
      return true;
    }
    if (command.kind == IsoCommandKind.renameSketch) {
      final name=command.sketchName!;
      final result=await controller.renameSketch(name,expectedRevision:controller.revision);
      if(!mounted || epoch!=_conversationEpoch) return true;
      _pendingIso=null;
      switch(result) {
        case IsoNameResult.saved:
          _isoDidExecute=true;
          _isoReply('Zapisałem nazwę rysunku: $name. To ten sam szkic, z zachowaniem jego geometrii.',
            'Saved the drawing name: $name. This is the same sheet, with its geometry preserved.');
        case IsoNameResult.rejected:
          _isoReply('Nie potwierdziłem zmiany nazwy. Rysunek zmienił się podczas polecenia albo nazwa jest niepoprawna.',
            'Name change not confirmed. The drawing changed during the request or the name is invalid.');
        case IsoNameResult.unsaved:
          _isoReply('Nazwa jest zmieniona na ekranie, ale nie udało się zapisać rysunku. Pozostaw edytor otwarty i ponów zapis.',
            'The name changed on screen, but saving the drawing failed. Keep the editor open and retry saving.');
      }
      return true;
    }
    if (command.kind == IsoCommandKind.setPipeDimension) {
      final number=await controller.setPipeIsoDimension(command.dimensionMm!,
        ordinal:command.pipeOrdinal,expectedRevision:controller.revision);
      if (!mounted || epoch != _conversationEpoch) return true;
      _pendingIso=null;
      if(number==null) {
        _isoReply('Nie zmieniłem rysunku. Nie ma wskazanej rury albo rysunek zmienił się podczas polecenia. Numer oznacza kolejność rysowania rur.',
          'Drawing unchanged. The pipe was not found or the drawing changed during the request. Numbers follow pipe creation order.');
      } else {
        _isoDidExecute=true;
        _isoReply('Ustawiłem wymiar ISO rury numer $number (kolejność rysowania) na ${command.dimensionMm} mm. Połączenia i potrącenia zachowane. Możesz cofnąć zmianę.',
          'Set the ISO dimension of pipe $number (creation order) to ${command.dimensionMm} mm. Connections and take-outs preserved. You can undo this change.');
      }
      return true;
    }
    if (command.kind == IsoCommandKind.changeLastTurn) {
      final dir = command.turnDir;
      final report =
          dir == null ? null : await controller.redirectLastTurn(dir);
      if (!mounted || epoch != _conversationEpoch) return true;
      if (report == null) {
        _isoReply(
            'Nie zmieniłem rysunku. Mogę poprawić tylko ostatnie polecenie '
                'z kolanem lub odgałęzieniem, jeśli od tego czasu nie było zmian ręcznych.',
            'Drawing unchanged. I can only correct the last voice command '
                'with an elbow or branch, with no manual changes since.');
      } else if (report.ok) {
        _isoDidExecute = true;
        _isoReply(
            '${controller.lastCorrectionChangesBranchOrigin ? 'Zmieniłem kierunek odgałęzienia.' : 'Zmieniłem kierunek ostatniego kolana.'} ${report.assumedPl.join(' ')}',
            '${controller.lastCorrectionChangesBranchOrigin ? 'Changed the branch direction.' : 'Changed the last elbow direction.'} ${report.assumedEn.join(' ')}');
      } else {
        _isoReply(report.problemPl ?? 'Rysunek bez zmian.',
            report.problemEn ?? 'Drawing unchanged.');
      }
      return true;
    }
    _pendingIso = null;
    if (command.kind == IsoCommandKind.undo) {
      controller.undo();
      _isoDidExecute = true;
      _isoReply(
          'Cofnąłem ostatni krok rysunku.', 'Undid the last drawing step.');
      return true;
    }
    try {
      if (command.kind == IsoCommandKind.newSketch) {
        await controller.startNew();
        if (!mounted || epoch != _conversationEpoch) return true;
        _isoDidExecute = true;
        _isoReply('Nowy arkusz. Powiedz, co narysować.',
            'New sheet. Tell me what to draw.');
        return true;
      }
      try {
        // The conversation and structured module input share the same native
        // field contract; never replace an explicitly requested unsupported DN
        // with a remembered size in the controller.
        decodeIsoSteps(encodeIsoSteps(command.steps));
      } on FormatException {
        _isoReply(
            'Nie zmieniłem rysunku. Podaj DN z listy zeszytu oraz dodatnią długość. Kierunek samodzielnej kształtki podaj jako polecenie wstawienia symbolu.',
            'Drawing unchanged. Choose a notebook DN and a positive length. Specify a standalone fitting direction as a symbol placement command.');
        return true;
      }
      final report = await controller.draw(command.steps,
          newSketch: command.newSketch,
          fromLastTee: command.fromLastTee,
          explicitLastTee: command.explicitLastTee);
      if (!mounted || epoch != _conversationEpoch) return true;
      if (report.ok) {
        _isoDidExecute = true;
        _isoReply(
            'Narysowałem: rury ${report.segments}, kolana ${report.elbows}, '
                'kształtki ${report.fittings}. ${report.assumedPl.join(' ')}',
            'Drawn: ${report.segments} pipes, ${report.elbows} elbows, '
                '${report.fittings} fittings. ${report.assumedEn.join(' ')}');
      } else {
        if (report.problem == IsoDrawProblem.spatialFitting) {
          unawaited(_feedback.missing(text,
              tool: 'iso_notebook', skill: 'iso.spatial_fitting', lang: lang));
        }
        if (command.fromLastTee &&
            report.problem == IsoDrawProblem.invalidBranch &&
            command.steps.firstOrNull is IsoPipe) {
          final pipe = command.steps.first as IsoPipe;
          _pendingIsoBranch = command.copyWith(steps: [
            IsoPipe(lengthMm: pipe.lengthMm),
            ...command.steps.skip(1)
          ], compassAt: {
            for (final e in command.compassAt.entries)
              if (e.key != 0) e.key: e.value
          });
        }
        _isoReply(
            report.problemPl ?? 'Nie zmieniłem rysunku. Doprecyzuj polecenie.',
            report.problemEn ??
                'Drawing unchanged. Please clarify the command.');
      }
    } on StateError {
      if (!mounted || epoch != _conversationEpoch) return true;
      if (!identical(IsoNotebookController.active, controller)) {
        _isoReply(
            'Zeszyt ISO został zamknięty przed wykonaniem polecenia. Otwórz go i spróbuj ponownie.',
            'The ISO notebook closed before the command could run. Open it and try again.');
        return true;
      }
      _isoReply(
          'Nie udało się bezpiecznie rozpocząć nowego rysunku. Bieżący arkusz pozostaje otwarty. Sprawdź komunikat zapisu i spróbuj ponownie.',
          'Could not safely start the new drawing. The current sheet remains open. Check the save message and try again.');
    }
    return true;
  }

  String _confirmationCancelledNotice(ConfirmResult pending) {
    if (pending is AccountSignOutConfirmation) {
      return (_noticeIsError == true
              ? AccountSignOutConfirmation.cancelledAfterFailure
              : AccountSignOutConfirmation.cancelled)
          .of(context.language);
    }
    return _noticeIsError == true
        ? _tr('Anulowano dalsze próby. Sprawdź dane w module.',
            'Further attempts cancelled. Check the module data.')
        : _tr('Anulowano. Nic nie zapisano.', 'Cancelled. Nothing saved.');
  }

  Future<bool> _tryLocalCommand(String text, AppLanguage lang) async {
    final utterance = Utterance(text, lang: lang, byVoice: _voiceUsed);
    if (const {'cofnij zapis', 'undo save'}.contains(utterance.folded)) {
      _aiQueue.cancel();
      if (_localUndo == null) {
        setState(() {
          _busy = false;
          _notice = _tr('Nie mam zapisu do cofnięcia w tej rozmowie.',
              'There is no save to undo in this conversation.');
          _noticeIsError = false;
        });
      } else {
        await _undoLocal(fromCommand: true);
      }
      _cmdCtrl.clear();
      return true;
    }
    if (_localResult case final ConfirmResult pending) {
      if (const {'anuluj', 'nie', 'cancel', 'no', 'stop'}
          .contains(utterance.folded)) {
        final cancelled = _confirmationCancelledNotice(pending);
        setState(() {
          _resetAct();
          _busy = false;
          _notice = cancelled;
          _noticeIsError = false;
        });
        return true;
      }
      if (const {'tak', 'zapisz', 'potwierdz', 'yes', 'save', 'confirm'}
              .contains(utterance.folded) ||
          pending is AccountSignOutConfirmation &&
              const {
                'tak wyloguj',
                'potwierdz wylogowanie',
                'yes sign me out',
                'confirm sign out'
              }.contains(utterance.folded)) {
        if (pending.touchOnly) {
          setState(() {
            _busy = false;
            _cmdCtrl.clear();
            _notice = _tr('Ten zapis wymaga dotknięcia przycisku „Zapisz”.',
                'This save requires tapping the Save button.');
            _noticeIsError = false;
          });
        } else {
          await _confirmLocal(pending);
        }
        return true;
      }
      _aiQueue.cancel();
      // Any new instruction supersedes the old summary before routing it.
      _localResult = null;
    }
    _localUndo = null;
    if (isNegatedCommand(utterance)) {
      _aiQueue.cancel();
      _aiClarification = null;
      _brain.cancelPending();
      _pendingIso = null;
      _pendingIsoValve = null;
      _pendingIsoBranch = null;
      _awaitingIsoChoice = false;
      _isoReply(
          'Nie wykonuję tego polecenia.', 'I will not execute that command.');
      return true;
    }
    if (referencesInstruction(utterance)) {
      _pendingIsoValve = null;
      _pendingIsoBranch = null;
      _pendingIso = null;
      _awaitingIsoChoice = false;
    }
    _brainContext.lang = lang;
    final legacyIntent = parseAssistantCommand(text).intent;
    final calculationRequest = heatInputRequested(utterance) ||
        _brain.recognizesCalculation(utterance, _brainContext);
    if ((legacyIntent == kIntentSaveWeldParameter && !calculationRequest) ||
        legacyIntent == kIntentAddWeldJournalEntry ||
        legacyIntent == kIntentQueryMyParams) {
      if (!(_aiQueue.waiting &&
              (_aiQueue.waitingSkill?.startsWith('legacy.') ?? false)) &&
          !_brain.recognizesNewCommand(utterance, _brainContext,
              exceptSkillIds: const {
                'legacy.save',
                'legacy.journal',
                'params.saved'
              })) {
        _brain.cancelPending();
        _clearIsoQuestion();
        _localResult = null;
        return false;
      }
    }
    _brainContext.lang = lang;
    final epoch = _conversationEpoch;
    if (_aiQueue.waiting &&
        _brain.pending != null &&
        !_brain.canAnswerPendingDirectly(utterance, _brainContext) &&
        _brain.recognizesNewCommand(utterance, _brainContext)) {
      _aiQueue.cancel();
    }
    final reply = await _brain.handle(
        Utterance(text, lang: lang, byVoice: _voiceUsed), _brainContext);
    if (!mounted || epoch != _conversationEpoch) return true;
    return _presentBrainReply(reply, utterance, text, lang);
  }

  Future<bool> _presentBrainReply(
      BrainReply reply, Utterance utterance, String text, AppLanguage lang,
      {bool aiExecution = false}) async {
    if (!mounted) return true;
    final epoch = _conversationEpoch;
    final result = reply.result;
    if (reply.match?.skill.id != 'iso.draw') _clearIsoQuestion();
    if (result is NotUnderstood) return false;
    if (result is FailedResult && result.reportMissingCapability) {
      unawaited(_feedback.missing(text,
          tool: reply.match?.skill.toolId,
          skill: reply.match?.skill.id,
          lang: lang));
    }
    setState(() {
      _busy = _runningAiPlan ||
          (widget.embedded && result is AnswerResult && result.show != null);
      _localResult = result;
      _pendingKnowledgeAnswer = null;
      _aiClarification = null;
      _question = null;
      _notice = null;
      _noticeIsError = false;
      _cmdCtrl.clear();
    });
    final spoken = switch (result) {
      AnswerResult(:final answer) => answer.speechText(lang),
      ConfirmResult(:final summary) => summary.speechText(lang),
      AskResult(:final question) => question.of(lang),
      FailedResult(:final message) => message.of(lang),
      _ => '',
    };
    if (spoken.isNotEmpty) await _speak(spoken);
    if (!mounted || epoch != _conversationEpoch) return true;
    final explicitOpen = aiExecution ||
        reply.match?.skill.id == 'tool.open' ||
        reply.match?.skill.id == 'account.open' ||
        (reply.match?.skill.id.startsWith('timer.') ?? false) ||
        ((reply.match?.skill.answersQuestionsOnly ?? false) &&
            kOpenVerbAtStartRe.hasMatch(utterance.folded)) ||
        (reply.match?.skill.tier == AssistantTier.b &&
            requestsCalculation(utterance)) ||
        (reply.match?.skill.id == 'heat.input' &&
            reply.match?.slots['mode'] == 'set');
    if (mounted && result is AnswerResult && result.show != null) {
      if (widget.embedded) {
        setState(() => _busy = true);
        try {
          await _showModule(result.show!, explicit: explicitOpen);
        } finally {
          if (mounted) setState(() => _busy = false);
        }
      } else if (explicitOpen) {
        final tool = toolById(result.show!.toolId);
        if (tool != null) {
          await openTool(_navigationContext, tool, fields: result.show!.fields);
        }
      }
    }
    if (spoken.isNotEmpty) {
      _rememberAi(text, _noticeIsError ? '$spoken\n${_notice ?? ''}' : spoken);
    }
    if (!_runningAiPlan && _aiQueue.waiting) {
      if (result is FailedResult ||
          result is AnswerResult && !result.actionCompleted) {
        _aiQueue.cancel();
      } else if (_aiQueue.resolve(reply.match?.skill.id,
          completed: result is AnswerResult)) {
        await _runAiPlan(lang);
      }
    }
    return true;
  }

  Future<void> _showModule(ShowInModule show, {bool explicit = true}) async {
    final outcome = await showInModule(show, explicit: explicit);
    if (!mounted) return;
    if (outcome == ShowOutcome.timedOut ||
        outcome == ShowOutcome.unsupportedFields ||
        outcome == ShowOutcome.unavailable) {
      setState(() {
        _notice = _tr(
            'Wynik jest gotowy, ale nie udało się ustawić go w module. '
                'Spróbuj ponownie przyciskiem „Pokaż w module”.',
            'The answer is ready, but could not be applied in the module. '
                'Try again using "Show in module".');
        _noticeIsError = true;
      });
    }
  }

  Widget _localAnswerCard(SkillResult result) {
    final lang = context.language;
    final answer = switch (result) {
      AnswerResult(:final answer) => answer,
      ConfirmResult(:final summary) => summary,
      _ => null,
    };
    final question = result is AskResult ? result.question.of(lang) : null;
    final choices = switch (result) {
      AnswerResult(:final followUps) => followUps,
      AskResult(:final choices) => choices,
      _ => const <FollowUp>[],
    };
    return _InfoCard(
      key: const Key('assistant-local-answer'),
      children: [
        Semantics(
            liveRegion: true,
            child: Text(
                answer?.text.of(lang) ??
                    question ??
                    (result is FailedResult ? result.message.of(lang) : ''),
                style: const TextStyle(color: _kTextPrimary, fontSize: 16))),
        if (answer?.source case final source?) ...[
          const SizedBox(height: 8),
          Text(source.of(lang), style: const TextStyle(color: _kTextSec)),
        ],
        if (result is AnswerResult && result.show != null)
          TextButton.icon(
            key: const Key('assistant-show-module'),
            icon: const Icon(Icons.open_in_new),
            label: Text(_tr('Pokaż w module', 'Show in module')),
            onPressed: _busy
                ? null
                : () {
                    final show = result.show!;
                    final tool = toolById(show.toolId);
                    if (widget.embedded) {
                      _showModule(show);
                    } else if (tool != null) {
                      openTool(_navigationContext, tool, fields: show.fields);
                    }
                  },
          ),
        if (answer != null)
          for (var index = 0; index < answer.lines.length; index++)
            Padding(
              key: ValueKey('assistant-answer-row-$index'),
              padding: const EdgeInsets.only(top: 10),
              child: MergeSemantics(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(answer.lines[index].label.of(lang),
                        style: const TextStyle(color: _kTextSec, fontSize: 13)),
                    Text(answer.lines[index].value,
                        style: const TextStyle(
                            color: _kTextPrimary, fontSize: 16)),
                  ],
                ),
              ),
            ),
        if (choices.isNotEmpty)
          Wrap(spacing: 8, children: [
            for (final choice in choices)
              ActionChip(
                label: Text(choice.label.of(lang)),
                onPressed: _busy
                    ? null
                    : () {
                        _cmdCtrl.text = choice.utterance;
                        _voiceUsed = false;
                        _submitCommand();
                      },
              ),
          ]),
        if (result is ConfirmResult) ...[
          if (result.touchOnly)
            Text(
                _tr('Potwierdzenie tylko dotykiem.',
                    'Confirmation by touch only.'),
                key: const Key('assistant-touch-only')),
          Wrap(spacing: 8, children: [
            FilledButton(
              key: const Key('assistant-local-save'),
              onPressed: (_busy || _runningAiPlan)
                  ? null
                  : () => _confirmLocal(result),
              child: Text(result is AccountSignOutConfirmation
                  ? _tr('Wyloguj', 'Sign out')
                  : _tr('Zapisz', 'Save')),
            ),
            TextButton(
              key: const Key('assistant-local-cancel'),
              onPressed: (_busy || _runningAiPlan)
                  ? null
                  : () {
                      final cancelled = _confirmationCancelledNotice(result);
                      setState(() {
                        _resetAct();
                        _notice = cancelled;
                        _noticeIsError = false;
                      });
                    },
              child: Text(_tr('Anuluj', 'Cancel')),
            ),
          ]),
        ],
        if (_localUndo != null)
          TextButton.icon(
            key: const Key('assistant-local-undo'),
            onPressed: (_busy || _runningAiPlan) ? null : _undoLocal,
            icon: const Icon(Icons.undo),
            label: Text(_tr('Cofnij zapis', 'Undo save')),
          ),
      ],
    );
  }

  Future<void> _confirmLocal(ConfirmResult pending) async {
    if (_runningAiPlan ||
        _localCommitting ||
        !identical(_localResult, pending)) {
      return;
    }
    setState(() {
      _busy = true;
      _localCommitting = true;
      _notice = null;
      _noticeIsError = false;
    });
    var saved = false;
    final epoch = _conversationEpoch;
    try {
      final undo = await pending.perform();
      saved = true;
      if (pending is AccountSignOutConfirmation) {
        // Only a generic completion may enter the new guest conversation.
        // Never resurrect the old request/history/queue after identity changes.
        if (mounted &&
            pending.completedForCurrentGuest &&
            epoch != _conversationEpoch &&
            _messages.length == 1 &&
            !_busy &&
            !_typing.value &&
            _localResult == null) {
          final notice =
              AccountSignOutConfirmation.success.of(context.language);
          setState(() {
            _notice = notice;
            _noticeIsError = false;
            _messages.add(ChatMessage(
                role: ChatRole.assistant,
                text: notice,
                kind: AiReplyKind.localDialogue));
          });
          unawaited(_speak(notice));
        }
        return;
      }
      if (!mounted || epoch != _conversationEpoch) return;
      _rememberAi(
          _tr('Potwierdzam zapis', 'Confirm save'), _tr('Zapisano.', 'Saved.'));
      setState(() {
        _localUndo = undo;
        _localResult = AnswerResult(
            const AssistantAnswer(text: AssistantText('Zapisano.', 'Saved.')),
            show: pending.show);
        _cmdCtrl.clear();
      });
      if (pending.show case final show?) {
        if (widget.embedded) {
          await _showModule(show);
        } else if (toolById(show.toolId) case final tool?) {
          await openTool(_navigationContext, tool, fields: show.fields);
        }
      }
    } catch (_) {
      if (mounted && epoch == _conversationEpoch) {
        setState(() {
          _notice = saved
              ? _tr('Zapisano, ale nie udało się otworzyć modułu.',
                  'Saved, but the module could not be opened.')
              : pending is AccountSignOutConfirmation
                  ? AccountSignOutConfirmation.failure.of(context.language)
                  : _tr(
                      'Nie udało się potwierdzić zapisu. Sprawdź dane w module przed ponowieniem.',
                      'Could not confirm the save. Check the module before retrying.');
          _noticeIsError = true;
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          if (epoch == _conversationEpoch) _busy = false;
          _localCommitting = false;
        });
      }
    }
    if (!mounted || epoch != _conversationEpoch) return;
    if (mounted && _aiQueue.waiting && (!saved || _noticeIsError == true)) {
      _aiQueue.cancel();
    }
    if (mounted && saved && _noticeIsError != true && _aiQueue.waiting) {
      final id = _aiQueue.waitingSkill;
      if (_aiQueue.resolve(id, completed: true)) {
        await _runAiPlan(context.language);
      }
    }
  }

  Future<void> _undoLocal({bool fromCommand = false}) async {
    final epoch = _conversationEpoch;
    final undo = _localUndo;
    if (_runningAiPlan || undo == null || (_busy && !fromCommand)) return;
    setState(() => _busy = true);
    try {
      await undo();
      if (!mounted || epoch != _conversationEpoch) return;
      _rememberAi(_tr('Cofnij zapis', 'Undo save'),
          _tr('Zapis cofnięty.', 'Save undone.'));
      setState(() {
        _localUndo = null;
        _localResult = const AnswerResult(AssistantAnswer(
            text: AssistantText('Zapis cofnięty.', 'Save undone.')));
        _notice = null;
      });
    } catch (_) {
      if (mounted && epoch == _conversationEpoch) {
        setState(() {
          _notice = _tr(
              'Nie udało się cofnąć zapisu. Sprawdź, czy rekord został zmieniony.',
              'Could not undo the save. Check whether the record has changed.');
          _noticeIsError = true;
        });
      }
    } finally {
      if (mounted && epoch == _conversationEpoch) setState(() => _busy = false);
    }
  }

  Future<void> _handleOutcome(AssistantOutcome out) async {
    final epoch = _conversationEpoch;
    final check = out.check;
    final lang = context.language;
    switch (check) {
      case AssistantReadyToSave(:final draft):
        setState(() {
          _question = null;
          _pendingField = null;
        });
        final confirmed = await _showPrivateConversationPage(_SaveSummaryPage(
          draft: draft,
          note: draft.sourceNote(at: _now(), byVoice: _voiceUsed, lang: lang),
        ));
        if (!mounted || epoch != _conversationEpoch) return;
        if (confirmed == true) {
          await _save(draft);
        } else {
          // „Popraw": wraca całe polecenie (z odpowiedziami) do edycji.
          setState(() {
            _resetAct(clearText: false);
            _cmdCtrl.text = _commandSoFar;
            _notice = _tr(
                'Nic nie zapisano. Popraw polecenie i stuknij „Dalej".',
                'Nothing saved. Edit the command and tap "Next".');
            _noticeIsError = false;
          });
        }
      case AssistantReadyToAnswer(:final text):
        // Pytanie → tryb „Odpowiedz" (zgoda / pomoc offline jak zawsze).
        setState(() {
          _resetAct();
          _notice = null;
          if (!widget.embedded) _mode = AssistantMode.answer;
          _inputCtrl.text = text;
        });
        if (widget.embedded) setState(() => _busy = true);
        try {
          await _send();
        } finally {
          if (mounted && widget.embedded) setState(() => _busy = false);
        }
      case AssistantReadyToQuery(:final criteria):
        await _showMyParams(criteria);
      case AssistantReadyToJournal(:final draft):
        setState(() {
          _question = null;
          _pendingField = null;
        });
        await _prepareJournal(draft);
      case AssistantReadyToOpen(:final query):
        final tool = resolveToolQuery(query, lang);
        if (tool == null) {
          setState(() {
            _resetAct(clearText: false);
            _notice = _tr(
                'Nie znalazłem narzędzia „$query". Spróbuj inną nazwą.',
                'No tool found for "$query". Try another name.');
            _noticeIsError = true;
          });
          return;
        }
        setState(() => _resetAct());
        await openTool(_navigationContext, tool);
      case AssistantNeedsField(:final intent, :final field):
        var q = assistantQuestionFor(field, lang);
        if (field == 'project') {
          _lastProject = await loadLastWeldProject();
          if (!mounted || epoch != _conversationEpoch) return;
          if (_lastProject.isNotEmpty) {
            q = _tr('$q Powiedz „ten sam", żeby wybrać: $_lastProject.',
                '$q Say "the same" to use: $_lastProject.');
          }
        }
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
      case AssistantRejected(:final reason, :final field)
          when _pendingField != null && _pendingIntent != null:
        // Odmowa ODPOWIEDZI na pytanie: polecenie zostaje, pytamy jeszcze raz.
        setState(() {
          _commandSoFar = _commandBeforeAnswer;
          _cmdCtrl.clear();
          _notice = [
            _rejectText(reason, field, lang),
            _tr('Polecenie zostaje — odpowiedz jeszcze raz.',
                'The command stays — answer again.'),
          ].join('\n');
          _noticeIsError = true;
        });
        Haptic.error();
        if (_question != null) await _speak(_question!);
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
        if (_aiUnavailable == null) {
          unawaited(_feedback.missing(_commandSoFar,
              tool: ToolBridge.instance.activeToolId, lang: lang));
        }
        setState(() {
          _resetAct(clearText: false);
          _notice = _notUnderstoodText(out);
          _noticeIsError = true;
          _offerServer =
              out.remoteUnavailable == RemoteUnavailableKind.notAllowed &&
                  !LegalConsent.instance.isAccepted;
          _offerAsk = true;
        });
    }
  }

  DateTime _now() => (widget.now ?? DateTime.now)();

  Future<bool?> _showPrivateConversationPage(Widget page) =>
      _showPrivateConversationRoute(
          MaterialPageRoute<bool>(builder: (_) => page));

  Future<bool?> _showPrivateConversationRoute(Route<bool> route) async {
    ScaffoldMessenger.maybeOf(_navigationContext)?.clearSnackBars();
    _conversationRoutes.add(route);
    try {
      return await Navigator.of(_navigationContext).push(route);
    } finally {
      _conversationRoutes.remove(route);
    }
  }

  Future<void> _save(WeldParamDraft draft) async {
    if (_localCommitting) return;
    final epoch = _conversationEpoch;
    setState(() {
      _busy = true;
      _localCommitting = true;
    });
    try {
      final undo = await _actions.saveWeldParam(draft,
          byVoice: _voiceUsed, lang: context.language);
      if (mounted && epoch == _conversationEpoch) {
        _savedNative(undo, journal: false);
      }
    } catch (e) {
      debugPrint('Assistant native save: ${e.runtimeType}');
      if (mounted && epoch == _conversationEpoch) {
        setState(() {
          _notice = _tr(
              'Nie udało się zapisać — sprawdź dane przed ponowieniem.',
              'Could not confirm the save — check the data before retrying.');
          _noticeIsError = true;
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          if (epoch == _conversationEpoch) _busy = false;
          _localCommitting = false;
        });
      }
    }
  }

  void _savedNative(UndoAction? undo, {required bool journal}) {
    final messenger = ScaffoldMessenger.of(context);
    final saved = journal
        ? _tr('Dopisano do dziennika spoin — status „do badania"',
            'Added to the weld journal — status "pending"')
        : _tr('Zapisano w „Parametry — rury" → Moje',
            'Saved to "Pipe parameters" → Mine');
    _rememberAi(_commandSoFar, saved);
    Haptic.saved();
    setState(() {
      _resetAct();
      _notice = null;
    });
    unawaited(_speak(saved));
    messenger.showSnackBar(SnackBar(
        content: Text(saved),
        duration: const Duration(seconds: 8),
        action: undo == null
            ? null
            : SnackBarAction(
                label: _tr('Cofnij', 'Undo'),
                onPressed: () async {
                  try {
                    await undo();
                  } catch (_) {
                    messenger.showSnackBar(SnackBar(
                        content: Text(_tr(
                            'Nie udało się cofnąć — rekord został zmieniony.',
                            'Could not undo — the record has changed.'))));
                    return;
                  }
                  if (!mounted) return;
                  final text = journal
                      ? _tr('Cofnięto — wpis oznaczony jako usunięty.',
                          'Undone — the entry is marked deleted.')
                      : _tr('Cofnięto — rekord usunięty.',
                          'Undone — record removed.');
                  _rememberAi(_tr('Cofnij zapis', 'Undo save'), text);
                  messenger.showSnackBar(SnackBar(content: Text(text)));
                })));
  }

  Future<String> _stamp() async {
    final custom = widget.welderStamp;
    if (custom != null) return custom();
    try {
      return (await WelderIdentityService.instance.get())?.stamp ?? '';
    } catch (e) {
      debugPrint('Assistant: welder identity failed: $e');
      return '';
    }
  }

  /// „Jaki prąd mam zapisany na…" — odczyt „Moich parametrów", offline.
  Future<void> _showMyParams(Map<String, Object> criteria) async {
    final epoch = _conversationEpoch;
    final lang = context.language;
    List<WeldParam> all;
    try {
      all = await _dao.listAll();
    } catch (e) {
      debugPrint('Assistant query failed: $e');
      if (!mounted || epoch != _conversationEpoch) return;
      setState(() {
        _resetAct(clearText: false);
        _notice = _tr('Nie udało się odczytać zapisanych parametrów.',
            'Could not read the saved parameters.');
        _noticeIsError = true;
      });
      return;
    }
    if (!mounted || epoch != _conversationEpoch) return;
    final hits = findMyWeldParams(all, criteria);
    setState(() {
      _resetAct();
      _notice = null;
      _queryTitle = describeMyParamsQuery(criteria, lang);
      _queryResults = hits;
    });
    await _speak(hits.isEmpty
        ? _tr('Nie masz zapisanych parametrów dla: $_queryTitle.',
            'No saved parameters for: $_queryTitle.')
        : myWeldParamLine(hits.first, lang));
  }

  /// Wpis do dziennika: sprawdzenie numeru, podsumowanie, zapis po „Zapisz".
  Future<void> _prepareJournal(WeldJournalDraft draft) async {
    final epoch = _conversationEpoch;
    final lang = context.language;
    final byVoice = _voiceUsed;
    final prep =
        await _actions.prepareJournal(draft, byVoice: byVoice, lang: lang);
    if (!mounted || epoch != _conversationEpoch) return;
    switch (prep) {
      case JournalWeldNoTaken(:final project, :final weldNo, :final wps):
        final q = assistantQuestionFor('weld_no', lang);
        setState(() {
          _pendingIntent = kIntentAddWeldJournalEntry;
          _pendingField = 'weld_no';
          _carried = {'project': project, if (wps != null) 'wps': wps};
          _question = q;
          _cmdCtrl.clear();
          _notice = _tr(
              'Spoina $weldNo jest już w projekcie „$project”. Nic nie zapisano — podaj inny numer.',
              'Weld $weldNo already exists in project "$project". Nothing saved — give another number.');
          _noticeIsError = true;
        });
        Haptic.error();
        await _speak(q);
        return;
      case JournalUnavailable(:final message):
        setState(() {
          _resetAct(clearText: false);
          _notice = message.of(lang);
          _noticeIsError = true;
        });
        return;
      case PreparedJournal():
        final snapshot = prep.payload as AssistantJournalSnapshot;
        final confirmed = await _showPrivateConversationPage(
            _JournalSummaryPage(entry: snapshot.entry));
        if (!mounted || epoch != _conversationEpoch) return;
        if (confirmed != true) {
          setState(() {
            _resetAct(clearText: false);
            _cmdCtrl.text = _commandSoFar;
            _notice = _tr(
                'Nic nie zapisano. Popraw polecenie i stuknij „Dalej”.',
                'Nothing saved. Edit the command and tap "Next".');
            _noticeIsError = false;
          });
          return;
        }
        try {
          final undo =
              await _actions.saveJournal(prep, byVoice: byVoice, lang: lang);
          if (mounted && epoch == _conversationEpoch) {
            _savedNative(undo, journal: true);
          }
        } catch (_) {
          if (mounted && epoch == _conversationEpoch) {
            setState(() {
              _notice = _tr(
                  'Nie udało się potwierdzić zapisu. Dziennik mógł zostać zmieniony — sprawdź go przed ponowieniem.',
                  'Could not confirm the save. The journal may have changed — check it before retrying.');
              _noticeIsError = true;
            });
          }
        }
    }
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
      'purge_lpm' => en ? 'purge flow' : 'przepływ formowania',
      'weld_no' => en ? 'weld number' : 'numer spoiny',
      'project' => en ? 'project' : 'projekt',
      'wps' => 'WPS',
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

  Future<void> _useServer() async {
    final ok = await ensureServerConsent(_navigationContext);
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

  bool get _awaitingNativeInput =>
      _brain.pending != null ||
      _pendingField != null ||
      _localResult is ConfirmResult ||
      _isoPort.hasPendingQuestion;

  Future<bool> _tryKnowledgeQuestion(String text, AppLanguage lang) async {
    final u = Utterance(text, lang: lang, byVoice: _voiceUsed);
    _brainContext.lang = lang;
    if (isNegatedCommand(u) ||
        requestsConversationAction(u) ||
        const {'anuluj', 'cancel', 'stop', 'nie', 'no'}.contains(u.folded)) {
      _knowledgeClarification = null;
      return false;
    }
    if (_awaitingNativeInput || _aiClarification != null) return false;
    final clarification = _knowledgeClarification;
    if (clarification == null) {
      if (!isKnowledgeQuestion(u)) return false;
      if (parseAssistantCommand(text).intent == kIntentQueryMyParams) {
        return false;
      }
      // Exact numeric lookups retain the app's deterministic calculations.
      if (!isExplanationQuestion(u) &&
          _brain.recognizesCalculation(u, _brainContext) &&
          _brain.recognizesLocalRequest(u, _brainContext)) {
        return false;
      }
    }
    final epoch = _conversationEpoch;
    setState(() {
      _inputCtrl.text = text;
      _cmdCtrl.clear();
    });
    try {
      await _send(questionClarification: clarification);
    } finally {
      if (mounted && epoch == _conversationEpoch) setState(() => _busy = false);
    }
    return true;
  }


  // Knowledge is a side conversation while a native action awaits a value or
  // confirmation. Keep its question/controls and queued steps visible.
  void _appendKnowledgeReply(ChatMessage reply) {
    _messages.add(reply);
    if (!widget.embedded) return;
    if (_awaitingNativeInput) {
      _pendingKnowledgeAnswer = reply.text;
    } else {
      _pendingKnowledgeAnswer = null;
      _localResult =
          AnswerResult(AssistantAnswer(text: AssistantText.same(reply.text)));
    }
  }

  void _offerKnowledgeRetry(String text, AiClarification? clarification, int epoch) {
    var started = false;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(_tr('Nie otrzymałem odpowiedzi AI.', 'No AI answer was received.')),
      duration: const Duration(seconds: 6),
      behavior: SnackBarBehavior.floating,
      backgroundColor: _kCard,
      action: SnackBarAction(
        label: _tr('Ponów', 'Retry'), textColor: _kAccent,
        onPressed: () {
          if (started || !mounted || epoch != _conversationEpoch) return;
          started = true;
          _inputCtrl.text = text;
          unawaited(_send(questionClarification: clarification));
        },
      ),
    ));
  }

  Future<void> _send({AiClarification? questionClarification}) async {
    questionClarification ??= _knowledgeClarification;
    final epoch = _conversationEpoch;
    final text = _inputCtrl.text.trim();
    if (text.isEmpty || _typing.value) return;
    if (_blockCredentialInput(text)) return;
    if (text.length > kChatQuestionMaxChars) {
      return;
    }
    _brainContext.invalidateActionReference();
    if (_listening) {
      await _speech.stop();
      if (!mounted) return;
      setState(() => _listening = false);
    }
    // Treść pytania wychodzi na serwer — najpierw zgoda (bez wymogu imienia).
    // Bez zgody: pomoc offline z aplikacji, NIC nie wychodzi z telefonu.
    final consented = await ensureServerConsent(_navigationContext);
    if (!mounted || epoch != _conversationEpoch) return;

    // Historia BEZ bieżącego pytania, najwyżej 6 ostatnich wpisów.
    final history = chatHistoryForRequest(_messages);
    setState(() {
      _messages.add(ChatMessage(role: ChatRole.user, text: text));
      _inputCtrl.clear();
      _voiceUsed = false;
    });

    if (!consented) {
      final offline = AiChatService.instance.offlineReply(questionClarification?.sourceWithReply(text) ?? text);
      setState(() {
        _appendKnowledgeReply(offline);
      });
      _scrollToBottom();
      await _speak(offline.text);
      return;
    }

    _typing.value = true;
    _scrollToBottom();

    try {
      final iso = _isoPort.isForeground ? IsoNotebookController.active : null;
      final summary = iso?.summary;
      final revision = iso?.revision;
      final calculatorHandle = ToolBridge.instance.current;
      final calculatorContext =
          CalculatorQuestionContext.capture(_brainContext.modules);
      final reply = widget.contextChatSender != null
          ? await widget.contextChatSender!(text, history, summary)
          : widget.chatSender != null
              ? await widget.chatSender!(text, history)
              : await AiChatService.instance.sendMessage(text,
                  history: history,
                  isoSummary: summary,
                  calculatorContext: calculatorContext,
                  questionClarification: questionClarification);
      if (!mounted || epoch != _conversationEpoch) return;
      if (calculatorContext != null) {
        final current =
            CalculatorQuestionContext.capture(_brainContext.modules);
        if (!identical(calculatorHandle, ToolBridge.instance.current) ||
            calculatorContext.toolId != current?.toolId ||
            !mapEquals(calculatorContext.inputs, current?.inputs) ||
            !mapEquals(calculatorContext.results, current?.results)) {
          final notice = _tr(
              'Kalkulator lub dane zmieniły się podczas przygotowywania odpowiedzi. Zapytaj ponownie o aktualny stan.',
              'The calculator or inputs changed while the answer was being prepared. Ask again about the current state.');
          setState(() {
            _appendKnowledgeReply(ChatMessage(
                role: ChatRole.assistant,
                text: notice,
                kind: AiReplyKind.localDialogue));
            _typing.value = false;
          });
          await _speak(notice);
          return;
        }
      }
      if (summary != null &&
          (!_isoPort.isForeground ||
              !identical(iso, IsoNotebookController.active) ||
              iso!.revision != revision)) {
        final notice = _tr(
            'Rysunek zmienił się podczas przygotowywania odpowiedzi. Zapytaj ponownie o aktualny stan.',
            'The drawing changed while the answer was being prepared. Ask again about its current state.');
        setState(() {
          _appendKnowledgeReply(ChatMessage(
              role: ChatRole.assistant,
              text: notice,
              kind: AiReplyKind.localDialogue));
          _typing.value = false;
        });
        _scrollToBottom();
        await _speak(notice);
        return;
      }
      setState(() {
        if (reply.kind == AiReplyKind.live) {
          _knowledgeClarification = reply.needsClarification
              ? AiClarification(
                  question: reply.text,
                  userTurns: [...?questionClarification?.userTurns, text])
              : null;
        }
        _appendKnowledgeReply(reply);
      });
      if (reply.kind == AiReplyKind.live) {
        _rememberAi(text, reply.text,
            addMessages: false, kind: AiReplyKind.live);
      }
      _typing.value = false;
      if (questionClarification != null &&
          const {AiReplyKind.unavailable, AiReplyKind.offlineHelp}.contains(reply.kind)) {
        _offerKnowledgeRetry(text, questionClarification, epoch);
      }
      _scrollToBottom();
      await _speak(reply.text);
    } catch (e) {
      debugPrint('AiChatScreen.send error: $e');
      if (!mounted || epoch != _conversationEpoch) return;
      setState(() {
        _appendKnowledgeReply(ChatMessage(
          role: ChatRole.assistant,
          text: _tr(
              'Nie udało się pobrać odpowiedzi. Sprawdź połączenie i spróbuj ponownie.',
              "Couldn't fetch a reply. Check your connection and try again."),
          kind: AiReplyKind.unavailable,
        ));
      });
      _typing.value = false;
      _scrollToBottom();
      _offerKnowledgeRetry(text, questionClarification, epoch);
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
    final epoch = _conversationEpoch;
    if (_messages.length > 1) {
      final confirmed = await _showPrivateConversationRoute(DialogRoute<bool>(
        context: _navigationContext,
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
      ));
      if (confirmed != true || !mounted || epoch != _conversationEpoch) return;
    }
    _clearConversation();
  }

  Future<void> _openConversation() async {
    if (_busy || _runningAiPlan || _typing.value || _listening) return;
    FocusManager.instance.primaryFocus?.unfocus();
    final messages = List<ChatMessage>.unmodifiable(_messages);
    // Read-only view: no second engine, provider request or native action.
    // Like record summaries, this private snapshot closes on a session change.
    await _showPrivateConversationPage(_ConversationPage(
      messages: messages,
      onClear: _clearChat,
    ));
  }

  // ═════════════════════════════════════════════════════════════════════════
  // Widok
  // ═════════════════════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    if (widget.embedded) return _buildEmbedded();
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
                icon: Icon(
                    on ? Icons.volume_up_outlined : Icons.volume_off_outlined),
                color: on ? _kAccent : _kTextSec,
                tooltip: on
                    ? _tr('Czytanie na głos: włączone', 'Read aloud: on')
                    : _tr('Czytanie na głos: wyłączone', 'Read aloud: off'),
                onPressed: () async {
                  if (on) _voice.stop();
                  final saved = await _history.setSpeakReplies(!on);
                  if (!mounted || saved) return;
                  ScaffoldMessenger.of(this.context).showSnackBar(SnackBar(
                    content: Text(_tr(
                      'Czytanie zmieniono w tej sesji. Nie udało się zapisać ustawienia na później.',
                      'Read-aloud changed for this session. Could not save the preference for later.',
                    )),
                  ));
                },
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.history, color: _kTextSec),
            tooltip: _tr('Historia operacji', 'Operation history'),
            onPressed: () => Navigator.of(_navigationContext)
                .push(MaterialPageRoute(builder: (_) => const _HistoryPage())),
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
                    _cancelMic();
                    _listening = false;
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

  Widget _buildEmbedded() => Column(children: [
        Expanded(
            child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                children: [
              if (_pendingKnowledgeAnswer != null)
                Text(_pendingKnowledgeAnswer!, key: const Key('assistant-side-answer')),
              if (_localResult case final result?) _localAnswerCard(result),
              if (_question != null) Text(_question!),
              if (_notice != null) Text(_notice!),
              if (_queryResults != null) ...[
                Text(_tr('Moje parametry: $_queryTitle',
                    'My parameters: $_queryTitle')),
                if (_queryResults!.isEmpty)
                  Text(_tr(
                      'Brak zapisanych parametrów.', 'No saved parameters.')),
                for (final p in _queryResults!)
                  Text(myWeldParamLine(p, context.language)),
              ],
              if (_localResult == null && _question == null && _notice == null)
                Text(_tr(
                    'Powiedz np. „narysuj rura metr kolano w górę rura metr” '
                        'albo zapytaj o wymiar.',
                    'Say e.g. "draw pipe one metre elbow up pipe one metre", or ask a dimension.')),
              if (_listening)
                Text(_tr('Słucham…', 'Listening…'),
                    key: const Key('assistant-listening')),
            ])),
        Padding(
            padding: const EdgeInsets.all(8),
            child: Row(children: [
              ValueListenableBuilder<bool>(
                  valueListenable: _typing,
                  builder: (context, typing, _) => SizedBox.square(
                      dimension: 48,
                      child: IconButton(
                          key: const Key('assistant-conversation'),
                          tooltip:
                              _tr('Bieżąca rozmowa', 'Current conversation'),
                          onPressed:
                              _busy || _runningAiPlan || typing || _listening
                                  ? null
                                  : _openConversation,
                          icon: const Icon(Icons.forum_outlined)))),
              if (_speech.isSupported)
                SizedBox(
                    width: 56,
                    height: 56,
                    child: IconButton(
                        key: const Key('assistant-mic'),
                        tooltip: _tr('Powiedz polecenie', 'Speak a command'),
                        onPressed: _busy ? null : () => _toggleMic(_cmdCtrl),
                        icon: Icon(_listening ? Icons.stop : Icons.mic))),
              Expanded(
                  child: TextField(
                      key: const Key('assistant-command'),
                      controller: _cmdCtrl,
                      enabled: !_busy,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _submitCommand(),
                      decoration: InputDecoration(
                          labelText:
                              _tr('Co mam zrobić?', 'What should I do?')))),
              SizedBox(
                  width: 56,
                  height: 56,
                  child: IconButton(
                      key: const Key('assistant-go'),
                      tooltip: _aiThinking
                          ? _tr('Anuluj AI', 'Cancel AI')
                          : _tr('Wykonaj', 'Execute'),
                      onPressed: _aiThinking
                          ? _cancelAiThinking
                          : _busy
                              ? null
                              : _submitCommand,
                      icon: _aiThinking
                          ? const Icon(Icons.stop)
                          : _busy
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child:
                                      CircularProgressIndicator(strokeWidth: 2))
                              : const Icon(Icons.send))),
            ])),
      ]);

  Widget _buildActBody() {
    final answering = _question != null;
    return ListView(
      padding: EdgeInsets.fromLTRB(
          12, 8, 12, 24 + MediaQuery.viewPaddingOf(context).bottom),
      children: [
        if (_localResult case final result?) ...[
          _localAnswerCard(result),
          const SizedBox(height: 12),
        ],
        if (!answering && _localResult == null)
          _InfoCard(
            children: [
              Text(
                _tr('Powiedz, co mam zrobić w aplikacji.',
                    'Tell me what to do in the app.'),
                style: const TextStyle(
                    color: _kTextPrimary,
                    fontSize: 15,
                    fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              for (final example in [
                _tr('Zapisz, że spawam stal nierdzewną, ściankę 2 mm, TIG bez drutu na 60 amperach',
                    'Save stainless steel, 2 mm wall, TIG without filler at 60 amps'),
                _tr('Jaka jest średnica rury DN40?',
                    'What is the outside diameter of DN40?'),
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
                          style:
                              const TextStyle(color: _kTextSec, fontSize: 14)),
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
                : _tr(
                    'Polecenie (możesz poprawić)', 'Command (you can edit it)'),
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
        if (_queryResults != null) ...[
          const SizedBox(height: 12),
          _InfoCard(
            key: const Key('assistant-query-results'),
            children: [
              Text(
                _tr('Moje parametry: $_queryTitle',
                    'My parameters: $_queryTitle'),
                style: const TextStyle(
                    color: _kTextPrimary,
                    fontSize: 15,
                    fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 8),
              if (_queryResults!.isEmpty)
                Text(
                  _tr('Nic nie znalazłem w „Parametry — rury" → Moje.',
                      'Nothing found in "Pipe parameters" → Mine.'),
                  style: const TextStyle(color: _kTextSec, fontSize: 14.5),
                ),
              for (final p in _queryResults!)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Text(myWeldParamLine(p, context.language),
                      style: const TextStyle(
                          color: _kTextPrimary,
                          fontSize: 15.5,
                          fontWeight: FontWeight.w600)),
                ),
              const SizedBox(height: 6),
              Text(
                _tr('Tylko odczyt — nic nie zmieniono.',
                    'Read only — nothing was changed.'),
                style: const TextStyle(color: _kTextMut, fontSize: 12.5),
              ),
            ],
          ),
        ],
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
                        onPressed: typing ? null : () => _toggleMic(_inputCtrl),
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
      (
        tr('Materiał', 'Material'),
        assistantMaterialLabel(draft.material, lang)
      ),
      (tr('Metoda', 'Process'), assistantProcessLabel(draft.process, lang)),
      (
        tr('Spoiwo', 'Filler'),
        draft.filler
            ? tr('z drutem', 'with filler')
            : tr('bez drutu', 'without filler')
      ),
      (tr('Grubość ścianki', 'Wall thickness'), '${n(draft.wallMm)} mm'),
      (tr('Prąd', 'Current'), '${n(draft.currentA)} A'),
      (
        tr('Średnica', 'Diameter'),
        draft.diameterMm == null ? notGiven : '${n(draft.diameterMm!)} mm'
      ),
      if (draft.position != null) (tr('Pozycja', 'Position'), draft.position!),
      if (draft.gas != null)
        (tr('Gaz', 'Gas'), assistantGasLabel(draft.gas!, lang)),
      if (draft.flowLpm != null)
        (tr('Przepływ gazu', 'Gas flow'), '${n(draft.flowLpm!)} l/min'),
      if (draft.electrodeMm != null)
        (
          draft.process == 'MIG_MAG'
              ? tr('Drut (średnica)', 'Wire (diameter)')
              : tr('Elektroda', 'Electrode'),
          '${n(draft.electrodeMm!)} mm'
        ),
      if (draft.purgeLpm != null)
        (tr('Formowanie', 'Purge'), '${n(draft.purgeLpm!)} l/min'),
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

/// Podsumowanie wpisu do dziennika spoin — zapis dopiero po „Zapisz".
class _JournalSummaryPage extends StatelessWidget {
  final WeldEntry entry;
  const _JournalSummaryPage({required this.entry});

  @override
  Widget build(BuildContext context) {
    String tr(String pl, String en) => context.tr(pl: pl, en: en);
    final rows = <(String, String)>[
      (tr('Nr spoiny', 'Weld no.'), entry.weldNo),
      (tr('Projekt', 'Project'), entry.projectName),
      (
        'WPS',
        entry.wpsRef.isEmpty ? tr('nie podano', 'not given') : entry.wpsRef
      ),
      (
        tr('Spawacz (stempel)', 'Welder (stamp)'),
        entry.welder.isEmpty
            ? tr('brak — ustaw tożsamość spawacza',
                'none — set up welder identity')
            : entry.welder
      ),
      (tr('Data', 'Date'), entry.date),
      (tr('Status', 'Status'), tr('do badania', 'pending')),
      (tr('Notatka', 'Note'), entry.notes),
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
                    tr('Dopiszę dokładnie to do dziennika spoin:',
                        'I will add exactly this to the weld journal:'),
                    style: const TextStyle(
                        color: _kTextPrimary,
                        fontSize: 15,
                        fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 10),
                  _InfoCard(
                    key: const Key('assistant-journal-summary'),
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
                    tr('Resztę pól (linia, materiał, badania) uzupełnisz w dzienniku.',
                        'Fill in the other fields (line, material, NDT) in the journal.'),
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
                        key: const Key('assistant-journal-edit'),
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
                        key: const Key('assistant-journal-save'),
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
        listenable: Listenable.merge([store, AccountService.instance]),
        builder: (context, _) {
          final entries = store.entries;
          return Column(children: [
            if (store.persistenceFailed)
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  tr('Nie udało się odczytać lub trwale zapisać historii. Lista może być niepełna, a nowe wpisy mogą zniknąć po zamknięciu aplikacji.',
                      'Could not read or persist history. The list may be incomplete and new entries may be lost after closing the app.'),
                  key: const Key('assistant-history-persistence-warning'),
                  style: const TextStyle(color: _kTextPrimary),
                ),
              ),
            Expanded(child: Builder(builder: (context) {
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
              final source = e.byVoice
                  ? tr('głosowo', 'by voice')
                  : tr('tekstem', 'typed');
              return _InfoCard(
                children: [
                  Row(
                    children: [
                      Icon(e.undone ? Icons.undo : Icons.check_circle_outline,
                          color: e.undone ? _kTextSec : _kOk),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          e.kind == 'quote.new'
                              ? (e.undone
                                  ? tr(
                                      'Szkic wyceny — cofnięty', 'Quote draft — undone')
                                  : tr('Szkic wyceny', 'Quote draft'))
                              : e.kind == 'interpass.reading'
                                  ? (e.undone
                                      ? tr('Pomiar temperatury — cofnięty',
                                          'Temperature reading — undone')
                                      : tr(
                                          'Pomiar temperatury', 'Temperature reading'))
                                  : e.kind == 'confined_space.prepare'
                                      ? (e.undone
                                          ? tr(
                                              'Szkic przestrzeni zamkniętej — cofnięty',
                                              'Confined space draft — undone')
                                          : tr('Szkic przestrzeni zamkniętej',
                                              'Confined space draft'))
                                      : e.kind == 'hot_work.prepare'
                                          ? (e.undone
                                              ? tr(
                                                  'Szkic prac gorących — cofnięty',
                                                  'Hot work draft — undone')
                                              : tr('Szkic prac gorących',
                                                  'Hot work draft'))
                                          : e.kind == kIntentAddWeldJournalEntry
                                              ? (e.undone
                                                  ? tr(
                                                      'Wpis do dziennika — cofnięty',
                                                      'Journal entry — undone')
                                                  : tr(
                                                      'Wpis do dziennika spoin',
                                                      'Weld journal entry'))
                                              : (e.undone
                                                  ? tr('Zapis parametru — cofnięty', 'Parameter saved — undone')
                                                  : tr('Zapis parametru', 'Parameter saved')),
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
            })),
          ]);
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
  final lines = citation.split('\n');
  final sourceUrl = lines.length > 1 ? Uri.tryParse(lines.last) : null;
  final isWeb = sourceUrl != null &&
      sourceUrl.scheme == 'https' &&
      sourceUrl.host.isNotEmpty &&
      sourceUrl.userInfo.isEmpty;
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
          pl: isWeb
              ? 'Źródło internetowe wykorzystane przy odpowiedzi. Możesz otworzyć oryginalny materiał.'
              : 'Cytat wskazuje sekcję bazy wiedzy albo pomocy, z której pochodzi '
                  'odpowiedź.',
          en: isWeb
              ? 'An external source used for this answer. You can open the original material.'
              : 'The citation points to the knowledge-base or help section the '
                  'answer came from.',
        ),
        style: const TextStyle(fontSize: 12, color: _kTextPrimary, height: 1.5),
      ),
      actions: [
        if (isWeb)
          TextButton(
            onPressed: () async {
              final opened = await launchUrl(sourceUrl,
                  mode: LaunchMode.externalApplication);
              if (!opened && dctx.mounted) {
                ScaffoldMessenger.of(dctx).showSnackBar(SnackBar(
                    content: Text(dctx.tr(
                        pl: 'Nie udało się otworzyć źródła.',
                        en: 'Could not open the source.'))));
              }
            },
            child: Text(context.tr(pl: 'Otwórz źródło', en: 'Open source')),
          ),
        TextButton(
          onPressed: () => Navigator.pop(dctx),
          child: const Text('OK'),
        ),
      ],
    ),
  );
}

class _ConversationPage extends StatelessWidget {
  const _ConversationPage({required this.messages, required this.onClear});
  final List<ChatMessage> messages;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) => Scaffold(
        key: const Key('assistant-conversation-page'),
        backgroundColor: _kBg,
        appBar: AppBar(
          title: Text(
              context.tr(pl: 'Bieżąca rozmowa', en: 'Current conversation'),
              maxLines: 1,
              overflow: TextOverflow.ellipsis),
          actions: [
            IconButton(
              key: const Key('assistant-conversation-clear'),
              tooltip: context.tr(pl: 'Wyczyść rozmowę', en: 'Clear chat'),
              onPressed: onClear,
              icon: const Icon(Icons.delete_sweep_outlined),
            )
          ],
        ),
        body: SafeArea(
            child: ListView.builder(
          key: const Key('assistant-conversation-messages'),
          padding: const EdgeInsets.all(12),
          reverse: true,
          itemCount: messages.length,
          itemBuilder: (context, index) {
            final message = messages[messages.length - 1 - index];
            final label = message.role == ChatRole.user
                ? context.tr(pl: 'Ty', en: 'You')
                : switch (message.kind) {
                    AiReplyKind.live =>
                      context.tr(pl: 'Asystent · AI', en: 'Assistant · AI'),
                    AiReplyKind.nativeAction ||
                    AiReplyKind.localDialogue =>
                      context.tr(
                          pl: 'Asystent · aplikacja', en: 'Assistant · app'),
                    AiReplyKind.offlineHelp =>
                      context.tr(pl: 'Pomoc w aplikacji', en: 'In-app help'),
                    AiReplyKind.dailyLimit ||
                    AiReplyKind.premiumRequired ||
                    AiReplyKind.unavailable =>
                      context.tr(
                          pl: 'Komunikat o dostępności AI',
                          en: 'AI availability notice'),
                    AiReplyKind.demo =>
                      context.tr(pl: 'Asystent', en: 'Assistant'),
                  };
            return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Text(label,
                          style: Theme.of(context).textTheme.labelSmall)),
                  _MessageBubble(message: message, interactiveCitations: false),
                ]);
          },
        )),
      );
}

class _MessageBubble extends StatelessWidget {
  final ChatMessage message;
  final bool interactiveCitations;
  const _MessageBubble(
      {required this.message, this.interactiveCitations = true});

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
                                onTap: interactiveCitations
                                    ? () => _showCitation(context, c)
                                    : null,
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
            child:
                const Icon(Icons.smart_toy_outlined, color: _kAccent, size: 18),
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
      context.tr(
          pl: 'Heat input dla SMAW 110A', en: 'Heat input for SMAW 110A'),
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
            child: ValueListenableBuilder<TextEditingValue>(
              valueListenable: controller,
              builder: (context, value, _) => TextField(
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
                  errorText: value.text.trim().length > kChatQuestionMaxChars
                      ? chatQuestionTooLongNotice(context.language)
                      : null,
                  errorMaxLines: 4,
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
