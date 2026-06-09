import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config/backend_config.dart';
import 'api_client.dart';

// Premium subscription state for Fitter Welder Pro.
//
// Phase 4a (this file): local-only stub. The service caches a single bool
// in SharedPreferences and broadcasts changes via a Stream. There is no
// payment integration yet — `purchase()` flips the flag and returns true
// only when called from a dev override; production users see the "Coming
// soon" snackbar inside PremiumScreen.
//
// Phase 4b will wire this up to Stripe Checkout (reusing the Railway
// backend from PrzetargAI) + Firestore-side webhook flags. The widget API
// (`PremiumService.instance.isPremium`, `.statusStream`, etc.) is designed
// to stay stable across both phases so we don't have to touch consumers.
//
// Phase 5-7 (AI Chat, premium calculators, free job listing) will gate
// features via `PremiumGate` (see lib/widgets/premium_gate.dart).

enum PremiumPlan {
  /// Free user — no Premium features.
  free,

  /// 19 PLN / month — recurring.
  monthly,

  /// 149 PLN / year (35% saving) — recurring.
  yearly,

  /// Lifetime / promo unlock (e.g. plant license, contest winner).
  lifetime,
}

class PremiumStatus {
  final PremiumPlan plan;

  /// Subscription expiry. `null` for [PremiumPlan.lifetime] or
  /// [PremiumPlan.free].
  final DateTime? expiresAt;

  /// Whether the local cache was refreshed against the backend within the
  /// last hour. Used by the UI to decide if a "Refresh" button is needed.
  final DateTime? lastVerifiedAt;

  const PremiumStatus({
    required this.plan,
    this.expiresAt,
    this.lastVerifiedAt,
  });

  factory PremiumStatus.free() => const PremiumStatus(plan: PremiumPlan.free);

  bool get isActive {
    if (plan == PremiumPlan.free) return false;
    if (plan == PremiumPlan.lifetime) return true;
    final exp = expiresAt;
    if (exp == null) return false;
    return DateTime.now().isBefore(exp);
  }

  /// Human-readable label for the badge / paywall screen.
  String get label {
    switch (plan) {
      case PremiumPlan.free:
        return 'FREE';
      case PremiumPlan.monthly:
        return 'PRO · monthly';
      case PremiumPlan.yearly:
        return 'PRO · yearly';
      case PremiumPlan.lifetime:
        return 'PRO · lifetime';
    }
  }

  PremiumStatus copyWith({
    PremiumPlan? plan,
    DateTime? expiresAt,
    DateTime? lastVerifiedAt,
  }) {
    return PremiumStatus(
      plan: plan ?? this.plan,
      expiresAt: expiresAt ?? this.expiresAt,
      lastVerifiedAt: lastVerifiedAt ?? this.lastVerifiedAt,
    );
  }
}

class PremiumService {
  PremiumService._();
  static final PremiumService instance = PremiumService._();

  final _controller = StreamController<PremiumStatus>.broadcast();
  PremiumStatus _current = PremiumStatus.free();
  bool _initialised = false;
  String? _deviceId;

  static const _kDeviceIdKey = 'fitter_device_id';

  /// Call once at app startup from `main()`. Loads or generates the device
  /// id (stable identifier used as Stripe `client_reference_id`) and
  /// hydrates Premium status from the cached `SharedPreferences` entry.
  Future<void> init() async {
    if (_initialised) return;
    _initialised = true;
    final prefs = await SharedPreferences.getInstance();
    _deviceId = prefs.getString(_kDeviceIdKey);
    if (_deviceId == null || _deviceId!.length < 16) {
      _deviceId = _generateDeviceId();
      await prefs.setString(_kDeviceIdKey, _deviceId!);
    }
    _controller.add(_current);
  }

  /// Stable identifier for this install. Used as Stripe `client_reference_id`
  /// so the webhook can map the subscription back to the device. Survives
  /// app restarts (SharedPreferences), wiped on app uninstall.
  String get deviceId {
    return _deviceId ?? _generateDeviceId();
  }

  static String _generateDeviceId() {
    final r = math.Random.secure();
    final bytes = List<int>.generate(16, (_) => r.nextInt(256));
    return bytes
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join();
  }

  PremiumStatus get status => _current;

  bool get isPremium => _current.isActive;

  /// Broadcasts whenever [status] changes (login, purchase, expiry refresh).
  /// UI widgets should listen here instead of polling.
  Stream<PremiumStatus> get statusStream => _controller.stream;

  /// Rolling log of every status that has been applied via [applyStatus].
  /// Capped at [_kHistoryCap] so we don't grow unbounded over a long session.
  /// Most recent entry is at the END of the list (the live `_current` is NOT
  /// in `_history` — `_history.last` is the status that was active immediately
  /// before the current one). Used by [undoLastStatusChange] to revert an
  /// optimistic mutation (e.g. a webhook race that briefly drops PRO) and by
  /// [previousStatus] for UI banners ("Reaktywuj poprzedni plan").
  static const int _kHistoryCap = 8;
  final List<PremiumStatus> _history = <PremiumStatus>[];

  /// Snapshot of the status that was live the LAST time a debug helper
  /// (`debugUnlockPro` / `debugClear`) was invoked, so QA can restore the
  /// real status after poking around. Set ONLY by the debug helpers; cleared
  /// by [debugRestorePreDebugStatus]. Has no effect on production code paths.
  PremiumStatus? _preDebugStatus;

  /// Identifier of the most recent checkout session we asked the backend
  /// to create. Set by [createCheckoutSession] on success, cleared by
  /// [cancelCheckoutSession] and by any subsequent successful status apply
  /// (because if we got a new status, the pending checkout is either
  /// resolved or stale). Pure book-keeping — does NOT participate in the
  /// P0-04 / P0r-10 downgrade-grace state machine.
  String? _pendingCheckoutSessionId;
  String? get pendingCheckoutSessionId => _pendingCheckoutSessionId;

  /// Overwrite the in-memory status. Used by:
  ///   - Phase 4a dev override (debug-only paywall bypass during testing)
  ///   - Phase 4b Stripe webhook → Firestore listener → call here
  ///   - Phase 4b restore-purchases (Apple IAP / Google Billing)
  Future<void> applyStatus(PremiumStatus next) async {
    // Record the OUTGOING status in history before we overwrite it, so
    // `undoLastStatusChange()` can roll back exactly one step. Cap at
    // `_kHistoryCap` entries — drop the oldest when full.
    _history.add(_current);
    if (_history.length > _kHistoryCap) {
      _history.removeRange(0, _history.length - _kHistoryCap);
    }
    _current = next;
    _controller.add(next);
  }

  /// Status that was live immediately before the most recent
  /// [applyStatus] call. `null` when no status has ever been applied (i.e.
  /// we're still on the initial `PremiumStatus.free()`). Useful for UI
  /// banners like "Reaktywuj poprzedni plan" / "Reactivate previous plan".
  PremiumStatus? get previousStatus =>
      _history.isEmpty ? null : _history.last;

  /// Reverts to the status that was live before the most recent
  /// [applyStatus] call. Returns `true` when something was rolled back,
  /// `false` when the history is empty. Mounted-safe at the call site —
  /// this method itself never awaits, so the caller's `mounted` guard
  /// (if any) is enough.
  ///
  /// Intentionally bypasses [applyStatus] (would otherwise push the
  /// current status back onto `_history`, defeating the undo).
  bool undoLastStatusChange() {
    if (_history.isEmpty) {
      debugPrint('PremiumService.undoLastStatusChange: history empty, noop');
      return false;
    }
    final prev = _history.removeLast();
    _current = prev;
    _controller.add(prev);
    return true;
  }

  /// Debug-only: grants Premium locally so we can test gated features
  /// without a payment backend. **Strip from production builds.**
  Future<void> debugUnlockPro() async {
    _preDebugStatus ??= _current;
    await applyStatus(PremiumStatus(
      plan: PremiumPlan.lifetime,
      lastVerifiedAt: DateTime.now(),
    ));
  }

  Future<void> debugClear() async {
    _preDebugStatus ??= _current;
    await applyStatus(PremiumStatus.free());
  }

  /// QA helper: restore whatever status was live the first time a debug
  /// helper was invoked during this session. Returns `true` when a
  /// pre-debug snapshot existed and was restored, `false` when there's
  /// nothing to restore. Not safe for production — debug pair only.
  Future<bool> debugRestorePreDebugStatus() async {
    final snap = _preDebugStatus;
    if (snap == null) {
      debugPrint(
        'PremiumService.debugRestorePreDebugStatus: no pre-debug snapshot',
      );
      return false;
    }
    _preDebugStatus = null;
    await applyStatus(snap);
    return true;
  }

  // ── Stripe checkout (Phase 4b) ────────────────────────────────────────────
  /// Requests a Stripe Checkout session URL from the Railway backend.
  ///
  /// When [BackendConfig.stripeBackendLive] is `false`, this returns `null`
  /// so the caller can show a "Coming soon" message. Once the backend is
  /// deployed and the flag flipped, this hits `/api/fitter/billing/checkout`
  /// with the plan id; the server returns a URL that the client launches in
  /// an in-app browser or system browser. The webhook on the server flips
  /// the user's plan in Firestore, and a Firestore listener (added in 4b)
  /// calls `applyStatus()` here to update the UI.
  Future<String?> createCheckoutSession({
    required PremiumPlan plan,
    required String deviceId,
    String? customerEmail,
  }) async {
    if (!BackendConfig.stripeBackendLive) return null;
    final planStr = switch (plan) {
      PremiumPlan.monthly => 'monthly',
      PremiumPlan.yearly => 'yearly',
      _ => throw ArgumentError('Cannot checkout for plan $plan'),
    };
    final body = await ApiClient.instance.postJson(
      BackendConfig.stripeCheckout,
      body: {
        'plan': planStr,
        'device_id': deviceId,
        if (customerEmail != null) 'customer_email': customerEmail,
      },
    );
    // Track the session id so [cancelCheckoutSession] can clear it if the
    // user backs out of the Stripe hosted page before completing payment.
    // Falls back to the URL when the backend does not echo a session id
    // (older route shape) — either is enough for "is there a pending
    // checkout" book-keeping.
    final sessionId = body['session_id'] as String? ??
        body['checkout_session_id'] as String? ??
        body['checkout_url'] as String?;
    if (sessionId != null) {
      _pendingCheckoutSessionId = sessionId;
    }
    return body['checkout_url'] as String?;
  }

  /// Discards the locally-tracked pending checkout session — call this
  /// when the user dismisses the in-app browser / Stripe page without
  /// completing payment so subsequent UI doesn't keep showing a
  /// "Czekamy na potwierdzenie płatności…" banner.
  ///
  /// Does NOT touch the P0-04 / P0r-10 downgrade-grace state machine —
  /// `clearPendingDowngrade()` is the dedicated lever for that.
  void cancelCheckoutSession() {
    _pendingCheckoutSessionId = null;
  }

  /// Stripe Customer Portal URL for managing an existing subscription.
  /// Same gate as [createCheckoutSession] — returns null when the backend
  /// flag is off.
  Future<String?> createPortalSession({String? userId}) async {
    if (!BackendConfig.stripeBackendLive) return null;
    try {
      final body = await ApiClient.instance.postJson(
        BackendConfig.stripePortal,
        body: {if (userId != null) 'user_id': userId},
      );
      return body['portal_url'] as String?;
    } catch (_) {
      return null;
    }
  }

  /// Asks the backend to reactivate the user's most recently cancelled
  /// subscription (Stripe `subscriptions.resume` under the hood). The
  /// route is intentionally separate from [createCheckoutSession] so we
  /// avoid issuing a brand-new Stripe Checkout (and a brand-new charge)
  /// when the user just wants to undo a "cancel at period end" click.
  ///
  /// Returns `true` when the backend confirms the reactivation, `false`
  /// when the flag is off / the route is missing / the call fails — the
  /// caller should fall back to the standard upgrade flow in that case.
  /// Never throws; "noop fallback" is the deliberate failure mode so UI
  /// doesn't have to wrap every call in try/catch.
  Future<bool> reactivateSubscription({String? userId}) async {
    if (!BackendConfig.stripeBackendLive) return false;
    try {
      await init();
      final body = await ApiClient.instance.postJson(
        '/api/fitter/billing/reactivate',
        body: {
          'device_id': deviceId,
          if (userId != null) 'user_id': userId,
        },
      );
      return body['reactivated'] == true || body['is_active'] == true;
    } catch (e) {
      debugPrint('PremiumService.reactivateSubscription noop fallback: $e');
      return false;
    }
  }

  /// Asks the backend whether this device currently has an active Premium
  /// subscription. Called at app startup, after returning from Stripe
  /// Checkout, and periodically while the Premium screen is open. Updates
  /// the in-memory status (broadcast via [statusStream]) when the backend
  /// reports a change.
  /// Sticky 2-minute window after the first time the backend reports
  /// is_active=false on a currently-active subscription. We require a
  /// SECOND confirming "free" read inside this window before propagating
  /// the downgrade — guards against a Stripe webhook race or a single
  /// flaky backend response stripping PRO from a paying customer mid-job.
  ///
  /// P0r-10 hardening: also require N consecutive "free" reads (defaults
  /// to 3) so a permanently-misconfigured backend — wrong Stripe key on a
  /// sideloaded APK, missing INTERNET permission masquerading as 401, etc.
  /// — cannot strip PRO after just one grace window. Public
  /// `clearPendingDowngrade()` lets the billing flow reset the state
  /// machine after a successful purchase or restore.
  static const Duration _kDowngradeGrace = Duration(minutes: 2);
  static const int _minConfirmingReads = 3;
  DateTime? _pendingDowngradeAt;
  int _consecutiveFreeReads = 0;

  /// Called by the billing flow after a successful checkout / restore so a
  /// pending downgrade from a prior backend race doesn't fire after the
  /// user has already paid again.
  void clearPendingDowngrade() {
    _pendingDowngradeAt = null;
    _consecutiveFreeReads = 0;
  }

  Future<PremiumStatus> refreshFromBackend() async {
    if (!BackendConfig.stripeBackendLive) return _current;
    await init();
    final id = deviceId;
    try {
      final body = await ApiClient.instance.getJson(
        BackendConfig.premiumStatus,
        query: {'device_id': id},
        timeout: const Duration(seconds: 8),
      );
      final isActive = body['is_active'] == true;
      final planStr = body['plan'] as String?;
      final periodEnd = body['current_period_end'] as String?;
      final fresh = isActive
          ? PremiumStatus(
              plan: planStr == 'yearly' ? PremiumPlan.yearly : PremiumPlan.monthly,
              expiresAt: periodEnd != null ? DateTime.tryParse(periodEnd) : null,
              lastVerifiedAt: DateTime.now(),
            )
          : PremiumStatus.free().copyWith(lastVerifiedAt: DateTime.now());

      // Downgrade-grace logic: if the user IS active right now and the
      // backend just said "free", start a 2-minute timer and keep them
      // active. A subsequent "free" response after the timer elapses
      // commits the downgrade; an "active" response in the meantime
      // clears the timer.
      final wasActive = _current.isActive;
      final goingFree = wasActive && !fresh.isActive;
      if (goingFree) {
        _consecutiveFreeReads++;
        final pending = _pendingDowngradeAt;
        if (pending == null) {
          // First "free" read — record the moment, keep PRO live.
          _pendingDowngradeAt = DateTime.now();
          _current = _current.copyWith(lastVerifiedAt: DateTime.now());
          _controller.add(_current);
          return _current;
        }
        if (DateTime.now().difference(pending) < _kDowngradeGrace) {
          // Still inside the grace window — keep PRO live.
          _current = _current.copyWith(lastVerifiedAt: DateTime.now());
          _controller.add(_current);
          return _current;
        }
        if (_consecutiveFreeReads < _minConfirmingReads) {
          // Grace exhausted but we want N consecutive confirming reads
          // before treating this as a real downgrade — protects paying
          // users on misconfigured backends from being silently stripped.
          _current = _current.copyWith(lastVerifiedAt: DateTime.now());
          _controller.add(_current);
          return _current;
        }
        // N consecutive frees beyond grace — propagate the downgrade.
        _pendingDowngradeAt = null;
        _consecutiveFreeReads = 0;
      } else {
        // Either still active or already free — clear the state machine.
        _pendingDowngradeAt = null;
        _consecutiveFreeReads = 0;
      }

      if (fresh.plan != _current.plan ||
          fresh.expiresAt != _current.expiresAt) {
        await applyStatus(fresh);
      } else {
        _current = fresh;
        _controller.add(fresh);
      }
      return fresh;
    } catch (_) {
      // Network glitch — keep showing whatever we already have cached.
      // Pending-downgrade timer is NOT cleared so a flaky network during
      // the grace window doesn't reset the countdown.
      return _current;
    }
  }
}
