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
  });

  final HotWorkStore store;
  final DateTime Function() now;

  /// Identyfikator nowego protokołu — wstrzykiwany w testach.
  final String Function()? newId;
  final HotWorkShareText shareText;
  final HotWorkSharePdf sharePdf;

  @override
  State<HotWorkPage> createState() => _HotWorkPageState();
}

enum _ItemAction { duplicate, delete }

class _HotWorkPageState extends State<HotWorkPage> {
  List<HotWorkPermit>? _items;
  bool _loadFailed = false;

  @override
  void initState() {
    super.initState();
    unawaited(_reload());
  }

  Future<void> _reload() async {
    try {
      final items = await widget.store.load();
      if (!mounted) return;
      setState(() {
        _items = items;
        _loadFailed = false;
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

  Future<void> _open(HotWorkPermit permit) async {
    await Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => HotWorkEditPage(
        initial: permit,
        store: widget.store,
        now: widget.now,
        shareText: widget.shareText,
        sharePdf: widget.sharePdf,
      ),
    ));
    await _reload();
  }

  Future<void> _new() =>
      _open(HotWorkPermit.blank(id: _id(), now: widget.now()));

  /// „Jak wczoraj”: dane organizacyjne zostają, zaznaczenia i pomiary — nie.
  Future<void> _duplicate(HotWorkPermit source) async {
    final copy = source.duplicateFor(newId: _id(), now: widget.now());
    try {
      await widget.store.upsert(copy);
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
    await widget.store.delete(permit.id);
    await _reload();
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(context.tr(pl: 'Protokół usunięty.', en: 'Record deleted.')),
        action: SnackBarAction(
          label: context.tr(pl: 'Cofnij', en: 'Undo'),
          onPressed: () async {
            await widget.store.upsert(permit);
            await _reload();
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
  });

  final int index;
  final HotWorkPermit permit;
  final String title;
  final bool en;
  final VoidCallback onOpen;
  final Future<void> Function(_ItemAction a) onAction;

  @override
  Widget build(BuildContext context) {
    final a = permit.assess();
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
                  Icon(
                    a.readiness == HotWorkReadiness.overLimit
                        ? Icons.dangerous_outlined
                        : a.readyToStart
                            ? Icons.verified_outlined
                            : Icons.pending_actions_outlined,
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
