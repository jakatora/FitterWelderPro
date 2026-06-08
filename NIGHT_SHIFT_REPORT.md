# Night Shift Report — co zostało zrobione

**Data**: 2026-05-26 (nocna sesja)
**Build**: `build\app\outputs\flutter-apk\app-release.apk` (57.6 MB)
**Status**: `flutter analyze` 0 issues. APK podpisany kluczem release.

## 🎯 TL;DR

1. ✅ **Zeszyt ISO** — auto-wstawianie kolanka 90° gdy 2 rury spotykają się pod kątem, wymiary wpisywane na końcu z jednego ekranu.
2. ✅ **Moduł Praca** — pełen lokalny MVP: lista, dodawanie, edycja, usuwanie, filtrowanie po lokalizacji, 12 quick-pick tagów kwalifikacji.
3. ✅ **Premium + AI + Chat backend stubs** — kod gotowy, podpina się po jednym flag flip w `lib/config/backend_config.dart`.
4. ✅ **Mojibake** — 1200+ zepsutych znaków polskich + emoji naprawione w 14 plikach (skrypty w `tools/`).

## 🧪 CO PRZETESTOWAĆ NA TELEFONIE

Zainstaluj nowy APK i sprawdź:

### Zeszyt ISO (najważniejsze życzenie)
1. **FITTER → Zeszyt ISO**
2. Wybierz narzędzie **"Rura"** (na dolnej palecie)
3. Narysuj **dwie rury które spotykają się na rogu** (np. pierwsza poziomo, druga w górę-prawo) — przeciągnij palec na ekranie
4. ✨ **Aplikacja sama wstawi kolanko 90°** w punkcie połączenia, w odpowiedniej orientacji izometrycznej
5. Po narysowaniu całej trasy kliknij ikonę **`linijka`** (Wymiary) na pasku akcji
6. Wpisz wymiary dla wszystkich segmentów naraz w bottom sheet → **Zapisz wszystkie**
7. Sprawdź że stary flow nadal działa — tap pojedynczej rury otwiera dialog wymiaru (na wypadek gdyby user chciał wpisać jeden po drugim)

### Moduł Praca
1. **Home → PRACA** (czerwony kafelek — już nie pokazuje "WKRÓTCE")
2. **FAB "Dodaj"** lub ikona `+` w app bar
3. Wypełnij ogłoszenie:
   - Tytuł: "Spawacz TIG 141 — rurociągi SS"
   - Firma, lokalizacja, stawka (opcjonalnie)
   - Klik na quick-pick chip kwalifikacji (np. "TIG 141", "6G", "NACE MR0175") → dorzucają się do listy
   - Opis stanowiska
   - Email/telefon kontaktowy
   - Wybierz czas publikacji (7/14/30/60 dni)
   - **Opublikuj**
4. W liście pojawi się świeżo dodane ogłoszenie
5. Filtruj po lokalizacji (np. wpisz "Płock") — lista się przefiltruje
6. Tap na ogłoszenie → szczegóły + Edit / Delete

### Help v2 z search
1. **Home → POMOC**
2. Search bar na górze — wpisz np. `nace`, `preheat p91`, `purge`
3. Filter chips per kategoria (13 kategorii, 50+ entries)
4. Tap entry → rozwinięcie + highlight zaznaczonych terminów

### Bolt Torque PRO
1. **FITTER → Moment śrub**
2. Wybierz wielkość (np. 5/8"), grade (B7), smar (Cu anti-seize), preload slider
3. Wynik w N·m + ft·lb + krok-po-kroku ASME PCC-1
4. "Kopiuj" przepuszcza do schowka

### Heat Input + CE PRO
1. **SPAWACZ → Heat Input + CE**
2. Tab 1: wpisz V/I/travel speed + WPS range → **kolor karty** (zielony=OK, czerwony=poza zakresem)
3. Tab 2: wpisz chemię stali (C, Mn, Cr...) + grubość → **rekomendacja preheat** z severity coloring

### Saddle / Coping PDF
1. **FITTER → Saddle / Coping**
2. Wpisz header OD (np. 114.3), branch OD (60.3), kąt 90°
3. Preview profilu cięcia
4. **Eksportuj szablon PDF** → otwiera share sheet
5. PDF ma 3 sekcje: tabela offsetów co 15°, scaled preview, **strony 1:1 do druku + owinięcia na rurze**

### AI Chat (Premium DEMO)
1. **Home → PREMIUM → Wypróbuj AI Asystenta** (gold hero button)
2. Wpisz: `preheat p91`, `nace`, `torque`, `purge`, `saddle` lub `heat input`
3. AI odpowiada z demo bazy (Phase 5b podmieni na Claude Haiku 4.5)
4. Klik na sugestię → wypełnia się w polu

## 🔧 INSTRUKCJA: CO MUSZĘ SAM ZROBIĆ

Wszystkie 3 backend-heavy moduły są **gotowe od strony klienta**. Brakuje tylko:

### Plik kontroli flag — [`lib/config/backend_config.dart`](lib/config/backend_config.dart)

```dart
static const bool stripeBackendLive = false;  // → true po wdrożeniu Stripe webhook
static const bool aiBackendLive = false;      // → true po wdrożeniu AI Chat endpoint
static const bool jobsBackendLive = false;    // → true po wdrożeniu Firestore sync
static const bool chatBackendLive = false;    // → true po wdrożeniu Firestore chat
```

### Phase 4b: Stripe Checkout (subscription Premium)

**Wymagane backend endpoints** (na Twoim Railway, dorób w PrzetargAI backend):

#### `POST /api/fitter/billing/checkout`
**Request:**
```json
{
  "plan_id": "fitter_pro_monthly_19pln",  // lub "fitter_pro_yearly_149pln"
  "user_id": "firebase-uid-optional",
  "success_url": "fitterwelder://premium/success",
  "cancel_url": "fitterwelder://premium/cancel"
}
```
**Response:**
```json
{
  "checkout_url": "https://checkout.stripe.com/c/pay/cs_xxxxx"
}
```

**Implementacja serwera:**
1. Stwórz w Stripe Dashboard 2 Products:
   - "Fitter Pro Monthly" — Price 19 PLN/month, recurring
   - "Fitter Pro Yearly" — Price 149 PLN/year, recurring
2. Skopiuj Price ID-y (`price_xxx`) do env vars: `STRIPE_PRICE_MONTHLY`, `STRIPE_PRICE_YEARLY`
3. Endpoint mapuje `plan_id` na Price ID i tworzy Checkout Session przez Stripe SDK
4. Zwraca `checkout_url`

#### Webhook `POST /api/fitter/billing/webhook`
- Subscribe na zdarzenia: `checkout.session.completed`, `customer.subscription.updated`, `customer.subscription.deleted`
- W Firestore zapisz dla `user_id`: `plan`, `expires_at`, `stripe_customer_id`

#### `POST /api/fitter/billing/portal`
- Tworzy Stripe Customer Portal Session dla `user_id`
- Zwraca `portal_url`

**Klient po deploy:**
1. Dodaj `url_launcher: ^6.3.0` do `pubspec.yaml`
2. W `premium_screen.dart` zamień `SnackBar` z URL na `await launchUrl(Uri.parse(url))`
3. Zmień `stripeBackendLive = true` w `backend_config.dart`

### Phase 5b: AI Chat (Claude Haiku 4.5 + RAG)

**Wymagane backend endpoint:**

#### `POST /api/fitter/ai/chat`
**Request:**
```json
{
  "message": "Jaki preheat dla P91?",
  "history": [
    {"role": "user", "text": "..."},
    {"role": "assistant", "text": "..."}
  ],
  "lang": "pl"
}
```
**Response:**
```json
{
  "text": "P91 preheat 200-300°C (mandatory)...",
  "citations": ["Iteration 75 — P91/P22 alloy welding"]
}
```

**Implementacja serwera (na Railway):**
1. Anthropic API key: ustaw `ANTHROPIC_API_KEY` w env vars Railway (klucz w `C:\Users\Startklaar\.api-keys\keys.env`)
2. Załaduj `docs/piping_knowledge.md` (270 KB, 100 iteracji wiedzy) do retrievera:
   - **Prosty MVP**: split po nagłówkach `## Iteration N`, w runtime dla każdego query → keyword grep top-3 sekcje → wstaw jako context
   - **Lepsze**: embeddings + vector search (Pinecone / Qdrant / pgvector)
3. Każde query: retrieval → wstaw top-3 chunks jako system prompt → wywołaj Claude Haiku 4.5 z user message
4. Wyciągnij citations z którego chunka odpowiedź pochodzi

**Pseudokod (Python FastAPI lub Node):**
```python
@app.post("/api/fitter/ai/chat")
async def chat(req: ChatRequest):
    chunks = retrieve_chunks(req.message, top_k=3)  # z piping_knowledge.md
    system_prompt = "Jesteś AI asystentem fitter/welder. Odpowiadaj z poniższych sekcji bazy:\n" + "\n".join(chunks)
    response = anthropic.messages.create(
        model="claude-haiku-4-5-20251001",
        system=system_prompt,
        messages=[*req.history, {"role": "user", "content": req.message}],
    )
    return {"text": response.content[0].text, "citations": [c.title for c in chunks]}
```

**Klient po deploy:** zmień `aiBackendLive = true` w `backend_config.dart`. Nic więcej.

### Phase 6b: Praca z Firestore + Stripe one-time boost

**Wymagane:**
1. Firestore collection `job_listings/{listing_id}` ze schema jak [`models/job_listing.dart`](lib/models/job_listing.dart)
2. Cloud Function która odpala się gdy stworzony nowy listing (dla notyfikacji)
3. Endpoint `POST /api/fitter/jobs/boost`:
   - Request: `{listing_id, boost_plan: "job_boost_7d_19pln" | "job_boost_30d_49pln", user_id}`
   - Response: `{checkout_url}` (Stripe one-time payment)
   - Webhook flipuje `is_paid: true` w Firestore dla listing_id
4. W kliencie: `JobListingDao` zamień implementację (zostaw same interfejs, podmień under-the-hood SQLite → Firestore + lokalny cache)

### Phase 7b: Chat user-to-user

**Wymagane:**
1. Firebase Auth — user musi być zalogowany żeby wchodzić w czat
2. Firestore collections:
   - `chat_rooms/{room_id}`: members[2], lastMessageAt, lastMessageText
   - `chat_rooms/{room_id}/messages/{message_id}`: senderId, text, timestamp, attachments[]
3. Cloud Function dla moderacji: AI screening nowych wiadomości (Anthropic content filter lub własny model). Flag → ukryj + powiadom moderatora.
4. Firebase Cloud Messaging dla push notifications
5. UI: lista rozmów + chat screen z bubbles (jak `ai_chat_screen.dart` — można reuse design)

## 📁 NOWE PLIKI W TEJ SESJI

```
lib/
├── config/
│   └── backend_config.dart          # NEW: feature flags + endpoint URLs
├── data/
│   └── help_entries.dart            # 13 kategorii × 50+ entries Help v2
├── database/
│   └── job_listing_dao.dart         # NEW: SQLite DAO dla Praca
├── models/
│   └── job_listing.dart             # NEW: model ogłoszenia
├── screens/
│   ├── ai_chat_screen.dart          # AI Chat (Premium) z demo + HTTP gotowe
│   ├── bolt_torque_screen.dart      # Moment śrub PRO
│   ├── chat_screen.dart             # User chat placeholder (gated chatBackendLive)
│   ├── heat_input_screen.dart       # Heat Input + CE/Preheat PRO
│   ├── help_screen.dart             # Help v2 z search + highlight
│   ├── job_add_screen.dart          # NEW: formularz ogłoszenia
│   ├── jobs_screen.dart             # NEW: lista + filtrowanie + detail
│   ├── premium_screen.dart          # Paywall + AI hero button + Stripe checkout call
│   └── saddle_template_screen.dart  # Saddle / Coping PDF generator
├── services/
│   ├── ai_chat_service.dart         # AI service: demo + real HTTP po aiBackendLive
│   ├── help_search.dart             # Fuzzy search z PL→ASCII normalizacją
│   ├── premium_service.dart         # Singleton + Stripe checkout HTTP
│   └── saddle_template.dart         # Saddle geometry + PDF generator
└── widgets/
    └── premium_gate.dart            # PremiumGate + PremiumLockTile

tools/
├── fix_polish_encoding.ps1          # NEW: skrypt naprawy mojibake Win-1252
└── fix_emoji_dashes.ps1             # NEW: drugi pass dla emoji + em-dash

NIGHT_SHIFT_REPORT.md                # ten plik
```

**Zmodyfikowane** (oprócz mojibake): `home_screen.dart` (6 nowych kafelków + badge), `fitter_menu_screen.dart` (+ 2 PRO tile), `welder_menu_screen.dart` (+ 1 PRO tile), `iso_notebook_screen.dart` (auto-elbow + Wymiary button + DimensionsSheet).

## 🧹 SPRZĄTANIE NA POTEM

- Niektóre pliki mają jeszcze `// â”€â”€â”€` w komentarzach (box-drawing mojibake). Bez wpływu na runtime, do kosmetycznego pucu.
- 2 stare emoji mojibake w `home_screen.dart` (`Witaj, Spawaczu 👷`) — naprawione ręcznie.
- W `welder_tools_screen.dart` jest stary tab "Heat Input" — nowy `heat_input_screen.dart` jest osobny, bardziej rozbudowany. Zostaje oba, można w przyszłości zdecydować czy konsolidować.

## 🚀 NASTĘPNE KROKI

**Mała robota (Twoja, ~10 minut)**:
1. Wgraj APK na telefon, przetestuj listę powyżej (10 minut)
2. Sprawdź czy emoji 👷 i polskie znaki wyświetlają się prawidłowo wszędzie
3. Jeśli zauważysz mojibake w nowych miejscach — uruchom `powershell -ExecutionPolicy Bypass -File tools\fix_polish_encoding.ps1` (idempotentny)

**Średnia robota (~1-2h każda faza)**:
4. Phase 4b — dorób Stripe endpoint w Railway backend PrzetargAI (jest tam już Stripe webhook dla PrzetargAI, możesz reuse logikę)
5. Phase 5b — dorób AI Chat endpoint (najprostsze MVP: keyword search bez embeddings)
6. Po obu — flip flagi w `backend_config.dart`, rebuild APK

**Większa robota (~1 dzień każda)**:
7. Phase 6b — Firestore sync dla ogłoszeń + Stripe boost
8. Phase 7b — Chat user-to-user z moderacją

Wszystkie 4 fazy są **niezależne** — możesz je włączać po kolei, apka działa bez przerwy.

---

🌙 Idź jeszcze spać, rano przetestuj, daj znać czy coś poprawić.
