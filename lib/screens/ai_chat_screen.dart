import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:uuid/uuid.dart';

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
import '../assistant/core/tool_bridge.dart';
import '../assistant/skills/welder_calc/heat_input_skill.dart';
import '../assistant/skills/iso/iso_command_parser.dart';
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
typedef AssistantChatSender = Future<ChatMessage> Function(
    String text, List<ChatMessage> history);

class AiChatScreen extends StatefulWidget {
  const AiChatScreen({
    super.key,
    this.initialMode = AssistantMode.act,
    this.embedded = false,
    this.speechInput,
    this.speechOutput,
    this.engine,
    this.chatSender,
    this.now,
    this.welderStamp,
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

  /// Zegar do notatki źródłowej (testy).
  final DateTime Function()? now;

  /// Stempel spawacza do wpisu w dzienniku (domyślnie tożsamość spawacza
  /// zapisana w telefonie).
  final Future<String> Function()? welderStamp;

  @override
  State<AiChatScreen> createState() => _AiChatScreenState();
}

class _AiChatScreenState extends State<AiChatScreen>
    with WidgetsBindingObserver {
  late final SpeechInput _speech = widget.speechInput ?? SystemSpeechInput();
  late final SpeechOutput _voice = widget.speechOutput ?? SystemSpeechOutput();
  late final AssistantEngine _engine =
      widget.engine ?? AssistantEngine(remoteAllowed: () async => false);
  late final _brain = AssistantBrain(skills: buildSkillCatalog());
  late final _brainContext = AssistantContext(
      lang: AppLanguage.pl,
      modules:
          widget.embedded ? ToolBridge.instance : const FixedModuleContext(),
      now: widget.now);
  SkillResult? _localResult;
  final _feedback = AssistantFeedbackRecorder();
  IsoCommand? _pendingIso;
  bool _awaitingIsoChoice = false;
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
    _history.load();
    if (widget.embedded) {
      AssistantPanelController.instance.onCommand = _receiveCommand;
      AssistantPanelController.instance.addListener(_panelChanged);
      appRoutes.addListener(_panelChanged);
    }
  }

  void _panelChanged() {
    if (!mounted ||
        (AssistantPanelController.instance.expanded &&
            appRoutes.assistantAvailable)) {
      return;
    }
    if (_listening) {
      _speech.cancel();
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
    if (widget.embedded) {
      AssistantPanelController.instance.onCommand = null;
      AssistantPanelController.instance.removeListener(_panelChanged);
      appRoutes.removeListener(_panelChanged);
    }
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
    var submitted = false;
    await _speech.listen(
      language: lang,
      onResult: (text, isFinal) {
        if (!mounted || submitted) return;
        final joined = before.isEmpty ? text : '$before $text';
        setState(() {
          target.value = TextEditingValue(
            text: joined,
            selection: TextSelection.collapsed(offset: joined.length),
          );
        });
        if (widget.embedded && isFinal && joined.trim().isNotEmpty) {
          submitted = true;
          scheduleMicrotask(_submitCommand);
        }
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
    _queryResults = null;
    _localResult = null;
    _brain.cancelPending();
    if (clearText) {
      _cmdCtrl.clear();
      _voiceUsed = false;
    }
  }

  Future<void> _submitCommand() async {
    var text = _cmdCtrl.text.trim();
    if (text.isEmpty || _busy) return;
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
      _notice = null;
      _offerServer = false;
      _offerAsk = false;
      _queryResults = null;
      _commandBeforeAnswer = _commandSoFar;
      _commandSoFar = _pendingField == null ? text : '$_commandSoFar, $text';
    });
    AssistantOutcome out;
    try {
      // A pending legacy save owns its replies until its summary is ready.
      if (_pendingField == null && await _tryLocalCommand(text, lang)) return;
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

  void _isoReply(String pl, String en) {
    if (!mounted) return;
    setState(() {
      _busy = false;
      _cmdCtrl.clear();
      _localResult = AnswerResult(AssistantAnswer(text: AssistantText(pl, en)));
      _notice = null;
      _question = null;
    });
    _speak(_tr(pl, en));
  }

  Future<bool> _tryIsoCommand(String text, AppLanguage lang) async {
    final u = Utterance(text, lang: lang, byVoice: _voiceUsed);
    var command = parseIsoCommand(u);
    final onIso = appRoutes.toolId == 'iso_notebook' ||
        (!widget.embedded && IsoNotebookController.active != null);
    if (_awaitingIsoChoice) {
      final folded = u.folded;
      if (folded == 'anuluj' || folded == 'cancel') {
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
        if (parseAssistantCommand(text).intent != kIntentUnknown) {
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
      if (dir != null) {
        command = IsoCommand(
            kind: IsoCommandKind.changeLastTurn,
            turnDir: dir,
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
    final unsafe = command.warnings
        .where((w) => w.kind != IsoParseWarningKind.lengthAssumedMeters);
    if (unsafe.isNotEmpty ||
        command.compassAt.isNotEmpty ||
        command.turnCompass != null) {
      unawaited(_feedback.missing(text,
          tool: 'iso_notebook', skill: 'iso.unsupported', lang: lang));
      _isoReply(
          'Potrzebuję dokładniejszego polecenia. Podaj długość z jednostką, '
              'kierunek (prawo, lewo, góra, dół) i rodzaj kształtki. '
              'Kolana 45° i trójniki dodaj na razie ręcznie.',
          'Please specify a length with units, direction (right, left, up, down) '
              'and fitting type. Add 45° elbows and tees manually for now.');
      return true;
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
        _isoReply('Nie udało się otworzyć Zeszytu ISO. Spróbuj ponownie.',
            'Could not open the ISO notebook. Please try again.');
        return true;
      } finally {
        IsoNotebookController.activeListenable.removeListener(changed);
      }
    }
    if (!mounted) return true;
    await controller.ready;
    if (!mounted) return true;
    if (command.kind == IsoCommandKind.changeLastTurn) {
      final dir = command.turnDir;
      final report =
          dir == null ? null : await controller.redirectLastTurn(dir);
      if (report == null) {
        _isoReply(
            'Nie zmieniłem rysunku. Mogę poprawić tylko ostatnie polecenie '
                'z kolanem, jeśli od tego czasu nie było zmian ręcznych.',
            'Drawing unchanged. I can only correct the last voice command '
                'with an elbow, with no manual changes since.');
      } else if (report.ok) {
        _isoReply(
            'Zmieniłem kierunek ostatniego kolana. ${report.assumedPl.join(' ')}',
            'Changed the last elbow direction. ${report.assumedEn.join(' ')}');
      } else {
        _isoReply(report.problemPl ?? 'Rysunek bez zmian.',
            report.problemEn ?? 'Drawing unchanged.');
      }
      return true;
    }
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
    _pendingIso = null;
    if (command.kind == IsoCommandKind.undo) {
      controller.undo();
      _isoReply(
          'Cofnąłem ostatni krok rysunku.', 'Undid the last drawing step.');
      return true;
    }
    if (command.newSketch || command.kind == IsoCommandKind.newSketch) {
      await controller.startNew();
    }
    if (command.kind == IsoCommandKind.newSketch) {
      _isoReply('Nowy arkusz. Powiedz, co narysować.',
          'New sheet. Tell me what to draw.');
      return true;
    }
    final report = await controller.draw(command.steps);
    if (report.ok) {
      _isoReply(
          'Narysowałem: rury ${report.segments}, kolana ${report.elbows}, '
              'kształtki ${report.fittings}. ${report.assumedPl.join(' ')}',
          'Drawn: ${report.segments} pipes, ${report.elbows} elbows, '
              '${report.fittings} fittings. ${report.assumedEn.join(' ')}');
    } else {
      _isoReply(
          report.problemPl ?? 'Nie zmieniłem rysunku. Doprecyzuj polecenie.',
          report.problemEn ?? 'Drawing unchanged. Please clarify the command.');
    }
    return true;
  }

  Future<bool> _tryLocalCommand(String text, AppLanguage lang) async {
    final utterance = Utterance(text, lang: lang, byVoice: _voiceUsed);
    if (isNegatedCommand(utterance)) {
      _brain.cancelPending();
      _pendingIso = null;
      _awaitingIsoChoice = false;
      _isoReply(
          'Nie wykonuję tego polecenia.', 'I will not execute that command.');
      return true;
    }
    if (referencesInstruction(utterance)) {
      _pendingIso = null;
      _awaitingIsoChoice = false;
    } else if (await _tryIsoCommand(text, lang)) {
      return true;
    }
    _brainContext.lang = lang;
    final legacyIntent = parseAssistantCommand(text).intent;
    final calculationRequest = heatInputRequested(utterance) ||
        _brain.recognizesCalculation(utterance, _brainContext);
    if ((legacyIntent == kIntentSaveWeldParameter && !calculationRequest) ||
        legacyIntent == kIntentAddWeldJournalEntry ||
        legacyIntent == kIntentQueryMyParams) {
      _brain.cancelPending();
      _localResult = null;
      return false;
    }
    _brainContext.lang = lang;
    final reply = await _brain.handle(
        Utterance(text, lang: lang, byVoice: _voiceUsed), _brainContext);
    if (!mounted) return true;
    final result = reply.result;
    if (result is NotUnderstood) return false;
    if (result is FailedResult && result.reportMissingCapability) {
      unawaited(_feedback.missing(text,
          tool: reply.match?.skill.toolId,
          skill: reply.match?.skill.id,
          lang: lang));
    }
    // Write skills are intentionally left to the existing confirmation flow.
    if (result is ConfirmResult) return false;
    setState(() {
      _busy = widget.embedded && result is AnswerResult && result.show != null;
      _localResult = result;
      _question = null;
      _notice = null;
      _cmdCtrl.clear();
    });
    final spoken = switch (result) {
      AnswerResult(:final answer) => (answer.spoken ?? answer.text).of(lang),
      AskResult(:final question) => question.of(lang),
      FailedResult(:final message) => message.of(lang),
      _ => '',
    };
    if (spoken.isNotEmpty) await _speak(spoken);
    final explicitOpen = reply.match?.skill.id == 'tool.open' ||
        reply.match?.skill.id == 'account.open' ||
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
    final answer = result is AnswerResult ? result.answer : null;
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
      ],
    );
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
        final confirmed = await Navigator.of(_navigationContext).push<bool>(
          MaterialPageRoute(
            builder: (_) => _SaveSummaryPage(
              draft: draft,
              note:
                  draft.sourceNote(at: _now(), byVoice: _voiceUsed, lang: lang),
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
          if (!mounted) return;
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
        unawaited(_feedback.missing(_commandSoFar,
            tool: ToolBridge.instance.activeToolId, lang: lang));
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
    final undoneText =
        _tr('Cofnięto — rekord usunięty.', 'Undone — record removed.');
    final undoFailedText = _tr('Nie udało się cofnąć — rekord zostaje.',
        'Could not undo — the record stays.');
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
          try {
            await _dao.deleteById(entry.recordId);
          } catch (e) {
            debugPrint('Assistant undo failed: $e');
            messenger.showSnackBar(SnackBar(content: Text(undoFailedText)));
            return;
          }
          await _history.markUndone(entry.id);
          messenger.showSnackBar(SnackBar(content: Text(undoneText)));
        },
      ),
    ));
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
    final lang = context.language;
    List<WeldParam> all;
    try {
      all = await _dao.listAll();
    } catch (e) {
      debugPrint('Assistant query failed: $e');
      if (!mounted) return;
      setState(() {
        _resetAct(clearText: false);
        _notice = _tr('Nie udało się odczytać zapisanych parametrów.',
            'Could not read the saved parameters.');
        _noticeIsError = true;
      });
      return;
    }
    if (!mounted) return;
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
    final lang = context.language;
    List<WeldEntry> journal;
    String stamp;
    try {
      journal = await _journalDao.listAll();
      stamp = await _stamp();
    } catch (e) {
      debugPrint('Assistant journal read failed: $e');
      if (!mounted) return;
      setState(() {
        _resetAct(clearText: false);
        _notice = _tr(
            'Nie udało się odczytać dziennika spoin. Nic nie zapisano.',
            'Could not read the weld journal. Nothing saved.');
        _noticeIsError = true;
      });
      return;
    }
    if (!mounted) return;
    final project = canonicalJournalProject(journal, draft.project);
    if (isWeldNoTaken(journal, project: project, weldNo: draft.weldNo)) {
      // Numer zajęty: projekt i WPS zostają, pytamy tylko o inny numer.
      final q = assistantQuestionFor('weld_no', lang);
      setState(() {
        _pendingIntent = kIntentAddWeldJournalEntry;
        _pendingField = 'weld_no';
        _carried = {
          'project': project,
          if (draft.wps != null) 'wps': draft.wps
        };
        _question = q;
        _cmdCtrl.clear();
        _notice = _tr(
            'Spoina ${draft.weldNo} jest już w projekcie „$project". Nic nie zapisano — podaj inny numer.',
            'Weld ${draft.weldNo} already exists in project "$project". Nothing saved — give another number.');
        _noticeIsError = true;
      });
      Haptic.error();
      await _speak(q);
      return;
    }
    final at = _now();
    final entry = buildAssistantWeldEntry(
      WeldJournalDraft(weldNo: draft.weldNo, project: project, wps: draft.wps),
      id: _uuid.v4(),
      stamp: stamp,
      at: at,
      byVoice: _voiceUsed,
      lang: lang,
    );
    final confirmed = await Navigator.of(_navigationContext).push<bool>(
      MaterialPageRoute(builder: (_) => _JournalSummaryPage(entry: entry)),
    );
    if (!mounted) return;
    if (confirmed != true) {
      setState(() {
        _resetAct(clearText: false);
        _cmdCtrl.text = _commandSoFar;
        _notice = _tr('Nic nie zapisano. Popraw polecenie i stuknij „Dalej".',
            'Nothing saved. Edit the command and tap "Next".');
        _noticeIsError = false;
      });
      return;
    }
    await _saveJournal(entry, stamp: stamp, at: at);
  }

  Future<void> _saveJournal(WeldEntry entry,
      {required String stamp, required DateTime at}) async {
    final lang = context.language;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await _journalDao.insert(entry, by: stamp);
    } catch (e) {
      debugPrint('Assistant journal save failed: $e');
      if (!mounted) return;
      setState(() {
        _notice = _tr('Nie udało się zapisać — nic nie zostało zmienione.',
            'Could not save — nothing was changed.');
        _noticeIsError = true;
      });
      return;
    }
    await saveLastWeldProject(entry.projectName);
    final history = AssistantHistoryEntry(
      id: _uuid.v4(),
      kind: kIntentAddWeldJournalEntry,
      summary: [
        '${lang == AppLanguage.en ? 'Weld' : 'Spoina'} ${entry.weldNo}',
        entry.projectName,
        if (entry.wpsRef.isNotEmpty) 'WPS ${entry.wpsRef}',
        if (entry.welder.isNotEmpty) entry.welder,
      ].join(' · '),
      recordId: entry.id,
      at: at,
      byVoice: _voiceUsed,
    );
    await _history.add(history);
    Haptic.saved();
    if (!mounted) return;
    final savedText = _tr('Dopisano do dziennika spoin — status „do badania"',
        'Added to the weld journal — status "pending"');
    final undoLabel = _tr('Cofnij', 'Undo');
    final undoneText = _tr('Cofnięto — wpis oznaczony jako usunięty.',
        'Undone — the entry is marked deleted.');
    final undoFailedText = _tr('Nie udało się cofnąć — wpis zostaje.',
        'Could not undo — the entry stays.');
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
          try {
            // Dziennik to dowód — wpisu nie kasujemy, tylko oznaczamy.
            await _journalDao.softDelete(entry.id, by: stamp);
          } catch (e) {
            debugPrint('Assistant journal undo failed: $e');
            messenger.showSnackBar(SnackBar(content: Text(undoFailedText)));
            return;
          }
          await _history.markUndone(history.id);
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

  Future<void> _send() async {
    final text = _inputCtrl.text.trim();
    if (text.isEmpty || _typing.value) return;
    if (_listening) {
      await _speech.stop();
      if (!mounted) return;
      setState(() => _listening = false);
    }
    // Treść pytania wychodzi na serwer — najpierw zgoda (bez wymogu imienia).
    // Bez zgody: pomoc offline z aplikacji, NIC nie wychodzi z telefonu.
    final consented = await ensureServerConsent(_navigationContext);
    if (!mounted) return;

    // Historia BEZ bieżącego pytania, najwyżej 6 ostatnich wpisów.
    final history = chatHistoryForRequest(_messages);
    setState(() {
      _messages.add(ChatMessage(role: ChatRole.user, text: text));
      _inputCtrl.clear();
      _voiceUsed = false;
    });

    if (!consented) {
      final offline = AiChatService.instance.offlineReply(text);
      setState(() {
        _messages.add(offline);
        if (widget.embedded) {
          _localResult = AnswerResult(
              AssistantAnswer(text: AssistantText.same(offline.text)));
        }
      });
      _scrollToBottom();
      await _speak(offline.text);
      return;
    }

    _typing.value = true;
    _scrollToBottom();

    try {
      final sender = widget.chatSender ??
          (t, h) => AiChatService.instance.sendMessage(t, history: h);
      final reply = await sender(text, history);
      if (!mounted) return;
      setState(() {
        _messages.add(reply);
        if (widget.embedded) {
          _localResult = AnswerResult(
              AssistantAnswer(text: AssistantText.same(reply.text)));
        }
      });
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
        content: Text(
            _tr('Połączenie z AI nie powiodło się.', 'AI connection failed.')),
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

  Widget _buildEmbedded() => Column(children: [
        Expanded(
            child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                children: [
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
                      tooltip: _tr('Wykonaj', 'Execute'),
                      onPressed: _busy ? null : _submitCommand,
                      icon: _busy
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2))
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
                          e.kind == kIntentAddWeldJournalEntry
                              ? (e.undone
                                  ? tr('Wpis do dziennika — cofnięty',
                                      'Journal entry — undone')
                                  : tr('Wpis do dziennika spoin',
                                      'Weld journal entry'))
                              : (e.undone
                                  ? tr('Zapis parametru — cofnięty',
                                      'Parameter saved — undone')
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
