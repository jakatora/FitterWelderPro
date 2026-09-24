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
  ///
  /// 2026-09-24: nowa wersja dedykowanego backendu (sekret instalacji, limity
  /// dzienne i bramka budżetu AI na /scan-iso) jest gotowa, ale jeszcze NIE
  /// wdrożona. Po wdrożeniu i sprawdzeniu realnym skanem (HTTP 200) można
  /// przełączyć skaner na [baseUrl]. Aplikacja wysyła już nagłówki
  /// X-Device-Id / X-Install-Secret — backend PrzetargAI je ignoruje.
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
