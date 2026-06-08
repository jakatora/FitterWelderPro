# Backend Deploy Report — Fitter Welder Pro + PrzetargAI

**Data**: 2026-05-27 (sesja kontynuacji po Night Shift)
**Status**: AI Chat + Stripe Checkout **LIVE w produkcji** ✅

## ✅ Co działa end-to-end

### Backend (Railway)
- Projekt: `adventurous-magic` / Service: `backend`
- URL: https://backend-production-a43e3.up.railway.app
- Deployment ID: `93f68551-580b-44a3-b82e-be75b2dc556b` (commit `b312f8d`)
- Health: `GET /health` → 200 OK

### Stripe (TEST mode)
- Product **"Fitter Welder Pro Monthly"** — `prod_UayvlLjaYPoNXO`
- Product **"Fitter Welder Pro Yearly"** — `prod_UayvthT2UxOuGP`
- Price **monthly 19 PLN/m** — `price_1TbmxyAom97JfF2jzoBZQBIe`
- Price **yearly 149 PLN/y** — `price_1TbmxzAom97JfF2jtqUfZne9`
- Env vars set on Railway: `STRIPE_PRICE_FITTER_MONTHLY`, `STRIPE_PRICE_FITTER_YEARLY`

### Endpointy LIVE (przetestowane przez curl)

#### `POST /api/fitter/billing/checkout`
**Request:**
```json
{"plan":"monthly","device_id":"test-device-12345678"}
```
**Response:**
```json
{"checkout_url":"https://checkout.stripe.com/c/pay/cs_test_b1S8zPW3OPCP2BQM2A470RJzuFQPFKAhGf2tXFMcvRGx6W2..."}
```

#### `POST /api/fitter/ai/chat`
**Request:**
```json
{"message":"Jaki preheat dla P91?","lang":"pl"}
```
**Response (real Claude Haiku 4.5):**
```
# Preheat dla P91

**Minimum 200-300°C** — wymóg bezwzględny, nawet dla tack welds.

## Krótko:
- **Typowo 250°C** (wiele WPS specyfikuje ten zakres).
- **Utrzymywać przez cały weld** — min. 150 mm szerokość od linii spawu...

Citations: [Iteration 74, Iteration 88, ...]
```

### Klient (Fitter Welder Pro APK)
- Build: `build\app\outputs\flutter-apk\app-release.apk` (58.6 MB)
- `BackendConfig.stripeBackendLive = true`
- `BackendConfig.aiBackendLive = true`
- Device ID generator (SharedPreferences cache, 32-char hex)
- Stripe Checkout URL otwierany przez `url_launcher` (externalApplication)
- AI Chat woła `/api/fitter/ai/chat` — citations renderują w UI

## 📁 Pliki backend (commit b312f8d na main)

```
backend/src/
├── config/env.js                # + STRIPE_PRICE_FITTER_MONTHLY/YEARLY
├── services/
│   ├── stripe.js                # + createFitterCheckoutSession()
│   └── fitterAi.js              # NEW: chatFitter() + retrieveSections() RAG
├── routes/
│   ├── fitterBilling.js         # NEW: POST /checkout, GET /success|/cancel
│   └── fitterAi.js              # NEW: POST /chat
├── data/
│   └── piping_knowledge.md      # NEW: 1.2 MB knowledge base (100 iteracji)
└── app.js                       # + mount /api/fitter/billing + /api/fitter/ai
```

## ⚠️ Co JESZCZE NIE działa (do dorobienia)

### 1. Webhook → Premium activation (KRYTYCZNE)

**Problem**: po opłaceniu Stripe Checkout, klient nie wie że ma Premium.
Webhook event `checkout.session.completed` musi:
1. Wykryć `metadata.project=fitter` (już ustawione w createFitterCheckoutSession)
2. Zapisać do nowej tabeli `fitter_premium(device_id, plan, expires_at, stripe_subscription_id)`
3. Klient pyta `GET /api/fitter/billing/status?device_id=X` → otrzymuje active/expires

**Co dorobić**:
- `backend/src/routes/webhooks.js` — dodaj handler dla `checkout.session.completed` + `customer.subscription.deleted` + `customer.subscription.updated` z `metadata.project === 'fitter'`
- `backend/src/db/migrate.js` — nowa tabela `fitter_premium`
- `backend/src/routes/fitterBilling.js` — dodaj `GET /status?device_id=X`
- Klient `PremiumService.refresh()` — periodically poll status, sync z lokalnym `applyStatus()`

### 2. Stripe TEST webhook secret

Backend ma `STRIPE_WEBHOOK_SECRET` ale to **STARY** PrzetargAI webhook secret. Dla nowego Fitter checkout testu potrzebny nowy webhook endpoint w Stripe Dashboard:
- URL: `https://backend-production-a43e3.up.railway.app/webhooks/stripe` (już istniejący endpoint)
- Events: `checkout.session.completed`, `customer.subscription.updated`, `customer.subscription.deleted`
- Wystarczy 1 webhook dla wszystkich projektów (PrzetargAI + Fitter różnicowane przez metadata)

### 3. LIVE mode

Wszystko obecnie w **TEST mode**:
- `STRIPE_SECRET_KEY_TEST` (klucz w env Railway to TEST)
- Price IDs są w TEST mode (`price_1Tbmxy*`, `price_1Tbmxz*`)

Aby przełączyć na LIVE:
1. W vault masz `STRIPE_SECRET_KEY_LIVE` (dodany 2026-05-26)
2. **Wymień klucz Stripe** w Railway: `STRIPE_SECRET_KEY` env var → wartość z `STRIPE_SECRET_KEY_LIVE`
3. Stwórz **LIVE products + prices** w Stripe Dashboard (możesz to zrobić ja przez API z LIVE key)
4. Wymień `STRIPE_PRICE_FITTER_MONTHLY/YEARLY` env vars w Railway na LIVE price IDs
5. Wymień `STRIPE_WEBHOOK_SECRET` na LIVE wartość

### 4. Apple IAP dla iOS

App Store **wymaga** IAP dla subscription. Stripe Checkout w WebView może spowodować odrzucenie apki. Strategia hybrid:
- iOS: subscription przez StoreKit (Apple IAP, 30% fee)
- Android: Stripe Checkout OK (Google Play tolerates)
- Tworzysz tygodnio "Fitter Pro Monthly" + "Yearly" w App Store Connect → IAP products

## 🚀 Do uruchomienia

### W produkcji (gdy będziesz gotowy):
1. Stwórz LIVE Stripe products przez `tools/...` (mogę to zrobić następnym razem, mam LIVE key)
2. Skonfiguruj webhook w Stripe Dashboard → URL → `https://backend-production-a43e3.up.railway.app/webhooks/stripe`
3. Dorób webhook handler + status endpoint (~1h pracy)
4. Zmień env vars Railway na LIVE (~5 min)
5. Rebuild APK (już z flagami live, więc bez zmian w kliencie)

### Test natychmiast:
1. Wgraj APK 58.6 MB na telefon
2. **AI Chat**: Home → PREMIUM → Wypróbuj AI Asystenta → wpisz cokolwiek → real Claude odpowiada z RAG citations z bazy wiedzy 1.2 MB
3. **Stripe Checkout**: Home → PREMIUM → Wybierz plan miesięczny → otwiera się Stripe Checkout w przeglądarce (TEST mode — nie obciąży karty)
4. Po opłacie zobaczysz success page z Fitter Welder Pro branding

## 📊 Statystyki sesji

- **Commits**: 1 (`b312f8d` na PrzetargAI/main)
- **Deployments**: 2 (Railway, ostatni successful = `93f68551`)
- **Stripe objects created**: 4 (2 products + 2 prices)
- **Railway env vars set**: 2 (`STRIPE_PRICE_FITTER_*`)
- **Anthropic API**: working, billing tracked w `ai_usage` DB tabeli
- **Backend kod**: +5 plików, +19,779 linii (1.2 MB z piping_knowledge.md to większość)
- **Klient kod**: 4 zmienione pliki (premium_service, premium_screen, backend_config, pubspec)
- **APK final**: 58.6 MB (Android release, signed)

## 🔑 Co zostało zapamiętane

- `STRIPE_SECRET_KEY_LIVE` w vault (dodany w poprzedniej sesji)
- `STRIPE_PRICE_FITTER_MONTHLY_TEST` + `_YEARLY_TEST` w vault
- Memory: `MEMORY.md` ma teraz sekcję "🔑 KLUCZOWE FAKTY" + reference_external_services.md
