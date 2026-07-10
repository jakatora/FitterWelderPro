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
//   • ISO Scanner (Claude Vision, billed per scan) → kAiScannerEnabled
//   • Job board (backend not deployed) → kJobsEnabled
//
// IMPORTANT (audit P0): once kCommunityEnabled is true the app talks to the
// Railway backend, so the store listing may NOT claim "works fully offline /
// no data collected". The privacy policy and the App Privacy / Data Safety
// declarations must describe chat, profiles and the wish list before release.

/// Paid tier (Stripe checkout, Premium screen). Hidden while false.
const bool kPaidFeaturesEnabled = false;

/// Metered AI: ISO drawing scanner (Claude Vision, cost per scan). Hidden
/// while false — shipping it free is an uncapped bill.
const bool kAiScannerEnabled = false;

/// Job board. The backend route exists but `jobsBackendLive` is false, so the
/// listings would be device-local only. Hidden while false.
const bool kJobsEnabled = false;

/// Community: public chat, member profiles (amps), shared wish list.
/// Free for everyone.
const bool kCommunityEnabled = true;
