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
      id: 'quick-converter',
      entryPoint: 'QuickConverterScreen',
      sourcePath: 'lib/screens/quick_converter_screen.dart',
      category: AuditCategory.fitter,
      risk: AuditRisk.medium,
      status: AuditStatus.unverified,
      scenario: '25,4 mm konwertuje się na 1 cal.'),
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
