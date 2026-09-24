/// Picks a test coupon from the coupon log for a weld's coupon field.
///
/// The field in the journal was free text with no link to the log, so a
/// coupon reference could name a coupon that was never logged — or a NOK
/// one. Picking from the log links the weld (`coupon_id`) and writes the
/// coupon's reference; typing by hand still works for rows written before
/// the link existed.
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
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  ctx.tr(
                      pl: 'Kupon z logu kuponów', en: 'Coupon from the log'),
                  style: const TextStyle(
                      color: kArc, fontSize: 15, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 10),
                Flexible(
                  child: FutureBuilder<List<CouponEntry>>(
                    future: (dao ?? CouponDao()).listAll(),
                    builder: (_, snap) {
                      if (snap.hasError) {
                        return Text(
                            ctx.tr(
                                pl: 'Nie udało się wczytać logu kuponów.',
                                en: 'Failed to load the coupon log.'),
                            style: const TextStyle(color: kFail));
                      }
                      if (!snap.hasData) {
                        return const Padding(
                          padding: EdgeInsets.all(24),
                          child: Center(
                              child: CircularProgressIndicator(color: kArc)),
                        );
                      }
                      final list = snap.data!;
                      if (list.isEmpty) {
                        return Text(
                          ctx.tr(
                            pl: 'Log kuponów jest pusty. Dodaj kupon w '
                                '„Log kuponów próbnych” albo wpisz odnośnik '
                                'ręcznie.',
                            en: 'The coupon log is empty. Add a coupon in '
                                '"Test coupon log" or type the reference by '
                                'hand.',
                          ),
                          style: const TextStyle(color: kTextMut),
                        );
                      }
                      return ListView.separated(
                        shrinkWrap: true,
                        itemCount: list.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 6),
                        itemBuilder: (_, i) {
                          final c = list[i];
                          final ok = c.result == 'OK';
                          final selected = c.id == currentId;
                          return InkWell(
                            onTap: () => Navigator.pop(ctx, c),
                            borderRadius: BorderRadius.circular(10),
                            child: Container(
                              constraints: const BoxConstraints(
                                  minHeight: kMinTapTarget),
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 8),
                              decoration: BoxDecoration(
                                color: selected
                                    ? kArc.withValues(alpha: 0.12)
                                    : kBg,
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                    color: selected ? kArc : kBorder),
                              ),
                              child: Row(
                                children: [
                                  Text(c.result,
                                      style: TextStyle(
                                          fontWeight: FontWeight.w800,
                                          color: ok ? kPass : kFail)),
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
                  onPressed: () => Navigator.pop(ctx),
                  child: Text(ctx.tr(pl: 'Anuluj', en: 'Cancel')),
                ),
              ],
            ),
          ),
        ),
      ),
    );
