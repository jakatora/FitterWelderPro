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

1. **Kopia bazy.** Pobrać `fitter.db` z wolumenu (migracja v2 uruchomi się sama).
2. **Wolumen.** Sprawdzić, że SQLite leży na podpiętym wolumenie
   (`DATABASE_PATH` wskazuje w wolumen). Bez tego każdy deploy kasuje czat,
   Premium, sekrety instalacji i licznik kosztów AI.
3. **Zmienne (przed pierwszym deployem):**
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
   - **klucz Anthropic osobny dla Fittera** (albo limit wydatków w konsoli
     Anthropic) — budżet w backendzie liczy tylko ten serwer.
   Po deployu: jeden próbny skan prawdziwego rysunku i jedno pytanie do
   asystenta (schemat JSON intencji nie był sprawdzony na żywym API).
4. **Jedna replika** (limity i rezerwacje budżetu są w pamięci procesu).
5. **Deploy**, potem sprawdzić:
   - `GET /health` → 200
   - `GET /privacy` i `GET /data-deletion` → 200 (to są adresy dla sklepów)
   - `GET /api/fitter/chat/moderation/queue` bez tokena → 401
   - w logach różne skróty IP dla różnych klientów (potwierdza `TRUST_PROXY_HOPS`).
6. **Wyczyścić czat przed recenzją Apple** (dziś w pokoju „Ogólny” są wulgaryzmy
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
   (`flutter` z PATH to stara 3.38 i nie zbuduje). Keystore: `upload-keystore.jks`
   + `android/key.properties` (poza gitem).
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
