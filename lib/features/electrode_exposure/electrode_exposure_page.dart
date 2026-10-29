// Elektrody zasadowe: czas na powietrzu i suszenie. Partia „wyjąłem
// elektrody” startuje licznik z limitem z tabeli AWS D1.1 / karty
// producenta; akcje: do piecyka, wyjęte ponownie, ponownie wysuszone,
// zużyte, złom — każda z wpisem w dzienniku dla QC (tekst i PDF).
// Logika: domain/welding/electrode_exposure.dart. Zapis: SharedPreferences
// (electrode_batch_store.dart). Przypomnienia: services/electrode_reminders.dart.

import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import '../../domain/welding/electrode_exposure.dart';
import '../../domain/welding/electrode_reference.dart';
import '../../assistant/core/tool_bridge.dart';
import '../../i18n/app_language.dart';
import '../../services/electrode_log_export.dart';
import '../../services/electrode_reminders.dart';
import '../../services/qualification_reminders.dart';
import '../../theme/app_theme.dart';
import '../../utils/haptic.dart';
import '../../widgets/local_record_scope.dart';
import '../../widgets/number_field.dart';
import '../quotes/quote_widgets.dart';
import 'electrode_batch_store.dart';

/// Udostępnienie tekstu dziennika (wstrzykiwane w testach).
typedef ElectrodeShareText = Future<void> Function(String text);

/// Udostępnienie PDF dziennika (wstrzykiwane w testach).
typedef ElectrodeSharePdf = Future<void> Function(
    List<ElectrodeBatch> batches, LogRange range, DateTime now);

Color electrodeStateColor(ExposureState s) => switch (s) {
      ExposureState.ok => kPass,
      ExposureState.endingSoon => kWarn,
      ExposureState.exceeded => kFail,
      ExposureState.inOven => kArc,
      ExposureState.consumed || ExposureState.scrapped => kTextMut,
    };

ButtonStyle _gloveStyle(Color color) => OutlinedButton.styleFrom(
      foregroundColor: color,
      side: BorderSide(color: color.withValues(alpha: 0.7)),
      minimumSize: const Size(kMinTapTarget, kMinTapTarget),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      tapTargetSize: MaterialTapTargetSize.padded,
    );

class ElectrodeExposurePage extends StatelessWidget {
  const ElectrodeExposurePage({
    super.key,
    this.now = DateTime.now,
    this.store,
    this.reminders,
    this.shareText,
    this.sharePdf,
    this.tick = const Duration(seconds: 20),
  });

  /// Zegar — w testach sterowany.
  final DateTime Function() now;
  final ElectrodeBatchStore? store;

  /// Domyślnie [electrodeReminders].
  final QualificationReminders? reminders;
  final ElectrodeShareText? shareText;
  final ElectrodeSharePdf? sharePdf;

  /// Co ile odświeżać licznik na ekranie.
  final Duration tick;

  @override
  Widget build(BuildContext context) => LocalRecordScope(
        builder: (_, session) => _ElectrodeExposureBody(
          session: session,
          now: now,
          store:
              store ?? ElectrodeBatchStore(captureOwner: session.captureOwner),
          reminders: reminders,
          shareText: shareText,
          sharePdf: sharePdf,
          tick: tick,
        ),
      );
}

class _ElectrodeExposureBody extends StatefulWidget {
  const _ElectrodeExposureBody({
    required this.session,
    required this.now,
    required this.store,
    required this.reminders,
    required this.shareText,
    required this.sharePdf,
    required this.tick,
  });

  final LocalRecordSession session;
  final DateTime Function() now;
  final ElectrodeBatchStore store;
  final QualificationReminders? reminders;
  final ElectrodeShareText? shareText;
  final ElectrodeSharePdf? sharePdf;
  final Duration tick;

  @override
  State<_ElectrodeExposureBody> createState() => _ElectrodeExposurePageState();
}

class _ElectrodeExposurePageState extends State<_ElectrodeExposureBody>
    with ToolHandleHost<_ElectrodeExposureBody> {
  ElectrodeClass? _referenceClass;
  ElectrodeSource? _referenceOrigin;
  late TabController _tabs;
  final _activeScroll = ScrollController();
  @override
  String get toolId => 'electrode_exposure';
  @override
  Set<String> get supportedFields =>
      const {'electrode_class', 'origin', 'reference_only'};
  @override
  Future<Set<String>> apply(Map<String, Object?> fields) async {
    if (!mounted || !widget.session.isCurrent) return fields.keys.toSet();
    final rejected = fields.keys.toSet().difference(supportedFields);
    if (rejected.isNotEmpty) return rejected;
    final c = ElectrodeClass.values
        .where((v) => v.name == fields['electrode_class'])
        .firstOrNull;
    final origin = ElectrodeSource.values
        .where((v) => v.name == fields['origin'])
        .firstOrNull;
    if (c == null || origin == null || fields['reference_only'] != true) {
      return fields.keys.toSet();
    }
    setState(() {
      _referenceClass = c;
      _referenceOrigin = origin;
      _tabs.index = 0;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && widget.session.isCurrent && _activeScroll.hasClients) {
        _activeScroll.jumpTo(0);
      }
    });
    return {};
  }

  List<ElectrodeBatch> _batches = const [];
  bool _loading = true;
  bool _remindersOn = false;
  LogRange _range = LogRange.today;
  Timer? _ticker;

  QualificationReminders get _reminders =>
      widget.reminders ?? electrodeReminders;

  bool get _en => context.language == AppLanguage.en;

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(widget.tick, (_) {
      if (mounted && widget.session.isCurrent) setState(() {});
    });
    unawaited(_load());
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _activeScroll.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    var batches = <ElectrodeBatch>[];
    var reminders = false;
    try {
      batches = await widget.store.load();
      reminders = await _reminders.isEnabled();
    } catch (_) {
      // Pusty dziennik zamiast zablokowanego ekranu.
    }
    if (!mounted || !widget.session.isCurrent) return;
    setState(() {
      _batches = batches;
      _remindersOn = reminders;
      _loading = false;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && widget.session.isCurrent) markReady();
    });
    // Plan mógł się zestarzeć (restart telefonu, zmiana strefy).
    unawaited(_reschedule());
  }

  Future<void> _reschedule() => widget.session.isCurrent
      ? rescheduleElectrodeReminders(_reminders, _batches,
          now: widget.now(), english: _en)
      : Future<void>.value();

  Future<void> _commit(List<ElectrodeBatch> next) async {
    // Po zamknięciu ekranu (np. „Cofnij” w snackbarze, który żyje dalej
    // w ScaffoldMessengerze aplikacji) — żadnego setState; cofnięcie po
    // wyjściu idzie przez [_undoBatch] wprost na zapisie.
    if (!mounted || !widget.session.isCurrent) return;
    setState(() => _batches = next);
    try {
      await widget.store.save(next);
    } catch (_) {
      if (mounted && widget.session.isCurrent) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(context.tr(
                pl: 'Nie udało się zapisać dziennika.',
                en: 'Could not save the log.'))));
      }
    }
    if (!mounted || !widget.session.isCurrent) return;
    await _reschedule();
  }

  String _newId() {
    final base = 'b${widget.now().millisecondsSinceEpoch}';
    var id = base;
    var n = 1;
    while (_batches.any((b) => b.id == id)) {
      id = '$base-${n++}';
    }
    return id;
  }

  Future<void> _add() async {
    if (!widget.session.isCurrent) return;
    final batch = await Navigator.of(context).push<ElectrodeBatch>(
      MaterialPageRoute(
        builder: (_) => LocalRecordScope(
          originSession: widget.session,
          restartOnAccountChange: false,
          builder: (_, __) => _TakeOutPage(
              session: widget.session, id: _newId(), now: widget.now),
        ),
      ),
    );
    if (batch == null || !mounted || !widget.session.isCurrent) return;
    unawaited(Haptic.saved());
    await _commit([..._batches, batch]);
    if (!mounted || !widget.session.isCurrent) return;
    final end = batch.deadline ?? batch.takenOutAt.add(batch.limit);
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
          content: Text(context.tr(
              pl: 'Start odliczania: ${batch.label(en: false)} — limit do '
                  '${formatHm(end)}.',
              en: 'Countdown started: ${batch.label(en: true)} — limit until '
                  '${formatHm(end)}.'))));
  }

  Future<void> _replace(ElectrodeBatch next, {String? undoText}) async {
    if (!widget.session.isCurrent) return;
    final previous = _batches.where((b) => b.id == next.id).firstOrNull;
    await _commit([
      for (final b in _batches) b.id == next.id ? next : b,
    ]);
    unawaited(Haptic.saved());
    if (undoText == null ||
        previous == null ||
        !mounted ||
        !widget.session.isCurrent) {
      return;
    }
    _showUndo(undoText, previous);
  }

  /// Snackbar „Cofnij” dla JEDNEJ partii — przywraca tylko ją, w bieżącej
  /// liście (zmiany innych partii zrobione w międzyczasie zostają).
  void _showUndo(String text, ElectrodeBatch previous) {
    if (!widget.session.isCurrent) return;
    final undo = _undoBatch(previous);
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(text),
        action: SnackBarAction(
          label: context.tr(pl: 'Cofnij', en: 'Undo'),
          onPressed: () => unawaited(undo()),
        ),
      ));
  }

  /// Cofnięcie przygotowane z góry: zależności zebrane teraz, bo snackbar
  /// może zostać kliknięty już po zamknięciu ekranu.
  Future<void> Function() _undoBatch(ElectrodeBatch previous) {
    final store = widget.store;
    final reminders = _reminders;
    final now = widget.now;
    final english = _en;
    final session = widget.session;
    return () async {
      if (!session.isCurrent) return;
      if (mounted) {
        await _commit(restoreBatch(_batches, previous));
        return;
      }
      try {
        final next = restoreBatch(await store.load(), previous);
        await store.save(next);
        if (!session.isCurrent) return;
        await rescheduleElectrodeReminders(reminders, next,
            now: now(), english: english);
      } catch (_) {
        // Cofnięcie po wyjściu z ekranu to wygoda — błąd nie może wywalić
        // aplikacji.
      }
    };
  }

  Future<void> _toOven(ElectrodeBatch b) =>
      _replace(b.returnToOven(widget.now()));

  Future<void> _outAgain(ElectrodeBatch b) async {
    final next = b.takeOutAgain(widget.now());
    await _replace(next);
    if (!mounted || !widget.session.isCurrent) return;
    final reset = next.events.last.reset;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
          content: Text(reset
              ? context.tr(
                  pl: 'Limit od nowa — elektrody leżały w piecyku min. '
                      '${kOvenResetHold.inHours} h.',
                  en: 'Limit reset — electrodes were in the oven for at least '
                      '${kOvenResetHold.inHours} h.')
              : context.tr(
                  pl: 'Krócej niż ${kOvenResetHold.inHours} h w piecyku — '
                      'licznik liczy dalej od ${formatSpan(next.priorExposure)}.',
                  en: 'Less than ${kOvenResetHold.inHours} h in the oven — the '
                      'clock continues from ${formatSpan(next.priorExposure)}.'))));
  }

  Future<void> _redry(ElectrodeBatch b) async {
    if (!widget.session.isCurrent) return;
    if (b.redryLimitReached) {
      final go = await showDialog<bool>(
        context: context,
        builder: (ctx) => LocalRecordScope(
          originSession: widget.session,
          restartOnAccountChange: false,
          builder: (_, __) => AlertDialog(
            title: Text(ctx.tr(
                pl: 'Limit suszeń wyczerpany', en: 'Re-dry limit used up')),
            content: Text(ctx.tr(
                pl: 'Ta partia była już suszona ${b.redryCount} '
                    '${b.redryCount == 1 ? 'raz' : 'razy'} (dopuszczalne: '
                    '${b.maxRedries}). Kolejne suszenie niszczy otulinę — '
                    'elektrody powinny iść na złom. Zapisać suszenie mimo to?',
                en: 'This batch has already been re-dried ${b.redryCount} '
                    'time(s) (allowed: ${b.maxRedries}). Another cycle damages '
                    'the coating — the electrodes should be scrapped. Record the '
                    're-dry anyway?')),
            actions: [
              TextButton(
                key: const ValueKey('electrode-redry-cancel'),
                onPressed: () => Navigator.of(ctx).pop(false),
                child: Text(ctx.tr(pl: 'Anuluj', en: 'Cancel')),
              ),
              TextButton(
                key: const ValueKey('electrode-redry-anyway'),
                onPressed: () => Navigator.of(ctx).pop(true),
                child: Text(ctx.tr(pl: 'Zapisz mimo to', en: 'Record anyway'),
                    style: const TextStyle(color: kFail)),
              ),
            ],
          ),
        ),
      );
      if (go != true || !mounted || !widget.session.isCurrent) return;
    }
    await _replace(b.redried(widget.now()));
  }

  Future<void> _close(ElectrodeBatch b, BatchClosure how) => _replace(
        b.close(widget.now(), how),
        undoText: how == BatchClosure.consumed
            ? context.tr(pl: 'Partia zużyta.', en: 'Batch used up.')
            : context.tr(pl: 'Partia na złom.', en: 'Batch scrapped.'),
      );

  Future<void> _delete(ElectrodeBatch b) async {
    if (!widget.session.isCurrent) return;
    final previous = _batches.where((x) => x.id == b.id).firstOrNull ?? b;
    await _commit([
      for (final x in _batches)
        if (x.id != b.id) x
    ]);
    if (!mounted || !widget.session.isCurrent) return;
    _showUndo(
        context.tr(
            pl: 'Usunięto partię z dziennika.', en: 'Batch removed from log.'),
        previous);
  }

  Future<void> _editLimit(ElectrodeBatch b) async {
    if (!widget.session.isCurrent) return;
    final result = await showDialog<(int, int)>(
      context: context,
      builder: (_) => LocalRecordScope(
        originSession: widget.session,
        restartOnAccountChange: false,
        builder: (_, __) =>
            _LimitDialog(batch: b, canRaise: b.canRaiseLimitAt(widget.now())),
      ),
    );
    if (result == null || !mounted || !widget.session.isCurrent) return;
    final (minutes, maxRedries) = result;
    // Bieżąca wersja partii (mogła się zmienić, gdy dialog był otwarty).
    final current = _batches.where((x) => x.id == b.id).firstOrNull;
    if (current == null) return;
    try {
      await _replace(
          current.withLimit(minutes, widget.now()).withMaxRedries(maxRedries));
    } on StateError {
      if (!mounted || !widget.session.isCurrent) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(context.tr(
              pl: 'Partia jest przekroczona — limit można tylko obniżyć. '
                  'Zostaje ponowne suszenie albo złom.',
              en: 'The batch is over its limit — the limit can only be '
                  'lowered. Re-dry or scrap.'))));
    }
  }

  Future<void> _toggleReminders(bool on) async {
    if (!widget.session.isCurrent) return;
    if (on) {
      final ok = await _reminders.enable(
          planElectrodeReminders(_batches, now: widget.now(), english: _en));
      if (!mounted || !widget.session.isCurrent) return;
      setState(() => _remindersOn = ok);
      if (!ok) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(context.tr(
                pl: 'Bez zgody na powiadomienia przypomnienia nie zadziałają.',
                en: 'Reminders need notification permission.'))));
      }
    } else {
      await _reminders.disable();
      if (mounted && widget.session.isCurrent) {
        setState(() => _remindersOn = false);
      }
    }
  }

  Future<void> _share({required bool pdf}) async {
    if (!widget.session.isCurrent) return;
    final now = widget.now();
    final list = batchesForLog(_batches, _range, now);
    try {
      if (pdf) {
        await (widget.sharePdf ??
            (l, r, n) => ElectrodeLogExport.sharePdf(l,
                now: n, range: r, mayShare: () => widget.session.isCurrent))(
          list,
          _range,
          now,
        );
      } else {
        final text =
            buildElectrodeLogText(list, now: now, range: _range, en: _en);
        await (widget.shareText ??
            (t) => ElectrodeLogExport.shareText(t, en: _en))(text);
      }
    } catch (_) {
      if (!mounted || !widget.session.isCurrent) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(context.tr(
              pl: 'Nie udało się udostępnić.', en: 'Sharing failed.'))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final now = widget.now();
    final active = sortActive(_batches, now);
    return DefaultTabController(
      length: 2,
      child: Builder(builder: (tabContext) {
        _tabs = DefaultTabController.of(tabContext);
        return Scaffold(
          appBar: AppBar(
            title: Text(context.tr(
                pl: 'Elektrody zasadowe', en: 'Low-hydrogen electrodes')),
            bottom: TabBar(
              indicatorColor: kArc,
              labelColor: kArc,
              unselectedLabelColor: kTextSec,
              tabs: [
                Tab(
                  key: const ValueKey('electrode-tab-active'),
                  text: context.tr(
                      pl: 'Na stanowisku (${active.length})',
                      en: 'At the station (${active.length})'),
                ),
                Tab(
                  key: const ValueKey('electrode-tab-log'),
                  text: context.tr(pl: 'Dziennik QC', en: 'QC log'),
                ),
              ],
            ),
          ),
          floatingActionButton: FloatingActionButton.extended(
            key: const ValueKey('electrode-add'),
            backgroundColor: kArc,
            foregroundColor: kOnArc,
            onPressed: _loading ? null : () => unawaited(_add()),
            icon: const Icon(Icons.outbox_outlined),
            label: Text(
                context.tr(pl: 'Wyjąłem elektrody', en: 'Took electrodes out'),
                style: const TextStyle(fontWeight: FontWeight.w800)),
          ),
          body: _loading
              ? const Center(child: CircularProgressIndicator(color: kArc))
              : TabBarView(
                  children: [
                    _activeTab(active, now),
                    _logTab(now),
                  ],
                ),
        );
      }),
    );
  }

  // ── Na stanowisku ──────────────────────────────────────────────────────

  Widget _activeTab(List<ElectrodeBatch> active, DateTime now) {
    final bottom = 96 + MediaQuery.viewPaddingOf(context).bottom;
    return ListView(
      key: const ValueKey('electrode-active-list'),
      controller: _activeScroll,
      padding: EdgeInsets.fromLTRB(16, 12, 16, bottom),
      children: [
        if (_referenceClass != null && _referenceOrigin != null)
          Card(
              key: const ValueKey('electrode-assistant-reference'),
              child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                            context.tr(
                                pl: 'Referencja asystenta',
                                en: 'Assistant reference'),
                            style:
                                const TextStyle(fontWeight: FontWeight.bold)),
                        SelectableText(electrodeReferenceText(
                            _referenceClass!, _referenceOrigin!,
                            en: _en)),
                        TextButton(
                            onPressed: () => setState(() {
                                  _referenceClass = null;
                                  _referenceOrigin = null;
                                }),
                            child: Text(context.tr(
                                pl: 'Zamknij referencję',
                                en: 'Close reference'))),
                      ]))),
        Text(
          context.tr(
            pl: 'Zasadowe (niskowodorowe) elektrody po wyjęciu z piecyka '
                'chłoną wilgoć — wodór w spoinie to pęknięcia zimne. Licznik '
                'pilnuje limitu z AWS D1.1 albo karty producenta.',
            en: 'Low-hydrogen electrodes pick up moisture once out of the '
                'oven — hydrogen in the weld means cold cracking. The timer '
                'tracks the AWS D1.1 or manufacturer limit.',
          ),
          style: const TextStyle(fontSize: 12.5, color: kTextSec, height: 1.4),
        ),
        const SizedBox(height: 8),
        if (_reminders.supported) ...[
          Material(
            color: Colors.transparent,
            child: SwitchListTile(
              key: const ValueKey('electrode-reminders'),
              contentPadding: EdgeInsets.zero,
              value: _remindersOn,
              activeThumbColor: kArc,
              onChanged: (v) => unawaited(_toggleReminders(v)),
              title: Text(context.tr(
                  pl: 'Przypomnienia przed końcem limitu i w chwili końca',
                  en: 'Reminders before the limit ends and when it ends')),
            ),
          ),
          // Android planuje bez SCHEDULE_EXACT_ALARM (inexactAllowWhileIdle):
          // w trybie oszczędzania baterii powiadomienie bywa spóźnione.
          Text(
            context.tr(
                pl: 'Telefon może dostarczyć przypomnienie kilka minut '
                    'później (oszczędzanie baterii). Liczy się licznik na '
                    'ekranie. Przy limitach do 1 h przypominamy też w połowie '
                    'czasu.',
                en: 'The phone may deliver a reminder a few minutes late '
                    '(battery saving). The timer on screen is what counts. '
                    'For limits up to 1 h we also remind you halfway.'),
            key: const ValueKey('electrode-reminder-note'),
            style: const TextStyle(fontSize: 12, color: kTextMut, height: 1.35),
          ),
        ] else if (!kIsWeb)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text(
                context.tr(
                    pl: 'Przypomnienia działają na telefonie (Android/iOS).',
                    en: 'Reminders work on the phone (Android/iOS).'),
                style: const TextStyle(fontSize: 12, color: kTextMut)),
          ),
        const SizedBox(height: 8),
        if (active.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Text(
              context.tr(
                  pl: 'Brak elektrod na stanowisku. Dotknij „Wyjąłem '
                      'elektrody”, gdy wyjmujesz partię z piecyka albo '
                      'otwierasz opakowanie próżniowe.',
                  en: 'No electrodes at the station. Tap “Took electrodes '
                      'out” when you take a batch out of the oven or open a '
                      'vacuum pack.'),
              key: const ValueKey('electrode-empty'),
              textAlign: TextAlign.center,
              style: const TextStyle(color: kTextSec),
            ),
          ),
        for (final b in active)
          _BatchCard(
            key: ValueKey('electrode-card-${b.id}'),
            batch: b,
            now: now,
            onOven: () => unawaited(_toOven(b)),
            onOutAgain: () => unawaited(_outAgain(b)),
            onRedry: () => unawaited(_redry(b)),
            onConsumed: () => unawaited(_close(b, BatchClosure.consumed)),
            onScrap: () => unawaited(_close(b, BatchClosure.scrapped)),
            onLimit: () => unawaited(_editLimit(b)),
            onDelete: () => unawaited(_delete(b)),
          ),
        const SizedBox(height: 4),
        _rulesSection(),
      ],
    );
  }

  Widget _rulesSection() {
    String fam(ElectrodeFamily f, String pl, String en) =>
        '• ${context.tr(pl: pl, en: en)}: ${f.redry(en: _en)}';
    return QuoteSection(
      title: context.tr(pl: 'Zasady w skrócie', en: 'Rules in short'),
      children: [
        Text(
          [
            context.tr(
                pl: '• Piecyk-przechowalnik min. $kHoldingOvenMinC °C '
                    '(zwykle 120–150 °C). Powrót do piecyka PRZED końcem '
                    'limitu i min. ${kOvenResetHold.inHours} h w środku — '
                    'limit od nowa. Krócej — licznik tylko stoi.',
                en: '• Holding oven min. $kHoldingOvenMinC °C (typically '
                    '120–150 °C). Back in the oven BEFORE the limit and at '
                    'least ${kOvenResetHold.inHours} h inside — limit resets. '
                    'Shorter — the clock only pauses.'),
            context.tr(
                pl: '• Kołczan / termos nie zatrzymuje licznika — wg AWS D1.1 '
                    'to czas na powietrzu.',
                en: '• A quiver / rod canister does not stop the clock — per '
                    'AWS D1.1 it counts as exposure.'),
            context.tr(
                pl: '• Po przekroczeniu limitu — ponowne suszenie w piecu '
                    'suszarniczym albo złom:',
                en: '• Limit exceeded — re-dry in a drying oven or scrap:'),
            fam(ElectrodeFamily.awsA51, 'AWS A5.1', 'AWS A5.1'),
            fam(ElectrodeFamily.awsA55, 'AWS A5.5', 'AWS A5.5'),
            fam(ElectrodeFamily.enIso2560, 'EN ISO 2560-A / 18275-A',
                'EN ISO 2560-A / 18275-A'),
            context.tr(
                pl: '• Do pieca wkładaj przy temp. max połowy docelowej, '
                    'trzymaj ½ h, potem grzej; czas suszenia liczy się od '
                    'osiągnięcia temperatury (AWS D1.1).',
                en: '• Load into the oven at no more than half the final '
                    'temperature, hold ½ h, then heat up; drying time counts '
                    'from reaching temperature (AWS D1.1).'),
            context.tr(
                pl: '• AWS D1.1: najwyżej jedno ponowne suszenie. Producenci '
                    'EN zwykle dopuszczają 2–3 — sprawdź kartę.',
                en: '• AWS D1.1: re-dry no more than once. EN manufacturers '
                    'usually allow 2–3 — check the data sheet.'),
            context.tr(
                pl: '• Zamoczone elektrody — tylko złom.',
                en: '• Electrodes that got wet — scrap only.'),
            context.tr(
                pl: '• AWS D1.5 (mosty): suszenie 230–290 °C min. 2 h; A5.5 '
                    'z „R” do 9 h. WPS albo producent mogą być ostrzejsze — '
                    'limit partii jest edytowalny.',
                en: '• AWS D1.5 (bridges): re-dry 230–290 °C, 2 h min.; A5.5 '
                    'with “R” up to 9 h. The WPS or manufacturer may be '
                    'stricter — the batch limit is editable.'),
          ].join('\n'),
          style: const TextStyle(fontSize: 12.5, color: kText, height: 1.45),
        ),
      ],
    );
  }

  // ── Dziennik ───────────────────────────────────────────────────────────

  Widget _logTab(DateTime now) {
    final list = batchesForLog(_batches, _range, now);
    final bottom = 96 + MediaQuery.viewPaddingOf(context).bottom;
    return ListView(
      key: const ValueKey('electrode-log-list'),
      padding: EdgeInsets.fromLTRB(16, 12, 16, bottom),
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: [
            for (final r in LogRange.values)
              ChoiceChip(
                key: ValueKey('electrode-range-${r.name}'),
                materialTapTargetSize: MaterialTapTargetSize.padded,
                label: Text(switch (r) {
                  LogRange.today => context.tr(pl: 'Dziś', en: 'Today'),
                  LogRange.week => context.tr(pl: '7 dni', en: '7 days'),
                  LogRange.all => context.tr(pl: 'Wszystko', en: 'All'),
                }),
                selected: _range == r,
                onSelected: (_) => setState(() => _range = r),
              ),
          ],
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            OutlinedButton.icon(
              key: const ValueKey('electrode-share-text'),
              style: _gloveStyle(kText),
              onPressed: () => unawaited(_share(pdf: false)),
              icon: const Icon(Icons.share_outlined, size: 20),
              label: Text(context.tr(pl: 'Udostępnij tekst', en: 'Share text')),
            ),
            OutlinedButton.icon(
              key: const ValueKey('electrode-share-pdf'),
              style: _gloveStyle(kText),
              onPressed: () => unawaited(_share(pdf: true)),
              icon: const Icon(Icons.picture_as_pdf_outlined, size: 20),
              label: Text(context.tr(pl: 'PDF dla QC', en: 'PDF for QC')),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (list.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Text(
              context.tr(
                  pl: 'Brak wpisów w tym zakresie.',
                  en: 'No entries in this range.'),
              key: const ValueKey('electrode-log-empty'),
              textAlign: TextAlign.center,
              style: const TextStyle(color: kTextSec),
            ),
          ),
        for (final b in list) _LogCard(batch: b, now: now),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// KARTA PARTII
// ═══════════════════════════════════════════════════════════════════════════

class _BatchCard extends StatelessWidget {
  const _BatchCard({
    super.key,
    required this.batch,
    required this.now,
    required this.onOven,
    required this.onOutAgain,
    required this.onRedry,
    required this.onConsumed,
    required this.onScrap,
    required this.onLimit,
    required this.onDelete,
  });

  final ElectrodeBatch batch;
  final DateTime now;
  final VoidCallback onOven;
  final VoidCallback onOutAgain;
  final VoidCallback onRedry;
  final VoidCallback onConsumed;
  final VoidCallback onScrap;
  final VoidCallback onLimit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final b = batch;
    final en = context.language == AppLanguage.en;
    final state = b.stateAt(now);
    final color = electrodeStateColor(state);
    final left = b.remainingAt(now);
    // Bez `!` — zapis z niespójnym stanem (naprawiany w fromJson) i tak nie
    // może wywalić ekranu.
    final ovenSince = b.ovenSince ?? now;
    final start = b.exposureStart ?? b.takenOutAt;
    final end = b.deadline ?? start.add(b.limit - b.priorExposure);
    final headline = switch (state) {
      ExposureState.exceeded => context.tr(
          pl: 'PRZEKROCZONO o ${formatSpan(left)}',
          en: 'OVER by ${formatSpan(left)}'),
      ExposureState.inOven => context.tr(
          pl: 'W piecyku od ${formatHm(ovenSince)}',
          en: 'In the oven since ${formatHm(ovenSince)}'),
      _ => context.tr(
          pl: 'zostało ${formatSpan(left)}', en: '${formatSpan(left)} left'),
    };
    final detail = switch (state) {
      ExposureState.inOven => context.tr(
          pl: 'Na powietrzu dotąd ${formatSpan(b.exposureAt(now))} z '
              '${formatSpan(b.limit)} · licznik stoi',
          en: 'Exposed so far ${formatSpan(b.exposureAt(now))} of '
              '${formatSpan(b.limit)} · clock paused'),
      ExposureState.exceeded => context.tr(
          pl: 'Na powietrzu ${formatSpan(b.exposureAt(now))} · limit '
              '${formatSpan(b.limit)}',
          en: 'Exposed ${formatSpan(b.exposureAt(now))} · limit '
              '${formatSpan(b.limit)}'),
      _ => context.tr(
          pl: 'Start ${formatHm(start)} · limit '
              '${formatSpan(b.limit)} · koniec ${formatHm(end)}',
          en: 'Start ${formatHm(start)} · limit '
              '${formatSpan(b.limit)} · ends ${formatHm(end)}'),
    };
    final reset = b.resetRemainingAt(now);

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: kCard,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(
              color: state == ExposureState.exceeded
                  ? kFail.withValues(alpha: 0.7)
                  : kBorder),
        ),
        clipBehavior: Clip.antiAlias,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 4, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(b.label(en: en),
                            style: const TextStyle(
                                fontWeight: FontWeight.w800, fontSize: 15.5)),
                        Text(
                          [
                            if (b.source == ElectrodeSource.hermeticPack)
                              context.tr(
                                  pl: 'opakowanie próżniowe',
                                  en: 'vacuum pack'),
                            if (b.location.isNotEmpty) b.location,
                            context.tr(
                                pl: 'suszenia ${b.redryCount}/${b.maxRedries}',
                                en: 're-dries ${b.redryCount}/${b.maxRedries}'),
                          ].join(' · '),
                          style:
                              const TextStyle(fontSize: 12.5, color: kTextSec),
                        ),
                      ],
                    ),
                  ),
                  PopupMenuButton<String>(
                    key: ValueKey('electrode-more-${b.id}'),
                    tooltip: context.tr(pl: 'Więcej', en: 'More'),
                    onSelected: (v) => switch (v) {
                      'limit' => onLimit(),
                      'redry' => onRedry(),
                      'used' => onConsumed(),
                      'scrap' => onScrap(),
                      _ => onDelete(),
                    },
                    itemBuilder: (_) => [
                      PopupMenuItem(
                          value: 'limit',
                          child: Text(context.tr(
                              pl: 'Zmień limit / suszenia',
                              en: 'Change limit / re-dries'))),
                      PopupMenuItem(
                          value: 'redry',
                          child: Text(context.tr(
                              pl: 'Ponownie wysuszone', en: 'Re-dried'))),
                      PopupMenuItem(
                          value: 'used',
                          child: Text(context.tr(pl: 'Zużyte', en: 'Used up'))),
                      PopupMenuItem(
                          value: 'scrap',
                          child: Text(context.tr(pl: 'Złom', en: 'Scrap'))),
                      PopupMenuItem(
                          value: 'delete',
                          child: Text(context.tr(
                              pl: 'Usuń z dziennika', en: 'Remove from log'))),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.only(right: 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      headline,
                      key: ValueKey('electrode-remaining-${b.id}'),
                      style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w900,
                          color: color),
                    ),
                    Text(detail,
                        style:
                            const TextStyle(fontSize: 12.5, color: kTextSec)),
                    const SizedBox(height: 8),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: b.usedFraction(now),
                        minHeight: 8,
                        color: color,
                        backgroundColor: kBorder,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      electrodeStateLabel(state, en: en),
                      key: ValueKey('electrode-state-${b.id}-${state.name}'),
                      style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w800,
                          color: color),
                    ),
                    if (state == ExposureState.exceeded) ...[
                      const SizedBox(height: 8),
                      QuoteNotice(
                        key: ValueKey('electrode-exceeded-${b.id}'),
                        color: kFail,
                        icon: Icons.warning_amber_rounded,
                        text: b.redryLimitReached
                            ? context.tr(
                                pl: 'Nie spawaj nimi. Limit suszeń wyczerpany '
                                    '(${b.redryCount}/${b.maxRedries}) — '
                                    'na złom.',
                                en: 'Do not weld with them. Re-dry limit used '
                                    'up (${b.redryCount}/${b.maxRedries}) — '
                                    'scrap.')
                            : context.tr(
                                pl: 'Nie spawaj nimi. Do ponownego suszenia: '
                                    '${b.electrode.family.redry(en: false)}; '
                                    'potem piecyk min. $kHoldingOvenMinC °C. '
                                    'To będzie suszenie nr '
                                    '${b.redryCount + 1} z ${b.maxRedries}. '
                                    'Albo złom.',
                                en: 'Do not weld with them. Re-dry: '
                                    '${b.electrode.family.redry(en: true)}; '
                                    'then holding oven min. '
                                    '$kHoldingOvenMinC °C. This will be '
                                    're-dry no. ${b.redryCount + 1} of '
                                    '${b.maxRedries}. Or scrap.'),
                      ),
                    ],
                    if (state == ExposureState.inOven && reset != null) ...[
                      const SizedBox(height: 6),
                      Text(
                        reset == Duration.zero
                            ? context.tr(
                                pl: 'Min. ${kOvenResetHold.inHours} h w '
                                    'piecyku minęły — po wyjęciu limit od nowa.',
                                en: '${kOvenResetHold.inHours} h in the oven '
                                    'done — the limit resets when taken out.')
                            : context.tr(
                                pl: 'Limit od nowa po ${kOvenResetHold.inHours} h '
                                    'w piecyku (jeszcze ${formatSpan(reset)}). '
                                    'Wyjęte wcześniej — licznik dalej.',
                                en: 'Limit resets after '
                                    '${kOvenResetHold.inHours} h in the oven '
                                    '(${formatSpan(reset)} to go). Taken out '
                                    'earlier — the clock continues.'),
                        style: const TextStyle(
                            fontSize: 12, color: kTextMut, height: 1.35),
                      ),
                    ],
                    if (b.redryLimitExceeded) ...[
                      const SizedBox(height: 8),
                      QuoteNotice(
                        color: kFail,
                        text: context.tr(
                            pl: 'Suszone więcej razy niż dopuszczalne '
                                '(${b.redryCount}/${b.maxRedries}).',
                            en: 'Re-dried more often than allowed '
                                '(${b.redryCount}/${b.maxRedries}).'),
                      ),
                    ],
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: _actions(context, state),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _actions(BuildContext context, ExposureState state) {
    final id = batch.id;
    Widget btn(String key, IconData icon, String label, Color color,
            VoidCallback onTap) =>
        OutlinedButton.icon(
          key: ValueKey('electrode-$key-$id'),
          style: _gloveStyle(color),
          onPressed: onTap,
          icon: Icon(icon, size: 20),
          label: Text(label),
        );
    final oven = btn('oven', Icons.inventory_2_outlined,
        context.tr(pl: 'Do piecyka', en: 'Back to oven'), kArc, onOven);
    final again = btn(
        'out-again',
        Icons.outbox_outlined,
        context.tr(pl: 'Wyjąłem ponownie', en: 'Took out again'),
        kPass,
        onOutAgain);
    final redry = btn('redry', Icons.local_fire_department_outlined,
        context.tr(pl: 'Ponownie wysuszone', en: 'Re-dried'), kWarn, onRedry);
    final used = btn('used', Icons.check_circle_outline,
        context.tr(pl: 'Zużyte', en: 'Used up'), kTextSec, onConsumed);
    final scrap = btn('scrap', Icons.delete_outline,
        context.tr(pl: 'Złom', en: 'Scrap'), kFail, onScrap);
    return switch (state) {
      ExposureState.ok || ExposureState.endingSoon => [oven, used, scrap],
      ExposureState.inOven => [again, used],
      ExposureState.exceeded => [redry, scrap],
      _ => const [],
    };
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// KARTA DZIENNIKA
// ═══════════════════════════════════════════════════════════════════════════

class _LogCard extends StatelessWidget {
  const _LogCard({required this.batch, required this.now});

  final ElectrodeBatch batch;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final b = batch;
    final en = context.language == AppLanguage.en;
    final state = b.stateAt(now);
    return Padding(
      key: ValueKey('electrode-log-${b.id}'),
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: kCard,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: kBorder),
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                  [b.label(en: en), if (b.location.isNotEmpty) b.location]
                      .join(' — '),
                  style: const TextStyle(
                      fontWeight: FontWeight.w800, fontSize: 15)),
              Text(b.electrode.desc(en: en),
                  style: const TextStyle(fontSize: 12, color: kTextMut)),
              const SizedBox(height: 4),
              Text(electrodeStatusLine(b, now, en: en),
                  style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: electrodeStateColor(state))),
              const SizedBox(height: 8),
              for (final e in b.events)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: 50,
                        child: Text(formatHm(e.at),
                            style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                fontFeatures: [FontFeature.tabularFigures()])),
                      ),
                      Expanded(
                        child: Text(
                          '${_sameDay(e.at, now) ? '' : '${formatYmd(e.at)} · '}'
                          '${electrodeEventLabel(e, b, en: en)}',
                          style: const TextStyle(
                              fontSize: 13, color: kText, height: 1.3),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  static bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;
}

// ═══════════════════════════════════════════════════════════════════════════
// DIALOG LIMITU
// ═══════════════════════════════════════════════════════════════════════════

String _hoursText(int minutes, {required bool en}) {
  final h = minutes / 60;
  final s = h == h.roundToDouble()
      ? h.toStringAsFixed(0)
      : h.toStringAsFixed(2).replaceFirst(RegExp(r'0$'), '');
  return en ? s : s.replaceAll('.', ',');
}

/// Godziny z pola („4”, „0,5”) → minuty; `null` — poza 1 min … 7 dni.
int? _parseHours(String text) {
  final v = parseDecimal(text.trim());
  if (v == null || !v.isFinite) return null;
  final m = (v * 60).round();
  if (m < 1 || m > 7 * 24 * 60) return null;
  return m;
}

class _LimitDialog extends StatefulWidget {
  const _LimitDialog({required this.batch, required this.canRaise});
  final ElectrodeBatch batch;

  /// `false` — partia przekroczona: wolno tylko obniżyć limit
  /// ([ElectrodeBatch.canRaiseLimitAt]).
  final bool canRaise;

  @override
  State<_LimitDialog> createState() => _LimitDialogState();
}

class _LimitDialogState extends State<_LimitDialog> {
  late final TextEditingController _hours;
  late final TextEditingController _redries;
  bool _initialized = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialized) return;
    _initialized = true;
    final en = context.language == AppLanguage.en;
    _hours = TextEditingController(
        text: _hoursText(widget.batch.limitMinutes, en: en));
    _redries = TextEditingController(text: '${widget.batch.maxRedries}');
  }

  @override
  void dispose() {
    _hours.dispose();
    _redries.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final minutes = _parseHours(_hours.text);
    final redries = int.tryParse(_redries.text.trim());
    final raiseBlocked = !widget.canRaise &&
        minutes != null &&
        minutes > widget.batch.limitMinutes;
    final ok =
        minutes != null && !raiseBlocked && redries != null && redries >= 0;
    final tableMinutes =
        defaultLimitMinutes(widget.batch.electrode, widget.batch.source);
    return AlertDialog(
      title: Text(context.tr(pl: 'Limit partii', en: 'Batch limit')),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!widget.canRaise)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(
                  context.tr(
                      pl: 'Partia jest przekroczona — limit można tylko '
                          'obniżyć. Zostaje ponowne suszenie albo złom.',
                      en: 'The batch is over its limit — the limit can only '
                          'be lowered. Re-dry or scrap.'),
                  key: const ValueKey('electrode-limit-locked'),
                  style: const TextStyle(fontSize: 12.5, color: kFail),
                ),
              ),
            TextField(
              key: const ValueKey('electrode-limit-edit'),
              controller: _hours,
              keyboardType: numberKeyboard(),
              inputFormatters: numberInputFormatters(),
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                labelText: context.tr(
                    pl: 'Czas na powietrzu', en: 'Atmospheric exposure'),
                suffixText: 'h',
                helperText: context.tr(
                    pl: 'Z tabeli: ${formatSpan(Duration(minutes: tableMinutes))}',
                    en: 'Table: ${formatSpan(Duration(minutes: tableMinutes))}'),
                errorMaxLines: 3,
                errorText: minutes == null
                    ? context.tr(pl: 'Podaj 0,1–168 h', en: 'Enter 0.1–168 h')
                    : raiseBlocked
                        ? context.tr(
                            pl: 'Nie więcej niż '
                                '${formatSpan(widget.batch.limit)} — partia '
                                'przekroczona.',
                            en: 'No more than ${formatSpan(widget.batch.limit)} '
                                '— the batch is over its limit.')
                        : null,
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              key: const ValueKey('electrode-redries-edit'),
              controller: _redries,
              keyboardType: numberKeyboard(decimal: false),
              inputFormatters: numberInputFormatters(decimal: false),
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                labelText: context.tr(
                    pl: 'Dopuszczalne suszenia', en: 'Allowed re-dries'),
                border: const OutlineInputBorder(),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(context.tr(pl: 'Anuluj', en: 'Cancel')),
        ),
        TextButton(
          key: const ValueKey('electrode-limit-save'),
          onPressed:
              ok ? () => Navigator.of(context).pop((minutes, redries)) : null,
          child: Text(context.tr(pl: 'Zapisz', en: 'Save')),
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// FORMULARZ „WYJĄŁEM ELEKTRODY”
// ═══════════════════════════════════════════════════════════════════════════

const List<double> _kDiameters = [2.5, 3.2, 4.0, 5.0];

/// Formularz nowej partii — prywatny: wpis audytu modułu ma tylko ekran
/// główny [ElectrodeExposurePage].
class _TakeOutPage extends StatefulWidget {
  const _TakeOutPage(
      {required this.session, required this.id, required this.now});

  final LocalRecordSession session;
  final String id;
  final DateTime Function() now;

  @override
  State<_TakeOutPage> createState() => _TakeOutPageState();
}

class _TakeOutPageState extends State<_TakeOutPage> {
  ElectrodeClass _class = ElectrodeClass.e7018;
  ElectrodeSource _source = ElectrodeSource.oven;
  double? _diameter = 3.2;
  final _qty = TextEditingController();
  final _location = TextEditingController();
  final _limit = TextEditingController();
  final _redries = TextEditingController();
  bool _limitEdited = false;
  bool _redriesEdited = false;
  late DateTime _at = _minute(widget.now());
  bool _initialized = false;

  static DateTime _minute(DateTime t) =>
      DateTime(t.year, t.month, t.day, t.hour, t.minute);

  bool get _en => context.language == AppLanguage.en;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialized) return;
    _initialized = true;
    _syncDefaults();
  }

  @override
  void dispose() {
    for (final c in [_qty, _location, _limit, _redries]) {
      c.dispose();
    }
    super.dispose();
  }

  void _syncDefaults() {
    if (!_limitEdited) {
      _limit.text = _hoursText(defaultLimitMinutes(_class, _source), en: _en);
    }
    if (!_redriesEdited) _redries.text = '${defaultMaxRedries(_class)}';
  }

  void _shift(int minutes) {
    final now = _minute(widget.now());
    setState(() => _at = now.subtract(Duration(minutes: minutes)));
  }

  Future<void> _pickTime() async {
    if (!widget.session.isCurrent) return;
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_at),
      builder: (ctx, child) => LocalRecordScope(
        originSession: widget.session,
        restartOnAccountChange: false,
        builder: (_, __) => MediaQuery(
          data: MediaQuery.of(ctx).copyWith(alwaysUse24HourFormat: true),
          child: child!,
        ),
      ),
    );
    if (picked == null || !mounted || !widget.session.isCurrent) return;
    // Godzina „z przyszłości” to wczoraj (nocna zmiana) — kalendarzowo,
    // bez odejmowania 24 h (doba zmiany czasu).
    final at = resolvePickedTime(widget.now(), picked.hour, picked.minute);
    setState(() => _at = at);
  }

  void _save() {
    if (!widget.session.isCurrent) return;
    final minutes = _parseHours(_limit.text);
    final redries = int.tryParse(_redries.text.trim());
    if (minutes == null || redries == null || redries < 0) return;
    Navigator.of(context).pop(ElectrodeBatch.takenOut(
      id: widget.id,
      electrode: _class,
      source: _source,
      at: _at,
      diameterMm: _diameter,
      quantity: _qty.text,
      location: _location.text,
      limitMinutes: minutes,
      maxRedries: redries,
    ));
  }

  Widget _chip(String key, String label, bool selected, VoidCallback onTap) =>
      ChoiceChip(
        key: ValueKey(key),
        materialTapTargetSize: MaterialTapTargetSize.padded,
        label: Text(label),
        selected: selected,
        onSelected: (_) => onTap(),
      );

  @override
  Widget build(BuildContext context) {
    final minutes = _parseHours(_limit.text);
    final redries = int.tryParse(_redries.text.trim());
    final valid = minutes != null && redries != null && redries >= 0;
    final now = widget.now();
    final sameDay =
        _at.year == now.year && _at.month == now.month && _at.day == now.day;
    final tableMinutes = defaultLimitMinutes(_class, _source);
    final fam = _class.family;

    return Scaffold(
      appBar: AppBar(
          title: Text(
              context.tr(pl: 'Wyjąłem elektrody', en: 'Took electrodes out'))),
      // Formularz krótki — SingleChildScrollView buduje wszystkie pola od
      // razu (domyślne wartości limitu widać i testuje się bez przewijania).
      body: SingleChildScrollView(
        key: const ValueKey('electrode-form-list'),
        padding: EdgeInsets.fromLTRB(
            16, 12, 16, 24 + MediaQuery.viewPaddingOf(context).bottom),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            QuoteSection(
              title: context.tr(pl: 'Klasyfikacja', en: 'Classification'),
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    for (final c in ElectrodeClass.values)
                      _chip(
                          'electrode-class-${c.name}',
                          c.code,
                          _class == c,
                          () => setState(() {
                                _class = c;
                                _syncDefaults();
                              })),
                  ],
                ),
                const SizedBox(height: 8),
                Text(_class.desc(en: _en),
                    key: const ValueKey('electrode-class-desc'),
                    style: const TextStyle(fontSize: 12.5, color: kTextSec)),
              ],
            ),
            QuoteSection(
              title: context.tr(pl: 'Skąd', en: 'Source'),
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    _chip(
                        'electrode-source-oven',
                        context.tr(
                            pl: 'Z piecyka / termosu',
                            en: 'From oven / quiver'),
                        _source == ElectrodeSource.oven,
                        () => setState(() {
                              _source = ElectrodeSource.oven;
                              _syncDefaults();
                            })),
                    _chip(
                        'electrode-source-hermeticPack',
                        context.tr(
                            pl: 'Otwarte opakowanie próżniowe',
                            en: 'Opened vacuum pack'),
                        _source == ElectrodeSource.hermeticPack,
                        () => setState(() {
                              _source = ElectrodeSource.hermeticPack;
                              _syncDefaults();
                            })),
                  ],
                ),
                if (_source == ElectrodeSource.hermeticPack)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      fam.perManufacturer
                          ? context.tr(
                              pl: 'Limit po otwarciu wg producenta: Lincoln SAHARA '
                                  'ReadyPack 8 h (≤ 35 °C, ≤ 90 % RH), Böhler DRY '
                                  'SYSTEM 9 h, Kobelco ok. 8 h (niektóre 4 h). '
                                  'Sprawdź etykietę.',
                              en: 'Limit after opening per manufacturer: Lincoln '
                                  'SAHARA ReadyPack 8 h (≤ 35 °C, ≤ 90 % RH), Böhler '
                                  'DRY SYSTEM 9 h, Kobelco approx. 8 h (some 4 h). '
                                  'Check the label.')
                          : context.tr(
                              pl: 'AWS D1.1 obowiązuje też po otwarciu opakowania '
                                  'hermetycznego. Próżniowe E7018 to zwykle H4R — '
                                  'wybierz „E7018 H4R / H8R” (9 h).',
                              en: 'AWS D1.1 also applies after opening a hermetic '
                                  'pack. Vacuum-packed E7018 is usually H4R — pick '
                                  '“E7018 H4R / H8R” (9 h).'),
                      key: const ValueKey('electrode-pack-note'),
                      style: const TextStyle(fontSize: 12, color: kTextMut),
                    ),
                  ),
              ],
            ),
            QuoteSection(
              title: context.tr(pl: 'Partia', en: 'Batch'),
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    for (final d in _kDiameters)
                      _chip(
                          'electrode-dia-$d',
                          'Ø${formatDiameter(d, en: _en)}',
                          _diameter == d,
                          () => setState(() => _diameter = d)),
                    _chip(
                        'electrode-dia-none',
                        context.tr(pl: 'inna', en: 'other'),
                        _diameter == null,
                        () => setState(() => _diameter = null)),
                  ],
                ),
                const SizedBox(height: 12),
                TextField(
                  key: const ValueKey('electrode-qty'),
                  controller: _qty,
                  textInputAction: TextInputAction.next,
                  decoration: InputDecoration(
                    labelText: context.tr(
                        pl: 'Ilość / notatka', en: 'Quantity / note'),
                    hintText: context.tr(pl: 'np. 40 szt.', en: 'e.g. 40 pcs'),
                    border: const OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  key: const ValueKey('electrode-location'),
                  controller: _location,
                  decoration: InputDecoration(
                    labelText: context.tr(pl: 'Miejsce', en: 'Location'),
                    hintText: context.tr(
                        pl: 'np. hala B, rurociąg 12',
                        en: 'e.g. hall B, line 12'),
                    border: const OutlineInputBorder(),
                  ),
                ),
              ],
            ),
            QuoteSection(
              title: context.tr(pl: 'Godzina wyjęcia', en: 'Time taken out'),
              children: [
                Text(
                  '${sameDay ? context.tr(pl: 'dziś', en: 'today') : formatYmd(_at)} '
                  '${formatHm(_at)}',
                  key: const ValueKey('electrode-time'),
                  style: const TextStyle(
                      fontSize: 22, fontWeight: FontWeight.w900, color: kText),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    OutlinedButton(
                      key: const ValueKey('electrode-time-now'),
                      style: _gloveStyle(kText),
                      onPressed: () => _shift(0),
                      child: Text(context.tr(pl: 'Teraz', en: 'Now')),
                    ),
                    OutlinedButton(
                      key: const ValueKey('electrode-time-15'),
                      style: _gloveStyle(kText),
                      onPressed: () => _shift(15),
                      child: const Text('−15 min'),
                    ),
                    OutlinedButton(
                      key: const ValueKey('electrode-time-30'),
                      style: _gloveStyle(kText),
                      onPressed: () => _shift(30),
                      child: const Text('−30 min'),
                    ),
                    OutlinedButton.icon(
                      key: const ValueKey('electrode-time-pick'),
                      style: _gloveStyle(kArc),
                      onPressed: () => unawaited(_pickTime()),
                      icon: const Icon(Icons.schedule, size: 20),
                      label: Text(
                          context.tr(pl: 'Inna godzina', en: 'Other time')),
                    ),
                  ],
                ),
              ],
            ),
            QuoteSection(
              title: context.tr(pl: 'Limit', en: 'Limit'),
              subtitle: fam.perManufacturer
                  ? context.tr(
                      pl: 'Norma EN nie podaje czasu — przyjęto '
                          '${formatSpan(Duration(minutes: tableMinutes))} '
                          '(ostrożnie, jak AWS tej wytrzymałości). Wpisz limit '
                          'z karty producenta albo WPS.',
                      en: 'The EN standard gives no time — '
                          '${formatSpan(Duration(minutes: tableMinutes))} assumed '
                          '(conservative, as AWS of this strength). Enter the '
                          'limit from the data sheet or WPS.')
                  : context.tr(
                      pl: 'Z tabeli: ${formatSpan(Duration(minutes: tableMinutes))} '
                          '(AWS D1.1 Tab. 7.1, kol. A). WPS, AWS D1.5 albo '
                          'producent może być ostrzejszy — wpisz mniejszy.',
                      en: 'Table: ${formatSpan(Duration(minutes: tableMinutes))} '
                          '(AWS D1.1 Table 7.1, column A). The WPS, AWS D1.5 or '
                          'the manufacturer may be stricter — enter less.'),
              children: [
                TextField(
                  key: const ValueKey('electrode-limit'),
                  controller: _limit,
                  keyboardType: numberKeyboard(),
                  inputFormatters: numberInputFormatters(),
                  onChanged: (_) => setState(() => _limitEdited = true),
                  decoration: InputDecoration(
                    labelText: context.tr(
                        pl: 'Czas na powietrzu', en: 'Atmospheric exposure'),
                    suffixText: 'h',
                    errorText: minutes == null
                        ? context.tr(
                            pl: 'Podaj 0,1–168 h', en: 'Enter 0.1–168 h')
                        : null,
                    border: const OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  key: const ValueKey('electrode-max-redries'),
                  controller: _redries,
                  keyboardType: numberKeyboard(decimal: false),
                  inputFormatters: numberInputFormatters(decimal: false),
                  onChanged: (_) => setState(() => _redriesEdited = true),
                  decoration: InputDecoration(
                    labelText: context.tr(
                        pl: 'Dopuszczalne ponowne suszenia',
                        en: 'Allowed re-drying cycles'),
                    helperText: fam.perManufacturer
                        ? context.tr(
                            pl: 'Wg producenta (Lincoln Europe: 2; Lincoln US '
                                'dla E8018+: 3).',
                            en: 'Per manufacturer (Lincoln Europe: 2; Lincoln '
                                'US for E8018+: 3).')
                        : context.tr(
                            pl: 'AWS D1.1: najwyżej 1.',
                            en: 'AWS D1.1: no more than 1.'),
                    helperMaxLines: 2,
                    border: const OutlineInputBorder(),
                  ),
                ),
              ],
            ),
            SizedBox(
              height: 52,
              child: FilledButton.icon(
                key: const ValueKey('electrode-save'),
                style: FilledButton.styleFrom(
                  backgroundColor: kArc,
                  foregroundColor: kOnArc,
                  minimumSize: const Size.fromHeight(52),
                ),
                onPressed: valid ? _save : null,
                icon: const Icon(Icons.timer_outlined),
                label: Text(
                    context.tr(
                        pl: 'Zapisz i licz czas', en: 'Save and start timer'),
                    style: const TextStyle(fontWeight: FontWeight.w800)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
