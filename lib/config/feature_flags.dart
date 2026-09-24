// Feature switches for Fitter Welder Pro.
//
// The app is being reshaped into a community tool for welders and fitters:
// public chat (signed with the member's real name), member profiles showing
// the welding parameters / amps they actually run, and a shared wish list.
// Those are FREE for everyone — the community IS the product.
//
// Anything that costs money to run stays switched OFF and is HIDDEN from the
// UI entirely (not shown as "coming soon"), so a user never walks into a dead
// end or a purchase flow we don't want live yet:
//   • Stripe / Premium tier      → kPaidFeaturesEnabled
//   • Job board (backend not deployed) → kJobsEnabled
//
// The one metered feature that IS live is the ISO scanner
// (kAiScannerEnabled): every scan is a Claude Vision call, so read the note
// on that flag before touching it — it says exactly which caps exist and
// which do not.
//
// IMPORTANT (audit P0): once kCommunityEnabled is true the app talks to the
// Railway backend, so the store listing may NOT claim "works fully offline /
// no data collected". The privacy policy and the App Privacy / Data Safety
// declarations must describe chat, profiles and the wish list before release.

/// Paid tier (Stripe checkout, Premium screen). Hidden while false.
const bool kPaidFeaturesEnabled = false;

/// Metered AI: ISO drawing scanner (Claude Vision, cost per scan).
///
/// ON since 2026-08-29, when the scanner finally leads somewhere: a scan can
/// be reviewed and saved as a real project with a cut list
/// (`scan_review_screen.dart`) instead of ending in the clipboard.
///
/// What actually caps the bill — read out of `backend/src`, not assumed:
///   • `PremiumGate(alwaysEnforced: true)` on the scanner screen: only an
///     active Premium subscription can reach the camera at all;
///   • [kAiScanDailyLimitPerDevice]: a per-install daily budget that the
///     scanner screen enforces and shows before every scan.
///
/// What does NOT cap it: the backend. `/api/fitter/scan-iso` has no
/// per-device daily limit and no budget gate. The only server-side control
/// is the shared 120-requests-per-minute IP limiter in `app.js` (verified
/// live: the route answers with `ratelimit-limit: 120`, `ratelimit-policy:
/// 120;w=60`), and `AI_BUDGET_SOFT_USD` / `AI_BUDGET_HARD_USD` are declared
/// in `config/env.js` and never read by anything. Until a real cap lands
/// server-side, the two caps above are the only ones there are — and both
/// live on a device the user controls.
///
/// The menu tiles (home screen, FITTER menu) follow [kAiScannerReachable],
/// not this flag: while Premium cannot be bought the tile would lead only to
/// a gate with no way through, so it stays hidden
/// (`test/welder_journey_test.dart` pins that behaviour).
const bool kAiScannerEnabled = true;

/// Whether a user can actually unlock the ISO scanner by buying Premium.
///
/// The scanner screen sits behind `PremiumGate(alwaysEnforced: true)`, and
/// Premium cannot be bought while [kPaidFeaturesEnabled] is false. The menu
/// tiles follow this constant, so the scanner is never offered as a dead end.
const bool kAiScannerReachable = kAiScannerEnabled && kPaidFeaturesEnabled;

/// Scans one install may run per calendar day before the scanner refuses.
///
/// A fitter works through a handful of drawings a day, so this sits far above
/// normal use and far below a runaway loop. It is a client-side budget — a
/// reinstall resets it — so it protects against an accident (a stuck retry, a
/// curious afternoon), not against abuse. Abuse still needs a server-side cap.
const int kAiScanDailyLimitPerDevice = 25;

/// Job board. The backend route exists but `jobsBackendLive` is false, so the
/// listings would be device-local only. Hidden while false.
const bool kJobsEnabled = false;

/// Community: public chat, member profiles (amps), shared wish list.
/// Free for everyone.
const bool kCommunityEnabled = true;
