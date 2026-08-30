// Backend endpoints + feature flags for the Premium / AI / Praca modules.
//
// Single source of truth: flip a flag here once the corresponding backend
// is deployed, and the rest of the app routes through it automatically.
// Until then the relevant screens fall back to demo mode / local storage.
//
// Endpoints reuse the Railway backend from the PrzetargAI project.
// Authentication: Bearer token from Firebase Auth UID + signed JWT issued
// by the backend on /api/auth/exchange. The token is cached in memory by
// PremiumService and refreshed when it expires.

class BackendConfig {
  // ── Base URLs ────────────────────────────────────────────────────────────
  /// Standalone Fitter Welder Pro backend on its own Railway project
  /// (jubilant-charm, deployed 2026-06-05). Replaced the shared PrzetargAI
  /// backend at backend-production-a43e3.up.railway.app — that one had a
  /// stale Anthropic model alias and shared infra with KredytAI/PrzetargAI,
  /// user wanted clean separation. Same /api/fitter/* route prefix so route
  /// paths in this file did not need to change.
  static const String baseUrl =
      'https://fitter-welder-pro-backend-production.up.railway.app';

  /// Skaner izometrii celuje w INNY backend niz reszta apki — i to jest swiadome.
  ///
  /// Stan na 2026-08-29, sprawdzony realnym zadaniem POST /api/fitter/scan-iso:
  ///   • dedykowany backend (baseUrl powyzej): /health = 200, ale scan-iso = **500**,
  ///   • wspoldzielony backend PrzetargAI: scan-iso = **200**, model claude-sonnet-5,
  ///     poprawnie odczytal testowa izometrie (2 segmenty, kolano 90 LR, dwa kolnierze,
  ///     DN100/SCH40/A312 316L) i sam policzyl wymiar zapisany jako "1500+250".
  ///
  /// Powod przeniesienia skanera na wlasny backend byl inny — „stale Anthropic model
  /// alias" na wspoldzielonym — i wlasnie zostal usuniety (alias podniesiony do
  /// claude-sonnet-5, tanszego i nowszego niz poprzedni claude-sonnet-4-6).
  ///
  /// Po naprawie dedykowanego backendu wystarczy usunac te stala i wrocic do baseUrl.
  /// Nie ruszamy tu pozostalych tras (czat, platnosci) — one dzialaja na dedykowanym.
  static const String scannerBaseUrl =
      'https://backend-production-a43e3.up.railway.app';

  // ── Feature flags ────────────────────────────────────────────────────────
  /// Set to true once Stripe checkout webhook + /api/fitter/subscribe are
  /// live on Railway. Until then, PremiumScreen renders the "Coming soon"
  /// snackbar and PremiumGate stays open (no paywall).
  static const bool stripeBackendLive = true; // LIVE since 2026-05-27

  /// Set to true once the /api/fitter/ai-chat endpoint is deployed.
  /// Until then, AiChatService returns canned demo answers.
  static const bool aiBackendLive = true; // LIVE since 2026-05-27

  /// Set to true once Firestore + Cloud Functions are configured for
  /// cross-device job listing sync. Until then jobs_screen.dart uses
  /// local SQLite only.
  static const bool jobsBackendLive = false;

  /// Set to true once user-to-user chat (Railway-backed public rooms with
  /// rolling moderation) is live. The Flutter client polls /api/fitter/chat
  /// every ~8s while a room is open.
  static const bool chatBackendLive = true; // LIVE since 2026-05-28

  // ── Endpoint paths (relative to baseUrl) ────────────────────────────────
  static const String authExchange = '/api/fitter/auth/exchange';
  static const String stripeCheckout = '/api/fitter/billing/checkout';
  static const String stripePortal = '/api/fitter/billing/portal';
  static const String premiumStatus = '/api/fitter/billing/status';
  static const String aiChat = '/api/fitter/ai/chat';
  static const String knowledgeSearch = '/api/fitter/ai/search';
  static const String scanIso = '/api/fitter/scan-iso';
  static const String jobsList = '/api/fitter/jobs';
  static const String jobsCreate = '/api/fitter/jobs';
  static const String jobsBoost = '/api/fitter/jobs/boost'; // Stripe one-time
  static const String chatRooms = '/api/fitter/chat/rooms';
  static const String chatMessages = '/api/fitter/chat/messages';
  static const String chatReport = '/api/fitter/chat/report';

  // ── Stripe plans ────────────────────────────────────────────────────────
  /// Plan IDs the backend uses when creating a checkout session. The actual
  /// Stripe Price IDs are configured server-side via env vars; the client
  /// just sends the plan identifier.
  static const String planMonthly = 'fitter_pro_monthly_19pln';
  static const String planYearly = 'fitter_pro_yearly_149pln';

  /// Stripe one-time payment plans for boosting a job listing.
  static const String boostWeek = 'job_boost_7d_19pln';
  static const String boostMonth = 'job_boost_30d_49pln';
}
