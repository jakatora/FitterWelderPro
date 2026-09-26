# G8 — Przegląd przekrojowy + backend

Data: 2026-09-26. Gałąź `fix/audyt-2026-08-29` (HEAD z 2026-09-25 03:39, 109 commitów od 24.09), backend `backend/` (11 lokalnych commitów, HEAD `c5c4dc8`, niewdrożony).
Tryb: tylko odczyt. Uruchomione lokalnie:

| Sprawdzenie | Wynik |
|---|---|
| `flutter analyze --no-pub` | **No issues found** (29 s) |
| `flutter test --no-pub` | **2089 testów, 0 błędów, 0 pominiętych**, 76 s, 176 plików `*_test.dart` (181 plików `.dart` w `test/`) |
| `npm test` (backend) | **92 testy, 0 błędów**, 11,5 s |
| Flutter SDK | 3.47.5 stable |
| `app-release.aab` z 25.09 | 76,6 MB, z czego 37,9 MB to symbole debug (`BUNDLE-METADATA`), a jedno ABI to ok. 12 MB |

Priorytety: **P1** przed wydaniem albo wdrożeniem, **P2** w najbliższym cyklu, **P3** porządki. Rozmiar: **S** do pół dnia, **M** 1–3 dni, **L** ponad 3 dni.

---

## 1. Warstwa danych (SQLite na telefonie, DAO, kopia zapasowa)

- **Stan:** Solidnie. Schemat `cutlist.db` v22 ma samonaprawę (`_createTables` na początku każdej migracji, `_ensureColumn`). `migration_test.dart` sprawdza każdą ścieżkę vN→v22, idempotencję i bazę bez tabel. Kopia `.zip` przechodzi przez `VACUUM INTO` (z zapasowym checkpointem WAL), przepina ścieżki zdjęć i ma dwufazowe przywracanie: najpierw cały plik, potem zapis. O pominiętych tabelach i kolumnach informuje w raporcie. Usuwanie projektu robi kaskadę ręcznie w transakcji, z „Cofnij”. Zdjęcia wytopów są zmniejszane przy wyborze z aparatu lub galerii.
- **Problemy potwierdzone:**
  - `lib/database/db.dart:77-85`: `openDatabase` bez `onConfigure`, więc w `cutlist.db` **klucze obce są wyłączone** (`segments`, `heat_photos`, `component_heats` deklarują FK, ale nic go nie egzekwuje). Druga baza `lib/data/app_database.dart:23-25` ma `PRAGMA foreign_keys = ON`. Scenariusz: każdy DAO, który usunie projekt inaczej niż `ProjectDao.deleteProjectCascade`, np. `SegmentDao.deleteAllForProject` albo przyszły kod, zostawi sieroty bez błędu.
  - `lib/services/data_backup.dart:1409-1427`: przywracanie idzie **po kolei po dwóch bazach**, każda w osobnej transakcji. Scenariusz: `cutlist.db` zapisze się, a `cut_list_app.db` rzuci wyjątek (brak miejsca, uszkodzony plik modułu) → telefon zostaje z pół nową, pół starą bazą. Zdjęcia są kopiowane wcześniej (`:1401`) i nadpisują pliki o tej samej nazwie.
  - Dwie klasy o nazwie `AppDatabase` (`lib/database/db.dart:8` i `lib/data/app_database.dart:5`), do tego pliki w dwóch katalogach: `getDatabasesPath()` i `getApplicationDocumentsDirectory()`. Wymusza to aliasy importów (`cutlist_db`, `module_db`) i utrudnia wspólną transakcję. `app_database.dart:14-50` nie ma zabezpieczenia przed równoległym otwarciem, jakie ma `db.dart:51-70`.
  - `lib/database/weld_journal_dao.dart:47-56`: `listAll()` pobiera **cały** dziennik: wszystkie wiersze × ok. 70 kolumn (v20: 20 NDT + metadane) plus wszystkie naprawy. Filtr i sortowanie naturalne robi Dart na wątku UI. Przy 5000 spoin to ok. 350 tys. komórek przez kanał platformy przy każdym wejściu i odświeżeniu ekranu. Brak indeksu na `weld_journal(project_id)` i `deleted_at`, choć dziś zapytania i tak skanują całą tabelę.
  - Pozorna synchronizacja ze społecznością, `lib/modules/welder_pipe/community_sync_service.dart:14-21`: `syncOutboxOnce()` oznacza wpisy jako `sent` **bez żadnego żądania sieciowego**. UI `welder_pipe_param_edit_screen.dart:457-461` pokazuje przełącznik „Dodaj do puli 100/100 (społeczność)” z obietnicą zatwierdzenia po 100 osobach. Obietnica nigdy nie zostanie spełniona.
- **Ryzyka:**
  - Brak testu przywracania kopii zrobionej przez **starą wersję aplikacji**, np. plik v17 lub v19 do v22. Dziś testy robią kopię i przywracają ją tą samą wersją, a v22 sprawdzają tylko kolumny. Kolumna `NOT NULL` bez wartości domyślnej dodana w przyszłej wersji wywróci przywrócenie starej kopii.
  - Tabela `weld_journal_history` rośnie o wiersz na każdą zmienioną wartość, np. 5000 spoin × 10 zmian = 50 tys. wierszy. Przy przywracaniu całość ląduje w pamięci (`_readAllTables`).
  - Android Auto Backup: `android:allowBackup` nie jest ustawiony, więc domyślnie `true`. Bazy i SharedPreferences, łącznie z sekretem instalacji, trafiają na Dysk Google użytkownika. Polityka prywatności mówi, że dane „nie opuszczają urządzenia”.
- **Propozycje:**
  - [P2] [S] Usunąć przełącznik „pula 100/100” albo oznaczyć go jako „wkrótce” i nie zapisywać `sent`, dopóki nie ma backendu.
  - [P2] [S] Test w `data_backup_restore_test.dart`: fixture bazy v17 i v19 spakowany jako kopia, przywracany do bieżącej wersji.
  - [P2] [M] Przywracanie „wszystko albo nic” dla obu baz: najpierw przywrócić do plików tymczasowych, potem podmienić pliki po zamknięciu połączeń. Alternatywa: `ATTACH` i jedna transakcja.
  - [P2] [M] Dziennik: projekcja kolumn listy i stronicowanie albo filtr w SQL (`WHERE deleted_at IS NULL AND project_id = ?` z indeksem). Pełny wiersz dopiero w edytorze.
  - [P3] [S] `onConfigure: PRAGMA foreign_keys = ON` w `cutlist.db`. Najpierw jednorazowe sprzątanie sierot w migracji v23, bo inaczej `defer_foreign_keys` przy przywracaniu wywróci COMMIT.
  - [P3] [S] Przemianować `lib/data/app_database.dart` na np. `ModuleDatabase`. Zadecydować o `allowBackup` / `dataExtractionRules`, np. wykluczyć `fitter_install_secret`, i uzgodnić to z polityką.

## 2. Sieć i bezpieczeństwo klienta

- **Stan:** Sekret instalacji to 32 bajty z `Random.secure()` w base64url (`premium_service.dart:225-240`), wysyłany w `X-Install-Secret`. Rejestracja (`registerDeviceIfConsented`, `main.dart:49`) rusza dopiero po zgodzie na zasady czatu i uzupełnionym profilu. Asystent AI pyta o zgodę przed pierwszym pytaniem (`ai_chat_screen.dart:610`), skaner ma własną zgodę (`iso_scan_consent_v1`). Premium przy `kPaidFeaturesEnabled == false` nie wysyła nic na starcie. **Przed zgodą aplikacja nie wysyła żadnych danych** (zweryfikowane w `main.dart` i `chat_service.dart:305-316`). Kody `INSTALL_SECRET_*` są mapowane na komunikaty. Tylko HTTPS, brak cleartext.
- **Problemy potwierdzone:**
  - **Historia asystenta AI bez limitu.** `ai_chat_screen.dart:624` wysyła `List.of(_messages)`, czyli całą rozmowę: powitanie, **bieżące pytanie**, odpowiedzi offline i komunikaty o limicie. `ai_chat_service.dart:133-139` przekazuje to bez przycięcia. Backend przyjmuje najwyżej 20 wpisów po 4000 znaków (`backend/src/routes/fitterAi.js:29-32`). Scenariusz: 11. pytanie w jednej rozmowie daje 22 wpisy → **400** → `offlineReply` (`ai_chat_service.dart:161`). Asystent po cichu „przechodzi w tryb offline” do końca sesji. Poza tym model dostaje bieżące pytanie dwa razy, co podwaja tokeny, oraz „odpowiedzi” offline jako wypowiedzi asystenta. Żaden test (`test/services/ai_chat_request_test.dart`) nie pilnuje tego limitu.
  - **Ponawianie nieidempotentnych POST.** `lib/services/api_client.dart:115-135` ponawia *każde* żądanie, także POST, po `TimeoutException` i po 502/503/504. Scenariusz na budowie ze słabym zasięgiem: `POST /chat/messages` z limitem 8 s (`chat_service.dart:272-281`) dociera, ale odpowiedź się spóźnia → drugi POST → **zdublowana wiadomość w publicznym czacie**. To samo dotyczy `jobs/checkout` (dwa szkice i dwie sesje Stripe) i `billing/checkout`. 503 `AI_BUDGET_EXCEEDED` też jest ponawiane bez sensu.
  - `iso_scanner_screen.dart:571-574` i gałąź `default` przy `IMAGE_REJECTED` (422) pokazują polski `message` z backendu także w interfejsie EN („The server rejected the photo: Wymagane: image_base64…”).
- **Ryzyka:**
  - Squatting TOFU. `device_id` wyciekał przez miesiące (stare `GET /chat/messages`). Kto go zna, rejestruje własny sekret pierwszy, a prawowity użytkownik dostaje 401 na każdym zapisie. „Usuń moje dane” też dostaje 401 (`server_data_deletion.dart:111`). Jedyna droga to ręczny `moderation/reset-secret`. Brak samodzielnej naprawy w aplikacji.
  - Sekret leży w zwykłych SharedPreferences i NSUserDefaults. To akceptowalne (piaskownica aplikacji), ale trafia do kopii OS (patrz sekcja 1).
  - Skaner: limit czasu klienta to 150 s (`iso_scanner_ai.dart:1290`), a serwer nie ma własnego limitu i pozwala na 16 000 tokenów wyjścia z adaptacyjnym myśleniem (sekcja 3). Klient może się poddać, serwer i tak policzy koszt, a użytkownik ponowi.
- **Propozycje:**
  - [P1] [S] Historia AI: wysyłać tylko wpisy `kind == live` oraz pytania użytkownika, **bez bieżącego pytania**, najwyżej 6 ostatnich. Tyle backend i tak bierze (`services/fitterAi.js:269`). Tekst przyciąć do 4000 znaków. Do tego test, że 30 pytań w jednej sesji nadal idzie do serwera.
  - [P2] [S] `ApiClient`: ponawiać POST tylko przy błędzie połączenia *przed* wysłaniem (`SocketException` przy connect) albo gdy wywołujący poda `idempotent: true`. Nie ponawiać 503 z kodem `AI_*`. Opcjonalnie nagłówek `Idempotency-Key` dla czatu i checkoutu, deduplikowany na serwerze.
  - [P2] [S] Przy `INSTALL_SECRET_INVALID` zaproponować „Utwórz nową tożsamość instalacji” (`resetIdentity()` bez `DELETE /me`), z informacją, że stare wiadomości zostaną pod starym podpisem.
  - [P3] [S] Zmapować `IMAGE_REJECTED`, `IMAGE_TOO_LARGE` i `BAD_REQUEST` na teksty PL/EN w `friendlyScanError`.

## 3. Backend (Express 5 + `node:sqlite`)

- **Stan:** Dobry poziom. Walidacja zod na wszystkich trasach. Trwałe liczniki limitów w SQLite, z kluczami HMAC zamiast surowego IP i `device_id`. Bramka budżetu z rezerwacjami żądań w locie; cennik zgodny z aktualnym cennikiem Anthropic (Haiku 4.5: $1/$5, Sonnet 5: $2/$10), a nieznany model jest liczony najdroższą stawką. Duże body skanera jest czytane **po** limiterze IP i sprawdzeniu dziennego limitu. Typ obrazu rozpoznawany po bajtach. Webhook Stripe weryfikuje podpis na surowym body, ma idempotencję po `event.id` w tej samej transakcji, zwraca 500 do ponowienia i zawsze pobiera świeży stan subskrypcji. `DELETE /me` działa w jednej transakcji i zachowuje aktywne Premium. `author_id = HMAC(device_id)`, więc `device_id` nie wycieka. Intencje używają structured outputs i dodatkowo walidacji zod, a pytanie uzupełniające składa serwer. Panel moderacji jest wyłączony bez tokena, token porównywany w stałym czasie. Strony `/privacy` i `/data-deletion` to statyczny HTML PL+EN, zgodny z kodem (brak zapisu treści AI i zdjęć, IP tylko jako HMAC).
- **Problemy potwierdzone:**
  - **Pułapka wdrożeniowa: wolumen przykryje bazę wiedzy.** README (`backend/README.md:230-236`) każe podpiąć wolumen „pod katalogiem” `/app/data`. W tym samym katalogu leży **śledzony w git** `data/piping_knowledge.md` (`src/services/fitterAi.js:24`). Scenariusz: wolumen montowany na `/app/data` → plik znika → `loadIndex()` loguje tylko `warn` (`fitterAi.js:198-204`) → asystent odpowiada **bez RAG**, a `/health` pokazuje „ok”.
  - **Wersja Node.** `package.json:8` ma `"node": ">=22.5.0"`, ale `node:sqlite` bez flagi `--experimental-sqlite` działa dopiero od 22.13. Skrypt `start` tej flagi nie podaje. Scenariusz: Nixpacks lub Railpack wybiera Node 22.5–22.12 → start kończy się błędem `No such built-in module: node:sqlite`. Lokalnie testy przechodzą na Node 24.19.
  - **Ścieżka pieniędzy: druga subskrypcja na tym samym urządzeniu.** `fitterBilling.js:46` blokuje nowy checkout tylko przy `isPremiumActive` (active/trialing). Przy `past_due`, `unpaid`, `incomplete` albo `paused` pozwala założyć drugą subskrypcję. `repos.js:50` robi `ON CONFLICT(device_id)` i **nadpisuje `stripe_subscription_id`**. Pierwsza subskrypcja dalej może pobierać opłaty, a u nas nie ma po niej śladu. Gorzej: zdarzenie starej subskrypcji (np. `updated` → `canceled`) nie znajdzie wiersza po `subscription_id` (`webhooks.js:185-192`) i przez `upsert` po `metadata.device_id` (`webhooks.js:200`) **nadpisze aktywną nową subskrypcję statusem `canceled`**. Płacący traci Premium. Dziś płatności są wyłączone, więc to blokada włączenia płatności.
  - **`limit` ujemny = bez limitu.** `fitterChat.js:105` i `fitterJobs.js:86`: `Math.min(parseInt('-1') || 100, 200)` daje `-1`, a `LIMIT -1` w SQLite oznacza wszystko. Scenariusz: `GET /api/fitter/chat/messages?room=general&limit=-1` zwraca całą historię pokoju w jednej odpowiedzi. 120 takich żądań na minutę z jednego IP to tani DoS pamięci i CPU. To samo `moderation/queue` (`fitterChat.js:222`, tylko dla admina).
  - Moduł Praca: `purgeExpired()` (`repos.js:331`) **nigdy nie jest wywoływany**. Wygasłe ogłoszenia i nieopłacone szkice (z e-mailem i telefonem) zostają na zawsze. `GET /jobs/:id` (`fitterJobs.js:131-135`) zwraca także **nieopłacone szkice** z danymi kontaktowymi. UUIDv4 trudno zgadnąć, ale to niezgodne z zasadą minimalizacji. `stripe_session_id` nigdy nie jest uzupełniany (`:63-65` to martwy kod). `fitterJobs.js:67` loguje surowy `deviceId`, choć reszta kodu tego unika.
  - Skaner a pamięć: body do ok. 10,2 MB, ciąg JSON, regex, `Buffer`, a potem ponowna serializacja przez SDK Anthropic. Przy ok. 5× rozmiarze obrazu na żądanie 20 równoległych skanów z różnych IP to ponad 1 GB → OOM kontenera Railway. Brak limitu równoległości.
  - Skaner nie ma timeoutu po stronie serwera: `anthropicClient.js:9` (`maxRetries: 1`, domyślnie 10 min), `fitterScan.js` (`max_tokens: 16000`, adaptacyjne myślenie). Klient rezygnuje po 150 s, serwer płaci dalej.
- **Ryzyka:**
  - **Limity po IP a IPv6 i CGNAT.** Własne liczniki (`rateLimits.js:102`, `ipKey = req.ip`) liczą pojedynczy adres. Przy IPv6 zmiana adresu w obrębie /64 omija dzienne limity AI (chat 100, skan 30, intent 150 na IP) oraz próg „3 różne IP” przy auto-ukrywaniu w czacie. Działa to też w drugą stronę: brygada na jednym Wi-Fi z budowy albo operator z CGNAT. Czat odpytuje co 8 s (`chat_screen.dart:369`), czyli 7,5 żądania na minutę, więc globalny limit 120/min na IP (`app.js:76-82`) **przepuszcza najwyżej ok. 16 otwartych czatów za jednym IP**. Kolejne osoby dostaną 429. Podobnie 30 skanów dziennie na całą budowę.
  - Pojedyncza replika jest twardym wymogiem (limiter w pamięci, `inFlightUsd`, SQLite). `railway.json` go nie wymusza, a README tylko o nim wspomina. Brak kopii zapasowej `fitter.db`: subskrypcje, sekrety, idempotencja.
  - Budżet AI: domyślnie $500 miesięcznie, próg miękki tylko w logu, bez alertu. Przy obejściu przez IPv6 ktoś może wyczerpać budżet i wyłączyć AI wszystkim do końca miesiąca (503 `AI_BUDGET_EXCEEDED`).
  - Brak obsługi zwrotów i sporów (`charge.refunded`, `charge.dispute.*`): ogłoszenie zostaje opłacone po zwrocie.
  - `ADMIN_TOKEN` bez minimalnej długości (`env.js:108`). Krótki token da się zgadywać w tempie 120 prób na minutę.
  - `/health` ujawnia `env` i `uptime`. `JWT_SECRET` jest wymagany, choć nieużywany (służy tylko jako źródło klucza pseudonimów).
  - Czat bez retencji (polityka: „tak długo, jak istnieje pokój”), a wiadomości są pod imieniem i nazwiskiem. Filtr słów działa na surowym tekście, nick nie jest filtrowany (znaki RTL i zerowej szerokości, podszywanie się pod „Moderator”).
  - Testy: brak testów tras Praca (checkout, szkice, `/:id`), `limit` ujemnego, scenariusza drugiej subskrypcji, obecności bazy wiedzy po starcie i limitu równoległości skanera.
- **Propozycje:**
  - [P1] [S] Przenieść bazę wiedzy poza katalog wolumenu (np. `kb/piping_knowledge.md`) **albo** montować wolumen na `/data` z `DATABASE_PATH=/data/fitter.db`. Przy `NODE_ENV=production` brak bazy wiedzy ma kończyć start błędem, a `/health` ma pokazywać `kb_sections`.
  - [P1] [S] `"engines": {"node": ">=22.13"}` oraz przypięcie Node 24 w Railway (`.node-version` / `NIXPACKS_NODE_VERSION`). Rozważyć Railpack zamiast wycofywanego Nixpacks.
  - [P1] [M] (przed włączeniem płatności, z listą z `money-path-review`) Checkout blokowany dla każdego statusu, który nadal może pobierać opłaty (ten sam zbiór co `BILLING_LIVE` w `dataErasure.js`). Przy odrzuceniu kierować do portalu. `handleFitterSubscription`: `upsert` po `device_id` tylko wtedy, gdy wiersz nie istnieje albo ma tę samą subskrypcję; w innym razie log `error` i alert. Test: stara subskrypcja `canceled` nie nadpisuje nowej `active`.
  - [P2] [S] `limit`: `Math.max(1, Math.min(n, 200))` we wszystkich trasach. Test `limit=-1`.
  - [P2] [S] Semafor skanera (np. 3 w locie → 503 `AI_BUSY`) oraz `client.messages.create(…, { timeout: 120_000 })` krótszy niż 150 s po stronie klienta.
  - [P2] [M] Klucz limitów: dla IPv6 prefiks /64 (tak jak `ipv6Subnet` w `express-rate-limit`). Dla CGNAT i Wi-Fi na budowie: wyższy globalny limit dla `GET /chat/messages` albo osobny limiter na urządzenie z sekretem, a dzienne limity liczone przede wszystkim na **zweryfikowane urządzenie**. Rejestrację nowych urządzeń ograniczyć dodatkowo globalnie na godzinę.
  - [P2] [S] Praca: `purgeExpired()` przy starcie i co godzinę, usuwanie nieopłaconych szkiców po 48 h, `GET /jobs/:id` tylko dla `is_paid = 1 AND expires_at > now`, bez `deviceId` w logu.
  - [P2] [S] Backup `fitter.db`: codzienny `VACUUM INTO` na wolumenie z rotacją 7 dni i włączone backupy wolumenu w Railway. `numReplicas: 1` wpisane w konfigurację deployu.
  - [P3] [S] `ADMIN_TOKEN` min. 32 znaki, `/health` bez `env`, usunięcie wymogu `JWT_SECRET`, retencja czatu (np. 12 mies.) opisana w polityce, normalizacja nicka.

## 4. i18n

- **Stan:** Interfejs jest prawie w całości dwujęzyczny: 2928 wywołań `tr(...)`, a w widżetach zostało ok. 19 literałów z polskimi znakami (głównie symbole i jednostki: `Ø`, `α = … ×10⁻⁶ /°C`). Zmiana języka nie wymaga restartu (`AppLanguageController`). Teksty uprawnień iOS są dwujęzyczne.
- **Problemy potwierdzone:**
  - **Cztery równoległe mechanizmy tłumaczeń:** `context.tr(pl:, en:)` (`lib/i18n/app_language.dart:121`), ręczna mapa `AppLocalizations.translate(key)` (`lib/l10n/app_localizations.dart`, 15 użyć), pliki `lib/l10n/app_{pl,en}.arb`, które **nie są podpięte** (brak `generate: true` w `pubspec.yaml`; w PL brakuje 11 kluczy względem EN), oraz `trL(...)` w module `welder_pipe`.
  - Treści „na sztywno” w obu językach naraz: `coupon_log_export.dart:192` („Brak kuponów. / No coupons.”), `NSPhotoLibraryUsageDescription` tylko po angielsku (`ios/Runner/Info.plist`), a pozostałe opisy uprawnień to PL + EN w jednym ciągu zamiast `InfoPlist.strings` per język.
  - Komunikaty backendu są wyłącznie po polsku i przebijają się do interfejsu EN w skanerze (sekcja 2).
  - Liczby: 517 × `toStringAsFixed`, zawsze z kropką. Separator z preferencji użytkownika działa tylko w `pipe_route_calculator_screen.dart:192`. Daty formatowane ręcznie (`padLeft(2,'0')` w 23 plikach). `intl` jest w zależnościach, ale nieużywany (0 importów w `lib/`).
- **Ryzyka:** Dodanie DE wymaga dopisania trzeciego argumentu w ok. 2900 miejscach albo migracji. Tłumacz nie ma jednego pliku do pracy. EN pisane przez programistę, bez przeglądu native speakera (terminy typu „take-out”, „heat number” są poprawne, ale długie zdania w komunikatach bywają dosłowne).
- **Propozycje:**
  - [P3] [S] Usunąć martwe `.arb` albo je podpiąć. Wygasić `AppLocalizations` (15 kluczy przenieść do `tr`). Ujednolicić `trL` do `tr`.
  - [P3] [S] Formatowanie liczb i dat przez jeden helper oparty na `intl` (`NumberFormat.decimalPattern(locale)`, `DateFormat.yMd`), używany w UI i PDF.
  - [P3] [L] Przygotowanie pod DE: `tr` przyjmuje mapę języków z fallbackiem na EN albo generator ARB z istniejących par `pl`/`en` (skrypt AST), po czym DE jako kolejny plik ARB. Backend zwraca tylko `code`, a tekst wybiera aplikacja (to już prawie tak działa).

## 5. Wydajność i rozmiar

- **Stan:** Start aplikacji czeka tylko na odczyt języka z SharedPreferences (limit 2 s). Baza otwiera się leniwie, a usługi są doładowywane bez `await` (`main.dart:25-80`). Zdjęcia: `pickImage` z `maxWidth`/`imageQuality`, miniatury z `cacheWidth`. Kodowanie JPEG skanu idzie przez `compute` (`iso_scanner_ai.dart:1055`). Dziennik korzysta z `ListView.separated`. Szkicownik ma `RepaintBoundary` i `shouldRepaint` po liczniku wersji. `flutter_assets` w AAB zajmują 0,32 MB (14 MB ikon z `assets/icons` nie trafia do paczki).
- **Problemy potwierdzone:**
  - **PDF dziennika powstaje na wątku UI.** `weld_journal_export.dart:556` (`doc.save()`), podobnie w `hydrotest_export`, `coupon_log_export` i `iso_pdf_export`. W `lib/` nie ma żadnego `Isolate.run`. Test „400 spoin” (`test/services/weld_journal_pdf_render_test.dart:100`) trwa **2,8 s** na desktopowym JIT. Na słabym Androidzie AOT to 1–3 s zamrożonego ekranu bez animacji postępu.
  - `iso_notebook_screen.dart` ma 9238 linii i 12 klas w jednym pliku, a `scan_to_project.dart` 3383 linie. Każdy `setState` (19 w szkicowniku) przebudowuje duże poddrzewa. Utrudnia to przegląd i profilowanie, choć nie jest błędem samo w sobie.
  - AAB 76,6 MB: 37,9 MB symboli debug (Play ich nie pobiera na urządzenia), `lib/` na jedno ABI ok. 12 MB skompresowane (`libapp.so` 13,4 MB i `libflutter.so` ok. 12 MB po rozpakowaniu). `libsqlite3.so` z `sqlite3_flutter_libs` (ok. 0,8 MB na ABI) jest dołączony na Androidzie, choć telefon używa systemowego SQLite przez `sqflite` (`lib/data/db_bootstrap_io.dart`). `proguard-rules.pro` trzyma całe `androidx.lifecycle.**`.
  - Dziennik przy 5000 spoin (sekcja 1): pełne ładowanie i sortowanie na wątku UI.
- **Ryzyka:** Rozmiar do pobrania z Play (ok. 13–15 MB na urządzenie) jest akceptowalny. `x86_64` w AAB nie szkodzi, bo Play dzieli paczkę. Na iOS brak odchudzenia symboli nie ma znaczenia. Czat odpytujący serwer co 8 s zużywa baterię (jest heartbeat 30 s w tle, więc w porządku).
- **Propozycje:**
  - [P2] [M] Budowa PDF w `Isolate.run`: przekazać rekordy jako proste struktury i bajty fontów, zwrócić `Uint8List`, a w UI pokazać wskaźnik postępu. Test wydajności z budżetem czasu dla 400 spoin, np. poniżej 3 s w CI jako alarm, nie twardy próg.
  - [P3] [M] Podzielić `iso_notebook_screen.dart` na kontroler (`ChangeNotifier`), malarz i panele. Użyć `ValueListenableBuilder` przy często zmienianych polach.
  - [P3] [S] Przenieść `sqlite3_flutter_libs` do buildów desktopowych albo świadomie użyć go także na Androidzie, żeby mieć stały SQLite z `VACUUM INTO`. Obecny stan łączy wady obu podejść. Zawęzić `-keep` w R8.

## 6. Budowanie i wydanie

- **Stan:** `targetSdk`/`compileSdk` 36, R8 z `isShrinkResources`, desugaring, `POST_NOTIFICATIONS` i `RECEIVE_BOOT_COMPLETED` dla przypomnień o uprawnieniach. Reguły keep dla `flutter_local_notifications` (Gson) są uzasadnione. iOS 13, `PrivacyInfo.xcprivacy`, `ITSAppUsesNonExemptEncryption=false`. Codemagic przypięty do Fluttera 3.47.5, z numerem builda z licznika. GitHub `checks.yml` uruchamia `analyze` i `test` na każdym pushu.
- **Problemy potwierdzone:**
  - **Toolchain Androida stoi dokładnie na progach błędu Fluttera 3.47.** `flutter_tools/.../DependencyVersionChecker.kt:94-109`: błąd przy Gradle < 8.14, AGP < 8.11.1, KGP < 2.2.20; ostrzeżenie przy Gradle < 9.1.0, AGP < 9.0.1, KGP < 2.3.20. Projekt ma Gradle 8.14, AGP 8.11.1 i Kotlin 2.2.20 (`android/settings.gradle.kts:22-23`, `gradle-wrapper.properties`). Scenariusz: najbliższy stabilny Flutter podniesie minima i build się nie złoży.
  - **Wydanie podpisane kluczem debug jako cichy fallback.** `android/app/build.gradle.kts` (`release { signingConfig = … else getByName("debug") }`). Bez `key.properties` powstaje „release” AAB z kluczem debug, który Play odrzuci, a w najgorszym razie trafi do testów wewnętrznych pod złą sygnaturą.
  - Zależności w tyle: `share_plus` 10.1.4 (w cache jest 13.3.0), `file_picker` 8.3.7, `flutter_local_notifications` 21.0.0 (dostępna 22.3.x), `sqlite3 >=2.7 <3`. Aktualizacje major trzeba robić świadomie i z testami na urządzeniu.
  - Codemagic: `xcode: latest` (`codemagic.yaml:14`) daje niedeterministyczne buildy. W workflow nie ma `flutter analyze` ani `flutter test` przed IPA. `fetch-signing-files --create` może trafić na limit certyfikatów (409).
  - `.github/workflows/ios-app-store.yml` (macOS + fastlane) dubluje Codemagic, a zasada w projekcie mówi, że iOS buduje się tylko przez Codemagic.
  - W repo są śledzone `android/app/google-services.json` (Firebase nieużywany, brak w `pubspec.yaml`) i `testwrite.tmp`. `upload-keystore.jks` leży w katalogu projektu (poprawnie w `.gitignore`).
  - Web: `web/sqlite3.wasm` jest obecny, ale druga baza i kopia zapasowa używają `path_provider` i `dart:io`, które w przeglądarce rzucą wyjątek. Build webowy i Windows nie są sprawdzane w CI.
- **Ryzyka:** CI nie buduje Androida, więc błąd R8 lub Gradle wyjdzie dopiero przy wydaniu. Brak testu backendu w CI (osobne repo). `analyze` bez `--fatal-infos`, choć dziś nie ma żadnych uwag.
- **Propozycje:**
  - [P2] [S] Podbić AGP ≥ 9.0.1, Gradle ≥ 9.1 i KGP ≥ 2.3.20 (z flagami migratora `builtInKotlin` i `newDsl`), potem pełny `flutter build appbundle` i test na urządzeniu (powiadomienia po restarcie, mikrofon, aparat).
  - [P2] [S] Release bez `key.properties` ma kończyć build błędem (`throw GradleException`), a nie cicho brać klucz debug.
  - [P2] [S] CI: job `flutter build appbundle --debug` lub `apk --release` bez podpisu na Ubuntu, `--fatal-infos` w `analyze`, osobny workflow `npm test` w repo backendu. Codemagic: przypiąć wersję Xcode, dodać krok `flutter test`, usunąć `--create` po pierwszym udanym buildzie.
  - [P3] [S] Usunąć `ios-app-store.yml`, `google-services.json` i `testwrite.tmp` z repo. `NSPhotoLibraryUsageDescription` przez `InfoPlist.strings` (pl/en).
  - [P3] [M] Aktualizacje major (`share_plus`, `file_picker`, `flutter_local_notifications`) w osobnym PR, z listą zmian API.

## 7. Jakość testów

- **Stan:** Bardzo dobra liczba i szybkość: 2089 testów w 76 s, 0 pominiętych, bez `Future.delayed` ani `sleep`. Warstwa danych ma prawdziwe testy SQLite (migracje, przywracanie kopii na plikach), usługi sieciowe mają `MockClient`, jest test 400 spoin w PDF i testy kontraktu z backendem (sekret, 401, 404 starego backendu). Backend: 92 testy na atrapach Anthropic i Stripe, bez sieci.
- **Problemy potwierdzone:**
  - **Kruchość tekstowa:** 589 × `find.text` i 250 × `find.textContaining`, z czego co najmniej 176 z polskimi znakami. Mało kluczy: 75 × `find.byKey`. Każda poprawka copy albo tłumaczenia zmienia wynik testów.
  - **Testy czytające kod źródłowy:** 10 plików. Przykład: `test/audit/data_integrity_audit_test.dart:373-380` sprawdza, że `projects_screen.dart` *zawiera* `'await _dao.deleteProjectCascade(p.id)'` i polskie zdanie „użyć „Cofnij” przez 6 sekund”. Refaktor bez zmiany zachowania czerwieni test. Podobnie `module_manifest_test`, `help_texts_test` i `contrast_test`.
  - Brak testów krytycznych ścieżek: limit historii asystenta (sekcja 2), brak ponawiania POST w `ApiClient`, przywracanie kopii ze *starej* wersji, przerwane przywracanie przy dwóch bazach, `listAll` przy 5000 spoin. Po stronie backendu brakuje testów wymienionych w sekcji 3.
  - Brak testów integracyjnych na urządzeniu (`integration_test/`). `test_driver/app.dart` to tylko szkielet. Systemowy SQLite Androida (brak `VACUUM INTO` w starych wersjach), `speech_to_text`, powiadomienia i FileProvider nie są nigdzie sprawdzane automatycznie.
- **Ryzyka:** Najwolniejsze pliki (`module_smoke_test` 16 s, `quick_converter_test` 16 s, `saddle_cut_test` 14 s) nie są problemem dziś. Przy tempie ok. 100 commitów na dobę suite może rosnąć szybciej niż jego czytelność. Testy tekstowe dają fałszywe poczucie bezpieczeństwa: sprawdzają obecność napisu, nie zachowanie.
- **Propozycje:**
  - [P2] [S] Dopisać brakujące testy krytyczne: historia AI, idempotencja POST, kopia ze starej wersji, `limit=-1`, druga subskrypcja, obecność bazy wiedzy na starcie.
  - [P3] [M] Zasada dla nowych testów widżetów: `Key` na elementach, których test szuka, a tekst sprawdzany w jednym teście „copy” na ekran. Istniejące testy przepinać przy okazji.
  - [P3] [M] Testy „czytające źródło” zamienić na testy zachowania. Tam, gdzie chodzi o zakaz wzorca, użyć reguły lintera (`custom_lint`) zamiast `contains()` na pliku.
  - [P3] [M] `integration_test` z 3–5 scenariuszami na emulatorze Androida w CI: nowy projekt → cut list → PDF, kopia i przywrócenie, dziennik → PDF.

## 8. Obserwowalność

- **Stan:** Aplikacja nie ma crash reportingu, analityki ani globalnych handlerów (`FlutterError.onError`, `PlatformDispatcher.instance.onError` i `runZonedGuarded` nie występują w `lib/`). Błędy trafiają tylko do `debugPrint`, który w wersji release znika. Backend loguje przez pino (JSON) do Railway, z `audit` bez surowego IP. Polityka prywatności obiecuje: „Nie używamy reklam, analityki, pikseli śledzących ani zewnętrznych SDK marketingowych”.
- **Problemy potwierdzone:**
  - Ciche awarie, których nikt nie zobaczy. Przykłady: asystent przechodzący w tryb offline przez 400 (sekcja 2), pusta baza wiedzy po wdrożeniu (sekcja 3), błąd `setState` po `dispose` w długich ekranach.
  - Próg miękki budżetu AI, błędy zapisu kosztu (`aiBudget.js:98`) i `Nieobsłużony błąd` idą tylko do logu, bez alertu.
- **Ryzyka:** Po premierze jedynym źródłem informacji o awariach są recenzje w sklepie. Dodanie SDK firm trzecich (Crashlytics, Sentry) bez zmiany polityki i Data Safety byłoby z nią sprzeczne. Firebase Analytics całkowicie odpada.
- **Rekomendacja (zgodna z polityką, w kolejności):**
  - [P2] [S] **Lokalny rejestr błędów:** `FlutterError.onError` i `PlatformDispatcher.onError` zapisują ostatnie 50 błędów (typ, stos, wersja aplikacji, ekran; **bez** danych użytkownika, tekstów pytań i ścieżek plików) do pliku w katalogu aplikacji. W Profil → Kontakt przycisk „Wyślij raport błędu” (share sheet lub mailto) z podglądem treści. Zero zmian w polityce, bo użytkownik sam wysyła dane.
  - [P2] [S] **Konsole sklepów bez SDK:** Android vitals (Play Console) i Crashes w App Store Connect / Xcode Organizer. Włączyć przesyłanie symboli do Play: plik `native-debug-symbols` już jest w AAB.
  - [P2] [S] **Backend:** alert z Railway na wzorce `Budżet AI`, `Nieobsłużony błąd`, `Brak piping_knowledge` i `Baza SQLite utworzona od nowa`, UptimeRobot na `/health` (rozszerzonym o `kb_sections` i `db`) oraz dzienny wpis z sumą kosztu AI.
  - [P3] [M] Opcjonalnie później: Sentry (region UE, `sendDefaultPii: false`, `beforeSend` usuwa ścieżki i treści) **tylko za zgodą** w ustawieniach (domyślnie wyłączone), z aktualizacją polityki (sekcja „Raporty awarii”) i Data Safety („Crash logs, opcjonalne”). Ewentualnie własny endpoint `POST /api/fitter/crash` na istniejącym backendzie, z limitem na urządzenie. To spójniejsze z obecną polityką niż SDK zewnętrzne.

---

## Top 5

1. **[P1] [S] Asystent AI „gaśnie” po 10 pytaniach.** Klient wysyła całą rozmowę razem z bieżącym pytaniem (`ai_chat_screen.dart:624`, `ai_chat_service.dart:133-139`), backend przyjmuje najwyżej 20 wpisów (`fitterAi.js:29-32`). Efekt: 400, po cichu pomoc offline i podwójne tokeny. Naprawa: wysyłać 6 ostatnich wpisów `live` bez bieżącego pytania i dodać test.
2. **[P1] [S] Dwie pułapki przy wdrożeniu backendu.** Wolumen wg README (`/app/data`) przykryje `data/piping_knowledge.md` i asystent po cichu działa bez RAG. `engines >=22.5` pozwala na Node bez `node:sqlite` bez flagi, co daje crash przy starcie. Naprawa: przenieść bazę wiedzy lub zamontować wolumen na `/data`, przypiąć Node ≥ 22.13 (najlepiej 24), a brak bazy wiedzy ma kończyć start błędem.
3. **[P1 przed włączeniem płatności] [M] Druga subskrypcja nadpisuje pierwszą.** Checkout blokuje tylko `active`/`trialing` (`fitterBilling.js:46`), `upsert ON CONFLICT(device_id)` (`repos.js:50`), a zdarzenie starej subskrypcji może ustawić `canceled` na nowej, opłaconej (`webhooks.js:185-209`). Opłaty mogą iść bez śladu albo płacący traci Premium.
4. **[P2] [M] Limity i nadużycia.** `limit=-1` zwraca całą tabelę (`fitterChat.js:105`, `fitterJobs.js:86`). Skaner nie ma limitu równoległości (ryzyko OOM) ani timeoutu serwera krótszego niż 150 s klienta. Limity po pojedynczym IP łatwo obejść przez IPv6 (wyczerpanie budżetu AI, uciszanie w czacie), a jednocześnie blokują brygadę na jednym Wi-Fi (ok. 16 czatów na IP przy odpytywaniu co 8 s). `ApiClient` ponawia POST po timeoucie, co dubluje wiadomości w czacie (`api_client.dart:115-135`).
5. **[P2] [S] Build Androida na granicy.** Gradle 8.14, AGP 8.11.1 i Kotlin 2.2.20 to dokładnie minima błędu w Flutterze 3.47 (ostrzeżenie od 9.1 / 9.0.1 / 2.3.20), więc najbliższy upgrade Fluttera zepsuje build. Do tego release bez `key.properties` po cichu podpisuje się kluczem debug. CI nie buduje Androida.

Następne w kolejce: pozorna synchronizacja „pula 100/100” (sekcja 1), PDF na wątku UI (2,8 s dla 400 spoin w teście), przywracanie kopii nieatomowe między dwiema bazami, brak jakiegokolwiek rejestru błędów w aplikacji i brak kopii zapasowej `fitter.db` na serwerze.
