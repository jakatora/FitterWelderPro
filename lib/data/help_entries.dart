// ignore_for_file: prefer_const_constructors

import 'package:flutter/material.dart';

import '../i18n/app_language.dart';

// Help v2 — searchable knowledge base for fitters and welders.
// Each entry has bilingual (PL/EN) question + answer + tags for fuzzy matching.
// Categories are sorted by relevance to daily fitter/welder work.
//
// Sourced from:
//   - Original 21 entries from the legacy help_screen.dart
//   - 100-iteration piping_knowledge.md research base
//   - ASME B31.3 / API 1104 / NACE MR0175 / AWS D1.1 hands-on practice
//
// Add new entries by appending to the relevant category list — search index
// rebuilds itself on each query.

class HelpCategory {
  /// Internal id (kebab case). Used for filter chip routing.
  final String id;

  /// Display title (PL / EN).
  final String Function(AppLanguage) title;

  /// Short subtitle / hint shown under the title.
  final String Function(AppLanguage) subtitle;

  /// Material icon. Constant `IconData` from `Icons.X` so Flutter's icon
  /// tree-shaker can drop unused glyphs.
  final IconData icon;

  /// Accent colour as ARGB hex.
  final int accentArgb;

  final List<HelpEntry> entries;

  const HelpCategory({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.accentArgb,
    required this.entries,
  });
}

class HelpEntry {
  final String id;
  final String Function(AppLanguage) question;
  final String Function(AppLanguage) answer;

  /// Lowercase tags, language-agnostic where possible (`tig`, `purge`, `nace`).
  /// Used as the primary fuzzy-match field — be generous.
  final List<String> tags;

  const HelpEntry({
    required this.id,
    required this.question,
    required this.answer,
    this.tags = const [],
  });
}

// ─── Helpers ──────────────────────────────────────────────────────────────────

String Function(AppLanguage) _bi(String pl, String en) =>
    (lang) => lang == AppLanguage.pl ? pl : en;

// Icons used as constant `Icons.X` references below so Flutter's
// font tree-shaker keeps only the glyphs we actually reference.

// ─── Knowledge base ───────────────────────────────────────────────────────────

List<HelpCategory> kHelpCategories = [
  // ════════════════════════════════════════════════════════════════════════
  // 1. SPOINY TIG — original content + practical additions
  // ════════════════════════════════════════════════════════════════════════
  HelpCategory(
    id: 'tig-welds',
    title: _bi('Spoiny TIG', 'TIG welds'),
    subtitle: _bi('Kolor, kształt, defekty', 'Color, shape, defects'),
    icon: Icons.local_fire_department,
    accentArgb: 0xFFFFA726,
    entries: [
      HelpEntry(
        id: 'tig-color-change',
        question: _bi(
          'Dlaczego spoina TIG zmienia kolor?',
          'Why does a TIG weld change color?',
        ),
        answer: _bi(
          'Przebarwienie wskazuje zbyt wysoką temperaturę, niewystarczającą osłonę gazową, za krótki post-flow lub zbyt wolne prowadzenie palnika. '
          'Kolor "soomówka" (srebrny/lekko słomkowy) jest OK, ciemny niebieski/fioletowy = lekkie utlenienie, szary matowy = silne utlenienie, biały/żółty łuszczący = katastrofalne zanieczyszczenie — odrzucić.',
          'Discoloration means too much heat, insufficient gas shielding, too short post-flow, or moving the torch too slowly. '
          'Silver/straw is fine, dark blue/purple = light oxidation, dull gray = heavy, white/yellow flaking = catastrophic — reject.',
        ),
        tags: ['tig', 'kolor', 'color', 'oxidation', 'utlenienie', 'post-flow', 'shielding'],
      ),
      HelpEntry(
        id: 'tig-black-weld',
        question: _bi(
          'Dlaczego spoina jest matowa lub czarna (sugar)?',
          'Why is the weld dull or black (sugar)?',
        ),
        answer: _bi(
          'Najczęstsza przyczyna to brak back purge przy spawaniu rurociągów stalowych nierdzewnych — tlen od strony root utlenia spoinę. '
          'Sprawdź: szczelność tam purge (dam bladders / paper), ciągłość argonu, czy osiągnięto <0.1% O₂ przed pierwszym pass. Dla titanium i super duplex limit: <50 ppm i <20 ppm O₂.',
          'Most common cause is no back purge on stainless pipe — oxygen on the root side oxidizes the weld. '
          'Check: purge dam tightness, argon flow continuity, O₂ <0.1% before first pass. For Ti and super duplex: <50 ppm and <20 ppm O₂.',
        ),
        tags: ['tig', 'sugar', 'cukier', 'back-purge', 'ss', 'stainless', 'oxidation'],
      ),
      HelpEntry(
        id: 'tig-cracks-cool',
        question: _bi(
          'Dlaczego spoina pęka po ostygnięciu?',
          'Why does the weld crack after cooling?',
        ),
        answer: _bi(
          'Cold cracking po ostygnięciu wskazuje na hydrogen embrittlement w HAZ — typowe dla wysokowytrzymałych stali (P91, X65+). '
          'Przyczyny: wilgoć w elektrodzie/druciku, brak preheat, za szybkie chłodzenie. '
          'Rozwiązanie: low-H electrody (E7018-H4) suszone w 230°C 2 h, preheat 150-300°C, slower cool z dehydrogenation hold 200°C × 2-4 h.',
          'Cold cracking after cooling = hydrogen embrittlement in HAZ — typical for high-strength steels (P91, X65+). '
          'Causes: moist electrode/wire, no preheat, fast cooling. '
          'Fix: low-H electrodes (E7018-H4) baked at 230°C × 2 h, preheat 150-300°C, slow cool with dehydrogenation hold 200°C × 2-4 h.',
        ),
        tags: ['cracks', 'pekanie', 'cold-cracking', 'hydrogen', 'preheat', 'p91', 'haz'],
      ),
      HelpEntry(
        id: 'tig-porosity',
        question: _bi(
          'Dlaczego pojawia się porowatość?',
          'Why does porosity appear?',
        ),
        answer: _bi(
          'Porowatość wynika z gazu uwięzionego w spoinie. Źródła: brud/tłuszcz/wilgoć na materiale, za duży lub za mały przepływ gazu (turbulencja albo brak osłony), zła czystość argonu, wilgotne elektrody. '
          'Test: argon ≥99.995% (welding grade), surface clean acetone+IPA wipe, flow 8-12 L/min dla 1.6 mm, 10-15 L/min dla 2.4 mm. Pre-purge ≥10 sec.',
          'Porosity = gas trapped in the weld. Sources: dirt/grease/moisture, gas flow too high (turbulence) or too low (no shield), poor argon purity, damp electrodes. '
          'Test: argon ≥99.995% welding grade, acetone+IPA wipe, 8-12 L/min for 1.6 mm tungsten, 10-15 L/min for 2.4 mm. Pre-purge ≥10 sec.',
        ),
        tags: ['porosity', 'porowatosc', 'gas', 'argon', 'tig', 'shielding'],
      ),
      HelpEntry(
        id: 'tig-undercut',
        question: _bi(
          'Skąd się bierze undercut (podtopienie) i jak go uniknąć?',
          'What causes undercut and how to avoid it?',
        ),
        answer: _bi(
          'Undercut to rowek wzdłuż brzegu spoiny, w którym brakuje materiału — wynik za dużego prądu, zbyt krótkiego łuku przy źle dobranym kącie palnika, lub za szybkiego prowadzenia. '
          'Krytyczny w wibrującym lub cyklicznym ciśnieniu — staje się fatigue crack initiator. '
          'Code limit (ASME B31.3 §344.6): max 0.8 mm głębokości lub 1/32 t.',
          'Undercut is a groove along the weld toe with missing material — caused by too much current, too short an arc with bad torch angle, or too fast travel. '
          'Critical in vibrating/cyclic service — becomes a fatigue crack initiator. '
          'Code limit (ASME B31.3 §344.6): max 0.8 mm depth or 1/32 t.',
        ),
        tags: ['undercut', 'podtopienie', 'defekt', 'fatigue', 'asme-b31'],
      ),
    ],
  ),

  // ════════════════════════════════════════════════════════════════════════
  // 2. ŁUK + TUNGSTEN + GAZ
  // ════════════════════════════════════════════════════════════════════════
  HelpCategory(
    id: 'arc-tungsten-gas',
    title: _bi('Łuk · Tungsten · Gaz', 'Arc · Tungsten · Gas'),
    subtitle: _bi('Stabilność, ostrzenie, przepływy', 'Stability, sharpening, flows'),
    icon: Icons.bolt,
    accentArgb: 0xFF42A5F5,
    entries: [
      HelpEntry(
        id: 'arc-unstable',
        question: _bi(
          'Dlaczego łuk jest niestabilny lub gaśnie?',
          'Why is the arc unstable or going out?',
        ),
        answer: _bi(
          'Najczęściej: zanieczyszczona elektroda (dotknięcie jeziorka), słaba masa (rdza/farba pod zaciskiem), zbyt długi łuk, HF arc start issue. '
          'Test: zacisk masy bezpośrednio do czystej stali, długość łuku ~1×D elektrody, naostrz tungsten wzdłuż osi. '
          'Dla AC (Al): balance 65-80% EN.',
          'Most often: contaminated electrode (dipped pool), poor ground (rust/paint under clamp), arc too long, HF start fault. '
          'Test: clamp directly to clean steel, arc length ≈1× electrode dia, sharpen tungsten along axis. '
          'For AC (Al): balance 65-80% EN.',
        ),
        tags: ['arc', 'luk', 'tungsten', 'ground', 'masa', 'hf-start'],
      ),
      HelpEntry(
        id: 'tungsten-balling',
        question: _bi(
          'Dlaczego tungsten robi się kulisty (balling)?',
          'Why is the tungsten balling up?',
        ),
        answer: _bi(
          'Kula na końcu = praca przy AC lub za wysoki prąd dla średnicy elektrody (przekroczony rating). '
          'Tabela max prądu DCEN: WT-20 (czerwony, thoriated) — 1.6 mm: 150 A, 2.4 mm: 250 A, 3.2 mm: 400 A. '
          'WL-20 (lanthanated, niebieski) podobne. Dla AC kula jest normalna — wybierz ceriated/lanthanated, NIE thoriated (radio-aktywny pył).',
          'Balling = AC operation or current exceeded electrode rating. '
          'Max DCEN: WT-20 (red, thoriated) — 1.6 mm: 150 A, 2.4 mm: 250 A, 3.2 mm: 400 A. '
          'WL-20 (lanthanated, blue) similar. For AC balling is normal — use ceriated/lanthanated, NOT thoriated (radioactive dust).',
        ),
        tags: ['tungsten', 'balling', 'kulisty', 'electrode', 'thoriated', 'lanthanated'],
      ),
      HelpEntry(
        id: 'tungsten-sharpening',
        question: _bi(
          'Jak ostrzyć tungsten dokładnie?',
          'How should tungsten be sharpened?',
        ),
        answer: _bi(
          'Szlifuj WZDŁUŻ osi elektrody (nie poprzecznie!) na dedykowanej tarczy diamentowej — rysy poprzeczne powodują arc wandering. '
          'Kąt 20-30° (ostrzejszy = mniej spread łuku, dla cienkich blach), 60-90° (bardziej tępy = większy spread, dla grubszych). '
          'Stumpkowanie końcówki na ~0.5× średnicy chroni przed pęknięciem.',
          'Grind ALONG the electrode axis (not across!) on a diamond wheel — transverse scratches cause arc wandering. '
          'Angle 20-30° (sharper = narrower arc, for thin metal), 60-90° (blunt = wider, for thicker). '
          'A small flat ~0.5× diameter at the tip prevents tip breakage.',
        ),
        tags: ['tungsten', 'ostrzenie', 'sharpening', 'grinding', 'angle'],
      ),
      HelpEntry(
        id: 'gas-flow',
        question: _bi(
          'Jaki przepływ gazu osłonowego ustawić?',
          'What shielding gas flow should be set?',
        ),
        answer: _bi(
          'Reguła: 0.85 × średnica dyszy w mm = L/min. Typowo: cup #6 (10 mm) → 8-10 L/min, cup #8 (13 mm) → 10-13 L/min. '
          'Za mało = wciąganie powietrza, porosity. Za dużo = turbulencja, też porosity. '
          'Gas lens (sintered diffuser) pozwala na laminar flow przy niższych przepływach i dłuższym tungsten stick-out (lepszy dostęp do narożników).',
          'Rule: 0.85 × cup ID in mm = L/min. Typical: cup #6 (10 mm) → 8-10 L/min, cup #8 (13 mm) → 10-13 L/min. '
          'Too low = air ingress, porosity. Too high = turbulence, also porosity. '
          'Gas lens (sintered diffuser) enables laminar flow at lower flow rates and longer stick-out (better corner access).',
        ),
        tags: ['gas', 'flow', 'argon', 'cup', 'gas-lens', 'przeplyw'],
      ),
      HelpEntry(
        id: 'back-purge-time',
        question: _bi(
          'Ile czasu powinien trwać back purge?',
          'How long should back purge last?',
        ),
        answer: _bi(
          'Reguła: 3-5 wymian objętości rury między dams. Volume = π·(D/2)²·L. '
          'Przykład: rura DN 100 (Ø 114 mm), zone 500 mm = 5.1 L → przy flow 15 L/min = 60 sec dla 3 wymiany. '
          'KONIECZNIE z analyzerem O₂ na wylocie — czas to tylko szacunek; właściwy moment startu spawania to <0.1% O₂ (zwykła stal), <50 ppm (Ti), <20 ppm (Zr).',
          'Rule: 3-5 volume changes between dams. Volume = π·(D/2)²·L. '
          'Example: DN 100 (Ø 114 mm), 500 mm zone = 5.1 L → at 15 L/min = 60 sec for 3 changes. '
          'ALWAYS use an O₂ analyzer at the outlet — time is just an estimate; weld start trigger is <0.1% O₂ (normal steel), <50 ppm (Ti), <20 ppm (Zr).',
        ),
        tags: ['purge', 'back-purge', 'argon', 'oxygen', 'tlen', 'analyzer'],
      ),
    ],
  ),

  // ════════════════════════════════════════════════════════════════════════
  // 3. CIĘCIE, FAZOWANIE, FIT-UP
  // ════════════════════════════════════════════════════════════════════════
  HelpCategory(
    id: 'cutting-bevel',
    title: _bi('Cięcie i fazowanie', 'Cutting & beveling'),
    subtitle: _bi('V/J/U groove, fit-up', 'V/J/U groove, fit-up'),
    icon: Icons.content_cut,
    accentArgb: 0xFF26A69A,
    entries: [
      HelpEntry(
        id: 'bevel-types',
        question: _bi(
          'Jaki bevel wybrać: V, J, czy U?',
          'Which bevel: V, J, or U?',
        ),
        answer: _bi(
          'V-groove (60-75° included, root face 1-3 mm, opening 2-4 mm) — standard dla ściany 6-25 mm, najprostszy. '
          'J-groove (curved root + 20-25° bevel) — dla orbital welding + grubych ścian, mniej filler metal o ~30%. '
          'U-groove (curved + 8-15° bevel) — bardzo grubo (>25-30 mm), oszczędza 50% filler vs V. '
          'Double-V (oba strony) — gdy dostęp od obu, oszczędza 40-50% filler na grubych blachach.',
          'V-groove (60-75° included, root face 1-3 mm, opening 2-4 mm) — standard for 6-25 mm wall, simplest. '
          'J-groove (curved root + 20-25° bevel) — for orbital welding + thick walls, ~30% less filler metal. '
          'U-groove (curved + 8-15° bevel) — very thick (>25-30 mm), saves 50% filler vs V. '
          'Double-V (both sides) — when both-side access, saves 40-50% on thick plate.',
        ),
        tags: ['bevel', 'groove', 'v-groove', 'j-groove', 'u-groove', 'fit-up'],
      ),
      HelpEntry(
        id: 'high-lo',
        question: _bi(
          'Jaki dopuszczalny high-lo (mismatch) przy fit-up?',
          'What high-lo (mismatch) is allowed at fit-up?',
        ),
        answer: _bi(
          'ASME B31.3 §328.4.3: mismatch alignment ≤1.5 mm dla ścianki <12.5 mm, ≤t/8 (max 3 mm) dla grubszych. '
          'API 1104 (pipeline): mismatch ≤1.6 mm. '
          'Dla critical service (sour, hydrogen, cryogenic) project spec może być stricter (np. ≤0.5 mm). '
          'Pomiar: high-lo gauge na każdej cwiartce obwodu, dokumentuj przed root pass.',
          'ASME B31.3 §328.4.3: alignment mismatch ≤1.5 mm for wall <12.5 mm, ≤t/8 (max 3 mm) for thicker. '
          'API 1104 (pipeline): mismatch ≤1.6 mm. '
          'For critical service (sour, hydrogen, cryogenic) project spec may be tighter (e.g. ≤0.5 mm). '
          'Measurement: high-lo gauge at each quadrant, document before root pass.',
        ),
        tags: ['high-lo', 'mismatch', 'fit-up', 'asme-b31', 'api-1104'],
      ),
      HelpEntry(
        id: 'cold-bending-radius',
        question: _bi(
          'Jaki minimalny promień przy cold bending rury?',
          'What minimum radius for cold pipe bending?',
        ),
        answer: _bi(
          'Standard CS schedule 40-80: R ≥ 30-40D (D = NPS). '
          'Wyższe gatunki (X65, X70): R ≥ 40-60D. '
          'Hot bending pozwala R = 0.7-1.5×D (dużo ciaśniej). '
          'Induction bending: R = 1.5×D nawet dla X80 + ścianka >25 mm. '
          'Limit ovality (B31.4): 5% max (D_max−D_min)/D_nom. Wall thinning przy extrados: 5-15% norm.',
          'Standard CS schedule 40-80: R ≥ 30-40D (D = NPS). '
          'Higher grades (X65, X70): R ≥ 40-60D. '
          'Hot bending allows R = 0.7-1.5×D (much tighter). '
          'Induction bending: R = 1.5×D even for X80 + wall >25 mm. '
          'Ovality limit (B31.4): 5% max (D_max−D_min)/D_nom. Wall thinning at extrados: 5-15% normal.',
        ),
        tags: ['bending', 'gniecie', 'cold-bend', 'hot-bend', 'induction', 'ovality'],
      ),
      HelpEntry(
        id: 'saddle-cut',
        question: _bi(
          'Jak przygotować saddle cut (fish-mouth) na trójniku?',
          'How to prepare a saddle cut (fish-mouth) for a tee?',
        ),
        answer: _bi(
          'Saddle = wycięcie w branch pipe pasujące do header pipe. Geometria: dla 90° header/branch tej samej średnicy = "fish mouth" symmetric o promieniu = header OD/2. '
          'Dla branch < header: szablon owinięty na branch. '
          'Apka generuje PDF szablon do druku 1:1 (w fazie Premium). '
          'Tolerancja gap: ≤3 mm przed weld, root opening 2-4 mm. Welder qualifies as 6G if positions overhead/horizontal.',
          'Saddle = cut in branch pipe matching header pipe. Geometry: 90° same-size header/branch = symmetric "fish mouth" with radius = header OD/2. '
          'Branch < header: wrap-around template. '
          'The app generates a printable 1:1 PDF template (Premium phase). '
          'Gap tolerance: ≤3 mm before weld, root opening 2-4 mm. 6G qualifies for overhead/horizontal.',
        ),
        tags: ['saddle', 'fish-mouth', 'branch', 'tee', 'template', 'coping'],
      ),
    ],
  ),

  // ════════════════════════════════════════════════════════════════════════
  // 4. MATERIAŁY, NACE, P-NUMBERS
  // ════════════════════════════════════════════════════════════════════════
  HelpCategory(
    id: 'materials',
    title: _bi('Materiały i kompatybilność', 'Materials & compatibility'),
    subtitle: _bi('P-numbers, NACE, alloy welding', 'P-numbers, NACE, alloy welding'),
    icon: Icons.science,
    accentArgb: 0xFF7E57C2,
    entries: [
      HelpEntry(
        id: 'p-numbers',
        question: _bi(
          'Czym są P-numbers wg ASME IX?',
          'What are P-numbers per ASME IX?',
        ),
        answer: _bi(
          'P-number grupuje materiały bazowe wg podobnej spawalności — zmiana grupy wymaga re-qualifikacji WPS. '
          'P1: carbon steel (A106 Gr B, A53, X42-X70). '
          'P3: Cr-Mo niskie (P11, P22). '
          'P4: wyższe Cr-Mo (P5, P9). '
          'P5A/B: P91 (V/Nb modified). '
          'P8: austenitic SS (304, 316, 321). '
          'P10H: duplex (2205, 2507). '
          'P34: nickel alloys. P41: aluminum. F-numbers grupują fillery równolegle.',
          'P-number groups base materials by similar weldability — group change requires WPS re-qualification. '
          'P1: carbon steel (A106 Gr B, A53, X42-X70). '
          'P3: low Cr-Mo (P11, P22). '
          'P4: higher Cr-Mo (P5, P9). '
          'P5A/B: P91 (V/Nb modified). '
          'P8: austenitic SS (304, 316, 321). '
          'P10H: duplex (2205, 2507). '
          'P34: nickel. P41: aluminum. F-numbers group fillers in parallel.',
        ),
        tags: ['p-number', 'asme-ix', 'wps', 'material', 'classification'],
      ),
      HelpEntry(
        id: 'nace-mr0175',
        question: _bi(
          'Co wymaga NACE MR0175 / ISO 15156 (sour service)?',
          'What does NACE MR0175 / ISO 15156 require (sour service)?',
        ),
        answer: _bi(
          'Threshold: H₂S partial pressure ≥0.05 psi (0.3 kPa) lub H₂S w wodzie ≥1.45 ppm → wymóg compliance. '
          'Hardness limit: ≤22 HRC (~250 HV10) dla CS + welds + HAZ. Ni content ≤1% w CS. '
          'PWHT wymagany dla wszystkich CS welds. '
          'Bolts: tylko B7M/L7M (lower hardness vs B7); B16 zabronione. NIGDY high-strength (>1240 MPa). '
          'HIC-tested plate per NACE TM0284 (CLR ≤15%, CTR ≤5%, CSR ≤2%).',
          'Threshold: H₂S partial pressure ≥0.05 psi (0.3 kPa) or H₂S in water ≥1.45 ppm → compliance required. '
          'Hardness limit: ≤22 HRC (~250 HV10) for CS + welds + HAZ. Ni content ≤1% in CS. '
          'PWHT required for all CS welds. '
          'Bolts: only B7M/L7M (lower hardness vs B7); B16 prohibited. NEVER high-strength (>1240 MPa). '
          'HIC-tested plate per NACE TM0284 (CLR ≤15%, CTR ≤5%, CSR ≤2%).',
        ),
        tags: ['nace', 'mr0175', 'sour-service', 'h2s', 'ssc', 'hic', 'hardness'],
      ),
      HelpEntry(
        id: 'pmi-xrf',
        question: _bi(
          'Jak wykonać PMI (Positive Material ID) w terenie?',
          'How to do PMI (Positive Material ID) in the field?',
        ),
        answer: _bi(
          '3 metody (API RP 578): handheld XRF (najczęściej, ale NIE wykrywa węgla → nie odróżni 304/304L), handheld OES (z carbon detection, mała iskra), LIBS (laser, no contact). '
          'Procedura: surface grind 25 mm² do bare metal → 5-30 sec measurement → record. '
          'Tolerancja ±10% major alloying elements (Cr, Ni, Mo). '
          'Krytyczne: 100% PMI dla sour service + hydrogen, statistical sampling 5-25% innych.',
          '3 methods (API RP 578): handheld XRF (most common, but NO carbon detection → cannot tell 304 vs 304L), handheld OES (carbon-capable, small spark), LIBS (laser, no contact). '
          'Procedure: grind 25 mm² to bare metal → 5-30 sec read → record. '
          'Tolerance ±10% on major elements (Cr, Ni, Mo). '
          'Critical: 100% PMI for sour service + hydrogen, statistical 5-25% sampling elsewhere.',
        ),
        tags: ['pmi', 'xrf', 'oes', 'libs', 'api-578', 'alloy-id'],
      ),
      HelpEntry(
        id: 'no-copper-ammonia',
        question: _bi(
          'Dlaczego w NH₃ nie wolno używać miedzi?',
          'Why is copper forbidden in ammonia service?',
        ),
        answer: _bi(
          'Amoniak reaguje z miedzią + mosiądzem + brązem → tworzą się rozpuszczalne kompleksy Cu(NH₃)₄²⁺ → korozja + cracking miedzi w miesiącach. '
          'IIAR 2 wymaga: tylko carbon steel (A106 Gr B), SS 304/316 dla high-P/low-T, aluminum dla cryogenic. '
          'NIGDY: Cu, brass, bronze, galvanized (Zn też reaguje). Sprawdź każdy element (zacisk masy, narzędzia, plomby) przed instalacją.',
          'Ammonia reacts with copper + brass + bronze → forms soluble Cu(NH₃)₄²⁺ complexes → copper corrosion + cracking in months. '
          'IIAR 2 requires: carbon steel only (A106 Gr B), SS 304/316 for high-P/low-T, aluminum for cryogenic. '
          'NEVER: Cu, brass, bronze, galvanized (Zn also reacts). Check every component (ground clamp, tools, seals) before install.',
        ),
        tags: ['ammonia', 'nh3', 'copper', 'iiar', 'no-copper', 'refrigeration'],
      ),
      HelpEntry(
        id: 'h2so4-velocity',
        question: _bi(
          'Jakie velocity dla 98% H₂SO₄ w CS pipe?',
          'What velocity for 98% H₂SO₄ in CS pipe?',
        ),
        answer: _bi(
          'MAX 0.9 m/s (3 ft/s) — wyższe powoduje erozję pasywnej warstwy FeSO₄ → katastrofalna korozja. '
          'Mechanizm: stężony kwas (93-99%) tworzy ochronną warstwę siarczanu żelaza. Przy 2 m/s rate korozji rośnie 10-50×. '
          'Material: A106 Gr B Sch 80 (corrosion allowance), welded bez PWHT. Slope 1:50 w kierunku drain. NO pockets, eccentric reducer flat-top.',
          'MAX 0.9 m/s (3 ft/s) — higher velocity erodes the passive FeSO₄ layer → catastrophic corrosion. '
          'Mechanism: concentrated acid (93-99%) forms protective iron sulfate film. At 2 m/s, corrosion rate increases 10-50×. '
          'Material: A106 Gr B Sch 80 (corrosion allowance), welded no PWHT. Slope 1:50 to drain. NO pockets, eccentric reducer flat-top.',
        ),
        tags: ['h2so4', 'sulfuric-acid', 'velocity', 'corrosion', 'passivation'],
      ),
    ],
  ),

  // ════════════════════════════════════════════════════════════════════════
  // 5. PWHT + PREHEAT + CE
  // ════════════════════════════════════════════════════════════════════════
  HelpCategory(
    id: 'pwht-preheat',
    title: _bi('Preheat i PWHT', 'Preheat & PWHT'),
    subtitle: _bi('CE, ramp rates, hold times', 'CE, ramp rates, hold times'),
    icon: Icons.settings,
    accentArgb: 0xFFEF5350,
    entries: [
      HelpEntry(
        id: 'preheat-temperature',
        question: _bi(
          'Jak ustalić temperaturę preheat?',
          'How to determine preheat temperature?',
        ),
        answer: _bi(
          'Carbon Equivalent (CE) wg IIW: CE = C + Mn/6 + (Cr+Mo+V)/5 + (Ni+Cu)/15. '
          'CE <0.35 — brak preheat dla cienkiej ścianki, 50°C dla >25 mm. '
          'CE 0.35-0.45 — preheat 100-150°C. '
          'CE 0.45-0.55 — 150-200°C + low-H electrody. '
          'CE >0.55 — 200-300°C + PWHT mandatory. '
          'P91: 200-300°C (mandatory), interpass ≤350°C. P22: ≥150°C dla ≥10 mm.',
          'Carbon Equivalent (CE) per IIW: CE = C + Mn/6 + (Cr+Mo+V)/5 + (Ni+Cu)/15. '
          'CE <0.35 — no preheat for thin wall, 50°C for >25 mm. '
          'CE 0.35-0.45 — preheat 100-150°C. '
          'CE 0.45-0.55 — 150-200°C + low-H electrodes. '
          'CE >0.55 — 200-300°C + PWHT mandatory. '
          'P91: 200-300°C (mandatory), interpass ≤350°C. P22: ≥150°C for ≥10 mm.',
        ),
        tags: ['preheat', 'ce', 'carbon-equivalent', 'p91', 'p22', 'iiw'],
      ),
      HelpEntry(
        id: 'pwht-p91',
        question: _bi(
          'Jak wykonać PWHT P91 prawidłowo?',
          'How to perform P91 PWHT correctly?',
        ),
        answer: _bi(
          'P91 PWHT: 730-760°C × 1 h per inch (25 mm) wall thickness, min 1 h. '
          'Ramp rate ≤222°C/h. Cool ≤278°C/h kontrolowane. '
          'NIE przekraczaj 770°C — re-austenization, utrata wszystkich PWHT benefits, re-weld. '
          'Type IV crack zone: fine-grained HAZ — uniform T critical w całym HAZ. '
          'Recording thermocouples on weld + 3× cardinal positions, retain charts dla audit.',
          'P91 PWHT: 730-760°C × 1 h per inch (25 mm) wall, min 1 h. '
          'Ramp rate ≤222°C/h. Cool ≤278°C/h controlled. '
          'NEVER exceed 770°C — re-austenization, all PWHT benefits lost, re-weld required. '
          'Type IV crack zone: fine-grained HAZ — uniform T critical across HAZ. '
          'Recording thermocouples on weld + 3× cardinal positions, retain charts for audit.',
        ),
        tags: ['pwht', 'p91', 'creep', 'type-iv', 'heat-treatment'],
      ),
      HelpEntry(
        id: 'heat-input-formula',
        question: _bi(
          'Jak liczyć heat input (kJ/mm)?',
          'How to calculate heat input (kJ/mm)?',
        ),
        answer: _bi(
          'HI [kJ/mm] = (V × I × 60) / (travel_speed_mm/min × 1000). '
          'Przykład: 22 V × 110 A × 60 / (200 mm/min × 1000) = 0.726 kJ/mm. '
          'P91 WPS range: 1.0-2.5 kJ/mm, NIE przekraczaj górnego. '
          'Za wysokie HI = coarse-grain HAZ, low toughness, wider Type IV zone. '
          'Za niskie HI = fast cooling, hardening, hydrogen cracking risk.',
          'HI [kJ/mm] = (V × I × 60) / (travel_speed_mm/min × 1000). '
          'Example: 22 V × 110 A × 60 / (200 mm/min × 1000) = 0.726 kJ/mm. '
          'P91 WPS range: 1.0-2.5 kJ/mm, do NOT exceed upper. '
          'Too high HI = coarse-grain HAZ, low toughness, wider Type IV. '
          'Too low HI = fast cooling, hardening, hydrogen cracking risk.',
        ),
        tags: ['heat-input', 'wps', 'p91', 'kj-mm', 'formula'],
      ),
    ],
  ),

  // ════════════════════════════════════════════════════════════════════════
  // 6. NDT (RT, UT, PAUT, MT, PT)
  // ════════════════════════════════════════════════════════════════════════
  HelpCategory(
    id: 'ndt',
    title: _bi('NDT — Badania nieniszczące', 'NDT — Non-destructive testing'),
    subtitle: _bi('RT, UT, PAUT, MT, PT', 'RT, UT, PAUT, MT, PT'),
    icon: Icons.science,
    accentArgb: 0xFF66BB6A,
    entries: [
      HelpEntry(
        id: 'rt-iqi',
        question: _bi(
          'Co to IQI / penetrameter w RT?',
          'What is IQI / penetrameter in RT?',
        ),
        answer: _bi(
          'IQI (Image Quality Indicator) weryfikuje czy zdjęcie ma wymaganą czułość. Bez widocznego IQI radiograf jest nieważny. '
          'Wire-type (ASME V, ASTM E747): 6 drutów malejącej średnicy, najmniejszy widoczny = czułość = (Ø/grubość)×100%. '
          'Wymagana czułość 2% (najmniejszy widoczny drut ≤2% grubości). '
          'Hole-type (ASTM E1025): płytka z 3 dziurkami (1T, 2T, 4T). Standard 2-2T dla większości welds.',
          'IQI (Image Quality Indicator) verifies the radiograph meets required sensitivity. No visible IQI = invalid radiograph. '
          'Wire-type (ASME V, ASTM E747): 6 wires of decreasing diameter, smallest visible = sensitivity = (Ø/thickness)×100%. '
          'Required 2% sensitivity (smallest visible wire ≤2% of thickness). '
          'Hole-type (ASTM E1025): plate with 3 holes (1T, 2T, 4T). Standard 2-2T for most welds.',
        ),
        tags: ['rt', 'iqi', 'penetrameter', 'asme-v', 'sensitivity'],
      ),
      HelpEntry(
        id: 'paut-vs-rt',
        question: _bi(
          'Kiedy PAUT zamiast RT?',
          'When to use PAUT instead of RT?',
        ),
        answer: _bi(
          'PAUT (phased array UT) — wieloelementowa głowica, multiple beam angles 40-70° w jednym pass. '
          'Plusy vs RT: brak promieniowania (24/7 work bez exclusion zone), lepsze dla planar defects (cracks, LOF), real-time wyniki, digital record. '
          'Minusy: gorsze dla volumetric (porosity, slag) — RT lepsze. '
          'ASME B31.3 (2022+) akceptuje PAUT jako substytut RT. Wymaga ASNT Level II/III operatora.',
          'PAUT (phased array UT) — multi-element probe, multiple beam angles 40-70° in single pass. '
          'Pros vs RT: no radiation (24/7 work, no exclusion zone), better for planar defects (cracks, LOF), real-time results, digital record. '
          'Cons: worse for volumetric (porosity, slag) — RT better. '
          'ASME B31.3 (2022+) accepts PAUT as RT substitute. Requires ASNT Level II/III operator.',
        ),
        tags: ['paut', 'rt', 'phased-array', 'ut', 'ndt-comparison'],
      ),
      HelpEntry(
        id: 'mt-vs-pt',
        question: _bi(
          'MT czy PT — kiedy które badanie?',
          'MT or PT — which one when?',
        ),
        answer: _bi(
          'MT (magnetic particle): tylko dla ferromagnetic (CS, low-alloy, martensitic SS). Wykrywa surface + sub-surface (do 6 mm pod skin). Szybkie, tanie. '
          'PT (penetrant): WSZYSTKIE materiały (włącznie SS 300-series, Al, Cu, Ti, plastics). Tylko surface-breaking defects. '
          'Acceptance ASME B31.3 §344.3: linear ≥3× width — limit 2-6 mm zależnie od grubości. Rounded <6 mm. CRACKS: ZERO.',
          'MT (magnetic particle): ferromagnetic only (CS, low-alloy, martensitic SS). Detects surface + sub-surface (to 6 mm below). Fast, cheap. '
          'PT (penetrant): ALL materials (incl. 300-series SS, Al, Cu, Ti, plastics). Surface-breaking only. '
          'Acceptance ASME B31.3 §344.3: linear ≥3× width — limit 2-6 mm depending on thickness. Rounded <6 mm. CRACKS: ZERO.',
        ),
        tags: ['mt', 'pt', 'magnetic-particle', 'penetrant', 'surface-defects'],
      ),
    ],
  ),

  // ════════════════════════════════════════════════════════════════════════
  // 7. FLANSZE + BOLTING
  // ════════════════════════════════════════════════════════════════════════
  HelpCategory(
    id: 'flanges-bolting',
    title: _bi('Flansze i moment śrub', 'Flanges & bolt torque'),
    subtitle: _bi('B7, gaskets, star pattern', 'B7, gaskets, star pattern'),
    icon: Icons.handyman,
    accentArgb: 0xFFAB47BC,
    entries: [
      HelpEntry(
        id: 'bolt-grades',
        question: _bi(
          'Czym różnią się B7, B7M, B16, B8M?',
          'How do B7, B7M, B16, B8M differ?',
        ),
        answer: _bi(
          'ASTM A193 grades: '
          'B7 = standard CS dla większości service, do 400°C, hardness do 35 HRC. '
          'B7M = "modified", lower hardness (≤22 HRC) dla sour/NACE service. '
          'B16 = Cr-Mo dla high T (do 540°C, np. steam) — NIE dla sour. '
          'B8M = SS 316, dla SS flanges, lower strength ale corrosion-resistant. '
          'L7/L7M = low-T variants dla cryogenic.',
          'ASTM A193 grades: '
          'B7 = standard CS for most service, to 400°C, hardness up to 35 HRC. '
          'B7M = "modified", lower hardness (≤22 HRC) for sour/NACE service. '
          'B16 = Cr-Mo for high T (to 540°C, e.g. steam) — NOT for sour. '
          'B8M = SS 316, for SS flanges, lower strength but corrosion-resistant. '
          'L7/L7M = low-T variants for cryogenic.',
        ),
        tags: ['bolts', 'b7', 'b7m', 'b16', 'b8m', 'a193', 'flange'],
      ),
      HelpEntry(
        id: 'torque-pattern',
        question: _bi(
          'Jak skręcać flansze: star pattern?',
          'How to bolt up flanges: star pattern?',
        ),
        answer: _bi(
          'ASME PCC-1: star pattern 4 passes: '
          '1) 25% target torque, '
          '2) 50%, '
          '3) 75%, '
          '4) 100% — wszystkie w gwiazdę. '
          '5) Final circular pass 100% (kilka śrub się relaxuje przy innych). '
          '6) Relaxation pass po 20 min - 4 h (re-torque 100%). '
          'Bez star pattern → uneven gasket compression → blow-out. Use anti-seize (Cu-based dla CS, Ni-based dla SS).',
          'ASME PCC-1: star pattern 4 passes: '
          '1) 25% target torque, '
          '2) 50%, '
          '3) 75%, '
          '4) 100% — all in star sequence. '
          '5) Final circular pass 100% (some bolts relax when others tighten). '
          '6) Relaxation pass after 20 min - 4 h (re-torque 100%). '
          'Without star pattern → uneven gasket compression → blow-out. Use anti-seize (Cu-based for CS, Ni-based for SS).',
        ),
        tags: ['torque', 'star-pattern', 'asme-pcc-1', 'flange', 'bolt-up'],
      ),
      HelpEntry(
        id: 'gasket-types',
        question: _bi(
          'Spiral wound czy graphite — jaką uszczelkę wybrać?',
          'Spiral wound or graphite — which gasket?',
        ),
        answer: _bi(
          'Spiral wound (Flexitallic CGI): standard dla większości proces (steam, oil, gas), Class 150-2500, T do 600°C. Inner ring + outer ring + spiral with filler (graphite/PTFE/mica). '
          'Pure graphite (Flexitallic Sigma): high-T (>400°C), aggressive media (acids). '
          'PTFE (Garlock 3500): pharma/food, sanitary, niski T. '
          'Kammprofile: solid grooved metal core + facing — premium, dla critical service.',
          'Spiral wound (Flexitallic CGI): standard for most process (steam, oil, gas), Class 150-2500, T to 600°C. Inner ring + outer ring + spiral with filler (graphite/PTFE/mica). '
          'Pure graphite (Flexitallic Sigma): high-T (>400°C), aggressive media (acids). '
          'PTFE (Garlock 3500): pharma/food, sanitary, low T. '
          'Kammprofile: solid grooved metal core + facing — premium, for critical service.',
        ),
        tags: ['gasket', 'spiral-wound', 'graphite', 'ptfe', 'kammprofile', 'flange'],
      ),
    ],
  ),

  // ════════════════════════════════════════════════════════════════════════
  // 8. PODPORY RUR (Pipe supports)
  // ════════════════════════════════════════════════════════════════════════
  HelpCategory(
    id: 'pipe-supports',
    title: _bi('Podpory i wsporniki', 'Supports & hangers'),
    subtitle: _bi('Spacing, spring, friction', 'Spacing, spring, friction'),
    icon: Icons.anchor,
    accentArgb: 0xFF8D6E63,
    entries: [
      HelpEntry(
        id: 'support-spacing',
        question: _bi(
          'Jaki rozstaw podpór dla CS w/g B31.3?',
          'What support spacing for CS per B31.3?',
        ),
        answer: _bi(
          'ASME B31.3 dla CS pełnej wody, ambient T: '
          'DN 50 (2"): 4.0 m max, '
          'DN 100 (4"): 5.5 m, '
          'DN 150 (6"): 6.4 m, '
          'DN 200 (8"): 7.0 m, '
          'DN 300 (12"): 8.2 m, '
          'DN 600 (24"): 10.0 m. '
          'Redukuj 30-50% przy: zawory/flansze nearby, vibration service, T >400°C, insulation.',
          'ASME B31.3 for CS full of water, ambient T: '
          'DN 50 (2"): 4.0 m max, '
          'DN 100 (4"): 5.5 m, '
          'DN 150 (6"): 6.4 m, '
          'DN 200 (8"): 7.0 m, '
          'DN 300 (12"): 8.2 m, '
          'DN 600 (24"): 10.0 m. '
          'Reduce 30-50% with: valves/flanges nearby, vibration, T >400°C, insulation.',
        ),
        tags: ['support', 'spacing', 'rozstaw', 'asme-b31', 'mss-sp-58'],
      ),
      HelpEntry(
        id: 'spring-hanger-variable-constant',
        question: _bi(
          'Spring hanger: variable czy constant?',
          'Spring hanger: variable or constant?',
        ),
        answer: _bi(
          'Variable spring (Anvil, Lisega): load variation ≤25% — dla movement <75 mm + non-critical. F = k·x (Hooke prosto). Tanio. '
          'Constant load: variation ≤6% — dla movement >75 mm lub critical (main steam, turbine inlet). Cam mechanism utrzymuje stałą siłę. 2-3× droższe. '
          'Lock-down stops podczas hydrotest (water + lock = rigid), release po fill + heatup do operating T.',
          'Variable spring (Anvil, Lisega): load variation ≤25% — for movement <75 mm + non-critical. F = k·x (Hooke linear). Cheap. '
          'Constant load: variation ≤6% — for movement >75 mm or critical (main steam, turbine inlet). Cam mechanism holds constant force. 2-3× more expensive. '
          'Lock-down stops during hydrotest (water + lock = rigid), release after fill + heat-up to operating T.',
        ),
        tags: ['spring-hanger', 'variable', 'constant', 'mss-sp-58', 'thermal-movement'],
      ),
      HelpEntry(
        id: 'ptfe-slide-plate',
        question: _bi(
          'Po co PTFE slide plate na podporze?',
          'Why use PTFE slide plate on a support?',
        ),
        answer: _bi(
          'Steel-on-steel sliding ma μ ≈ 0.3-0.5 — wysokie reaction forces na supports + struktury. '
          'PTFE slide plate (2 płytki PTFE: na shoe + na beam) obniża μ do 0.10-0.15. '
          'Rezultat: 3× niższe siły reakcji, mniejsze nozzle loads na pumps/vessels, długoletnia trwałość PTFE (UV-res, T do 260°C). '
          'Zawsze inspekcja roczna — wear może przekraczać 1 mm/rok przy high cycling.',
          'Steel-on-steel sliding has μ ≈ 0.3-0.5 — high reaction forces on supports + structure. '
          'PTFE slide plate (2 PTFE pads: on shoe + on beam) drops μ to 0.10-0.15. '
          'Result: 3× lower reaction forces, smaller nozzle loads on pumps/vessels, long PTFE life (UV-res, T to 260°C). '
          'Annual inspection mandatory — wear can exceed 1 mm/year with high cycling.',
        ),
        tags: ['ptfe', 'slide-plate', 'friction', 'support', 'mss-sp-58'],
      ),
    ],
  ),

  // ════════════════════════════════════════════════════════════════════════
  // 9. BEZPIECZEŃSTWO (Hot work, confined space, PPE)
  // ════════════════════════════════════════════════════════════════════════
  HelpCategory(
    id: 'safety',
    title: _bi('Bezpieczeństwo i permity', 'Safety & permits'),
    subtitle: _bi('Hot work, confined space, PPE', 'Hot work, confined space, PPE'),
    icon: Icons.health_and_safety,
    accentArgb: 0xFFE57373,
    entries: [
      HelpEntry(
        id: 'hot-work-35-ft',
        question: _bi(
          'Co to zasada 35 stóp (NFPA 51B)?',
          "What's the 35-foot rule (NFPA 51B)?",
        ),
        answer: _bi(
          'Wokół miejsca hot work (welding, grinding, cutting) musi być **promień 10.7 m (35 ft) clean of flammables**: '
          'usuń materiały palne, zakryj fire-resistant blankets, polej wodą podłogę palną, zakryj kratki ściekowe (sparks → vapors w kanalizacji = BLEVE). '
          'Fire watch 30 min PO zakończeniu pracy (high-risk: 60 min+). Atmospheric test LEL <10%, O₂ 19.5-23.5%, H₂S/CO/NH₃ per spec.',
          'Within hot work radius **10.7 m (35 ft) clean of flammables**: '
          'remove combustibles, cover with fire blankets, wet combustible floors, cover drains (sparks → vapors in sewer = BLEVE). '
          'Fire watch 30 min AFTER work (high-risk: 60 min+). Atmospheric test LEL <10%, O₂ 19.5-23.5%, H₂S/CO/NH₃ per spec.',
        ),
        tags: ['hot-work', 'nfpa-51b', 'fire-watch', '35-ft', 'permit'],
      ),
      HelpEntry(
        id: 'confined-space-o2-lel',
        question: _bi(
          'Confined space: jakie atmospheric tests?',
          'Confined space: what atmospheric tests?',
        ),
        answer: _bi(
          'OSHA 1910.146 — kolejność (oxygen FIRST, bo inne mierniki potrzebują O₂!): '
          '1) **O₂: 19.5-23.5%** — niżej = nieprzytomność, wyżej = fire hazard. '
          '2) **LEL <10%** — flammables. '
          '3) **Toxic** per substance: H₂S <10 ppm, CO <25 ppm, NH₃ <25 ppm. '
          'Continuous monitoring na 4-gas detector w trakcie pracy. Test na 3 levels (bottom/middle/top — gases stratify). Ventilation: 5-7 air changes/h.',
          'OSHA 1910.146 — order (oxygen FIRST, because other meters need O₂!): '
          '1) **O₂: 19.5-23.5%** — lower = unconsciousness, higher = fire hazard. '
          '2) **LEL <10%** — flammables. '
          '3) **Toxic** per substance: H₂S <10 ppm, CO <25 ppm, NH₃ <25 ppm. '
          'Continuous monitoring on 4-gas detector during work. Test 3 levels (bottom/middle/top — gases stratify). Ventilation: 5-7 air changes/h.',
        ),
        tags: ['confined-space', 'osha', 'o2', 'lel', 'h2s', 'atmospheric-test'],
      ),
      HelpEntry(
        id: 'welder-shade',
        question: _bi(
          'Jaki shade na masce dla SMAW/TIG/MIG?',
          'What lens shade for SMAW/TIG/MIG?',
        ),
        answer: _bi(
          'ANSI Z87.1 shade chart (im więcej, tym ciemniej): '
          '**SMAW** (stick): shade 10 @ <100 A, 11 @ 100-150 A, 12 @ 150-250 A, 13 @ 250-350 A, 14 @ >350 A. '
          '**TIG**: 8 @ <30 A, 9-10 @ 30-100 A, 11-12 @ 100-200 A, 13 @ 200-400 A. '
          '**MIG/FCAW**: 10 @ <100 A, 11-12 @ 100-200 A, 13 @ 200-400 A. '
          'Aluminum: +1 shade (więcej UV). Carbon arc gouging: 13-14 (very intense).',
          'ANSI Z87.1 shade chart (higher = darker): '
          '**SMAW** (stick): shade 10 @ <100 A, 11 @ 100-150 A, 12 @ 150-250 A, 13 @ 250-350 A, 14 @ >350 A. '
          '**TIG**: 8 @ <30 A, 9-10 @ 30-100 A, 11-12 @ 100-200 A, 13 @ 200-400 A. '
          '**MIG/FCAW**: 10 @ <100 A, 11-12 @ 100-200 A, 13 @ 200-400 A. '
          'Aluminum: +1 shade (more UV). Carbon arc gouging: 13-14 (very intense).',
        ),
        tags: ['shade', 'helmet', 'ansi-z87', 'smaw', 'tig', 'mig', 'ppe'],
      ),
      HelpEntry(
        id: 'papr-cr6',
        question: _bi(
          'Kiedy PAPR przy spawaniu SS?',
          'When PAPR for SS welding?',
        ),
        answer: _bi(
          'Spawanie stali nierdzewnej generuje **hexavalent chromium (Cr⁶⁺)** — cancerogen, OSHA PEL 5 µg/m³ (bardzo nisko, łatwe do przekroczenia). '
          'PAPR (Powered Air-Purifying Respirator) z HEPA + integralna maska welder = APF 1000, positive pressure inside = no fume ingress. '
          'Producenci: Optrel, 3M Speedglas, Miller. '
          'Koszt 1.5-3.5k PLN per unit (vs 200-500 PLN standard helmet). OSHA preferuje dla SS — protective + comfortable.',
          'SS welding generates **hexavalent chromium (Cr⁶⁺)** — carcinogen, OSHA PEL 5 µg/m³ (very low, easily exceeded). '
          'PAPR (Powered Air-Purifying Respirator) with HEPA + integrated welder helmet = APF 1000, positive pressure inside = no fume ingress. '
          'Makers: Optrel, 3M Speedglas, Miller. '
          'Cost 1.5-3.5k PLN per unit (vs 200-500 PLN standard helmet). OSHA preferred for SS — protective + comfortable.',
        ),
        tags: ['papr', 'cr6', 'hex-chrome', 'fume', 'ss', 'respirator', 'osha'],
      ),
    ],
  ),

  // ════════════════════════════════════════════════════════════════════════
  // 10. KODY I NORMY (ASME B31, API, NACE)
  // ════════════════════════════════════════════════════════════════════════
  HelpCategory(
    id: 'codes',
    title: _bi('Kody i normy', 'Codes & standards'),
    subtitle: _bi('ASME B31, API, NACE', 'ASME B31, API, NACE'),
    icon: Icons.menu_book,
    accentArgb: 0xFF5C6BC0,
    entries: [
      HelpEntry(
        id: 'b31-family',
        question: _bi(
          'B31.1 vs B31.3 vs B31.4 vs B31.8 — który kod?',
          'B31.1 vs B31.3 vs B31.4 vs B31.8 — which code?',
        ),
        answer: _bi(
          '**B31.1** Power Piping — boilery, steam, power plant (4:1 safety factor, większy margines). '
          '**B31.3** Process Piping — refinery, chem plant, pharma (3:1 safety factor). NAJCZĘSTSZY w przemyśle. '
          '**B31.4** Liquid Pipeline — crude oil, products, slurry cross-country. Design factor F=0.72. '
          '**B31.8** Gas Pipeline — natural gas + distribution. F zmienne 0.40-0.72 wg location class (gęstość zabudowy). '
          '**B31.9** Building Services — HVAC, plumbing. '
          '**B31.12** Hydrogen — H₂ specific (X52 max material).',
          '**B31.1** Power Piping — boilers, steam, power plant (4:1 safety factor, more margin). '
          '**B31.3** Process Piping — refinery, chem, pharma (3:1 safety factor). MOST COMMON. '
          '**B31.4** Liquid Pipeline — crude, products, slurry cross-country. Design factor F=0.72. '
          '**B31.8** Gas Pipeline — natural gas + distribution. F variable 0.40-0.72 by location class. '
          '**B31.9** Building Services — HVAC, plumbing. '
          '**B31.12** Hydrogen — H₂ specific (X52 max material).',
        ),
        tags: ['asme-b31', 'codes', 'process', 'power', 'pipeline'],
      ),
      HelpEntry(
        id: 'api-941-nelson',
        question: _bi(
          'Co to Nelson curves (API 941)?',
          'What are Nelson curves (API 941)?',
        ),
        answer: _bi(
          'API RP 941: krzywe T vs H₂ partial pressure dla każdego stopu — poniżej krzywej = safe, powyżej = High-Temperature Hydrogen Attack (HTHA). '
          'Aplikacja >204°C (400°F) + H₂. '
          'Krzywa CS dla non-PWHT 50°F niższa niż dla PWHT (update 2016). '
          'C-0.5Mo curve USUNIĘTA z API 941 (po failures jak Tesoro Anacortes 2010). '
          'Mechanizm: H + carbon/carbides → metan trapped → fissures + decarburization → cracking.',
          'API RP 941: curves of T vs H₂ partial pressure per alloy — below curve = safe, above = High-Temperature Hydrogen Attack (HTHA). '
          'Applies >204°C (400°F) + H₂. '
          'CS non-PWHT curve is 50°F lower than PWHT (2016 update). '
          'C-0.5Mo curve REMOVED from API 941 (after failures like Tesoro Anacortes 2010). '
          'Mechanism: H + carbon/carbides → methane trapped → fissures + decarburization → cracking.',
        ),
        tags: ['api-941', 'nelson-curve', 'htha', 'hydrogen', 'p22', 'p11'],
      ),
      HelpEntry(
        id: 'wps-pqr-wpq',
        question: _bi(
          'WPS, PQR, WPQ — co to dokładnie?',
          'WPS, PQR, WPQ — what exactly?',
        ),
        answer: _bi(
          '**WPS (Welding Procedure Specification)** — instrukcja "jak spawać" dla welder: proces, base material P-no, filler F-no, position (1G-6G), parametry, preheat, PWHT, gas. '
          '**PQR (Procedure Qualification Record)** — dowód że WPS działa: spawano coupon → testy mechaniczne (tensile, bend, Charpy, hardness, macro) → wszystkie pass → PQR podpisany przez PE. '
          '**WPQ (Welder Performance Qualification)** — test każdego welder na danej WPS. 6G pipe test kwalifikuje WSZYSTKIE pozycje (best). Continuity: musi spawać co 6 m-cy lub re-test.',
          '**WPS (Welding Procedure Specification)** — instructions "how to weld" for welder: process, base P-no, filler F-no, position (1G-6G), parameters, preheat, PWHT, gas. '
          '**PQR (Procedure Qualification Record)** — proof the WPS works: weld coupon → mechanical tests (tensile, bend, Charpy, hardness, macro) → all pass → PQR signed by PE. '
          '**WPQ (Welder Performance Qualification)** — each welder tested on given WPS. 6G pipe test qualifies ALL positions (best). Continuity: must weld every 6 mo or re-test.',
        ),
        tags: ['wps', 'pqr', 'wpq', 'asme-ix', 'qualification', 'welder'],
      ),
    ],
  ),

  // ════════════════════════════════════════════════════════════════════════
  // 11. ISO + P&ID + SYMBOLE
  // ════════════════════════════════════════════════════════════════════════
  HelpCategory(
    id: 'iso-drawings',
    title: _bi('Izometryki i symbole', 'Isometrics & symbols'),
    subtitle: _bi('Czytanie ISO, take-out', 'Reading ISO, take-out'),
    icon: Icons.account_tree,
    accentArgb: 0xFF1A8A9B,
    entries: [
      HelpEntry(
        id: 'iso-take-out',
        question: _bi(
          'Co to take-out i jak liczyć cięcie?',
          'What is take-out and how to calculate cut length?',
        ),
        answer: _bi(
          'Take-out = długość komponentu liczona od face do centerline (dla kolanka) lub jego pełna długość (dla flange, valve). '
          '**CUT = ISO_dimension − Σ(take-outs)**. '
          'Przykład: ISO face-to-face 1000 mm między dwoma kolankami 90° LR (take-out = R = 1.5×D, dla 4" = 152 mm × 2 = 304 mm) + flange 25 mm × 2 = 50 mm → CUT = 1000 − 304 − 50 = 646 mm. '
          'Apka ma tabelę elbow takeouts (LR/SR 90°/45°) i kalkuluje automatycznie.',
          'Take-out = component length from face to centerline (elbow) or full length (flange, valve). '
          '**CUT = ISO_dimension − Σ(take-outs)**. '
          'Example: ISO face-to-face 1000 mm between two 90° LR elbows (take-out = R = 1.5×D, for 4" = 152 mm × 2 = 304 mm) + 2× flange 25 mm = 50 mm → CUT = 1000 − 304 − 50 = 646 mm. '
          'App has elbow takeout tables (LR/SR 90°/45°) and calculates automatically.',
        ),
        tags: ['iso', 'take-out', 'cut', 'elbow', 'face-to-face'],
      ),
      HelpEntry(
        id: 'pid-symbols',
        question: _bi(
          'Najważniejsze symbole P&ID?',
          'Most important P&ID symbols?',
        ),
        answer: _bi(
          'Główne symbole (ISA-5.1): '
          '**Zawory**: gate (kąt w środku), globe (sphere), ball (krąg z linią), check (V), butterfly (D z osią). '
          '**Pompy**: circle z trójkątem (centrifugal), prostokąt (PD). '
          '**Heat exchanger**: dwa równoległe rurociągi (shell + tube). '
          '**Instrumenty**: kółko z ID — TT=temp transmitter, PT=pressure, FT=flow, LT=level. Bubble line solid = field, dashed = control room. '
          '**Direction arrow** zawsze na każdym pipe segment.',
          'Main symbols (ISA-5.1): '
          '**Valves**: gate (angle inside), globe (sphere), ball (circle with line), check (V), butterfly (D with axis). '
          '**Pumps**: circle with triangle (centrifugal), rectangle (PD). '
          '**Heat exchanger**: two parallel pipes (shell + tube). '
          '**Instruments**: bubble with ID — TT=temp transmitter, PT=pressure, FT=flow, LT=level. Solid line = field, dashed = control room. '
          '**Direction arrow** always on each pipe segment.',
        ),
        tags: ['pid', 'symbols', 'isa-5-1', 'valves', 'instruments'],
      ),
      HelpEntry(
        id: 'pipe-labeling',
        question: _bi(
          'Jak oznaczać rury wg ASME A13.1?',
          'How to label pipes per ASME A13.1?',
        ),
        answer: _bi(
          'ASME A13.1 — color code + flow arrow + legend. Kolory wg hazard (NIE wg substance): '
          '**Flammable/oxidizing**: white text on brown (Pantone 4515). '
          '**Toxic/corrosive**: white on orange (Pantone 152). '
          '**Fire water**: white on red (Pantone 186). '
          '**Compressed air/gas**: white on blue. '
          '**Cooling water**: white on green. '
          'Letter height proporcjonalne do pipe OD: 0.5" dla pipe ≤1.25", do 3.5" dla pipe >10". Placement: co 7.6 m + each direction change + each valve + walls penetrations.',
          'ASME A13.1 — color code + flow arrow + legend. Colors by hazard (NOT by substance): '
          '**Flammable/oxidizing**: white text on brown (Pantone 4515). '
          '**Toxic/corrosive**: white on orange (Pantone 152). '
          '**Fire water**: white on red (Pantone 186). '
          '**Compressed air/gas**: white on blue. '
          '**Cooling water**: white on green. '
          'Letter height proportional to pipe OD: 0.5" for pipe ≤1.25", up to 3.5" for pipe >10". Placement: every 7.6 m + each direction change + each valve + wall penetrations.',
        ),
        tags: ['labeling', 'asme-a13', 'color-code', 'pipe-marking'],
      ),
    ],
  ),

  // ════════════════════════════════════════════════════════════════════════
  // 12. KALKULACJE PRAKTYCZNE
  // ════════════════════════════════════════════════════════════════════════
  HelpCategory(
    id: 'calculations',
    title: _bi('Kalkulacje praktyczne', 'Practical calculations'),
    subtitle: _bi('NPSH, expansion, hydrotest', 'NPSH, expansion, hydrotest'),
    icon: Icons.factory,
    accentArgb: 0xFF00897B,
    entries: [
      HelpEntry(
        id: 'thermal-expansion',
        question: _bi(
          'Jak liczyć rozszerzalność cieplną rury?',
          'How to calculate pipe thermal expansion?',
        ),
        answer: _bi(
          '**ΔL = α × L × ΔT**, gdzie α to coefficient of thermal expansion. '
          'CS (A106): α = 12 × 10⁻⁶ /°C → 100 m rury 20°C → 200°C: ΔL = 12e-6 × 100 × 180 = 0.216 m = 216 mm. '
          'SS 304: α = 17 × 10⁻⁶ /°C (większa expansion!). '
          'Bez kompensacji → flange leak, support failure, equipment damage. Kompensacja: expansion loops (covered B31.3 §319) lub bellows (covered MSS).',
          '**ΔL = α × L × ΔT**, where α is coefficient of thermal expansion. '
          'CS (A106): α = 12 × 10⁻⁶ /°C → 100 m pipe 20°C → 200°C: ΔL = 12e-6 × 100 × 180 = 0.216 m = 216 mm. '
          'SS 304: α = 17 × 10⁻⁶ /°C (larger expansion!). '
          'No compensation → flange leak, support failure, equipment damage. Compensation: expansion loops (B31.3 §319) or bellows (MSS-covered).',
        ),
        tags: ['thermal-expansion', 'dylatacja', 'cs', 'ss', 'asme-b31'],
      ),
      HelpEntry(
        id: 'hydrotest-pressure',
        question: _bi(
          'Jakie ciśnienie hydrotestu?',
          'What hydrotest pressure?',
        ),
        answer: _bi(
          'ASME B31.3 §345.4: **P_test = 1.5 × P_design** w ambient T, ale skorygowane przy T compensation (P_test ≤ 1.5 × P_design × S_test/S_design). '
          'Hold time: min 10 min (kod), praktycznie 1-4 h dla wiarygodnej leak detection. '
          'Fluid: water default (incompressible, low stored energy). Avoid chloride water on SS (>50 ppm = pitting risk). '
          'Pneumatic test allowed only when hydro impractical (cryogenic, vacuum) — duże zagrożenie energii.',
          'ASME B31.3 §345.4: **P_test = 1.5 × P_design** at ambient T, but T-compensated (P_test ≤ 1.5 × P_design × S_test/S_design). '
          'Hold time: min 10 min (code), practical 1-4 h for reliable leak detection. '
          'Fluid: water default (incompressible, low stored energy). Avoid chloride water on SS (>50 ppm = pitting risk). '
          'Pneumatic test allowed only when hydro impractical (cryogenic, vacuum) — huge energy hazard.',
        ),
        tags: ['hydrotest', 'pressure-test', 'asme-b31', 'leak-test'],
      ),
      HelpEntry(
        id: 'npsh',
        question: _bi(
          'Co to NPSH i jak unikać kawitacji?',
          'What is NPSH and how to avoid cavitation?',
        ),
        answer: _bi(
          'NPSH (Net Positive Suction Head) = energia per unit weight cieczy nad jej vapor pressure. '
          'NPSHa (available) = P_atm + h_static − friction − P_vapor. '
          'NPSHr (required) z pump curve manufacturer. '
          '**NPSHa ≥ NPSHr + 1 m** (lub +20%) — margin bezpieczeństwa. '
          'Niżej = kawitacja: bubbles implode na impeller → erozja, vibracje, hałas (gravel sound), spadek wydajności. '
          'Eccentric reducer flat-top na suction (NIGDY bottom-flat = gas pocket).',
          'NPSH (Net Positive Suction Head) = energy per unit weight of liquid above its vapor pressure. '
          'NPSHa (available) = P_atm + h_static − friction − P_vapor. '
          'NPSHr (required) from pump curve. '
          '**NPSHa ≥ NPSHr + 1 m** (or +20%) — safety margin. '
          'Below = cavitation: bubbles implode on impeller → erosion, vibration, gravel sound, capacity drop. '
          'Eccentric reducer flat-top on suction (NEVER bottom-flat = gas pocket).',
        ),
        tags: ['npsh', 'cavitation', 'kawitacja', 'pump', 'suction'],
      ),
      HelpEntry(
        id: 'water-hammer',
        question: _bi(
          'Co to water hammer i jak zapobiec?',
          'What is water hammer and how to prevent?',
        ),
        answer: _bi(
          'Water hammer = pressure spike gdy moving liquid suddenly decelerates (valve close, pump trip). '
          '**Joukowsky equation: ΔP = ρ × a × ΔV**. ρ wody = 1000, a (wave speed CS pipe) ≈ 1200 m/s, ΔV = 3 m/s → ΔP = 36 bar dodane do operating P! '
          'Mitygacja: slow valve closure (>2L/a), surge tank / accumulator, PRV, anti-cavitation devices. '
          'Velocity limit dla water: <3 m/s w industrial lines.',
          'Water hammer = pressure spike when moving liquid suddenly decelerates (valve close, pump trip). '
          '**Joukowsky equation: ΔP = ρ × a × ΔV**. Water ρ = 1000, CS pipe wave speed a ≈ 1200 m/s, ΔV = 3 m/s → ΔP = 36 bar added to operating! '
          'Mitigation: slow valve closure (>2L/a), surge tank / accumulator, PRV, anti-cavitation devices. '
          'Velocity limit for water: <3 m/s in industrial lines.',
        ),
        tags: ['water-hammer', 'surge', 'joukowsky', 'transient', 'mitigation'],
      ),
    ],
  ),

  // ════════════════════════════════════════════════════════════════════════
  // 13. DEFEKTY I REPAIRS
  // ════════════════════════════════════════════════════════════════════════
  HelpCategory(
    id: 'defects',
    title: _bi('Defekty i naprawy', 'Defects & repairs'),
    subtitle: _bi('Cracks, sleeves, hot tap', 'Cracks, sleeves, hot tap'),
    icon: Icons.dangerous,
    accentArgb: 0xFFFF7043,
    entries: [
      HelpEntry(
        id: 'sleeve-type-a-b',
        question: _bi(
          'Sleeve Type A vs Type B — różnica?',
          'Sleeve Type A vs Type B — difference?',
        ),
        answer: _bi(
          '**Type A** (reinforcement): full-encirclement sleeve z 2 longitudinal welds, NIE welded do pipe. Działa jak "wrapper". Tylko non-through-wall defects (corrosion, dents). PHMSA bulletin 2026: częste failures z moisture intrusion → corrosion under sleeve. '
          '**Type B** (pressure-containing): full encirclement + fillet welded do pipe na obu końcach. Dla through-wall leaks + crack-like defects. Wymaga in-service welding procedure (burn-through risk dla ścianki <4-5 mm). Preferowany w nowoczesnych repairs.',
          '**Type A** (reinforcement): full-encirclement sleeve with 2 longitudinal welds, NOT welded to pipe. Acts as "wrapper". Non-through-wall defects only (corrosion, dents). PHMSA 2026 bulletin: frequent failures from moisture intrusion → corrosion under sleeve. '
          '**Type B** (pressure-containing): full encirclement + fillet welded to pipe at both ends. For through-wall leaks + crack-like defects. Requires in-service welding procedure (burn-through risk for wall <4-5 mm). Preferred in modern repairs.',
        ),
        tags: ['sleeve', 'type-a', 'type-b', 'pipeline-repair', 'phmsa'],
      ),
      HelpEntry(
        id: 'hot-tap',
        question: _bi(
          'Hot tap — kiedy i jak?',
          'Hot tap — when and how?',
        ),
        answer: _bi(
          'Hot tap = wiercenie branch connection na live pipeline bez shutdown. Procedura: weld saddle fitting + valve → drill machine on top → drill coupon out → coupon retracted → valve closed → drilling rig removed → new branch connected. '
          'Limits: pipe wall ≥4 mm (burn-through risk), flow velocity ≥0.4 m/s (heat dissipation), pressure ≤60-80% MAOP, no flammable/explosive atmosphere podczas welding. '
          'Specialty contractors: T.D. Williamson, TEAM, Furmanite.',
          'Hot tap = drilling branch connection on live pipeline without shutdown. Procedure: weld saddle fitting + valve → drill machine on top → drill coupon out → coupon retracted → valve closed → drilling rig removed → new branch connected. '
          'Limits: pipe wall ≥4 mm (burn-through risk), flow velocity ≥0.4 m/s (heat dissipation), pressure ≤60-80% MAOP, no flammable/explosive atmosphere during welding. '
          'Specialty contractors: T.D. Williamson, TEAM, Furmanite.',
        ),
        tags: ['hot-tap', 'in-service', 'pipeline', 'branch-connection'],
      ),
      HelpEntry(
        id: 'pipe-cui',
        question: _bi(
          'Co to CUI (Corrosion Under Insulation)?',
          'What is CUI (Corrosion Under Insulation)?',
        ),
        answer: _bi(
          'CUI = korozja CS pipe pod izolacją gdy woda dostanie się do mineral wool / calsil (rain, washdown, condensation). Najgorsza w zakresie **60-150°C** (rate korozji peak). '
          'Hidden — wykrywa się dopiero przy through-wall leak. Multi-billion problem w refineries. '
          'Mitygacja: pipe coating + paint przed insulation, closed-cell foam jeśli T pozwala, vapor barrier sealed na cold lines, periodic insulation removal + UT inspection co 5-10 lat.',
          'CUI = corrosion of CS pipe under insulation when water enters mineral wool / calsil (rain, washdown, condensation). Worst in **60-150°C** range (peak corrosion rate). '
          'Hidden — only detected at through-wall leak. Multi-billion problem in refineries. '
          'Mitigation: pipe coating + paint before insulation, closed-cell foam if T allows, vapor barrier sealed on cold lines, periodic insulation removal + UT every 5-10 yr.',
        ),
        tags: ['cui', 'corrosion', 'insulation', 'hidden-damage', 'inspection'],
      ),
    ],
  ),
];
