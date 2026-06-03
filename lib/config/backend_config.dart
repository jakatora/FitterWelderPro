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
  /// Railway-hosted FastAPI/Express backend. Reuses the PrzetargAI server;
  /// the Fitter Welder routes live under `/api/fitter/*`.
  static const String baseUrl =
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
