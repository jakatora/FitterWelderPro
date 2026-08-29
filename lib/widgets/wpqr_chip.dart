// WPQR expiry warning — the readout that was missing.
//
// WHY THIS EXISTS: `WelderIdentity.wpqrExpiringSoon` and `.wpqrExpired`
// (lib/services/welder_identity.dart:102 / :110) were written at P0-08,
// unit-tested in test/services/welder_identity_test.dart, and then read by
// NOBODY — a grep over lib/ returned zero call sites. The welder therefore
// found out about a lapsed qualification from the inspector, not from the
// app, and every joint stamped in the meantime is an invalid weld under
// EN ISO 9606 / ASME IX QW-322: the welds get cut out and the welder gets
// pulled off the job.
//
// The chip is deliberately dumb: its state comes from the model getters,
// never from arithmetic repeated here, so the warning on screen can never
// disagree with the thresholds the tests pin.

import 'dart:async';

import 'package:flutter/material.dart';

import '../i18n/app_language.dart';
import '../services/welder_identity.dart';
import '../theme/app_theme.dart';

/// Severity of the qualification warning to show for a welder identity.
enum WpqrWarning {
  /// No expiry recorded, or the certificate is still comfortably valid.
  none,

  /// 30 days or fewer to go — time to book the re-qualification.
  expiringSoon,

  /// Past the expiry date; joints stamped now are not covered by it.
  expired,
}

/// Maps [identity] onto the warning the UI must show.
///
/// Reads the model getters instead of re-deriving the 30-day threshold, so
/// this can never drift from `test/services/welder_identity_test.dart`.
///
/// [WpqrWarning.expired] is checked FIRST on purpose. On the expiry day both
/// getters return true: `wpqrExpiringSoon` computes `difference(now).inDays`,
/// and `Duration` truncates toward zero, so a certificate that lapsed five
/// hours ago still reports `0` days left and passes the `daysLeft >= 0`
/// guard. Amber "expires today" on an already-dead WPQR is exactly the
/// message that lets someone strike an arc they must not strike.
WpqrWarning wpqrWarningOf(WelderIdentity? identity) {
  if (identity == null) return WpqrWarning.none;
  if (identity.wpqrExpired) return WpqrWarning.expired;
  if (identity.wpqrExpiringSoon) return WpqrWarning.expiringSoon;
  return WpqrWarning.none;
}

/// Whole days left until the WPQR expires, floored — the same arithmetic
/// `wpqrExpiringSoon` uses for its threshold, so the number shown to the
/// welder agrees with the rule that made the chip appear. Returns 0 when no
/// expiry is recorded; callers only reach it for a non-[WpqrWarning.none]
/// identity, which always has a date.
int wpqrDaysLeft(WelderIdentity identity, {DateTime? now}) {
  final expiry = identity.wpqrExpiry;
  if (expiry == null) return 0;
  return expiry.difference(now ?? DateTime.now()).inDays;
}

/// `2026-09-10`. ISO-ordered on purpose: the same format the identity setup
/// screen prints, and unambiguous for a crew mixing PL and EN conventions.
String _fmtDate(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, "0")}-'
    '${d.day.toString().padLeft(2, "0")}';

/// Amber/red banner warning that the welder's WPQR is about to lapse or has
/// already lapsed. Renders nothing at all when there is no expiry date or the
/// certificate is still valid, so it can be dropped into any layout
/// unconditionally.
///
/// Pure by design — it takes the identity as a parameter so it is testable
/// without SharedPreferences. Use [WpqrChipLive] when the caller has no
/// identity at hand.
class WpqrChip extends StatelessWidget {
  /// Identity to warn about; `null` renders nothing.
  final WelderIdentity? identity;

  /// Outer padding applied ONLY when the chip actually draws something.
  /// Without this a caller adding a fixed gap around the chip would leave a
  /// hole in the layout on the (common) happy path.
  final EdgeInsetsGeometry padding;

  const WpqrChip({
    super.key,
    required this.identity,
    this.padding = EdgeInsets.zero,
  });

  @override
  Widget build(BuildContext context) {
    final warning = wpqrWarningOf(identity);
    if (warning == WpqrWarning.none) return const SizedBox.shrink();

    final id = identity!;
    final expiry = id.wpqrExpiry;
    // Unreachable: both getters return false without a date. Kept so a future
    // change to the model degrades to "no chip" instead of a null crash on
    // the profile screen.
    if (expiry == null) return const SizedBox.shrink();

    final expired = warning == WpqrWarning.expired;
    final accent = expired ? kFail : kWarn;
    final label = expired
        ? context.tr(
            pl: 'WPQR wygasł ${_fmtDate(expiry)} — spoiny wykonane teraz mogą '
                'zostać unieważnione. Odnów uprawnienie przed kolejną zmianą.',
            en: 'WPQR expired ${_fmtDate(expiry)} — welds made now may be '
                'rejected. Renew the qualification before your next shift.',
          )
        : _expiringLabel(context, id, expiry);

    return Padding(
      padding: padding,
      child: Semantics(
        liveRegion: true,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: accent.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: accent.withValues(alpha: 0.35)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                expired ? Icons.gpp_bad_outlined : Icons.warning_amber_rounded,
                size: 18,
                color: accent,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    color: accent,
                    fontSize: 12.5,
                    height: 1.35,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _expiringLabel(
    BuildContext context,
    WelderIdentity id,
    DateTime expiry,
  ) {
    final days = wpqrDaysLeft(id);
    if (days <= 0) {
      return context.tr(
        pl: 'WPQR wygasa dziś (${_fmtDate(expiry)}). Umów przedłużenie.',
        en: 'WPQR expires today (${_fmtDate(expiry)}). Book the renewal.',
      );
    }
    // Polish takes "dzień" only for 1; "dni" covers 2, 5 and 22 alike.
    final plUnit = days == 1 ? 'dzień' : 'dni';
    final enUnit = days == 1 ? 'day' : 'days';
    return context.tr(
      pl: 'WPQR wygasa za $days $plUnit (${_fmtDate(expiry)}). '
          'Umów przedłużenie.',
      en: 'WPQR expires in $days $enUnit (${_fmtDate(expiry)}). '
          'Book the renewal.',
    );
  }
}

/// [WpqrChip] wired to [WelderIdentityService] — for callers that have no
/// identity loaded (stateless menus, headers).
///
/// Listens to the service's `changes` stream, so saving a new expiry date or
/// wiping the identity via "Delete my data" updates the warning without a
/// route rebuild. Without the stream the profile screen would keep warning
/// about a stamp the user had just erased.
class WpqrChipLive extends StatefulWidget {
  /// Forwarded to [WpqrChip.padding] — applied only when the chip draws.
  final EdgeInsetsGeometry padding;

  const WpqrChipLive({super.key, this.padding = EdgeInsets.zero});

  @override
  State<WpqrChipLive> createState() => _WpqrChipLiveState();
}

class _WpqrChipLiveState extends State<WpqrChipLive> {
  // Sync cache first so a warm rebuild paints the warning on frame one.
  WelderIdentity? _identity = WelderIdentityService.instance.current;
  StreamSubscription<WelderIdentity?>? _sub;

  @override
  void initState() {
    super.initState();
    // `current` is null until the store has hydrated once, so on a cold start
    // pull it explicitly rather than trusting the sync cache and silently
    // showing no warning at all.
    unawaited(WelderIdentityService.instance.get().then((id) {
      if (!mounted) return;
      setState(() => _identity = id);
    }));
    _sub = WelderIdentityService.instance.changes.listen((id) {
      if (!mounted) return;
      setState(() => _identity = id);
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      WpqrChip(identity: _identity, padding: widget.padding);
}
