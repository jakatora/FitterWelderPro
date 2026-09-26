# G6 — Nawigacja, konto, społeczność (przegląd 2026-09-26)

Gałąź `fix/audyt-2026-08-29`, stan po commicie `40f254e` (release 0.3.0+17). Przegląd tylko do odczytu, bez zmian w kodzie.

**Zakres:** home, fitter-menu, welder-menu, help, legal, consent, onboarding-name, profile, chat, premium, jobs, job-add, register, tutor oraz części wspólne: `tool_registry.dart`, `tool_tiles.dart`, `community_gate.dart`, `scan_consent_gate.dart`, `lib/i18n/`, `app_theme.dart`, `legal_texts.dart`, `feature_flags.dart`, `chat_service.dart`, `premium_service.dart`, `api_client.dart`.

**Uruchomione testy** (`flutter test --no-pub`):
- `community_trust`, `scanner_flags`, `app_language`, `legal_server_sync`, `legal`, `chat_secured_backend`, `consent_screen`: +152, bez błędów.
- 15 kolejnych plików (onboarding, profile_delete_data, profile_restore_warning, tool_menus, chat_identity, device_identity, premium_status, server_data_deletion, tool_usage, contrast, welder_journey, help_texts, scan_consent_gate, tool_registry, widget_test): **+138, wszystkie przeszły**.
- `home_quick_access_test`: uruchomiony sam przechodzi (+12). W pierwszej, dużej paczce zawiesił się jednak w `tearDownAll` na ponad 6 minut. Mogło to wynikać z obciążenia maszyny przez równoległe agenty. Pewność niska, ale warto to sprawdzić w CI.

---

## home — Ekran główny („FITTER WELDER PRO”)
- **Cel i dla kogo:** start aplikacji dla montera lub spawacza, który chce w kilka sekund dostać się do jednego narzędzia. Od 24.09 nie ma bramki: aplikacja otwiera się od razu na tym ekranie (`root_gate.dart` zwraca `HomeScreen`).
- **Co zawiera:**
  - powitanie imieniem oraz liczniki projektów i segmentów;
  - wyszukiwarkę narzędzi (rejestr, PL i EN naraz, odmiana polska); Enter otwiera pierwszy wynik;
  - przypięte narzędzia (długie przytrzymanie) i „ostatnio używane” (4);
  - kafle działów: MONTER, SPAWACZ, ASYSTENT, CZAT (za bramką), SKANER ISO (gdy `kAiScannerReachable`), PRACA i PREMIUM (ukryte flagami);
  - „Ostatnie projekty” (3) z kartą „Spróbuj tego”;
  - w pasku: tożsamość spawacza, profil, pomoc, język (≥ 48 dp).
  - Pliki: `lib/screens/home_screen.dart`, `lib/widgets/tool_tiles.dart`, `lib/services/tool_usage.dart`.
- **Stan:** działa.
- **Błędy potwierdzone:**
  - `home_screen.dart:401` i `:409`: wejście do menu montera lub spawacza (`_push`) nie odświeża potem licznika ani „Ostatnich projektów”. To samo dotyczy `openTool` z przypiętych i ostatnich (`:238`, `:303`, `:317`). Projekt założony przez Monter → Lista cięć nie pojawia się na ekranie głównym do czasu pociągnięcia w dół. Odświeżają się tylko `_TryThis` (`:370`) i kafel projektu (`:384`).
  - `home_screen.dart:445-447`: nieaktualny komentarz („Skaner stoi za bramką Premium”). Skaner jest dziś darmowy.
  - `home_screen.dart:418-425`: martwa gałąź `_push(AiChatScreen())`. Wpis `assistant` w rejestrze jest zawsze dostępny.
  - `home_screen.dart:109-112`: liczenie segmentów pobiera wszystkie segmenty wszystkich projektów, tylko po to, żeby je policzyć (N zapytań). Przy kilkudziesięciu projektach start zwalnia.
- **Problemy UX / sklepowe:**
  - Wyszukiwarka nie znajduje czatu, profilu, pomocy, tożsamości spawacza ani „usuń dane”, bo tych ekranów nie ma w rejestrze. Monter wpisujący „czat” albo „profil” dostaje „Brak narzędzia”.
  - Kafle działów są WERSALIKAMI (MONTER, CZAT). Rejestr ma zasadę „tytuły zdaniem”, więc to niespójne.
  - Skaner ma dwa wejścia (kafel działu i Monter → Cięcie i projekty). To świadome, ale wymaga ostrożności przy zmianie flag.
  - Cztery ikony w pasku plus tytuł: na 320 dp tytuł mocno się zmniejsza (FittedBox). Można rozważyć przeniesienie tożsamości spawacza do profilu.
  - Dostępność: kafle działów nie mają `Semantics(button: true)`. InkWell daje akcję, ale bez roli „przycisk”.
- **Brakujące funkcje:** wyszukiwarka nie obejmuje ekranów konta (profil, dane, zasady) ani pomocy. Nie ma licznika ani ikonki nowych wiadomości na kaflu CZAT.
- **Testy:**
  - Pokryte (`home_quick_access_test`): start bez bramki, bramka czatu, wyszukiwarka, przypinanie, ostatnio używane, język ≥ 48 dp.
  - Brak testu odświeżenia listy projektów po powrocie z menu.
- **Propozycje:**
  - [P2][S] `.then((_) => _load())` przy wejściach do menu i `openTool` (albo `RouteAware` / `didPopNext`).
  - [P2][S] Wpisy „nawigacyjne” w wyszukiwarce: Czat, Profil, Usuń moje dane, Pomoc, Tożsamość spawacza. Mogą być osobnym typem wpisu, bez ToolGroup.
  - [P3][S] `COUNT(*)` w `SegmentDao` zamiast pobierania list; usunąć martwą gałąź i nieaktualny komentarz.
  - [P3][S] `Semantics(button: true, label: …)` na `_SectionTile`.

## fitter-menu — „Monter”
- **Cel i dla kogo:** pogrupowana lista narzędzi montera.
- **Co zawiera:** `ToolGroupedMenu(section: fitter)`: 6 grup i 21 narzędzi z rejestru (Lista cięć, Zeszyt ISO, Skaner, Biblioteka komponentów, Fazowanie, kolana, siodła, trasa i spadki, tabele, podpory i kołnierze). Pomoc „?” (`kFitterMenuHelp`). Na tablecie dwie kolumny. Pliki: `fitter_menu_screen.dart`, `tool_tiles.dart`, `tool_registry.dart`, `menu_help.dart`.
- **Stan:** działa.
- **Błędy potwierdzone:** brak.
- **Problemy UX / sklepowe:**
  - Przypinanie jest dostępne tylko przez długie przytrzymanie. `Semantics(onLongPressHint)` jest, ale nie ma alternatywy dla osób, które nie wykonają długiego gestu (WCAG 2.5.1). Warto dodać ikonę pinezki albo pozycję w menu kontekstowym.
  - W `ScreenHelp` są kroki z emoji (📋📐). W aplikacji to w porządku, ale nie wolno ich kopiować do metadanych sklepu.
  - Podtytuły są ucięte do jednej linii (`maxLines: 1`). Przy dużej czcionce systemowej część tekstu znika („…”).
- **Brakujące funkcje:** brak filtra lub wyszukiwarki w samym menu. Jest tylko na ekranie głównym.
- **Testy:** pokryte (`tool_menus_test`): kompletność, wiersze ≥ 56 dp, kolejność grup, PL/EN, przypinanie, dwie kolumny na tablecie.
- **Propozycje:**
  - [P3][S] Pinezka jako widoczny `IconButton` w wierszu (≥ 48 dp).
  - [P3][S] `maxLines: 2` dla podtytułu przy `textScaler > 1.3`.

## welder-menu — „Spawacz”
- **Cel i dla kogo:** narzędzia spawacza. Na górze stan uprawnień (WpqrChipLive) i wskazówka „Spróbuj tego”, która prowadzi do checklisty.
- **Co zawiera:** 4 grupy: parametry (rury, zbiorniki, orbital, wolfram, Asystent), kalkulatory (Heat input i CE; Gaz, formowanie i timer), kontrola i dokumentacja (checklista, dziennik, uprawnienia, WPS, kupony, próba ciśnieniowa), wykończenie nierdzewki. Pliki: `welder_menu_screen.dart`, `wpqr_chip.dart`.
- **Stan:** działa.
- **Błędy potwierdzone:** brak.
- **Problemy UX / sklepowe:**
  - Wskazówka „Spróbuj tego” wisi na stałe. Po pierwszym użyciu checklisty zajmuje miejsce. Powinna znikać, gdy `pre_weld_checklist` jest w „ostatnio używanych”.
  - Nazwa klasy i pliku `WpqrChip` zostaje, choć UI mówi o „uprawnieniach spawacza”. To tylko kosmetyka kodu.
  - „Asystent” jest w grupie „Parametry spawania”, a na ekranie głównym ma własny kafel. Dwa wejścia są OK, ale asystent odpowiada też na pytania montera.
- **Brakujące funkcje:** brak.
- **Testy:** pokryte w `tool_menus_test` i `welder_journey_test`. Brak testu, że chip uprawnień otwiera rejestr.
- **Propozycje:**
  - [P3][S] Chować „Spróbuj tego” po pierwszym użyciu checklisty.
  - [P3][S] Test tapnięcia w WpqrChipLive.

## help — „Pomoc” (baza wiedzy)
- **Cel i dla kogo:** techniczna ściągawka dla montera i spawacza (TIG, materiały, PWHT, NDT, kołnierze, podpory, BHP, normy, ISO, obliczenia, naprawy).
- **Co zawiera:** 13 kategorii i 49 haseł PL/EN (`lib/data/help_entries.dart`), wyszukiwarka z opóźnieniem 300 ms, podświetlanie trafień, poziome filtry kategorii, okno „O bazie wiedzy”. Pliki: `help_screen.dart`, `help_search.dart`, `help_entries.dart`.
- **Stan:** działa.
- **Błędy potwierdzone:**
  - `help_screen.dart:152`: rząd filtrów ma `SizedBox(height: 38)`, więc chipy mają cel dotyku 38 dp, poniżej 48 dp. Tekst chipa ma 12 sp, a licznik 10 sp.
  - `help_screen.dart:291`: chip to `GestureDetector` bez `Semantics(button/selected)`. Czytnik ekranu nie wie, że to przełącznik.
  - `help_screen.dart:124`: `IconButton` „wyczyść” bez `tooltip`, więc bez etykiety dostępności.
- **Problemy UX / sklepowe:**
  - „Pomoc” nie tłumaczy samej aplikacji. Brakuje haseł o tym, jak działa czat i zgłaszanie, gdzie usunąć dane, jaki jest limit skanera, co wysyła asystent, jak przypinać narzędzia i jak zrobić kopię. Nie ma też kontaktu (jest tylko w profilu). Apple 1.2 i Google Play oczekują łatwo dostępnego kontaktu.
  - Na ekranie głównym brak wyników kieruje „Szukaj w pomocy”, ale nie przenosi wpisanego słowa do pola wyszukiwania pomocy.
  - Kolory są stałymi w pliku (`_kBg`, `_kCard`…), a nie tokenami z motywu. Wartości są te same, ale migracja nie jest dokończona.
- **Brakujące funkcje:** kategoria „Aplikacja i konto”; przeniesienie zapytania z ekranu głównego; link „Napisz do nas”.
- **Testy:** `help_texts_test` (ScreenHelp), smoke w `audit/module_smoke_test` i wejście z home. Brak testu wyszukiwarki pomocy na widgecie i testu celów dotyku chipów.
- **Propozycje:**
  - [P2][S] Chipy ≥ 48 dp (`ChoiceChip` z `materialTapTargetSize.padded` albo wysokość 48), `Semantics(selected:)`, tooltip dla „wyczyść”.
  - [P2][M] Kategoria „Aplikacja”: czat i zgłaszanie, dane i prywatność, skaner i limit, asystent, kopia zapasowa, kontakt.
  - [P3][S] `HelpScreen(initialQuery:)` z `_NoResults`.

## legal — „Regulamin” / „Polityka prywatności”
- **Cel i dla kogo:** teksty prawne wbudowane w aplikację (działają offline). Wymagane przez Apple 1.2 i 5.1.1 oraz Google Play (UGC, Data safety).
- **Co zawiera:** `LegalScreen` renderuje `LegalDocument` z `legal_texts.dart` (PL/EN): `kLegalVersion = 3`, `kLegalUpdated = 2026-09-25`, `kMinimumAge = 16`. Polityka ma sekcje: telefon, czat, serwer, IP/HMAC, podmioty przetwarzające (Railway, Anthropic), retencja, usuwanie danych, RODO, asystent, skaner, płatności, kontakt. Regulamin: WPS, AI, wiek, zero tolerancji, zgłaszanie i blokowanie, własne nazwisko, dostępność, usunięcie danych, zmiany. Publiczne URL-e: `AppLinks.privacyPolicyUrl` / `dataDeletionUrl` (`/privacy`, `/data-deletion` na backendzie).
- **Stan:** działa. Wersja hostowana zależy od wdrożenia backendu (`app_links.dart:23` mówi, że 24.09 zwracała 404).
- **Błędy potwierdzone (sprzeczności treści):**
  - `legal_texts.dart:75-83`: lista „co zostaje na telefonie … Te dane nie opuszczają urządzenia” obejmuje „imię i nazwisko z profilu”. Dwa akapity niżej (`:88-95`) polityka mówi, że imię i nazwisko wysyłamy z każdą wiadomością. To sprzeczność w jednym dokumencie.
  - `legal_texts.dart:78` („usuwają się razem z odinstalowaniem”) nie zgadza się z `android/app/src/main/AndroidManifest.xml`: brak `android:allowBackup`, więc domyślnie `true`. Auto Backup Androida odtwarza SharedPreferences (profil, zgody, `fitter_device_id` i `fitter_install_secret`) po reinstalacji lub na nowym telefonie. To także klonuje sekret instalacji na drugie urządzenie.
  - `legal_texts.dart:425-433`: regulamin obiecuje, że autorom treści łamiących zasady „odbieramy dostęp”. Backend (`backend/src/routes/fitterChat.js:199-265`) ma tylko ukrywanie wiadomości, reset sekretu i usunięcie danych. Nie ma blokady (bana) urządzenia ani autora.
  - `legal_texts.dart:440` / `consent_screen.dart:175-177` („zgłoszenia rozpatrujemy w 24 godziny”): backend przy zgłoszeniu tylko loguje (`fitterChat.js:187`). Nie ma powiadomienia moderatora (mail, push, webhook), więc 24 h zależy od ręcznego sprawdzania `/moderation/queue`.
- **Problemy UX / sklepowe:**
  - `ios/Runner/PrivacyInfo.xcprivacy`: `NSPrivacyCollectedDataTypes` i `NSPrivacyAccessedAPITypes` są puste. Aplikacja zbiera imię i nazwisko, treści użytkownika (czat), identyfikator urządzenia (device_id), zdjęcia (skaner) i treść pytań (asystent), a używa UserDefaults (shared_preferences, powód CA92.1). Manifest powinien to odzwierciedlać, zgodnie z etykietą App Privacy.
  - Brak linku do regulaminu i polityki bezpośrednio na ekranie czatu. Są w profilu i w bramce zgody, co wystarcza, ale wymaga dwóch kroków.
  - `LegalScreen` to długi tekst bez spisu treści i bez możliwości zaznaczenia (`SelectableText`) ani udostępnienia.
- **Brakujące funkcje:** spis sekcji z kotwicami; zaznaczanie tekstu; link do wersji hostowanej („otwórz w przeglądarce”).
- **Testy:** `legal_test` (filtr, zgoda) i `legal_server_sync_test` (zgodność z `publicPages.js`). Brak testu, który wymusza spójność „co wysyłamy” z „co zostaje”. Trudne do zautomatyzowania, ale można przynajmniej pilnować listy słów.
- **Propozycje:**
  - [P1][S] Usunąć „imię i nazwisko” z sekcji „nie opuszczają urządzenia” (albo dopisać „poza podpisem wiadomości na czacie”); zsynchronizować z `publicPages.js`.
  - [P1][S] `android:allowBackup="false"` (albo `dataExtractionRules` wykluczające `fitter_install_secret`, `fitter_device_id`, profil i zgody) albo zmienić tekst polityki.
  - [P1][M] Uzupełnić `PrivacyInfo.xcprivacy` (Name, Other User Content, Device ID, Photos, UserDefaults CA92.1). Spisać zgodnie z `docs/store/deklaracje-prywatnosci.md`.
  - [P1][M] Powiadomienie moderatora o zgłoszeniu (np. e-mail przez istniejący `SUPPORT_EMAIL` albo webhook Discord/Telegram). Albo złagodzić obietnicę „24 h” i „odbieramy dostęp” do tego, co jest (ukrycie po 3 zgłoszeniach i ręczna moderacja).
  - [P2][M] Ban urządzenia lub autora w backendzie (`banned_devices`, 403 `DEVICE_BANNED`) i obsługa w `classifyChatError`.

## consent — „Zasady i prywatność” (ConsentScreen)
- **Cel i dla kogo:** ponowna lub pierwsza akceptacja zasad dla osoby, która ma profil, ale nie ma zgody na bieżącą `kLegalVersion`. Pokazuje go bramka czatu i bramka asystenta.
- **Co zawiera:** 3 punkty (nazwisko, zero tolerancji i 24 h, WPS), przyciski „Regulamin” i „Polityka prywatności”, cały wiersz „mam 16 lat, przeczytałem…” klikalny (≥ 48 dp), „Akceptuję” (ochrona przed podwójnym stuknięciem). Pliki: `consent_screen.dart`, `services/legal_consent.dart`, `widgets/community_gate.dart`.
- **Stan:** działa.
- **Błędy potwierdzone:**
  - `community_gate.dart:58-67` (`ensureServerConsent`, wołane z `ai_chat_screen.dart:582`, `:610`) otwiera ten sam `ConsentScreen`, którego treść jest wyłącznie czatowa (`consent_screen.dart:83-97`: „Na czacie piszesz pod własnym nazwiskiem… Zanim napiszesz na czacie…”). Monter, który zadaje pytanie asystentowi, widzi ekran o czacie i nazwisku, choć asystent nazwiska nie wysyła. To myląca zgoda: nie mówi, na co naprawdę się zgadza (wysyłka pytania do Anthropic).
- **Problemy UX / sklepowe:**
  - Akceptacja przez asystenta ustawia ogólną `LegalConsent`. Później wejście na czat z istniejącym profilem nie pokaże już zasad czatu. Formalnie zgoda jest ta sama, ale kontekst „zero tolerancji” nie był wtedy istotny dla użytkownika.
  - Pole wyboru bez zaznaczenia: przycisk jest wyłączony (`onPressed: null`), więc `Haptic.error()` w `_accept` (`:35-37`) nigdy się nie wykona.
- **Brakujące funkcje:** wariant treści dla kontekstu (czat, asystent); opcja wycofania zgody w profilu.
- **Testy:** `consent_screen_test` (checkbox, zapis wersji, podwójne stuknięcie). Brak testu treści w kontekście asystenta.
- **Propozycje:**
  - [P2][S] `ConsentScreen(context: ConsentContext.chat | .assistant)` z osobnym nagłówkiem i punktami (asystent: „pytanie trafia na nasz serwer i do Anthropic, bez nazwiska”).
  - [P3][S] Usunąć martwą gałąź haptyki albo zostawić przycisk aktywny i pokazywać błąd.

## onboarding-name — „Zanim napiszesz na czacie”
- **Cel i dla kogo:** jednorazowy krok przed pierwszym wejściem na czat: imię, nazwisko i akceptacja zasad.
- **Co zawiera:** dwa pola z walidacją (regex Unicode), informacja, co wysyłamy, wiersz zgody z linkami, przełącznik PL/EN (≥ 48 dp), „Zapisz i dalej”. Pliki: `onboarding_name_screen.dart`, `services/user_profile.dart`.
- **Stan:** działa.
- **Błędy potwierdzone:**
  - `onboarding_name_screen.dart:94-97`: `LegalConsent.accept()` wykonuje się także wtedy, gdy zapis profilu się nie udał (`ok == false`). Zgoda zostaje zapisana bez profilu. Użytkownik widzi „Nie udało się zapisać”, a przy kolejnej próbie brakuje tylko profilu. Zgoda powinna iść po `ok`.
  - `onboarding_name_screen.dart:25` i zduplikowany `profile_screen.dart:35`: regex `^[\p{L} '\-]{2,}$` przepuszcza nazwy bez liter („--”, „' -”). Komunikat mówi „min. 2 litery”, ale kod tego nie sprawdza.
  - `onboarding_name_screen.dart:413`, `:421`: `TapGestureRecognizer` tworzone w `build` (StatelessWidget) i nigdy nie zwalniane. To drobny wyciek.
- **Problemy UX / sklepowe:**
  - Wymóg prawdziwego imienia i nazwiska jest uczciwie opisany. Nie ma jednak żadnej weryfikacji, więc „Jan Kowalski” może być kimkolwiek. Regulamin zakazuje podszywania się, ale to fikcja bez moderacji.
  - Walidacja nie ma limitu długości. Podpis jest przycinany do 32 znaków w `chat_service.dart:209`, a użytkownik o tym nie wie.
  - `autofocus` na pierwszym polu od razu otwiera klawiaturę i zasłania punkty o prywatności na małym ekranie.
- **Brakujące funkcje:** podgląd, jak będzie wyglądał podpis („Jan Kowalski · 12:04”).
- **Testy:** `onboarding_name_screen_test` (48 dp, zgoda, język, onDone). Brak testu „zapis profilu padł, zgoda nie powinna się zapisać” i testu nazw bez liter.
- **Propozycje:**
  - [P2][S] Zgoda dopiero po `ok`; wspólny walidator nazw w `user_profile.dart` (≥ 2 litery `\p{L}`, max 32 znaki, `maxLength` w polu).
  - [P3][S] Recognizery w StatefulWidget z `dispose`; bez `autofocus` albo przewinięcie do pól.

## profile — „Twój profil”
- **Cel i dla kogo:** edycja podpisu, lista zablokowanych, kopia i przywracanie, zasady, kontakt, „Usuń moje dane” (Google Play: usuwanie danych w aplikacji; RODO art. 17).
- **Co zawiera:** `_Identity`, WpqrChipLive, opisy „Co widzą inni” i „Co zostaje na telefonie”, pola imię i nazwisko, zablokowani z „Odblokuj”, kopia ZIP i przywracanie (z oknem ostrzeżenia), Regulamin, Polityka, Kontakt (mailto z zapasowym SnackBarem), „Usuń moje dane”. Kolejność usuwania: `DELETE /api/fitter/me`, potem dane lokalne, potem podsumowanie; obsługa 404, 429, offline, 401 i 5xx, zachowanie tożsamości przy aktywnym Premium. Pliki: `profile_screen.dart`, `server_data_deletion.dart`, `data_backup.dart`, `blocked_users.dart`.
- **Stan:** działa, z lukami w zakresie usuwania.
- **Błędy potwierdzone:**
  - `profile_screen.dart:705-718` (`_eraseLocalData`) nie kasuje zgody na wysyłkę zdjęć do skanera. Nie usuwa klucza `iso_scan_consent_v1` z `scan_consent_gate.dart:94` i nie zeruje statycznego `ScanConsent._acceptedVersion`. Po „Usuń moje dane” skaner dalej wysyła zdjęcia bez pytania o zgodę. Nie czyści też historii asystenta (`AssistantHistoryStore`, lokalna, może zawierać treść pytań). Okno i podsumowanie mówią ogólnie o „zgodzie na zasady”, więc użytkownik zakłada, że wszystkie zgody zniknęły.
  - `server_data_deletion.dart:80` i `main.dart:37`: `PremiumService.init()` przy każdym starcie generuje i zapisuje `fitter_device_id`, więc `hasStoredDeviceId()` jest praktycznie zawsze `true`. Gałąź `nothingToDelete` jest martwa. Monter, który nigdy nie korzystał z czatu, skanera ani asystenta, po „Usuń moje dane” bez zasięgu dostaje okno „Brak połączenia… danych z czatu jeszcze nie usunęliśmy”, choć na serwerze niczego nie ma. Do tego pierwszym kontaktem takiej instalacji z serwerem staje się właśnie `DELETE /me`.
  - `profile_screen.dart:776-781` („Co zostaje na telefonie… zdjęcia… Nic z tego nie trafia na serwer”) pomija, że zdjęcie rysunku ze skanera wychodzi na serwer i do Anthropic.
- **Problemy UX / sklepowe:**
  - Ścieżka usuwania danych jest dobra: widoczna, 2 kroki, podsumowanie, droga mailowa, publiczny URL `dataDeletionUrl`, zgodnie z Google Play.
  - Zmiana imienia nie zmienia podpisu już wysłanych wiadomości (serwer trzyma `nickname` przy wiadomości). Podpis „Tak podpisane są Twoje wiadomości” sugeruje, że zmieni.
  - Profil można zapisać bez zgody. Potem bramka czatu pokaże `ConsentScreen`, co jest poprawne, ale ekran nie mówi, że czat wymaga jeszcze akceptacji.
  - Brak sekcji „Zgody”: skaner, asystent, zasady czatu, z datą i możliwością wycofania (RODO art. 7 ust. 3: wycofanie zgody tak łatwe jak jej wyrażenie).
  - Kolory: `_LinkTile` jako `ListTile`, cele dotyku OK. „Odblokuj” to TextButton z domyślnym minimum 48 dp, OK.
- **Brakujące funkcje:** lista zgód z wycofaniem; eksport danych serwerowych (RODO art. 15/20, na dziś mailowo); usunięcie danych lokalnych (projekty, dziennik) jednym przyciskiem. Polityka odsyła do odinstalowania, co przy Auto Backup Androida nie wystarcza.
- **Testy:** `profile_delete_data_test` (kolejność serwer i telefon, 404, offline, 429), `profile_restore_warning_test`. Brak testu, że zgoda skanera i historia asystenta są czyszczone, oraz testu ścieżki instalacji bez kontaktu z serwerem.
- **Propozycje:**
  - [P1][S] W `_eraseLocalData`: `ScanConsent.clear()` (nowa metoda: usuwa klucz i zeruje stan statyczny) oraz `AssistantHistoryStore.clear()`; dopisać je w oknie i podsumowaniu; test regresyjny.
  - [P2][S] Znacznik „instalacja kontaktowała się z serwerem” (ustawiany przy pierwszym `authHeaders()` z zapytaniem) zamiast `hasStoredDeviceId()`. Wtedy `nothingToDelete` znowu działa offline.
  - [P2][M] Sekcja „Zgody” z datą i przyciskiem „Wycofaj” (skaner, asystent, czat).
  - [P3][S] Poprawić opis „Co zostaje na telefonie” (skaner) i podpis przy nazwisku („nowe wiadomości”).

## chat — „Czat” (pokoje i rozmowy)
- **Cel i dla kogo:** publiczny czat branżowy pod prawdziwym nazwiskiem; 4 pokoje (Ogólny, Spawanie, Montaż rurociągów, Praca / brygady).
- **Co zawiera:**
  - lista pokoi (z backendu, awaryjnie lokalna) i widok pokoju: odpytywanie co 8 s, w tle najwyżej co 30 s, deduplikacja id + czas;
  - pole wiadomości: 2–400 znaków, lokalny `ContentFilter`, ponowna bramka `hasCommunityAccess` przed wysyłką;
  - długie przytrzymanie cudzej wiadomości: „Zgłoś” (potwierdzenie; ukrycie po 3 zgłoszeniach) albo „Zablokuj autora” (lokalnie, po `author_id`);
  - komunikaty dla 429, 400/422, `INSTALL_SECRET_*` i braku sieci; rejestracja urządzenia (TOFU) przy wejściu.
  - Pliki: `chat_screen.dart`, `services/chat_service.dart`, `content_filter.dart`, `blocked_users.dart`, `api_client.dart`.
- **Stan:** działa, z błędami poniżej.
- **Błędy potwierdzone:**
  - `content_filter.dart` (rdzeń `'pedal'`) blokuje słowa „pedał” i „pedal”, czyli **pedał nożny do TIG-a** („foot pedal”), codzienne słowo spawacza. Wiadomości „mam problem z pedałem od TIG-a” i „foot pedal amperage” są odrzucane jako obraźliwe. Test `test/legal_test.dart:44` utrwala to zachowanie.
  - `api_client.dart:115-135`: `_withRetry` ponawia także **POST** po `TimeoutException` i 502/503/504. `postMessage` (`chat_service.dart:272`, timeout 8 s) na wolnym łączu może wysłać tę samą wiadomość dwa razy: serwer przyjął pierwszą, klient nie zdążył dostać odpowiedzi. To samo dotyczy `report` i `device/register`.
  - `chat_screen.dart:1045`: `IconButton` „wyślij” bez `tooltip`, więc TalkBack i VoiceOver czytają „przycisk” bez etykiety.
  - `chat_screen.dart:921-923`: menu zgłoś/zablokuj jest dostępne tylko przez `GestureDetector.onLongPress`, bez `Semantics(onLongPressHint)` i bez widocznej ikony. Czytnik ekranu tej akcji nie ogłasza, a recenzent Apple może jej nie znaleźć.
  - Kontrast w dymkach: czas we własnym dymku `kTextMut` na fiolecie 50% (`:919`, `:972`) to ok. **3,3:1**. Podpis autora `_kAccent #AB47BC` na `#141821` (`:953-956`, 11 sp) to ok. **3,7:1**. Oba poniżej WCAG AA 4,5:1.
  - `chat_service.dart:186-192` (i backend): pokój „Praca / brygady” ma opis „wymiana CV”, a polityka (`legal_texts.dart:129-132`) każe nie publikować telefonów ani adresów. Opis pokoju zachęca do łamania zasad prywatności.
- **Problemy UX / sklepowe:**
  - Apple 1.2 jest spełniony w zakresie filtra, zgłaszania, blokowania, akceptacji zasad i kontaktu. Słabe punkty to brak powiadomienia moderatora (patrz „legal”) i brak bana po stronie serwera.
  - Po zgłoszeniu wiadomość zostaje widoczna dla zgłaszającego do czasu 3 zgłoszeń. Standard (i oczekiwanie recenzentów) to natychmiastowe ukrycie u zgłaszającego.
  - Nie można usunąć własnej wiadomości. Polityka mówi „chyba że … Ty je usuniesz” i odsyła do usunięcia wszystkich danych naraz.
  - Po zablokowaniu wszystkich widocznych autorów pusty pokój pokazuje „Witaj — bądź pierwszy”, co jest mylące.
  - Tylko ostatnie 100 wiadomości, bez wczytywania starszych.
  - Tekstu wiadomości nie da się zaznaczyć ani skopiować, a to przydaje się przy parametrach.
  - Kolory są stałymi w pliku (`_kCard`, `_kAccent`…), a nie tokenami. Tytuł pokoju to `Row` bez `Flexible`, więc długa nazwa pokoju z backendu przepełni pasek.
  - Na liście pokoi margines kafla jest wewnątrz `InkWell` (`:254-262`), więc rozlew wychodzi poza kartę.
- **Brakujące funkcje:** widoczne menu „⋮” przy wiadomości; usuwanie własnej wiadomości; ukrycie po własnym zgłoszeniu; wczytywanie starszych; kopiowanie; link „Zasady czatu” w pasku; licznik nieprzeczytanych.
- **Testy:** `chat_secured_backend_test` (rejestracja, `mine`, blokada po `author_id`, 401), `chat_identity_test`, `community_trust_test`. Brak testu zgłoszenia na widgecie (potwierdzenie, SnackBar, 429), testu fałszywych trafień filtra dla słownictwa branżowego i testu „POST nie jest ponawiany po timeoucie”.
- **Propozycje:**
  - [P1][S] Usunąć `pedal` z listy (albo wyjątek dla „pedał/pedal” obok „tig”, „nożny”, „foot”); dodać test fałszywych trafień z żargonem (pedał, dupa w znaczeniu „tył”, sutki… do przejrzenia).
  - [P1][S] Nie ponawiać POST poza błędami połączenia sprzed wysłania (albo klucz idempotencji `client_msg_id` w `postMessage` i deduplikacja na serwerze).
  - [P1][S] Widoczny `IconButton` „⋮” w dymku (≥ 48 dp) plus `Semantics(onLongPressHint)`; tooltip „Wyślij”.
  - [P2][S] Ukrywać wiadomość lokalnie od razu po zgłoszeniu (lista `reported_ids` w SharedPreferences).
  - [P2][S] Kontrast: czas w dymku `kText` z alpha 0.8 albo jaśniejszy; podpis `#CE93D8` (≈ 7:1).
  - [P2][M] `DELETE /chat/messages/:id` dla własnych i pozycja „Usuń” w menu.
  - [P2][S] Zmienić opis pokoju „Praca / brygady” (bez „wymiana CV”, z dopiskiem „kontakt przez prywatne kanały”).
  - [P3][M] Wczytywanie starszych wiadomości, zaznaczanie tekstu, tokeny motywu.

## premium — „Fitter Welder Pro+” (ukryty)
- **Cel i dla kogo:** płatna subskrypcja (19 PLN/mies., 149 PLN/rok) przez Stripe Checkout w przeglądarce.
- **Co zawiera:** `premium_screen.dart` (1247 linii): lista korzyści, plany, weryfikacja płatności z odpytywaniem, portal Stripe, „Pomiń teraz”. `premium_gate.dart` (nakładka z cenami), `premium_service.dart` (tożsamość instalacji i status, obie funkcje wspólne z czatem, skanerem i usuwaniem danych).
- **Stan:** ukryty (`kPaidFeaturesEnabled = false`; kafel `home_screen.dart:457`). Nieosiągalny także przez PremiumGate, bo `kAiScannerFreeTier = true`. `BackendConfig.stripeBackendLive = true`, więc usługi płatności nie są wyłączone flagą backendu, tylko UI.
- **Błędy potwierdzone / problemy sklepowe (jeśli ktoś włączy flagę):**
  - **Apple 3.1.1:** subskrypcja odblokowująca funkcje w aplikacji przez Stripe Checkout (`premium_screen.dart:774`, `launchUrl`) byłaby odrzucona na iOS. Potrzebny jest StoreKit / IAP (albo uprawnienie na zewnętrzny link, tylko w wybranych krajach). Google Play wymaga Play Billing dla treści cyfrowych.
  - **Apple 3.1.2 / 2.3.1:** ekran obiecuje „Bez reklam” i „Cloud sync między urządzeniami”, których nie ma. Obiecuje też „Kalkulator momentu śrub”, „Heat input + preheat” i „Coping templates” jako korzyści Premium, a te są dziś darmowe w rejestrze. Brak „Przywróć zakupy”, brak linków do regulaminu (EULA) i polityki przy planach, ceny wpisane na sztywno w PLN (`:473`, `:483`, `premium_gate.dart:158`) zamiast cen ze sklepu.
  - Polityka (`legal_texts.dart:346-354`) mówi, że płatności są wyłączone. Włączenie flagi wymaga podniesienia `kLegalVersion`.
- **Problemy UX:** brak realnej propozycji wartości. Asystent i skaner są darmowe, a reszta narzędzi też.
- **Brakujące funkcje:** IAP, przywracanie zakupów, faktycznie płatne funkcje.
- **Testy:** `premium_status_test`, `device_identity_test` (odświeżanie nie wysyła nic przy wyłączonych płatnościach). Brak testu ekranu Premium, ale jest nieosiągalny.
- **Ocena: trzymać tylko warstwę `PremiumService` (tożsamość instalacji, `authHeaders`, `registerDevice`, `resetIdentity`), a ekran i bramkę wyciąć.** `PremiumService` jest dziś faktycznie usługą tożsamości instalacji, a nie Premium.
- **Propozycje:**
  - [P2][M] Przenieść tożsamość (device_id, sekret, author_id, register, reset) do `InstallIdentityService`; `PremiumService` zostawić jako cienką fasadę albo usunąć.
  - [P3][M] Usunąć `premium_screen.dart`, `premium_gate.dart` (i gałąź PremiumGate w skanerze) z buildu; kod zostaje w historii git. Gdy wróci monetyzacja: StoreKit 2 / Play Billing (np. RevenueCat), nowe teksty, `kLegalVersion` 4.
  - [P3][S] Do czasu usunięcia: test strażnika, że żadna ścieżka UI nie prowadzi do `PremiumScreen` przy `kPaidFeaturesEnabled == false`.

## jobs — „Praca” (ukryty)
- **Cel i dla kogo:** tablica ogłoszeń o pracę (monterzy, spawacze, brygady).
- **Co zawiera:** `jobs_screen.dart` (1149 linii): lista, filtr lokalizacji, edycja, odpytywanie po płatności Stripe. `jobs_service.dart` (checkout 49 PLN), `models/job_listing.dart`.
- **Stan:** ukryty (`kJobsEnabled = false`, `jobsBackendLive = false`). Komentarz w pliku mówi „local-first”, a serwis jest „Backend-backed” — dwa modele w jednym module.
- **Błędy potwierdzone:** `jobs_service.dart:20`, `:35` sprawdzają `stripeBackendLive`, a nie `jobsBackendLive` ani `kJobsEnabled`, więc przy odsłonięciu ekranu lista od razu łączyłaby się z backendem.
- **Problemy UX / sklepowe:**
  - Treści użytkowników bez zgłaszania i blokowania ogłoszeń (Apple 1.2) i bez filtra treści.
  - Płatne ogłoszenie przez Stripe wewnątrz aplikacji: ryzyko przy Apple 3.1.1 (treść cyfrowa konsumowana w aplikacji; w najlepszym razie wymaga uzasadnienia).
  - Dane kontaktowe (e-mail, telefon) publicznie w ogłoszeniach: potrzebny opis w polityce, a dziś go brak.
  - Pokrywa się z pokojem czatu „Praca / brygady”, który jest darmowy i już moderowany.
- **Brakujące funkcje:** moderacja, zgłaszanie, wygasanie ogłoszeń, IAP.
- **Testy:** brak dedykowanych (jest parametr `loadListings` do wstrzyknięcia, ale bez testu).
- **Ocena: wyciąć.** Potrzebę pokrywa pokój czatu. Powrót wymagałby zgłaszania i blokowania, moderacji, IAP, nowej polityki i `kLegalVersion` 4, czyli pracy na rozmiar L.
- **Propozycje:** [P3][S] Usunąć `jobs_screen.dart`, `job_add_screen.dart`, `jobs_service.dart`, `job_listing.dart`, `kJobsEnabled` i kafel z `home_screen.dart:437-444`. Zostawić tylko usuwanie `job_listings` w `DELETE /me` na backendzie (dla starych danych).

## job-add — „Dodaj ogłoszenie” (ukryty)
- **Cel i dla kogo:** formularz ogłoszenia z płatnością 49 PLN za 30 dni.
- **Co zawiera:** `job_add_screen.dart` (583 linie): pola, walidacja, potwierdzenie porzucenia zmian, Stripe Checkout, blokada podwójnej płatności.
- **Stan:** ukryty; osiągalny wyłącznie z `JobsScreen`.
- **Błędy potwierdzone:**
  - `job_add_screen.dart:374`: `label: 'Email'` poza `context.tr`.
  - `:470`: tekst „Listing is saved locally (MVP)” przeczy płatnej publikacji na serwerze.
- **Problemy UX / sklepowe:** jak w „jobs” (3.1.1, UGC, dane kontaktowe).
- **Brakujące funkcje:** jak wyżej.
- **Testy:** brak.
- **Ocena: wyciąć razem z „jobs”.**
- **Propozycje:** [P3][S] Usunąć razem z modułem jobs.

## register — „Rejestracja” (sierota)
- **Cel i dla kogo:** relikt z prototypu: rejestracja e-mail i hasło.
- **Co zawiera:** `register_screen.dart` (131 linii), `services/auth_service.dart` (użytkownicy w pamięci, SHA-256 bez soli, **wbudowany użytkownik demo `test@example.com` / `password123`**), `widgets/auth_widgets.dart` (150 linii, nieużywany), teksty ze starego systemu `AppLocalizations.translate` (`lib/l10n/*.arb`).
- **Stan:** ukryty, nieosiągalny. Rejestr świadomie go pomija (`tool_registry.dart:52-55`).
- **Błędy potwierdzone:** `register_screen.dart:35-39`: puste pola pokazują komunikat „hasła się nie zgadzają” (`register_password_mismatch`). Konta znikają po restarcie.
- **Problemy UX / sklepowe:** gdyby ekran był osiągalny, Apple 5.1.1(v) wymagałby usuwania konta, a hasło demo w kodzie źle wygląda w audycie bezpieczeństwa. Aplikacja z założenia działa bez konta.
- **Brakujące funkcje:** nie dotyczy.
- **Testy:** brak.
- **Ocena: wyciąć.**
- **Propozycje:** [P3][S] Usunąć `register_screen.dart`, `auth_service.dart`, `auth_widgets.dart`. Po usunięciu też tutor można skasować `lib/l10n/` (ARB: EN 139 linii, PL 127, rozjazd kluczy) i delegata `AppLocalizations` w `app.dart:133`. Wcześniej sprawdzić jedyną wzmiankę w `welder_identity.dart:5` (to tylko komentarz).

## tutor — „Tutor” (sierota)
- **Cel i dla kogo:** relikt: „korepetytor” z filtrem zakresu tematów.
- **Co zawiera:** `tutor_screen.dart` (273 linie), `services/backend_service.dart`: pamięć podręczna w RAM, `searchAnswer` zawsze zwraca `null`.
- **Stan:** ukryty, nieosiągalny. **Funkcjonalnie martwy:** każde pytanie w zakresie kończy się „brak odpowiedzi”.
- **Błędy potwierdzone:** `backend_service.dart` (`searchAnswer` → `return null`), więc tutor nigdy nie odpowiada. Miesza `AppLocalizations.translate` z `context.tr`.
- **Problemy UX / sklepowe:** nieosiągalny, więc nie ma dziś ryzyka. Funkcję w całości zastępuje Asystent (`ai_chat_screen.dart`, tryb „Odpowiedz”).
- **Brakujące funkcje:** nie dotyczy.
- **Testy:** brak.
- **Ocena: wyciąć.**
- **Propozycje:** [P3][S] Usunąć `tutor_screen.dart` i `backend_service.dart`. Listę słów zakresu można przenieść do parsera asystenta, jeśli się przyda.

---

## Części wspólne

### `lib/widgets/tool_registry.dart` + `tool_tiles.dart`
- Jeden rejestr (35 wpisów, 10 grup) dla menu, wyszukiwarki, przypiętych i ostatnio używanych. Trwałe identyfikatory, tytuły PL/EN, słowa kluczowe PL/EN, `needsAccount`, `available`. Wyszukiwarka zwija polskie znaki i obcina końcówki odmiany (stemming). Integralność pilnuje `tool_registry_test`: unikalne id i tytuły, brak WERSALIKÓW, brak duplikatów celu, sieroty bez wejścia. Wszystkie testy zielone.
- **Uwaga:** `needsAccount` nie ma dziś żadnego użytkownika (skaner i asystent mają `false`), więc bramka `openTool` jest martwym kodem, gotowym na przyszłość.
- Poza rejestrem, a osiągalne z UI: Czat, Profil, Pomoc, Tożsamość spawacza, Asystent (jest w rejestrze). Tylko pierwsze cztery są „niewyszukiwalne”, patrz propozycja w „home”.
- **Duplikaty:** brak (sprawdzone testem). **Ślepe zaułki:** brak przy obecnych flagach. **Ekrany z ceną:** `PremiumScreen`, `PremiumGate._LockedOverlay`, `JobAddScreen` są nieosiągalne.

### `community_gate.dart` / `scan_consent_gate.dart`
- Model zgód jest dobry: czat wymaga imienia i zasad; asystent tylko zasad; skaner osobnej zgody na zdjęcie (z linkiem do polityki), bez nazwiska. Każda zgoda jest wersjonowana `kLegalVersion`.
- Luki: tekst zgody dla asystenta mówi o czacie (patrz „consent”); zgoda skanera nie jest kasowana przy „Usuń moje dane” (patrz „profile”); brak miejsca, w którym widać i wycofuje się zgody.

### `lib/i18n/app_language.dart`
- `context.tr(pl:, en:)` wymaga obu języków (brak EN nie skompiluje się). Język zapisywany; bez zapisu idzie za językiem telefonu (polski daje PL, każdy inny EN). W grupie znaleziono tylko 1 tekst UI poza `tr` (`job_add_screen.dart:374`). „Polski”, „English” i „PREMIUM” są celowo nazwami własnymi.
- Równolegle żyje stary system `lib/l10n` (ARB), używany tylko przez register i tutor. Do usunięcia razem z nimi.

### `lib/theme/app_theme.dart`
- Tokeny z udokumentowanym kontrastem (`contrast_test`); `kMinTapTarget = 48`; czarny tekst na bursztynie.
- Część ekranów (chat, help, premium, jobs) trzyma kopie stałych, a fiolet czatu (`#AB47BC`) i zieleń pomocy (`#2ECC71`) są poza tokenami i poza testem kontrastu. Stąd niewykryte 3,3:1 i 3,7:1 w czacie.
- Brak `filledButtonTheme`. `FilledButton` w oknie zgody skanera bierze kolory z palety wygenerowanej z koloru bazowego, więc różni się od reszty.

### `lib/config/feature_flags.dart`
- Flagi są spójne i dobrze opisane. `kCommunityEnabled = true`, `kAiScannerEnabled` i `kAiScannerFreeTier` mają wartość `true`, a `kPaidFeaturesEnabled` i `kJobsEnabled` wartość `false`. Testy `scanner_flags_test` i `welder_journey_test` pilnują kafli skanera.
- Uwaga: `BackendConfig.stripeBackendLive = true` przy wyłączonych płatnościach. Usługi (`jobs_service`) sprawdzają flagę backendu, a nie produktu.

### `services/chat_service.dart`, `premium_service.dart`, `api_client.dart`
- Tożsamość instalacji (device_id, sekret TOFU, author_id) jest poprawnie wczytywana raz (`init()` zapamiętuje obietnicę), reset po usunięciu danych działa, a sekret nie trafia do treści żądań ani do logów.
- Błąd ponawiania POST: patrz „chat”.
- `ApiClient._decode` rzuca `FormatException`, gdy odpowiedź 2xx nie jest JSON-em. Kończy się to ogólnym „server”, co jest akceptowalne.
- `ChatService.getNickname` przy braku profilu podpisuje „Monter XXXX” (`:218`), co omija regułę „tylko prawdziwe nazwisko”. Dziś bramka temu zapobiega, ale lepiej rzucać wyjątek niż wysyłać anonimowo.

---

## Top 5 w grupie

1. **[P1] Filtr czatu blokuje „pedał” od TIG-a** (`content_filter.dart`, rdzeń `pedal`; test `legal_test.dart:44` to utrwala). Codzienne słowo spawacza jest odrzucane jako wyzwisko. Poprawka [S]: usunąć rdzeń albo dodać wyjątki kontekstowe; test fałszywych trafień z żargonem.
2. **[P1] „Usuń moje dane” zostawia zgodę na wysyłkę zdjęć do skanera i historię asystenta** (`profile_screen.dart:705-718` wobec `scan_consent_gate.dart:94`). Po usunięciu danych skaner wysyła zdjęcia bez ponownej zgody. Dodatkowo `nothingToDelete` jest martwe (`main.dart:37` → `server_data_deletion.dart:80`), więc monter offline bez historii serwerowej dostaje mylące okno. [S]
3. **[P1] Obietnice moderacji bez pokrycia i niespójna polityka.** „24 h” i „odbieramy dostęp” nie mają powiadomienia moderatora ani bana w backendzie. Polityka wymienia imię i nazwisko jako „nie opuszczają urządzenia” (`legal_texts.dart:75-83`). Auto Backup Androida (brak `allowBackup="false"`) przeczy zdaniu „usuwają się z odinstalowaniem” i klonuje sekret instalacji. `PrivacyInfo.xcprivacy` jest pusty. [M]
4. **[P1] Czat: duplikaty wiadomości i dostępność zgłaszania.** `ApiClient` ponawia POST po timeoucie (`api_client.dart:115-135`), więc przy słabym zasięgu wiadomość idzie dwa razy. Zgłoś i zablokuj są tylko pod długim przytrzymaniem, bez semantyki i bez widocznej ikony (`chat_screen.dart:921`). „Wyślij” nie ma etykiety (`:1045`). Podpis i czas w dymkach nie spełniają AA (3,7:1 i 3,3:1). [S–M]
5. **[P2] Porządek w modułach ukrytych i w zgodach.**
   - Wyciąć jobs, job-add, register (z hasłem demo w `auth_service.dart`) i tutor (zawsze „brak odpowiedzi”) razem ze starym `lib/l10n`.
   - Premium zredukować do usługi tożsamości instalacji. W obecnej formie naruszałby Apple 3.1.1 i 3.1.2 (Stripe zamiast IAP, obiecywane „bez reklam” i „cloud sync”, których nie ma).
   - Rozdzielić treść `ConsentScreen` dla czatu i asystenta (`community_gate.dart:58-67`).
   - Dołożyć odświeżanie ekranu głównego po powrocie z menu (`home_screen.dart:401`, `:409`) i wpisy nawigacyjne (Czat, Profil, Usuń dane) w wyszukiwarce. [M]
