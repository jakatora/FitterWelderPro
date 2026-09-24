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
// (kAiScannerEnabled + kAiScannerFreeTier): every scan is a Claude Vision
// call, free for the user within a daily limit. Read the note on
// [kAiScannerEnabled] before touching it — it lists which caps exist where.
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
/// Since 2026-09-25 it runs in a FREE tier ([kAiScannerFreeTier]) against the
/// dedicated backend (`BackendConfig.scannerBaseUrl` == `baseUrl`). What caps
/// the bill — read out of `backend/src` (version of 2026-09-24), not assumed:
///   • server, per install: `AI_SCAN_DAILY_PER_DEVICE` scans per UTC day
///     (default 10), keyed by `device_id` bound to the install secret on
///     first use (TOFU, `X-Install-Secret`) — answers 429 `RATE_LIMITED`
///     with `Retry-After`;
///   • server, per IP: `AI_SCAN_DAILY_PER_IP` per UTC day (default 30) and
///     `AI_SCAN_PER_IP_PER_MIN` per minute (default 6), both checked BEFORE
///     the 10 MB body is read;
///   • server, money: monthly `AI_BUDGET_SOFT_USD` / `AI_BUDGET_HARD_USD`
///     gate in front of every Anthropic call — 503 `AI_BUDGET_EXCEEDED`;
///   • server, optional: `AI_SCAN_REQUIRES_PREMIUM=true` turns the route into
///     Premium-only (402 `PREMIUM_REQUIRED`); default false;
///   • client: [kAiScanDailyLimitPerDevice], a per-install counter the
///     scanner screen shows ("Pozostało dziś: N") and enforces before a
///     photo leaves the phone. A safety fuse only — a reinstall resets it.
///
/// The OLD deployment of the dedicated backend (before 2026-09-24) answers
/// `/scan-iso` with 500 and has none of the server caps above; the client
/// then shows a plain "scanner not available yet" message
/// (`iso_scanner_ai.dart`). The scanner must not be advertised before the
/// owner deploys the new backend and a real scan returns 200.
///
/// The menu tiles (home screen, FITTER menu) follow [kAiScannerReachable]
/// (`test/welder_journey_test.dart`, `test/config/scanner_flags_test.dart`).
const bool kAiScannerEnabled = true;

/// Free tier of the ISO scanner: no Premium needed, daily limits instead
/// (server `AI_SCAN_DAILY_PER_DEVICE` + [kAiScanDailyLimitPerDevice]).
///
/// With this on the scanner screen is NOT wrapped in a Premium gate. Before
/// the first scan the user is told where the photo goes (our server +
/// Anthropic) and asked to agree (`widgets/scan_consent_gate.dart`).
/// Switch off to put the scanner back behind `PremiumGate(alwaysEnforced)`
/// — then it is reachable only once Premium can be bought.
const bool kAiScannerFreeTier = true;

/// Whether the ISO scanner leads somewhere usable: either the free tier is
/// on, or Premium can actually be bought. The menu tiles follow this
/// constant, so the scanner is never offered as a dead end or a price screen.
const bool kAiScannerReachable =
    kAiScannerEnabled && (kPaidFeaturesEnabled || kAiScannerFreeTier);

/// Scans one install may run per calendar day before the scanner refuses.
///
/// Equal to the backend default `AI_SCAN_DAILY_PER_DEVICE` (10), so the
/// "Pozostało dziś: N" the screen shows matches what the server allows. If
/// the owner raises the server limit, raise this too — otherwise the phone
/// stops first. It is a client-side fuse — a reinstall resets it — so it
/// protects against an accident (a stuck retry, a curious afternoon); the
/// server caps are what stop abuse.
const int kAiScanDailyLimitPerDevice = 10;

/// Job board. The backend route exists but `jobsBackendLive` is false, so the
/// listings would be device-local only. Hidden while false.
const bool kJobsEnabled = false;

/// Community: public chat, member profiles (amps), shared wish list.
/// Free for everyone.
const bool kCommunityEnabled = true;
