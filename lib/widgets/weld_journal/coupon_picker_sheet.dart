/// Picks a test coupon from the coupon log for a weld's coupon field.
///
/// The field in the journal was free text with no link to the log, so a
/// coupon reference could name a coupon that was never logged — or a NOK
/// one. Picking from the log links the weld (`coupon_id`) and writes the
/// coupon's reference; typing by hand still works for rows written before
/// the link existed.
///
/// v25: NOK coupons are greyed out and need an explicit "Spoina na kuponie
/// NOK?" confirmation; a coupon still "to be assessed" asks too. By default
/// only coupons of the weld's day are listed ("Wszystkie dni" shows the
/// rest). Deleted coupons are not offered.
library;

import 'package:flutter/material.dart';

import '../../database/coupon_dao.dart';
import '../../domain/weld_journal/coupon_entry.dart';
import '../../i18n/app_language.dart';
import '../../theme/app_theme.dart';

Future<CouponEntry?> showCouponPickerSheet(
  BuildContext context, {
  String? currentId,
  CouponDao? dao,
  String weldDate = '',
}) =>
    showModalBottomSheet<CouponEntry>(
      context: context,
      isScrollControlled: true,
      backgroundColor: kCard,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => SafeArea(
        child: ConstrainedBox(
          constraints:
              BoxConstraints(maxHeight: MediaQuery.sizeOf(ctx).height * 0.7),
          child: CouponPickerList(
            currentId: currentId,
            dao: dao ?? CouponDao(),
            weldDate: weldDate.trim(),
          ),
        ),
      ),
    );

class CouponPickerList extends StatefulWidget {
  final String? currentId;
  final CouponDao dao;
  final String weldDate;

  const CouponPickerList({
    super.key,
    this.currentId,
    required this.dao,
    this.weldDate = '',
  });

  @override
  State<CouponPickerList> createState() => _CouponPickerListState();
}

class _CouponPickerListState extends State<CouponPickerList> {
  late final Future<List<CouponEntry>> _future = widget.dao.listAll();
  late bool _onlyWeldDay = widget.weldDate.isNotEmpty;

  Future<void> _pick(CouponEntry c) async {
    if (c.isRejected || c.isPending) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(c.isRejected
              ? ctx.tr(pl: 'Spoina na kuponie NOK?', en: 'Weld on a NOK coupon?')
              : ctx.tr(
                  pl: 'Kupon jeszcze nieoceniony',
                  en: 'Coupon not assessed yet')),
          content: Text(c.isRejected
              ? ctx.tr(
                  pl: 'Kupon ${c.reference} został odrzucony. Podpięcie go do '
                      'spoiny oznacza spawanie produkcji na parametrach, które '
                      'nie przeszły próby. Podpiąć mimo to?',
                  en: 'Coupon ${c.reference} was rejected. Linking it means '
                      'production welded on parameters that failed the test. '
                      'Link anyway?')
              : ctx.tr(
                  pl: 'Kupon ${c.reference} nie ma jeszcze wyniku. Podpiąć?',
                  en: 'Coupon ${c.reference} has no result yet. Link it?')),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(ctx.tr(pl: 'Anuluj', en: 'Cancel')),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(ctx.tr(pl: 'Podepnij mimo to', en: 'Link anyway')),
            ),
          ],
        ),
      );
      if (ok != true || !mounted) return;
    }
    if (mounted) Navigator.pop(context, c);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            context.tr(pl: 'Kupon z logu kuponów', en: 'Coupon from the log'),
            style: const TextStyle(
                color: kArc, fontSize: 15, fontWeight: FontWeight.w800),
          ),
          if (widget.weldDate.isNotEmpty)
            SwitchListTile(
              key: const ValueKey('coupon-picker-weld-day'),
              contentPadding: EdgeInsets.zero,
              value: _onlyWeldDay,
              onChanged: (v) => setState(() => _onlyWeldDay = v),
              title: Text(
                context.tr(
                    pl: 'Tylko z dnia spoiny (${widget.weldDate})',
                    en: 'Only from the weld day (${widget.weldDate})'),
                style: const TextStyle(fontSize: 13),
              ),
            ),
          const SizedBox(height: 6),
          Flexible(
            child: FutureBuilder<List<CouponEntry>>(
              future: _future,
              builder: (_, snap) {
                if (snap.hasError) {
                  return Text(
                      context.tr(
                          pl: 'Nie udało się wczytać logu kuponów.',
                          en: 'Failed to load the coupon log.'),
                      style: const TextStyle(color: kFail));
                }
                if (!snap.hasData) {
                  return const Padding(
                    padding: EdgeInsets.all(24),
                    child: Center(child: CircularProgressIndicator(color: kArc)),
                  );
                }
                final all = snap.data!;
                final list = _onlyWeldDay
                    ? all.where((c) => c.date.trim() == widget.weldDate).toList()
                    : all;
                if (list.isEmpty) {
                  return Text(
                    all.isEmpty
                        ? context.tr(
                            pl: 'Log kuponów jest pusty. Dodaj kupon w '
                                '„Log kuponów próbnych” albo wpisz odnośnik '
                                'ręcznie.',
                            en: 'The coupon log is empty. Add a coupon in '
                                '"Test coupon log" or type the reference by '
                                'hand.',
                          )
                        : context.tr(
                            pl: 'Brak kuponów z dnia spoiny — wyłącz filtr, '
                                'żeby zobaczyć wszystkie.',
                            en: 'No coupons from the weld day — turn the '
                                'filter off to see all.'),
                    style: const TextStyle(color: kTextMut),
                  );
                }
                return ListView.separated(
                  shrinkWrap: true,
                  itemCount: list.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 6),
                  itemBuilder: (_, i) {
                    final c = list[i];
                    final selected = c.id == widget.currentId;
                    final color = c.isOk
                        ? kPass
                        : c.isRejected
                            ? kFail
                            : kArc;
                    final label = c.isPending
                        ? context.tr(pl: 'do oceny', en: 'to assess')
                        : c.result;
                    return Opacity(
                      // NOK wyszarzony — da się wybrać tylko z potwierdzeniem.
                      opacity: c.isRejected ? 0.55 : 1,
                      child: InkWell(
                        onTap: () => _pick(c),
                        borderRadius: BorderRadius.circular(10),
                        child: Container(
                          constraints:
                              const BoxConstraints(minHeight: kMinTapTarget),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 8),
                          decoration: BoxDecoration(
                            color:
                                selected ? kArc.withValues(alpha: 0.12) : kBg,
                            borderRadius: BorderRadius.circular(10),
                            border:
                                Border.all(color: selected ? kArc : kBorder),
                          ),
                          child: Row(
                            children: [
                              Text(label,
                                  style: TextStyle(
                                      fontWeight: FontWeight.w800,
                                      color: color)),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  [
                                    c.reference,
                                    if (c.welder.isNotEmpty) c.welder,
                                  ].join(' · '),
                                  style: const TextStyle(
                                      fontSize: 13, color: kText),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
          const SizedBox(height: 8),
          TextButton(
            style: TextButton.styleFrom(
                minimumSize: const Size(kMinTapTarget, kMinTapTarget)),
            onPressed: () => Navigator.pop(context),
            child: Text(context.tr(pl: 'Anuluj', en: 'Cancel')),
          ),
        ],
      ),
    );
  }
}
