import 'dart:async';

import 'package:flutter/material.dart';

import '../config/feature_flags.dart';
import '../features/cone_layout/cone_layout_page.dart';
import '../features/cooling_time/cooling_time_page.dart';
import '../features/electrode_exposure/electrode_exposure_page.dart';
import '../features/filler/filler_selector_page.dart';
import '../features/fillet_strength/fillet_strength_page.dart';
import '../features/flange_check/flange_check_page.dart';
import '../features/glossary/glossary_page.dart';
import '../features/hardness/hardness_page.dart';
import '../features/hot_work/hot_work_page.dart';
import '../features/weather_check/weather_check_page.dart';
import '../features/instruments/instrument_register_page.dart';
import '../features/iso5817/iso5817_page.dart';
import '../features/mitre_bend/mitre_bend_page.dart';
import '../features/progress/progress_page.dart';
import '../features/steel_weight/steel_weight_page.dart';
import '../features/pwht/pwht_planner_page.dart';
import '../features/weld_symbols/weld_symbols_page.dart';
import '../features/qualification/certificate_register_page.dart';
import '../features/quotes/hourly_rate_page.dart';
import '../features/quotes/quote_list_page.dart';
import '../features/wps/wps_library_page.dart';
import '../i18n/app_language.dart';
import '../legal/legal_texts.dart';
import '../screens/ai_chat_screen.dart';
import '../screens/bolt_torque_screen.dart';
import '../screens/chat_screen.dart';
import '../screens/component_library_screen.dart';
import '../screens/coupon_log_screen.dart';
import '../screens/dn_mm_screen.dart';
import '../screens/elbow_takeout_screen.dart';
import '../screens/fitter_tools_screen.dart';
import '../screens/heat_input_screen.dart';
import '../screens/help_screen.dart';
import '../screens/heat_tint_screen.dart';
import '../screens/hydrotest_screen.dart';
import '../screens/iso_notebook_screen.dart';
import '../screens/iso_scanner_screen.dart';
import '../screens/legal_screen.dart';
import '../screens/orbital_tig_screen.dart';
import '../screens/passivation_screen.dart';
import '../screens/pipe_route_calculator_screen.dart';
import '../screens/pipe_schedule_screen.dart';
import '../screens/pipe_slope_screen.dart';
import '../screens/pre_weld_checklist_screen.dart';
import '../screens/profile_screen.dart';
import '../screens/projects_screen.dart';
import '../screens/quick_converter_screen.dart';
import '../screens/rolling_offset_screen.dart';
import '../screens/saddle_cut_screen.dart';
import '../screens/saddle_template_screen.dart';
import '../screens/sanitary_tube_screen.dart';
import '../screens/support_config_screen.dart';
import '../screens/tungsten_screen.dart';
import '../screens/weld_journal_screen.dart';
import '../screens/welder_identity_setup_screen.dart';
import '../screens/welder_pipes_screen.dart';
import '../screens/welder_tanks_screen.dart';
import '../screens/welder_tools_screen.dart';
import '../services/help_search.dart' show normalizeForSearch;
import '../services/tool_usage.dart';
import 'community_gate.dart';

// Jeden rejestr narzędzi dla menu montera, menu spawacza, wyszukiwarki,
// „ostatnio używanych" i przypiętych na ekranie głównym.
//
// Zasady:
//   • jedno narzędzie = jeden wpis. Dwa ekrany, które robią różne rzeczy, mają
//     różne nazwy (np. „Cięcie pod spadek" ≠ „Spadek rury");
//   • identyfikatory są trwałe — lądują w SharedPreferences (ostatnio używane,
//     przypięte). Zmieniaj tytuły do woli, identyfikatorów nie;
//   • tytuły zdaniem, nie WERSALIKAMI; skróty branżowe (DN, TIG, CE) zostają;
//   • ekrany-sieroty (TandemMenuScreen, WelderPipeParamsListScreen,
//     RegisterScreen, TutorScreen, NewCutListProjectScreen) celowo NIE są tu
//     wpisane — nie mają dziś wejścia w aplikacji i nie dostają go tylnymi
//     drzwiami przez wyszukiwarkę.

enum ToolSection { fitter, welder }

extension ToolSectionText on ToolSection {
  String label(BuildContext context) => switch (this) {
        ToolSection.fitter => context.tr(pl: 'Monter', en: 'Fitter'),
        ToolSection.welder => context.tr(pl: 'Spawacz', en: 'Welder'),
      };
}

/// Grupy w menu, w kolejności wyświetlania. Kolejność sekcji (monter, potem
/// spawacz) jest ta sama co na ekranie głównym.
enum ToolGroup {
  cutProjects(ToolSection.fitter, 'Cięcie i projekty', 'Cutting and projects'),
  elbowsFittings(
      ToolSection.fitter, 'Kolana i kształtki', 'Elbows and fittings'),
  branches(ToolSection.fitter, 'Odgałęzienia i siodła', 'Branches and saddles'),
  routeSlope(ToolSection.fitter, 'Trasa i spadki', 'Route and slope'),
  tables(ToolSection.fitter, 'Tabele i przeliczniki', 'Tables and converters'),
  supportsFlanges(
      ToolSection.fitter, 'Podpory i kołnierze', 'Supports and flanges'),
  weldParams(ToolSection.welder, 'Parametry spawania', 'Welding parameters'),
  weldCalculators(ToolSection.welder, 'Kalkulatory', 'Calculators'),
  inspection(
      ToolSection.welder, 'Kontrola i dokumentacja', 'Inspection and records'),
  stainlessFinish(
      ToolSection.welder, 'Wykończenie nierdzewki', 'Stainless finishing'),
  costing(ToolSection.welder, 'Wyceny i koszty', 'Quotes and costs');

  const ToolGroup(this.section, this.titlePl, this.titleEn);

  final ToolSection section;
  final String titlePl;
  final String titleEn;

  String title(BuildContext context) => context.tr(pl: titlePl, en: titleEn);
}

class ToolSpec {
  /// Trwały identyfikator (zapisywany w SharedPreferences).
  final String id;
  final ToolGroup group;
  final String titlePl;
  final String titleEn;
  final String subtitlePl;
  final String subtitleEn;
  final IconData icon;
  final Color color;
  final WidgetBuilder builder;

  /// Słowa, po których monter szuka narzędzia. Bez polskich znaków nie trzeba —
  /// wyszukiwarka i tak je zwija (ą→a, ł→l…).
  final List<String> keywordsPl;
  final List<String> keywordsEn;

  /// Narzędzie wysyła dane na serwer pod nazwiskiem montera — przed otwarciem
  /// przechodzi przez bramkę imienia i zasad (community_gate.dart).
  final bool needsAccount;

  /// Widoczność zależna od flag (np. skaner tylko, gdy da się go użyć —
  /// darmowy tryb albo Premium do kupienia).
  final bool available;

  const ToolSpec({
    required this.id,
    required this.group,
    required this.titlePl,
    required this.titleEn,
    required this.subtitlePl,
    required this.subtitleEn,
    required this.icon,
    required this.color,
    required this.builder,
    this.keywordsPl = const [],
    this.keywordsEn = const [],
    this.needsAccount = false,
    this.available = true,
  });

  ToolSection get section => group.section;

  String title(BuildContext context) => context.tr(pl: titlePl, en: titleEn);
  String subtitle(BuildContext context) =>
      context.tr(pl: subtitlePl, en: subtitleEn);
}

// ─── Rejestr ────────────────────────────────────────────────────────────────

/// Wszystkie wpisy, łącznie z chwilowo niedostępnymi. Do UI używaj
/// [availableTools] / [toolsInGroup] / [toolById].
final List<ToolSpec> kToolRegistry = [
  // ── Monter · Cięcie i projekty ───────────────────────────────────────────
  ToolSpec(
    id: 'cut_list',
    group: ToolGroup.cutProjects,
    titlePl: 'Lista cięć',
    titleEn: 'Cut list',
    subtitlePl: 'Projekty, segmenty, długości do cięcia',
    subtitleEn: 'Projects, segments, cut lengths',
    icon: Icons.assignment_outlined,
    color: const Color(0xFFFF8E1E),
    builder: (_) => const ProjectsScreen(),
    keywordsPl: const [
      'cut list',
      'cutlista',
      'lista ciec',
      'projekt',
      'projekty',
      'segment',
      'ciecie',
      'dlugosc',
      'rura',
      'bom',
      'material'
    ],
    keywordsEn: const [
      'cut list',
      'project',
      'segment',
      'cutting',
      'length',
      'pipe',
      'bom',
      'material'
    ],
  ),
  ToolSpec(
    id: 'iso_notebook',
    group: ToolGroup.cutProjects,
    titlePl: 'Zeszyt ISO',
    titleEn: 'ISO notebook',
    subtitlePl: 'Trasy i numery linii na siatce izometrycznej',
    subtitleEn: 'Routes and line tags on an isometric grid',
    icon: Icons.grid_on,
    color: const Color(0xFF5C6BC0),
    builder: (_) => const IsoNotebookScreen(),
    keywordsPl: const [
      'izometria',
      'izometryk',
      'iso',
      'siatka',
      'rysunek',
      'szkic',
      'linia',
      'trasa',
      'zeszyt'
    ],
    keywordsEn: const [
      'isometric',
      'iso',
      'grid',
      'drawing',
      'sketch',
      'line',
      'notebook'
    ],
  ),
  ToolSpec(
    id: 'iso_scanner',
    group: ToolGroup.cutProjects,
    titlePl: 'Skaner izometryku',
    titleEn: 'Iso scanner',
    subtitlePl: 'Zdjęcie rysunku → lista cięć (wymaga internetu)',
    subtitleEn: 'Photo of a drawing → cut list (needs internet)',
    icon: Icons.document_scanner_outlined,
    color: const Color(0xFFEF6C00),
    builder: (_) => const IsoScannerScreen(),
    keywordsPl: const [
      'skaner',
      'zdjecie',
      'aparat',
      'ai',
      'rysunek',
      'izometryk',
      'skanuj'
    ],
    keywordsEn: const ['scanner', 'scan', 'photo', 'camera', 'ai', 'drawing'],
    // Zdjęcie rysunku idzie na serwer, ale nie pod nazwiskiem — zamiast
    // bramki czatu (imię + zasady) ekran pyta o zgodę na wysyłkę tuż przed
    // pierwszym skanem (scan_consent_gate.dart). Ręczne wpisywanie działa bez.
    needsAccount: false,
    // Darmowy tryb z dziennym limitem albo Premium, które da się kupić.
    available: kAiScannerReachable,
  ),
  ToolSpec(
    id: 'component_library',
    group: ToolGroup.cutProjects,
    titlePl: 'Biblioteka komponentów',
    titleEn: 'Component library',
    subtitlePl: 'Twoje kolana, redukcje, zawory — SS / CS',
    subtitleEn: 'Your elbows, reducers, valves — SS / CS',
    icon: Icons.inventory_2_outlined,
    color: const Color(0xFF78909C),
    builder: (_) => const ComponentLibraryScreen(),
    keywordsPl: const [
      'komponent',
      'komponenty',
      'biblioteka',
      'katalog',
      'zawor',
      'kolnierz',
      'trojnik',
      'ksztaltka'
    ],
    keywordsEn: const [
      'component',
      'library',
      'catalogue',
      'catalog',
      'fitting',
      'valve',
      'flange',
      'tee'
    ],
  ),
  ToolSpec(
    id: 'bevel',
    group: ToolGroup.cutProjects,
    titlePl: 'Fazowanie',
    titleEn: 'Bevel',
    subtitlePl: 'Kąt fazy, próg, szczelina (EN ISO 9692)',
    subtitleEn: 'Bevel angle, root face, gap (EN ISO 9692)',
    icon: Icons.change_history,
    color: const Color(0xFF9575CD),
    builder: (_) => const FitterToolsScreen(initialTab: 6),
    keywordsPl: const [
      'faza',
      'fazowanie',
      'ukosowanie',
      'prog',
      'szczelina',
      'przygotowanie',
      'rowek',
      '9692'
    ],
    keywordsEn: const [
      'bevel',
      'root face',
      'gap',
      'joint prep',
      'groove',
      '9692'
    ],
  ),

  // ── Monter · Kolana i kształtki ──────────────────────────────────────────
  ToolSpec(
    id: 'elbow_takeouts',
    group: ToolGroup.elbowsFittings,
    titlePl: 'Wymiary kolan',
    titleEn: 'Elbow takeouts',
    subtitlePl: 'Środek–czoło LR/SR 90° i 45° (ASME B16.9)',
    subtitleEn: 'Centre-to-face LR/SR 90° & 45° (ASME B16.9)',
    icon: Icons.table_rows_outlined,
    color: const Color(0xFFE57373),
    builder: (_) => const ElbowTakeoutScreen(),
    keywordsPl: const [
      'kolano',
      'kolana',
      'kolanko',
      'wymiar',
      'wymiary',
      'takeout',
      'odejscie',
      'lr',
      'sr',
      '90',
      '45',
      'b16.9'
    ],
    keywordsEn: const [
      'elbow',
      'takeout',
      'take-out',
      'center to face',
      'centre to face',
      'lr',
      'sr',
      'long radius',
      'short radius',
      'b16.9'
    ],
  ),
  ToolSpec(
    id: 'elbow_cut',
    group: ToolGroup.elbowsFittings,
    titlePl: 'Cięcie kolanka',
    titleEn: 'Elbow cut',
    subtitlePl: 'Kolano docięte na kąt docelowy',
    subtitleEn: 'Trim an elbow to the target angle',
    icon: Icons.content_cut_outlined,
    color: const Color(0xFF26A69A),
    builder: (_) => const FitterToolsScreen(initialTab: 1),
    keywordsPl: const [
      'kolano',
      'kolanko',
      'ciecie',
      'kat',
      'przyciac',
      'dociac'
    ],
    keywordsEn: const ['elbow', 'cut', 'angle', 'trim'],
  ),
  ToolSpec(
    id: 'elbow_rotation',
    group: ToolGroup.elbowsFittings,
    titlePl: 'Obrót kolanka',
    titleEn: 'Elbow rotation',
    subtitlePl: 'Obrót w % i w stopniach',
    subtitleEn: 'Rotation in % and degrees',
    icon: Icons.rotate_right,
    color: const Color(0xFF42A5F5),
    builder: (_) => const FitterToolsScreen(initialTab: 2),
    keywordsPl: const ['obrot', 'kolano', 'kolanko', 'kat', 'skret', 'roll'],
    keywordsEn: const ['rotation', 'roll', 'elbow', 'angle'],
  ),
  ToolSpec(
    id: 'insert',
    group: ToolGroup.elbowsFittings,
    titlePl: 'Wstawka',
    titleEn: 'Insert',
    subtitlePl: 'Ø / R / kąt / odejście',
    subtitleEn: 'Ø / R / angle / offset',
    icon: Icons.straighten,
    color: const Color(0xFFAB47BC),
    builder: (_) => const FitterToolsScreen(initialTab: 3),
    keywordsPl: const [
      'wstawka',
      'odcinek',
      'kolano',
      'odejscie',
      'promien',
      'przesuniecie'
    ],
    keywordsEn: const ['insert', 'spool', 'offset', 'radius'],
  ),
  ToolSpec(
    id: 'reducer',
    group: ToolGroup.elbowsFittings,
    titlePl: 'Skracanie redukcji',
    titleEn: 'Reducer trimming',
    subtitlePl: 'Docięcie do Ø wyjściowej',
    subtitleEn: 'Trim to the outlet Ø',
    icon: Icons.compress,
    color: const Color(0xFFEF5350),
    builder: (_) => const FitterToolsScreen(initialTab: 4),
    keywordsPl: const ['redukcja', 'skracanie', 'zwezka', 'srednica', 'dociac'],
    keywordsEn: const ['reducer', 'trim', 'concentric', 'outlet'],
  ),

  ToolSpec(
    id: 'mitre_bend',
    group: ToolGroup.elbowsFittings,
    // „Segmentowe kolana”, nie „Kolano segmentowe”: na zapytanie „kolano”
    // pierwsze mają zostać „Wymiary kolan” (najczęstsza potrzeba).
    titlePl: 'Segmentowe kolana',
    titleEn: 'Mitred bends',
    subtitlePl: 'Kolano z segmentów rury: kąt cięcia, długości, szablon 1:1',
    subtitleEn: 'Segments from pipe: cut angle, lengths, 1:1 template',
    icon: Icons.turn_right,
    color: const Color(0xFFFFB74D),
    builder: (_) => const MitreBendPage(),
    keywordsPl: const [
      'segmentowe',
      'kolano segmentowe',
      'lobster',
      'segment',
      'segmenty',
      'ciecie ukosne',
      'kolano z rury',
      'szablon kolana'
    ],
    keywordsEn: const [
      'mitred bend',
      'mitered bend',
      'miter',
      'mitre',
      'lobster back',
      'segmented elbow',
      'gored elbow'
    ],
  ),
  ToolSpec(
    id: 'cone_layout',
    group: ToolGroup.elbowsFittings,
    titlePl: 'Rozwinięcie stożka i przejść',
    titleEn: 'Cone & transition layout',
    subtitlePl:
        'Lej, stożek, kwadrat–koło: wymiary do trasowania, szablon 1:1',
    subtitleEn: 'Cones, hoppers, square to round: layout data, 1:1 template',
    icon: Icons.filter_alt_outlined,
    color: const Color(0xFF4DB6AC),
    builder: (_) => const ConeLayoutPage(),
    keywordsPl: const [
      'stozek',
      'stozek sciety',
      'lej',
      'rozwiniecie',
      'rozwiniecie blachy',
      'kwadrat kolo',
      'przejscie kwadrat kolo',
      'przejscie',
      'mimosrodowy',
      'triangulacja',
      'trasowanie',
      'kotlarz',
      'zbiornik',
      'kanal',
      'szablon stozka'
    ],
    keywordsEn: const [
      'cone',
      'frustum',
      'cone layout',
      'flat pattern',
      'development',
      'square to round',
      'transition',
      'eccentric cone',
      'hopper',
      'funnel',
      'triangulation',
      'sheet metal',
      'boilermaker'
    ],
  ),

  // ── Monter · Odgałęzienia i siodła ───────────────────────────────────────
  // Dwa różne narzędzia: tabela dla odgałęzienia 90° i szablon do druku dla
  // dowolnego kąta. Nazwy mówią, które jest które.
  ToolSpec(
    id: 'saddle_cut',
    group: ToolGroup.branches,
    titlePl: 'Siodło 90° — tabela',
    titleEn: 'Saddle 90° — table',
    subtitlePl: 'Wycięcie siodłowe co 15°, odgałęzienie centralne',
    subtitleEn: 'Fish-mouth cut every 15°, centred branch',
    icon: Icons.join_full_outlined,
    color: const Color(0xFF8E24AA),
    builder: (_) => const SaddleCutScreen(),
    keywordsPl: const [
      'siodlo',
      'siodelko',
      'wyciecie',
      'odgalezienie',
      'trojnik',
      'wcinka',
      'saddle',
      'fish mouth'
    ],
    keywordsEn: const [
      'saddle',
      'fish mouth',
      'branch',
      'cope',
      'coping',
      'tee'
    ],
  ),
  ToolSpec(
    id: 'saddle_template',
    group: ToolGroup.branches,
    titlePl: 'Szablon siodła do druku',
    titleEn: 'Printable saddle template',
    subtitlePl: 'Dowolny kąt 15–90°, PDF 1:1 do owinięcia rury',
    subtitleEn: 'Any angle 15–90°, 1:1 PDF to wrap the pipe',
    icon: Icons.crop_din_outlined,
    color: const Color(0xFF26A69A),
    builder: (_) => const SaddleTemplateScreen(),
    keywordsPl: const [
      'szablon',
      'siodlo',
      'druk',
      'drukuj',
      'pdf',
      'coping',
      'odgalezienie',
      'kat',
      'saddle'
    ],
    keywordsEn: const [
      'template',
      'saddle',
      'print',
      'pdf',
      'coping',
      'wrap',
      'branch'
    ],
  ),

  // ── Monter · Trasa i spadki ──────────────────────────────────────────────
  ToolSpec(
    id: 'pipe_route',
    group: ToolGroup.routeSlope,
    titlePl: 'Trasa rur',
    titleEn: 'Pipe route',
    subtitlePl: '2 kolana 90° — długości odcinków',
    subtitleEn: '2 × 90° elbows — segment lengths',
    icon: Icons.account_tree_outlined,
    color: const Color(0xFF00897B),
    builder: (_) => const PipeRouteCalculatorScreen(),
    keywordsPl: const [
      'trasa',
      'odcinek',
      'odcinki',
      'kolano',
      'rurociag',
      'uklad',
      'dlugosc'
    ],
    keywordsEn: const ['route', 'run', 'segment', 'elbow', 'layout', 'length'],
  ),
  ToolSpec(
    id: 'rolling_offset',
    group: ToolGroup.routeSlope,
    titlePl: 'Rolling offset',
    titleEn: 'Rolling offset',
    subtitlePl: 'Przesunięcie w dwóch płaszczyznach: rise + spread → travel',
    subtitleEn: 'Offset in two planes: rise + spread → travel',
    icon: Icons.swap_vert_circle_outlined,
    color: const Color(0xFF1E88E5),
    builder: (_) => const RollingOffsetScreen(),
    keywordsPl: const [
      'rolling',
      'offset',
      'przesuniecie',
      'odsadzka',
      'travel',
      'rise',
      'spread',
      'ukos'
    ],
    keywordsEn: const ['rolling', 'offset', 'travel', 'rise', 'spread'],
  ),
  ToolSpec(
    id: 'pipe_slope',
    group: ToolGroup.routeSlope,
    titlePl: 'Spadek rury',
    titleEn: 'Pipe fall',
    subtitlePl: 'Spadek trasy: %, mm/m, kąt, różnica wysokości',
    subtitleEn: 'Line slope: %, mm/m, angle, rise',
    icon: Icons.show_chart,
    color: const Color(0xFFFF7043),
    builder: (_) => const PipeSlopeScreen(),
    keywordsPl: const [
      'spadek',
      'nachylenie',
      'procent',
      'mm/m',
      'kat',
      'wysokosc',
      'kanalizacja',
      'grawitacja'
    ],
    keywordsEn: const [
      'slope',
      'fall',
      'gradient',
      'grade',
      'percent',
      'pitch',
      'rise'
    ],
  ),
  ToolSpec(
    id: 'slope_cut',
    group: ToolGroup.routeSlope,
    titlePl: 'Cięcie pod spadek',
    titleEn: 'Slope cut',
    subtitlePl: 'Jedno cięcie na skos: Δh na przekroju i kąt piły',
    subtitleEn: 'Single angled cut: Δh across the pipe and saw angle',
    icon: Icons.trending_down,
    color: const Color(0xFFFFA726),
    builder: (_) => const FitterToolsScreen(initialTab: 0),
    keywordsPl: const [
      'spadek',
      'ciecie',
      'skos',
      'pila',
      'miter',
      'kat',
      'ukos'
    ],
    keywordsEn: const ['slope', 'miter', 'mitre', 'cut', 'saw', 'angle'],
  ),
  ToolSpec(
    id: 'thermal_expansion',
    group: ToolGroup.routeSlope,
    titlePl: 'Dylatacja',
    titleEn: 'Thermal expansion',
    subtitlePl: 'Wydłużenie rurociągu od różnicy temperatur',
    subtitleEn: 'Pipe growth from a temperature difference',
    icon: Icons.thermostat,
    color: const Color(0xFF4DB6AC),
    builder: (_) => const FitterToolsScreen(initialTab: 7),
    keywordsPl: const [
      'dylatacja',
      'wydluzenie',
      'temperatura',
      'kompensator',
      'rozszerzalnosc',
      'cieplna',
      'delta t'
    ],
    keywordsEn: const [
      'expansion',
      'thermal',
      'growth',
      'temperature',
      'compensator',
      'delta t'
    ],
  ),

  // ── Monter · Tabele i przeliczniki ───────────────────────────────────────
  ToolSpec(
    id: 'dn_mm',
    group: ToolGroup.tables,
    titlePl: 'DN ↔ mm',
    titleEn: 'DN ↔ mm',
    subtitlePl: 'DN ↔ OD (mm) + NPS',
    subtitleEn: 'DN ↔ OD (mm) + NPS',
    icon: Icons.table_chart_outlined,
    color: const Color(0xFF5C6BC0),
    builder: (_) => const DnMmScreen(),
    keywordsPl: const [
      'dn',
      'nps',
      'srednica',
      'od',
      'cal',
      'cale',
      'mm',
      'rozmiar',
      'tabela'
    ],
    keywordsEn: const ['dn', 'nps', 'diameter', 'od', 'inch', 'size', 'table'],
  ),
  ToolSpec(
    id: 'wall_thickness',
    group: ToolGroup.tables,
    titlePl: 'Grubości ścianek',
    titleEn: 'Wall thickness',
    subtitlePl: 'Sch 10S / STD / 40 / 80 / 160 + kg/m',
    subtitleEn: 'Sch 10S / STD / 40 / 80 / 160 + kg/m',
    icon: Icons.view_column_outlined,
    color: const Color(0xFF7E57C2),
    builder: (_) => const PipeScheduleScreen(),
    keywordsPl: const [
      'scianka',
      'scianki',
      'grubosc',
      'schedule',
      'sch',
      'std',
      'xs',
      'tabela'
    ],
    keywordsEn: const ['wall', 'thickness', 'schedule', 'sch', 'std', 'xs'],
  ),
  ToolSpec(
    id: 'pipe_weight',
    group: ToolGroup.tables,
    titlePl: 'Ciężar rury',
    titleEn: 'Pipe weight',
    subtitlePl: 'kg/m i masa odcinka z OD i ścianki',
    subtitleEn: 'kg/m and run weight from OD and wall',
    icon: Icons.scale_outlined,
    color: const Color(0xFFA1887F),
    builder: (_) => const FitterToolsScreen(initialTab: 5),
    keywordsPl: const [
      'ciezar',
      'waga',
      'masa',
      'kg',
      'kilogram',
      'rura',
      'dzwig',
      'transport'
    ],
    keywordsEn: const ['weight', 'mass', 'kg', 'pipe', 'lift'],
  ),
  // Po „Ciężar rury”: przy remisie w wyszukiwarce („ciężar”, „weight”)
  // pierwsza ma zostać rura.
  ToolSpec(
    id: 'steel_weight',
    group: ToolGroup.tables,
    titlePl: 'Ciężar stali — profile',
    titleEn: 'Steel weight — sections',
    subtitlePl: 'IPE, HEB, UPN, kątowniki, blachy · lista i koszt',
    subtitleEn: 'IPE, HEB, UPN, angles, plates · list and cost',
    icon: Icons.view_in_ar_outlined,
    color: const Color(0xFF546E7A),
    builder: (_) => const SteelWeightPage(),
    keywordsPl: const [
      'stal',
      'profil',
      'profile',
      'belka',
      'dwuteownik',
      'ipe',
      'hea',
      'heb',
      'hem',
      'ceownik',
      'upn',
      'upe',
      'katownik',
      'plaskownik',
      'pret',
      'blacha',
      'zamkniety',
      'masa stali',
      'lista materialowa',
      'zamowienie stali',
      'tonaz',
      'malowanie',
      'dzwig'
    ],
    keywordsEn: const [
      'steel',
      'beam',
      'section',
      'channel',
      'angle',
      'flat bar',
      'round bar',
      'plate',
      'shs',
      'rhs',
      'hollow section',
      'material list',
      'tonnage',
      'paint area'
    ],
  ),
  ToolSpec(
    id: 'sanitary_tube',
    group: ToolGroup.tables,
    titlePl: 'Rury sanitarne',
    titleEn: 'Sanitary tube',
    subtitlePl: 'Spożywka i farmacja: ASME BPE + DIN 11850',
    subtitleEn: 'Food and pharma: ASME BPE + DIN 11850',
    icon: Icons.water_drop_outlined,
    color: const Color(0xFF26A69A),
    builder: (_) => const SanitaryTubeScreen(),
    keywordsPl: const [
      'sanitarne',
      'spozywka',
      'spozywcza',
      'farmacja',
      'bpe',
      'din 11850',
      'nierdzewka',
      'rurka'
    ],
    keywordsEn: const ['sanitary', 'food', 'pharma', 'bpe', 'tube', 'hygienic'],
  ),
  ToolSpec(
    id: 'unit_converter',
    group: ToolGroup.tables,
    titlePl: 'Konwerter jednostek',
    titleEn: 'Unit converter',
    subtitlePl: 'mm/in, °C/°F, bar/MPa/psi',
    subtitleEn: 'mm/in, °C/°F, bar/MPa/psi',
    icon: Icons.swap_horiz_outlined,
    color: const Color(0xFF66BB6A),
    builder: (_) => const QuickConverterScreen(),
    keywordsPl: const [
      'jednostki',
      'przelicz',
      'przelicznik',
      'konwerter',
      'cale',
      'cal',
      'bar',
      'psi',
      'mpa',
      'fahrenheit',
      'stopnie'
    ],
    keywordsEn: const [
      'units',
      'convert',
      'converter',
      'inch',
      'bar',
      'psi',
      'mpa',
      'fahrenheit'
    ],
  ),
  ToolSpec(
    id: 'glossary',
    group: ToolGroup.tables,
    titlePl: 'Słownik spawalniczy',
    titleEn: 'Welding dictionary',
    subtitlePl:
        'PL · EN · DE · NL · NO: terminy, niezgodności ISO 6520, zwroty na budowę',
    subtitleEn:
        'PL · EN · DE · NL · NO: terms, ISO 6520 imperfections, site phrases',
    icon: Icons.translate,
    color: const Color(0xFF7986CB),
    builder: (_) => const GlossaryPage(),
    keywordsPl: const [
      'slownik',
      'slownik spawalniczy',
      'tlumacz',
      'tlumaczenie',
      'jezyki',
      'niemiecki',
      'holenderski',
      'niderlandzki',
      'norweski',
      'angielski',
      'rozmowki',
      'zwroty',
      'za granica',
      'niemcy',
      'holandia',
      'belgia',
      'norwegia',
      'nazwy niezgodnosci',
      'iso 6520',
      'iso 4063'
    ],
    keywordsEn: const [
      'dictionary',
      'glossary',
      'translate',
      'translation',
      'german',
      'dutch',
      'norwegian',
      'phrases',
      'abroad',
      'terminology',
      'iso 6520',
      'iso 4063'
    ],
  ),

  // ── Monter · Podpory i kołnierze ─────────────────────────────────────────
  ToolSpec(
    id: 'pipe_supports',
    group: ToolGroup.supportsFlanges,
    titlePl: 'Podpory rur',
    titleEn: 'Pipe supports',
    subtitlePl: 'Rozstaw, typy, zasady',
    subtitleEn: 'Spacing, types, rules',
    icon: Icons.anchor_outlined,
    color: const Color(0xFF8D6E63),
    builder: (_) => const SupportConfigScreen(),
    keywordsPl: const [
      'podpora',
      'podpory',
      'wieszak',
      'rozstaw',
      'uchwyt',
      'support'
    ],
    keywordsEn: const ['support', 'hanger', 'spacing', 'span'],
  ),
  ToolSpec(
    id: 'bolt_torque',
    group: ToolGroup.supportsFlanges,
    titlePl: 'Moment śrub',
    titleEn: 'Bolt torque',
    subtitlePl: 'Kołnierze: B7 / B7M / B16 / B8M',
    subtitleEn: 'Flanges: B7 / B7M / B16 / B8M',
    icon: Icons.build_outlined,
    color: const Color(0xFFE8C14B),
    builder: (_) => const BoltTorqueScreen(),
    keywordsPl: const [
      'moment',
      'sruba',
      'sruby',
      'kolnierz',
      'kolnierze',
      'dokrecanie',
      'klucz',
      'nm',
      'b7'
    ],
    keywordsEn: const [
      'torque',
      'bolt',
      'flange',
      'tightening',
      'wrench',
      'nm'
    ],
  ),
  ToolSpec(
    id: 'flange_check',
    group: ToolGroup.supportsFlanges,
    titlePl: 'Odbiór połączenia kołnierzowego',
    titleEn: 'Flange joint check',
    subtitlePl: 'Osiowość wg PCC-1, lista montażu, protokół PDF',
    subtitleEn: 'PCC-1 alignment, assembly checklist, PDF record',
    icon: Icons.adjust,
    color: const Color(0xFF81C784),
    builder: (_) => const FlangeCheckPage(),
    keywordsPl: const [
      'kolnierz',
      'kolnierze',
      'flansza',
      'odbior kolnierza',
      'osiowosc',
      'osiowanie',
      'rownoleglosc',
      'szczelina',
      'uszczelka',
      'pcc-1',
      'protokol',
      'montaz kolnierzy',
      'skrecanie kolnierzy'
    ],
    keywordsEn: const [
      'flange',
      'flange joint',
      'flange alignment',
      'pcc-1',
      'gasket',
      'bolt up',
      'high low',
      'parallelism',
      'joint assembly',
      'checklist'
    ],
  ),

  // ── Spawacz · Parametry spawania ─────────────────────────────────────────
  ToolSpec(
    id: 'welder_pipes',
    group: ToolGroup.weldParams,
    titlePl: 'Parametry — rury',
    titleEn: 'Pipe parameters',
    subtitlePl: 'Prąd, gazy, zatwierdzone, moje',
    subtitleEn: 'Amps, gases, approved, mine',
    icon: Icons.oil_barrel_outlined,
    color: const Color(0xFFE67E22),
    builder: (_) => const WelderPipesScreen(),
    keywordsPl: const [
      'parametry',
      'rury',
      'prad',
      'amper',
      'amp',
      'gaz',
      'tig',
      'wps',
      'natezenie'
    ],
    keywordsEn: const [
      'parameters',
      'pipe',
      'amps',
      'current',
      'gas',
      'tig',
      'wps'
    ],
  ),
  ToolSpec(
    id: 'welder_tanks',
    group: ToolGroup.weldParams,
    titlePl: 'Parametry — zbiorniki',
    titleEn: 'Tank parameters',
    subtitlePl: 'Prąd, tandem TIG',
    subtitleEn: 'Amps, tandem TIG',
    icon: Icons.propane_tank_outlined,
    color: const Color(0xFFEF5350),
    builder: (_) => const WelderTanksScreen(),
    keywordsPl: const [
      'zbiornik',
      'zbiorniki',
      'tandem',
      'tig',
      'prad',
      'parametry'
    ],
    keywordsEn: const ['tank', 'tandem', 'tig', 'amps', 'parameters'],
  ),
  ToolSpec(
    id: 'orbital_tig',
    group: ToolGroup.weldParams,
    titlePl: 'Orbital TIG',
    titleEn: 'Orbital TIG',
    subtitlePl: 'Parametry startowe, czas spoiny',
    subtitleEn: 'Starting parameters, weld time',
    icon: Icons.donut_large_outlined,
    color: const Color(0xFF26C6DA),
    builder: (_) => const OrbitalTigScreen(),
    keywordsPl: const ['orbital', 'orbitalne', 'tig', 'glowica', 'czas'],
    keywordsEn: const ['orbital', 'tig', 'head', 'weld time'],
  ),
  ToolSpec(
    id: 'tungsten',
    group: ToolGroup.weldParams,
    titlePl: 'Elektroda wolframowa',
    titleEn: 'Tungsten electrode',
    subtitlePl: 'Dobór Ø wg prądu, typy',
    subtitleEn: 'Ø by current, types',
    icon: Icons.bolt_outlined,
    color: const Color(0xFF5C6BC0),
    builder: (_) => const TungstenScreen(),
    keywordsPl: const [
      'wolfram',
      'elektroda',
      'tig',
      'ostrzenie',
      'wc20',
      'wl15'
    ],
    keywordsEn: const ['tungsten', 'electrode', 'tig', 'grinding'],
  ),
  ToolSpec(
    id: 'filler_selector',
    group: ToolGroup.weldParams,
    titlePl: 'Dobór spoiwa',
    titleEn: 'Filler metal selector',
    subtitlePl: 'Spoiwo EN ISO i AWS, gaz, formowanie',
    subtitleEn: 'EN ISO and AWS filler, gas, purge',
    icon: Icons.merge_type,
    color: const Color(0xFF8D6E63),
    builder: (_) => const FillerSelectorPage(),
    keywordsPl: const [
      'spoiwo',
      'drut',
      'pret',
      'elektroda',
      'dobor spoiwa',
      '309l',
      '308l',
      '316l',
      '2209',
      'roznoimienne',
      'nierdzewka',
      'czarna',
      'p91',
      'aluminium',
      'gaz oslonowy',
      'formowanie',
      'schaeffler',
      'rozcienczenie'
    ],
    keywordsEn: const [
      'filler',
      'filler metal',
      'wire',
      'rod',
      'electrode',
      'consumable',
      '309l',
      'dissimilar',
      'stainless',
      'p91',
      'aluminium',
      'shielding gas',
      'purge',
      'schaeffler',
      'dilution'
    ],
  ),
  // Asystent: pytania (serwer, po zgodzie) i zapis parametrów głosem (offline).
  // Bez `needsAccount` — tryb „Wykonaj" działa bez sieci i bez zgody; zgodę na
  // wysyłanie pytań ekran zbiera sam przy pierwszym pytaniu.
  ToolSpec(
    id: 'assistant',
    group: ToolGroup.weldParams,
    titlePl: 'Asystent',
    titleEn: 'Assistant',
    subtitlePl: 'Zapis parametrów głosem, pytania',
    subtitleEn: 'Save parameters by voice, questions',
    icon: Icons.record_voice_over_outlined,
    color: const Color(0xFF26A69A),
    builder: (_) => const AiChatScreen(),
    keywordsPl: const [
      'asystent',
      'ai',
      'glos',
      'glosowy',
      'mikrofon',
      'dyktowanie',
      'pytanie',
      'zapisz parametr'
    ],
    keywordsEn: const [
      'assistant',
      'ai',
      'voice',
      'microphone',
      'dictation',
      'question',
      'save parameter'
    ],
  ),

  // ── Spawacz · Kalkulatory ────────────────────────────────────────────────
  // Heat input i podgrzewanie mają jedno wejście: ekran „Heat input i CE".
  // Kafel poniżej prowadzi do pozostałych kalkulatorów spawacza i otwiera je
  // na zakładce z tytułu (gaz); zakładek heat input / temperatury już tam nie
  // ma.
  ToolSpec(
    id: 'heat_input',
    group: ToolGroup.weldCalculators,
    titlePl: 'Heat input i CE',
    titleEn: 'Heat input and CE',
    subtitlePl: 'Energia liniowa + podgrzewanie z chemii stali',
    subtitleEn: 'Arc energy + preheat from steel chemistry',
    icon: Icons.local_fire_department_outlined,
    color: const Color(0xFFE8C14B),
    builder: (_) => const HeatInputScreen(),
    keywordsPl: const [
      'heat input',
      'energia',
      'liniowa',
      'ce',
      'cev',
      'podgrzewanie',
      'preheat',
      'wegiel',
      'rownowaznik'
    ],
    keywordsEn: const [
      'heat input',
      'arc energy',
      'ce',
      'cev',
      'preheat',
      'carbon equivalent'
    ],
  ),
  ToolSpec(
    id: 'welder_calculators',
    group: ToolGroup.weldCalculators,
    titlePl: 'Gaz, formowanie i timer',
    titleEn: 'Gas, purge and timer',
    subtitlePl: 'Zużycie gazu, formowanie O₂, timer, ciśnienie',
    subtitleEn: 'Gas use, O₂ purge, timer, pressure',
    icon: Icons.calculate_outlined,
    color: const Color(0xFF4A9EFF),
    builder: (_) =>
        const WelderToolsScreen(initialTab: WelderToolsScreen.tabGas),
    keywordsPl: const [
      'gaz',
      'formowanie',
      'formierka',
      'purge',
      'tlen',
      'o2',
      'zuzycie',
      'timer',
      'stoper',
      'cisnienie',
      'argon'
    ],
    keywordsEn: const [
      'gas',
      'purge',
      'oxygen',
      'o2',
      'consumption',
      'timer',
      'pressure',
      'argon'
    ],
  ),

  ToolSpec(
    id: 'pwht_planner',
    group: ToolGroup.weldCalculators,
    titlePl: 'Obróbka cieplna po spawaniu',
    titleEn: 'Post-weld heat treatment',
    subtitlePl: 'Plan PWHT: czy wymagane, temperatura, czas, szybkości, wykres',
    subtitleEn: 'PWHT plan: required or not, temperature, hold, rates, chart',
    icon: Icons.thermostat_outlined,
    color: const Color(0xFFEF5350),
    builder: (_) => const PwhtPlannerPage(),
    keywordsPl: const [
      'pwht',
      'obrobka cieplna',
      'wyzarzanie',
      'odprezanie',
      'wygrzewanie',
      'temperatura wytrzymania',
      'czas wytrzymania',
      'szybkosc grzania',
      'p91',
      'cr-mo'
    ],
    keywordsEn: const [
      'pwht',
      'post weld heat treatment',
      'heat treatment',
      'stress relief',
      'soak',
      'holding time',
      'ramp rate',
      'p91'
    ],
  ),
  ToolSpec(
    id: 'fillet_strength',
    group: ToolGroup.weldCalculators,
    titlePl: 'Nośność spoiny pachwinowej',
    titleEn: 'Fillet weld resistance',
    subtitlePl: 'EN 1993-1-8: ile udźwignie spoina, jakie a wystarczy',
    subtitleEn: 'EN 1993-1-8: weld capacity and the throat a you need',
    icon: Icons.fitness_center,
    color: const Color(0xFFD4E157),
    builder: (_) => const FilletStrengthPage(),
    keywordsPl: const [
      'nosnosc spoiny',
      'spoina pachwinowa',
      'pachwinowa',
      'grubosc a',
      'wymagane a',
      'wspornik',
      'ucho',
      'podpora',
      'eurokod 3',
      'en 1993-1-8',
      'udzwig',
      'wytrzymalosc spoiny',
      'obciazenie spoiny'
    ],
    keywordsEn: const [
      'fillet weld',
      'weld strength',
      'weld capacity',
      'weld resistance',
      'throat size',
      'bracket',
      'lifting lug',
      'eurocode 3',
      'en 1993-1-8',
      'directional method'
    ],
  ),
  ToolSpec(
    id: 'cooling_time',
    group: ToolGroup.weldCalculators,
    titlePl: 'Czas stygnięcia t8/5',
    titleEn: 'Cooling time t8/5',
    subtitlePl: 'EN 1011-2 zał. D: okno t8/5, energia Q i podgrzewanie',
    subtitleEn: 'EN 1011-2 Annex D: t8/5 window, energy Q and preheat',
    icon: Icons.ac_unit,
    color: const Color(0xFF4FC3F7),
    builder: (_) => const CoolingTimePage(),
    keywordsPl: const [
      't8/5',
      't85',
      'czas stygniecia',
      'stygniecie',
      'chlodzenie',
      'swc',
      'strefa wplywu ciepla',
      'stal wysokowytrzymala',
      's690',
      's960',
      'strenx',
      'dillimax',
      'en 1011-2'
    ],
    keywordsEn: const [
      't8/5',
      'cooling time',
      'cooling rate',
      'haz',
      'high strength steel',
      'quenched and tempered',
      'tmcp',
      'en 1011-2'
    ],
  ),

  // ── Spawacz · Kontrola i dokumentacja ────────────────────────────────────
  ToolSpec(
    id: 'pre_weld_checklist',
    group: ToolGroup.inspection,
    titlePl: 'Checklista przed spawaniem',
    titleEn: 'Pre-weld checklist',
    subtitlePl: 'Kontrola złącza przed zajarzeniem łuku',
    subtitleEn: 'Joint check before you strike the arc',
    icon: Icons.checklist_rtl,
    color: const Color(0xFFFFA726),
    builder: (_) => const PreWeldChecklistScreen(),
    keywordsPl: const [
      'checklista',
      'kontrola',
      'lista',
      'przed spawaniem',
      'sprawdzenie'
    ],
    keywordsEn: const ['checklist', 'check', 'pre-weld', 'inspection'],
  ),
  ToolSpec(
    id: 'weather_check',
    group: ToolGroup.inspection,
    titlePl: 'Warunki do spawania',
    titleEn: 'Welding conditions',
    subtitlePl: 'Mróz, wiatr, deszcz, punkt rosy — czy wolno spawać',
    subtitleEn: 'Frost, wind, rain, dew point — OK to weld?',
    icon: Icons.wb_cloudy_outlined,
    color: const Color(0xFF78909C),
    builder: (_) => const WeatherCheckPage(),
    keywordsPl: const [
      'pogoda',
      'wiatr',
      'deszcz',
      'snieg',
      'mroz',
      'zima',
      'punkt rosy',
      'rosa',
      'wilgoc',
      'wilgotnosc',
      'kondensacja',
      'namiot',
      'oslona',
      'beaufort',
      'temperatura otoczenia',
      'spawanie w terenie',
      'aws d1.1'
    ],
    keywordsEn: const [
      'weather',
      'wind',
      'rain',
      'snow',
      'cold weather',
      'frost',
      'dew point',
      'humidity',
      'condensation',
      'shelter',
      'windbreak',
      'beaufort',
      'ambient temperature',
      'field welding',
      'aws d1.1'
    ],
  ),
  ToolSpec(
    id: 'hardness',
    group: ToolGroup.inspection,
    titlePl: 'Twardość: przelicznik i limity',
    titleEn: 'Hardness: converter and limits',
    subtitlePl: 'HV, HB, HRC, HRB wg ISO 18265; limity NACE, ISO 15614-1, B31.3',
    subtitleEn: 'HV, HB, HRC, HRB per ISO 18265; NACE, ISO 15614-1, B31.3 limits',
    icon: Icons.diamond_outlined,
    color: const Color(0xFF90A4AE),
    builder: (_) => const HardnessPage(),
    keywordsPl: const [
      'twardosc',
      'twardosci',
      'hv',
      'hv10',
      'hb',
      'hbw',
      'hrc',
      'hrb',
      'vickers',
      'brinell',
      'rockwell',
      'leeb',
      'uci',
      'przelicznik twardosci',
      'nace',
      'mr0175',
      '15156',
      'h2s',
      'srodowisko kwasne',
      '15614',
      'wpqr',
      'pwht',
      'swc',
      '18265'
    ],
    keywordsEn: const [
      'hardness',
      'hardness conversion',
      'vickers',
      'brinell',
      'rockwell',
      'leeb',
      'sour service',
      'nace',
      'iso 15156',
      'iso 15614',
      'pqr',
      'pwht',
      'haz',
      'astm e140',
      'iso 18265'
    ],
  ),
  ToolSpec(
    id: 'hot_work',
    group: ToolGroup.inspection,
    titlePl: 'Prace pożarowo niebezpieczne',
    titleEn: 'Hot work permit',
    subtitlePl: 'Zezwolenie, checklista stanowiska, pomiar DGW, protokół PDF',
    subtitleEn: 'Permit, work area checklist, LEL gas test, PDF record',
    icon: Icons.fire_extinguisher,
    color: const Color(0xFFFF7043),
    builder: (_) => const HotWorkPage(),
    keywordsPl: const [
      'prace pozarowe',
      'pozarowo niebezpieczne',
      'zezwolenie',
      'pozar',
      'ogien',
      'iskry',
      'dgw',
      'eksplozymetr',
      'dozor',
      'gasnica',
      'checklista pozarowa'
    ],
    keywordsEn: const [
      'hot work',
      'permit',
      'fire watch',
      'lel',
      'gas test',
      'fire'
    ],
  ),
  ToolSpec(
    id: 'electrode_exposure',
    group: ToolGroup.inspection,
    titlePl: 'Elektrody zasadowe: czas i suszenie',
    titleEn: 'Low-hydrogen electrodes: exposure',
    subtitlePl: 'Limit AWS D1.1 po wyjęciu z piecyka, suszenie, dziennik QC',
    subtitleEn: 'AWS D1.1 exposure limit, re-drying, QC log',
    icon: Icons.hourglass_bottom,
    color: const Color(0xFFBCAAA4),
    builder: (_) => const ElectrodeExposurePage(),
    keywordsPl: const [
      'elektroda',
      'elektrody',
      'zasadowe',
      'niskowodorowe',
      'e7018',
      '7018',
      'h4r',
      'suszenie',
      'piecyk',
      'termos',
      'kolczan',
      'wilgoc',
      'wodor',
      'pekniecia zimne',
      'czas na powietrzu',
      'vacpac',
      'sahara',
      'aws d1.1',
      'en iso 2560',
      'mma',
      '111'
    ],
    keywordsEn: const [
      'low hydrogen',
      'electrode',
      'stick',
      'smaw',
      'e7018',
      'h4r',
      'rebake',
      're-dry',
      'redry',
      'holding oven',
      'rod oven',
      'quiver',
      'atmospheric exposure',
      'moisture',
      'hydrogen cracking',
      'vacpac',
      'sahara readypack',
      'aws d1.1',
      'table 7.1'
    ],
  ),
  ToolSpec(
    id: 'weld_journal',
    group: ToolGroup.inspection,
    titlePl: 'Dziennik spoin',
    titleEn: 'Weld journal',
    subtitlePl: 'Weld map BPE, numeracja, śledzenie',
    subtitleEn: 'BPE weld map, numbering, traceability',
    icon: Icons.article_outlined,
    color: const Color(0xFF2ECC71),
    builder: (_) => const WeldJournalScreen(),
    keywordsPl: const [
      'dziennik',
      'spoina',
      'spoiny',
      'weld map',
      'numeracja',
      'rejestr',
      'stempel'
    ],
    keywordsEn: const [
      'journal',
      'weld',
      'log',
      'weld map',
      'traceability',
      'stamp'
    ],
  ),
  // Uprawnienia SPAWACZA (EN ISO 9606-1 / ASME WPQ) — nie „WPQR", który jest
  // kwalifikacją procedury i należy do WPS (następny wpis).
  ToolSpec(
    id: 'welder_certificates',
    group: ToolGroup.inspection,
    titlePl: 'Uprawnienia spawacza',
    titleEn: 'Welder qualifications',
    subtitlePl: 'ISO 9606-1 / WPQ: ważność, potwierdzenia co 6 mies.',
    subtitleEn: 'ISO 9606-1 / WPQ: validity, 6-month confirmations',
    icon: Icons.workspace_premium_outlined,
    color: const Color(0xFFFFB300),
    builder: (_) => const CertificateRegisterPage(),
    keywordsPl: const [
      'uprawnienia',
      'certyfikat',
      'kwalifikacja',
      'egzamin',
      'waznosc',
      'przedluzenie',
      '9606'
    ],
    keywordsEn: const [
      'qualification',
      'certificate',
      'wpq',
      'welder cert',
      'continuity',
      'expiry'
    ],
  ),
  ToolSpec(
    id: 'wps_library',
    group: ToolGroup.inspection,
    titlePl: 'Biblioteka WPS',
    titleEn: 'WPS library',
    subtitlePl: 'Instrukcje spawania, zakresy, WPQR/PQR, eksport JSON',
    subtitleEn: 'Welding procedures, ranges, WPQR/PQR, JSON export',
    icon: Icons.menu_book_outlined,
    color: const Color(0xFF26A69A),
    builder: (_) => const WpsLibraryPage(),
    keywordsPl: const [
      'wps',
      'instrukcja',
      'technologia',
      'wpqr',
      'procedura',
      'zakres'
    ],
    keywordsEn: const [
      'wps',
      'procedure',
      'pqr',
      'wpqr',
      'range'
    ],
  ),
  ToolSpec(
    id: 'work_progress',
    group: ToolGroup.inspection,
    titlePl: 'Postęp robót',
    titleEn: 'Work progress',
    subtitlePl: 'Ile zrobione dziś, DI, spawacze, naprawy, kiedy koniec pakietu',
    subtitleEn: 'Done today, dia-inches, welders, repairs, package finish date',
    icon: Icons.insights_outlined,
    color: const Color(0xFF4A9EFF),
    builder: (_) => const ProgressPage(),
    keywordsPl: const [
      'postep',
      'postep robot',
      'wydajnosc',
      'tempo',
      'ile zrobione',
      'cal srednica',
      'di',
      'prognoza',
      'termin',
      'pakiet',
      'brygada',
      'brygadzista',
      'naprawy',
      'odsetek napraw',
      'raport dzienny',
      'raport tygodniowy'
    ],
    keywordsEn: const [
      'progress',
      'work progress',
      'productivity',
      'output',
      'dia-inch',
      'di',
      'forecast',
      'deadline',
      'test package',
      'crew',
      'foreman',
      'repair rate',
      'daily report',
      'weekly report'
    ],
  ),
  ToolSpec(
    id: 'weld_symbols',
    group: ToolGroup.inspection,
    titlePl: 'Symbole spawalnicze',
    titleEn: 'Welding symbols',
    subtitlePl: 'Czytnik rysunku: strona, rowek, a/z, n × l (e)',
    subtitleEn: 'Drawing reader: side, groove, a/z, n × l (e)',
    icon: Icons.architecture,
    color: const Color(0xFF26C6DA),
    builder: (_) => const WeldSymbolsPage(),
    keywordsPl: const [
      'symbol',
      'symbole',
      'oznaczenie spoin',
      'rysunek',
      'iso 2553',
      'pachwina',
      'strona strzalki',
      'linia przerywana',
      'grubosc obliczeniowa',
      'przerywana',
      'montazowa',
      'dookola'
    ],
    keywordsEn: const [
      'weld symbol',
      'welding symbols',
      'drawing',
      'iso 2553',
      'aws a2.4',
      'arrow side',
      'other side',
      'fillet',
      'throat',
      'leg',
      'intermittent',
      'field weld',
      'all around'
    ],
  ),
  ToolSpec(
    id: 'iso5817',
    group: ToolGroup.inspection,
    titlePl: 'Odbiór spoin ISO 5817',
    titleEn: 'Weld acceptance ISO 5817',
    subtitlePl: 'Limity B / C / D niezgodności VT, ocena pomiaru',
    subtitleEn: 'B / C / D limits for VT imperfections, measurement check',
    icon: Icons.fact_check_outlined,
    color: const Color(0xFF29B6F6),
    builder: (_) => const Iso5817Page(),
    keywordsPl: const [
      '5817',
      'iso 5817',
      'odbior',
      'vt',
      'kontrola wizualna',
      'poziom jakosci',
      'podtopienie',
      'nadlew',
      'wklesniecie grani',
      'przesuniecie krawedzi',
      'niezgodnosci',
      'wady spoin'
    ],
    keywordsEn: const [
      '5817',
      'iso 5817',
      'visual inspection',
      'vt',
      'quality level',
      'acceptance',
      'undercut',
      'excess weld metal',
      'root concavity',
      'misalignment',
      'imperfections'
    ],
  ),
  ToolSpec(
    id: 'instruments',
    group: ToolGroup.inspection,
    titlePl: 'Przyrządy i kalibracja',
    titleEn: 'Instruments and calibration',
    subtitlePl: 'Spawarki, manometry, termometry — terminy, przypomnienia',
    subtitleEn: 'Welders, gauges, thermometers — due dates, reminders',
    icon: Icons.speed_outlined,
    color: const Color(0xFF9CCC65),
    builder: (_) => const InstrumentRegisterPage(),
    keywordsPl: const [
      'kalibracja',
      'wzorcowanie',
      'walidacja',
      'przyrzad',
      'przyrzady',
      'manometr',
      'termometr',
      'pirometr',
      'miernik',
      'swiadectwo',
      'klucz dynamometryczny',
      '3834',
      '60974-14'
    ],
    keywordsEn: const [
      'calibration',
      'validation',
      'instrument',
      'gauge',
      'thermometer',
      'meter',
      'certificate',
      'torque wrench',
      '3834'
    ],
  ),
  ToolSpec(
    id: 'coupon_log',
    group: ToolGroup.inspection,
    titlePl: 'Log kuponów',
    titleEn: 'Coupon log',
    subtitlePl: 'Próbki spawów dnia',
    subtitleEn: 'Daily test coupons',
    icon: Icons.science_outlined,
    color: const Color(0xFF66BB6A),
    builder: (_) => const CouponLogScreen(),
    keywordsPl: const ['kupon', 'kupony', 'probka', 'probki', 'test'],
    keywordsEn: const ['coupon', 'sample', 'test'],
  ),
  ToolSpec(
    id: 'hydrotest',
    group: ToolGroup.inspection,
    titlePl: 'Próba ciśnieniowa',
    titleEn: 'Pressure test',
    subtitlePl: 'Ciśnienie próby, objętość, czas',
    subtitleEn: 'Test pressure, volume, time',
    icon: Icons.water_outlined,
    color: const Color(0xFF1976D2),
    builder: (_) => const HydrotestScreen(),
    keywordsPl: const [
      'proba',
      'cisnienie',
      'cisnieniowa',
      'hydro',
      'szczelnosc',
      'protokol'
    ],
    keywordsEn: const [
      'pressure test',
      'hydrotest',
      'hydrostatic',
      'leak test'
    ],
  ),

  // ── Spawacz · Wykończenie nierdzewki ─────────────────────────────────────
  ToolSpec(
    id: 'heat_tint',
    group: ToolGroup.stainlessFinish,
    titlePl: 'Przebarwienia',
    titleEn: 'Heat tint',
    subtitlePl: 'Karta kolorów spoiny, akceptacja',
    subtitleEn: 'Weld colour chart, acceptance',
    icon: Icons.palette_outlined,
    color: const Color(0xFFAB47BC),
    builder: (_) => const HeatTintScreen(),
    keywordsPl: const [
      'przebarwienia',
      'kolor',
      'kolory',
      'nalot',
      'utlenienie',
      'nierdzewka'
    ],
    keywordsEn: const [
      'heat tint',
      'colour',
      'color',
      'oxidation',
      'stainless'
    ],
  ),
  ToolSpec(
    id: 'passivation',
    group: ToolGroup.stainlessFinish,
    titlePl: 'Trawienie i pasywacja',
    titleEn: 'Pickling and passivation',
    subtitlePl: 'Obróbka powierzchni po spawaniu',
    subtitleEn: 'Post-weld surface treatment',
    icon: Icons.cleaning_services_outlined,
    color: const Color(0xFFEC407A),
    builder: (_) => const PassivationScreen(),
    keywordsPl: const ['trawienie', 'pasywacja', 'pasta', 'kwas', 'nierdzewka'],
    keywordsEn: const ['pickling', 'passivation', 'paste', 'acid', 'stainless'],
  ),

  // ── Spawacz · Wyceny i koszty ────────────────────────────────────────────
  ToolSpec(
    id: 'weld_quotes',
    group: ToolGroup.costing,
    titlePl: 'Wyceny spawalnicze',
    titleEn: 'Welding quotes',
    subtitlePl: 'Koszt roboty: godziny, spoiwo, gaz, NDT → oferta PDF',
    subtitleEn: 'Job cost: hours, filler, gas, NDT → PDF quote',
    icon: Icons.request_quote_outlined,
    color: const Color(0xFF35C88B),
    builder: (_) => const QuoteListPage(),
    keywordsPl: const [
      'wycena',
      'wyceny',
      'oferta',
      'kosztorys',
      'koszt',
      'cena',
      'stawka',
      'roboczogodziny',
      'zuzycie spoiwa',
      'ile kosztuje',
      'cal srednica',
      'di',
      'faktura',
      'vat'
    ],
    keywordsEn: const [
      'quote',
      'quotation',
      'estimate',
      'cost',
      'price',
      'rate',
      'man-hours',
      'filler consumption',
      'dia-inch',
      'di',
      'offer'
    ],
  ),
  ToolSpec(
    id: 'hourly_rate',
    group: ToolGroup.costing,
    titlePl: 'Ile brać za godzinę',
    titleEn: 'What to charge per hour',
    subtitlePl: 'Minimalna stawka z kosztów firmy, podatku i godzin',
    subtitleEn: 'Minimum rate from business costs, tax and hours',
    icon: Icons.price_check_outlined,
    color: const Color(0xFFE8C14B),
    builder: (_) => const HourlyRatePage(),
    keywordsPl: const [
      'stawka',
      'godzinowa',
      'ile brac',
      'za godzine',
      'dniowka',
      'zus',
      'podatek',
      'ryczalt',
      'dzialalnosc',
      'b2b',
      'zarobek',
      'na reke'
    ],
    keywordsEn: const [
      'hourly rate',
      'rate',
      'day rate',
      'charge',
      'tax',
      'self-employed',
      'contractor',
      'income'
    ],
  ),
];

final Map<String, ToolSpec> _byId = {
  for (final t in kToolRegistry) t.id: t,
};

/// Dostępny wpis o danym identyfikatorze albo null (nieznany / ukryty flagą).
ToolSpec? toolById(String id) {
  final t = _byId[id];
  return (t != null && t.available) ? t : null;
}

List<ToolSpec> get availableTools =>
    kToolRegistry.where((t) => t.available).toList(growable: false);

List<ToolSpec> toolsInGroup(ToolGroup group) =>
    kToolRegistry.where((t) => t.available && t.group == group).toList(
          growable: false,
        );

/// Grupy sekcji, które mają co najmniej jedno dostępne narzędzie.
List<ToolGroup> groupsOf(ToolSection section) => ToolGroup.values
    .where((g) => g.section == section && toolsInGroup(g).isNotEmpty)
    .toList(growable: false);

/// Rozwiązuje zapisane identyfikatory na dostępne narzędzia, po cichu
/// pomijając nieznane i ukryte.
List<ToolSpec> resolveTools(Iterable<String> ids, {int? limit}) {
  final out = <ToolSpec>[];
  for (final id in ids) {
    final t = toolById(id);
    if (t == null) continue;
    out.add(t);
    if (limit != null && out.length >= limit) break;
  }
  return out;
}

// ─── Otwieranie ─────────────────────────────────────────────────────────────

/// Otwiera narzędzie: zapisuje je w „ostatnio używanych", a jeśli narzędzie
/// wysyła dane na serwer — najpierw przepuszcza przez bramkę imienia i zasad.
Future<void> openTool(BuildContext context, ToolSpec tool) async {
  if (tool.needsAccount) {
    final ok = await ensureCommunityAccess(context);
    if (!ok || !context.mounted) return;
  }
  // Nie czekamy na zapis — ekran ma się otworzyć od razu.
  unawaited(ToolUsageStore.instance.recordOpen(tool.id));
  await Navigator.of(context).push(MaterialPageRoute(builder: tool.builder));
}

// ─── Wyszukiwarka ───────────────────────────────────────────────────────────

class ToolSearchHit {
  final ToolSpec tool;
  final int score;
  const ToolSearchHit(this.tool, this.score);
}

/// Warianty rdzenia dla odmiany polskiej: „kolano" → „kolan" łapie „kolana",
/// „kolanka"; „spadku" → „spad" łapie „spadek". Nigdy krótsze niż 4 znaki.
List<String> _stems(String term) => [
      term,
      if (term.length >= 5) term.substring(0, term.length - 1),
      if (term.length >= 6) term.substring(0, term.length - 2),
    ];

/// Szuka narzędzi po tytule, słowach kluczowych i podtytule — w obu językach
/// naraz, bo monter w polskiej wersji też wpisuje „takeout" czy „rolling".
/// Wielkość liter i polskie znaki nie mają znaczenia. Każde wpisane słowo musi
/// gdzieś pasować. Pusty wynik dla pustego zapytania.
List<ToolSearchHit> searchTools(String rawQuery, AppLanguage lang) {
  final query = normalizeForSearch(rawQuery);
  if (query.isEmpty) return const [];
  final terms = query.split(' ').where((t) => t.isNotEmpty).toList();
  if (terms.isEmpty) return const [];

  final hits = <ToolSearchHit>[];
  for (final tool in availableTools) {
    final score = _score(
      query: query,
      terms: terms,
      titleMain: lang == AppLanguage.en ? tool.titleEn : tool.titlePl,
      titleOther: lang == AppLanguage.en ? tool.titlePl : tool.titleEn,
      keywords: [...tool.keywordsPl, ...tool.keywordsEn],
      subtitles: '${tool.subtitlePl} ${tool.subtitleEn}',
    );
    if (score != null) hits.add(ToolSearchHit(tool, score));
  }
  hits.sort((a, b) {
    final byScore = b.score.compareTo(a.score);
    if (byScore != 0) return byScore;
    // Remis: kolejność z rejestru (kolejność menu).
    return kToolRegistry
        .indexOf(a.tool)
        .compareTo(kToolRegistry.indexOf(b.tool));
  });
  return hits;
}

/// Wynik dopasowania jednego wpisu (narzędzia albo ekranu) do zapytania, albo
/// `null`, gdy któreś słowo zapytania nigdzie nie pasuje.
int? _score({
  required String query,
  required List<String> terms,
  required String titleMain,
  required String titleOther,
  required List<String> keywords,
  required String subtitles,
}) {
  final main = normalizeForSearch(titleMain);
  final other = normalizeForSearch(titleOther);
  final keys = keywords.map(normalizeForSearch).toList();
  final subs = normalizeForSearch(subtitles);
  final titleWords = main.split(' ');

  var score = 0;
  for (final term in terms) {
    var best = 0;
    for (final (i, stem) in _stems(term).indexed) {
      // Dokładne słowo wygrywa z rdzeniem.
      final penalty = i * 2;
      if (titleWords.any((w) => w.startsWith(stem))) {
        best = _max(best, 12 - penalty);
      } else if (main.contains(stem)) {
        best = _max(best, 9 - penalty);
      }
      if (keys.any((k) => k == stem)) {
        best = _max(best, 10 - penalty);
      } else if (keys.any((k) => k.startsWith(stem))) {
        best = _max(best, 8 - penalty);
      } else if (stem.length >= 3 && keys.any((k) => k.contains(stem))) {
        best = _max(best, 5 - penalty);
      }
      if (other.contains(stem)) best = _max(best, 6 - penalty);
      if (stem.length >= 3 && subs.contains(stem)) {
        best = _max(best, 3 - penalty);
      }
    }
    if (best <= 0) return null;
    score += best;
  }
  // Całe zapytanie w tytule — najmocniejszy sygnał.
  if (main.contains(query)) score += 10;
  return score;
}

int _max(int a, int b) => a > b ? a : b;

// ─── Wpisy nawigacyjne (konto, zasady, pomoc) ───────────────────────────────
//
// Ekrany, które nie są narzędziami (nie mają grupy w menu montera ani
// spawacza), ale monter ich szuka: „czat", „profil", „usuń dane", „zasady".
// Wcześniej wyszukiwarka odpowiadała na nie „Brak narzędzia". Osobny typ, bo
// nie trafiają do menu, „ostatnio używanych" ani przypiętych.

class NavEntry {
  /// Trwały identyfikator (klucz w UI: `nav-<id>`). Nie może kolidować z
  /// identyfikatorami narzędzi.
  final String id;
  final String titlePl;
  final String titleEn;
  final String subtitlePl;
  final String subtitleEn;
  final IconData icon;
  final Color color;
  final List<String> keywordsPl;
  final List<String> keywordsEn;
  final bool available;

  /// Otwiera ekran (z bramką, jeśli ekran jej wymaga).
  final Future<void> Function(BuildContext context) open;

  const NavEntry({
    required this.id,
    required this.titlePl,
    required this.titleEn,
    required this.subtitlePl,
    required this.subtitleEn,
    required this.icon,
    required this.color,
    required this.open,
    this.keywordsPl = const [],
    this.keywordsEn = const [],
    this.available = true,
  });

  String title(BuildContext context) => context.tr(pl: titlePl, en: titleEn);
  String subtitle(BuildContext context) =>
      context.tr(pl: subtitlePl, en: subtitleEn);
}

Future<void> _pushScreen(BuildContext context, Widget screen) =>
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));

final List<NavEntry> kNavEntries = [
  NavEntry(
    id: 'chat',
    titlePl: 'Czat',
    titleEn: 'Chat',
    subtitlePl: 'Rozmowy z fachowcami — pokoje branżowe',
    subtitleEn: 'Talk to pros — trade rooms',
    icon: Icons.forum_outlined,
    color: const Color(0xFFCE93D8),
    available: kCommunityEnabled,
    keywordsPl: const [
      'czat',
      'rozmowa',
      'rozmowy',
      'pokoj',
      'wiadomosc',
      'forum',
      'spolecznosc',
      'brygada',
      'praca',
      'zglos',
      'zablokuj',
    ],
    keywordsEn: const [
      'chat',
      'messages',
      'room',
      'forum',
      'community',
      'report',
      'block',
    ],
    // Czat wysyła dane pod nazwiskiem — ta sama bramka co kafel CZAT.
    open: (context) async {
      if (!await ensureCommunityAccess(context)) return;
      if (!context.mounted) return;
      await _pushScreen(context, const ChatScreen());
    },
  ),
  NavEntry(
    id: 'profile',
    titlePl: 'Twój profil',
    titleEn: 'Your profile',
    subtitlePl: 'Imię, zablokowani, kopia zapasowa, zgody',
    subtitleEn: 'Name, blocked people, backup, consents',
    icon: Icons.person_outline,
    color: const Color(0xFF9BA3C7),
    keywordsPl: const [
      'profil',
      'konto',
      'imie',
      'nazwisko',
      'podpis',
      'zablokowani',
      'odblokuj',
      'kopia',
      'backup',
      'przywroc',
      'zgoda',
      'zgody',
      'kontakt',
    ],
    keywordsEn: const [
      'profile',
      'account',
      'name',
      'blocked',
      'unblock',
      'backup',
      'restore',
      'consent',
      'contact',
    ],
    open: (context) => _pushScreen(context, const ProfileScreen()),
  ),
  NavEntry(
    id: 'delete_data',
    titlePl: 'Usuń moje dane',
    titleEn: 'Delete my data',
    subtitlePl: 'Z serwera i z telefonu (RODO)',
    subtitleEn: 'From the server and the phone (GDPR)',
    icon: Icons.delete_outline,
    color: const Color(0xFFF0655A),
    keywordsPl: const [
      'usun',
      'usuniecie',
      'dane',
      'rodo',
      'prywatnosc',
      'wymaz',
      'skasuj',
    ],
    keywordsEn: const ['delete', 'erase', 'data', 'gdpr', 'remove'],
    // Otwiera profil od razu z oknem potwierdzenia — nic nie znika bez „Usuń".
    open: (context) =>
        _pushScreen(context, const ProfileScreen(openDeleteOnStart: true)),
  ),
  NavEntry(
    id: 'terms',
    titlePl: 'Regulamin',
    titleEn: 'Terms of Use',
    subtitlePl: 'Zasady czatu, skanera i asystenta',
    subtitleEn: 'Rules for chat, scanner and assistant',
    icon: Icons.description_outlined,
    color: const Color(0xFF9BA3C7),
    keywordsPl: const ['zasady', 'regulamin', 'warunki', 'moderacja'],
    keywordsEn: const ['rules', 'terms', 'conditions', 'moderation'],
    open: (context) => Navigator.of(context).push(LegalScreen.route(termsOfUse)),
  ),
  NavEntry(
    id: 'privacy',
    titlePl: 'Polityka prywatności',
    titleEn: 'Privacy Policy',
    subtitlePl: 'Co wysyłamy, dokąd i jak to usunąć',
    subtitleEn: 'What we send, where, and how to delete it',
    icon: Icons.privacy_tip_outlined,
    color: const Color(0xFF9BA3C7),
    keywordsPl: const ['zasady', 'prywatnosc', 'polityka', 'rodo', 'dane'],
    keywordsEn: const ['privacy', 'policy', 'gdpr', 'data', 'rules'],
    open: (context) =>
        Navigator.of(context).push(LegalScreen.route(privacyPolicy)),
  ),
  NavEntry(
    id: 'help',
    titlePl: 'Pomoc',
    titleEn: 'Help',
    subtitlePl: 'Baza wiedzy: TIG, materiały, NDT, aplikacja',
    subtitleEn: 'Knowledge base: TIG, materials, NDT, the app',
    icon: Icons.help_outline_rounded,
    color: const Color(0xFF2ECC71),
    keywordsPl: const ['pomoc', 'baza wiedzy', 'faq', 'jak', 'instrukcja'],
    keywordsEn: const ['help', 'knowledge base', 'faq', 'how to', 'guide'],
    open: (context) => _pushScreen(context, const HelpScreen()),
  ),
  NavEntry(
    id: 'welder_identity',
    titlePl: 'Tożsamość spawacza',
    titleEn: 'Welder identity',
    subtitlePl: 'Stempel i dane do dziennika spoin',
    subtitleEn: 'Stamp and details for the weld journal',
    icon: Icons.badge_outlined,
    color: const Color(0xFF4A9EFF),
    keywordsPl: const ['stempel', 'tozsamosc', 'spawacz', 'podpis spoiny'],
    keywordsEn: const ['stamp', 'identity', 'welder id'],
    open: (context) => _pushScreen(context, const WelderIdentitySetupScreen()),
  ),
];

class NavSearchHit {
  final NavEntry entry;
  final int score;
  const NavSearchHit(this.entry, this.score);
}

/// Wpisy nawigacyjne pasujące do zapytania — te same zasady co
/// [searchTools] (oba języki, bez polskich znaków, odmiana).
List<NavEntry> searchNavEntries(String rawQuery, AppLanguage lang) {
  final query = normalizeForSearch(rawQuery);
  if (query.isEmpty) return const [];
  final terms = query.split(' ').where((t) => t.isNotEmpty).toList();
  if (terms.isEmpty) return const [];
  final hits = <NavSearchHit>[];
  for (final entry in kNavEntries) {
    if (!entry.available) continue;
    final score = _score(
      query: query,
      terms: terms,
      titleMain: lang == AppLanguage.en ? entry.titleEn : entry.titlePl,
      titleOther: lang == AppLanguage.en ? entry.titlePl : entry.titleEn,
      keywords: [...entry.keywordsPl, ...entry.keywordsEn],
      subtitles: '${entry.subtitlePl} ${entry.subtitleEn}',
    );
    if (score != null) hits.add(NavSearchHit(entry, score));
  }
  hits.sort((a, b) {
    final byScore = b.score.compareTo(a.score);
    if (byScore != 0) return byScore;
    return kNavEntries.indexOf(a.entry).compareTo(kNavEntries.indexOf(b.entry));
  });
  return [for (final h in hits) h.entry];
}
