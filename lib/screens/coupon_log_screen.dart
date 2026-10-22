import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../data/heat_tint.dart';
import '../database/coupon_dao.dart';
import '../domain/weld_journal/coupon_entry.dart';
import '../domain/weld_journal/weld_dates.dart';
import '../domain/weld_journal/weld_history.dart' show formatHistoryTime;
import '../i18n/app_language.dart';
import '../services/coupon_log_export.dart';
import '../services/welder_identity.dart';
import '../theme/app_theme.dart';
import '../utils/haptic.dart';
import '../widgets/weld_journal/coupon_editor_sheet.dart';
import '../widgets/local_record_scope.dart';

// The model and DAO moved to lib/domain/weld_journal/coupon_entry.dart and
// lib/database/coupon_dao.dart; kept importable from here.
export '../database/coupon_dao.dart' show CouponDao;
export '../domain/weld_journal/coupon_entry.dart';

/// A test coupon ("kupon próbny") is a sacrificial weld a welder makes — on
/// food & pharma work, usually at the start of every shift and on every
/// machine — and gets accepted before touching production. This screen is
/// that daily log, which an auditor will ask for: now editable, exportable
/// (CSV/PDF), and carrying the weld program, the O₂ reading and the heat
/// tint level (AWS D18.2). The weld journal links welds to these coupons.
///
/// v25: every change is logged (history per coupon), deleting is soft and
/// reversible ("Pokaż usunięte" → Przywróć), a new coupon starts "to be
/// assessed" instead of OK, and deleting a coupon that welds refer to says
/// which welds will show it as deleted.
/// v33: log należy do konta — po zmianie konta lista startuje od nowa.
class CouponLogScreen extends StatelessWidget {
  const CouponLogScreen({super.key});

  @override
  Widget build(BuildContext context) =>
      LocalRecordScope(builder: (_, __) => const _CouponLog());
}

class _CouponLog extends StatefulWidget {
  const _CouponLog();

  @override
  State<_CouponLog> createState() => _CouponLogScreenState();
}

class _CouponLogScreenState extends State<_CouponLog> {
  static const _uuid = Uuid();
  final _dao = CouponDao();
  List<CouponEntry> _items = [];
  bool _loading = true;
  bool _exporting = false;
  bool _showDeleted = false;

  String get _stamp => WelderIdentityService.instance.current?.stamp ?? '';

  String _tr(String pl, String en) => context.tr(pl: pl, en: en);

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() => _loading = true);
    try {
      await WelderIdentityService.instance.get();
      final all = await _dao.listAll(includeDeleted: _showDeleted);
      if (!mounted) return;
      setState(() {
        _items = all;
        _loading = false;
      });
    } catch (e) {
      debugPrint('CouponLog load error: $e');
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(_tr('Nie udało się wczytać logu kuponów.',
            'Failed to load the coupon log.')),
        action: SnackBarAction(label: _tr('Ponów', 'Retry'), onPressed: _load),
      ));
    }
  }

  Future<void> _add() async {
    final identity = await WelderIdentityService.instance.get();
    if (!mounted) return;
    final saved = await showCouponEditor(
      context,
      isNew: true,
      dao: _dao,
      initial: CouponEntry(
        id: _uuid.v4(),
        date: isoDate(DateTime.now()),
        welder: identity?.stamp ?? '',
        machine: '',
        size: '',
        // Do oceny — kupon przyjmuje się świadomie, nie domyślnie.
        result: CouponResult.pending,
        notes: '',
      ),
    );
    if (saved != null) {
      await Haptic.saved();
      await _load();
    }
  }

  Future<void> _edit(CouponEntry e) async {
    final saved =
        await showCouponEditor(context, isNew: false, dao: _dao, initial: e);
    if (saved != null) {
      await Haptic.saved();
      await _load();
    }
  }

  Future<void> _delete(CouponEntry e) async {
    var linked = const <(String, String)>[];
    try {
      linked = await _dao.linkedWelds(e.id);
    } catch (err) {
      debugPrint('CouponLog linked welds error: $err');
    }
    if (!mounted) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(ctx.tr(pl: 'Usunąć kupon?', en: 'Delete coupon?')),
        content: Text([
          ctx.tr(
            pl: 'Kupon zniknie z listy, ale zostanie w logu z historią — '
                'przywrócisz go przełącznikiem „Pokaż usunięte”.',
            en: 'The coupon leaves the list but stays in the log with its '
                'history — restore it with "Show deleted".',
          ),
          if (linked.isNotEmpty)
            ctx.tr(
              pl: 'Spoiny powiązane z kuponem (${linked.length}) pokażą go '
                  'jako usunięty: ${linked.map((w) => w.$2).join(', ')}.',
              en: 'Welds linked to it (${linked.length}) will show it as '
                  'deleted: ${linked.map((w) => w.$2).join(', ')}.',
            ),
        ].join('\n\n')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(ctx.tr(pl: 'Anuluj', en: 'Cancel')),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: kFail, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(ctx.tr(pl: 'Usuń', en: 'Delete')),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await _dao.softDelete(e.id, by: _stamp);
    } catch (err) {
      debugPrint('CouponLog delete error: $err');
      if (!mounted) return;
      // Fire-and-forget: awaiting the haptic opens an async gap and the
      // BuildContext below would no longer be provably mounted.
      Haptic.error();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(
            _tr('Nie udało się usunąć kuponu.', 'Failed to delete coupon.')),
      ));
      return;
    }
    if (!mounted) return;
    await Haptic.saved();
    await _load();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(_tr('Usunięto kupon.', 'Coupon deleted.')),
      action: SnackBarAction(
        label: _tr('Cofnij', 'Undo'),
        onPressed: () => _restore(e, quiet: true),
      ),
    ));
  }

  Future<void> _restore(CouponEntry e, {bool quiet = false}) async {
    try {
      await _dao.restore(e.id, by: _stamp);
    } catch (err) {
      debugPrint('CouponLog restore error: $err');
    }
    if (mounted) await _load();
    if (quiet || !mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(_tr('Przywrócono kupon.', 'Coupon restored.')),
    ));
  }

  Future<void> _history(CouponEntry e) async {
    List<CouponHistoryEntry> h;
    try {
      h = await _dao.history(e.id);
    } catch (err) {
      debugPrint('CouponLog history error: $err');
      h = const [];
    }
    if (!mounted) return;
    final en = AppLanguageController.isEnglish;
    String action(String a) => switch (a) {
          CouponHistoryAction.create => en ? 'Created' : 'Utworzono',
          CouponHistoryAction.update => en ? 'Edited' : 'Edycja',
          CouponHistoryAction.delete => en ? 'Deleted' : 'Usunięto',
          CouponHistoryAction.restore => en ? 'Restored' : 'Przywrócono',
          _ => a,
        };
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: kCard,
      builder: (ctx) => SafeArea(
        child: ConstrainedBox(
          constraints:
              BoxConstraints(maxHeight: MediaQuery.sizeOf(ctx).height * 0.7),
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.all(16),
            children: [
              Text(
                ctx.tr(pl: 'Historia kuponu', en: 'Coupon history'),
                style: const TextStyle(
                    color: kArc, fontSize: 15, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 8),
              if (h.isEmpty)
                Text(ctx.tr(pl: 'Brak wpisów.', en: 'No entries.'),
                    style: const TextStyle(color: kTextMut)),
              for (final x in h)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    [
                      '${formatHistoryTime(x.at)} · ${action(x.action)}'
                          '${x.byStamp.isEmpty ? '' : ' · ${x.byStamp}'}',
                      if (x.field.isNotEmpty)
                        '${couponFieldLabel(x.field, en: en)}: '
                            '${x.oldValue.isEmpty ? '—' : x.oldValue} → '
                            '${x.newValue.isEmpty ? '—' : x.newValue}'
                      else if ((x.newValue.isNotEmpty ? x.newValue : x.oldValue)
                          .isNotEmpty)
                        x.newValue.isNotEmpty ? x.newValue : x.oldValue,
                    ].join('\n'),
                    style: const TextStyle(fontSize: 13, color: kText),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  /// Eksport: tylko kupony nieusunięte (usunięte są w historii).
  List<CouponEntry> get _exportable =>
      _items.where((c) => !c.isDeleted).toList();

  Future<void> _export(Future<void> Function() job) async {
    if (_exportable.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(_tr('Brak kuponów do wyeksportowania.',
            'No coupons to export.')),
      ));
      return;
    }
    if (_exporting) return;
    setState(() => _exporting = true);
    try {
      await job();
    } catch (e) {
      debugPrint('CouponLog export error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(_tr('Nie udało się wyeksportować logu.',
              'Failed to export the log.')),
        ));
      }
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_tr('Log kuponów próbnych', 'Test coupon log')),
        actions: [
          IconButton(
            icon: const Icon(Icons.table_view_outlined),
            tooltip: _tr('Eksport CSV (Excel)', 'Export CSV (Excel)'),
            onPressed: _exporting
                ? null
                : () => _export(() => CouponLogExport.shareCsv(_exportable)),
          ),
          IconButton(
            icon: const Icon(Icons.picture_as_pdf_outlined),
            tooltip: _tr('Eksport PDF', 'Export PDF'),
            onPressed: _exporting
                ? null
                : () => _export(() => CouponLogExport.sharePdf(_exportable)),
          ),
          PopupMenuButton<String>(
            tooltip: _tr('Więcej', 'More'),
            onSelected: (_) {
              setState(() => _showDeleted = !_showDeleted);
              _load();
            },
            itemBuilder: (_) => [
              CheckedPopupMenuItem(
                value: 'deleted',
                checked: _showDeleted,
                child: Text(_tr('Pokaż usunięte', 'Show deleted')),
              ),
            ],
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: kArc))
          : _items.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.science_outlined,
                            size: 48, color: kTextMut),
                        const SizedBox(height: 12),
                        Text(
                          _tr(
                            'Brak kuponów. Dotknij „Kupon”, aby dodać pierwszy '
                                'kupon dnia.',
                            'No coupons yet. Tap "Coupon" to add the first '
                                'coupon of the day.',
                          ),
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: kTextMut, fontSize: 13),
                        ),
                      ],
                    ),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(14, 12, 14, 96),
                  itemCount: _items.length,
                  itemBuilder: (_, i) => _CouponTile(
                    entry: _items[i],
                    onTap: () => _edit(_items[i]),
                    onAction: (a) => switch (a) {
                      'history' => _history(_items[i]),
                      'restore' => _restore(_items[i]),
                      _ => _delete(_items[i]),
                    },
                  ),
                ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _add,
        icon: const Icon(Icons.add),
        label: Text(_tr('Kupon', 'Coupon')),
        backgroundColor: kArc,
        foregroundColor: kOnArc,
      ),
    );
  }
}

class _CouponTile extends StatelessWidget {
  final CouponEntry entry;
  final VoidCallback onTap;
  final ValueChanged<String> onAction;
  const _CouponTile(
      {required this.entry, required this.onTap, required this.onAction});

  @override
  Widget build(BuildContext context) {
    final c = entry.isDeleted
        ? kTextMut
        : entry.isOk
            ? kPass
            : entry.isRejected
                ? kFail
                : kArc;
    final resultLabel = entry.isPending
        ? context.tr(pl: 'do oceny', en: 'to assess')
        : entry.result;
    final tint =
        kHeatTintLevels.where((l) => l.level == entry.heatTint).firstOrNull;
    final details = [
      if (entry.programNo.isNotEmpty) 'P${entry.programNo}',
      if (entry.o2Ppm != null) 'O₂ ${formatO2Ppm(entry.o2Ppm)} ppm',
      if (tint != null)
        '${context.tr(pl: 'przebarw.', en: 'tint')} ${tint.level}',
    ].join('  ·  ');
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.fromLTRB(12, 10, 0, 10),
          decoration: BoxDecoration(
            color: kCard,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: kBorder),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                decoration: BoxDecoration(
                  color: c.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: c.withValues(alpha: 0.4)),
                ),
                child: Text(resultLabel,
                    style: TextStyle(
                        color: c, fontSize: 12, fontWeight: FontWeight.w800)),
              ),
              if (tint != null) ...[
                const SizedBox(width: 8),
                Container(
                  width: 18,
                  height: 18,
                  decoration: BoxDecoration(
                    color: tint.swatch,
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: kBorder),
                  ),
                ),
              ],
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      [
                        if (entry.welder.isNotEmpty) entry.welder,
                        if (entry.machine.isNotEmpty) entry.machine,
                        if (entry.size.isNotEmpty) entry.size,
                      ].join('  ·  '),
                      style: TextStyle(
                          color: kText,
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          decoration: entry.isDeleted
                              ? TextDecoration.lineThrough
                              : null),
                    ),
                    if (entry.isDeleted)
                      Text(context.tr(pl: 'usunięty', en: 'deleted'),
                          style:
                              const TextStyle(color: kFail, fontSize: 12)),
                    if (entry.acceptedBy.isNotEmpty)
                      Text(
                          '${context.tr(pl: 'przyjął', en: 'accepted by')} '
                          '${entry.acceptedBy}'
                          '${entry.acceptedAt.isEmpty ? '' : ' · ${entry.acceptedAt}'}',
                          style: const TextStyle(
                              color: kTextSec, fontSize: 12)),
                    if (entry.date.isNotEmpty)
                      Text(entry.date,
                          style:
                              const TextStyle(color: kTextMut, fontSize: 12)),
                    if (details.isNotEmpty)
                      Text(details,
                          style:
                              const TextStyle(color: kTextSec, fontSize: 12)),
                    if (entry.notes.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 3),
                        child: Text(entry.notes,
                            style:
                                const TextStyle(color: kTextSec, fontSize: 12),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis),
                      ),
                  ],
                ),
              ),
              PopupMenuButton<String>(
                tooltip: context.tr(pl: 'Akcje kuponu', en: 'Coupon actions'),
                icon: const Icon(Icons.more_vert, color: kTextSec),
                onSelected: onAction,
                itemBuilder: (_) => [
                  PopupMenuItem(
                      value: 'history',
                      child: Text(context.tr(
                          pl: 'Historia zmian', en: 'Change history'))),
                  if (entry.isDeleted)
                    PopupMenuItem(
                        value: 'restore',
                        child:
                            Text(context.tr(pl: 'Przywróć', en: 'Restore')))
                  else
                    PopupMenuItem(
                        value: 'delete',
                        child: Text(context.tr(pl: 'Usuń…', en: 'Delete…'),
                            style: const TextStyle(color: kFail))),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
