# FitterWelder Pro — AUDYT CZĘŚCIOWY

Data: 2026-08-30. Pełny audyt pozostaje nieukończony.
Raport rozdziela dowody testowe, naprawione usterki i brakującą weryfikację.
Nie usunięto żadnego modułu. Zakres inwentaryzacji: publiczne klasy Screen
w lib/screens oraz lib/modules/*/ui i klasy Page w lib/features (rejestr
uprawnień spawacza, Biblioteka WPS), nie każdy wewnętrzny serwis aplikacji.

## Podsumowanie manifestu

Moduły: 64

| Status | Liczba |
|---|---:|
| unverified | 46 |
| passed | 17 |
| simplify | 0 |
| broken | 0 |
| domainReview | 1 |

`passed` oznacza wyłącznie zakres wskazanego dowodu, nie certyfikację całego
modułu, wszystkich danych wejściowych ani poprawności branżowej. `unverified`
oznacza brak pełnego dowodu scenariusza, nie potwierdzony błąd. `domainReview`
wymaga rozstrzygnięcia pojęć domenowych. `broken` i `simplify` są zarezerwowane
dla udokumentowanych usterek i problemów obsługi; zerowe liczniki nie dowodzą
ich nieobecności w niesprawdzonych funkcjach.

## Inwentaryzacja i dowody

Tabela zachowuje statusy, scenariusze i dowody źródłowego manifestu bez
podnoszenia statusu na podstawie renderowania. Wspólny smoke test to
`test/audit/module_smoke_test.dart`: 64 ekrany renderowane offline przy
skali tekstu 1,3 oraz 7 kontroli przekrojowych. Nie zastępuje scenariuszy
biznesowych. Puste pole dowodu niżej oznacza brak dowodu scenariusza, mimo
przejścia renderowania. W Task 6 doprecyzowano wyłącznie opisy, bez zmian
statusów: pipe-slope dotyczy 1%/10 m = 100 mm, elbow-takeout testu danych
(nie wyświetlania), a heat-input, saddle, orbital TIG i tungsten dokładnych
wejść lub próbkowania istniejącego testu. Saddle i orbital TIG sprawdzają
własności wyników, a nie zgodność z zatwierdzonym projektem/WPS.

| ID | Punkt wejścia | Plik | Kategoria | Ryzyko | Status | Scenariusz | Dowód |
|---|---|---|---|---|---|---|---|
| `ai-chat` | AiChatScreen | lib/screens/ai_chat_screen.dart | ai | high | unverified | Użytkownik wysyła pytanie o spawanie i otrzymuje odpowiedź bez uruchamiania płatnej funkcji. | Brak dowodu scenariusza |
| `bolt-torque` | BoltTorqueScreen | lib/screens/bolt_torque_screen.dart | fitter | safetyCritical | unverified | Śruba M16 klasy 8.8 zwraca moment dokręcania w Nm. | Brak dowodu scenariusza |
| `certificate-edit` | CertificateEditPage | lib/features/qualification/certificate_edit_page.dart | welder | high | passed | Nowy certyfikat (nr PL-99, procesy 141, 135, t 1,5–6 mm, BW) trafia do bazy; zakres grubości 8–2 mm (min > max) nie jest zapisywany. | test/features/qualification_pages_test.dart: formularz: nowy certyfikat trafia do bazy<br>test/features/qualification_pages_test.dart: formularz: min > max — nie zapisuje<br>test/audit/module_smoke_test.dart: CertificateEditPage renderuje przy skali tekstu 1,3 |
| `certificate-register` | CertificateRegisterPage | lib/features/qualification/certificate_register_page.dart | welder | high | passed | Certyfikat ISO 9606-1 z egzaminem sprzed 7 miesięcy ma status „przeterminowane”; wpis potwierdzenia 6-miesięcznego zapisuje dzisiejszą datę i zdejmuje ten status. | test/features/qualification_pages_test.dart: certyfikat po terminie: status i wpis potwierdzenia<br>test/audit/module_smoke_test.dart: CertificateRegisterPage renderuje przy skali tekstu 1,3 |
| `chat` | ChatScreen | lib/screens/chat_screen.dart | social | medium | unverified | Zalogowany użytkownik otwiera rozmowę i widzi historię wiadomości. | test/audit/module_smoke_test.dart: Ponów wykonuje drugie wywołanie Chat i pokazuje zwrócony pokój |
| `component-library` | ComponentLibraryScreen | lib/screens/component_library_screen.dart | project | medium | unverified | Użytkownik filtruje bibliotekę komponentów po średnicy 100 mm. | Brak dowodu scenariusza |
| `consent` | ConsentScreen | lib/screens/consent_screen.dart | account | high | unverified | Użytkownik akceptuje wymagane zgody przed użyciem aplikacji. | Brak dowodu scenariusza |
| `coupon-log` | CouponLogScreen | lib/screens/coupon_log_screen.dart | account | medium | unverified | Użytkownik widzi historię wykorzystanych kuponów. | Brak dowodu scenariusza |
| `cut-list-summary` | CutListSummaryScreen | lib/screens/cut_list_summary_screen.dart | project | high | unverified | Projekt z trzema odcinkami wyświetla podsumowanie listy cięcia. | Brak dowodu scenariusza |
| `dn-mm` | DnMmScreen | lib/screens/dn_mm_screen.dart | fitter | medium | unverified | DN 100 zwraca odpowiadającą wartość w milimetrach. | Brak dowodu scenariusza |
| `elbow-takeout` | ElbowTakeoutScreen | lib/screens/elbow_takeout_screen.dart | fitter | high | passed | Dane kolana 90 stopni LR DN 100 zawierają take-out 152 mm. | test/audit/fitter_calculations_audit_test.dart: kolano 90° LR DN100 ma take-out 152 mm |
| `fitter-menu` | FitterMenuScreen | lib/screens/fitter_menu_screen.dart | fitter | low | unverified | Użytkownik otwiera menu narzędzi montera. | test/audit/module_smoke_test.dart: FitterMenuScreen renderuje przy skali tekstu 1,3 |
| `fitter` | FitterScreen | lib/screens/fitter_screen.dart | fitter | low | unverified | Użytkownik otwiera główny ekran montera. | test/audit/module_smoke_test.dart: FitterScreen renderuje z istniejącym projektem przy skali 1,3 |
| `fitter-tools` | FitterToolsScreen | lib/screens/fitter_tools_screen.dart | fitter | low | unverified | Użytkownik wybiera kalkulator z zestawu narzędzi montera. | Brak dowodu scenariusza |
| `heat-input` | HeatInputScreen | lib/screens/heat_input_screen.dart | welder | safetyCritical | passed | 12 V, 100 A, 100 mm/min, GTAW wyświetla 0,43 kJ/mm; prędkość 0 i -1 jest odrzucana. | test/audit/welder_calculations_audit_test.dart: GTAW 0,432 kJ/mm (0,43 w UI) oraz odrzucenie prędkości 0 i -1 |
| `heat-photos` | HeatPhotosScreen | lib/screens/heat_photos_screen.dart | project | medium | unverified | Użytkownik dodaje zdjęcie numeru wytopu do komponentu. | Brak dowodu scenariusza |
| `heat-tint` | HeatTintScreen | lib/screens/heat_tint_screen.dart | welder | high | passed | Ekran oznacza wartości O2 jako orientacyjne, a specyfikację projektu lub WPS jako wiążące. | test/audit/welder_calculations_audit_test.dart: heat tint jest oznaczony jako porada orientacyjna z wiążącym WPS |
| `help` | HelpScreen | lib/screens/help_screen.dart | document | low | unverified | Wyszukanie hasła TIG pokazuje odpowiednią pomoc. | Brak dowodu scenariusza |
| `home` | HomeScreen | lib/screens/home_screen.dart | start | medium | unverified | Użytkownik otwiera ekran startowy i przechodzi do dostępnego modułu. | Brak dowodu scenariusza |
| `hydrotest` | HydrotestScreen | lib/screens/hydrotest_screen.dart | fitter | safetyCritical | passed | Ciśnienie projektowe powyżej zakresu ekranu jest odrzucane bez wyniku ciśnienia testowego. | test/audit/welder_calculations_audit_test.dart: 2001 bar pokazuje błąd zakresu i nie tworzy wyniku |
| `iso-notebook` | IsoNotebookScreen | lib/screens/iso_notebook_screen.dart | document | high | unverified | Użytkownik otwiera zapisany notatnik ISO projektu. | Brak dowodu scenariusza |
| `iso-scanner` | IsoScannerScreen | lib/screens/iso_scanner_screen.dart | ai | high | unverified | Użytkownik wybiera obraz ISO i widzi bezpieczny stan funkcji skanowania. | Brak dowodu scenariusza |
| `job-add` | JobAddScreen | lib/screens/job_add_screen.dart | social | medium | unverified | Użytkownik wprowadza ofertę pracy z tytułem i lokalizacją. | Brak dowodu scenariusza |
| `jobs` | JobsScreen | lib/screens/jobs_screen.dart | social | medium | unverified | Użytkownik przegląda listę ofert pracy. | test/audit/module_smoke_test.dart: Ponów wykonuje drugie wywołanie Jobs i pokazuje zwróconą ofertę |
| `legal` | LegalScreen | lib/screens/legal_screen.dart | document | medium | unverified | Użytkownik otwiera politykę prywatności w aplikacji. | test/audit/module_smoke_test.dart: LegalScreen renderuje politykę prywatności przy skali 1,3 |
| `material-list` | MaterialListScreen | lib/screens/material_list_screen.dart | project | high | unverified | Projekt z odcinkami wyświetla listę materiałową z ilościami. | Brak dowodu scenariusza |
| `new-cut-list-project` | NewCutListProjectScreen | lib/screens/new_cut_list_project_screen.dart | project | medium | unverified | Użytkownik zakłada projekt listy cięcia z nazwą. | Brak dowodu scenariusza |
| `new-project` | NewProjectScreen | lib/screens/new_project_screen.dart | project | medium | unverified | Użytkownik tworzy nowy projekt spawalniczy. | Brak dowodu scenariusza |
| `onboarding-name` | OnboardingNameScreen | lib/screens/onboarding_name_screen.dart | start | low | unverified | Nowy użytkownik zapisuje swoje imię w onboardingu. | Brak dowodu scenariusza |
| `orbital-tig` | OrbitalTigScreen | lib/screens/orbital_tig_screen.dart | welder | safetyCritical | passed | Estimator orbitalnego TIG dla 50,8 × 1,65 mm zwraca cztery skończone dodatnie poziomy prądu. | test/audit/welder_calculations_audit_test.dart: cztery skończone dodatnie poziomy prądu orbitalnego TIG |
| `passivation` | PassivationScreen | lib/screens/passivation_screen.dart | welder | high | passed | Ekran oznacza pasywację jako przewodnik procesowy, a kartę produktu i specyfikację projektu jako wiążące. | test/audit/welder_calculations_audit_test.dart: passivation jest oznaczone jako przewodnik nienormatywny |
| `pipe-route-calculator` | PipeRouteCalculatorScreen | lib/screens/pipe_route_calculator_screen.dart | fitter | high | unverified | Trasa z dwoma odcinkami zwraca całkowitą długość rurociągu. | Brak dowodu scenariusza |
| `pipe-schedule` | PipeScheduleScreen | lib/screens/pipe_schedule_screen.dart | fitter | high | unverified | NPS 2 Schedule 40 pokazuje grubość ścianki i średnicę wewnętrzną. | Brak dowodu scenariusza |
| `pipe-slope` | PipeSlopeScreen | lib/screens/pipe_slope_screen.dart | fitter | high | passed | Spadek 1 procent na 10 m zwraca różnicę wysokości 100 mm. | test/audit/fitter_calculations_audit_test.dart: spadek 1% na 10 m daje 100 mm |
| `pre-weld-checklist` | PreWeldChecklistScreen | lib/screens/pre_weld_checklist_screen.dart | welder | safetyCritical | unverified | Spawacz odhacza komplet warunków przed rozpoczęciem spawania. | Brak dowodu scenariusza |
| `premium` | PremiumScreen | lib/screens/premium_screen.dart | account | high | unverified | Użytkownik widzi plan premium bez inicjowania płatności. | test/audit/module_smoke_test.dart: PremiumScreen renderuje offline bez uruchomienia płatności |
| `profile` | ProfileScreen | lib/screens/profile_screen.dart | account | medium | passed | Istniejący user_profile_v1 odtwarza polskie imię i nazwisko bez utraty znaków. | test/audit/data_integrity_audit_test.dart: UserProfileService odczytuje istniejący user_profile_v1 |
| `project-components` | ProjectComponentsScreen | lib/screens/project_components_screen.dart | project | high | unverified | Projekt wyświetla przypisane komponenty i ich numery wytopu. | Brak dowodu scenariusza |
| `projects` | ProjectsScreen | lib/screens/projects_screen.dart | project | medium | passed | Edycja przeżywa ponowne otwarcie, a usunięcie i Cofnij atomowo obejmują projekt, segmenty, zdjęcia i numery wytopów. | test/audit/data_integrity_audit_test.dart: edycja projektu i CUT segmentu przeżywa ponowne otwarcie bazy<br>test/audit/data_integrity_audit_test.dart: usunięcie projektu atomowo usuwa tylko jego dane zależne<br>test/audit/data_integrity_audit_test.dart: błąd ograniczenia cofa niepełne usunięcie projektu<br>test/audit/data_integrity_audit_test.dart: snapshot Cofnij odtwarza projekt i wszystkie zależności<br>test/audit/data_integrity_audit_test.dart: ProjectsScreen deleguje usunięcie i Cofnij wyłącznie do atomowego API |
| `quick-converter` | QuickConverterScreen | lib/screens/quick_converter_screen.dart | fitter | medium | unverified | 25,4 mm konwertuje się na 1 cal. | Brak dowodu scenariusza |
| `register` | RegisterScreen | lib/screens/register_screen.dart | account | high | unverified | Użytkownik podaje poprawny e-mail i hasło do rejestracji. | Brak dowodu scenariusza |
| `rolling-offset` | RollingOffsetScreen | lib/screens/rolling_offset_screen.dart | fitter | high | unverified | Dwa przesunięcia osi wyliczają długość rozwinięcia. | Brak dowodu scenariusza |
| `saddle-cut` | SaddleCutScreen | lib/screens/saddle_cut_screen.dart | fitter | safetyCritical | unverified | Rura odgałęźna 60 mm na kolektorze 114 mm wylicza profil siodła. | Brak dowodu scenariusza |
| `saddle-template` | SaddleTemplateScreen | lib/screens/saddle_template_screen.dart | fitter | safetyCritical | passed | Szablon siodła 200/100 mm przy 45 stopniach zawiera 73 punkty o skończonych, nieujemnych i symetrycznych głębokościach. | test/audit/fitter_calculations_audit_test.dart: saddle jest symetryczny, skończony i nieujemny |
| `sanitary-tube` | SanitaryTubeScreen | lib/screens/sanitary_tube_screen.dart | fitter | high | unverified | Rura sanitarna 38 mm zwraca średnicę i grubość ścianki. | Brak dowodu scenariusza |
| `scan-review` | ScanReviewScreen | lib/screens/scan_review_screen.dart | document | high | unverified | Użytkownik przegląda wynik rozpoznania ISO przed zapisem projektu. | Brak dowodu scenariusza |
| `segment-builder` | SegmentBuilderScreen | lib/screens/segment_builder_screen.dart | project | high | passed | Zapisany CUT 896 mm oraz poprawiona wartość ISO segmentu przeżywają ponowne otwarcie bazy. | test/audit/data_integrity_audit_test.dart: edycja projektu i CUT segmentu przeżywa ponowne otwarcie bazy |
| `support-config` | SupportConfigScreen | lib/screens/support_config_screen.dart | fitter | high | unverified | Średnica i medium zwracają maksymalny rozstaw podpór. | Brak dowodu scenariusza |
| `tungsten` | TungstenScreen | lib/screens/tungsten_screen.dart | welder | high | passed | Dobór wolframu DC zwraca elektrodę pokrywającą prądy od 15 do 400 A sprawdzone co 0,5 A. | test/audit/welder_calculations_audit_test.dart: pasma wolframu pokrywają 15-400 A co 0,5 A bez luk |
| `tutor` | TutorScreen | lib/screens/tutor_screen.dart | document | low | unverified | Użytkownik otwiera lekcję z instrukcją użycia modułu. | Brak dowodu scenariusza |
| `weld-journal` | WeldJournalScreen | lib/screens/weld_journal_screen.dart | welder | high | unverified | Aktywny filtr ekranu przekazuje dokładnie ten sam zbiór do integracji CSV i PDF. | Brak dowodu scenariusza |
| `welder-identity-setup` | WelderIdentitySetupScreen | lib/screens/welder_identity_setup_screen.dart | account | medium | unverified | Spawacz zapisuje identyfikator do podpisywania parametrów. | Brak dowodu scenariusza |
| `welder-menu` | WelderMenuScreen | lib/screens/welder_menu_screen.dart | welder | low | unverified | Użytkownik otwiera menu modułów spawacza. | test/audit/module_smoke_test.dart: WelderMenuScreen renderuje przy skali tekstu 1,3 |
| `welder-pipes` | WelderPipesScreen | lib/screens/welder_pipes_screen.dart | welder | medium | unverified | Użytkownik otwiera narzędzia spawalnicze dla rur. | test/audit/module_smoke_test.dart: WelderPipesScreen renderuje przy skali tekstu 1,3 |
| `welder-tanks` | WelderTanksScreen | lib/screens/welder_tanks_screen.dart | welder | medium | unverified | Użytkownik otwiera narzędzia spawalnicze dla zbiorników. | test/audit/module_smoke_test.dart: WelderTanksScreen renderuje przy skali tekstu 1,3 |
| `welder-tools` | WelderToolsScreen | lib/screens/welder_tools_screen.dart | welder | low | unverified | Użytkownik wybiera kalkulator z zestawu narzędzi spawacza. | Brak dowodu scenariusza |
| `wps-edit` | WpsEditPage | lib/features/wps/wps_edit_page.dart | welder | high | passed | WPS bez numeru nie jest zapisywana; WPS-7 z energią liniową 0,4–1,1 kJ/mm zapisuje się z konwencją EN. | test/features/qualification_pages_test.dart: formularz WPS: bez numeru nie zapisze<br>test/features/qualification_pages_test.dart: formularz WPS: zakres energii liniowej zapisany z konwencją<br>test/audit/module_smoke_test.dart: WpsEditPage renderuje przy skali tekstu 1,3 |
| `wps-library` | WpsLibraryPage | lib/features/wps/wps_library_page.dart | welder | high | passed | Import JSON ze schowka dodaje WPS-141-01 rev. B (z nowym identyfikatorem) do listy; tekst, który nie jest WPS, daje komunikat i nic nie dodaje. | test/features/qualification_pages_test.dart: import JSON ze schowka dodaje WPS do listy<br>test/features/qualification_pages_test.dart: import czegoś, co nie jest WPS — komunikat, nic nie dodaje<br>test/audit/module_smoke_test.dart: WpsLibraryPage renderuje przy skali tekstu 1,3 |
| `welder-pipe-param-edit` | WelderPipeParamEditScreen | lib/modules/welder_pipe/ui/welder_pipe_param_edit_screen.dart | welder | high | unverified | Spawacz zapisuje parametry rury z prądem, napięciem i procesem. | Brak dowodu scenariusza |
| `welder-pipe-params-list` | WelderPipeParamsListScreen | lib/modules/welder_pipe/ui/welder_pipe_params_list_screen.dart | welder | high | passed | Migracja v3-v5 zachowuje lokalny rekord parametrów rury, a restart produkcyjnej bazy nie duplikuje danych startowych. | test/audit/data_integrity_audit_test.dart: migracja v3-v5 zachowuje rekord po restarcie produkcyjnej bazy |
| `tandem-calculator` | TandemCalculatorScreen | lib/modules/welder_tandem/ui/tandem_calculator_screen.dart | welder | safetyCritical | domainReview | Asymetryczny zestaw zachowuje inside/outside; mapowanie tych pól na lead/trail wymaga potwierdzenia domenowego. | test/audit/welder_calculations_audit_test.dart: asymetryczne 83/137 A nie jest zamieniane |
| `tandem-library` | TandemLibraryScreen | lib/modules/welder_tandem/ui/tandem_library_screen.dart | welder | medium | unverified | Użytkownik przegląda bibliotekę parametrów tandemowych. | Brak dowodu scenariusza |
| `tandem-menu` | TandemMenuScreen | lib/modules/welder_tandem/ui/tandem_menu_screen.dart | welder | low | unverified | Użytkownik otwiera menu modułu tandemowego TIG. | test/audit/module_smoke_test.dart: TandemMenuScreen renderuje przy skali tekstu 1,3 |
| `tandem-my-params` | TandemMyParamsScreen | lib/modules/welder_tandem/ui/tandem_my_params_screen.dart | welder | high | unverified | Użytkownik widzi własne zapisane parametry tandemowe. | Brak dowodu scenariusza |

## Naprawione usterki — nie są otwartym backlogiem

Poniższe naprawy pochodzą z bieżącej gałęzi audytu. Każda ma opis objawu
przed naprawą i regresję; wpisy nie obejmują wszystkich możliwych awarii.

| Naprawa | Objaw przed naprawą → sprawdzony wynik | Dowód testowy |
|---|---|---|
| Ułamki mieszane cali | `1 1/2 in` dawało null → 38,1 mm; mianownik zero odrzucony | test/audit/fitter_calculations_audit_test.dart: `1 in = 25.4 mm, a 1 1/2 in = 38.1 mm`, `ułamek cala z mianownikiem 0 jest odrzucany` |
| Walidacja heat input | Prędkość 0 przechodziła walidację → 0 i -1 odrzucane | test/audit/welder_calculations_audit_test.dart: `heat input rejects travel speed 0`, `heat input rejects travel speed -1` |
| Bilans rzazu | Rzaz dopisywany jako odcinek oraz pomijane cięcie odpadu → 3000+2000+900/6000 mm: 3 cięcia, rzaz 9 mm, użyte 5909 mm, reszta 91 mm | test/audit/welder_calculations_audit_test.dart: `rod optimizer preserves pieces and never returns negative remainder`, `rod optimizer keeps n-1 cuts for fully consumed stock`, `tracked rod plan keeps kerf out of its piece list` |
| Niewykonalny odcinek optymalizatora | 5998 mm przy sztandze 6000 mm i rzazie 3 mm znikało z planu; podsumowanie mogło zawierać Infinity → ArgumentError dla samego odcinka i zestawu 6000+5998+900 mm, bez zwracania niepełnego wyniku | test/audit/welder_calculations_audit_test.dart: `rod optimizer rejects infeasible 5998 mm piece`, `rod optimizer rejects mixed input containing infeasible piece` |
| Usunięcie projektu i Cofnij | Osobne usuwanie segmentów i niepełne Undo → transakcyjny snapshot/delete/restore projektu, segmentów, zdjęć i numerów wytopów | test/audit/data_integrity_audit_test.dart: `usunięcie projektu atomowo usuwa tylko jego dane zależne`, `błąd ograniczenia cofa niepełne usunięcie projektu`, `snapshot Cofnij odtwarza projekt i wszystkie zależności` |
| Ponowne otwarcie bazy | Singleton oddawał zamknięty uchwyt (`database_closed`) → produkcyjne otwarcie po migracji v3–v5 zachowuje rekordy i seedy | test/audit/data_integrity_audit_test.dart: `migracja v3-v5 zachowuje rekord po restarcie produkcyjnej bazy` |
| Cykl życia projektów | `setState` po zamknięciu ekranu → kontrola mounted przed zmianą stanu i po odczycie | test/audit/module_smoke_test.dart: `ProjectsScreen nie aktualizuje stanu po zamknięciu podczas load`; dodatkowy kontrakt źródłowy kolejności zabezpieczeń |
| Start listy parametrów rur | Odczyt inherited zależności w initState → ich pobranie dopiero w obsługiwanej gałęzi błędu | test/audit/module_smoke_test.dart: `WelderPipeParamsListScreen renderuje przy skali tekstu 1,3` |

DAO delete/restore jest testowane na prawdziwym SQLite z wymuszeniem rollbacku
przez trigger. Podłączenie usunięcia/Cofnij przez ekran sprawdza kontrakt
źródłowy, nie pełna interakcja gestem i SnackBarem. Test migracji uruchamia
produkcyjne onUpgrade v3–v5, a potem zwykłe ponowne otwarcie aktualnej bazy;
nie udowadnia ponownego wykonania callbacku migracji na bazie v5.

## Potwierdzone otwarte usterki

W wykonanym zakresie nie pozostała odtworzona, nienaprawiona usterka z testem
reprodukującym. Nie nadajemy nieznanym zachowaniom etykiety „błąd P0/P1”.
To nie jest zapewnienie, że aplikacja jest wolna od usterek. Ostrzeżenia
blokady SQLite w istniejących testach regresji wymagają osobnej diagnostyki;
sam warning bez potwierdzonej utraty danych nie jest dowodem błędu P0.

## Kolejka brakującej weryfikacji — osobna od usterek

P0–P3 poniżej oznaczają pilność zdobycia dowodu, nie potwierdzoną wagę błędu:
P0 — bezpieczeństwo/CUT; P1 — pozostałe wysokie ryzyko (wyniki, dane,
konto/AI/płatności); P2 — średnie ryzyko obsługi i przepływów; P3 — niższe
ryzyko nawigacji/pomocy. W każdej grupie należy wykonać dokładny scenariusz
z tabeli, dodać niezależne oczekiwania i przypadki błędne, a dopiero potem
zmienić status. Nie kupować ani nie publikować w ramach testu.

### P0 — weryfikacja

- [unverified] `bolt-torque`: Śruba M16 klasy 8.8 zwraca moment dokręcania w Nm. (ryzyko: safetyCritical).
- [unverified] `cut-list-summary`: Projekt z trzema odcinkami wyświetla podsumowanie listy cięcia. (ryzyko: high).
- [unverified] `iso-scanner`: Użytkownik wybiera obraz ISO i widzi bezpieczny stan funkcji skanowania. (ryzyko: high).
- [unverified] `pre-weld-checklist`: Spawacz odhacza komplet warunków przed rozpoczęciem spawania. (ryzyko: safetyCritical).
- [unverified] `saddle-cut`: Rura odgałęźna 60 mm na kolektorze 114 mm wylicza profil siodła. (ryzyko: safetyCritical).
- [unverified] `scan-review`: Użytkownik przegląda wynik rozpoznania ISO przed zapisem projektu. (ryzyko: high).

### P1 — weryfikacja

- [unverified] `ai-chat`: Użytkownik wysyła pytanie o spawanie i otrzymuje odpowiedź bez uruchamiania płatnej funkcji. (ryzyko: high).
- [unverified] `consent`: Użytkownik akceptuje wymagane zgody przed użyciem aplikacji. (ryzyko: high).
- [unverified] `iso-notebook`: Użytkownik otwiera zapisany notatnik ISO projektu. (ryzyko: high).
- [unverified] `material-list`: Projekt z odcinkami wyświetla listę materiałową z ilościami. (ryzyko: high).
- [unverified] `pipe-route-calculator`: Trasa z dwoma odcinkami zwraca całkowitą długość rurociągu. (ryzyko: high).
- [unverified] `pipe-schedule`: NPS 2 Schedule 40 pokazuje grubość ścianki i średnicę wewnętrzną. (ryzyko: high).
- [unverified] `premium`: Użytkownik widzi plan premium bez inicjowania płatności. (ryzyko: high).
- [unverified] `project-components`: Projekt wyświetla przypisane komponenty i ich numery wytopu. (ryzyko: high).
- [unverified] `register`: Użytkownik podaje poprawny e-mail i hasło do rejestracji. (ryzyko: high).
- [unverified] `rolling-offset`: Dwa przesunięcia osi wyliczają długość rozwinięcia. (ryzyko: high).
- [unverified] `sanitary-tube`: Rura sanitarna 38 mm zwraca średnicę i grubość ścianki. (ryzyko: high).
- [unverified] `support-config`: Średnica i medium zwracają maksymalny rozstaw podpór. (ryzyko: high).
- [unverified] `weld-journal`: Aktywny filtr ekranu przekazuje dokładnie ten sam zbiór do integracji CSV i PDF. (ryzyko: high).
- [unverified] `welder-pipe-param-edit`: Spawacz zapisuje parametry rury z prądem, napięciem i procesem. (ryzyko: high).
- [unverified] `tandem-my-params`: Użytkownik widzi własne zapisane parametry tandemowe. (ryzyko: high).

### P2 — weryfikacja

- [unverified] `chat`: Zalogowany użytkownik otwiera rozmowę i widzi historię wiadomości. (ryzyko: medium).
- [unverified] `component-library`: Użytkownik filtruje bibliotekę komponentów po średnicy 100 mm. (ryzyko: medium).
- [unverified] `coupon-log`: Użytkownik widzi historię wykorzystanych kuponów. (ryzyko: medium).
- [unverified] `dn-mm`: DN 100 zwraca odpowiadającą wartość w milimetrach. (ryzyko: medium).
- [unverified] `heat-photos`: Użytkownik dodaje zdjęcie numeru wytopu do komponentu. (ryzyko: medium).
- [unverified] `home`: Użytkownik otwiera ekran startowy i przechodzi do dostępnego modułu. (ryzyko: medium).
- [unverified] `job-add`: Użytkownik wprowadza ofertę pracy z tytułem i lokalizacją. (ryzyko: medium).
- [unverified] `jobs`: Użytkownik przegląda listę ofert pracy. (ryzyko: medium).
- [unverified] `legal`: Użytkownik otwiera politykę prywatności w aplikacji. (ryzyko: medium).
- [unverified] `new-cut-list-project`: Użytkownik zakłada projekt listy cięcia z nazwą. (ryzyko: medium).
- [unverified] `new-project`: Użytkownik tworzy nowy projekt spawalniczy. (ryzyko: medium).
- [unverified] `quick-converter`: 25,4 mm konwertuje się na 1 cal. (ryzyko: medium).
- [unverified] `welder-identity-setup`: Spawacz zapisuje identyfikator do podpisywania parametrów. (ryzyko: medium).
- [unverified] `welder-pipes`: Użytkownik otwiera narzędzia spawalnicze dla rur. (ryzyko: medium).
- [unverified] `welder-tanks`: Użytkownik otwiera narzędzia spawalnicze dla zbiorników. (ryzyko: medium).
- [unverified] `tandem-library`: Użytkownik przegląda bibliotekę parametrów tandemowych. (ryzyko: medium).

### P3 — weryfikacja

- [unverified] `fitter-menu`: Użytkownik otwiera menu narzędzi montera. (ryzyko: low).
- [unverified] `fitter`: Użytkownik otwiera główny ekran montera. (ryzyko: low).
- [unverified] `fitter-tools`: Użytkownik wybiera kalkulator z zestawu narzędzi montera. (ryzyko: low).
- [unverified] `help`: Wyszukanie hasła TIG pokazuje odpowiednią pomoc. (ryzyko: low).
- [unverified] `onboarding-name`: Nowy użytkownik zapisuje swoje imię w onboardingu. (ryzyko: low).
- [unverified] `tutor`: Użytkownik otwiera lekcję z instrukcją użycia modułu. (ryzyko: low).
- [unverified] `welder-menu`: Użytkownik otwiera menu modułów spawacza. (ryzyko: low).
- [unverified] `welder-tools`: Użytkownik wybiera kalkulator z zestawu narzędzi spawacza. (ryzyko: low).
- [unverified] `tandem-menu`: Użytkownik otwiera menu modułu tandemowego TIG. (ryzyko: low).

### Rozstrzygnięcia domenowe

- [domainReview] `tandem-calculator`: Asymetryczny zestaw zachowuje inside/outside; mapowanie tych pól na lead/trail wymaga potwierdzenia domenowego. Priorytet weryfikacji P0; bez automatycznego utożsamiania inside/outside z lead/trail.

## Granice audytu i dalsza rozbudowa

- Konto i synchronizacja na żywo między urządzeniami pozostają niezweryfikowane;
  lokalny profil oraz test rejestracji nie dowodzą synchronizacji ani auth.
- Społeczność, czat i oferty: testy retry korzystają z kontrolowanych loaderów;
  nie sprawdzono serwera na żywo, moderacji, prywatności ani publikowania.
- Asystent AI, wejście/odpowiedź głosowa i zapis parametrów do profilu po
  potwierdzeniu wymagają osobnej implementacji lub weryfikacji istniejących
  ścieżek. Ten etap nie uruchamiał płatnego AI i nie dodał modułu głosowego.
- ISO: brak walidacji OCR i list CUT na prawdziwych rysunkach referencyjnych.
  Skanera nie odblokowano produkcyjnie; bez tej walidacji nie można obiecać
  bezbłędnej listy cięć. Istniejące testy czystych obliczeń nie zastępują OCR.
- Weld Journal: zgodność aktywnego filtra ekranu z oboma eksportami CSV/PDF
  pozostaje niezweryfikowana; test samego helpera eksportu nie wystarcza.
- Premium renderuje offline, ale zakup, powrót z Checkout i webhook nie są
  pokryte tym audytem. Nie wykonywano realnych operacji pieniężnych.
- Smoke nie jest pełnym audytem dostępności: semantyka obejmuje główne CTA
  trzech formularzy; nie przetestowano każdego kontrolera ani urządzenia.
- Szersze uproszczenie UX, profesjonalny wygląd czatu i instrukcje krok po
  kroku pozostają kolejnym etapem. Ten etap stabilizuje istniejącą bazę.

## Odtworzenie raportu i bramki weryfikacji

```text
dart run tool/audit/render_audit_report.dart --output docs/audits/2026-08-30-module-audit.md
flutter analyze --no-pub
flutter test --no-pub
git diff --check
```

Raport jest deterministycznie generowany z manifestu; nie uruchamia testów
ani nie nadaje sobie statusu PASS. Dokładne wyniki końcowego uruchomienia
kontroler zapisuje w raporcie wykonania Task 6. Zielony zestaw testów nie
zamyka brakujących scenariuszy wymienionych powyżej.
