import 'dart:async';
import 'dart:math' as math;

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

  /// Overwrite the in-memory status. Used by:
  ///   - Phase 4a dev override (debug-only paywall bypass during testing)
  ///   - Phase 4b Stripe webhook → Firestore listener → call here
  ///   - Phase 4b restore-purchases (Apple IAP / Google Billing)
  Future<void> applyStatus(PremiumStatus next) async {
    _current = next;
    _controller.add(next);
  }

  /// Debug-only: grants Premium locally so we can test gated features
  /// without a payment backend. **Strip from production builds.**
  Future<void> debugUnlockPro() async {
    await applyStatus(PremiumStatus(
      plan: PremiumPlan.lifetime,
      lastVerifiedAt: DateTime.now(),
    ));
  }

  Future<void> debugClear() async {
    await applyStatus(PremiumStatus.free());
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
    return body['checkout_url'] as String?;
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

  /// Asks the backend whether this device currently has an active Premium
  /// subscription. Called at app startup, after returning from Stripe
  /// Checkout, and periodically while the Premium screen is open. Updates
  /// the in-memory status (broadcast via [statusStream]) when the backend
  /// reports a change.
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
      final next = isActive
          ? PremiumStatus(
              plan: planStr == 'yearly' ? PremiumPlan.yearly : PremiumPlan.monthly,
              expiresAt: periodEnd != null ? DateTime.tryParse(periodEnd) : null,
              lastVerifiedAt: DateTime.now(),
            )
          : PremiumStatus.free().copyWith(lastVerifiedAt: DateTime.now());
      if (next.plan != _current.plan || next.expiresAt != _current.expiresAt) {
        await applyStatus(next);
      } else {
        _current = next;
        _controller.add(next);
      }
      return next;
    } catch (_) {
      // Network glitch — keep showing whatever we already have cached.
      return _current;
    }
  }
}
