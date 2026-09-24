import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../data/heat_tint.dart';
import '../database/coupon_dao.dart';
import '../domain/weld_journal/coupon_entry.dart';
import '../domain/weld_journal/weld_dates.dart';
import '../i18n/app_language.dart';
import '../services/coupon_log_export.dart';
import '../services/welder_identity.dart';
import '../theme/app_theme.dart';
import '../utils/haptic.dart';
import '../widgets/weld_journal/coupon_editor_sheet.dart';

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
class CouponLogScreen extends StatefulWidget {
  const CouponLogScreen({super.key});

  @override
  State<CouponLogScreen> createState() => _CouponLogScreenState();
}

class _CouponLogScreenState extends State<CouponLogScreen> {
  static const _uuid = Uuid();
  final _dao = CouponDao();
  List<CouponEntry> _items = [];
  bool _loading = true;
  bool _exporting = false;

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
      final all = await _dao.listAll();
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
        result: 'OK',
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
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(ctx.tr(pl: 'Usunąć kupon?', en: 'Delete coupon?')),
        content: Text(ctx.tr(
          pl: 'Kupon próbny zostanie usunięty z dziennika audytowego. '
              'Spoiny powiązane z nim zachowają jego opis.',
          en: 'This test coupon will be removed from the audit log. Welds '
              'linked to it keep its reference text.',
        )),
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
      await _dao.delete(e.id);
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
        onPressed: () async {
          try {
            await _dao.insert(e);
          } catch (err) {
            debugPrint('CouponLog undo error: $err');
          }
          if (mounted) await _load();
        },
      ),
    ));
  }

  Future<void> _export(Future<void> Function() job) async {
    if (_items.isEmpty) {
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
                : () => _export(() => CouponLogExport.shareCsv(_items)),
          ),
          IconButton(
            icon: const Icon(Icons.picture_as_pdf_outlined),
            tooltip: _tr('Eksport PDF', 'Export PDF'),
            onPressed: _exporting
                ? null
                : () => _export(() => CouponLogExport.sharePdf(_items)),
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
                    onDelete: () => _delete(_items[i]),
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
  final VoidCallback onDelete;
  const _CouponTile(
      {required this.entry, required this.onTap, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    final ok = entry.result == 'OK';
    final c = ok ? kPass : kFail;
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
                child: Text(entry.result,
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
                      style: const TextStyle(
                          color: kText,
                          fontSize: 13,
                          fontWeight: FontWeight.w700),
                    ),
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
              IconButton(
                icon: const Icon(Icons.delete_outline, color: kTextMut),
                tooltip: context.tr(pl: 'Usuń kupon', en: 'Delete coupon'),
                onPressed: onDelete,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
