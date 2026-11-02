# QA-COCKPIT — FitterWelderPro

## Obsługa błędów głosu — 2026-11-02

- Asystent rozróżnia teraz ciszę/brak rozpoznanej wypowiedzi, problem połączenia, brak uprawnień, niedostępny język i zajętą usługę. Zamiast jednego ogólnego komunikatu podaje właściwy następny krok po polsku i angielsku. Kody potwierdzono w zainstalowanym speech_to_text7.5.0 (Android/iOS).
- Tekst w polu pozostaje edytowalny; komunikat o jego zachowaniu pojawia się tylko dla niepustego pola. Błąd nie wysyła polecenia; mikrofon można uruchomić ponownie. Regresje obejmują również ochronę przed spóźnionymi wynikami i pracą w tle.
- **47 testów /3 zestawy PASS**, 0 błędów/pominięć, 21,111s; `speech-recovery-test-summary.json` i `speech-recovery-tests.jsonl` w katalogu artefaktów2026-11-02. To testy Flutter z wstrzykniętymi zdarzeniami rozpoznawania, nie test fizycznego mikrofonu. `adb devices -l` nie wykazało podłączonego telefonu.
- Pełna analiza `flutter analyze --no-pub`: **No issues found**, 58,4s; log `speech-recovery-analyze.log`.
- Zmiana jest w kodzie źródłowym; wcześniejsze APK0.5.18/iOS1083 nie zawierają tych nowych komunikatów. Nie uruchamiano dla samej zmiany komunikatów kolejnego buildu lub deployu backendu.

## Doprecyzowanie przez AI z zachowaniem pytania — 2026-11-02

- Rzeczywisty test rozmowy **PASS**: „Jaki gaz dobrać do spawania?” → AI pyta o proces i materiał → „TIG, stal nierdzewna 316L, chodzi o gaz osłonowy.” → końcowa odpowiedź dotycząca pierwotnego doboru gazu. Pierwsza odpowiedź ma `needs_clarification:true`, druga `false`; żadnego pytania o wybór modułu.
- Wychodzące drugie żądanie zawiera dokładne pierwotne pytanie w `question_clarification.user_turns` i poprzednią wymianę w historii. Serwer potwierdza `question_clarification_used:true`. Obie odpowiedzi wyświetlono w rzeczywistym panelu; obejrzano kadry27/30 nagrania.
- `matrix-346a450rn5oft` **FINISHED/SUCCESS**, wirtualny MediumPhone.arm / Android15 API35 / PL, 1 native testcase, 0 błędów/pominięć, 25s +3s przetwarzania. Dwa rzeczywiste żądania czatu HTTP200, zero przed faktyczną zgodą, zero blokowanych prób innych ścieżek, brak ponowień. Dane własnej instalacji usunięte HTTP200/ok, prywatny plik usunięty.
- QA źródło `aa04a33c1ac773d55684a0c699f7e994fc293879`, produkcyjny `lib` identyczny z `9c025f3`. Analiza dwóch plików testu bez uwag. Ta tura dodaje dowód istniejącego zachowania; kod produkcyjny i wydania 0.5.18 pozostają bez zmian. Raport `G:/Projekty/FitterWelderPro-artifacts/2026-11-02/clarification-qa-virtual-verification.json` i pliki `clarification-qa-virtual-*`.
- Zakres: instrumentowany debug z prawdziwym backendem i modelem, bez atrap. Nie potwierdza dowolnej porady spawalniczej, działania mikrofonu, release AOT ani fizycznego iPhone’a. Serwer zachowuje limity/rezerwację budżetu; dwa żądania mobilne nie oznaczają gwarantowanej liczby płatnych wywołań dostawcy, dokładny koszt nie jest udostępniony.

## iOS 0.5.18 (1083) — wewnętrzny TestFlight gotowy, 2026-11-02

- **Apple `VALID` / `IN_BETA_TESTING`**, potwierdzone API 2026-11-02T03:21:15.355748Z. Train `0.5.18`, build `1083`, Apple build ID `86c2f807-5c99-482d-9343-f1bfa0604b49`, nie wygasł. External state `READY_FOR_BETA_SUBMISSION`; recenzji zewnętrznej bety nie zgłaszano.
- Źródło `04457693010db445d81a3faaf3f365d804d174d2`: kod aplikacji, zasoby, iOS i zależności identyczne z Androidem 0.5.18 (`e13ba58`); zmiana dotyczy konfiguracji CI. Nowy `ios-upload` dziedziczy sprawdzony signing, SDK i budowanie, wysyła IPA z `submit_to_testflight:false` / `submit_to_app_store:false`. Flagi sterują zgłoszeniami po uploadzie. Stary workflow `ios-testflight` zachowany bez zmian po rozwinięciu YAML. Standardowy eksport App Store pozwala później zgłosić ten sam build; nie ustawiano ograniczenia export internal-only ani nie wygaszano wcześniejszych buildów.
- Codemagic **`6ae7ff5bf02e5d31a17cb04d` finished**, wszystkie kroki success, 2026-11-02T03:11:30.520Z–03:17:28.592Z. Test wersji zaliczony na macOS; Flutter 3.47.5, istniejący klucz podpisu i profil. Upload potwierdzony logiem `UPLOAD SUCCEEDED with no errors`. Brak zadań zewnętrznej recenzji i ponowienia limitu 422. Numer nowego workflow to 1, ale globalny licznik projektu poprawnie dał cfBundleVersion 1083 >1082.
- IPA `G:/Projekty/FitterWelderPro-artifacts/2026-11-02/fwp-ios-6ae7ff5bf02e5d31a17cb04d.ipa`, **34 976 920 B**, SHA256 `746d66279e546970093396d8a9091ed330d1f6007cba8406d4cdc57d2888139f`. Bundle `com.jakatora.fitterwelderpro`, Team `B7J6A7R258`, ważny profil do 2027-07-10T14:57:03, debug entitlement false, CodeResources obecne; Apple zakończyło przetwarzanie VALID.
- W pobranym IPA potwierdzono zgodność wszystkich pięciu opisów uprawnień z repo: lokalizacja podczas użycia, biblioteka zdjęć, kamera, mikrofon i rozpoznawanie mowy. `NSLocationWhenInUseUsageDescription` wymagany w zgłoszeniu ITMS-90683 jest obecny i niepusty.
- Raport zbiorczy `ios-0518-delivery-summary.json`, konfiguracja `ios-0518-config-verification.json`, IPA `fwp-ios-0445769-artifact-check.json`, upload `fwp-ios-0445769-publishing-result.json`, stan Apple `fwp-apple-0518-status.json` — katalog artefaktów 2026-11-02. Brak wpisu processing w logu Codemagic nie oznacza błędu: przy samym uploadzie potwierdzeniem przetworzenia jest API Apple.
- Zakres: build, podpis/profil, pakiet, upload i dostępność wewnętrzna. **Rozmowy, mikrofonu i interfejsu nie testowano na fizycznym iPhonie.** Zewnętrzna beta/App Store nie zostały wydane tą operacją. Backend `7461cba` działa już produkcyjnie; jego poprawka wyszukiwania nie wymaga dodatkowej zmiany binarki.

## Automatyczne wyszukiwanie i źródła w rozmowie — 2026-11-02

- Rzeczywisty test pytania o aktualne wydanie/status ISO 9606-1 wykazał błąd: wyszukiwanie znalazło dwa źródła i odczytało dokument, ale końcowa synteza została odrzucona jako `model_reference_marker` (link lub własne oznaczenie w tekście modelu). Pierwszy przebieg wirtualny `matrix-y6s04w2mxncma` zakończył się FAILURE i poprawnym komunikatem `unverified`; sprzątanie HTTP200/ok.
- Backend **`7461cba44208994e3b5beca03db80c85df3d1e55`** wyjaśnia teraz modelowi, że odnośniki i numerację tworzy aplikacja z `evidence_ids`, również gdy pytanie prosi o link. Walidator, kontrola dowodów i źródeł pozostają bez zmian. **534 testy backendu PASS, 0 błędów/pominięć**, log `research-link-rendering-backend-tests.log`. Aktualne koszty wejścia są nadal liczone z rzeczywistego promptu i schematu; każda płatna ścieżka zachowuje rezerwację budżetu oraz brak automatycznych ponowień.
- Railway **`8d6b078d-7a31-4f40-83bd-c7c6f933368d` SUCCESS** (2026-11-02T02:54:12.477Z), ten sam istniejący serwis. Poprawka działa z obecnym APK **0.5.18**, bez zmiany kodu klienta lub pliku wydania.
- **Test po poprawce PASS**: `matrix-zmwtwg4wuq5va`, wirtualny MediumPhone.arm / Android15 API35 / PL, jeden testcase / zero błędów i pominięć / 24 s. Brak żądania AI przed zgodą; jedno rzeczywiste żądanie czatu automatycznie wywołało wyszukiwanie. Odpowiedź `verified_sources` została pokazana w panelu, a w bieżącej rozmowie otwarto dialog oficjalnego źródła ISO. Treść metadanych porównano z [publicznym katalogiem ISO](https://www.iso.org/standard/54936.html), nie z pełnym tekstem normy. Logi nowego wdrożenia potwierdzają odczyt dokumentu i zaakceptowaną syntezę. [Test Lab](https://console.firebase.google.com/project/fitter-welder-pro/testlab/histories/bh.b011b172b6d018b9/matrices/9211610950601614396).
- Obejrzane kadry15/24/26 pokazują oczekiwanie, 27/28 dialog źródła z właściwym adresem i fragment odpowiedzi w tle. Test natywny sprawdził tekst odpowiedzi przed otwarciem dialogu. Brak FATAL EXCEPTION/Eflutter/ANR aplikacji. Sprzątanie obu instalacji HTTP200/ok; prywatne pliki usunięte. Raport `G:/Projekty/FitterWelderPro-artifacts/2026-11-02/research-qa-v2-virtual-verification.json`; surowe pliki `research-qa-v2-virtual-*`. Kod QA `0c635d5`, kod produkcyjny klienta zgodny `981c1a6`.
- Próba fizyczna `matrix-391mp3cqgb808` była INVALID/TEST_QUOTA_EXCEEDED z **zerem wykonań i żądań AI**. Skorzystano z dostępnej puli wirtualnej w tym samym projekcie, bez włączenia płatnych testów ani zmiany limitów. Wynik nie dowodzi wyszukiwania na fizycznym telefonie, dowolnej odpowiedzi technicznej, uruchomienia zewnętrznej przeglądarki, mikrofonu ani release AOT/R8. Jeden request dotyczy aplikacji mobilnej; backend może wykonać kilka ograniczonych wywołań modelu/narzędzi. Dokładny koszt nie jest udostępniony.

## Pierwsze użycie AI i sterowanie kalkulatorem — 2026-11-02

- Kod `0f32fd21741fd5094530cf236c3acc19bf794983` dodaje brakujący przycisk **Włącz AI** w małym panelu. Przyjęcie zgody wznawia pierwotne polecenie; cofnięcie zachowuje tekst i nie wywołuje AI. Blokada równoległych aktywacji zapobiega dwóm ekranom zgody/żądaniom; zmienione polecenie lub rozmowa wymagają ponownego wysłania. Ten sam przycisk działa w pełnym widoku.
- Nagłówek panelu dopasowuje wysokość do rzeczywistego tekstu. Test przy skali 1,8 wykrył i następnie potwierdził usunięcie obcinania nagłówka; przycisk jest przewijalny i ma pole dotyku >=48 dp.
- **Fizyczny Pixel 8 / Android15 / PL: PASS**, `matrix-ag9rm95dxv12a`, jedno native testcase / 0 błędów i pominięć / 12 s. Brak żądania AI przed zgodą; po zgodzie jedno rzeczywiste `/api/fitter/ai/assistant` HTTP200 z planem `tool.open` otworzyło rzeczywisty HeatInputScreen. Kolejne polecenie natywne ustawiło GTAW, EN, 24 V, 230 A, 150 mm/min i sprawność 0,6; odczyt rzeczywistego kalkulatora wyniósł 1,3248 kJ/mm (wyświetlane 1,32). Samo „otwórz” wywołało lokalne pytanie „Które narzędzie otworzyć?”, bez dodatkowego AI i bez zmiany modułu.
- Obejrzane kadry9/14/15 pokazują przycisk, pola kalkulatora i doprecyzowanie. Brak FATAL EXCEPTION/Eflutter/ANR aplikacji. Sprzątanie własnej instalacji HTTP200/ok; prywatny plik usunięty. [Test Lab](https://console.firebase.google.com/project/fitter-welder-pro/testlab/histories/bh.b011b172b6d018b9/matrices/4943715655835610889). Dowód `action-qa-verification.json` oraz surowe `action-qa-*` w katalogu artefaktów 2026-11-02. QA source `697b4d1`; późniejszy `2a3305b` zmienia tylko dokumentację.
- Zakres: jedna rzeczywista nawigacja modelu, **natywne** zmiany kalkulatora i lokalne doprecyzowanie w debug, bez atrap sieci/modelu/platformy. Nie dowodzi dowolnego sterowania, doprecyzowania przez model, mikrofonu ani działania tej ścieżki w release AOT/R8. Limity i rezerwacja budżetu serwera pozostały aktywne, automatycznych ponowień brak; dokładny koszt modelu nie jest udostępniony.
- Regresje kodu: 127 testów / 10 zestawów PASS; analiza zmienionych plików czysta. Czysty katalog wydania **0.5.18+37** (`e13ba58a6a129d86901d195368349903cd8c64f2`): **209 testów / 18 zestawów PASS, 0 błędów i pominięć**, 74,383 s; pełna analiza `No issues found`, 33,4 s. Raport `v0518-targeted-suite-summary.json`; logi `v0518-tests.log` i `v0518-analyze.log`. To selekcja związana ze zmianą UI/zgód/nawigacji/kalkulatora, a nie ponowiony pełny zestaw bieżącego źródła. Pełny poprzedni wynik 10 282 / 660 dotyczy `a60d4a8` (poniżej).
- **Podpisany APK 0.5.18 / 2037 arm64 GOTOWY**: `G:/Projekty/FitterWelderPro-artifacts/2026-11-02/FitterWelder-Pro-0.5.18-arm64.apk`, 39 161 553 B, SHA256 `a038c0320ac748988f570706ae51637bc60c90940fa84298b30ba988c36dfac5`. Poprawny certyfikat wydania `8cb31ad1…`, v2, brak debug i kodu testu diagnostycznego, zipalign16KB i pięć bibliotek ELF64 z LOAD>=16KB. Fizyczny runtime16KB nie był sprawdzany.
- `v0518-release-summary.json` łączy 209 selekcyjnych testów, pełną analizę, kontrolę binarki, oddzielny dowód akcji na urządzeniu oraz historyczny pełny wynik 0.5.17. AOT różni się od 0.5.17 (`v0518-aot-comparison.json`). Nowe UI jest w tym APK. Scenariusz akcji przeprowadzono w debug z kodem `0f32fd2`, nie bezpośrednio w release AOT/R8. Mikrofon pozostaje do sprawdzenia. iOS 0.5.18 (1083) jest gotowy w wewnętrznym TestFlight (szczegóły powyżej).

## Kontynuacje rozmowy — poprawka po teście urządzenia, 2026-11-02

- Test dwóch tur na Pixelu 8 wykrył, że „Czyli to zmierzona średnica w milimetrach?” po odpowiedzi o DN nie trafiało do ścieżki wiedzy. Kończyło się próbą interpretacji polecenia i pomocą offline, zamiast drugą odpowiedzią czatu z historią.
- Poprawiono rozpoznawanie kontynuacji PL/EN („czyli”, „więc”, „to znaczy”, „so”, „then”, „in other words”, „does that mean”, „you mean”). Bez znaku pytania wymagają istniejącej rozmowy. Jawne polecenia po łączniku zachowują ścieżkę działania; pytanie o znaczenie polecenia nie staje się jego wykonaniem.
- Nowy test ekranu odtwarza pytanie o DN i dalsze pytanie, sprawdza dokładną historię wysłaną do czatu oraz brak pytania o moduł. Regresje: **137 widocznych testów / 8 plików, 0 błędów i pominięć**, dodatkowo 22 ukryte zdarzenia cyklu testów; terminal `success:true`. Analiza trzech zmienionych plików: `No issues found`. Log `inference-followup-regressions.jsonl` i raport `inference-followup-regressions-summary.json` w katalogu artefaktów 2026-11-02.
- Dowód urządzenia PRZED poprawką: `matrix-1movuy01l05am`, [Test Lab](https://console.firebase.google.com/project/fitter-welder-pro/testlab/histories/bh.b011b172b6d018b9/matrices/5210637924530351844), terminal FAILURE. Stuknięcie i wpisanie drugiego pytania przeszły asercję. Jedno realne żądanie czatu HTTP200; dwie próby innych wywołań AI zablokowano przed transportem przez test. `aiRequests:3` w tym raporcie oznacza próby, nie trzy płatne żądania. Obejrzany kadr28 pokazuje oznaczoną pomoc offline. Sprzątanie HTTP200/ok; prywatny plik instalacji usunięty.
- Wcześniejsze dwie próby testu dwóch tur też zakończyły się FAILURE: pierwsza ujawniła brak oczekiwania na gotowy formularz, druga pusty tekst po symulowanym wpisywaniu. Poprawiono sam test (oczekiwanie, realne stuknięcie, asercja tekstu). Obie wysłały tylko pierwsze żądanie i potwierdziły sprzątanie. Pełna historia w README gałęzi `qa/device-assistant-0516`.
- **Poprawka routingu potwierdzona na fizycznym Pixelu 8** w buildzie diagnostycznym z kodem `8841175`: `matrix-3ok1lk295wgnx`, terminal SUCCESS, jeden testcase / zero błędów i pominięć, 12 s. Dwa rzeczywiste żądania czatu HTTP200, dokładna poprzednia wymiana w drugim żądaniu, obie odpowiedzi na ekranie. Obejrzany kadr14 pokazuje „Nie. DN nie jest zmierzoną średnicą…”, bez pytania o moduł i bez pomocy offline. Sprzątanie HTTP200/ok, prywatny plik usunięty; brak FATAL EXCEPTION/Eflutter/ANR aplikacji. [Test Lab](https://console.firebase.google.com/project/fitter-welder-pro/testlab/histories/bh.b011b172b6d018b9/matrices/6635781266232247469). Raport `conversation-fixed-qa-verification.json`; kod QA `aee1118`, aktualna gałąź QA `5de5371` (później tylko dokumentacja).
- Wynik obejmuje tę konkretną rozmowę tekstową w debug, bez atrap modelu/sieci/platformy. Nie dowodzi mikrofonu, dowolnej rozmowy, sterowania modułami przez model ani rozmowy w release AOT/R8. APK 0.5.16 nie zawiera poprawki. Wersja 0.5.17+36 (`a60d4a8`) przeszła pełną weryfikację w czystym katalogu wydania; podpisany APK jest gotowy (szczegóły poniżej). Żaden test urządzenia nie pozostaje aktywny.

## Pełne testy wersji 0.5.17 — 2026-11-02

Kod `a60d4a8df57b1d08327b34417ca77b6ddab96792`, czysty katalog `G:/Projekty/FitterWelderPro-release-0.5.17`.

- Pełne `flutter test --no-pub --concurrency=4 --reporter json`: **10 282 widoczne testy / 660 zestawów, 0 błędów i pominięć**, terminal `success:true`, 850,788 s. Wszystkie pliki testowe katalogu `test` jawnie przekazane do uruchomienia; bez diagnostycznego `integration_test` w produkcyjnym pakiecie.
- Pełne `flutter analyze --no-pub`: **No issues found**, 27,2 s.
- Raport `G:/Projekty/FitterWelderPro-artifacts/2026-11-02/v0517-full-suite-summary.json`; zapis `v0517-tests.log`; analiza `v0517-analyze.log`. Są to lokalne testy z atrapami platformy/sieci. Osobny dowód rzeczywistej rozmowy na urządzeniu znajduje się powyżej.
- Podpisany **APK 0.5.17 / 2036 arm64 GOTOWY**: `G:/Projekty/FitterWelderPro-artifacts/2026-11-02/FitterWelder-Pro-0.5.17-arm64.apk`, 39 161 549 B, SHA256 `4330b2e0d3c6ac5742056a6dfa7487f5b55590240e24eafcdc821a4ad6326204`. Pakiet `com.startklaar.fitterwelder`, poprawny certyfikat wydania `8cb31ad1…`, podpis v2, brak debug, zipalign 16 KB i pięć bibliotek ELF64 z poprawnymi segmentami LOAD >=16 KB. Brak markerów diagnostycznych i zależności integration_test w paczce wydania. Fizycznego urządzenia z rozmiarem strony 16 KB nie testowano.
- Artefakt AOT różni się od 0.5.16 (`v0517-aot-comparison.json`). Raport `v0517-release-summary.json` łączy pełne testy, analizę, kontrolę binarki i oddzielny dowód diagnostycznej rozmowy na urządzeniu. Release APK nie był testowany tym scenariuszem rozmowy; iOS 0.5.17 nie uruchamiano.

## Pełna weryfikacja wcześniejszego kodu — 2026-11-02

Kod aplikacji: `f0c8b8376d3dd6b0c613d504470bde6a93b7f641`.

- Pełne `flutter test --no-pub --reporter json`: **10 267 testów zaliczonych, 660 zestawów, 0 błędów**, zakończenie `success: true`, 298,083 s.
- Pełne `flutter analyze --no-pub`: **No issues found**, 35,0 s. Log: `full-analyze-f0c8b83.log` w katalogu artefaktów poniżej.
- Przebieg obejmuje poprawki głosu i lokalnych obliczeń, zachowania kontekstu po błędach AI, treści pomocy oraz trafności wyszukiwania offline i rozróżnienia DN/NPS/NPSH.
- Raport maszynowy: `G:/Projekty/FitterWelderPro-artifacts/2026-11-02/full-suite-f0c8b83-summary.json`; surowy zapis: `full-suite-f0c8b83.jsonl` w tym samym katalogu.
- Testy uruchomiono na Windows, z atrapami wywołań platformowych i sieciowych. Wynik nie dowodzi poprawności dowolnej odpowiedzi AI, aktualności całej wiedzy technicznej ani działania mikrofonu na fizycznym telefonie.
- APK **0.5.16 (2035)**: automatyczny test na fizycznym Pixelu 8 / Android 15 / PL zakończył się powodzeniem (`matrix-3vlr480ryihjb`, jedna próba, 134 s). W logu brak FATAL EXCEPTION, błędów Fluttera i ANR aplikacji. Obejrzane kadry obejmują listę projektów, pomoc formularza i walidację brakującej średnicy. Nie potwierdza to rozmowy AI ani mikrofonu. [Wynik Test Lab](https://console.firebase.google.com/project/fitter-welder-pro/testlab/histories/bh.b011b172b6d018b9/matrices/6021048068351313166).
- Osobny **build diagnostyczny** oparty na 0.5.16 przeszedł test rzeczywistej odpowiedzi AI na fizycznym Pixelu 8: jedno żądanie HTTP200, odpowiedź widoczna na ekranie i sprzątanie HTTP200/ok; jeden testcase, zero błędów i pominięć. [Test Lab](https://console.firebase.google.com/project/fitter-welder-pro/testlab/histories/bh.b011b172b6d018b9/matrices/7979772547584698356). Kod testu jest na osobnej gałęzi `qa/device-assistant-0516`; wynik nie obejmuje mikrofonu, wielu tur ani zachowania rozmowy w release AOT/R8.
- iOS **0.5.15 (1082)**: ostatnia potwierdzona kontrola Apple z 2026-11-01T23:54:24Z wykazała `VALID`, wewnętrznie `IN_BETA_TESTING`, zewnętrznie `READY_FOR_BETA_SUBMISSION`. Zgłoszenie zewnętrznej bety odrzucono limitem zgłoszeń (422). Ta binarka nie zawiera późniejszych zmian kontekstu/pomocy/offline.
- Osobny [raport rzeczywistych zapytań backendu](docs/audits/2026-11-02-live-assistant.md) opisuje trzy odpowiedzi AI, ich ograniczenia i kolejne poprawki wyszukiwania.

Poniższy raport z 2026-06-16 jest archiwalny. Jego liczby, lista brakujących testów i wersje narzędzi opisują ówczesny stan; nie stanowią oceny aktualnego kodu.

---


**Data audytu:** 2026-06-16
**Cel biznesowy:** mniej błędów → lepsze oceny w sklepach i niższy churn → wyższy przychód.
**Zakres tej tury:** wyłącznie DIAGNOZA (`flutter analyze` + `flutter test`). Kod aplikacji NIE był zmieniany.

---

## 1. Wynik na zielono (TL;DR)

| Kontrola | Wynik |
|---|---|
| `flutter analyze` | ✅ **No issues found** (44.9 s) |
| `flutter test` | ✅ **All tests passed** — 171 testów w 16 plikach |
| `print(` w `lib/` | ✅ 0 (brak logów debugowych w produkcji) |
| Realne znaczniki TODO/FIXME/HACK | ✅ 0 (jedyny trafiony „XXXX" to fallback nicku) |
| Wersja toolchain | Flutter 3.38.7 (stable) • Dart 3.10.7 |

**Wniosek:** baza jest zdrowa statycznie — żadnych błędów ani ostrzeżeń kompilatora/lintera, pełna logika obliczeniowa (kalkulatory, parsery, katalogi) przetestowana. To dobra wiadomość dla ocen: rdzeń liczący (cut list, ISO parser, prefab, harmonogramy rur) ma siatkę bezpieczeństwa.

**Ale** — przy 146 plikach w `lib/` (49 ekranów, 25 serwisów) testy pokrywają głównie czystą logikę. Najbardziej „crashogenne" warstwy (sieć, PDF, AI, paywall) nie mają testów. Tam siedzi realne ryzyko 1-gwiazdkowych recenzji. Poniżej priorytety napraw nakierowane na stabilność, oceny i konwersję.

---

## 2. Sygnały do uwagi (z analizy statycznej, nie-blokujące)

Brak błędów/ostrzeżeń, ale w kodzie są celowo wyciszone linty — każdy to potencjalny dług:

| Plik | Wyciszenie | Ryzyko |
|---|---|---|
| `lib/screens/iso_notebook_screen.dart:4314, 4353` | `// ignore: deprecated_member_use` → `SemanticsService.announce(...)` | **Średnie** — deprecated API. Przy kolejnym podbiciu Fluttera może zniknąć i zerwać build / dostępność. |
| `lib/screens/material_list_screen.dart:71` | `// ignore: unused_field` | Niskie — martwy kod, do usunięcia. |
| `lib/services/iso_parser.dart:75` | `// ignore: text_direction_code_point_in_literal` | Niskie — celowe (obsługa znaków RTL/Unicode w parserze). Zostawić. |
| 9 plików (ekrany + `help_entries.dart`) | `// ignore_for_file: prefer_const_constructors` | Niskie — kosmetyka/mikro-perf. Wyłącza lint dla całego pliku. |

---

## 3. Luki w pokryciu testami (główne źródło ryzyka)

171 testów to dużo, ale rozkładają się nierówno. **Przetestowane** (pure logic, świetnie): `cut_calculator`, `iso_parser`, `prefab_engine`, `unit_parser`, `bar_nesting`, `cut_packing_service`, `orbital_tig`, `tungsten`, `pipe_schedules`, `sanitary_tube`, `support_spacing`, `heat_tint`, `elbow_takeouts`, `premium_status`, `welder_identity`, `rolling_offset` + smoke test home menu.

**Serwisy BEZ testów (15):**
`ai_chat_service`, `api_client`, `auth_service`, `backend_service`, `chat_service`, `component_classification`, `flange_catalog`, `help_search`, `iso_pdf_export`, `iso_scanner_ai`, `jobs_service`, `material_catalog`, `material_list_builder`, `pdf_export_service`, `saddle_template`.

**Ekrany:** 49 ekranów, a testy widgetów obejmują tylko 2 (`widget_test` smoke + `rolling_offset`). Ścieżki sieciowe, eksport PDF, AI-scan i paywall nie są weryfikowane automatycznie.

---

## 4. Propozycje napraw — priorytetyzowane pod przychód

> Kolejność = wpływ na oceny/konwersję × prawdopodobieństwo awarii. To rekomendacje; wdrożenie w osobnej turze (to zadanie = diagnoza).

### P0 — Stabilność warstwy sieciowej (największy wpływ na oceny)
Awarie sieci to najczęstsza przyczyna 1★. Dziś `api_client`, `backend_service`, `chat_service`, `ai_chat_service` nie mają żadnych testów.
- **Akcja:** dodać testy jednostkowe na: brak sieci / timeout / HTTP 500 / niepoprawny JSON → aplikacja pokazuje komunikat, **nie crashuje**. Mockować `http.Client`.
- **Dlaczego płaci:** monter często pracuje offline (hala, plac budowy). Czytelny fallback zamiast wysypki = utrzymany użytkownik zamiast odinstalowania + złej recenzji.

### P0 — Eksport PDF (paying users)
`pdf_export_service` i `iso_pdf_export` bez testów. Eksport to funkcja, dla której monter płaci (raporty WPQR, listy cięć, izometryki).
- **Akcja:** test generujący PDF dla pustych / skrajnych danych (0 pozycji, bardzo długie nazwy, znaki Unicode/PL) — ma nie rzucać wyjątku.
- **Dlaczego płaci:** crash przy eksporcie = bezpośrednia utrata zaufania klienta premium → zwrot/churn.

### P1 — Usunąć deprecated API zanim zerwie build
`SemanticsService.announce` (2×) jest deprecated.
- **Akcja:** zastąpić rekomendowanym odpowiednikiem (np. `SemanticsService.announce` → kanał `Semantics`/`announce` wg aktualnego API Fluttera) i usunąć `// ignore`.
- **Dlaczego płaci:** chroni przed nagłym zerwaniem buildu iOS na Codemagic przy następnym SDK bump → brak przestoju w wydaniach.

### P1 — Podbicie krytycznych zależności (zgodność z Androidem 14/15)
`flutter analyze` zgłosił **43 paczki z nowszymi, niekompatybilnymi wersjami**. Krytyczne pod stabilność na nowych telefonach:
- `file_picker 8.0.7 → 11.0.2` (major) — poprawki photo-picker / scoped storage na Android 14/15.
- `share_plus 9.0.0 → 13.1.0` (major) — naprawy crashy share-sheet.
- `sqflite` / `sqflite_common_ffi` — drobne bump (stabilność bazy lokalnej = dane montera).
- `flutter_lints 5 → 6` — nowsze reguły wyłapią więcej zanim trafi do użytkownika.
- **Akcja:** podbić w osobnej gałęzi + przejść pełny `flutter test` i smoke na realnym urządzeniu (major bumpy mają breaking changes).
- **Dlaczego płaci:** crash na nowym Samsungu/Pixelu = recenzja „nie działa na moim telefonie". Aktualne pluginy = mniej takich raportów.

### P2 — Test ścieżki płatności (bezpośrednio konwersja/przychód)
Logika `premium_status` jest przetestowana, ale **ekran paywall i flow zakup/restore — nie**.
- **Akcja:** test widgetu `premium_screen`: poprawne renderowanie planów, stan po zakupie, działanie „Przywróć zakupy".
- **Dlaczego płaci:** zepsuty paywall = 100% utraconej sprzedaży na tej ścieżce. To najwyższy ROI z testów.

### P3 — Higiena (niski priorytet, szybkie)
- Usunąć `unused_field` w `material_list_screen.dart:71` (martwy kod).
- Rozważyć włączenie `prefer_const_constructors` (usunąć `ignore_for_file` z 9 plików, dodać `const`) — mikro-optymalizacja renderu + spójność.

---

## 5. Komendy do odtworzenia audytu

```bash
flutter analyze        # oczekiwane: No issues found
flutter test           # oczekiwane: All tests passed (171)
flutter pub outdated   # szczegóły przeterminowanych 43 paczek
```

---

### Podsumowanie dla właściciela
Aplikacja przechodzi diagnozę **bez błędów i bez ostrzeżeń**, a cały rdzeń obliczeniowy jest objęty testami — to fundament dobrych ocen. Największe ukryte ryzyko (a więc i największy potencjał wzrostu ocen/przychodu) leży **poza** logiką liczącą: w warstwie sieciowej, eksporcie PDF i paywall, które dziś nie mają automatycznych testów, oraz w przeterminowanych pluginach mogących crashować na najnowszych Androidach. Rekomendacje P0–P2 adresują dokładnie te punkty.
