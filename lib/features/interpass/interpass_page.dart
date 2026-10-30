import '../../widgets/local_record_scope.dart';
// Temperatura podgrzania i międzyściegowa — rejestr pomiarów spoin dla QC:
// lista spoin (SharedPreferences, bez zmian schematu bazy), nowa spoina,
// usuwanie z cofnięciem. Edycja jednej spoiny: interpass_weld_page.dart.
//
// Limity wpisuje się z WPS — aplikacja nie podaje „typowych” temperatur
// (lib/domain/welding/interpass_log.dart).

import 'dart:async';
import '../../assistant/core/tool_bridge.dart';

import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import 'package:uuid/uuid.dart';

import '../../database/weld_journal_dao.dart';
import '../../domain/weld_journal/weld_entry.dart';
import '../../domain/welding/interpass_log.dart';
import '../../domain/welding/interpass_text.dart';
import '../../i18n/app_language.dart';
import '../../services/interpass_export.dart';
import '../../theme/app_theme.dart';
import '../quotes/quote_widgets.dart' show QuoteNotice, QuoteSection;
import 'interpass_store.dart';
import 'interpass_weld_page.dart';

/// Udostępnienie tekstu — wstrzykiwane w testach.
typedef InterpassShareText = Future<void> Function(String text, String subject);

/// Udostępnienie PDF — wstrzykiwane w testach.
typedef InterpassSharePdf = Future<void> Function(
    InterpassWeld weld, bool english, InterpassUnit unit);

/// Spoiny z dziennika (lista wyboru) — wstrzykiwane w testach.
typedef InterpassJournalSource = Future<List<WeldEntry>> Function();

Future<void> interpassDefaultShareText(String text, String subject) async {
  await Share.share(text, subject: subject);
}

Future<void> interpassDefaultSharePdf(
        InterpassWeld weld, bool english, InterpassUnit unit) =>
    InterpassExport.sharePdf(weld, english: english, unit: unit);

/// Nieusunięte wpisy dziennika spoin (tylko odczyt, na żądanie).
Future<List<WeldEntry>> interpassDefaultJournalWelds() async =>
    (await WeldJournalDao().listAll()).where((e) => !e.isDeleted).toList();

/// Kolor werdyktu: czerwony tylko „poza limitem”, zielony tylko OK, szary
/// przy braku limitu z WPS (neutralnie), w pozostałych — ostrzeżenie.
Color interpassStatusColor(InterpassAssessment a) => switch (a.status) {
      InterpassWeldStatus.outOfLimits => kFail,
      InterpassWeldStatus.ok => kPass,
      InterpassWeldStatus.noLimit => kTextSec,
      _ => kWarn,
    };

class InterpassPage extends StatelessWidget {
  const InterpassPage({
    super.key,
    this.store = const InterpassStore(),
    this.now = DateTime.now,
    this.newId,
    this.shareText = interpassDefaultShareText,
    this.sharePdf = interpassDefaultSharePdf,
    this.loadWelds = interpassDefaultJournalWelds,
  });

  final InterpassStore store;
  final DateTime Function() now;

  /// Identyfikator nowej spoiny — wstrzykiwany w testach.
  final String Function()? newId;
  final InterpassShareText shareText;
  final InterpassSharePdf sharePdf;
  final InterpassJournalSource loadWelds;

  @override
  Widget build(BuildContext context) => LocalRecordScope(
      builder: (context, session) => _OwnedInterpassPage(
          session: session,
          store: store.scoped(session.captureOwner),
          now: now,
          newId: newId,
          shareText: shareText,
          sharePdf: sharePdf,
          loadWelds: loadWelds));
}

class _OwnedInterpassPage extends StatefulWidget {
  const _OwnedInterpassPage({
    required this.session,
    this.store = const InterpassStore(),
    this.now = DateTime.now,
    this.newId,
    this.shareText = interpassDefaultShareText,
    this.sharePdf = interpassDefaultSharePdf,
    this.loadWelds = interpassDefaultJournalWelds,
  });

  final LocalRecordSession session;
  final InterpassStore store;
  final DateTime Function() now;

  /// Identyfikator nowej spoiny — wstrzykiwany w testach.
  final String Function()? newId;
  final InterpassShareText shareText;
  final InterpassSharePdf sharePdf;
  final InterpassJournalSource loadWelds;

  @override
  State<_OwnedInterpassPage> createState() => _InterpassPageState();
}

class _InterpassPageState extends State<_OwnedInterpassPage>
    with ToolHandleHost<_OwnedInterpassPage> {
  @override
  String get toolId => 'interpass';
  @override
  Set<String> get supportedFields => const {'weld_id'};
  @override
  Future<Set<String>> apply(Map<String, Object?> fields) async {
    if (fields.length != 1 || fields['weld_id'] is! String) {
      return fields.keys.toSet();
    }
    final load = await widget.store.load();
    final found = load.welds.where((w) => w.id == fields['weld_id']).toList();
    if (!mounted || load.corrupt || found.length != 1) return {'weld_id'};
    unawaited(_open(found.single));
    return {};
  }

  void _onStoreChanged() {
    if (mounted && (ModalRoute.of(context)?.isCurrent ?? true)) {
      unawaited(_reload());
    }
  }

  @override
  void dispose() {
    InterpassStore.changes.removeListener(_onStoreChanged);
    super.dispose();
  }

  List<InterpassWeld>? _items;
  bool _corrupt = false;
  bool _backupFailed = false;
  bool _loadFailed = false;
  InterpassUnit _unit = InterpassUnit.c;

  @override
  void initState() {
    super.initState();
    InterpassStore.changes.addListener(_onStoreChanged);
    unawaited(_reload());
  }

  Future<void> _reload() async {
    var unit = _unit;
    try {
      unit = await widget.store.loadUnit();
    } catch (e) {
      debugPrint('[interpass] unit load failed: $e');
    }
    try {
      final load = await widget.store.load();
      if (!mounted || !widget.session.isCurrent) return;
      setState(() {
        _items = load.welds;
        _corrupt = load.corrupt;
        _backupFailed = load.backupFailed;
        _loadFailed = load.readFailed;
        _unit = unit;
      });
      if (!load.corrupt && !load.readFailed) markReady();
    } catch (e) {
      debugPrint('[interpass] load failed: $e');
      if (!mounted || !widget.session.isCurrent) return;
      setState(() {
        _items = const [];
        _loadFailed = true;
        _unit = unit;
      });
    }
  }

  /// Odświeżenie po zmianie zapisu z zamkniętego ekranu spoiny (np. „Cofnij”
  /// w snackbarze, który wisi już nad listą).
  Future<void> _reloadIfMounted() async {
    if (mounted) await _reload();
  }

  String _id() => widget.newId?.call() ?? const Uuid().v4();

  Future<void> _open(InterpassWeld weld) async {
    await Navigator.of(context).push(MaterialPageRoute<void>(
      settings: const RouteSettings(name: 'tool:interpass'),
      builder: (_) => InterpassWeldPage(
        originSession: widget.session,
        initial: weld,
        unit: _unit,
        store: widget.store,
        now: widget.now,
        shareText: widget.shareText,
        sharePdf: widget.sharePdf,
        loadWelds: widget.loadWelds,
        onStoreChanged: _reloadIfMounted,
      ),
    ));
    await _reload();
  }

  Future<void> _new() async {
    if (!widget.session.isCurrent) return;
    if (_backupFailed || _loadFailed) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(
          key: const ValueKey('ip-store-unavailable'),
          content: Text(context.tr(
            pl: 'Nie można bezpiecznie zapisać rejestru. Dane pozostają w telefonie; sprawdź historię.',
            en: 'The log cannot be saved safely. The data remains on this phone; check the history.',
          )),
        ));
      return;
    }
    if ((_items?.length ?? 0) >= InterpassStore.maxWelds) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(
          key: const ValueKey('ip-full'),
          content: Text(context.tr(
            pl: 'Rejestr pełny (${InterpassStore.maxWelds} spoin). Udostępnij '
                'protokoły starych spoin i usuń je.',
            en: 'The log is full (${InterpassStore.maxWelds} welds). Share '
                'the old welds’ records and delete them.',
          )),
        ));
      return;
    }
    await _open(InterpassWeld.blank(id: _id(), now: widget.now()));
  }

  Future<void> _delete(InterpassWeld weld) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => LocalRecordScope(
          restartOnAccountChange: false,
          originSession: widget.session,
          builder: (dialogCtx, _) => AlertDialog(
                title: Text(
                    context.tr(pl: 'Usunąć spoinę?', en: 'Delete this weld?')),
                content: Text(context.tr(
                  pl: '${_titleOf(weld)} — razem z pomiarami. Najpierw udostępnij '
                      'protokół, jeśli QC go potrzebuje.',
                  en: '${_titleOf(weld)} — with its readings. Share the record '
                      'first if QC needs it.',
                )),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(dialogCtx, false),
                    child: Text(context.tr(pl: 'Anuluj', en: 'Cancel')),
                  ),
                  FilledButton(
                    key: const ValueKey('ip-delete-confirm'),
                    style: FilledButton.styleFrom(
                        backgroundColor: kFail, foregroundColor: Colors.white),
                    onPressed: () => Navigator.pop(dialogCtx, true),
                    child: Text(context.tr(pl: 'Usuń', en: 'Delete')),
                  ),
                ],
              )),
    );
    if (ok != true || !mounted || !widget.session.isCurrent) return;
    try {
      await widget.store.delete(weld.id);
    } catch (e) {
      debugPrint('[interpass] delete failed: $e');
      if (mounted && widget.session.isCurrent) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(
            key: const ValueKey('ip-delete-failed'),
            content: Text(context.tr(
              pl: 'Nie udało się usunąć spoiny — sprawdź rejestr.',
              en: 'Could not delete the weld — check the log.',
            )),
          ));
        await _reload();
      }
      return;
    }
    await _reload();
    if (!mounted || !widget.session.isCurrent) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(context.tr(pl: 'Spoina usunięta.', en: 'Weld deleted.')),
        action: SnackBarAction(
          label: context.tr(pl: 'Cofnij', en: 'Undo'),
          onPressed: () async {
            if (!widget.session.isCurrent) return;
            try {
              await widget.store.upsert(weld);
            } catch (e) {
              debugPrint('[interpass] undo failed: $e');
            }
            if (mounted && widget.session.isCurrent) await _reload();
          },
        ),
      ));
  }

  String _titleOf(InterpassWeld w) {
    final no = w.weldNo.trim();
    if (no.isNotEmpty) return no;
    final d = w.description.trim();
    if (d.isNotEmpty) return d;
    return context.tr(pl: '(bez numeru)', en: '(no number)');
  }

  @override
  Widget build(BuildContext context) {
    final en = context.language == AppLanguage.en;
    final items = _items;
    final count = items?.length ?? 0;
    return Scaffold(
      appBar: AppBar(
        title: Text(context.tr(
            pl: 'Podgrzanie i międzyściegowa', en: 'Preheat and interpass')),
      ),
      body: ListView(
        key: const ValueKey('ip-list'),
        padding: EdgeInsets.fromLTRB(
            12, 12, 12, 24 + MediaQuery.viewPaddingOf(context).bottom),
        children: [
          QuoteNotice(
            icon: Icons.thermostat_outlined,
            text: interpassDisclaimer(en: en),
          ),
          if (_corrupt && !_loadFailed)
            QuoteNotice(
              key: const ValueKey('ip-corrupt'),
              color: kFail,
              icon: Icons.report_problem_outlined,
              text: _backupFailed
                  ? context.tr(
                      pl: 'Część zapisu była nieczytelna. Nie udało się zachować kopii, więc rejestr nie zostanie nadpisany.',
                      en: 'Part of the saved data could not be read. A backup could not be kept, so the log will not be overwritten.',
                    )
                  : context.tr(
                      pl: 'Część zapisu w telefonie była nieczytelna — surowa '
                          'kopia została zachowana, nowe zmiany zapisują się '
                          'normalnie.',
                      en: 'Part of the saved data could not be read — a raw copy '
                          'was kept; new changes are saved normally.',
                    ),
            ),
          QuoteSection(
            title: context.tr(pl: 'Nowa spoina', en: 'New weld'),
            subtitle: context.tr(
              pl: 'Limity z WPS, pomiar przed każdym ściegiem, werdykt '
                  'i protokół (tekst / PDF) dla QC.',
              en: 'WPS limits, a reading before every run, verdict and a '
                  'record (text / PDF) for QC.',
            ),
            children: [
              FilledButton.icon(
                key: const ValueKey('ip-new'),
                style: FilledButton.styleFrom(
                    minimumSize: const Size(0, kMinTapTarget)),
                onPressed: items == null ? null : _new,
                icon: const Icon(Icons.add),
                label: Text(context.tr(pl: 'Nowa spoina', en: 'New weld')),
              ),
              if (count >= InterpassStore.warnAt) ...[
                const SizedBox(height: 10),
                Text(
                  context.tr(
                    pl: 'Zapisanych spoin: $count z '
                        '${InterpassStore.maxWelds}. Udostępnij protokoły '
                        'zakończonych spoin i usuń je — przy pełnym rejestrze '
                        'nowej spoiny nie da się zapisać.',
                    en: 'Saved welds: $count of ${InterpassStore.maxWelds}. '
                        'Share the records of finished welds and delete '
                        'them — a full log cannot take a new weld.',
                  ),
                  key: const ValueKey('ip-limit-warn'),
                  style: const TextStyle(
                      color: kWarn, fontSize: 13, fontWeight: FontWeight.w600),
                ),
              ],
            ],
          ),
          QuoteSection(
            title: context.tr(pl: 'Spoiny ($count)', en: 'Welds ($count)'),
            children: [
              if (items == null)
                const Padding(
                  padding: EdgeInsets.all(12),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (items.isEmpty)
                Text(
                  _loadFailed
                      ? context.tr(
                          pl: 'Nie udało się wczytać rejestru.',
                          en: 'Could not load the log.')
                      : context.tr(
                          pl: 'Brak zapisanych spoin.',
                          en: 'No saved welds yet.'),
                  key: const ValueKey('ip-empty'),
                  style: const TextStyle(color: kTextSec, fontSize: 13.5),
                )
              else
                for (final (i, w) in items.indexed)
                  _WeldTile(
                    key: ValueKey('ip-item-$i'),
                    index: i,
                    weld: w,
                    title: _titleOf(w),
                    en: en,
                    onOpen: () => _open(w),
                    onDelete: () => _delete(w),
                  ),
            ],
          ),
        ],
      ),
    );
  }
}

class _WeldTile extends StatelessWidget {
  const _WeldTile({
    super.key,
    required this.index,
    required this.weld,
    required this.title,
    required this.en,
    required this.onOpen,
    required this.onDelete,
  });

  final int index;
  final InterpassWeld weld;
  final String title;
  final bool en;
  final VoidCallback onOpen;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final a = weld.assess();
    final color = interpassStatusColor(a);
    final chrono = a.chrono;
    final sub = [
      if (weld.wpsRef.trim().isNotEmpty) 'WPS ${weld.wpsRef.trim()}',
      en ? '${chrono.length} reading(s)' : 'pomiarów: ${chrono.length}',
      if (chrono.isNotEmpty) interpassDateTime(chrono.last.at),
    ].join(' · ');
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: kBg,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: const BorderSide(color: kBorder),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          key: ValueKey('ip-open-$index'),
          onTap: onOpen,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 64),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 0, 8),
              child: Row(
                children: [
                  Icon(
                    a.status == InterpassWeldStatus.outOfLimits
                        ? Icons.dangerous_outlined
                        : a.ok
                            ? Icons.verified_outlined
                            : Icons.thermostat_outlined,
                    color: color,
                    size: 26,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                color: kText,
                                fontSize: 15,
                                fontWeight: FontWeight.w700)),
                        const SizedBox(height: 2),
                        Text(sub,
                            style: const TextStyle(
                                color: kTextSec, fontSize: 12.5)),
                        const SizedBox(height: 2),
                        Text(interpassStatusShort(a, en: en),
                            key: ValueKey('ip-item-status-$index'),
                            style: TextStyle(
                                color: color,
                                fontSize: 12.5,
                                fontWeight: FontWeight.w800)),
                      ],
                    ),
                  ),
                  IconButton(
                    key: ValueKey('ip-del-$index'),
                    tooltip: en ? 'Delete' : 'Usuń',
                    constraints: const BoxConstraints(
                        minWidth: kMinTapTarget, minHeight: kMinTapTarget),
                    onPressed: onDelete,
                    icon: const Icon(Icons.delete_outline, color: kTextSec),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
