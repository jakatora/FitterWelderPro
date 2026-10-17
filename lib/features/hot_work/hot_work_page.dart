// Prace pożarowo niebezpieczne — zezwolenie i checklista: nowy protokół,
// „jak wczoraj” (kopia danych bez zaznaczeń i pomiarów) i historia
// ostatnich protokołów (SharedPreferences, bez zmian schematu bazy).
//
// MODUŁ BEZPIECZEŃSTWA: aplikacja jest listą pomocniczą — wiążące są
// przepisy, instrukcja bezpieczeństwa pożarowego zakładu i zezwolenie
// wystawione przez zakład (zastrzeżenie na górze ekranu).

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../../domain/hot_work/hot_work_permit.dart';
import '../../domain/hot_work/hot_work_text.dart';
import '../../i18n/app_language.dart';
import '../../theme/app_theme.dart';
import '../quotes/quote_widgets.dart' show QuoteNotice, QuoteSection;
import 'hot_work_edit_page.dart';
import 'hot_work_store.dart';

class HotWorkPage extends StatefulWidget {
  const HotWorkPage({
    super.key,
    this.store = const HotWorkStore(),
    this.now = DateTime.now,
    this.newId,
    this.shareText = hotWorkDefaultShareText,
    this.sharePdf = hotWorkDefaultSharePdf,
    this.pickTime = hotWorkDefaultPickTime,
  });

  final HotWorkStore store;
  final DateTime Function() now;

  /// Identyfikator nowego protokołu — wstrzykiwany w testach.
  final String Function()? newId;
  final HotWorkShareText shareText;
  final HotWorkSharePdf sharePdf;
  final HotWorkPickTime pickTime;

  @override
  State<HotWorkPage> createState() => _HotWorkPageState();
}

enum _ItemAction { duplicate, delete }

class _HotWorkPageState extends State<HotWorkPage> {
  List<HotWorkPermit>? _items;
  bool _loadFailed = false;

  /// Magazyn z zegarem ekranu (pomiary „z przyszłości” przy odczycie).
  late final HotWorkStore _store = widget.store.withClock(widget.now);

  /// Ostatni odczyt coś odrzucił (baner do końca wizyty na ekranie).
  HotWorkLoad? _damage;

  /// Co minutę przelicz stan — pomiar starzeje się bez dotykania ekranu
  /// (zielony nie może wisieć po upływie ważności pomiaru).
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() {});
    });
    unawaited(_reload());
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  Future<void> _reload() async {
    try {
      final load = await _store.loadReport();
      if (!mounted) return;
      setState(() {
        _items = load.permits;
        _loadFailed = false;
        if (load.damaged) _damage = load;
      });
    } catch (e) {
      debugPrint('[hot_work] load failed: $e');
      if (!mounted) return;
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
    if ((_items?.length ?? 0) < HotWorkStore.maxEntries) return false;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        key: const ValueKey('hw-store-full'),
        content: Text(context.tr(
          pl: 'Historia pełna (${HotWorkStore.maxEntries} protokołów) — '
              'udostępnij i usuń stare protokoły, żeby dodać nowy.',
          en: 'History full (${HotWorkStore.maxEntries} records) — share and '
              'delete old records to add a new one.',
        )),
      ));
    return true;
  }

  Future<void> _open(HotWorkPermit permit) async {
    await Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => HotWorkEditPage(
        initial: permit,
        store: _store,
        now: widget.now,
        shareText: widget.shareText,
        sharePdf: widget.sharePdf,
        pickTime: widget.pickTime,
      ),
    ));
    await _reload();
  }

  Future<void> _new() async {
    if (_refuseWhenFull()) return;
    await _open(HotWorkPermit.blank(id: _id(), now: widget.now()));
  }

  /// „Jak wczoraj”: dane organizacyjne zostają, zaznaczenia i pomiary — nie.
  Future<void> _duplicate(HotWorkPermit source) async {
    if (_refuseWhenFull()) return;
    final copy = source.duplicateFor(newId: _id(), now: widget.now());
    try {
      await _store.upsert(copy);
    } catch (e) {
      // Edycja i tak zapisuje się przy każdej zmianie — otwieramy kopię.
      debugPrint('[hot_work] duplicate save failed: $e');
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(context.tr(
          pl: 'Kopia na dziś — listę i pomiar wykonaj na miejscu od nowa.',
          en: 'Copy for today — redo the checklist and gas test on site.',
        )),
      ));
    await _open(copy);
  }

  Future<void> _delete(HotWorkPermit permit) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: Text(context.tr(
            pl: 'Usunąć protokół?', en: 'Delete this record?')),
        content: Text(_titleOf(permit)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx, false),
            child: Text(context.tr(pl: 'Anuluj', en: 'Cancel')),
          ),
          FilledButton(
            key: const ValueKey('hw-delete-confirm'),
            style: FilledButton.styleFrom(
                backgroundColor: kFail, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(dialogCtx, true),
            child: Text(context.tr(pl: 'Usuń', en: 'Delete')),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await _store.delete(permit.id);
    await _reload();
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(context.tr(pl: 'Protokół usunięty.', en: 'Record deleted.')),
        action: SnackBarAction(
          label: context.tr(pl: 'Cofnij', en: 'Undo'),
          onPressed: () async {
            await _store.upsert(permit);
            if (mounted) await _reload();
          },
        ),
      ));
  }

  String _titleOf(HotWorkPermit p) {
    final location = p.location.trim();
    if (location.isNotEmpty) return location;
    final description = p.description.trim();
    if (description.isNotEmpty) return description;
    return context.tr(pl: '(bez miejsca)', en: '(no location)');
  }

  @override
  Widget build(BuildContext context) {
    final en = context.language == AppLanguage.en;
    final items = _items;
    return Scaffold(
      appBar: AppBar(
        title: Text(context.tr(
            pl: 'Prace pożarowo niebezpieczne', en: 'Hot work permit')),
      ),
      body: ListView(
        key: const ValueKey('hw-list'),
        padding: EdgeInsets.fromLTRB(
            12, 12, 12, 24 + MediaQuery.viewPaddingOf(context).bottom),
        children: [
          if (items != null && items.length >= HotWorkStore.warnAt)
            QuoteNotice(
              key: const ValueKey('hw-store-warn'),
              color: items.length >= HotWorkStore.maxEntries ? kFail : kWarn,
              icon: Icons.inventory_2_outlined,
              text: context.tr(
                pl: 'Historia: ${items.length}/${HotWorkStore.maxEntries} '
                    'protokołów. Przy pełnej nowego protokołu nie da się '
                    'zapisać — udostępnij (PDF) i usuń stare.',
                en: 'History: ${items.length}/${HotWorkStore.maxEntries} '
                    'records. When full, a new record cannot be saved — share '
                    '(PDF) and delete old ones.',
              ),
            ),
          if (_damage != null)
            QuoteNotice(
              key: const ValueKey('hw-load-damaged'),
              color: kFail,
              icon: Icons.report_gmailerrorred_outlined,
              text: _damage!.unreadable
                  ? context.tr(
                      pl: 'Zapisanej historii nie da się odczytać — kopia '
                          'surowego zapisu została w telefonie.',
                      en: 'The saved history could not be read — a raw copy '
                          'is kept on the phone.')
                  : context.tr(
                      pl: 'Część zapisu była nieczytelna: pominięto '
                          '${_damage!.droppedPermits} protokołów i '
                          '${_damage!.droppedMeasurements} pomiarów. Kopia '
                          'surowego zapisu została w telefonie.',
                      en: 'Part of the saved data was unreadable: '
                          '${_damage!.droppedPermits} record(s) and '
                          '${_damage!.droppedMeasurements} reading(s) '
                          'skipped. A raw copy is kept on the phone.'),
            ),
          QuoteNotice(
            icon: Icons.gavel_outlined,
            text: hotWorkDisclaimer(en: en),
          ),
          QuoteSection(
            title: context.tr(pl: 'Nowa praca', en: 'New job'),
            subtitle: context.tr(
              pl: 'Lista kontrolna przygotowania stanowiska, pomiar '
                  'atmosfery, dane zezwolenia i protokół PDF dla nadzoru.',
              en: 'Work area checklist, gas test, permit details and a PDF '
                  'record for the supervisor.',
            ),
            children: [
              FilledButton.icon(
                key: const ValueKey('hw-new'),
                style: FilledButton.styleFrom(
                    minimumSize: const Size(0, kMinTapTarget)),
                onPressed: _new,
                icon: const Icon(Icons.add),
                label: Text(context.tr(pl: 'Nowy protokół', en: 'New record')),
              ),
              if (items != null && items.isNotEmpty) ...[
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  key: const ValueKey('hw-dup-last'),
                  style: OutlinedButton.styleFrom(
                      minimumSize: const Size(0, kMinTapTarget)),
                  onPressed: () => _duplicate(items.first),
                  icon: const Icon(Icons.copy_all_outlined),
                  label: Text(
                    context.tr(
                      pl: 'Jak wczoraj — kopia: ${_titleOf(items.first)}',
                      en: 'Same as yesterday — copy: ${_titleOf(items.first)}',
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
                  key: const ValueKey('hw-empty'),
                  style: const TextStyle(color: kTextSec, fontSize: 13.5),
                )
              else
                for (final (i, p) in items.indexed)
                  _HistoryTile(
                    key: ValueKey('hw-item-$i'),
                    now: widget.now(),
                    index: i,
                    permit: p,
                    title: _titleOf(p),
                    en: en,
                    onOpen: () => _open(p),
                    onAction: (a) => switch (a) {
                      _ItemAction.duplicate => _duplicate(p),
                      _ItemAction.delete => _delete(p),
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
    required this.permit,
    required this.title,
    required this.en,
    required this.onOpen,
    required this.onAction,
    required this.now,
  });

  final int index;
  final HotWorkPermit permit;
  final String title;
  final bool en;
  final VoidCallback onOpen;
  final Future<void> Function(_ItemAction a) onAction;

  /// Chwila oceny (wiek pomiaru, data protokołu).
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final a = permit.assess(now: now);
    final color = hotWorkReadinessColor(a);
    final types = [
      for (final t in HotWorkType.values)
        if (permit.workTypes.contains(t)) t.label(en: en),
    ].join(', ');
    final sub = [
      permit.date,
      if (hotWorkHours(permit) != '—') hotWorkHours(permit),
      if (types.isNotEmpty) types,
      if (permit.permitNo.trim().isNotEmpty)
        '${en ? 'no.' : 'nr'} ${permit.permitNo.trim()}',
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
          key: ValueKey('hw-open-$index'),
          onTap: onOpen,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 64),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 0, 8),
              child: Row(
                children: [
                  Icon(hotWorkReadinessIcon(a), color: color, size: 26),
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
                        Text(hotWorkReadinessShort(a, en: en),
                            key: ValueKey('hw-item-status-$index'),
                            style: TextStyle(
                                color: color,
                                fontSize: 12.5,
                                fontWeight: FontWeight.w800)),
                      ],
                    ),
                  ),
                  PopupMenuButton<_ItemAction>(
                    key: ValueKey('hw-menu-$index'),
                    tooltip: en ? 'More' : 'Więcej',
                    icon: const Icon(Icons.more_vert, color: kTextSec),
                    onSelected: onAction,
                    itemBuilder: (_) => [
                      PopupMenuItem(
                        key: const ValueKey('hw-menu-dup'),
                        value: _ItemAction.duplicate,
                        child: Text(en
                            ? 'Same as yesterday (copy for today)'
                            : 'Jak wczoraj (kopia na dziś)'),
                      ),
                      PopupMenuItem(
                        key: const ValueKey('hw-menu-del'),
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
