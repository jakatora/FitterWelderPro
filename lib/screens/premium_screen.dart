// ignore_for_file: prefer_const_constructors

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config/backend_config.dart';
import '../i18n/app_language.dart';
import '../services/premium_service.dart';
import 'ai_chat_screen.dart';

// Persisted across cold starts so that if the user kills the app after being
// bounced to Stripe Checkout (slow network, accidental swipe), the next launch
// of this screen still runs the post-checkout verification poll instead of
// silently dropping it on the floor.
const String _kPendingCheckoutKey = 'fitter_premium_pending_checkout';
const String _kPendingCheckoutSetAtKey = 'fitter_premium_pending_checkout_at';
// If a pending-checkout flag is older than this we silently drop it and
// don't re-run verification on screen reopen — covers the "user opened
// Stripe a week ago, never paid, now opens Premium screen again" path
// that was leaving the app stuck in "Weryfikuję płatność…" forever.
const Duration _kPendingCheckoutMaxAge = Duration(minutes: 30);

// Premium subscription screen. Live against the Railway backend (Stripe
// Checkout + webhook) since 2026-05-27. Two plans: 19 PLN / month and
// 149 PLN / year (35% saving on yearly).
// Premium features:
//   - AI Chat z bazą wiedzy 30+ norm ASME/EN/AWS (Claude Haiku 4.5 + RAG z piping_knowledge.md)
//   - Coping template generator (PDF)
//   - Bolt torque chart (interaktywny)
//   - Heat input + preheat calculator
//   - Job-board posting (1 darmowy/mc)
//   - Bez reklam
//   - Cloud sync między urządzeniami

const _kCard = Color(0xFF1A1D26);
const _kBorder = Color(0xFF2C3354);
const _kGold = Color(0xFFE8C14B);
const _kOrange = Color(0xFFF5A623);
const _kTextSec = Color(0xFF9BA3C7);
const _kTextMut = Color(0xFF55607A);
const _kGreen = Color(0xFF2ECC71);

class PremiumScreen extends StatefulWidget {
  const PremiumScreen({super.key});

  @override
  State<PremiumScreen> createState() => _PremiumScreenState();
}

class _PremiumScreenState extends State<PremiumScreen> with WidgetsBindingObserver {
  // True while we're waiting on the user to come back from Stripe Checkout.
  // When that happens AppLifecycleState.resumed fires; we re-poll status.
  bool _awaitingReturn = false;
  // True during the post-checkout polling window. Drives a full-screen
  // overlay so the user knows we're verifying the payment instead of
  // staring at the same plan picker as before they paid.
  bool _verifying = false;
  // Re-entrancy guard so concurrent triggers (e.g. AppLifecycleState.resumed
  // firing while initState's recovery path is still polling) don't stack
  // two verification loops at once — they used to ping-pong _verifying and
  // never settle, locking the user under the overlay.
  bool _verifyInFlight = false;
  // True while we're hitting the backend to create a Stripe Checkout
  // session. Without this the user taps "Wybierz" and stares at an
  // unchanged plan picker for 1-3s on bad signal, often double-tapping.
  bool _creatingCheckout = false;

  // P2-06: rotate 2-3 sample AI prompts every few seconds on the "Try AI"
  // tile. A static "Preheat dla P91…" example becomes wallpaper after the
  // second visit; cycling concrete questions keeps the tile pulling the eye
  // toward the killer feature on each return to the screen.
  int _promptIndex = 0;
  Timer? _promptTimer;
  static const Duration _kPromptRotateInterval = Duration(seconds: 4);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // P2-06: kick off the prompt-rotation timer. Cancelled in dispose so we
    // never call setState on an unmounted widget.
    _promptTimer = Timer.periodic(_kPromptRotateInterval, (_) {
      if (!mounted) return;
      setState(() {
        _promptIndex = (_promptIndex + 1) % 3;
      });
    });
    // Cheap re-check on screen open in case backend status changed since
    // last app start (e.g. webhook fired while app was backgrounded).
    PremiumService.instance.refreshFromBackend();
    // Deep-link recovery: if the previous session launched Stripe Checkout
    // but never got the resume callback (user force-killed the app, OS
    // reaped it in background), pick the verification poll up here.
    _resumePendingCheckoutIfAny();
  }

  Future<void> _resumePendingCheckoutIfAny() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getBool(_kPendingCheckoutKey) != true) return;
      // Stale-flag guard: if the pending was set more than 30 min ago, the
      // user almost certainly abandoned that Stripe session. Clear it and
      // skip — otherwise opening Premium screen days later still pops the
      // "Weryfikuję płatność…" overlay.
      final setAtMs = prefs.getInt(_kPendingCheckoutSetAtKey);
      if (setAtMs != null) {
        final age = DateTime.now()
            .difference(DateTime.fromMillisecondsSinceEpoch(setAtMs));
        if (age > _kPendingCheckoutMaxAge) {
          await prefs.remove(_kPendingCheckoutKey);
          await prefs.remove(_kPendingCheckoutSetAtKey);
          return;
        }
      }
      if (!mounted) return;
      _refreshAfterCheckout();
    } catch (_) {
      // Best-effort recovery — never block the screen on a prefs error.
    }
  }

  @override
  void dispose() {
    // P2-06: stop rotating sample prompts the moment the screen leaves the
    // tree — periodic Timer holds a reference to setState and would crash
    // mounted-safe assertions if it kept firing.
    _promptTimer?.cancel();
    _promptTimer = null;
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _awaitingReturn) {
      _awaitingReturn = false;
      _refreshAfterCheckout();
    }
  }

  /// Wall-clock cap for the whole verification loop (regardless of polling
  /// internals). Worst-case before: 6 polls × 8s backend timeout = 48s of
  /// frozen overlay if the backend was slow. Now we hard-cap and bail.
  /// P1-11: bumped 15s → 30s — basement / workshop signal routinely makes
  /// the legitimate Stripe webhook land 15-25s after checkout completes,
  /// the old budget was tripping on real payers and forcing them through
  /// the "Nie zarejestrowaliśmy płatności" branch.
  static const Duration _kVerifyBudget = Duration(seconds: 30);

  /// Manually break out of an in-flight verification — wired to the
  /// "Anuluj" button in the overlay. Clears the persisted flag so the
  /// overlay doesn't come back on the next screen reopen.
  Future<void> _cancelVerification() async {
    if (!_verifying) return;
    setState(() {
      _verifying = false;
      _verifyInFlight = false;
    });
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_kPendingCheckoutKey);
      await prefs.remove(_kPendingCheckoutSetAtKey);
    } catch (_) {}
  }

  // Poll a few times after Stripe Checkout — webhook usually fires within a
  // couple of seconds but can lag. Hard wall-clock cap protects against
  // backend timeouts stretching the overlay; in-flight guard prevents
  // concurrent loops from a resume re-trigger.
  Future<void> _refreshAfterCheckout() async {
    if (!mounted) return;
    if (_verifyInFlight) return;
    _verifyInFlight = true;
    setState(() => _verifying = true);
    final deadline = DateTime.now().add(_kVerifyBudget);
    try {
      while (DateTime.now().isBefore(deadline)) {
        if (!mounted) return;
        if (!_verifying) return; // user hit Anuluj mid-poll
        final s = await PremiumService.instance.refreshFromBackend();
        if (!mounted) return;
        if (!_verifying) return;
        if (s.isActive) {
          setState(() {
            _verifying = false;
            _verifyInFlight = false;
          });
          try {
            final prefs = await SharedPreferences.getInstance();
            await prefs.remove(_kPendingCheckoutKey);
            await prefs.remove(_kPendingCheckoutSetAtKey);
          } catch (_) {}
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            backgroundColor: _kGreen,
            content: Text(context.tr(
              pl: 'Premium aktywne — dzięki za zakup!',
              en: 'Premium active — thanks for upgrading!',
            )),
            duration: const Duration(seconds: 4),
          ));
          await Future.delayed(const Duration(milliseconds: 900));
          if (!mounted) return;
          Navigator.maybePop(context);
          return;
        }
        await Future.delayed(const Duration(milliseconds: 1500));
      }
      // Wall-clock cap reached. Assume the user either didn't pay or the
      // webhook is more than 30s late — either way, get them OFF the
      // overlay and give them an actionable next step.
      if (!mounted) return;
      setState(() {
        _verifying = false;
        _verifyInFlight = false;
      });
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.remove(_kPendingCheckoutKey);
        await prefs.remove(_kPendingCheckoutSetAtKey);
      } catch (_) {}
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(context.tr(
          pl: 'Nie zarejestrowaliśmy płatności. Spróbuj jeszcze raz lub odśwież ekran.',
          en: 'No payment registered. Try again or pull to refresh.',
        )),
        duration: const Duration(seconds: 5),
        action: SnackBarAction(
          label: context.tr(pl: 'Odśwież', en: 'Refresh'),
          onPressed: () => PremiumService.instance.refreshFromBackend(),
        ),
      ));
    } catch (_) {
      if (mounted) {
        setState(() {
          _verifying = false;
          _verifyInFlight = false;
        });
      }
    } finally {
      _verifyInFlight = false;
    }
  }

  // P2-06: three concrete fitter prompts cycled by _promptTimer. PL/EN pairs
  // kept in lock-step so a language switch mid-rotation doesn't flash a
  // mismatched example. Pulled out into a method so the tile itself can stay
  // const-friendly aside from the dynamic text.
  String _rotatingPromptText(BuildContext context) {
    switch (_promptIndex % 3) {
      case 0:
        return context.tr(
          pl: 'Spróbuj tego: "Preheat dla P91 grubość 25 mm?"',
          en: 'Try this: "Preheat for P91, 25 mm thick?"',
        );
      case 1:
        return context.tr(
          pl: 'Spróbuj tego: "Ile minut purgi argonem dla DN100 INOX?"',
          en: 'Try this: "How long argon purge for DN100 stainless?"',
        );
      default:
        return context.tr(
          pl: 'Spróbuj tego: "Hold time NDT po spawaniu 13CrMo4-5?"',
          en: 'Try this: "NDT hold time after welding 13CrMo4-5?"',
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F1117),
      appBar: AppBar(
        backgroundColor: _kCard,
        title: ShaderMask(
          shaderCallback: (b) => const LinearGradient(
            colors: [_kOrange, _kGold],
          ).createShader(b),
          child: Text(
            'PREMIUM',
            style: const TextStyle(
              fontWeight: FontWeight.w900,
              letterSpacing: 2,
              color: Colors.white,
            ),
          ),
        ),
      ),
      body: Stack(
        children: [
      // Pull-to-refresh lets the user manually re-verify their plan if the
      // webhook lagged — useful right after a successful Stripe payment
      // when the background poll hasn't picked the activation up yet.
      RefreshIndicator(
        color: _kGold,
        onRefresh: () => PremiumService.instance.refreshFromBackend(),
        child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _Hero(),
          const SizedBox(height: 16),
          // Try AI button — direct path to the killer feature. When the
          // gate is enforced the PremiumGate around AiChatScreen will route
          // non-PRO users back here automatically.
          GestureDetector(
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const AiChatScreen()),
            ),
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF2A2218), Color(0xFF1A1D26)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: _kGold.withValues(alpha: 0.5), width: 1.5),
              ),
              child: Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: _kGold.withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.smart_toy_outlined, color: _kGold),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // P1-41: dropped the fake "DEMO" badge — there is no
                        // real demo behind it (the tile already routes through
                        // the PremiumGate to AiChatScreen). Showing mockup
                        // content on a paywall screen erodes trust; leave the
                        // title bare and let the actual gate behaviour speak.
                        Text(
                          context.tr(pl: 'Wypróbuj AI Asystenta', en: 'Try the AI Assistant'),
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFFE8ECF0),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          context.tr(
                            // P2-06: swap "270 KB" (engineering jargon, means
                            // nothing to a fitter) for the human unit "30+
                            // norm ASME/EN/AWS" so the reader sees the actual
                            // breadth of the knowledge base.
                            pl: 'Zapytaj o WPS, NACE, preheat — 30+ norm ASME/EN/AWS.',
                            en: 'Ask about WPS, NACE, preheat — 30+ standards ASME/EN/AWS.',
                          ),
                          style: const TextStyle(fontSize: 12, color: _kTextSec),
                        ),
                        const SizedBox(height: 6),
                        // P2-06: rotating sample prompt — three concrete fitter
                        // questions cycle every 4 s so the tile shows different
                        // capabilities on each glance (preheat, gas purge, NDT
                        // hold) instead of being a single static example.
                        Text(
                          _rotatingPromptText(context),
                          style: const TextStyle(
                            fontSize: 11,
                            fontStyle: FontStyle.italic,
                            color: _kGold,
                            height: 1.3,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Icon(Icons.arrow_forward_ios, color: _kGold, size: 14),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          // P2-06: mini comparison table sits above the feature tiles so the
          // glanceable "what flips on" question gets answered before the user
          // reads any prose. Four rows cover the differentiators the support
          // inbox keeps surfacing: AI chat, no ads, cloud sync, calculator
          // gates (heat input / preheat).
          const _FreeVsPremiumTable(),
          const SizedBox(height: 20),
          _SectionLabel(context.tr(pl: 'Co dostajesz', en: 'What you get')),
          const SizedBox(height: 10),
          _FeatureTile(
            icon: Icons.smart_toy_outlined,
            title: context.tr(pl: 'AI Asystent z bazą wiedzy', en: 'AI Assistant w/ knowledge base'),
            body: context.tr(
              // P2-06: "270 KB" → "30+ norm ASME/EN/AWS" so the size metric
              // becomes a coverage metric a fitter can evaluate at a glance.
              pl: 'Zapytaj o WPS, preheat dla P91, NACE compliance, ASME B31 — '
                  'odpowiada z 30+ norm ASME/EN/AWS skondensowanych w jednej bazie.',
              en: 'Ask about WPS, P91 preheat, NACE compliance, ASME B31 — '
                  'answers from 30+ ASME/EN/AWS standards curated in one base.',
            ),
          ),
          _FeatureTile(
            icon: Icons.straighten,
            title: context.tr(pl: 'Coping & saddle templates (PDF)', en: 'Coping & saddle templates (PDF)'),
            body: context.tr(
              pl: 'Generuj szablony do owinięcia na rurze przed cięciem fish-mouth. '
                  'Druk 1:1 dla dowolnej kombinacji DN/kąt.',
              en: 'Print 1:1 wrap-around templates for fish-mouth branch cuts. '
                  'Any DN/angle combination.',
            ),
          ),
          _FeatureTile(
            icon: Icons.bolt_outlined,
            title: context.tr(pl: 'Kalkulator momentu śrub', en: 'Bolt torque calculator'),
            body: context.tr(
              pl: 'Flange + klasa + gatunek śrub (B7/B7M/B16/B8M) + smar → torque Nm/ft-lb. '
                  'Star pattern dla 4/8/12/16/20/24 śrub.',
              en: 'Flange + class + bolt grade + lube → torque Nm/ft-lb. '
                  'Star pattern for 4/8/12/16/20/24 bolts.',
            ),
          ),
          _FeatureTile(
            icon: Icons.local_fire_department_outlined,
            title: context.tr(pl: 'Heat input + preheat (CE)', en: 'Heat input + preheat (CE)'),
            body: context.tr(
              pl: 'Heat input kJ/mm z kontrolą out-of-WPS-range. '
                  'Carbon equivalent (IIW + Pcm) → wymóg preheatu.',
              en: 'Heat input kJ/mm with out-of-WPS-range alarm. '
                  'Carbon equivalent (IIW + Pcm) → preheat requirement.',
            ),
          ),
          _FeatureTile(
            icon: Icons.work_outline,
            title: context.tr(pl: '1 darmowe ogłoszenie/mc w Pracy', en: '1 free job listing/mo'),
            body: context.tr(
              pl: 'Wystaw 1 ogłoszenie w module Praca każdego miesiąca za darmo (oszczędność ~19 PLN).',
              en: 'Post 1 job listing per month for free (~19 PLN saved).',
            ),
          ),
          _FeatureTile(
            icon: Icons.cloud_sync_outlined,
            title: context.tr(pl: 'Cloud sync między urządzeniami', en: 'Cross-device cloud sync'),
            body: context.tr(
              pl: 'Projekty cut list + zeszyt ISO sync między telefonem i tabletem.',
              en: 'Cut list projects + ISO notebook sync between phone & tablet.',
            ),
          ),
          _FeatureTile(
            icon: Icons.block,
            title: context.tr(pl: 'Bez reklam', en: 'Ad-free'),
            body: context.tr(
              pl: 'Czyste UI bez bannerów i interstitial.',
              en: 'Clean UI, no banners or interstitials.',
            ),
          ),
          const SizedBox(height: 20),
          _SectionLabel(context.tr(pl: 'Plany', en: 'Plans')),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _PlanCard(
                  title: context.tr(pl: 'Miesięczny', en: 'Monthly'),
                  price: '19 PLN',
                  per: context.tr(pl: '/mc', en: '/mo'),
                  badge: null,
                  onTap: () => _startCheckout(context, PremiumPlan.monthly),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _PlanCard(
                  title: context.tr(pl: 'Roczny', en: 'Yearly'),
                  price: '149 PLN',
                  per: context.tr(pl: '/rok', en: '/yr'),
                  badge: context.tr(
                      pl: 'OSZCZĘDZASZ 35% · POPULARNE',
                      en: 'SAVE 35% · MOST POPULAR'),
                  // P1-27: display-only — the actual Stripe
                  // trial_period_days is wired backend-side; surface the
                  // benefit on the card so the yearly plan reads as the
                  // risk-free pick.
                  trialBadge: context.tr(
                    pl: 'Pierwsze 7 dni za darmo',
                    en: 'First 7 days free',
                  ),
                  // P2-06: per-month equivalent line under the yearly price —
                  // 149 PLN / 12 ≈ 12.42 PLN/mc; we surface "≈12 zł/mc" so a
                  // buyer comparing the two plans sees the yearly is ~35%
                  // cheaper per month at a glance instead of doing mental
                  // long division in gloves.
                  perMonthEquivalent: context.tr(
                    pl: '≈ 12 zł/mc',
                    en: '≈ 12 PLN/mo',
                  ),
                  highlight: true,
                  onTap: () => _startCheckout(context, PremiumPlan.yearly),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          // P1-27: "Anuluj w każdej chwili" promoted to its own 13 pt line
          // so the reassurance reads first instead of being buried in the
          // payment-providers run-on. BLIK kept in EN copy for parity with
          // the PL string (Polish payers using EN UI still see it).
          Text(
            context.tr(
              pl: 'Anuluj w każdej chwili.',
              en: 'Cancel anytime.',
            ),
            style: const TextStyle(
              fontSize: 13,
              color: _kTextSec,
              fontWeight: FontWeight.w700,
              height: 1.4,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 6),
          Text(
            context.tr(
              pl: 'Płatność: Stripe (karta, BLIK, Apple Pay, Google Pay).',
              en: 'Payment: Stripe (card, BLIK, Apple Pay, Google Pay).',
            ),
            style: const TextStyle(fontSize: 11, color: _kTextMut, height: 1.4),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 6),
          // P1-27: invoice footnote so accounting-conscious buyers (sole
          // traders, B2B fitters) see the VAT option without having to
          // contact support pre-purchase. Fakturownia automation lands in
          // a later milestone — for now the channel is manual e-mail.
          Text(
            context.tr(
              pl: 'Faktura VAT na żądanie — napisz po zakupie.',
              en: 'VAT invoice on request — message us after purchase.',
            ),
            style: const TextStyle(fontSize: 11, color: _kTextMut, height: 1.4),
            textAlign: TextAlign.center,
          ),
          // P1-41: subtle "Maybe later" handoff. A paywall with no clear
          // way out reads as a trap on first contact — a single muted line
          // ("Pomiń teraz") + a 48 dp tap target lets the user defer the
          // decision without having to hunt for the back gesture. Kept
          // visually quiet so it doesn't compete with the FilledButtons.
          const SizedBox(height: 14),
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 48, minWidth: 48),
              child: TextButton(
                onPressed: () {
                  if (!mounted) return;
                  // If a verification or checkout-prep overlay happens to be
                  // up we dismiss it first; otherwise pop the route. Either
                  // path gives the user the obvious "out" the hint promises.
                  if (_verifying || _creatingCheckout) {
                    setState(() {
                      _verifying = false;
                      _verifyInFlight = false;
                      _creatingCheckout = false;
                    });
                    return;
                  }
                  Navigator.maybePop(context);
                },
                child: Text(
                  context.tr(pl: 'Pomiń teraz', en: 'Maybe later'),
                  style: const TextStyle(
                    fontSize: 12,
                    color: _kTextMut,
                    fontWeight: FontWeight.w600,
                    decoration: TextDecoration.underline,
                    decorationColor: _kTextMut,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 4),
        ],
      ),
      ),
      if (_verifying || _creatingCheckout)
        Positioned.fill(
          child: AbsorbPointer(
            child: Container(
              color: Colors.black.withValues(alpha: 0.65),
              alignment: Alignment.center,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
                decoration: BoxDecoration(
                  color: _kCard,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: _kGold.withValues(alpha: 0.5)),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const CircularProgressIndicator(color: _kGold),
                    const SizedBox(height: 14),
                    Text(
                      _verifying
                          ? context.tr(
                              pl: 'Weryfikuję płatność…',
                              en: 'Verifying payment…',
                            )
                          : context.tr(
                              pl: 'Przygotowuję płatność…',
                              en: 'Preparing checkout…',
                            ),
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFFE8ECF0),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _verifying
                          ? context.tr(
                              pl: 'Stripe potwierdza zakup — to chwilę potrwa.',
                              en: 'Stripe is confirming — give it a moment.',
                            )
                          : context.tr(
                              pl: 'Otwieram bezpieczną stronę Stripe…',
                              en: 'Opening Stripe secure checkout…',
                            ),
                      style: const TextStyle(fontSize: 11, color: _kTextSec),
                      textAlign: TextAlign.center,
                    ),
                    // P1-11: linear progress under the spinner — a flat bar
                    // reads as "something is happening" even when the
                    // spinner blends into the gold/dark palette on dimmer
                    // workshop screens; gives the user a second visual cue
                    // that the verification is still in flight.
                    if (_verifying) ...[
                      const SizedBox(height: 14),
                      SizedBox(
                        width: 220,
                        child: LinearProgressIndicator(
                          minHeight: 3,
                          backgroundColor: _kBorder,
                          valueColor: const AlwaysStoppedAnimation<Color>(_kGold),
                        ),
                      ),
                    ],
                    // Escape hatch — only on the verifying overlay, NOT on
                    // the brief "preparing checkout" one. Without this the
                    // user is locked in the overlay until the wall-clock
                    // budget elapses, which is the bug they reported.
                    if (_verifying) ...[
                      const SizedBox(height: 16),
                      // P1-11: lets the payer who already saw "Payment
                      // successful" on Stripe re-trigger the verification
                      // poll without waiting for the budget to expire. We
                      // also reset the in-flight flag so the call isn't
                      // short-circuited by the re-entrancy guard.
                      ConstrainedBox(
                        constraints: const BoxConstraints(minHeight: 48),
                        child: TextButton(
                          onPressed: () {
                            _verifyInFlight = false;
                            _refreshAfterCheckout();
                          },
                          child: Text(
                            context.tr(
                              pl: 'Już zapłaciłem',
                              en: 'I already paid',
                            ),
                            style: const TextStyle(
                              color: _kGold,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 4),
                      ConstrainedBox(
                        constraints: const BoxConstraints(minHeight: 48),
                        child: TextButton(
                          onPressed: _cancelVerification,
                          child: Text(
                            context.tr(pl: 'Anuluj', en: 'Cancel'),
                            style: const TextStyle(
                              color: _kTextSec,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
        ],
      ),
    );
  }

  Future<void> _startCheckout(BuildContext context, PremiumPlan plan) async {
    if (!BackendConfig.stripeBackendLive) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(
          context.tr(
            pl: 'Płatności w przygotowaniu — wkrótce uruchomimy Premium.',
            en: 'Payments under construction — Premium launches soon.',
          ),
        ),
      ));
      return;
    }

    if (mounted) setState(() => _creatingCheckout = true);
    try {
      // Make sure we have a device id available (it's lazy-loaded otherwise).
      await PremiumService.instance.init();
      // P0r-10: clear any pending downgrade state machine from a prior
      // backend race — without this, a previously-armed grace timer can
      // fire mid-checkout and momentarily strip PRO even though the user
      // is about to (re-)purchase.
      PremiumService.instance.clearPendingDowngrade();
      final url = await PremiumService.instance.createCheckoutSession(
        plan: plan,
        deviceId: PremiumService.instance.deviceId,
      );
      if (url == null) {
        if (mounted) setState(() => _creatingCheckout = false);
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(context.tr(
            pl: 'Nie udało się utworzyć sesji płatności.',
            en: 'Failed to create checkout session.',
          )),
        ));
        return;
      }
      // Open Stripe Checkout in the user's default browser. Stripe redirects
      // back to /api/fitter/billing/success once payment goes through.
      _awaitingReturn = true;
      // Mirror the in-memory flag to disk so a cold start during the Stripe
      // round-trip still resumes the verification poll on next launch.
      // Timestamp accompanies the bool so the recovery path can drop the
      // flag silently if it's been sitting around for >30 min (user
      // abandoned the Stripe session and reopened Premium screen later).
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool(_kPendingCheckoutKey, true);
        await prefs.setInt(
          _kPendingCheckoutSetAtKey,
          DateTime.now().millisecondsSinceEpoch,
        );
      } catch (_) {}
      final ok = await launchUrl(
        Uri.parse(url),
        mode: LaunchMode.externalApplication,
      );
      if (mounted) setState(() => _creatingCheckout = false);
      if (!ok && context.mounted) {
        _awaitingReturn = false;
        try {
          final prefs = await SharedPreferences.getInstance();
          await prefs.remove(_kPendingCheckoutKey);
          await prefs.remove(_kPendingCheckoutSetAtKey);
        } catch (_) {}
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(context.tr(
            pl: 'Nie udało się otworzyć przeglądarki.',
            en: 'Failed to open browser.',
          )),
        ));
      }
    } catch (e) {
      _awaitingReturn = false;
      if (mounted) setState(() => _creatingCheckout = false);
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.remove(_kPendingCheckoutKey);
        await prefs.remove(_kPendingCheckoutSetAtKey);
      } catch (_) {}
      if (!context.mounted) return;
      // Don't leak raw exception strings (HTTP codes, library names) to a
      // user about to part with money — show a clear, actionable message
      // and keep the technical detail in the debug console for support.
      debugPrint('PremiumScreen checkout error: $e');
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(context.tr(
          pl: 'Coś poszło nie tak przy płatności. Sprawdź połączenie.',
          en: 'Payment setup failed. Check your connection.',
        )),
        duration: const Duration(seconds: 4),
        action: SnackBarAction(
          label: context.tr(pl: 'Ponów', en: 'Retry'),
          onPressed: () => _startCheckout(context, plan),
        ),
      ));
    }
  }
}

class _Hero extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      // P1-41: tightened vertical padding from 20 → 14 so the hero plus the
      // price pill below fit above the fold on 360 dp phones (Pixel 4a class)
      // without forcing the user to scroll to see what Premium costs.
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 14),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF2A2218), Color(0xFF1A1D26)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _kGold.withValues(alpha: 0.3), width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.workspace_premium, color: _kGold, size: 28),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  context.tr(pl: 'Fitter Welder Pro+', en: 'Fitter Welder Pro+'),
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFFE8ECF0),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            context.tr(
              pl: 'Pełen arsenał monterski + AI asystent w jednej apce.',
              en: 'Full fitter arsenal + AI assistant in one app.',
            ),
            style: const TextStyle(fontSize: 13, color: _kTextSec),
          ),
          const SizedBox(height: 10),
          // P1-41: compact price pill — the actual numbers (19 PLN/mc and 149
          // PLN/rok) MUST be visible without scrolling on a 360 dp phone, so
          // we surface them inside the hero. The full _PlanCard row stays
          // further down for the tap target + badges.
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: _kGold.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: _kGold.withValues(alpha: 0.4)),
            ),
            child: Text(
              context.tr(
                pl: '19 PLN/mc  ·  149 PLN/rok (-35%)',
                en: '19 PLN/mo  ·  149 PLN/yr (-35%)',
              ),
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w900,
                color: _kGold,
                letterSpacing: 0.2,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text.toUpperCase(),
      style: const TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w700,
        color: _kTextMut,
        letterSpacing: 1.5,
      ),
    );
  }
}

class _FeatureTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String body;
  const _FeatureTile({required this.icon, required this.title, required this.body});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _kCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _kBorder),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: _kGold.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 20, color: _kGold),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFFE8ECF0),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  body,
                  style: const TextStyle(fontSize: 12, color: _kTextSec, height: 1.4),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PlanCard extends StatelessWidget {
  final String title;
  final String price;
  final String per;
  final String? badge;
  // P1-27: display-only free-trial badge surfaced next to the yearly card
  // ("Pierwsze 7 dni za darmo"). The actual trial is configured on Stripe
  // via trial_period_days on the price object — this widget only marks the
  // plan visually so the yearly tile reads as the risk-free pick.
  final String? trialBadge;
  // P2-06: per-month equivalent caption (e.g. "≈ 12 zł/mc") so the yearly
  // card communicates its monthly cost directly instead of asking the buyer
  // to divide 149 by 12 in their head.
  final String? perMonthEquivalent;
  final bool highlight;
  final VoidCallback onTap;

  const _PlanCard({
    required this.title,
    required this.price,
    required this.per,
    required this.badge,
    required this.onTap,
    this.trialBadge,
    this.perMonthEquivalent,
    this.highlight = false,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: _kCard,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: highlight ? _kGold : _kBorder,
            width: highlight ? 2 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: Color(0xFFE8ECF0),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(
                  price,
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                    color: highlight ? _kGold : const Color(0xFFE8ECF0),
                  ),
                ),
                Text(
                  per,
                  style: const TextStyle(fontSize: 12, color: _kTextMut),
                ),
              ],
            ),
            if (perMonthEquivalent != null) ...[
              // P2-06: per-month equivalent line ("≈ 12 zł/mc") rendered
              // immediately under the headline price — small, muted, so it
              // reads as supporting math rather than a second price tag.
              const SizedBox(height: 2),
              Text(
                perMonthEquivalent!,
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: _kTextSec,
                ),
              ),
            ],
            if (badge != null) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: _kGreen.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  badge!,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    color: _kGreen,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
            ],
            if (trialBadge != null) ...[
              const SizedBox(height: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: _kGold.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: _kGold.withValues(alpha: 0.5)),
                ),
                child: Text(
                  trialBadge!,
                  style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    color: _kGold,
                    letterSpacing: 0.3,
                  ),
                ),
              ),
            ],
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: onTap,
                style: FilledButton.styleFrom(
                  backgroundColor: highlight ? _kGold : _kCard,
                  side: BorderSide(color: highlight ? _kGold : _kBorder),
                  foregroundColor: highlight ? Colors.black : const Color(0xFFE8ECF0),
                ),
                child: Text(
                  context.tr(pl: 'Wybierz', en: 'Choose'),
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// P2-06: compact "Free vs Premium" comparison table. Four rows cover the
// differentiators that come up most often in support tickets and the
// upgrade-flow analytics: AI chat, ads, cloud sync, and the calculator
// gates (heat input / preheat / coping). Free column shows a muted "—" so
// the eye-track jumps to the green check on the Premium side.
class _FreeVsPremiumTable extends StatelessWidget {
  const _FreeVsPremiumTable();

  @override
  Widget build(BuildContext context) {
    final rows = <_FvpRow>[
      _FvpRow(
        label: context.tr(pl: 'AI asystent (chat)', en: 'AI assistant (chat)'),
        free: false,
      ),
      _FvpRow(
        label: context.tr(pl: 'Bez reklam', en: 'No ads'),
        free: false,
      ),
      _FvpRow(
        label: context.tr(pl: 'Cloud sync (telefon ↔ tablet)', en: 'Cloud sync (phone ↔ tablet)'),
        free: false,
      ),
      _FvpRow(
        label: context.tr(
          pl: 'Kalkulatory zaawansowane (heat input, preheat)',
          en: 'Advanced calculators (heat input, preheat)',
        ),
        free: false,
      ),
    ];
    return Container(
      decoration: BoxDecoration(
        color: _kCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _kBorder),
      ),
      child: Column(
        children: [
          // Header row.
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 8),
            child: Row(
              children: [
                const Expanded(child: SizedBox.shrink()),
                SizedBox(
                  width: 64,
                  child: Text(
                    context.tr(pl: 'Free', en: 'Free'),
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: _kTextMut,
                      letterSpacing: 1.0,
                    ),
                  ),
                ),
                SizedBox(
                  width: 64,
                  child: Text(
                    context.tr(pl: 'Premium', en: 'Premium'),
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: _kGold,
                      letterSpacing: 1.0,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: _kBorder),
          for (int i = 0; i < rows.length; i++) ...[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      rows[i].label,
                      style: const TextStyle(
                        fontSize: 13,
                        color: Color(0xFFE8ECF0),
                        height: 1.3,
                      ),
                    ),
                  ),
                  SizedBox(
                    width: 64,
                    child: Center(
                      child: rows[i].free
                          ? const Icon(Icons.check_rounded,
                              color: _kGreen, size: 18)
                          : const Text(
                              '—',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                                color: _kTextMut,
                              ),
                            ),
                    ),
                  ),
                  const SizedBox(
                    width: 64,
                    child: Center(
                      child: Icon(Icons.check_rounded,
                          color: _kGold, size: 20),
                    ),
                  ),
                ],
              ),
            ),
            if (i < rows.length - 1)
              const Divider(height: 1, color: _kBorder),
          ],
        ],
      ),
    );
  }
}

class _FvpRow {
  final String label;
  final bool free;
  const _FvpRow({required this.label, required this.free});
}
