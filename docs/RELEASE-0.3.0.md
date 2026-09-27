# Wydanie 0.3.0 — co zostało do zrobienia ręcznie

Stan na 2026-09-25. Kod jest na gałęzi `fix/audyt-2026-08-29` (lokalnie), backend
w `backend/` (osobne repo `jakatora/fitter-welder-pro-backend`, lokalnie). Każdy
krok niżej wymaga dostępu, którego sesja z Claude nie ma (push, Railway, konsole
sklepów, telefon z Androidem). Kolejność ma znaczenie.

## 1. Wypchnąć kod

```bash
cd D:/projekty/FitterWelderPro
git push -u origin fix/audyt-2026-08-29
cd backend
git push origin HEAD
```

Token GitHub musi mieć **Contents: Read and write** dla obu repozytoriów.
Po pushu `checks.yml` (Flutter 3.47.5) powinien być zielony.

## 2. Wdrożyć backend (Railway, dedykowany projekt Fittera)

Backend jest zgodny wstecz: aplikacja 0.2.0 ze sklepów dalej czyta i pisze na
czacie. Dlatego backend idzie **przed** aplikacją.

1. **Kopia bazy.** Pobrać `fitter.db` z wolumenu (migracje v2 i v3 uruchomią
   się same; v3 przebudowuje `fitter_premium` na wiersz na subskrypcję i
   dokłada tabele `fitter_idempotency` i `fitter_checkout_pending`).
2. **Wolumen na `/data`, NIE na `/app/data`.** `railway.json` ma
   `requiredMountPath: "/data"` — deploy bez wolumenu na `/data` się nie
   uruchomi. Ustawić `DATABASE_PATH=/data/fitter.db`. Jeśli dziś baza leży
   w `/app/data/fitter.db` na wolumenie zamontowanym na `/app/data`: najpierw
   pobrać kopię, przemontować wolumen na `/data` i przenieść plik
   (`fitter.db` + ewentualne `-wal`/`-shm`) do `/data`. Wolumen na
   `/app/data` przykrywa bazę wiedzy asystenta `data/piping_knowledge.md` —
   od tej wersji serwer **nie wystartuje** bez niej (wcześniej asystent po
   cichu odpowiadał bez wiedzy). Bez wolumenu każdy deploy kasuje czat,
   Premium, sekrety instalacji i licznik kosztów AI.
3. **Node i builder.** `railway.json` przełącza builder na **Railpack**
   (Nixpacks jest wycofywany), Node z `engines.node = "24"` (+ `.nvmrc`).
   `node:sqlite` bez flagi działa od Node 22.13 — starszy Node wywraca start.
   Jeśli w usłudze ustawiono ręcznie `NIXPACKS_NODE_VERSION` albo builder
   w panelu — usunąć, żeby wygrał `railway.json`.
4. **Zmienne (przed pierwszym deployem):**
   - `PSEUDONYM_SECRET` — `openssl rand -hex 32`; **ustawić raz i nigdy nie zmieniać**
     (zmiana = inne `author_id` = rozjechane blokady);
   - `ADMIN_TOKEN` — `openssl rand -hex 32` (panel moderacji);
   - `TRUST_PROXY_HOPS=1`;
   - `AI_BUDGET_SOFT_USD` / `AI_BUDGET_HARD_USD` — domyślne 200/500 USD to dużo;
     proponowane np. 20/50;
   - opcjonalnie `AI_SCAN_MODEL` (domyślnie `claude-sonnet-5`);
   - asystent: `AI_CHAT_REQUIRES_PREMIUM=false`, `AI_CHAT_DAILY_PER_DEVICE=20`,
     `AI_INTENT_MODEL=claude-haiku-4-5`, `AI_INTENT_DAILY_PER_DEVICE=50`;
   - skaner: `AI_SCAN_DAILY_PER_DEVICE=10` (aplikacja ma ten sam limit
     w `kAiScanDailyLimitPerDevice` — zmieniać razem);
   - skaner (nowe, domyślne są rozsądne): `AI_SCAN_MAX_CONCURRENT=2`,
     `AI_SCAN_MAX_CONCURRENT_PER_DEVICE=1`, `AI_SCAN_TIMEOUT_MS=120000`
     (musi być krótszy niż 150 s klienta);
   - **klucz Anthropic osobny dla Fittera** (albo limit wydatków w konsoli
     Anthropic) — budżet w backendzie liczy tylko ten serwer.
   Po deployu: jeden próbny skan prawdziwego rysunku i jedno pytanie do
   asystenta (schemat JSON intencji nie był sprawdzony na żywym API).
5. **Jedna replika** — wpisana w `railway.json` (`numReplicas: 1`); limity,
   równoległość skanera i rezerwacje budżetu są w pamięci procesu.
6. **Deploy**, potem sprawdzić:
   - `GET /health` → 200, `"db": true`, `"kb_sections"` > 0 (ok. 330)
   - `GET /privacy` i `GET /data-deletion` → 200 (to są adresy dla sklepów)
   - `GET /api/fitter/chat/moderation/queue` bez tokena → 401
   - w logach różne skróty IP dla różnych klientów (potwierdza `TRUST_PROXY_HOPS`);
   - w logach startu: `Baza wiedzy asystenta OK`, `Migracja bazy zakończona`
     z `version: "3"`, brak `DATABASE_PATH wskazuje katalog aplikacji`.
   Alerty w Railway warto ustawić na wzorce `ALARM: druga płatna subskrypcja`,
   `Start przerwany`, `Budżet AI`, `Nieobsłużony błąd`.
7. **Co zmieniło się w API (zgodne wstecz):** `Idempotency-Key` w
   `POST /chat/messages` i `/chat/report` (powtórka w 24 h = odpowiedź z
   pierwszego zapisu, bez duplikatu); `limit` w listach 1–100; limity po IP
   liczone po sieci (IPv4 / prefiks /64 IPv6); skaner zwraca `503 AI_BUSY`
   przy 2 skanach naraz i `429` przy drugim skanie z tego samego urządzenia;
   `GET /jobs/:id` nie pokazuje nieopłaconych szkiców; `POST /billing/checkout`
   zwraca `409 SUBSCRIPTION_EXISTS` / `409 CHECKOUT_PENDING` (patrz README
   backendu). Sprzątanie wygasłych ogłoszeń, szkiców (> 7 dni) i kluczy
   idempotencji — przy starcie i co godzinę. Nowe: `DELETE
   /chat/messages/:id` (autor usuwa własną wiadomość), `POST
   /chat/moderation/ban` i `/unban` (moderator), filtr treści zgodny
   z aplikacją (żargon „pedał"/„sutki" przechodzi), `/privacy`
   i `/data-deletion` zsynchronizowane z `lib/legal/legal_texts.dart`.
8. **Wyczyścić czat przed recenzją Apple** (dziś w pokoju „Ogólny” są wulgaryzmy
   i śmieci typu „tggyu”): lista przez
   `GET /api/fitter/chat/moderation/queue` / `.../moderation/search?nickname=…`
   z nagłówkiem `x-admin-token`, ukrycie przez
   `POST /api/fitter/chat/moderation/<id>` z `{"hidden": true}`.

## 3. Konsole sklepów

- **App Privacy (App Store Connect) i Data Safety (Play Console)** —
  dokładnie wg `docs/store/deklaracje-prywatnosci.md`.
- **URL polityki prywatności**: `<backend>/privacy`; strona usuwania danych
  (Play): `<backend>/data-deletion`.
- **Metadane i kategoria**: `store/listing-2026-09/` (README mówi, co gdzie
  wkleić). Kategoria: Utilities + Productivity (App Store), Tools (Play).
- **Zrzuty ekranu** są nieaktualne (stary ekran główny) — zrobić nowe z
  telefonu/emulatora; formaty App Store 1242×2688 / 1284×2778.

## 4. Android

1. `pubspec.yaml`: podnieść numer budowania (np. `0.3.0+17` — ostatni
   potwierdzony na Play to vc14; vc15 zbudowany lokalnie, nie wiadomo, czy
   wgrany — wybrać numer wyższy od obu).
2. Build SDK-iem 3.47.5: `C:\Users\Startklaar\flutter\bin\flutter.bat build appbundle`
   (`flutter` z PATH to stara 3.38 i nie zbuduje), z `JAVA_HOME` na JDK 21
   (`C:\Users\Startklaar\.jdks\jdk-21.0.12.1+1`; JBR z Android Studio to
   Java 25 i Gradle się na nim nie uruchomi). Toolchain: Gradle 9.3.1,
   AGP 9.1.0, Kotlin 2.4.0 (wersje z szablonu Fluttera 3.47, powyżej progów
   ostrzeżeń 9.1 / 9.0.1 / 2.3.20). Keystore: `upload-keystore.jks`
   i `android/key.properties` (poza gitem). **Bez `key.properties` build
   release kończy się błędem** (`verifyReleaseSigning`) — nie powstaje już
   „release” podpisany kluczem debug.
3. Ścieżka **testów wewnętrznych**, smoke test na fizycznym telefonie (R8 jest
   włączony i nigdy nie był sprawdzony na urządzeniu):
   - projekt → segment → CUT, lista cięć → PDF (polskie znaki), CSV jako plik;
   - zeszyt ISO: narysować, wyjść, wrócić — szkic jest;
   - zdjęcie wytopu (aparat/galeria), kopia zapasowa → przywrócenie;
   - próba ciśnieniowa → PDF protokołu; dziennik spoin → PDF;
   - czat: zgoda → wiadomość → blokada; Profil → „Usuń moje dane”;
   - rejestr uprawnień: włączenie przypomnień → prośba o zgodę na
     powiadomienia (Android 13+), powiadomienie ma ikonę (R8!);
   - asystent: mikrofon (prośba o zgodę), „Zapisz, że spawam stal nierdzewną,
     ściankę 2 mm, TIG bez drutu na 60 amperach” → podsumowanie → Zapisz →
     Cofnij; tryb „Odpowiedz” (po wdrożeniu backendu);
   - skaner ISO: zdjęcie prawdziwej izometrii → przegląd (zakładki Cięcia /
     Spoiny / Materiały / Spoole) → zapis projektu → „Utwórz wpisy w dzienniku”;
     11. skan tego dnia → komunikat o limicie;
   - timer chłodzenia: start, wyjście z aplikacji → powiadomienie; wibracja
     i komunikat głosowy na koniec; ekran nie gaśnie w trakcie;
   - zdjęcie heat z aparatu (Komponenty i Heat numbers);
   - zeszyt ISO → „Utwórz projekt CUT” → CUT zgodny z zeszytem.
4. Dopiero potem produkcja.

## 5. iOS

Tylko na wyraźne polecenie: Codemagic (sprawdzić billing), workflow
`ios-testflight` — każdy build wysyła do App Store Connect. Flutter w
`codemagic.yaml` przypięty do 3.47.5.

## 6. Decyzje, które czekają na właściciela

- Model zarabiania: płatne pobranie vs darmowa + Pro (IAP/RevenueCat).
- Społeczność: publiczny czat z nazwiskami vs prywatne „brygady”.
- Próg akceptacji przebarwień (3-A: poziom ≥ 4 zwykle odrzut; aplikacja:
  3–4 dopuszczalne w spożywce).
- Kalkulator tandem: czy inside/outside = lead/trail.
- Ekrany-sieroty (TandemMenuScreen, WelderPipeParamsListScreen, RegisterScreen,
  TutorScreen, NewCutListProjectScreen): podpiąć czy zostawić ukryte.
- Skaner ISO: kiedy włączyć (wymaga płatności albo darmowego limitu) i jaki
  domyślny punkt odniesienia przy kołnierzach (dziś skaner każe potwierdzić).
- Raporty awarii / statystyki użycia (Crashlytics/Analytics) — wymagają
  zmiany polityki prywatności i deklaracji w sklepach.
