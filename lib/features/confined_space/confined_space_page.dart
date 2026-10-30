// Przestrzeń zamknięta: wejście i spawanie — nowy protokół, „jak wczoraj”
// (kopia danych bez pomiarów i odhaczeń) i historia ostatnich protokołów
// (SharedPreferences, bez zmian schematu bazy).
//
// MODUŁ BEZPIECZEŃSTWA: aplikacja jest listą pomocniczą — wiążą przepisy,
// instrukcja zakładu i pisemne pozwolenie (zastrzeżenie na górze ekranu).
// Uszkodzony zapis nie znika po cichu: baner + kopia surowego tekstu.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../../domain/confined_space/confined_space_record.dart';
import '../../assistant/core/tool_bridge.dart';
import '../../domain/confined_space/confined_space_text.dart';
import '../../i18n/app_language.dart';
import '../../theme/app_theme.dart';
import '../quotes/quote_widgets.dart' show QuoteNotice, QuoteSection;
import 'confined_space_edit_page.dart';
import 'confined_space_store.dart';
import '../../widgets/local_record_scope.dart';

class ConfinedSpacePage extends StatelessWidget {
  const ConfinedSpacePage({
    super.key,
    this.store,
    this.now = DateTime.now,
    this.newId,
    this.shareText = confinedSpaceDefaultShareText,
    this.sharePdf = confinedSpaceDefaultSharePdf,
    this.pickTime = confinedSpaceDefaultPickTime,
  });

  final ConfinedSpaceStore? store;
  final DateTime Function() now;

  /// Identyfikator nowego protokołu — wstrzykiwany w testach.
  final String Function()? newId;
  final ConfinedSpaceShareText shareText;
  final ConfinedSpaceSharePdf sharePdf;
  final ConfinedSpacePickTime pickTime;

  @override
  Widget build(BuildContext context) => LocalRecordScope(
        builder: (_, session) => _ConfinedSpaceBody(
          session: session,
          store:
              store ?? ConfinedSpaceStore(captureOwner: session.captureOwner),
          now: now,
          newId: newId,
          shareText: shareText,
          sharePdf: sharePdf,
          pickTime: pickTime,
        ),
      );
}

class _ConfinedSpaceBody extends StatefulWidget {
  const _ConfinedSpaceBody({
    required this.session,
    required this.store,
    required this.now,
    required this.newId,
    required this.shareText,
    required this.sharePdf,
    required this.pickTime,
  });

  final LocalRecordSession session;
  final ConfinedSpaceStore store;
  final DateTime Function() now;
  final String Function()? newId;
  final ConfinedSpaceShareText shareText;
  final ConfinedSpaceSharePdf sharePdf;
  final ConfinedSpacePickTime pickTime;

  @override
  State<_ConfinedSpaceBody> createState() => _ConfinedSpacePageState();
}

enum _ItemAction { duplicate, delete }

class _ConfinedSpacePageState extends State<_ConfinedSpaceBody>
    with ToolHandleHost<_ConfinedSpaceBody> {
  @override
  String get toolId => 'confined_space';
  @override
  Set<String> get supportedFields => const {'record_id'};
  @override
  Future<Set<String>> apply(Map<String, Object?> fields) async {
    if (!mounted || !widget.session.isCurrent) return fields.keys.toSet();
    if (fields.length != 1 || fields['record_id'] is! String) {
      return fields.keys.toSet();
    }
    final load = await _store.load();
    final found = load.records.where((r) => r.id == fields['record_id']);
    if (!mounted ||
        !widget.session.isCurrent ||
        load.damaged ||
        found.length != 1 ||
        ModalRoute.of(context)?.isCurrent != true) {
      return {'record_id'};
    }
    unawaited(_open(found.single));
    return {};
  }

  List<ConfinedSpaceRecord>? _items;
  bool _loadFailed = false;

  /// Magazyn z zegarem ekranu (pomiary „z przyszłości” przy odczycie).
  late final ConfinedSpaceStore _store = widget.store.withClock(widget.now);

  /// Ostatni odczyt coś odrzucił (baner do końca wizyty na ekranie).
  ConfinedSpaceLoad? _damage;

  /// Co minutę przelicz stan — pomiar starzeje się bez dotykania ekranu
  /// (zielony nie może wisieć po upływie ważności pomiaru).
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted && widget.session.isCurrent) setState(() {});
    });
    ConfinedSpaceStore.changes.addListener(_onStoreChanged);
    unawaited(_reload());
  }

  @override
  void dispose() {
    _tick?.cancel();
    ConfinedSpaceStore.changes.removeListener(_onStoreChanged);
    super.dispose();
  }

  /// Zapis spoza tego ekranu (np. „Cofnij” po zamknięciu protokołu) —
  /// odśwież listę, gdy jest na wierzchu (w trakcie edycji nie trzeba:
  /// powrót i tak przeładowuje).
  void _onStoreChanged() {
    if (!mounted || !widget.session.isCurrent) return;
    if (ModalRoute.of(context)?.isCurrent ?? true) unawaited(_reload());
  }

  Future<void> _reload() async {
    try {
      final load = await _store.load();
      if (!mounted || !widget.session.isCurrent) return;
      setState(() {
        _items = load.records;
        _loadFailed = load.readFailed;
        if (load.damaged) _damage = load;
      });
      if (!load.damaged) markReady();
    } catch (e) {
      debugPrint('[confined_space] load failed: $e');
      if (!mounted || !widget.session.isCurrent) return;
      setState(() {
        _items = const [];
        _loadFailed = true;
      });
    }
  }

  String _id() => widget.newId?.call() ?? const Uuid().v4();

  /// Historia pełna — nowego protokołu nie da się zapisać; mówimy to od
  /// razu, zamiast otwierać formularz, który się nie zapisze.
  bool _refuseWhenFull() {
    if ((_items?.length ?? 0) < ConfinedSpaceStore.maxEntries) return false;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        key: const ValueKey('cs-store-full'),
        content: Text(context.tr(
          pl: 'Historia pełna (${ConfinedSpaceStore.maxEntries} protokołów) '
              '— udostępnij i usuń stare protokoły, żeby dodać nowy.',
          en: 'History full (${ConfinedSpaceStore.maxEntries} records) — '
              'share and delete old records to add a new one.',
        )),
      ));
    return true;
  }

  Future<void> _open(ConfinedSpaceRecord record) async {
    if (!widget.session.isCurrent) return;
    await Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => LocalRecordScope(
          originSession: widget.session,
          restartOnAccountChange: false,
          builder: (_, session) => ConfinedSpaceEditPage(
                initial: record,
                store: _store,
                session: session,
                now: widget.now,
                shareText: widget.shareText,
                sharePdf: widget.sharePdf,
                pickTime: widget.pickTime,
              )),
    ));
    if (mounted && widget.session.isCurrent) await _reload();
  }

  Future<void> _new() async {
    if (!widget.session.isCurrent) return;
    if (_refuseWhenFull()) return;
    await _open(ConfinedSpaceRecord.blank(id: _id(), now: widget.now()));
  }

  /// „Jak wczoraj”: dane organizacyjne i progi zostają, pomiary,
  /// odhaczenia i wyłączone gazy — nie.
  Future<void> _duplicate(ConfinedSpaceRecord source) async {
    if (!widget.session.isCurrent) return;
    if (_refuseWhenFull()) return;
    final copy = source.duplicateFor(newId: _id(), now: widget.now());
    try {
      await _store.upsert(copy);
    } catch (e) {
      debugPrint('[confined_space] duplicate save failed: $e');
      if (mounted && widget.session.isCurrent) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          key: const ValueKey('cs-duplicate-failed'),
          content: Text(context.tr(
            pl: 'Nie udało się zapisać kopii. Protokół nie został otwarty.',
            en: 'Could not save the copy. The record was not opened.',
          )),
        ));
        await _reload();
      }
      return;
    }
    if (!mounted || !widget.session.isCurrent) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(context.tr(
          pl: 'Kopia na dziś — pomiary atmosfery i listę wykonaj od nowa.',
          en: 'Copy for today — redo the gas readings and the checklist.',
        )),
      ));
    await _open(copy);
  }

  Future<void> _delete(ConfinedSpaceRecord record) async {
    if (!widget.session.isCurrent) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => LocalRecordScope(
        originSession: widget.session,
        restartOnAccountChange: false,
        builder: (dialogCtx, __) => AlertDialog(
          title: Text(
              context.tr(pl: 'Usunąć protokół?', en: 'Delete this record?')),
          content: Text(_titleOf(record)),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogCtx, false),
              child: Text(context.tr(pl: 'Anuluj', en: 'Cancel')),
            ),
            FilledButton(
              key: const ValueKey('cs-delete-confirm'),
              style: FilledButton.styleFrom(
                  backgroundColor: kFail, foregroundColor: Colors.white),
              onPressed: () => Navigator.pop(dialogCtx, true),
              child: Text(context.tr(pl: 'Usuń', en: 'Delete')),
            ),
          ],
        ),
      ),
    );
    if (ok != true || !mounted || !widget.session.isCurrent) return;
    try {
      await _store.delete(record.id);
    } catch (e) {
      debugPrint('[confined_space] delete failed: $e');
      if (mounted && widget.session.isCurrent) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          key: const ValueKey('cs-delete-failed'),
          content: Text(context.tr(
            pl: 'Nie udało się usunąć protokołu — sprawdź historię.',
            en: 'Could not delete the record — check the history.',
          )),
        ));
        await _reload();
      }
      return;
    }
    await _reload();
    if (!mounted || !widget.session.isCurrent) return;
    final store = _store;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content:
            Text(context.tr(pl: 'Protokół usunięty.', en: 'Record deleted.')),
        action: SnackBarAction(
          label: context.tr(pl: 'Cofnij', en: 'Undo'),
          // Zapis przez magazyn — działa także po opuszczeniu ekranu.
          onPressed: () async {
            if (!widget.session.isCurrent) return;
            try {
              await store.restore(record);
            } catch (e) {
              debugPrint('[confined_space] undo delete failed: $e');
            }
            if (mounted && widget.session.isCurrent) await _reload();
          },
        ),
      ));
  }

  String _titleOf(ConfinedSpaceRecord r) {
    final location = r.location.trim();
    if (location.isNotEmpty) return location;
    final description = r.description.trim();
    if (description.isNotEmpty) return description;
    return context.tr(pl: '(bez nazwy przestrzeni)', en: '(no space name)');
  }

  @override
  Widget build(BuildContext context) {
    final en = context.language == AppLanguage.en;
    final items = _items;
    final damage = _damage;
    return Scaffold(
      appBar: AppBar(
        title: Text(context.tr(
            pl: 'Przestrzeń zamknięta: wejście i spawanie',
            en: 'Confined space: entry and welding')),
      ),
      body: ListView(
        key: const ValueKey('cs-list'),
        padding: EdgeInsets.fromLTRB(
            12, 12, 12, 24 + MediaQuery.viewPaddingOf(context).bottom),
        children: [
          if (items != null && items.length >= ConfinedSpaceStore.warnAt)
            QuoteNotice(
              key: const ValueKey('cs-store-warn'),
              color:
                  items.length >= ConfinedSpaceStore.maxEntries ? kFail : kWarn,
              icon: Icons.inventory_2_outlined,
              text: context.tr(
                pl: 'Historia: ${items.length}/${ConfinedSpaceStore.maxEntries} '
                    'protokołów. Przy pełnej nowego protokołu nie da się '
                    'zapisać — udostępnij (PDF) i usuń stare.',
                en: 'History: ${items.length}/${ConfinedSpaceStore.maxEntries} '
                    'records. When full, a new record cannot be saved — share '
                    '(PDF) and delete old ones.',
              ),
            ),
          if (damage != null)
            QuoteNotice(
              key: const ValueKey('cs-load-damaged'),
              color: kFail,
              icon: Icons.report_gmailerrorred_outlined,
              text: damage.readFailed
                  ? context.tr(
                      pl: 'Nie udało się odczytać historii. Zapis nowych '
                          'zmian jest wstrzymany, aby nie utracić danych.',
                      en: 'Could not read the history. New changes cannot '
                          'be saved until the data can be read.')
                  : damage.backupFailed
                      ? context.tr(
                          pl: 'Uszkodzony zapis pozostaje w telefonie, ale nie '
                              'udało się utworzyć jego kopii. Zapis nowych zmian '
                              'jest wstrzymany, aby nie utracić danych.',
                          en: 'The damaged data remains on this phone, but its '
                              'backup could not be made. New changes cannot be '
                              'saved until the data is protected.')
                      : damage.unreadable
                          ? context.tr(
                              pl: 'Zapisanej historii nie da się odczytać — kopia '
                                  'surowego zapisu została w telefonie.',
                              en: 'The saved history could not be read — a raw copy '
                                  'is kept on the phone.')
                          : context.tr(
                              pl: 'Część zapisu była nieczytelna: pominięto '
                                  '${damage.droppedRecords} protokołów i '
                                  '${damage.droppedMeasurements} pomiarów. Kopia '
                                  'surowego zapisu została w telefonie.',
                              en: 'Part of the saved data was unreadable: '
                                  '${damage.droppedRecords} record(s) and '
                                  '${damage.droppedMeasurements} reading(s) skipped. '
                                  'A raw copy is kept on the phone.'),
            ),
          QuoteNotice(
            icon: Icons.gavel_outlined,
            text: confinedSpaceDisclaimer(en: en),
          ),
          QuoteSection(
            title: context.tr(pl: 'Nowe wejście', en: 'New entry'),
            subtitle: context.tr(
              pl: 'Lista przed wejściem, pomiary O₂, gazów palnych, CO i H₂S '
                  'z godziną, ostrzeżenia dla spawacza (argon!) i protokół PDF '
                  'dla nadzoru.',
              en: 'Pre-entry checklist, O₂, flammable, CO and H₂S readings '
                  'with time, warnings for the welder (argon!) and a PDF '
                  'record for the supervisor.',
            ),
            children: [
              FilledButton.icon(
                key: const ValueKey('cs-new'),
                style: FilledButton.styleFrom(
                    minimumSize: const Size(0, kMinTapTarget)),
                onPressed: _new,
                icon: const Icon(Icons.add),
                label: Text(context.tr(pl: 'Nowy protokół', en: 'New record')),
              ),
              if (items != null && items.isNotEmpty) ...[
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  key: const ValueKey('cs-dup-last'),
                  style: OutlinedButton.styleFrom(
                      minimumSize: const Size(0, kMinTapTarget)),
                  onPressed: () => _duplicate(items.first),
                  icon: const Icon(Icons.copy_all_outlined),
                  label: Text(
                    context.tr(
                      pl: 'Jak wczoraj — kopia: ${_titleOf(items.first)}',
                      en: 'Same as yesterday — copy: '
                          '${_titleOf(items.first)}',
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ],
          ),
          QuoteSection(
            title: context.tr(
                pl: 'Historia (${items?.length ?? 0})',
                en: 'History (${items?.length ?? 0})'),
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
                          pl: 'Nie udało się wczytać historii.',
                          en: 'Could not load the history.')
                      : context.tr(
                          pl: 'Brak zapisanych protokołów.',
                          en: 'No saved records yet.'),
                  key: const ValueKey('cs-empty'),
                  style: const TextStyle(color: kTextSec, fontSize: 13.5),
                )
              else
                for (final (i, r) in items.indexed)
                  _HistoryTile(
                    key: ValueKey('cs-item-$i'),
                    now: widget.now(),
                    index: i,
                    record: r,
                    title: _titleOf(r),
                    en: en,
                    onOpen: () => _open(r),
                    onAction: (a) => switch (a) {
                      _ItemAction.duplicate => _duplicate(r),
                      _ItemAction.delete => _delete(r),
                    },
                  ),
            ],
          ),
        ],
      ),
    );
  }
}

class _HistoryTile extends StatelessWidget {
  const _HistoryTile({
    super.key,
    required this.index,
    required this.record,
    required this.title,
    required this.en,
    required this.onOpen,
    required this.onAction,
    required this.now,
  });

  final int index;
  final ConfinedSpaceRecord record;
  final String title;
  final bool en;
  final VoidCallback onOpen;
  final Future<void> Function(_ItemAction a) onAction;

  /// Chwila oceny (wiek pomiarów, data protokołu).
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final a = record.assess(now: now);
    final color = confinedSpaceReadinessColor(a);
    final processes = [
      for (final p in CsProcess.values)
        if (record.processes.contains(p)) p.label(en: en),
    ].join(', ');
    final sub = [
      record.date,
      if (confinedSpaceHours(record) != '—') confinedSpaceHours(record),
      if (processes.isNotEmpty) processes,
      if (record.permitNo.trim().isNotEmpty)
        '${en ? 'no.' : 'nr'} ${record.permitNo.trim()}',
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
          key: ValueKey('cs-open-$index'),
          onTap: onOpen,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 64),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 0, 8),
              child: Row(
                children: [
                  Icon(confinedSpaceReadinessIcon(a), color: color, size: 26),
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
                        Text(confinedSpaceReadinessShort(a, en: en),
                            key: ValueKey('cs-item-status-$index'),
                            style: TextStyle(
                                color: color,
                                fontSize: 12.5,
                                fontWeight: FontWeight.w800)),
                      ],
                    ),
                  ),
                  PopupMenuButton<_ItemAction>(
                    key: ValueKey('cs-menu-$index'),
                    tooltip: en ? 'More' : 'Więcej',
                    icon: const Icon(Icons.more_vert, color: kTextSec),
                    onSelected: onAction,
                    itemBuilder: (_) => [
                      PopupMenuItem(
                        key: const ValueKey('cs-menu-dup'),
                        value: _ItemAction.duplicate,
                        child: Text(en
                            ? 'Same as yesterday (copy for today)'
                            : 'Jak wczoraj (kopia na dziś)'),
                      ),
                      PopupMenuItem(
                        key: const ValueKey('cs-menu-del'),
                        value: _ItemAction.delete,
                        child: Text(en ? 'Delete' : 'Usuń'),
                      ),
                    ],
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
