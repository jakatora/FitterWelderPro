enum AuditCategory {
  start,
  fitter,
  welder,
  project,
  document,
  social,
  account,
  ai
}

enum AuditRisk { low, medium, high, safetyCritical }

enum AuditStatus { unverified, passed, simplify, broken, domainReview }

class ModuleAuditEntry {
  final String id;
  final String entryPoint;
  final String sourcePath;
  final AuditCategory category;
  final AuditRisk risk;
  final AuditStatus status;
  final String scenario;
  final List<String> evidence;

  const ModuleAuditEntry({
    required this.id,
    required this.entryPoint,
    required this.sourcePath,
    required this.category,
    required this.risk,
    required this.status,
    required this.scenario,
    this.evidence = const [],
  });
}

const moduleManifest = <ModuleAuditEntry>[
  ModuleAuditEntry(
      id: 'ai-chat',
      entryPoint: 'AiChatScreen',
      sourcePath: 'lib/screens/ai_chat_screen.dart',
      category: AuditCategory.ai,
      risk: AuditRisk.high,
      status: AuditStatus.unverified,
      scenario:
          'Użytkownik wysyła pytanie o spawanie i otrzymuje odpowiedź bez uruchamiania płatnej funkcji.'),
  ModuleAuditEntry(
      id: 'bolt-torque',
      entryPoint: 'BoltTorqueScreen',
      sourcePath: 'lib/screens/bolt_torque_screen.dart',
      category: AuditCategory.fitter,
      risk: AuditRisk.safetyCritical,
      status: AuditStatus.unverified,
      scenario: 'Śruba M16 klasy 8.8 zwraca moment dokręcania w Nm.'),
  ModuleAuditEntry(
      id: 'certificate-edit',
      entryPoint: 'CertificateEditPage',
      sourcePath: 'lib/features/qualification/certificate_edit_page.dart',
      category: AuditCategory.welder,
      risk: AuditRisk.high,
      status: AuditStatus.passed,
      scenario:
          'Nowy certyfikat (nr PL-99, procesy 141, 135, t 1,5–6 mm, BW) trafia do bazy; zakres grubości 8–2 mm (min > max) nie jest zapisywany.',
      evidence: [
        'test/features/qualification_pages_test.dart: formularz: nowy certyfikat trafia do bazy',
        'test/features/qualification_pages_test.dart: formularz: min > max — nie zapisuje',
        'test/audit/module_smoke_test.dart: CertificateEditPage renderuje przy skali tekstu 1,3',
      ]),
  ModuleAuditEntry(
      id: 'certificate-register',
      entryPoint: 'CertificateRegisterPage',
      sourcePath: 'lib/features/qualification/certificate_register_page.dart',
      category: AuditCategory.welder,
      risk: AuditRisk.high,
      status: AuditStatus.passed,
      scenario:
          'Certyfikat ISO 9606-1 z egzaminem sprzed 7 miesięcy ma status „przeterminowane”; wpis potwierdzenia 6-miesięcznego zapisuje dzisiejszą datę i zdejmuje ten status.',
      evidence: [
        'test/features/qualification_pages_test.dart: certyfikat po terminie: status i wpis potwierdzenia',
        'test/audit/module_smoke_test.dart: CertificateRegisterPage renderuje przy skali tekstu 1,3',
      ]),
  ModuleAuditEntry(
      id: 'chat',
      entryPoint: 'ChatScreen',
      sourcePath: 'lib/screens/chat_screen.dart',
      category: AuditCategory.social,
      risk: AuditRisk.medium,
      status: AuditStatus.unverified,
      scenario:
          'Zalogowany użytkownik otwiera rozmowę i widzi historię wiadomości.',
      evidence: [
        'test/audit/module_smoke_test.dart: Ponów wykonuje drugie wywołanie Chat i pokazuje zwrócony pokój',
      ]),
  ModuleAuditEntry(
      id: 'component-library',
      entryPoint: 'ComponentLibraryScreen',
      sourcePath: 'lib/screens/component_library_screen.dart',
      category: AuditCategory.project,
      risk: AuditRisk.medium,
      status: AuditStatus.unverified,
      scenario:
          'Użytkownik filtruje bibliotekę komponentów po średnicy 100 mm.'),
  ModuleAuditEntry(
      id: 'consent',
      entryPoint: 'ConsentScreen',
      sourcePath: 'lib/screens/consent_screen.dart',
      category: AuditCategory.account,
      risk: AuditRisk.high,
      status: AuditStatus.unverified,
      scenario: 'Użytkownik akceptuje wymagane zgody przed użyciem aplikacji.'),
  ModuleAuditEntry(
      id: 'cone-layout',
      entryPoint: 'ConeLayoutPage',
      sourcePath: 'lib/features/cone_layout/cone_layout_page.dart',
      category: AuditCategory.fitter,
      risk: AuditRisk.medium,
      status: AuditStatus.passed,
      scenario:
          'Lej D 600 / d 200 zewn., t 4, H 400: Dm 596 / dm 196, R 666,3, r 219,1, θ 161°, blacha 1314,4 × 630,2 mm; H 300 → R 537,2; 2 części → θ 80,5°, 861,1 × 499,1 mm; d ≥ D, puste H, t ≥ d/2 — komunikat bez wyniku; stożek mimośrodowy z tworzącą pionową: e 200, tworzące 400 / 565,7; kwadrat–koło 600×400/Ø300/H400: szew M3–9 427,2, krawędzie 1984 / 929,9 mm; R ≈ 19,9 m → tabela rzędnych, PDF zablokowany; szablon 1:1 w kaflach A4/A3.',
      evidence: [
        'test/domain/fitter/cone_development_test.dart: D 1000 / d 400 zewn., t 6, H 600 → R 1111,33, r 440,51, θ 161,00°',
        'test/domain/fitter/cone_development_test.dart: niezmienniki: łuki = obwody średnie, R − r = tworząca = √(H² + Δr²)',
        'test/domain/fitter/cone_development_test.dart: e = 0 daje to samo co wzór analityczny',
        'test/domain/fitter/transition_development_test.dart: niezmienniki: krawędź prostokąta = 2(A + B), krawędź kołowa = π·D',
        'test/features/cone_layout/cone_layout_page_test.dart: lej D 600 / d 200 zewn., t 4, H 400 → R 666,3; H 300 → 537,2',
        'test/features/cone_layout/cone_layout_page_test.dart: błędne wejście → komunikat, bez wyniku i bez PDF',
        'test/features/cone_layout/cone_layout_page_test.dart: udostępnianie tekstu i PDF przez wstrzyknięte funkcje',
      ]),
  ModuleAuditEntry(
      id: 'cooling-time',
      entryPoint: 'CoolingTimePage',
      sourcePath: 'lib/features/cooling_time/cooling_time_page.dart',
      category: AuditCategory.welder,
      risk: AuditRisk.safetyCritical,
      status: AuditStatus.passed,
      scenario:
          'Q 1,0 kJ/mm, T0 100 °C, d 20 mm, ścieg wypełniający czołowej (F3 0,9): przepływ 3D, t8/5 = 6,0 s, w oknie 5–15 s; T0 20 °C → 4,8 s, za krótko; d 10 mm → 2D, 10,2 s; okno max 8 s → za długo. Przykład MIGAL (30 V, 450 A, 350 mm/min, MAG, d 20, T0 150 °C) → 2D, 18,16 s; dla okna 5–15 s przy T0 100 °C Q = 0,836–2,023 kJ/mm.',
      evidence: [
        'test/features/cooling_time/cooling_time_page_test.dart: zmiana T0, grubości i okna zmienia wynik i werdykt',
        'test/features/cooling_time/cooling_time_page_test.dart: złącze teowe w 2D: wynik jako przedział',
        'test/features/cooling_time/cooling_time_page_test.dart: Q z U, I, v i procesu — przez heat_input.dart',
        'test/features/cooling_time/cooling_time_page_test.dart: wąski ekran, tekst ×1,3, wersja EN — bez wyjątków',
        'test/domain/welding/cooling_time_test.dart: przykłady ze źródeł: MIGAL 2D: 30 V, 450 A, 350 mm/min, MAG, d 20, T0 150 → 18,16 s',
        'test/domain/welding/cooling_time_test.dart: przykłady ze źródeł: Rontescu 2008: TIG 15 V, 153 A, 140 mm/min, d 10, T0 200 → ~10 s',
        'test/domain/welding/cooling_time_test.dart: wzory zał. D: grubość przejściowa d_t: Q 1, T0 20 °C → 14,66 mm',
        'test/domain/welding/cooling_time_test.dart: rozwiązanie odwrotne: Q z rozwiązania trafia w okno — dla każdego rodzaju spoiny',
      ]),
  ModuleAuditEntry(
      id: 'coupon-log',
      entryPoint: 'CouponLogScreen',
      sourcePath: 'lib/screens/coupon_log_screen.dart',
      category: AuditCategory.account,
      risk: AuditRisk.medium,
      status: AuditStatus.unverified,
      scenario: 'Użytkownik widzi historię wykorzystanych kuponów.'),
  ModuleAuditEntry(
      id: 'cut-list-summary',
      entryPoint: 'CutListSummaryScreen',
      sourcePath: 'lib/screens/cut_list_summary_screen.dart',
      category: AuditCategory.project,
      risk: AuditRisk.high,
      status: AuditStatus.unverified,
      scenario:
          'Projekt z trzema odcinkami wyświetla podsumowanie listy cięcia.'),
  ModuleAuditEntry(
      id: 'dn-mm',
      entryPoint: 'DnMmScreen',
      sourcePath: 'lib/screens/dn_mm_screen.dart',
      category: AuditCategory.fitter,
      risk: AuditRisk.medium,
      status: AuditStatus.unverified,
      scenario: 'DN 100 zwraca odpowiadającą wartość w milimetrach.'),
  ModuleAuditEntry(
      id: 'elbow-takeout',
      entryPoint: 'ElbowTakeoutScreen',
      sourcePath: 'lib/screens/elbow_takeout_screen.dart',
      category: AuditCategory.fitter,
      risk: AuditRisk.high,
      status: AuditStatus.passed,
      scenario: 'Dane kolana 90 stopni LR DN 100 zawierają take-out 152 mm.',
      evidence: [
        'test/audit/fitter_calculations_audit_test.dart: kolano 90° LR DN100 ma take-out 152 mm',
      ]),
  ModuleAuditEntry(
      id: 'electrode-exposure',
      entryPoint: 'ElectrodeExposurePage',
      sourcePath:
          'lib/features/electrode_exposure/electrode_exposure_page.dart',
      category: AuditCategory.welder,
      risk: AuditRisk.safetyCritical,
      status: AuditStatus.passed,
      scenario:
          'E7018 wyjęte 07:00: limit 4 h (AWS D1.1 Tab. 7.1) → koniec 11:00; 10:45 „zostało 15 min” (kończy się), 11:01 „PRZEKROCZONO o 1 min” z suszeniem 260–430 °C min. 2 h (nr 1 z 1); do piecyka 09:00 po 2 h, wyjęte 13:00 po 4 h → limit od nowa, wyjęte po 1 h → liczy dalej od 2 h; ponownie wysuszone 17:30 (1/1), o 22:00 limit suszeń wyczerpany → złom; przypomnienia 10:30 i 11:00; dziennik dziś/7 dni/wszystko, tekst i PDF.',
      evidence: [
        'test/features/electrode_exposure/electrode_exposure_page_test.dart: dodanie partii → odliczanie na żywo i zapis',
        'test/features/electrode_exposure/electrode_exposure_page_test.dart: przesunięcie zegara: OK → kończy się → przekroczony',
        'test/features/electrode_exposure/electrode_exposure_page_test.dart: akcje: piecyk, reset po 4 h, suszenie, limit suszeń, złom',
        'test/features/electrode_exposure/electrode_exposure_page_test.dart: wyjęte z piecyka po < 4 h — licznik liczy dalej',
        'test/features/electrode_exposure/electrode_exposure_page_test.dart: dziennik: filtr dziś / 7 dni / wszystko i udostępnianie',
        'test/features/electrode_exposure/electrode_exposure_page_test.dart: przypomnienia: plan po każdej zmianie partii',
        'test/features/electrode_exposure/electrode_exposure_page_test.dart: wąski ekran 320×640, tekst ×1,3 — bez overflow (PL i EN)',
        'test/domain/welding/electrode_exposure_test.dart: tabela limitów: limit domyślny dla każdej klasy (AWS D1.1 Tab. 7.1 / producent)',
        'test/domain/welding/electrode_exposure_test.dart: piecyk-przechowalnik: wyjęte po równo 4 h — limit od nowa',
        'test/domain/welding/electrode_exposure_test.dart: ponowne suszenie: suszenie zeruje licznik i liczy suszenia; AWS max 1',
        'test/domain/welding/electrode_exposure_test.dart: zapis JSON: uszkodzony JSON — pusta lista, bez wyjątku',
        'test/features/electrode_exposure/electrode_exposure_page_test.dart: A1: przekroczonej partii nie da się ożywić podniesieniem limitu',
        'test/features/electrode_exposure/electrode_exposure_page_test.dart: A4/A5: niespójny zapis i nieznane zdarzenie nie wywalają ekranu, kopia zostaje',
      ]),
  ModuleAuditEntry(
      id: 'flange-check',
      entryPoint: 'FlangeCheckPage',
      sourcePath: 'lib/features/flange_check/flange_check_page.dart',
      category: AuditCategory.fitter,
      risk: AuditRisk.safetyCritical,
      status: AuditStatus.passed,
      scenario:
          'DN150 CL300 (B16.5 → 12 śrub): przesunięcie osi 1,5 mm → OK, 1,6 mm → poza (PCC-1-2019 zał. E: 1,5 mm / 1/16"); szczelina 2,3/3,1/2,7/2,9 mm → max − min 0,8 OK, przy 3,2 → 0,9 poza; uszczelka 1,5 mm → szczelina 3,1 > 2 × 1,5 poza, 4,5 mm → OK; otwory 3,0 OK / 3,01 poza; 0,0625" w calach na granicy, po przełączeniu na mm 1,59 → poza; komplet odhaczeń bez pomiarów → „Niekompletny”; zapis L-101-F1 do historii, duplikat L-101-F2 bez pomiarów i odhaczeń; usunięcie z „Cofnij”; uszkodzony JSON → pusta historia.',
      evidence: [
        'test/domain/flange/flange_check_test.dart: przesunięcie osi (high/low): na granicy: 1,5 mm → OK',
        'test/domain/flange/flange_check_test.dart: przesunięcie osi (high/low): tuż ponad: 1,51 mm → poza tolerancją',
        'test/domain/flange/flange_check_test.dart: równoległość (max − min szczeliny): na granicy: 2,3 i 3,1 mm → różnica 0,8 → OK',
        'test/domain/flange/flange_check_test.dart: nadmierna szczelina (2 × grubość uszczelki): na granicy: uszczelka 4,5 mm, największa szczelina 9,0 → OK',
        'test/domain/flange/flange_check_test.dart: cale: 1/16" w protokole calowym — na granicy; ten sam odczyt w mm — poza (1,5875 > 1,5)',
        'test/domain/flange/flange_check_test.dart: 4 vs 8 punktów: klin widoczny tylko w 8 punktach: 4 punkty OK, 8 — poza',
        'test/domain/flange/flange_check_test.dart: werdykt protokołu: komplet odhaczeń bez pomiarów → niekompletny, nie zielony',
        'test/domain/flange/flange_check_test.dart: JSON: uszkodzony JSON → pusta lista zamiast wyjątku',
        'test/features/flange_check/flange_check_page_test.dart: wpisanie pomiarów zmienia werdykt',
        'test/features/flange_check/flange_check_page_test.dart: komplet odhaczeń bez pomiaru — nie zielony',
        'test/features/flange_check/flange_check_page_test.dart: zapis → historia; duplikat bez pomiarów i odhaczeń',
        'test/features/flange_check/flange_check_page_test.dart: usunięcie z cofnięciem',
        'test/features/flange_check/flange_check_page_test.dart: wąski ekran 320×640, tekst ×1,3 — bez wyjątków (pl)',
        'test/features/flange_check/flange_check_page_test.dart: cele dotyku ≥ 48 dp',
        'test/services/flange_check_export_test.dart: PDF renderuje się z polskimi fontami',
        'test/features/flange_check/flange_check_page_test.dart: B1: zmiana jednostki przy pomiarach pyta i czyści — werdykt nie zielenieje po cichu',
        'test/features/flange_check/flange_check_page_test.dart: B3: literówka 15 zamiast 1,5 — błąd pola i brak zieleni; luźniejsze niż PCC-1 — ostrzeżenie',
        'test/features/flange_check/flange_check_page_test.dart: B4: uszkodzone tolerancje w zapisie — Niekompletny z komunikatem, nie PCC-1',
      ]),
  ModuleAuditEntry(
      id: 'filler-selector',
      entryPoint: 'FillerSelectorPage',
      sourcePath: 'lib/features/filler/filler_selector_page.dart',
      category: AuditCategory.welder,
      risk: AuditRisk.high,
      status: AuditStatus.passed,
      scenario:
          'Stal węglowa + 304L, TIG → ER309L / W 23 12 L, formowanie wymagane, ostrzeżenie o spoiwie niklowym powyżej ok. 315–370 °C; aluminium + stal → „Nie spawa się łukowo”.',
      evidence: [
        'test/features/filler/filler_selector_page_test.dart: węglowa + 304L → 309L; MMA bez gazu, formowanie wymagane',
        'test/features/filler/filler_selector_page_test.dart: aluminium + stal → nie spawa się łukowo',
        'test/domain/filler/filler_selector_test.dart: symetria: A + B == B + A',
        'test/audit/module_smoke_test.dart: FillerSelectorPage renderuje przy skali tekstu 1,3',
      ]),
  ModuleAuditEntry(
      id: 'fitter-menu',
      entryPoint: 'FitterMenuScreen',
      sourcePath: 'lib/screens/fitter_menu_screen.dart',
      category: AuditCategory.fitter,
      risk: AuditRisk.low,
      status: AuditStatus.unverified,
      scenario: 'Użytkownik otwiera menu narzędzi montera.',
      evidence: [
        'test/audit/module_smoke_test.dart: FitterMenuScreen renderuje przy skali tekstu 1,3',
      ]),
  ModuleAuditEntry(
      id: 'fitter',
      entryPoint: 'FitterScreen',
      sourcePath: 'lib/screens/fitter_screen.dart',
      category: AuditCategory.fitter,
      risk: AuditRisk.low,
      status: AuditStatus.unverified,
      scenario: 'Użytkownik otwiera główny ekran montera.',
      evidence: [
        'test/audit/module_smoke_test.dart: FitterScreen renderuje z istniejącym projektem przy skali 1,3',
      ]),
  ModuleAuditEntry(
      id: 'fitter-tools',
      entryPoint: 'FitterToolsScreen',
      sourcePath: 'lib/screens/fitter_tools_screen.dart',
      category: AuditCategory.fitter,
      risk: AuditRisk.low,
      status: AuditStatus.unverified,
      scenario: 'Użytkownik wybiera kalkulator z zestawu narzędzi montera.'),
  ModuleAuditEntry(
      id: 'heat-input',
      entryPoint: 'HeatInputScreen',
      sourcePath: 'lib/screens/heat_input_screen.dart',
      category: AuditCategory.welder,
      risk: AuditRisk.safetyCritical,
      status: AuditStatus.passed,
      scenario:
          '12 V, 100 A, 100 mm/min, GTAW wyświetla 0,43 kJ/mm; prędkość 0 i -1 jest odrzucana.',
      evidence: [
        'test/audit/welder_calculations_audit_test.dart: GTAW 0,432 kJ/mm (0,43 w UI) oraz odrzucenie prędkości 0 i -1',
      ]),
  ModuleAuditEntry(
      id: 'heat-photos',
      entryPoint: 'HeatPhotosScreen',
      sourcePath: 'lib/screens/heat_photos_screen.dart',
      category: AuditCategory.project,
      risk: AuditRisk.medium,
      status: AuditStatus.unverified,
      scenario: 'Użytkownik dodaje zdjęcie numeru wytopu do komponentu.'),
  ModuleAuditEntry(
      id: 'heat-tint',
      entryPoint: 'HeatTintScreen',
      sourcePath: 'lib/screens/heat_tint_screen.dart',
      category: AuditCategory.welder,
      risk: AuditRisk.high,
      status: AuditStatus.passed,
      scenario:
          'Ekran oznacza wartości O2 jako orientacyjne, a specyfikację projektu lub WPS jako wiążące.',
      evidence: [
        'test/audit/welder_calculations_audit_test.dart: heat tint jest oznaczony jako porada orientacyjna z wiążącym WPS',
      ]),
  ModuleAuditEntry(
      id: 'help',
      entryPoint: 'HelpScreen',
      sourcePath: 'lib/screens/help_screen.dart',
      category: AuditCategory.document,
      risk: AuditRisk.low,
      status: AuditStatus.unverified,
      scenario: 'Wyszukanie hasła TIG pokazuje odpowiednią pomoc.'),
  ModuleAuditEntry(
      id: 'home',
      entryPoint: 'HomeScreen',
      sourcePath: 'lib/screens/home_screen.dart',
      category: AuditCategory.start,
      risk: AuditRisk.medium,
      status: AuditStatus.unverified,
      scenario:
          'Użytkownik otwiera ekran startowy i przechodzi do dostępnego modułu.'),
  ModuleAuditEntry(
      id: 'hot-work',
      entryPoint: 'HotWorkPage',
      sourcePath: 'lib/features/hot_work/hot_work_page.dart',
      category: AuditCategory.welder,
      risk: AuditRisk.safetyCritical,
      status: AuditStatus.passed,
      scenario:
          'Nowy protokół trafia do historii (SharedPreferences); „jak wczoraj” kopiuje miejsce, osoby, godziny i próg DGW, ale nie zaznaczenia, pomiary ani nr zezwolenia; pusty protokół nie jest zapisywany; usunięcie można cofnąć.',
      evidence: [
        'test/features/hot_work/hot_work_page_test.dart: nowy protokół: odhaczenie punktów, pomiar, zapis i historia',
        'test/features/hot_work/hot_work_page_test.dart: jak wczoraj: kopia danych bez zaznaczeń i pomiarów',
        'test/features/hot_work/hot_work_page_test.dart: menu pozycji: duplikat i usunięcie z cofnięciem',
        'test/features/hot_work/hot_work_page_test.dart: pusty protokół nie trafia do historii',
        'test/features/hot_work/hot_work_page_test.dart: wąski ekran, czcionka 1,3: bez przepełnień',
      ]),
  ModuleAuditEntry(
      id: 'hot-work-edit',
      entryPoint: 'HotWorkEditPage',
      sourcePath: 'lib/features/hot_work/hot_work_edit_page.dart',
      category: AuditCategory.welder,
      risk: AuditRisk.safetyCritical,
      status: AuditStatus.passed,
      scenario:
          'Wszystkie punkty „przed rozpoczęciem” odhaczone bez pomiaru — stan „Brak pomiaru atmosfery” (nie zielony); pomiar 7 % DGW przy progu 5 % — STOP; kolejny pomiar 0 % — „Stanowisko przygotowane”; tekst i PDF protokołu udostępniane.',
      evidence: [
        'test/features/hot_work/hot_work_page_test.dart: wszystkie punkty odhaczone, brak pomiaru — nie zielony',
        'test/features/hot_work/hot_work_page_test.dart: pomiar powyżej progu z zezwolenia — STOP; nowy pomiar zdejmuje',
        'test/features/hot_work/hot_work_page_test.dart: udostępnianie: tekst protokołu i PDF',
        'test/features/hot_work/hot_work_page_test.dart: cele dotyku ≥ 48 dp (rękawica)',
        'test/domain/hot_work/hot_work_permit_test.dart: ocena gotowości wszystko odhaczone, ale brak pomiaru — NIE zielony stan',
        'test/domain/hot_work/hot_work_checklist_test.dart: każda liczba w punkcie ma źródło, PL i EN mają te same liczby',
        'test/features/hot_work/hot_work_export_test.dart: wypełniony protokół — PL i EN',
      ]),
  ModuleAuditEntry(
      id: 'hydrotest',
      entryPoint: 'HydrotestScreen',
      sourcePath: 'lib/screens/hydrotest_screen.dart',
      category: AuditCategory.fitter,
      risk: AuditRisk.safetyCritical,
      status: AuditStatus.passed,
      scenario:
          'Ciśnienie projektowe powyżej zakresu ekranu jest odrzucane bez wyniku ciśnienia testowego.',
      evidence: [
        'test/audit/welder_calculations_audit_test.dart: 2001 bar pokazuje błąd zakresu i nie tworzy wyniku',
      ]),
  ModuleAuditEntry(
      id: 'hourly-rate',
      entryPoint: 'HourlyRatePage',
      sourcePath: 'lib/features/quotes/hourly_rate_page.dart',
      category: AuditCategory.project,
      risk: AuditRisk.medium,
      status: AuditStatus.passed,
      scenario:
          'Na rękę 9000 zł, koszty firmy, podatek 19% od dochodu, 21 dni × 8 h, 75% fakturowane → stawka minimalna; z wyceny „Użyj… zł/h” wpisuje ją do stawki spawacza.',
      evidence: [
        'test/domain/quotes/hourly_rate_test.dart: podatek od dochodu: przychód = koszty + na rękę / (1 − r)',
        'test/features/quotes/hourly_rate_page_test.dart: z wyceny: „Użyj” zwraca stawkę zaokrągloną w górę do 50 gr',
      ]),
  ModuleAuditEntry(
      id: 'iso5817',
      entryPoint: 'Iso5817Page',
      sourcePath: 'lib/features/iso5817/iso5817_page.dart',
      category: AuditCategory.welder,
      risk: AuditRisk.safetyCritical,
      status: AuditStatus.passed,
      scenario:
          'Spoina czołowa t 10 mm, poziom C, podtopienie: 0,4 mm „mieści się w C (limit 0,5 mm)”, 0,8 mm „przekracza C, mieści się w D (limit 1 mm)”, 1,2 mm „niedopuszczalne”; przy t 2 mm limit C 0,2 mm, a B niedopuszczalne; wynik udostępniany tekstem z zastrzeżeniem.',
      evidence: [
        'test/features/iso5817/iso5817_page_test.dart: wpisanie t i pomiaru zmienia werdykt (podtopienie 1.7)',
        'test/features/iso5817/iso5817_page_test.dart: spoina pachwinowa: pozycja z listy, werdykt i protokół do udostępnienia',
        'test/domain/iso5817/iso5817_limits_test.dart: B ≤ C ≤ D dla każdej pozycji na siatce t, b, a',
        'test/domain/iso5817/iso5817_limits_test.dart: zakres grubości t = 3 to jeszcze „0,5 to 3”, t > 3 już „> 3”',
      ]),
  ModuleAuditEntry(
      id: 'instrument-edit',
      entryPoint: 'InstrumentEditPage',
      sourcePath: 'lib/features/instruments/instrument_edit_page.dart',
      category: AuditCategory.document,
      risk: AuditRisk.medium,
      status: AuditStatus.passed,
      scenario:
          'Nowy przyrząd: rodzaj „Klucz dynamometryczny”, nazwa, interwał 12 mies. (ISO 6789) — „Zapisz” zwraca rekord do rejestru.',
      evidence: [
        'test/features/instruments/instrument_register_test.dart: formularz: nowy przyrząd z rodzajem i datą zwraca rekord',
      ]),
  ModuleAuditEntry(
      id: 'instrument-register',
      entryPoint: 'InstrumentRegisterPage',
      sourcePath: 'lib/features/instruments/instrument_register_page.dart',
      category: AuditCategory.document,
      risk: AuditRisk.high,
      status: AuditStatus.passed,
      scenario:
          'Manometr skalibrowany 2025-01-10 (12 mies.) na 2026-10-17: „po terminie 280 dni”, na górze listy przed termometrem w terminie; „Skalibrowane dziś” zapisuje datę i zeruje licznik po terminie; CSV i PDF rejestru.',
      evidence: [
        'test/features/instruments/instrument_register_test.dart: przyrząd po terminie na górze; „skalibrowane dziś” go zieleni',
        'test/domain/instruments/instrument_test.dart: status: po terminie, ≤ 30 dni, OK, brak daty',
        'test/domain/instruments/instrument_test.dart: plan przypomnień: 30 i 7 dni przed, tylko przyszłe, unikalne id',
        'test/domain/instruments/instrument_test.dart: CSV i PDF rejestru',
      ]),
  ModuleAuditEntry(
      id: 'iso-notebook',
      entryPoint: 'IsoNotebookScreen',
      sourcePath: 'lib/screens/iso_notebook_screen.dart',
      category: AuditCategory.document,
      risk: AuditRisk.high,
      status: AuditStatus.unverified,
      scenario: 'Użytkownik otwiera zapisany notatnik ISO projektu.'),
  ModuleAuditEntry(
      id: 'iso-scanner',
      entryPoint: 'IsoScannerScreen',
      sourcePath: 'lib/screens/iso_scanner_screen.dart',
      category: AuditCategory.ai,
      risk: AuditRisk.high,
      status: AuditStatus.unverified,
      scenario:
          'Użytkownik wybiera obraz ISO i widzi bezpieczny stan funkcji skanowania.'),
  ModuleAuditEntry(
      id: 'job-add',
      entryPoint: 'JobAddScreen',
      sourcePath: 'lib/screens/job_add_screen.dart',
      category: AuditCategory.social,
      risk: AuditRisk.medium,
      status: AuditStatus.unverified,
      scenario: 'Użytkownik wprowadza ofertę pracy z tytułem i lokalizacją.'),
  ModuleAuditEntry(
      id: 'jobs',
      entryPoint: 'JobsScreen',
      sourcePath: 'lib/screens/jobs_screen.dart',
      category: AuditCategory.social,
      risk: AuditRisk.medium,
      status: AuditStatus.unverified,
      scenario: 'Użytkownik przegląda listę ofert pracy.',
      evidence: [
        'test/audit/module_smoke_test.dart: Ponów wykonuje drugie wywołanie Jobs i pokazuje zwróconą ofertę',
      ]),
  ModuleAuditEntry(
      id: 'legal',
      entryPoint: 'LegalScreen',
      sourcePath: 'lib/screens/legal_screen.dart',
      category: AuditCategory.document,
      risk: AuditRisk.medium,
      status: AuditStatus.unverified,
      scenario: 'Użytkownik otwiera politykę prywatności w aplikacji.',
      evidence: [
        'test/audit/module_smoke_test.dart: LegalScreen renderuje politykę prywatności przy skali 1,3',
      ]),
  ModuleAuditEntry(
      id: 'material-list',
      entryPoint: 'MaterialListScreen',
      sourcePath: 'lib/screens/material_list_screen.dart',
      category: AuditCategory.project,
      risk: AuditRisk.high,
      status: AuditStatus.unverified,
      scenario: 'Projekt z odcinkami wyświetla listę materiałową z ilościami.'),
  ModuleAuditEntry(
      id: 'mitre-bend',
      entryPoint: 'MitreBendPage',
      sourcePath: 'lib/features/mitre_bend/mitre_bend_page.dart',
      category: AuditCategory.fitter,
      risk: AuditRisk.medium,
      status: AuditStatus.passed,
      scenario:
          'DN150 (Ø168,3), 90°, 3 spoiny, R = 1,5D: cięcie 15°, segment pełny oś 135,3 / gardło 90,2 / grzbiet 180,4 mm; 4 spoiny → 11,25°; R ≤ D/2 i za krótki odcinek przy jednym cięciu — komunikat bez wyniku; szablon 1:1 w kaflach A4.',
      evidence: [
        'test/domain/fitter/mitre_bend_test.dart: pełny segment: oś 2R·tg β, gardło i grzbiet ± D·tg β',
        'test/features/mitre_bend/mitre_bend_page_test.dart: domyślnie DN150, 90°, 3 spoiny → cięcie 15°',
        'test/features/mitre_bend/mitre_bend_page_test.dart: za mały promień — komunikat, bez wyniku',
        'test/features/mitre_bend/mitre_bend_page_test.dart: szablon PDF: kafle i podziałki, DN600 mieści się w limicie',
      ]),
  ModuleAuditEntry(
      id: 'new-cut-list-project',
      entryPoint: 'NewCutListProjectScreen',
      sourcePath: 'lib/screens/new_cut_list_project_screen.dart',
      category: AuditCategory.project,
      risk: AuditRisk.medium,
      status: AuditStatus.unverified,
      scenario: 'Użytkownik zakłada projekt listy cięcia z nazwą.'),
  ModuleAuditEntry(
      id: 'new-project',
      entryPoint: 'NewProjectScreen',
      sourcePath: 'lib/screens/new_project_screen.dart',
      category: AuditCategory.project,
      risk: AuditRisk.medium,
      status: AuditStatus.unverified,
      scenario: 'Użytkownik tworzy nowy projekt spawalniczy.'),
  ModuleAuditEntry(
      id: 'onboarding-name',
      entryPoint: 'OnboardingNameScreen',
      sourcePath: 'lib/screens/onboarding_name_screen.dart',
      category: AuditCategory.start,
      risk: AuditRisk.low,
      status: AuditStatus.unverified,
      scenario: 'Nowy użytkownik zapisuje swoje imię w onboardingu.'),
  ModuleAuditEntry(
      id: 'orbital-tig',
      entryPoint: 'OrbitalTigScreen',
      sourcePath: 'lib/screens/orbital_tig_screen.dart',
      category: AuditCategory.welder,
      risk: AuditRisk.safetyCritical,
      status: AuditStatus.passed,
      scenario:
          'Estimator orbitalnego TIG dla 50,8 × 1,65 mm zwraca cztery skończone dodatnie poziomy prądu.',
      evidence: [
        'test/audit/welder_calculations_audit_test.dart: cztery skończone dodatnie poziomy prądu orbitalnego TIG',
      ]),
  ModuleAuditEntry(
      id: 'passivation',
      entryPoint: 'PassivationScreen',
      sourcePath: 'lib/screens/passivation_screen.dart',
      category: AuditCategory.welder,
      risk: AuditRisk.high,
      status: AuditStatus.passed,
      scenario:
          'Ekran oznacza pasywację jako przewodnik procesowy, a kartę produktu i specyfikację projektu jako wiążące.',
      evidence: [
        'test/audit/welder_calculations_audit_test.dart: passivation jest oznaczone jako przewodnik nienormatywny',
      ]),
  ModuleAuditEntry(
      id: 'pipe-route-calculator',
      entryPoint: 'PipeRouteCalculatorScreen',
      sourcePath: 'lib/screens/pipe_route_calculator_screen.dart',
      category: AuditCategory.fitter,
      risk: AuditRisk.high,
      status: AuditStatus.unverified,
      scenario: 'Trasa z dwoma odcinkami zwraca całkowitą długość rurociągu.'),
  ModuleAuditEntry(
      id: 'pipe-schedule',
      entryPoint: 'PipeScheduleScreen',
      sourcePath: 'lib/screens/pipe_schedule_screen.dart',
      category: AuditCategory.fitter,
      risk: AuditRisk.high,
      status: AuditStatus.unverified,
      scenario:
          'NPS 2 Schedule 40 pokazuje grubość ścianki i średnicę wewnętrzną.'),
  ModuleAuditEntry(
      id: 'pipe-slope',
      entryPoint: 'PipeSlopeScreen',
      sourcePath: 'lib/screens/pipe_slope_screen.dart',
      category: AuditCategory.fitter,
      risk: AuditRisk.high,
      status: AuditStatus.passed,
      scenario: 'Spadek 1 procent na 10 m zwraca różnicę wysokości 100 mm.',
      evidence: [
        'test/audit/fitter_calculations_audit_test.dart: spadek 1% na 10 m daje 100 mm',
      ]),
  ModuleAuditEntry(
      id: 'pre-weld-checklist',
      entryPoint: 'PreWeldChecklistScreen',
      sourcePath: 'lib/screens/pre_weld_checklist_screen.dart',
      category: AuditCategory.welder,
      risk: AuditRisk.safetyCritical,
      status: AuditStatus.unverified,
      scenario:
          'Spawacz odhacza komplet warunków przed rozpoczęciem spawania.'),
  ModuleAuditEntry(
      id: 'premium',
      entryPoint: 'PremiumScreen',
      sourcePath: 'lib/screens/premium_screen.dart',
      category: AuditCategory.account,
      risk: AuditRisk.high,
      status: AuditStatus.unverified,
      scenario: 'Użytkownik widzi plan premium bez inicjowania płatności.',
      evidence: [
        'test/audit/module_smoke_test.dart: PremiumScreen renderuje offline bez uruchomienia płatności',
      ]),
  ModuleAuditEntry(
      id: 'profile',
      entryPoint: 'ProfileScreen',
      sourcePath: 'lib/screens/profile_screen.dart',
      category: AuditCategory.account,
      risk: AuditRisk.medium,
      status: AuditStatus.passed,
      scenario:
          'Istniejący user_profile_v1 odtwarza polskie imię i nazwisko bez utraty znaków.',
      evidence: [
        'test/audit/data_integrity_audit_test.dart: UserProfileService odczytuje istniejący user_profile_v1',
      ]),
  ModuleAuditEntry(
      id: 'project-components',
      entryPoint: 'ProjectComponentsScreen',
      sourcePath: 'lib/screens/project_components_screen.dart',
      category: AuditCategory.project,
      risk: AuditRisk.high,
      status: AuditStatus.unverified,
      scenario: 'Projekt wyświetla przypisane komponenty i ich numery wytopu.'),
  ModuleAuditEntry(
      id: 'projects',
      entryPoint: 'ProjectsScreen',
      sourcePath: 'lib/screens/projects_screen.dart',
      category: AuditCategory.project,
      risk: AuditRisk.medium,
      status: AuditStatus.passed,
      scenario:
          'Edycja przeżywa ponowne otwarcie, a usunięcie i Cofnij atomowo obejmują projekt, segmenty, zdjęcia i numery wytopów.',
      evidence: [
        'test/audit/data_integrity_audit_test.dart: edycja projektu i CUT segmentu przeżywa ponowne otwarcie bazy',
        'test/audit/data_integrity_audit_test.dart: usunięcie projektu atomowo usuwa tylko jego dane zależne',
        'test/audit/data_integrity_audit_test.dart: błąd ograniczenia cofa niepełne usunięcie projektu',
        'test/audit/data_integrity_audit_test.dart: snapshot Cofnij odtwarza projekt i wszystkie zależności',
        'test/audit/data_integrity_audit_test.dart: ProjectsScreen deleguje usunięcie i Cofnij wyłącznie do atomowego API',
      ]),
  ModuleAuditEntry(
      id: 'pwht-planner',
      entryPoint: 'PwhtPlannerPage',
      sourcePath: 'lib/features/pwht/pwht_planner_page.dart',
      category: AuditCategory.welder,
      risk: AuditRisk.safetyCritical,
      status: AuditStatus.passed,
      scenario:
          'ASME B31.3, P-No 4, grubość 25 mm: PWHT wymagane (> 16 mm), 650–705 °C, min. 1 h 00 min, maks. 335 °C/h powyżej 315 °C, pasmo 75 mm; P91 6 mm — wymagane; P-No 8 — tabela nie wymaga.',
      evidence: [
        'test/features/pwht/pwht_planner_page_test.dart: P-No 4, 25 mm: PWHT wymagane, odczyty i wykres',
        'test/features/pwht/pwht_planner_page_test.dart: P91 cienka ścianka: nadal wymagane',
        'test/features/pwht/pwht_planner_page_test.dart: austenityczna P-No 8: tabela nie wymaga, bez odczytów',
        'test/features/pwht/pwht_planner_page_test.dart: wąski ekran, czcionka 1,3: bez przepełnień',
        'test/domain/pwht/pwht_plan_test.dart: czy PWHT wymagane — B31.3 Tab. 331.1.3: P-No 4 i 5A: ≤ 16 mm warunkowo (C ≤ 0,15 %), > 16 mm wymagane',
      ]),
  ModuleAuditEntry(
      id: 'quick-converter',
      entryPoint: 'QuickConverterScreen',
      sourcePath: 'lib/screens/quick_converter_screen.dart',
      category: AuditCategory.fitter,
      risk: AuditRisk.medium,
      status: AuditStatus.unverified,
      scenario: '25,4 mm konwertuje się na 1 cal.'),
  ModuleAuditEntry(
      id: 'quote-edit',
      entryPoint: 'QuoteEditPage',
      sourcePath: 'lib/features/quotes/quote_edit_page.dart',
      category: AuditCategory.project,
      risk: AuditRisk.high,
      status: AuditStatus.passed,
      scenario:
          'Nowa wycena: spoina DN100 (Ø114,3 × 6,02) × 4 trafia do listy pozycji i paska sumy, zapisuje się sama w weld_quotes i otwiera zakładkę Wynik z ofertą PDF.',
      evidence: [
        'test/features/quotes/quote_flow_test.dart: nowa wycena → spoina wpisana ręcznie → zapis i lista',
        'test/features/quotes/quote_flow_test.dart: pusta wycena nie zapisuje się przy wyjściu',
        'test/domain/quotes/quote_calculator_test.dart: składniki sumują się dokładnie do netto i brutto',
      ]),
  ModuleAuditEntry(
      id: 'quote-joint',
      entryPoint: 'QuoteJointPage',
      sourcePath: 'lib/features/quotes/quote_joint_page.dart',
      category: AuditCategory.project,
      risk: AuditRisk.high,
      status: AuditStatus.passed,
      scenario:
          'Pozycja wpisana ręcznie (OD, ścianka, liczba przyciskiem +) pokazuje podgląd kosztu pozycji i wraca do wyceny po „Dodaj do wyceny".',
      evidence: [
        'test/features/quotes/quote_flow_test.dart: nowa wycena → spoina wpisana ręcznie → zapis i lista',
        'test/domain/quotes/quote_calculator_test.dart: DN100 Sch 40, V 60°: ~0,11 kg stopiwa stali węglowej na spoinę',
      ]),
  ModuleAuditEntry(
      id: 'quote-list',
      entryPoint: 'QuoteListPage',
      sourcePath: 'lib/features/quotes/quote_list_page.dart',
      category: AuditCategory.project,
      risk: AuditRisk.high,
      status: AuditStatus.passed,
      scenario:
          'Lista wycen: pusta pokazuje zachętę, nowa wycena dostaje numer WYC/rok/nnn, zapisana wraca jako karta z kwotą i liczbą spoin; kosz z przywracaniem.',
      evidence: [
        'test/features/quotes/quote_flow_test.dart: nowa wycena → spoina wpisana ręcznie → zapis i lista',
        'test/features/quotes/quote_flow_test.dart: DAO: zapis z sumami, kosz, numeracja, duplikat',
      ]),
  ModuleAuditEntry(
      id: 'quote-settings',
      entryPoint: 'QuoteSettingsPage',
      sourcePath: 'lib/features/quotes/quote_settings_page.dart',
      category: AuditCategory.project,
      risk: AuditRisk.medium,
      status: AuditStatus.unverified,
      scenario:
          'Zapis „moich stawek" i danych firmy — nowa wycena startuje z tymi stawkami, zapisane wyceny się nie zmieniają.',
      evidence: [
        'test/features/quotes/quote_flow_test.dart: moje stawki: zapis i odczyt, ceny spoiw per materiał',
      ]),
  ModuleAuditEntry(
      id: 'register',
      entryPoint: 'RegisterScreen',
      sourcePath: 'lib/screens/register_screen.dart',
      category: AuditCategory.account,
      risk: AuditRisk.high,
      status: AuditStatus.unverified,
      scenario: 'Użytkownik podaje poprawny e-mail i hasło do rejestracji.'),
  ModuleAuditEntry(
      id: 'rolling-offset',
      entryPoint: 'RollingOffsetScreen',
      sourcePath: 'lib/screens/rolling_offset_screen.dart',
      category: AuditCategory.fitter,
      risk: AuditRisk.high,
      status: AuditStatus.unverified,
      scenario: 'Dwa przesunięcia osi wyliczają długość rozwinięcia.'),
  ModuleAuditEntry(
      id: 'saddle-cut',
      entryPoint: 'SaddleCutScreen',
      sourcePath: 'lib/screens/saddle_cut_screen.dart',
      category: AuditCategory.fitter,
      risk: AuditRisk.safetyCritical,
      status: AuditStatus.unverified,
      scenario:
          'Rura odgałęźna 60 mm na kolektorze 114 mm wylicza profil siodła.'),
  ModuleAuditEntry(
      id: 'saddle-template',
      entryPoint: 'SaddleTemplateScreen',
      sourcePath: 'lib/screens/saddle_template_screen.dart',
      category: AuditCategory.fitter,
      risk: AuditRisk.safetyCritical,
      status: AuditStatus.passed,
      scenario:
          'Szablon siodła 200/100 mm przy 45 stopniach zawiera 73 punkty o skończonych, nieujemnych i symetrycznych głębokościach.',
      evidence: [
        'test/audit/fitter_calculations_audit_test.dart: saddle jest symetryczny, skończony i nieujemny',
      ]),
  ModuleAuditEntry(
      id: 'sanitary-tube',
      entryPoint: 'SanitaryTubeScreen',
      sourcePath: 'lib/screens/sanitary_tube_screen.dart',
      category: AuditCategory.fitter,
      risk: AuditRisk.high,
      status: AuditStatus.unverified,
      scenario: 'Rura sanitarna 38 mm zwraca średnicę i grubość ścianki.'),
  ModuleAuditEntry(
      id: 'scan-review',
      entryPoint: 'ScanReviewScreen',
      sourcePath: 'lib/screens/scan_review_screen.dart',
      category: AuditCategory.document,
      risk: AuditRisk.high,
      status: AuditStatus.unverified,
      scenario:
          'Użytkownik przegląda wynik rozpoznania ISO przed zapisem projektu.'),
  ModuleAuditEntry(
      id: 'segment-builder',
      entryPoint: 'SegmentBuilderScreen',
      sourcePath: 'lib/screens/segment_builder_screen.dart',
      category: AuditCategory.project,
      risk: AuditRisk.high,
      status: AuditStatus.passed,
      scenario:
          'Zapisany CUT 896 mm oraz poprawiona wartość ISO segmentu przeżywają ponowne otwarcie bazy.',
      evidence: [
        'test/audit/data_integrity_audit_test.dart: edycja projektu i CUT segmentu przeżywa ponowne otwarcie bazy',
      ]),
  ModuleAuditEntry(
      id: 'steel-weight',
      entryPoint: 'SteelWeightPage',
      sourcePath: 'lib/features/steel_weight/steel_weight_page.dart',
      category: AuditCategory.fitter,
      risk: AuditRisk.high,
      status: AuditStatus.passed,
      scenario:
          'HEB 200 × 6000 mm waży 367,8 kg (61,3 kg/m, EN 10365); IPE 240 × 12 m = 368,4 kg; HEB 200 × 2 szt. dodane do listy zapisuje się, z zapasem 5 % daje 772,4 kg, a przy 5,20 zł/kg koszt z zapasem 4 016,38 zł.',
      evidence: [
        'test/features/steel_weight/steel_weight_page_test.dart: wybór profilu i długości zmienia masę',
        'test/features/steel_weight/steel_weight_page_test.dart: dodanie do listy: zapis, suma z zapasem 5 % i koszt',
        'test/features/steel_weight/steel_weight_page_test.dart: lista wczytuje się z pamięci; edycja pozycji zmienia sumę',
        'test/features/steel_weight/steel_weight_page_test.dart: profil zamknięty: tabela EN 10219-2 i własny wymiar',
        'test/features/steel_weight/steel_weight_page_test.dart: wąski ekran, czcionka 1,3: bez przepełnień',
        'test/domain/steel_weight/steel_weight_test.dart: tabele — spójność z geometrią (wyłapuje literówki): IPE / HEA / HEB / HEM: masa = A(h, b, tw, tf, r)·7850 w ±0,5 %',
        'test/domain/steel_weight/steel_weight_test.dart: lista materiałowa: zapas 5 %: masa i koszt w groszach',
      ]),
  ModuleAuditEntry(
      id: 'support-config',
      entryPoint: 'SupportConfigScreen',
      sourcePath: 'lib/screens/support_config_screen.dart',
      category: AuditCategory.fitter,
      risk: AuditRisk.high,
      status: AuditStatus.unverified,
      scenario: 'Średnica i medium zwracają maksymalny rozstaw podpór.'),
  ModuleAuditEntry(
      id: 'tungsten',
      entryPoint: 'TungstenScreen',
      sourcePath: 'lib/screens/tungsten_screen.dart',
      category: AuditCategory.welder,
      risk: AuditRisk.high,
      status: AuditStatus.passed,
      scenario:
          'Dobór wolframu DC zwraca elektrodę pokrywającą prądy od 15 do 400 A sprawdzone co 0,5 A.',
      evidence: [
        'test/audit/welder_calculations_audit_test.dart: pasma wolframu pokrywają 15-400 A co 0,5 A bez luk',
      ]),
  ModuleAuditEntry(
      id: 'tutor',
      entryPoint: 'TutorScreen',
      sourcePath: 'lib/screens/tutor_screen.dart',
      category: AuditCategory.document,
      risk: AuditRisk.low,
      status: AuditStatus.unverified,
      scenario: 'Użytkownik otwiera lekcję z instrukcją użycia modułu.'),
  ModuleAuditEntry(
      id: 'weld-journal',
      entryPoint: 'WeldJournalScreen',
      sourcePath: 'lib/screens/weld_journal_screen.dart',
      category: AuditCategory.welder,
      risk: AuditRisk.high,
      status: AuditStatus.unverified,
      scenario:
          'Aktywny filtr ekranu przekazuje dokładnie ten sam zbiór do integracji CSV i PDF.'),
  ModuleAuditEntry(
      id: 'work-progress',
      entryPoint: 'ProgressPage',
      sourcePath: 'lib/features/progress/progress_page.dart',
      category: AuditCategory.project,
      risk: AuditRisk.medium,
      status: AuditStatus.passed,
      scenario:
          'Spoiny Blok 4 wpisane przez DAO: dziś 6 DI, ten tydzień 14 DI, warsztat 6 DI, pakiet TP-02 6 DI; JK-12 10 DI i AB-03 4 DI, brygada 4 spoiny (spoina z dwoma spawaczami liczona raz); zakres 40 DI → 35% i koniec 2026-10-22, zapamiętany per projekt; pusty dziennik otwiera WeldJournalScreen jednym dotknięciem; raport tekstem i PDF.',
      evidence: [
        'test/features/progress/progress_page_test.dart: spoiny z dziennika: DI dziś i w tygodniu, warsztat/obiekt, pakiet, spawacze bez podwójnego liczenia',
        'test/features/progress/progress_page_test.dart: prognoza: zakres DI zapamiętany per projekt, % i data końca przy obecnym tempie',
        'test/features/progress/progress_page_test.dart: pusty dziennik: zachęta i jedno dotknięcie do dziennika spoin',
        'test/features/progress/progress_page_test.dart: raport tekstem: idzie do udostępniania, a bez niego do schowka',
        'test/features/progress/progress_page_test.dart: PDF raportu tygodniowego renderuje się (PL i EN)',
        'test/domain/progress/weld_progress_test.dart: spoina z dwoma spawaczami: u obu, ale suma brygady liczy ją raz',
        'test/domain/progress/weld_progress_test.dart: spawacz i brygada: odrzucone ÷ zbadane RT/UT, R1 i R2+',
        'test/domain/progress/progress_forecast_test.dart: dziś z wpisami → liczenie od jutra, weekend pominięty',
      ]),
  ModuleAuditEntry(
      id: 'weld-symbols',
      entryPoint: 'WeldSymbolsPage',
      sourcePath: 'lib/features/weld_symbols/weld_symbols_page.dart',
      category: AuditCategory.welder,
      risk: AuditRisk.high,
      status: AuditStatus.passed,
      scenario:
          'Czytnik: pachwina a5 na linii ciągłej (system A), przerywana 3 × 50 (100), kółko i chorągiewka daje „Spoina pachwinowa a5 po stronie strzałki, przerywana 3 × 50 (100), dookoła, montażowa.” z ostrzeżeniem o kółku przy spoinie nieciągłej; symbol na linii przerywanej = strona przeciwna; V bez liczby = pełny przetop; z7 → a 4,95.',
      evidence: [
        'test/features/weld_symbols/weld_symbols_page_test.dart: czytnik: wybór elementów zmienia zdanie (przykład z rysunku)',
        'test/features/weld_symbols/weld_symbols_page_test.dart: czytnik: spoina czołowa — liczba to głębokość wtopienia',
        'test/features/weld_symbols/weld_symbols_page_test.dart: czytnik: system B — etykiety „pod / nad linią”, to samo zdanie',
        'test/features/weld_symbols/weld_symbols_page_test.dart: wymiary: przelicznik a5 → z 7,07, z7 → a 4,95',
        'test/features/weld_symbols/weld_symbols_page_test.dart: wszystkie zakładki renderują się na telefonie, tekst ×1.3',
        'test/domain/weld_symbols/weld_symbol_description_test.dart: zdanie po ludzku przykład z rysunku — PL',
      ]),
  ModuleAuditEntry(
      id: 'weather-check',
      entryPoint: 'WeatherCheckPage',
      sourcePath: 'lib/features/weather_check/weather_check_page.dart',
      category: AuditCategory.welder,
      risk: AuditRisk.safetyCritical,
      status: AuditStatus.passed,
      scenario:
          '15 °C, RH 50 %, wiatr 1 m/s, MMA: punkt rosy 4,7 °C, „Można spawać”; MAG przy 5 m/s bez osłony → „Nie spawać”, z parawanem → warunek „wiatr przy spoinie ≤ 2,2 m/s”; deszcz bez namiotu → „Nie spawać”, w namiocie → 2 warunki do odhaczenia; -5 °C, RH 80 %: rosa -7,9 °C, szron -7,0 °C, stal węglowa do ≥ 21 °C (nierdzewna ≥ 10 °C); brak temperatury powierzchni → widoczne założenie; próg wiatru gazu 5 m/s w ustawieniach → MAG przy 4 m/s „Można spawać”, przywrócenie domyślnych → „Nie spawać”; zapis do historii (weather_checks_v1) z miejscem, godziną i odhaczeniem; tekst i PDF.',
      evidence: [
        'test/features/weather_check/weather_check_page_test.dart: wpisanie wartości zmienia werdykt',
        'test/features/weather_check/weather_check_page_test.dart: brak temperatury powierzchni → założenie widoczne',
        'test/features/weather_check/weather_check_page_test.dart: ujemne temperatury z przecinkiem: mróz → podgrzać do 21 °C',
        'test/features/weather_check/weather_check_page_test.dart: ustawienia progów: zmiana, zapis i przywrócenie domyślnych',
        'test/features/weather_check/weather_check_page_test.dart: zapis do historii: wpis z miejscem, godziną i odhaczeniem',
        'test/features/weather_check/weather_check_page_test.dart: udostępnianie tekstu i PDF przez wstrzyknięte funkcje',
        'test/features/weather_check/weather_check_page_test.dart: wąski ekran 320×640, tekst ×1,3 — bez przepełnień',
        'test/domain/welding/weather_conditions_test.dart: punkt rosy: 20 °C / 50 % ≈ 9,3 °C',
        'test/domain/welding/weather_conditions_test.dart: werdykt: MMA vs MAG przy wietrze 5 m/s',
        'test/domain/welding/weather_conditions_test.dart: werdykt: opad bez namiotu → nie spawać; parawan nie pomaga; namiot → warunki',
        'test/domain/welding/weather_conditions_test.dart: werdykt: mróz: -18 °C (0 °F) jeszcze nie blokuje, -18,1 °C bez namiotu tak',
        'test/domain/welding/weather_conditions_test.dart: JSON: uszkodzone pojedyncze wpisy są pomijane, reszta zostaje',
      ]),
  ModuleAuditEntry(
      id: 'welder-identity-setup',
      entryPoint: 'WelderIdentitySetupScreen',
      sourcePath: 'lib/screens/welder_identity_setup_screen.dart',
      category: AuditCategory.account,
      risk: AuditRisk.medium,
      status: AuditStatus.unverified,
      scenario: 'Spawacz zapisuje identyfikator do podpisywania parametrów.'),
  ModuleAuditEntry(
      id: 'welder-menu',
      entryPoint: 'WelderMenuScreen',
      sourcePath: 'lib/screens/welder_menu_screen.dart',
      category: AuditCategory.welder,
      risk: AuditRisk.low,
      status: AuditStatus.unverified,
      scenario: 'Użytkownik otwiera menu modułów spawacza.',
      evidence: [
        'test/audit/module_smoke_test.dart: WelderMenuScreen renderuje przy skali tekstu 1,3',
      ]),
  ModuleAuditEntry(
      id: 'welder-pipes',
      entryPoint: 'WelderPipesScreen',
      sourcePath: 'lib/screens/welder_pipes_screen.dart',
      category: AuditCategory.welder,
      risk: AuditRisk.medium,
      status: AuditStatus.unverified,
      scenario: 'Użytkownik otwiera narzędzia spawalnicze dla rur.',
      evidence: [
        'test/audit/module_smoke_test.dart: WelderPipesScreen renderuje przy skali tekstu 1,3',
      ]),
  ModuleAuditEntry(
      id: 'welder-tanks',
      entryPoint: 'WelderTanksScreen',
      sourcePath: 'lib/screens/welder_tanks_screen.dart',
      category: AuditCategory.welder,
      risk: AuditRisk.medium,
      status: AuditStatus.unverified,
      scenario: 'Użytkownik otwiera narzędzia spawalnicze dla zbiorników.',
      evidence: [
        'test/audit/module_smoke_test.dart: WelderTanksScreen renderuje przy skali tekstu 1,3',
      ]),
  ModuleAuditEntry(
      id: 'welder-tools',
      entryPoint: 'WelderToolsScreen',
      sourcePath: 'lib/screens/welder_tools_screen.dart',
      category: AuditCategory.welder,
      risk: AuditRisk.low,
      status: AuditStatus.unverified,
      scenario: 'Użytkownik wybiera kalkulator z zestawu narzędzi spawacza.'),
  ModuleAuditEntry(
      id: 'wps-edit',
      entryPoint: 'WpsEditPage',
      sourcePath: 'lib/features/wps/wps_edit_page.dart',
      category: AuditCategory.welder,
      risk: AuditRisk.high,
      status: AuditStatus.passed,
      scenario:
          'WPS bez numeru nie jest zapisywana; WPS-7 z energią liniową 0,4–1,1 kJ/mm zapisuje się z konwencją EN.',
      evidence: [
        'test/features/qualification_pages_test.dart: formularz WPS: bez numeru nie zapisze',
        'test/features/qualification_pages_test.dart: formularz WPS: zakres energii liniowej zapisany z konwencją',
        'test/audit/module_smoke_test.dart: WpsEditPage renderuje przy skali tekstu 1,3',
      ]),
  ModuleAuditEntry(
      id: 'wps-library',
      entryPoint: 'WpsLibraryPage',
      sourcePath: 'lib/features/wps/wps_library_page.dart',
      category: AuditCategory.welder,
      risk: AuditRisk.high,
      status: AuditStatus.passed,
      scenario:
          'Import JSON ze schowka dodaje WPS-141-01 rev. B (z nowym identyfikatorem) do listy; tekst, który nie jest WPS, daje komunikat i nic nie dodaje.',
      evidence: [
        'test/features/qualification_pages_test.dart: import JSON ze schowka dodaje WPS do listy',
        'test/features/qualification_pages_test.dart: import czegoś, co nie jest WPS — komunikat, nic nie dodaje',
        'test/audit/module_smoke_test.dart: WpsLibraryPage renderuje przy skali tekstu 1,3',
      ]),
  ModuleAuditEntry(
      id: 'welder-pipe-param-edit',
      entryPoint: 'WelderPipeParamEditScreen',
      sourcePath:
          'lib/modules/welder_pipe/ui/welder_pipe_param_edit_screen.dart',
      category: AuditCategory.welder,
      risk: AuditRisk.high,
      status: AuditStatus.unverified,
      scenario:
          'Spawacz zapisuje parametry rury z prądem, napięciem i procesem.'),
  ModuleAuditEntry(
      id: 'welder-pipe-params-list',
      entryPoint: 'WelderPipeParamsListScreen',
      sourcePath:
          'lib/modules/welder_pipe/ui/welder_pipe_params_list_screen.dart',
      category: AuditCategory.welder,
      risk: AuditRisk.high,
      status: AuditStatus.passed,
      scenario:
          'Migracja v3-v5 zachowuje lokalny rekord parametrów rury, a restart produkcyjnej bazy nie duplikuje danych startowych.',
      evidence: [
        'test/audit/data_integrity_audit_test.dart: migracja v3-v5 zachowuje rekord po restarcie produkcyjnej bazy',
      ]),
  ModuleAuditEntry(
      id: 'tandem-calculator',
      entryPoint: 'TandemCalculatorScreen',
      sourcePath: 'lib/modules/welder_tandem/ui/tandem_calculator_screen.dart',
      category: AuditCategory.welder,
      risk: AuditRisk.safetyCritical,
      status: AuditStatus.domainReview,
      scenario:
          'Asymetryczny zestaw zachowuje inside/outside; mapowanie tych pól na lead/trail wymaga potwierdzenia domenowego.',
      evidence: [
        'test/audit/welder_calculations_audit_test.dart: asymetryczne 83/137 A nie jest zamieniane',
      ]),
  ModuleAuditEntry(
      id: 'tandem-library',
      entryPoint: 'TandemLibraryScreen',
      sourcePath: 'lib/modules/welder_tandem/ui/tandem_library_screen.dart',
      category: AuditCategory.welder,
      risk: AuditRisk.medium,
      status: AuditStatus.unverified,
      scenario: 'Użytkownik przegląda bibliotekę parametrów tandemowych.'),
  ModuleAuditEntry(
      id: 'tandem-menu',
      entryPoint: 'TandemMenuScreen',
      sourcePath: 'lib/modules/welder_tandem/ui/tandem_menu_screen.dart',
      category: AuditCategory.welder,
      risk: AuditRisk.low,
      status: AuditStatus.unverified,
      scenario: 'Użytkownik otwiera menu modułu tandemowego TIG.',
      evidence: [
        'test/audit/module_smoke_test.dart: TandemMenuScreen renderuje przy skali tekstu 1,3',
      ]),
  ModuleAuditEntry(
      id: 'tandem-my-params',
      entryPoint: 'TandemMyParamsScreen',
      sourcePath: 'lib/modules/welder_tandem/ui/tandem_my_params_screen.dart',
      category: AuditCategory.welder,
      risk: AuditRisk.high,
      status: AuditStatus.unverified,
      scenario: 'Użytkownik widzi własne zapisane parametry tandemowe.'),
];
