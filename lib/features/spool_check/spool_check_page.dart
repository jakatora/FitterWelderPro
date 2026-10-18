// Tolerancje spoola — kontrola wymiarów prefabrykatu przed wysyłką na
// budowę: nowy protokół, „następny spool z serii” (kopia wymiarów z
// rysunku bez pomiarów) i historia protokołów (SharedPreferences, bez zmian
// schematu bazy).

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../../domain/spool_check/spool_check.dart';
import '../../domain/spool_check/spool_check_text.dart';
import '../../i18n/app_language.dart';
import '../../theme/app_theme.dart';
import '../quotes/quote_widgets.dart' show QuoteNotice, QuoteSection;
import 'spool_check_edit_page.dart';
import 'spool_check_store.dart';

class SpoolCheckPage extends StatefulWidget {
  const SpoolCheckPage({
    super.key,
    this.store = const SpoolCheckStore(),
    this.now = DateTime.now,
    this.newId,
    this.shareText = spoolCheckDefaultShareText,
  });

  final SpoolCheckStore store;
  final DateTime Function() now;

  /// Identyfikator nowego protokołu / pozycji — wstrzykiwany w testach.
  final String Function()? newId;
  final SpoolCheckShareText shareText;

  @override
  State<SpoolCheckPage> createState() => _SpoolCheckPageState();
}

enum _ItemAction { duplicate, delete }

class _SpoolCheckPageState extends State<SpoolCheckPage> {
  List<SpoolCheck>? _items;
  bool _loadFailed = false;

  /// Ostatni odczyt coś odrzucił (baner do końca wizyty na ekranie).
  SpoolCheckLoad? _damage;

  @override
  void initState() {
    super.initState();
    unawaited(_reload());
  }

  Future<void> _reload() async {
    try {
      final load = await widget.store.loadReport();
      if (!mounted) return;
      setState(() {
        _items = load.checks;
        _loadFailed = false;
        if (load.damaged) _damage = load;
      });
    } catch (e) {
      debugPrint('[spool_check] load failed: $e');
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
    if ((_items?.length ?? 0) < SpoolCheckStore.maxEntries) return false;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        key: const ValueKey('sc-store-full'),
        content: Text(context.tr(
          pl: 'Historia pełna (${SpoolCheckStore.maxEntries} protokołów) — '
              'udostępnij i usuń stare protokoły, żeby dodać nowy.',
          en: 'History full (${SpoolCheckStore.maxEntries} records) — share '
              'and delete old records to add a new one.',
        )),
      ));
    return true;
  }

  void _showUnavailable() {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        key: const ValueKey('sc-store-unavailable'),
        content: Text(spoolStoreUnavailableText(context)),
      ));
  }

  Future<void> _open(SpoolCheck check) async {
    await Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => SpoolCheckEditPage(
        initial: check,
        store: widget.store,
        now: widget.now,
        shareText: widget.shareText,
        newId: widget.newId,
      ),
    ));
    await _reload();
  }

  Future<void> _new() async {
    if (_refuseWhenFull()) return;
    // Zapis uszkodzony bez kopii — formularz by się nie zapisał.
    if (_damage?.backupFailed ?? false) {
      _showUnavailable();
      return;
    }
    await _open(SpoolCheck.blank(id: _id(), now: widget.now()));
  }

  /// Następny spool z serii: nagłówek, tolerancje i wymiary z rysunku
  /// zostają, pomiary — nie.
  Future<void> _duplicate(SpoolCheck source) async {
    if (_refuseWhenFull()) return;
    final copy = source.duplicateFor(
        newId: _id(), now: widget.now(), itemId: (_) => _id());
    try {
      await widget.store.upsert(copy);
    } on SpoolCheckStoreUnavailable {
      // Zapis uszkodzony bez kopii — nic nie zapisano; nie otwieramy
      // formularza, który by się nie zapisał.
      _showUnavailable();
      return;
    } catch (e) {
      // Edycja i tak zapisuje się przy każdej zmianie — otwieramy kopię.
      debugPrint('[spool_check] duplicate save failed: $e');
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(context.tr(
          pl: 'Następny spool: wymiary z rysunku skopiowane, pomiary wpisz '
              'od nowa.',
          en: 'Next spool: drawing dimensions copied, enter the measurements '
              'again.',
        )),
      ));
    await _open(copy);
  }

  Future<void> _delete(SpoolCheck check) async {
    final en = context.language == AppLanguage.en;
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title:
            Text(context.tr(pl: 'Usunąć protokół?', en: 'Delete this record?')),
        content: Text(spoolCheckTitle(check, en: en)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx, false),
            child: Text(context.tr(pl: 'Anuluj', en: 'Cancel')),
          ),
          FilledButton(
            key: const ValueKey('sc-delete-confirm'),
            style: FilledButton.styleFrom(
                backgroundColor: kFail, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(dialogCtx, true),
            child: Text(context.tr(pl: 'Usuń', en: 'Delete')),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await widget.store.delete(check.id);
    } on SpoolCheckStoreUnavailable {
      _showUnavailable();
      return;
    }
    await _reload();
    if (!mounted) return;
    // Cofnięcie idzie przez magazyn — działa także po zamknięciu ekranu
    // i przy pełnej historii (to odwołanie usunięcia, nie nowy wpis).
    final store = widget.store;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        key: const ValueKey('sc-deleted'),
        content:
            Text(context.tr(pl: 'Protokół usunięty.', en: 'Record deleted.')),
        action: SnackBarAction(
          label: context.tr(pl: 'Cofnij', en: 'Undo'),
          onPressed: () async {
            try {
              await store.restore(check);
            } catch (e) {
              debugPrint('[spool_check] undo failed: $e');
              if (mounted) _showUnavailable();
              return;
            }
            if (mounted) await _reload();
          },
        ),
      ));
  }

  @override
  Widget build(BuildContext context) {
    final en = context.language == AppLanguage.en;
    final items = _items;
    return Scaffold(
      appBar: AppBar(
        title:
            Text(context.tr(pl: 'Tolerancje spoola', en: 'Spool tolerances')),
      ),
      body: ListView(
        key: const ValueKey('sc-list'),
        padding: EdgeInsets.fromLTRB(
            12, 12, 12, 24 + MediaQuery.viewPaddingOf(context).bottom),
        children: [
          if (items != null && items.length >= SpoolCheckStore.warnAt)
            QuoteNotice(
              key: const ValueKey('sc-store-warn'),
              color: items.length >= SpoolCheckStore.maxEntries ? kFail : kWarn,
              icon: Icons.inventory_2_outlined,
              text: context.tr(
                pl: 'Historia: ${items.length}/${SpoolCheckStore.maxEntries} '
                    'protokołów. Przy pełnej nowego protokołu nie da się '
                    'zapisać — udostępnij i usuń stare.',
                en: 'History: ${items.length}/${SpoolCheckStore.maxEntries} '
                    'records. When full, a new record cannot be saved — share '
                    'and delete old ones.',
              ),
            ),
          if (_damage?.backupFailed ?? false)
            QuoteNotice(
              key: const ValueKey('sc-store-unavailable-banner'),
              color: kFail,
              icon: Icons.sd_card_alert_outlined,
              text: spoolStoreUnavailableText(context),
            ),
          if (_damage != null)
            QuoteNotice(
              key: const ValueKey('sc-load-damaged'),
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
                          '${_damage!.droppedChecks} protokołów, uszkodzeń '
                          'w protokołach: ${_damage!.damagedEntries}. Kopia '
                          'surowego zapisu została w telefonie.',
                      en: 'Part of the saved data was unreadable: '
                          '${_damage!.droppedChecks} record(s) skipped, '
                          '${_damage!.damagedEntries} damaged entr(ies) in '
                          'records. A raw copy is kept on the phone.'),
            ),
          QuoteSection(
            title: context.tr(pl: 'Nowy spool', en: 'New spool'),
            subtitle: context.tr(
              pl: 'Przed wysyłką na budowę: długości F–F / C–F / C–C, '
                  'położenie odgałęzień i uchwytów, skręt otworów, '
                  'nachylenie czoła kołnierza, prostoliniowość — z werdyktem '
                  'wobec PFI ES-3, EN 13480-4 albo projektu.',
              en: 'Before shipping to site: F–F / C–F / C–C lengths, branch '
                  'and attachment locations, bolt-hole rotation, flange face '
                  'tilt, straightness — with a verdict against PFI ES-3, '
                  'EN 13480-4 or the design.',
            ),
            children: [
              FilledButton.icon(
                key: const ValueKey('sc-new'),
                style: FilledButton.styleFrom(
                    minimumSize: const Size(0, kMinTapTarget)),
                onPressed: _new,
                icon: const Icon(Icons.add),
                label: Text(context.tr(pl: 'Nowy protokół', en: 'New record')),
              ),
              if (items != null && items.isNotEmpty) ...[
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  key: const ValueKey('sc-dup-last'),
                  style: OutlinedButton.styleFrom(
                      minimumSize: const Size(0, kMinTapTarget)),
                  onPressed: () => _duplicate(items.first),
                  icon: const Icon(Icons.copy_all_outlined),
                  label: Text(
                    context.tr(
                      pl: 'Następny spool z serii: '
                          '${spoolCheckTitle(items.first, en: false)}',
                      en: 'Next spool in the series: '
                          '${spoolCheckTitle(items.first, en: true)}',
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
                  key: const ValueKey('sc-empty'),
                  style: const TextStyle(color: kTextSec, fontSize: 13.5),
                )
              else
                for (final (i, c) in items.indexed)
                  _HistoryTile(
                    key: ValueKey('sc-hist-$i'),
                    index: i,
                    check: c,
                    en: en,
                    onOpen: () => _open(c),
                    onAction: (a) => switch (a) {
                      _ItemAction.duplicate => _duplicate(c),
                      _ItemAction.delete => _delete(c),
                    },
                  ),
            ],
          ),
          QuoteNotice(
            icon: Icons.gavel_outlined,
            text: spoolCheckDisclaimer(en: en),
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
    required this.check,
    required this.en,
    required this.onOpen,
    required this.onAction,
  });

  final int index;
  final SpoolCheck check;
  final bool en;
  final VoidCallback onOpen;
  final Future<void> Function(_ItemAction a) onAction;

  @override
  Widget build(BuildContext context) {
    final r = check.evaluate();
    final o = r.overall;
    final color = spoolOverallColor(o);
    final sub = [
      check.date,
      if (check.isoNo.trim().isNotEmpty && check.spoolNo.trim().isNotEmpty)
        check.isoNo.trim(),
      if (check.dn != null) 'DN${check.dn}',
      check.toleranceSet?.label(en: en) ?? '—',
      '${r.items.length} ${en ? 'item(s)' : 'poz.'}',
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
          key: ValueKey('sc-open-$index'),
          onTap: onOpen,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 64),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 0, 8),
              child: Row(
                children: [
                  Icon(spoolOverallIcon(o), color: color, size: 26),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(spoolCheckTitle(check, en: en),
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
                        Text(spoolOverallShort(o, en: en),
                            key: ValueKey('sc-hist-status-$index'),
                            style: TextStyle(
                                color: color,
                                fontSize: 12.5,
                                fontWeight: FontWeight.w800)),
                      ],
                    ),
                  ),
                  PopupMenuButton<_ItemAction>(
                    key: ValueKey('sc-menu-$index'),
                    tooltip: en ? 'More' : 'Więcej',
                    icon: const Icon(Icons.more_vert, color: kTextSec),
                    onSelected: onAction,
                    itemBuilder: (_) => [
                      PopupMenuItem(
                        key: const ValueKey('sc-menu-dup'),
                        value: _ItemAction.duplicate,
                        child: Text(en
                            ? 'Next spool in the series (copy)'
                            : 'Następny spool z serii (kopia)'),
                      ),
                      PopupMenuItem(
                        key: const ValueKey('sc-menu-del'),
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
