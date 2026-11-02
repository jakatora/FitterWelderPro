# QA-COCKPIT — FitterWelderPro

## Wyszukiwanie DN50 otwiera właściwy rozmiar — 2026-11-02

- Pełne oznaczenie rozmiaru, np.DN50/dn50/DN 50, daje teraz bezpośrednio wynik tabeliDN i przekazuje wybrany rozmiar do ekranu. To samo działa po kliknięciu wiersza i po zatwierdzeniu wyszukiwania klawiaturą; nie trzeba ponownie wpisywać rozmiaru w module.
- Rozpoznawane są wyłącznie pełne oznaczeniaDN z1–4cyframi, istniejące w bieżącym katalogu `kNpsTable`. Nieznany DN, znak minus, ułamek lub dodatkowe słowa nie otrzymują zgadywanego rozmiaru. Zwykłe wyszukiwanie zachowuje swoją ścieżkę. Nie zmieniano wartości tabel ani interpretacji średnicyOD/NPS.
- `ToolSearchHit` przenosi niezmienne pola startowe wyniku; ekran główny przekazuje je zarówno przyEnter, jak i przezToolRow. Zwykłe wiersze bez pól zachowują dotychczasowe otwieranie. Działanie lokalne, bez wywołaniaAI lub zapisu danych użytkownika.
- Przed poprawką oba nowe testy rzeczywistegoHome FAILED (brak wynikuDN50/DN100). Końcowo **1632testy/5zestawów PASS**,0błędów/pominięć:62testy wyszukiwania/rejestru/Home21,494s i1570korpusu/wydajności routingu21,852s. RegresjePL/EN obejmują prawidłowe i nieprawidłowe oznaczenia oraz niezmienność pól. Home sprawdza zarówno otwarty ekran zinitialDn, jak i tekst pola50/100.
- Analiza5zmienionych plików:Noissuesfound9,3s. Dowody `G:/Projekty/FitterWelderPro-artifacts/2026-11-02/sized-dn-summary.json`, `sized-dn-before.jsonl`, `sized-dn-final.jsonl`, `sized-dn-router.jsonl`, `sized-dn-analyze.log`.
- Zakres dowodu: widgetyFlutter i logika naWindows, nie fizyczny telefon. Zmiana w źródłach po0.5.20; obecny APK/iOS1085 jeszcze jej nie zawierają. Brak nowego buildu, wdrożenia serwera lub wywołań płatnegoAI.

## Ponawianie odpowiedzi bez utraty szkicu — 2026-11-02

- Odtworzono rzeczywistą utratę nowego szkicu na pełnym ekranie rozmowy: po nieudanej odpowiedzi „Ponów” nadpisywało pole poprzednim pytaniem i czyściło je przy wysłaniu. Przed poprawką trzy przypadki tego ekranu FAILED; trzy kontrolne dla panelu na ekranie głównym już PASS. Rodzaje błędu:unavailable,offlineHelp,wyjątek transportu.
- Ponowienie przekazuje teraz poprzednie pytanie bezpośrednio do wysyłki, bez przepisywania edytora. Pole jest czyszczone tylko wtedy, gdy nadal zawiera właśnie wysyłany tekst. Nowy szkic nie jest dołączany do ponawianego pytania ani wysyłany automatycznie.
- Pełny ekran pozwala teraz edytować kolejne pytanie podczas oczekiwania naAI. Przycisk wysyłania i zatwierdzenie z klawiatury są wtedy nieaktywne; blokada w samej wysyłce i dotychczasowa ochrona przed dwukrotnym/starym ponowieniem pozostają.
- **55testów/3zestawy PASS**,0błędów/pominięć,26,350s: nowy `knowledge_retry_draft_test.dart` (6przypadków, oba widoki), istniejące rozmowy i widok historii. Nowe testy sprawdzają oryginalną treść ponowienia, nowy szkic przed i po odpowiedzi, edycję w trakcie, podwójne kliknięcie i brak dodatkowej wysyłki klawiaturą. Analiza dwóch zmienionych plików:Noissuesfound10,1s.
- Raport `G:/Projekty/FitterWelderPro-artifacts/2026-11-02/retry-draft-test-summary.json`, przed `retry-draft-before-both.jsonl`, końcowe `retry-draft-final-suite-v2.jsonl`, analiza `retry-draft-analyze.log`. Pierwsza próba poprawki zachowywała szkic, ale stary edytor był zablokowany podczas oczekiwania; końcowa zmiana umożliwia również edycję.
- Zakres: rzeczywiste widgetyFlutter naWindows, transportAI zastąpiony w testach. Bez nowego endpointu, automatycznych ponowień, zmiany budżetuAI lub działania na cudzych danych. To zmiana źródłowa po0.5.20; wydany APK/iOS1085 jeszcze jej nie zawierają. Nie wykonano nowego testu telefonu/mikrofonu ani nowego buildu.

## Krótsze wyjaśnienia wyników kalkulatora — 2026-11-02

- Backend `3b9ae09b9a516893dc69f5ae97cfd437c1c07f81`: rozmowa oparta wyłącznie na jawnym odczycie wyników masy rury, odsadzki lub spadku nie otrzymuje automatycznej stopki oWPS. Stopka pozostaje dla energii spawania, odpowiedzi przypisujących sobie fragmenty bazy technicznej, wyszukiwania zewnętrznego i starszego trybu odpowiedzi. Bez zmian publicznego kontraktu lub źródeł danych.
- Instrukcja modelu rozróżnia wewnętrzne ograniczenia od tekstu dla użytkownika: przy pytaniu o znaczenie wyświetlonych wartości podaje krótkie zdanie dla każdej wartości i kończy. Nie dopisuje rutynowej oceny udźwigu, certyfikatów ani ważenia. Pytania o te zagadnienia nadal wymagają odpowiedzi z brakującymi dowodami; ostrzeżenie o nakładających się kolanach i nieużytecznym CUT zachowano.
- **564 testy backendu PASS**,0błędów/pominięć,5,095s.9nowych przypadków sprawdza sześć odczytówPL/EN bez stopki oraz jej zachowanie dla energii, wiedzy technicznej i zwykłej rozmowy. Jedno wywołanie modelu, aktywna rezerwacja budżetu i brak automatycznych ponowień; większa instrukcja nadal jest objęta naliczaniem bajtówUTF8.
- Wdrożenie `9813478b-c197-4e82-8198-6930e0d7e455` SUCCESS2026-11-02T05:53:39.222Z. Dwa rzeczywiste zapytania po wdrożeniu:PL trzy masy → trzy zdania,5.541kg/m/5.541kg/szt./11.08kg, bez nieproszonych dopisków;EN energia →1.325kJ/mm z1.3248, współczynnik0.6 jako ustawienie kalkulatora, stopkaWPS zachowana. ObaHTTP200, citations[],calculator_context_usedtrue, cleanup200/ok i prywatne pliki usunięte.
- Pierwsza wersja usunęła stopkę deterministycznie, ale model nadal dodał uwagę o podnoszeniu; zachowano jako wynik częściowy, potem doprecyzowano instrukcję i wykonano nowy ograniczony test. Dowody `G:/Projekty/FitterWelderPro-artifacts/2026-11-02/answer-relevance-verification.json`, `answer-relevance-v2-live-native.json`, `answer-relevance-v2-live-heat.json`, log pełnych testów w tym samym katalogu.
- Zmiana serwera działa z APK0.5.20 bez nowego wydania. To rzeczywisty testHTTP/modelu, nie nowy test mikrofonu lub iPhone'a. Dwa przykłady nie stanowią gwarancji jakości każdej przyszłej odpowiedziAI.

## Podpisany APK 0.5.20 — rzeczywisty kalkulator offline, 2026-11-02

- **PASS: dokładnie udostępniony APK 0.5.20/2039**, bez przebudowania aplikacji lub dodawania kodu diagnostycznego. Zainstalowany SHA256 `3ff4675c87617ea5d4c6d4fd2e379335ac8314c3c28796d752b1c2fba3a22e6d`; test sprawdza brak flagi debug. Osobny natywny APK instrumentacji podpisano tym samym certyfikatem wydania; pomocniczego host APK nie używano do uruchomienia.
- Firebase Test Lab: wirtualny MediumPhone ARM64/API35/PL, `matrix-2isgs4zu4saaz` SUCCESS, 1 test / 0 błędów / 0 pominięć, 17 s + 3 s przetwarzania. Tryb samolotowy i brak aktywnej sieci potwierdzono przed startem i przy odczycie wyniku. Klawiatura wyszukuje „ciezar rury”, otwiera kalkulator i wpisuje OD60.3 / t3.91 / długość1000mm / ilość2 dla SS316/316L.
- Zrzut ekranu i semantyka rzeczywistego interfejsu potwierdzają **5.541kg/m, 5.541kg/szt. i 11.08kg łącznie**. Każde pole ma kontrolę dokładnej wpisanej wartości. Log: 0 FATAL EXCEPTION, 0 E/flutter, 0 ANR aplikacji. Własna instalacja testowa usunięta: HTTP200/ok; prywatny plik odzyskiwania usunięty. Bez zapytań AI i interakcji z publicznym czatem.
- Zachowano historię trzech nieudanych prób instrumentacji: brak biblioteki Kotlin w runnerze (0 testów), ACTION_SET_TEXT bez odświeżenia wyników oraz nieskuteczne Ctrl+A w polu liczbowym. Poprawiono wyłącznie projekt testowy; te wyniki nie dowodzą błędu produkcyjnego kalkulatora. Końcowy kod QA `a7cd8e79518a899ffdd1947502040583eebe6820`.
- Dowody: `G:/Projekty/FitterWelderPro-artifacts/2026-11-02/release-native-qa-v4-verification.json`, `release-native-qa-v4-calculator.png`, XML, log i nagranie w tym samym katalogu; historia `release-native-qa-attempt-history.json`. Podsumowanie wydania `v0520-release-summary.json` uzupełnione.
- Zakres jest wąski: ten przebieg **nie testuje rozmowy AI, mikrofonu, iOS ani fizycznego runtime16KB**. Nowsza poprawka DN/OD i podpowiedź asystenta `1b3adde` pozostają tylko w źródłach po0.5.20. Wydany APK i backend nie zostały zmienione.

## Wyszukiwanie DN/OD bez przypadkowych fragmentów słów — 2026-11-02

- Naprawiono dopasowanie krótkich kodów DN i OD w wyszukiwarce narzędzi oraz współdzielonym wyszukiwaniu nawigacji. „DN” nie pasuje już do środka „hardness”, a „OD” do „podpory”. Kody są dopasowywane jako pełne słowa lub kody z dołączonym oznaczeniem liczbowym w indeksowanym materiale. Zwykłe słowa zachowują dotychczasowe prefiksy i odmianę polską.
- Regresje PL/EN:8przypadków, przed zmianą6FAILED dlaDN/OD i2kontrolneAIpoprawne. ZachowaniaAI nie zmieniono. Po poprawce **1612testów/5zestawów PASS**,0błędów/pominięć,20,229s: wyszukiwarka, integralność rejestru, korpus poleceń asystenta, wydajność routingu, ekran główny.
- Podpowiedź pustego panelu asystenta pokazuje teraz krótkie pytanie oDN i polecenie obliczenia masy rury, z informacją o dopytywaniu, zamiast dominującego przykładu wieloetapowego rysowania. TreśćPL/EN; logika bez zmian.
- Test rzeczywistego widgetu ekranu głównego wpisujeOD iDN, sprawdza brak przypadkowych kafli i otwiera DnMmScreen z wyniku. To testFlutter naWindows, nie test fizycznego telefonu. Wzorce kompilowane raz, bez dodatkowych usług lub wywołańAI.
- Pełna analiza `flutter analyze --no-pub`: **No issues found**,90,3s; po zmianie treści podpowiedzi dodatkowo sprawdzono plik asystenta bez uwag. Logi `tool-acronyms-analyze.log` / `tool-acronyms-hint-analyze.log`.
- Raport `G:/Projekty/FitterWelderPro-artifacts/2026-11-02/tool-acronyms-summary.json`; surowe `tool-acronyms-before.jsonl` i `tool-acronyms-final-suite.jsonl`. Zmiana źródłowa po0.5.20; udostępnione APK0.5.20/iOS1085 jeszcze jej nie zawierają.

## Trafniejsze materiały kontekstu AI — aktualizacja serwera 2026-11-02

- Backend `3c98b354222a12f1b75be45d721403798bf37095` nie dołącza już automatycznie wszystkich pobranych fragmentów bazy do odpowiedzi rozmowy. Model wskazuje użyte sekcje po numerowanych identyfikatorach; serwer mapuje je wyłącznie na pobrane tytuły. Brak wskazania oznacza pustą listę, nigdy całą listę pobrań.
- Identyfikatory ujemne, ułamkowe, nieistniejące, tekstowe, powtórzone i nadmiarowe są odrzucane bez ponowienia modelu. Dopytania i żądania wyszukiwania nie mogą przypisywać sobie sekcji aplikacji. Klient otrzymuje ten sam publiczny format citations:string[], bez technicznych identyfikatorów. Starsza ścieżka bez conversation_mode zachowuje swój dotychczasowy kontrakt.
- **555 testów backendu PASS**,0błędów/pominięć,4,548s. Nowe testy wymuszają wybiórcze/puste wskazanie zamiast wszystkich4pobrań i odrzucanie wadliwych danych. Istniejące testy retrievalu nadal jawnie wskazują wszystkie pobrane sekcje, zachowując kontrolę ciągłości tematu i wyłączenia treści społecznościowych. Bramka budżetu, naliczenie rzeczywistego wejścia i maxRetries0 pozostają aktywne; nie dodano kolejnego wywołania modelu.
- Railway `620b4597-c1be-4f56-80ee-6a6d8d799dee` SUCCESS2026-11-02T04:55:51.814Z. Dwa ograniczone rzeczywiste zapytania HTTP/modelu po wdrożeniu: wyjaśnienie masy5,541kg/m/5,541kg/szt./11,08kg zachowało prawidłowe wartości i zwróciło pustą listę materiałów zamiast przypadkowych tematów; pytanie „Co oznacza DN na rurze?” zwróciło jedynie „DN — rozmiar nominalny rury / nominal pipe size”. Oba HTTP200/needs_clarification:false, bez ponowień.
- Obie własne instalacje DELETE200/ok, prywatne pliki usunięte. Raport `G:/Projekty/FitterWelderPro-artifacts/2026-11-02/knowledge-attribution-verification.json`, odpowiedzi `knowledge-attribution-live-native.json` / `knowledge-attribution-live-knowledge.json`, testy `knowledge-attribution-backend-tests-final.log`.
- Działa z obecnymi klientami rozmowy0.5.20 bez nowego APK/IPA. Zakres: realny serwer/model i testy kontraktu; nie wykonywano nowego testu interfejsu telefonu. Wskazanie sekcji pochodzi od modelu i nie jest niezależną weryfikacją wszystkich tez; zewnętrzne wyszukiwanie nadal ma osobny mechanizm dowodów. Dokładny koszt dostawcy nie jest udostępniony.

## iOS 0.5.20 (1085) — wewnętrzny TestFlight gotowy, 2026-11-02

- **Apple VALID / IN_BETA_TESTING**, potwierdzone2026-11-02T04:48:30.312211Z. Train0.5.20/build1085,ID `3f457a48-a8a2-407d-990b-77f006f5d0ae`,niewygasł. ExternalREADY_FOR_BETA_SUBMISSION,reviewnull; bez zgłoszenia zewnętrznej recenzji.
- Codemagic `6ae81411892fdbe7077f9d9c` /ios-upload/source `1c3bfc605e9387f2cb8ed6325347c354eeb00dc9`: wszystkie10krokówSUCCESS,2026-11-02T04:39:50.749Z–04:45:14.503Z. Ten sam kod co Android0.5.20. Persistent signing/SDK3.47.5/profil zachowane, bez modyfikacji certyfikatów, recenzji, grup testerów lub wcześniejszych buildów.
- IPA `G:/Projekty/FitterWelderPro-artifacts/2026-11-02/fwp-ios-6ae81411892fdbe7077f9d9c.ipa`,34979298B,SHA256 `7d2de076af26adef9819351eaba99f04d4a48b7bac03acb5d7f11f325ffcb2ba`; bundlecom.jakatora.fitterwelderpro/TeamB7J6A7R258/profilważnydo2027-07-10T14:57:03,debugfalse,CodeResourcesobecne. AppleVALID potwierdza przyjęcie i przetworzenie; lokalnieWindows nie wykonywano kryptograficznego codesignverify.
- Wszystkie5opisów uprawnień zgodne ze źródłem: lokalizacja, zdjęcia, kamera, mikrofon, rozpoznawanie mowy. App.framework zawiera markery nowych funkcji i nie zawiera markerów diagnostycznych; SHA256 `cfa82a1c3e17b584b30e2259eda55e88a6f395b79ef94cd6faf48df34472b23e`.
- Upload `UPLOAD SUCCEEDED with no errors`,tasks[],betaReviewAttemptedfalse; bez ponowienia uploadu podczas opóźnienia widoczności wApple. UploadedDate2026-11-01T20:46:54-08:00 =2026-11-02T04:46:54Z. Potwierdzenie przetworzenia pochodzi z APIApple, nie z kończącego wcześniej loguCI.
- Raport `ios-0520-delivery-summary.json`, IPA `fwp-ios-1c3bfc6-artifact-check.json`, upload `fwp-ios-1c3bfc6-publishing-result.json`, Apple `fwp-apple-0520-status.json` w katalogu artefaktów2026-11-02. Android `v0520-release-summary.json` wskazuje tę samą dostawę iOS. CHANGELOG uzupełniony o0.5.19/0.5.20.
- Zakres: build/pakiet/upload/przetworzenie/dostępność wewnętrzna. **Nie testowano fizycznego mikrofonu, schowka lub rozmowy na iPhonie.** To nie publikacja AppStore ani zewnętrznej bety; brak wysyłki email.

## Android 0.5.20 — wydanie z odczytem masy dla AI, 2026-11-02

- **APK0.5.20/2039 arm64 gotowy:** `G:/Projekty/FitterWelderPro-artifacts/2026-11-02/FitterWelder-Pro-0.5.20-arm64.apk`,39161553B,SHA256 `3ff4675c87617ea5d4c6d4fd2e379335ac8314c3c28796d752b1c2fba3a22e6d`. Źródło `1c3bfc605e9387f2cb8ed6325347c354eeb00dc9`, wersja0.5.20+39.
- Zawiera wspólną walidację masy rury dla formularza i asystenta(`5929d67`) oraz jawny odczyt widocznych danych i natywnych wyników do pytańAI(`ba2e567`). Nowe ciągi funkcji potwierdzono w libapp.so; AOT SHA256 `81912e7c35971181d0aaaf10249e6d356d32d79720765b490a1957b7e2c86991` różni się od0.5.19.
- Czysty worktree `G:/Projekty/FitterWelderPro-release-0.5.20`, canonicalcommittedlockSHA `b4be63098b21a8ddc447318b54259366aaecd6f2643266e51253999dc8f0a135`. **345testów/30zestawów PASS**,95,214s,0błędów/pominięć; pełna analiza Noissuesfound43,5s. To wybrane regresje głosu/rozmowy/zgód/nawigacji/kalkulatorów, nie pełny ponowiony zestaw bieżącego kodu.
- Releasebuild222,9s. Pakietcom.startklaar.fitterwelder,bezdebug,podpisv2/certwydania `8cb31ad1f1e00afe899d53dcb75e0b644b1594db166d79b1e78bf72da6f9dbb8`,zipalign16KB,pięć bibliotekELF64 zLOAD>=16KB,bezdiagnostycznychfixturemarkerów/testcode.
- `v0520-release-summary.json` łączy testy, analizę, kontrolę pakietu, markery nowych funkcji, porównanie AOT i oddzielny dowód UI. `fwp-1c3bfc6-arm64-android-release-artifact-check.json`, `v0520-targeted-suite-summary.json`, `v0520-aot-comparison.json` w katalogu artefaktów2026-11-02.
- Pełny przepływ kalkulator→AI był wcześniej potwierdzony na wirtualnym Androidzie w osobnym debugbuildzie z tym samym kodem funkcji(przed zmianą numeru wersji). Nie oznacza to testu rozmowy w releaseAOT/R8 ani fizycznego runtime16KB/mikrofonu/schowka. Brak wysyłki email i publikacji GooglePlay w tej operacji.

## Masa rury → pytanie AI: pełny przebieg interfejsu Android — 2026-11-02

- **PASS** `matrix-1u2kt3fkhy6lj`, wirtualny MediumPhone.arm / Android15 API35 / PL,1nativecase/0błędów/pominięć,16s +3s przetwarzania. Prawdziwy interfejs, backend i model, bez atrap platformy/sieci/modelu.
- Wpisane polecenie „Oblicz masę rury OD60,3mm ścianka3,91mm długość1m 316L ilość2” otworzyło właściwy kalkulator i lokalnie obliczyło5,541kg/m,5,541kg/sztukę,11,08kgłącznie. Zero żądańAI do tego momentu. Zwinęto panel i pokazano pełny wynik(kadr14).
- Pytanie o trzy widoczne masy uruchomiło rzeczywisty ekran zgody; zeroAI przed zgodą. Potem dokładnie1chatHTTP200 zawierał właściwe pola i wyniki3/3/2miejsca. Serwer potwierdził calculator_context_used:true; odpowiedź wyświetliła poprawne wartości i naturalne nazwy(kadr21), bez technicznych nazwJSON. Dane kalkulatora nie zmieniły się. Natywna historia miała przybliżenie5,54, ale AI użyło aktualnego odczytu5,541.
- QA źródło `5f3099d1a5ab1163a98e518a70bdb5f884e61180`; produkcyjny lib identyczny z `9babb9f`, backend `60fecd1`/wdrożenie `7dcd80f3-2d30-4162-9e4f-b5ff9e609bdb` SUCCESS sprawdzone przed testem. Analiza plików testu bez uwag. Diagnostyczne APK0.5.19/38 jest osobnym debugbuildem z nowszym kodem, a nie udostępnionym APK0.5.19/2038.
- Sprzątanie własnej instalacji DELETE200/ok; prywatny plik usunięty. ZeroFATAL EXCEPTION/Eflutter/ANR aplikacji. Raport `G:/Projekty/FitterWelderPro-artifacts/2026-11-02/pipe-weight-ui-qa-virtual-verification.json`, dane `pipe-weight-ui-qa-virtual-real-ui-report.json`, XML/log/wideo23,54s w tym samym katalogu.
- Zakres: jeden rzeczywisty przepływ UI na wirtualnym Androidzie. Nie dowodzi runtime releaseAOT/R8, fizycznego mikrofonu, schowka ani iOS. Nie wykonywano ponowień, nie zmieniano bramek budżetu i nie włączano płatnego TestLab; dokładny koszt dostawcy nie jest udostępniony. Kod tej funkcji jest już w wydaniu0.5.20 (raport powyżej).

## AI wyjaśnia rzeczywiste wyniki masy rury — 2026-11-02

- Kod `ba2e56741d0c7266ff547bf10ecca3cd20c472cd` dodaje jawny odczyt widocznych pól kalkulatora masy rury i natywnych wyników kg/m, kg/sztukę, kg łącznie. Wysyłane są wartości zaokrąglone tak jak na ekranie(3/3/2miejsca), nie ponowne obliczenia AI. Brak długości/ilości pozostaje brakiem; błędny formularz usuwa wszystkie wyniki z kontekstu. Zmiana zakładki nie udostępnia starej masy. Port nie czyta rekordów, notatek, tożsamości ani innych zakładek.
- Backend `fe2b4f8` rozszerza ścisły kontrakt Zod o pipe_weight; odrzuca prywatne/nieznane pola, złe wybory oraz niespójne wyniki przed modelem. `60fecd15394bfac7b2131493f60a270a65bb2636` dodatkowo nakazuje używanie naturalnych nazw zamiast technicznych pól JSON. Railway `7dcd80f3-2d30-4162-9e4f-b5ff9e609bdb` SUCCESS2026-11-02T04:23:15.936Z, ten sam istniejący serwis.
- **24 testyFlutter/4zestawy PASS**,14,653s; pełna analiza Noissuesfound21,4s. **539 testów backendu PASS**,0błędów/pominięć,8,310s. Pierwsza próba nowego testu backendu wykryła, że przypadki dopisano po teście wyczerpującym budżet; przeniesiono ten ostatni przypadek na koniec, zachowując blokadę budżetu i jej asercje.
- Rzeczywisty test produkcyjnego HTTP/modelu użył kontekstu przechwyconego z natywnego widgetu: OD60,3/ścianka3,91/długość1000/ilość2/316L →5,541kg/m,5,541kg/sztukę,11,08kgłącznie. Pierwszy HTTP200 prawidłowo wykorzystał dane, ale pokazał nazwyJSON; po zmianie instrukcji kolejny pojedynczy HTTP200 potwierdził czytelne nazwy i zgodne liczby. Oba zwróciły calculator_context_used:true/needs_clarification:false. Dwie własne instalacje DELETE200/ok, prywatne pliki usunięte; zero ponowień.
- Bramka budżetu przed płatnym modelem, rozliczenie rzeczywistego wejścia, limity urządzenia/IP i maxRetries0 pozostają aktywne. Nowa funkcja nie dodaje drugiego wywołania modelu do rozmowy. Dokładny koszt dostawcy nie jest udostępniony.
- Raport `pipe-weight-context-verification.json`, dane rozmów `pipe-weight-context-live.json` i `pipe-weight-context-live-v2.json`, logi testów i analizy w katalogu artefaktów2026-11-02. **Zakres:** natywny odczyt w teścieFlutter oraz osobny rzeczywisty HTTP/model; nie jest to dowód całej ścieżki na fizycznym telefonie. Nowy klient nie został jeszcze wydany w APK/iOS0.5.19; starsze wersje działają bez zmian z nowym serwerem.

## Spójna walidacja masy rury — 2026-11-02

- Naprawiono różnicę między formularzem ręcznym a asystentem. Ilość sztuk bez długości nie jest już ignorowana; formularz prosi o długość jednej sztuki albo usunięcie ilości. Po korekcie poprawny wynik wraca. Puste oba pola nadal pozwalają obliczyć wyłącznie kg/m, bez domyślnej długości lub ilości.
- Formularz przestrzega tego samego limitu całkowitej ilości co domena/asystent. Bardzo duże, ale skończone wymiary, których iloczyn przekracza zakres liczbowy, dają komunikat zamiast Infinity. Nie zostaje widoczny częściowy lub poprzedni wynik.
- Ręczne obliczenia i zastosowanie pól przez asystenta korzystają teraz z `domain/fitter/pipe_weight.dart`, zamiast utrzymywać osobną kopię wzoru w ekranie. Ceny/płatności i backend nie są zmieniane.
- Przed poprawką3nowe testy formularza FAILED; po poprawce **64 testy/6 zestawów PASS**,0błędów/pominięć,31,167s. Zakres: domena, formularz, umiejętność asystenta, interpretacja pól, kalkulatory montera i natywne kopiowanie/czyszczenie. Raport `pipe-weight-validation-summary.json`, surowe `pipe-weight-validation-before/after.jsonl` w katalogu artefaktów2026-11-02. To testyFlutter, bez dowodu runtime telefonu.
- Pełna analiza `flutter analyze --no-pub`: **No issues found**,26,5s; log `pipe-weight-validation-analyze-final.log`.
- Zmiana źródłowa po0.5.19; udostępnione APK0.5.19/iOS1084 jej jeszcze nie zawierają.

## iOS 0.5.19 (1084) — gotowe w wewnętrznym TestFlight, 2026-11-02

- **Apple VALID / IN_BETA_TESTING**, potwierdzone API2026-11-02T04:09:43.789245Z. Train0.5.19, build1084, ID `9608aab4-f0b9-4744-9a0b-cff0dfca67cf`, nie wygasł. Zewnętrzny stan READY_FOR_BETA_SUBMISSION; recenzji zewnętrznej bety nie zgłaszano.
- Codemagic `6ae80a8f0e82a88742700149` /workflowios-upload/source `67131d22880c0c49adff5ab296ea53caf4e8a22b`: wszystkie10kroków SUCCESS,2026-11-02T03:59:17.046Z–04:04:44.223Z. Kod aplikacji/testów/zasobów/iOS/zależności identyczny z Android0.5.19/source08cca66. Zawiera kopiowanie odpowiedzi ze źródłami i nowe komunikaty błędów głosu.
- IPA `G:/Projekty/FitterWelderPro-artifacts/2026-11-02/fwp-ios-6ae80a8f0e82a88742700149.ipa`,34980782B,SHA256 `b9dccafb60f9e65eece3852d2d361dd20c86fc9f1eb8ba0a216a6292595ec839`. Bundlecom.jakatora.fitterwelderpro/TeamB7J6A7R258,profilważnydo2027-07-10T14:57:03,debugfalse,CodeResourcesobecne. AppleVALID jest potwierdzeniem przyjęcia i przetworzenia pakietu; lokalnie naWindows nie wykonywano kryptograficznego codesignverify.
- W IPA sprawdzono wszystkie5opisów uprawnień: lokalizacja podczas użycia, zdjęcia, kamera, mikrofon, rozpoznawanie mowy. W App.framework potwierdzono ciągi nowych funkcji, brak markerów diagnostycznych; SHA256 `4f20a37749015e158415b79fa3af47207ab1a294ddf6c446a7db2990bcfbc09d`.
- Upload potwierdzony `UPLOAD SUCCEEDED with no errors`,tasks[],betaReviewAttemptedfalse. Po uploadzie API Apple nie pokazywało1084 przez kilka minut; bez ponownego buildu/uploadu doczekano jego widoczności. UploadDate2026-11-01T20:05:37-08:00 =2026-11-02T04:05:37Z. Potwierdzenie przetworzenia pochodzi z Apple, nie z kończącego wcześniej logu CI.
- Raport zbiorczy `ios-0519-delivery-summary.json`, kontrola IPA `fwp-ios-67131d2-artifact-check.json`, upload `fwp-ios-67131d2-publishing-result.json`, Apple `fwp-apple-0519-status.json` w katalogu artefaktów2026-11-02. Nie zmieniano certyfikatów, grup testerów, recenzji lub wcześniejszych buildów. Brak wysyłki email.
- Zakres: CI/build/pakiet/upload/przetworzenie/dostępność wewnętrzna. **Fizyczny mikrofon, schowek i rozmowa na iPhonie pozostają niezweryfikowane.** Nie jest to publikacja AppStore ani wydanie zewnętrznej bety.

## Android 0.5.19 — podpisany APK gotowy, 2026-11-02

- **APK0.5.19/2038 arm64 GOTOWY**: `G:/Projekty/FitterWelderPro-artifacts/2026-11-02/FitterWelder-Pro-0.5.19-arm64.apk`,39161553B, SHA256 `2773e20afa88ffac1838e6edf3c8a3c82b4c296118c23cc480a6a3314d5a002b`. Źródło `08cca669946b723507744bc86528c54045f7f028`, wersja źródłowa0.5.19+38.
- Zawiera lepszą obsługę błędów rozpoznawania mowy (`9446754`) i kopiowanie odpowiedzi z kontekstem/źródłami oraz oznaczeniem offline (`af83e35`). W skompilowanym libapp.so potwierdzono nowe ciągiPL/EN, nieobecne w0.5.18; AOT SHA256 `3f4759232e473891bdda4bc541372c01ebfab1207feba3829c57309f6e43377c` różni się od poprzedniego wydania.
- Czysty worktree `G:/Projekty/FitterWelderPro-release-0.5.19`, zależności z canonicalcommittedlockSHA `b4be63098b21a8ddc447318b54259366aaecd6f2643266e51253999dc8f0a135`. **260 testów/21 zestawów PASS**,79,223s,0błędów/pominięć. Wybrane zestawy obejmują głos, rozmowę, zgody, nawigację i kalkulatory; nie jest to pełny ponowiony zestaw bieżącego kodu.
- Pełna analiza **No issues found**,34,8s; release build204,1s. Pakiet `com.startklaar.fitterwelder`, bez debug, podpisv2/certyfikatwydania `8cb31ad1f1e00afe899d53dcb75e0b644b1594db166d79b1e78bf72da6f9dbb8`, zipalign16KB, pięć bibliotekELF64 zLOAD>=16KB. Brak integracyjnych fixturemarkerów/testcode.
- Raporty `v0519-release-summary.json`, `v0519-targeted-suite-summary.json`, `fwp-08cca66-arm64-android-release-artifact-check.json`, `v0519-aot-comparison.json`, `v0519-feature-markers.json` w katalogu artefaktów2026-11-02.
- Zakres: testyWindows i kontrola gotowej binarki. Fizyczny mikrofon/schowek oraz runtime16KB nie były w tej turze testowane. iOS0.5.19(1084) jest już gotowe w wewnętrznym TestFlight (raport powyżej). Backend bez zmian; bez wysyłki email lub publikacji sklepowej.

## Kopiowanie odpowiedzi z kontekstem i źródłami — 2026-11-02

- W bieżącej rozmowie i pełnym widoku czatu odpowiedzi mają przycisk **Kopiuj odpowiedź / Copy answer**. Kopiowany jest pełny tekst, kontekst i odnośniki ze źródeł; powtórzone odnośniki są pomijane. Pomoc offline zachowuje swoje oznaczenie również po skopiowaniu. Kopiowanie następuje wyłącznie po naciśnięciu przycisku, bez wysyłania wiadomości lub wywołania AI.
- Pole dotyku ma minimum48dp; przycisk jest zablokowany na czas obsługi schowka. Błąd schowka pozostawia zaznaczalny tekst i podaje sposób kontynuowania. Spóźniony wynik po wylogowaniu lub zamknięciu widoku nie pokazuje komunikatu w nowej sesji.
- **65 testów /3 zestawy PASS**, 0 błędów/pominięć, 23.716s: rozmowa, obsługa głosu i podstawowe przepływy asystenta. Raport `answer-copy-test-summary.json`, surowy `answer-copy-final-tests.jsonl` w katalogu artefaktów2026-11-02. Testy schowka używają platformowego handlera testowego; nie są dowodem schowka na fizycznym telefonie.
- Pełna analiza `flutter analyze --no-pub`: **No issues found**,25,7s; log `answer-copy-analyze.log`.
- Nowy przycisk nie wymaga uprawnień, dodatkowego pakietu ani backendu. Zmiana źródłowa po0.5.18; wcześniejsze APK0.5.18/iOS1083 jej nie zawierają.

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
