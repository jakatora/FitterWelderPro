import 'package:flutter/material.dart';

import '../i18n/app_language.dart';
import '../screens/premium_screen.dart';
import '../services/premium_service.dart';

// PremiumGate — wraps any Premium-only widget. In Phase 4a (this build) it
// always renders the child unchanged, so all PRO features remain free during
// beta. In Phase 4b (Stripe live), `gateActive` flips to true and Premium
// content gets a blurred overlay + paywall CTA.
//
// Usage:
//   PremiumGate(
//     featureName: 'AI Chat',
//     child: AiChatScreen(),
//   )
//
// The feature still renders for now — we're only setting the wiring so that
// once Stripe goes live we flip a single constant rather than walking every
// PRO screen.

/// Global kill-switch. Phase 4b PR will set this to `true` once Stripe is
/// live. Until then we want PRO features free so beta users can test.
const bool kPremiumGateEnforced = false;

class PremiumGate extends StatelessWidget {
  /// Human-friendly name of the feature behind the gate (e.g. 'AI Chat').
  /// Shown on the paywall overlay so the user knows what they unlock.
  final String featureName;

  /// The actual Premium widget — shown unobstructed when the gate is open.
  final Widget child;

  /// Optional preview to show through the blur when the gate is closed.
  /// Defaults to a partially-revealed render of [child].
  final Widget? lockedPreview;

  /// Forces the paywall regardless of [kPremiumGateEnforced]. Used for
  /// features that hit metered external services (Claude Vision in the
  /// ISO Scanner) — those must stay gated even while the rest of PRO is
  /// free during beta, because each call has real $$ cost.
  final bool alwaysEnforced;

  const PremiumGate({
    super.key,
    required this.featureName,
    required this.child,
    this.lockedPreview,
    this.alwaysEnforced = false,
  });

  @override
  Widget build(BuildContext context) {
    if (!kPremiumGateEnforced && !alwaysEnforced) return child;

    return StreamBuilder<PremiumStatus>(
      stream: PremiumService.instance.statusStream,
      initialData: PremiumService.instance.status,
      builder: (context, snap) {
        final hasPro = snap.data?.isActive ?? false;
        if (hasPro) return child;
        return _LockedOverlay(featureName: featureName, preview: lockedPreview ?? child);
      },
    );
  }
}

/// Less-disruptive variant: a small "PRO" badge that taps through to the
/// paywall instead of blocking the screen. Useful for menu tiles where we
/// want the user to see the entrypoint but bounce on tap.
class PremiumLockTile extends StatelessWidget {
  final Widget child;
  final String featureName;
  const PremiumLockTile({
    super.key,
    required this.child,
    required this.featureName,
  });

  @override
  Widget build(BuildContext context) {
    if (!kPremiumGateEnforced) return child;
    return Stack(
      children: [
        child,
        Positioned(
          top: 6,
          right: 6,
          child: GestureDetector(
            onTap: () => _openPaywall(context, featureName),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: const Color(0xFFE8C14B).withValues(alpha: 0.85),
                borderRadius: BorderRadius.circular(6),
              ),
              child: const Text(
                'PRO',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w900,
                  color: Colors.black,
                  letterSpacing: 0.5,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

void _openPaywall(BuildContext context, String featureName) {
  Navigator.push(
    context,
    MaterialPageRoute(builder: (_) => const PremiumScreen()),
  );
}

// ═══════════════════════════════════════════════════════════════════════════
// Locked overlay — Phase 4b will polish; Phase 4a stub is functional.
// ═══════════════════════════════════════════════════════════════════════════
class _LockedOverlay extends StatelessWidget {
  final String featureName;
  final Widget preview;
  const _LockedOverlay({required this.featureName, required this.preview});

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        // Faint, slightly-tinted preview of the feature behind the gate.
        Opacity(opacity: 0.35, child: IgnorePointer(child: preview)),
        Container(color: Colors.black.withValues(alpha: 0.55)),
        Center(
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.workspace_premium,
                    size: 64, color: Color(0xFFE8C14B)),
                const SizedBox(height: 14),
                Text(
                  featureName,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFFE8ECF0),
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 6),
                Text(
                  context.tr(
                    pl: 'Funkcja dostępna w planie Premium (19 PLN/mc lub 149 PLN/rok).',
                    en: 'Available on Premium (19 PLN/month or 149 PLN/year).',
                  ),
                  style: const TextStyle(
                      fontSize: 13, color: Color(0xFF9BA3C7), height: 1.5),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 18),
                FilledButton.icon(
                  onPressed: () => _openPaywall(context, featureName),
                  icon: const Icon(Icons.lock_open_outlined),
                  label: Text(context.tr(pl: 'Aktywuj Premium', en: 'Unlock Premium')),
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFFE8C14B),
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 20, vertical: 12),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
