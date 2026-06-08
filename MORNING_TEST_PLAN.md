# Plan testów rano — Fitter Welder Pro (po deploy 2026-05-27 22:15)

## Co jest LIVE

Backend Railway `https://backend-production-a43e3.up.railway.app`:
- `GET  /api/fitter/billing/status?device_id=X` → JSON `{plan, status, is_active, current_period_end}`
- `POST /api/fitter/billing/checkout` → Stripe Checkout URL (monthly/yearly)
- `GET  /api/fitter/billing/success` → strona "Subskrypcja aktywna"
- `GET  /api/fitter/billing/cancel`  → strona "Płatność anulowana"
- `POST /api/fitter/ai/chat` → Claude Haiku 4.5 z RAG po piping_knowledge.md
- `POST /webhooks/stripe` → przyjmuje `checkout.session.completed`,
  `customer.subscription.updated`, `customer.subscription.deleted`

DB: nowa tabela `fitter_premium` (PK `device_id`, **całkowicie osobna** od `users`
PrzetargAI). Webhook gałęzi po `metadata.project === 'fitter'`.

Stripe TEST mode:
- Produkt "Fitter Welder Pro Monthly" 19 PLN/mc → `price_1TbmxyAom97JfF2jzoBZQBIe`
- Produkt "Fitter Welder Pro Yearly" 149 PLN/rok → `price_1TbmxzAom97JfF2jtqUfZne9`
- Webhook endpoint dodany dla 3 eventów, secret w Railway

APK: `build/app/outputs/flutter-apk/app-release.apk` (58.6 MB).

## Test 1 — Status endpoint (czysty device)

Powinno zwrócić plan=free, is_active=false:
```
curl "https://backend-production-a43e3.up.railway.app/api/fitter/billing/status?device_id=test_nowy_123"
```

## Test 2 — Subskrypcja end-to-end

1. Zainstaluj nowy APK (`adb install -r build/app/outputs/flutter-apk/app-release.apk`).
2. Otwórz apkę → menu Premium.
3. Tap "Miesięczny" lub "Roczny" → otworzy się Stripe Checkout w przeglądarce.
4. Karta testowa: `4242 4242 4242 4242`, dowolna data w przyszłości, dowolne CVC.
5. Po opłaceniu Stripe wyświetli stronę success → wróć do apki (Alt+Tab/swipe).
6. Apka powinna sama złapać status (`AppLifecycleState.resumed` → polling 6× po 2s).
   Powinieneś zobaczyć snackbar "Premium aktywne — dzięki za zakup!".
7. Wróć do menu głównego → sekcje AI Chat / Bolt Torque / itp. powinny być
   odblokowane (PremiumGate nie powinien dolatywać).

## Test 3 — AI Chat

1. W apce: Premium → "Wypróbuj AI Asystenta" (lub po unlocku: AI Asystent).
2. Wpisz np.: "Jaki preheat dla P91 grubość 25 mm?"
3. Odpowiedź powinna wrócić w 2-5s, po polsku, z cytatami z bazy (sekcje
   `Iteration N` / `### LETTER`).

## Test 4 — Polskie znaki

Otwórz każdy ekran z polskim tekstem (Help, Premium, ISO, calculators).
Powinny wyświetlać się poprawnie: ą ć ę ł ń ó ś ź ż. Nie powinno być `Å„`,
`Ä™`, `Ä…` itd.

## Test 5 — Zeszyt ISO (auto-elbow)

1. Zeszyt ISO → nowy rysunek.
2. Narysuj linię poziomą, na końcu drugą pod kątem 90° (np. w dół).
3. Aplikacja powinna **automatycznie wstawić kolanko** w punkcie styku, z
   orientacją dopasowaną do płaszczyzny.
4. Dodaj 2-3 więcej linii.
5. Tap przycisk "Wymiary" → bottom sheet → wprowadź wymiary wszystkich linii
   naraz (nie jeden po jednym jak wcześniej).

## Test 6 — Webhook (zaawansowane)

Po zakupie testowym otwórz Stripe Dashboard → Developers → Webhook attempts.
Dla zdarzenia `checkout.session.completed` powinno być 200. W Railway logs
powinien pojawić się wpis "Fitter Premium activated" z `deviceId` i `plan`.

## Jeśli coś nie działa

- Status zwraca NOT_FOUND → backend padł, sprawdź `railway logs` lub
  zrób `railway redeploy --service backend --yes`.
- Checkout zwraca błąd → sprawdź env vary STRIPE_PRICE_FITTER_MONTHLY/YEARLY
  na Railway (powinny być ustawione w tej sesji).
- AI Chat zwraca generic error → sprawdź czy `ANTHROPIC_API_KEY` jest na
  Railway (powinno być od poprzedniego deployu).
- APK crashuje przy starcie → `flutter clean && flutter build apk --release`.

## Co zostaje do zrobienia

- **Praca (Jobs) module**: backend nie ma jeszcze routes/jobs.js. Wymagałby
  schema (job_listings table), CRUD endpoints, Stripe one-time boost,
  moderation flag. Klient ma `jobs_screen.dart` placeholder.
- **Chat user-to-user**: wymaga Firebase Firestore + push + moderation.
  Klient ma `chat_screen.dart` placeholder z "Coming soon".
- **LIVE mode Stripe**: trzeba utworzyć produkty Fitter w LIVE Stripe i
  zaktualizować Railway env vary z `_TEST` na LIVE wartości.
- **iOS build**: tylko APK dziś. iOS przez Codemagic (`codemagic.yaml` już
  jest, ale workflow `fitter-ios` może wymagać aktualizacji).
