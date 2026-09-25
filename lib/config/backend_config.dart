// Backend endpoints + feature flags for the Premium / AI / Praca modules.
//
// Single source of truth: flip a flag here once the corresponding backend
// is deployed, and the rest of the app routes through it automatically.
// Until then the relevant screens fall back to demo mode / local storage.
//
// Tożsamość urządzenia (kontrakt backendu z 2026-09-24, `backend/README.md`):
// nagłówki `X-Device-Id` (PremiumService.deviceId) i `X-Install-Secret`
// (losowy sekret instalacji, PremiumService.installSecret). Po zgodzie na
// zasady czatu aplikacja woła [deviceRegister]; stary backend odpowiada na tę
// trasę 404 i aplikacja działa dalej po staremu. Nie ma kont ani tokenów.

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

  /// Skaner izometrii — ten sam dedykowany backend co reszta aplikacji.
  ///
  /// WYMAGA wdrożonej wersji backendu z 2026-09-24 (sekret instalacji TOFU,
  /// dzienne limity na urządzenie i IP, bramka budżetu AI, model
  /// claude-sonnet-5, rozpoznawanie typu obrazu). Stara wersja dedykowanego
  /// backendu odpowiada na POST /api/fitter/scan-iso kodem **500** (zaszyty
  /// identyfikator modelu, którego API nie zna) — aplikacja pokazuje wtedy
  /// zrozumiały komunikat „skaner nie jest jeszcze dostępny" zamiast „Błąd
  /// 500" (`iso_scanner_ai.dart`), tak samo przy 404 (brak trasy).
  ///
  /// Historia: 2026-08-29 skaner tymczasowo celował we współdzielony backend
  /// PrzetargAI (backend-production-a43e3), bo tylko tam scan-iso zwracało
  /// 200. Tamten backend nie ma limitów per urządzenie ani bramki budżetu tej
  /// aplikacji, więc darmowego trybu skanera nie wolno było na nim oprzeć.
  ///
  /// Przed publikacją: wdrożyć backend, zrobić jeden prawdziwy skan (HTTP 200)
  /// i sprawdzić 429 po przekroczeniu `AI_SCAN_DAILY_PER_DEVICE`.
  static const String scannerBaseUrl = baseUrl;

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

  /// POST — klasyfikacja polecenia asystenta (tryb „Wykonaj"), kontrakt w
  /// lib/assistant/assistant_intent_client.dart. Stary backend: 404.
  static const String aiIntent = '/api/fitter/ai/intent';
  static const String knowledgeSearch = '/api/fitter/ai/search';
  static const String scanIso = '/api/fitter/scan-iso';
  static const String jobsList = '/api/fitter/jobs';
  static const String jobsCreate = '/api/fitter/jobs';
  static const String jobsBoost = '/api/fitter/jobs/boost'; // Stripe one-time
  static const String chatRooms = '/api/fitter/chat/rooms';
  static const String chatMessages = '/api/fitter/chat/messages';
  static const String chatReport = '/api/fitter/chat/report';

  /// POST — powiązanie sekretu instalacji z device_id (201/200). Stary
  /// backend: 404, które aplikacja po cichu ignoruje.
  static const String deviceRegister = '/api/fitter/device/register';

  /// DELETE — usunięcie danych urządzenia z serwera („Usuń moje dane").
  /// Stary backend: 404 → aplikacja kieruje do usunięcia mailowego.
  static const String me = '/api/fitter/me';

  /// Publiczne strony dla sklepów (statyczny HTML z backendu).
  static const String privacyPage = '/privacy';
  static const String dataDeletionPage = '/data-deletion';

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
