// Wady spoin: przyczyny i naprawa — dane offline (const).
//
// Model: lib/domain/defects/defect_model.dart, wybór przyczyn i wyszukiwarka:
// lib/domain/defects/defect_advice.dart, ekran:
// lib/features/weld_defects/weld_defects_page.dart.
//
// ZASADY
//  • Numery i nazwy PL wg PN-EN ISO 6520-1 — te same co w
//    lib/domain/iso5817/iso5817_table.dart i lib/data/welding_glossary.dart
//    (test pilnuje zgodności dla wspólnych numerów); pozostałe wg tabeli
//    PL/EN/DE/FR wikiweld.pl (tlumaczenia-iso-6520-1-en-de-fr,
//    niezgodnosci-spawalnicze-iso-6520). Tekstu PN-EN ISO 6520-1:2009 nie
//    widziano. Rozbieżności: wikiweld podaje krócej 2017 „Por”, 502 „Nadlew
//    spoiny”, 504 „Wyciek”, 505 „Niewłaściwy brzeg”, 511 „Niezupełne
//    wypełnienie rowka”, 2025 „Otwarte wgłębienie w kraterze” — zostają nazwy
//    z tabeli ISO 5817 w repo (spójność ekranów). 401: tabela ISO 5817 ma
//    „Przyklejenie (brak przetopienia)”, słownik i wikiweld „Przyklejenie
//    (brak wtopienia)” — tu to drugie (przetop to 402).
//  • Każda przyczyna ma źródło ([kDefectSources]). Liczba trafia do tekstu
//    tylko ze źródła i z nazwą źródła w tekście; gdy źródła się różnią —
//    zakres / obie wartości i „wiążąca jest karta spoiwa / WPS”. Bez źródła —
//    opis jakościowy.
//  • Te same liczby w PL i EN (test). Bez emoji.
//  • Kolejność przyczyn: [DefectCause.rank] 1 = najczęstsza / najszybsza do
//    sprawdzenia (np. przeciąg, przepływ gazu), wyżej = rzadsza / wymaga
//    pomiaru lub zmiany technologii.
//
// ŹRÓDŁA — sprawdzone 2026-10-17 (WebSearch / WebFetch). Strony Lincoln
// Electric (prodcd.lincolnelectric.com), ESAB i The Fabricator zwracały 403 —
// z tych wydawców bierzemy tylko dokumenty PDF otwarte z innych serwerów
// (opis przy kluczu). Fakty widziane wyłącznie w wynikach wyszukiwania NIE
// trafiły do danych. Wybrane ustalenia:
//  • Wiatr: AWS D1.1 (7.11.1 w wyd. 2020) — spawanie w osłonie gazu przy
//    wietrze najwyżej 5 mph (8 km/h ≈ 2,2 m/s), inaczej osłona (cytat wtórny
//    [aws-wind]; ta sama liczba w lib/domain/welding/weather_conditions.dart);
//    Kobelco: liczba pęcherzy rośnie gwałtownie powyżej 2 m/s [kobelco-gas].
//    EN 1011-1 / EN 1090-2 — ochrona przed wiatrem bez liczby.
//  • Przepływ MAG: Lincoln C4.200 — zwarciowy, drut 0,8–1,1 mm: 12–17 l/min
//    (25–35 cfh); Kemppi — zwykle 10–20 l/min, mierzyć rotametrem na dyszy;
//    SSAB — reguła: l/min ≈ średnica wewnętrzna dyszy w mm. Tabeli dokładnie
//    dla Ø1,0 mm w l/min nie znaleziono — w tekście zakres i WPS.
//  • Przepływ TIG: Kemppi — WC20 2,4 mm, dysza nr 6/7: 7–8 l/min; Miller —
//    15–20 cfh (≈ 7,1–9,4 l/min); TWI — za duży przepływ = turbulencja.
//  • Post-flow TIG: Miller — 1 s na każde 10 A, min. 8 s.
//  • Wylot drutu: Lincoln C4.200 — zwarciowy 6–13 mm, natryskowy 19–25 mm;
//    Miller — ok. 9,5 mm (3/8"), powyżej 13 mm (1/2") słabsza osłona.
//  • MIG Al: Lincoln C8.100 — 30–100 cfh (≈ 14–47 l/min), technika pchająca
//    5–10°; Hobart — materiał do strefy spawania 24 h wcześniej.
//  • SAW: Hobart HA-495 — suszenie 300–350 °C min. 2 h, przechowywanie
//    150 ± 25 °C (inne topniki — inne wartości, np. Oerlikon: topione 250 °C).
//  • Pęknięcia: TWI JK 46 — podgrzanie min. 75 mm od złącza, utrzymanie
//    2–3 h, przypadki wrażliwe 250–300 °C przez 3–4 h; TWI FAQ — czas przed
//    NDT: EN 1011-2 zwykle min. 16 h, AWS D1.1 48 h tylko dla A514 / A517 /
//    A709 Gr 100; TWI JK 44 — głębokość / szerokość ściegu 0,5–2, S + P
//    ≤ 0,06 % (C-Mn), ferryt ok. 5–10 % w stopiwie austenitycznym.
//  • Naprawa: TWI JK 40 / 41 / 12; 49 CFR 192.245 (rurociągi): naprawa
//    pęknięcia lub miejsca już naprawianego wg pisemnej procedury, pęknięcie
//    > 8 % długości spoiny — wycięcie; API 1104 (streszczenie open-exam-prep):
//    pęknięcie naprawia się raz; limit 2 napraw w jednym miejscu — przepisy
//    towarzystw klasyfikacyjnych (Welding Journal 1989, streszczenie TRID).
//    Ogólnego limitu „normowego” NIE podajemy — wiąże specyfikacja.
// NIEPEWNE / POMINIĘTE: kształt rowka naprawczego w liczbach (brak źródła
// normowego), „+ 50 mm za końcem pęknięcia” z AWS D1.1 (tylko forum),
// limit napraw w ASME / AWS, tabela czasów oczekiwania w EN ISO 17635.

import '../domain/defects/defect_model.dart';

// ── Źródła ──────────────────────────────────────────────────────────────────

const Map<String, DefectSource> kDefectSources = {
  // TWI Job Knowledge / FAQ
  'twi-porosity': DefectSource('TWI',
      'TWI Job Knowledge 42: Defects/imperfections in welds — porosity',
      'https://www.twi-global.com/technical-knowledge/job-knowledge/defects-imperfections-in-welds-porosity-042'),
  'twi-al-porosity': DefectSource('TWI',
      'TWI Job Knowledge: Avoiding porosity when welding aluminium',
      'https://www.twi-global.com/technical-knowledge/job-knowledge/Avoiding-Porosity-When-Welding-Aluminium'),
  'twi-al-porosity-faq': DefectSource('TWI',
      'TWI FAQ: I keep getting porosity when welding aluminium',
      'https://www.twi-global.com/technical-knowledge/faqs/faq-i-keep-getting-porosity-when-welding-aluminium-any-advice'),
  'twi-lof': DefectSource('TWI',
      'TWI Job Knowledge 41: Lack of sidewall and inter-run fusion',
      'https://www.twi-global.com/technical-knowledge/job-knowledge/weld-defects-imperfections-in-welds-lack-of-sidewall-and-inter-run-fusion-041'),
  'twi-lof-faq': DefectSource('TWI',
      'TWI FAQ: How can lack of fusion defects be prevented?',
      'https://www.twi-global.com/technical-knowledge/faqs/faq-how-can-lack-of-fusion-defects-be-prevented'),
  'twi-root': DefectSource('TWI',
      'TWI Job Knowledge 40: Incomplete root fusion or penetration',
      'https://www.twi-global.com/technical-knowledge/job-knowledge/weld-defects-imperfections-incomplete-root-fusion-or-penetration-040'),
  'twi-shape1': DefectSource('TWI',
      'TWI Job Knowledge 67: Geometric shape imperfections — part 1',
      'https://www.twi-global.com/technical-knowledge/job-knowledge/a-general-review-of-geometric-shape-imperfections-types-and-causes-part-1-067'),
  'twi-shape2': DefectSource('TWI',
      'TWI Job Knowledge 68: Shape imperfections — part 2',
      'https://www.twi-global.com/technical-knowledge/job-knowledge/a-general-review-of-the-causes-and-acceptance-of-shape-imperfections-part-2-068'),
  'twi-spatter': DefectSource('TWI', 'TWI FAQ: What is weld spatter?',
      'https://www.twi-global.com/technical-knowledge/faqs/what-is-weld-spatter'),
  'twi-slag': DefectSource('TWI',
      'TWI Job Knowledge 43: Slag inclusions',
      'https://www.twi-global.com/technical-knowledge/job-knowledge/defects-imperfections-in-welds-slag-inclusions-043'),
  'twi-slag-faq': DefectSource('TWI', 'TWI FAQ: What is slag in welding?',
      'https://www.twi-global.com/technical-knowledge/faqs/what-is-slag-in-welding'),
  'twi-solidification': DefectSource('TWI',
      'TWI Job Knowledge 44: Solidification cracking',
      'https://www.twi-global.com/technical-knowledge/job-knowledge/defects-solidification-cracking-044'),
  'twi-saw-cracking': DefectSource('TWI',
      'TWI FAQ: Minimising solidification cracking in SAW welds',
      'https://www.twi-global.com/technical-knowledge/faqs/faq-how-can-i-minimise-the-risk-of-solidification-cracking-in-submerged-arc-saw-welds'),
  'twi-saw-porosity': DefectSource('TWI',
      'TWI FAQ: Common causes of porosity in SA welds',
      'https://www.twi-global.com/technical-knowledge/faqs/faq-what-are-the-common-causes-of-porosity-in-sa-submerged-arc-welds'),
  'twi-saw-flux': DefectSource('TWI',
      'TWI FAQ: How much flux burden is required for SA welding?',
      'https://www.twi-global.com/technical-knowledge/faqs/faq-how-much-flux-burden-is-required-for-sa-submerged-arc-welding'),
  'twi-arc-blow': DefectSource('TWI', 'TWI FAQ: How do you prevent arc blow?',
      'https://www.twi-global.com/technical-knowledge/faqs/faq-how-do-you-prevent-arc-blow'),
  'twi-consumables': DefectSource('TWI',
      'TWI Job Knowledge 83: Welding consumables — part 2',
      'https://www.twi-global.com/technical-knowledge/job-knowledge/welding-consumables-part-2-083'),
  'twi-tig-equipment': DefectSource('TWI',
      'TWI Job Knowledge 17: Equipment for TIG welding',
      'https://www.twi-global.com/technical-knowledge/job-knowledge/equipment-for-tungsten-inert-gas-tig-gta-welding-017'),
  'twi-heat-tint': DefectSource('TWI',
      'TWI FAQ: What is heat tint and how do I avoid it (stainless)?',
      'https://www.twi-global.com/technical-knowledge/faqs/faq-what-is-heat-tint-and-how-do-i-avoid-it-during-welding-of-stainless-steels'),
  'twi-pickling': DefectSource('TWI',
      'TWI FAQ: Can pickling of stainless steel welds be replaced?',
      'https://www.twi-global.com/technical-knowledge/faqs/faq-can-pickling-of-stainless-steel-welds-be-replaced-by-other-cleaning-methods'),
  'twi-crater': DefectSource('TWI', 'TWI FAQ: What causes crater pipes?',
      'https://www.twi-global.com/technical-knowledge/faqs/faq-what-causes-crater-pipes-and-what-will-prevent-their-formation-during-welding'),
  'twi-hydrogen': DefectSource('TWI',
      'TWI Job Knowledge 46: Hydrogen cracks in steels — prevention',
      'https://www.twi-global.com/technical-knowledge/job-knowledge/defects-hydrogen-cracks-in-steels-prevention-and-best-practice-046'),
  'twi-ndt-delay': DefectSource('TWI',
      'TWI FAQ: Which standards stipulate delay time before inspecting welds?',
      'https://www.twi-global.com/technical-knowledge/faqs/faq-which-standards-stipulate-delay-time-before-inspecting-welds'),
  'twi-gouging': DefectSource('TWI',
      'TWI Job Knowledge 12: Air carbon arc gouging',
      'https://www.twi-global.com/technical-knowledge/job-knowledge/air-carbon-arc-gouging-012'),
  // Producenci
  'miller-defects': DefectSource('Miller', 'Miller: Troubleshooting weld defects',
      'https://www.millerwelds.com/resources/article-library/troubleshooting-weld-defects'),
  'miller-mig-basics': DefectSource('Miller',
      'Miller: Understanding the basics of MIG welding for mild steel',
      'https://www.millerwelds.com/resources/article-library/understanding-the-basics-of-mig-welding-for-mild-steel'),
  'miller-stickout': DefectSource('Miller',
      'Miller: Stickout, electrode extension and contact tip to work distance',
      'https://www.millerwelds.com/resources/article-library/what-are-stickout-electrode-extension-and-contact-tip-to-work-distance'),
  'miller-tig-problems': DefectSource('Miller', 'Miller: Common TIG welding problems',
      'https://www.millerwelds.com/en-us/resources/knowledge-hub/tig-welding/how-to/common-tig-weld-problems'),
  'miller-tig-gas': DefectSource('Miller',
      'Miller: Best practices for proper shielding gas in TIG welding',
      'https://www.millerwelds.com/en-us/resources/knowledge-hub/tig-welding/how-to/best-practices-for-proper-shielding-gas-in-tig-welding'),
  'miller-tig-basics': DefectSource('Miller', 'Miller: Guide to TIG welding basics',
      'https://www.millerwelds.com/en-us/resources/knowledge-hub/tig-welding/how-to/guide-to-tig-welding-basics'),
  // Lincoln C4.200 — kopia PDF na serwerze uczelni (oryginał 403).
  'lincoln-mig': DefectSource('Lincoln',
      'Lincoln Electric C4.200: GMAW (MIG/MAG) Welding Guide',
      'https://referenciaict.uo.edu.cu/sites/default/files/Guia%20de%20soldadura%20MIG-MAG.pdf'),
  // Lincoln C8.100 — kopia PDF u dystrybutora (oryginał 403).
  'lincoln-al': DefectSource('Lincoln',
      'Lincoln Electric C8.100: Aluminum GMAW Welding Guide',
      'https://bester.rapidwelding.com/files/Lincoln%20Aluminium%20Welding%20Guidebook.pdf'),
  // Lincoln Innershield Welding Guide — kopia PDF (oryginał 403).
  'lincoln-innershield': DefectSource('Lincoln',
      'Lincoln Electric: Innershield Welding Guide',
      'https://images.homedepot-static.com/catalog/pdfImages/95/95760b62-43a2-4903-9e6f-066e31ff67cb.pdf'),
  'lincoln-71a85': DefectSource('Lincoln',
      'Lincoln Electric C3.12.6: UltraCore 71A85 data sheet',
      'https://ch-delivery.lincolnelectric.com/api/public/content/bccbb0275c274b939093bd89ddb193f5'),
  'lincoln-gouging': DefectSource('Lincoln',
      'Lincoln Electric SUG004: Air carbon arc gouging — safe use guide',
      'https://ch-delivery.lincolnelectric.com/api/public/content/4aa60a4804894b3e93cd65c67f7441e3'),
  'hobart-stick': DefectSource('Hobart',
      'Hobart: Basic stick welding — electrode technique',
      'https://www.hobartbrothers.com/resources/technical-guides/helpful-hints-basic-welding/basic-stick-welding-electrode-technique/'),
  'hobart-fcaw-s': DefectSource('Hobart',
      'Hobart: Troubleshooting common self-shielded FCAW problems',
      'https://www.hobartbrothers.com/resources/technical-articles/troubleshooting-common-self-shielded-fcaw-problems/'),
  'hobart-al': DefectSource('Hobart', 'Hobart: Guide for aluminum welding',
      'https://www.hobartbrothers.com/downloads/Aluminum_Welding_Guide.pdf'),
  'hobart-al-cracking': DefectSource('Hobart',
      'Hobart: How to avoid cracking in aluminum alloys',
      'https://www.hobartbrothers.com/resources/technical-guides/aluminum-welding-guide/problem-solving-how-to-avoid-cracking-in-aluminum-alloys/'),
  'hobart-transfer': DefectSource('Hobart',
      'Hobart / Welding Journal 08/2021: Selecting the right transfer mode',
      'https://www.hobartbrothers.com/wp-content/uploads/2021/08/Welding-Journal_August-2021.pdf'),
  'hobart-ha495': DefectSource('Hobart', 'Hobart HA-495 SAW flux data sheet',
      'https://www.hobartbrothers.com/wp-content/uploads/hobart-catalog/pdf/datasheets/HA-495.pdf'),
  'bernard-gmaw': DefectSource('Tregaskiss', 'Bernard: The causes of GMAW flaws',
      'https://bernardtregaskiss.com/the-causes-of-gmaw-flaws'),
  'tregaskiss-guide': DefectSource('Tregaskiss',
      'Bernard / Tregaskiss: MIG troubleshooting guide',
      'https://bernardtregaskiss.com/wp-content/uploads/2020/07/troubleshooting_guide.pdf'),
  'kemppi-gas': DefectSource('Kemppi', 'Kemppi: Shielding gas setting',
      'https://userdoc.kemppi.com/om/x8-supersnake/en/content/topics/b_installation/shielding%20gas%20setting.htm'),
  'kemppi-tig': DefectSource('Kemppi', 'Kemppi MasterTig: TIG guide tables',
      'https://userdoc.kemppi.com/om/mastertig/en/content/topics/e_technical-data-and-ordering/tig-guide-tables.htm'),
  'fronius-tig': DefectSource('Fronius', 'Fronius TransTig 170/210: manual',
      'https://manuals.fronius.com/html/4204260308/en-US.html'),
  'fronius-hf': DefectSource('Fronius', 'Fronius: TIG welding — HF ignition',
      'https://blog.fronius.com/welding/en/know-how/tig-welding-hf-ignition/'),
  'kobelco-gas': DefectSource('Kobelco',
      'Kobelco: Fundamentals of shielding gas (wind and porosity)',
      'https://www.kobelco-welding.jp/education-center/Fundamentals/Fundamentals04.html'),
  'kobelco-start': DefectSource('Kobelco',
      'Kobelco: The ABC\'s of arc welding — start porosity',
      'https://www.kobelco-welding.jp/education-center/abc/ABC_2004-04.html'),
  'ssab-gas': DefectSource('SSAB', 'SSAB: MAG and TIG welding of Hardox — gas',
      'https://www.ssab.com/en/support/how-to-process/how-to-weld/shielding-gas/12-mag-and-tig-welding-of-hardox'),
  // CK Worldwide Form 116 — kopia PDF u dystrybutora.
  'ck-tig': DefectSource('CK Worldwide',
      'CK Worldwide Form 116: TIG welding troubleshooting guide',
      'https://www.bester.rapidwelding.com/files/TIG%20Welding%20Troubleshooting%20Guide.pdf'),
  'dgp-tungsten': DefectSource('Diamond Ground',
      'Diamond Ground Products: Winning preparation (tungsten)',
      'https://diamondground.com/WinningPreparation.pdf'),
  'hft-purge': DefectSource('HFT', 'Huntingdon Fusion Techniques: weld purging',
      'https://huntingdonfusion.com/?p=4448'),
  'oerlikon-storage': DefectSource('Oerlikon',
      'Oerlikon: Storage and redrying of welding consumables',
      'https://www.magmaweld.com.tr/Content/UserFiles/OerlikonKutuphanesi/Kaynak_malzemelerinin_depolanmasi_ve_kurutulmasi_ingilizce.pdf'),
  'twi-fillet': DefectSource('TWI',
      'TWI Job Knowledge 66: Fillet welded joints — practicalities',
      'https://www.twi-global.com/technical-knowledge/job-knowledge/fillet-welded-joints-a-review-of-the-practicalities-066'),
  'twi-al-faq': DefectSource('TWI', 'TWI FAQ: Aluminium welding',
      'https://www.twi-global.com/technical-knowledge/faqs/aluminium-welding'),
  'weldaus-shape': DefectSource('Weld Australia',
      'Weld Australia: Weld imperfections that lead to poor geometric shape',
      'https://welding.org.au/knowledge/weld-imperfections-that-lead-to-poor-geometric-shape/'),
  'kemppi-defects': DefectSource('Kemppi',
      'Kemppi: Understanding and preventing common welding defects (2024)',
      'https://kemppi.com/fr/blogs/understanding-and-preventing-common-welding-defects'),
  'kemppi-mig-defects': DefectSource('Kemppi',
      'Kemppi: How to avoid the most common MIG/MAG welding defects (2021)',
      'https://kemppi.com/it/blogs/how-to-avoid-the-most-common-mig-mag-welding-defects'),
  'miller-auto': DefectSource('Miller',
      'Miller: MIG basics for automotive welding repair (positions)',
      'https://www.millerwelds.com/en-US/resources/knowledge-hub/mig-welding/how-to/mig-basics-for-automotive-welding-repair'),
  'miller-fcaw': DefectSource('Miller',
      'Miller: Flux-cored welding — the basics for mild steel',
      'https://www.millerwelds.com/en-US/resources/knowledge-hub/welding-basics/flux-cored-welding-the-basics-for-mild-steel'),
  'miller-stick': DefectSource('Miller',
      'Miller: Five steps to improving your stick welding technique',
      'https://www.millerwelds.com/en-US/resources/knowledge-hub/stick-welding/five-steps-to-improving-your-stick-welding-technique'),
  'miller-al-clean': DefectSource('Miller',
      'Miller: Cleaning and preparing aluminum filler and base metals',
      'https://www.millerwelds.com/resources/article-library/what-you-need-to-know-about-cleaning-and-preparing-aluminum-filler-and-base-metals-before-welding'),
  // Strona Hobart (serwer wydawcy, adres roboczy) o wyspach krzemianowych.
  'hobart-silicon': DefectSource('Hobart',
      'Hobart: Silicon islands in MIG welds — causes and control',
      'https://hobartstaging.wpengine.com/?p=3239'),
  'fronius-lsc': DefectSource('Fronius', 'Fronius: LSC (Low Spatter Control)',
      'https://www.fronius.com/pl-pl/poland/spawalnictwo/swiat-spawalnictwa/fronius-welding-processes/lsc'),
  'hft-root': DefectSource('HFT',
      'Huntingdon Fusion Techniques: purge flow and root concavity',
      'https://huntingdonfusion.com/?p=5397'),
  'unimig-burn': DefectSource('UNIMIG',
      'UNIMIG: Welding burn-through — causes and prevention',
      'https://unimig.com.au/blog/welding-burn-through-what-is-it-what-causes-it-and-how-to-prevent-it/'),
  'patent-6oclock': DefectSource('US 5304776',
      'US patent 5304776: root concavity at the 6 o\'clock position of pipe',
      'https://patents.google.com/patent/US5304776'),
  // Normy / przepisy w cytatach wtórnych, BHP
  'wermac-wall': DefectSource('ASME B31.8',
      'Wermac: Unequal wall thickness — ASME B31.8 taper (secondary)',
      'https://www.wermac.org/documents/unequal_wallthickness.html'),
  'api-1104-alignment': DefectSource('API 1104',
      'API 1104 alignment and clamps (study guide summary)',
      'https://open-exam-prep.com/study-guides/api-1169/coating-lowering-tieins/tie-ins-alignment-oq'),
  'aws-wind': DefectSource('AWS D1.1',
      'AWS D1.1 wind limit for gas-shielded processes (secondary quote)',
      'https://materialwelding.com/maximum-wind-velocity-in-welding-area/'),
  'cfr-192-245': DefectSource('49 CFR 192.245',
      '49 CFR 192.245: Repair or removal of defects (pipelines)',
      'https://www.law.cornell.edu/cfr/text/49/192.245'),
  'api-1104': DefectSource('API 1104',
      'API 1104:2021 crack acceptance and repair (study guide summary)',
      'https://open-exam-prep.com/study-guides/aws-cwi-endorsement-api-1104/acceptance-standards/cracks-and-aoi'),
  'class-repairs': DefectSource('Welding Journal',
      'Lai, Fong: weld repairs, Welding Journal vol. 68 (1989), TRID abstract',
      'https://trid.trb.org/View/434079'),
  'epri-asme3': DefectSource('ASME III',
      'EPRI (2010): ASME III NB-4450 repair of weld metal defects',
      'https://www.nrc.gov/docs/ML1012/ML101230137.pdf'),
  'arc-strike': DefectSource('Project Materials',
      'Project Materials: What is an arc strike?',
      'https://blog.projectmaterials.com/quick-answers/materials/what-is-arc-strike/'),
  'hse-argon': DefectSource('HSE', 'HSE: Asphyxiation hazards in welding',
      'https://www.hse.gov.uk/Welding/asphyxiation-hazards.htm'),
  'hse-pickling': DefectSource('HSE', 'HSE: Post-weld cleaning (pickling)',
      'https://www.hse.gov.uk/Welding/post-weld-cleaning.htm'),
  'magnaflux-sds': DefectSource('Magnaflux',
      'Magnaflux SKL-SP2 penetrant aerosol — safety data sheet',
      'https://assets.testequity.com/te1/Documents/pdf/magnaflux/Magnaflux_SKL-SP2-Aerosol_Safety-Data-Sheet_0826.pdf'),
};

// ── Skróty ──────────────────────────────────────────────────────────────────

const _mma = DefectProcess.mma111;
const _mag = DefectProcess.mag135;
const _fcg = DefectProcess.fcaw136;
const _fcs = DefectProcess.fcaw114;
const _tig = DefectProcess.tig141;
const _saw = DefectProcess.saw121;
const _mig = DefectProcess.mig131;

const _cs = DefectMaterial.carbon;
const _ss = DefectMaterial.stainless;
const _al = DefectMaterial.aluminium;

const _all = {_mma, _mag, _fcg, _fcs, _tig, _saw, _mig};
const _hand = {_mma, _mag, _fcg, _fcs, _tig, _mig};
const _wire = {_mag, _fcg, _fcs, _mig};
const _gasWire = {_mag, _fcg, _mig};
const _bottleGas = {_mag, _fcg, _tig, _mig};
const _slagging = {_mma, _fcg, _fcs, _saw};
const _dc = {_mma, _mag, _fcg, _fcs, _tig, _saw};

// ── Wspólne kroki naprawy i BHP ─────────────────────────────────────────────

const _rCauseFirst = DefectStep(
  'cause-first',
  Tx('Najpierw usuń przyczynę z listy powyżej — inaczej wada wróci w naprawie.',
      'First remove the cause from the list above — otherwise the defect '
          'returns in the repair.'),
);

const _rMark = DefectStep(
  'mark',
  Tx('Oznacz wadę i jej zasięg (długość, głębokość), zapisz numer spoiny.',
      'Mark the defect and its extent (length, depth), note the weld number.'),
);

const _rRemove = DefectStep(
  'remove',
  Tx('Usuń wadę szlifowaniem albo żłobieniem do zdrowego metalu (TWI).',
      'Remove the defect by grinding or gouging down to sound metal (TWI).'),
);

const _rGouge = DefectStep(
  'gouge',
  Tx('Po żłobieniu łukowo-powietrznym zeszlifuj ścianki — zostaje warstwa '
          'nawęglona (twarda, skłonna do pęknięć); w stalach o podwyższonej '
          'wytrzymałości szlifuj zawsze (TWI).',
      'After air carbon arc gouging grind the walls — a carburised layer '
          'remains (hard, crack-prone); in higher-strength steels always '
          'grind (TWI).'),
  processes: _dc,
);

const _rConfirm = DefectStep(
  'confirm',
  Tx('Potwierdź usunięcie wady badaniem PT (stal węglowa także MT) wycięcia — '
          'np. ASME III wymaga PT wycięcia przed spawaniem.',
      'Confirm the defect is gone with PT (carbon steel also MT) of the '
          'excavation — e.g. ASME III requires PT of the excavation before '
          'welding.'),
);

const _rGroove = DefectStep(
  'groove',
  Tx('Nadaj wycięciu kształt rowka do spawania: łagodnie wyprowadzone końce i '
          'ścianki, dostęp dla elektrody / palnika; wymiary wg procedury '
          'naprawy.',
      'Shape the excavation into a weldable groove: gently sloped ends and '
          'walls, access for the electrode / torch; dimensions per the repair '
          'procedure.'),
);

const _rPreheat = DefectStep(
  'preheat',
  Tx('Podgrzej i pilnuj temperatury międzyściegowej jak w WPS / procedurze '
          'naprawy.',
      'Preheat and keep the interpass temperature as in the WPS / repair '
          'procedure.'),
);

const _rWeld = DefectStep(
  'weld',
  Tx('Spawaj wg zakwalifikowanej procedury (zwykle tej samej co spoina '
          'pierwotna — TWI). Naprawa pęknięcia lub miejsca już naprawianego — '
          'wg pisemnej procedury (np. 49 CFR 192.245).',
      'Weld to a qualified procedure (usually the original one — TWI). Repair '
          'of a crack or of an already repaired spot — to a written procedure '
          '(e.g. 49 CFR 192.245).'),
);

const _rNdt = DefectStep(
  'ndt',
  Tx('Zbadaj naprawę ponownie wg specyfikacji (Dziennik spoin zakłada te same '
          'metody co dla spoiny pierwotnej).',
      'Re-examine the repair per the specification (the Weld journal assumes '
          'the same methods as for the original weld).'),
);

const _rNdtDelay = DefectStep(
  'ndt-delay',
  Tx('Stal podatna na pęknięcia wodorowe: odczekaj przed badaniem końcowym — '
          'EN 1011-2 zwykle min. 16 h; AWS D1.1 48 h dla A514 / A517 / A709 '
          'Gr 100 (TWI); wiąże specyfikacja.',
      'Steel prone to hydrogen cracking: wait before the final examination — '
          'EN 1011-2 usually at least 16 h; AWS D1.1 48 h for A514 / A517 / '
          'A709 Gr 100 (TWI); the specification governs.'),
  materials: {_cs},
);

const _rLimit = DefectStep(
  'limit',
  Tx('Licz naprawy w tym samym miejscu — limit podaje specyfikacja (np. '
          'przepisy towarzystw klasyfikacyjnych: najwyżej 2; API 1104: '
          'pęknięcie naprawia się tylko raz).',
      'Count repairs in the same spot — the specification sets the limit '
          '(e.g. classification society rules: at most 2; API 1104: a crack '
          'may be repaired only once).'),
);

const _rGrindSmooth = DefectStep(
  'grind-smooth',
  Tx('Płytką wadę kształtu zeszlifuj z łagodnym przejściem w materiał, bez '
          'zejścia poniżej grubości minimalnej (TWI).',
      'Grind a shallow shape defect to a smooth transition into the parent '
          'metal without going below the minimum thickness (TWI).'),
);

const _rAddRun = DefectStep(
  'add-run',
  Tx('Za płytko / za mało stopiwa: oczyść i dołóż ścieg wg WPS (TWI).',
      'Too shallow / too little metal: clean and add a run per the WPS (TWI).'),
);

const _sGrind = Tx(
  'Szlifowanie: okulary lub przyłbica, osłona tarczy, ochrona słuchu; '
      'tarcza i szczotka przeznaczone do danego materiału.',
  'Grinding: goggles or face shield, wheel guard, hearing protection; a '
      'wheel and brush meant for that material.',
);

const _sGouge = Tx(
  'Żłobienie łukowo-powietrzne: hałas 108–120 dB(A) — ochrona słuchu także '
      'dla osób obok; dymy z miedzią (przy stalach z Cr także Cr(VI)) — '
      'odciąg lub maska; odpryski lecą daleko — usuń palne materiały, dozór '
      'pożarowy w trakcie i po pracy (Lincoln SUG004).',
  'Air carbon arc gouging: noise 108–120 dB(A) — hearing protection also for '
      'people nearby; fumes with copper (with Cr steels also Cr(VI)) — '
      'extraction or respirator; molten metal is thrown far — remove '
      'combustibles, fire watch during and after work (Lincoln SUG004).',
);

const _sPt = Tx(
  'Penetrant i zmywacz to łatwopalne aerozole — z dala od łuku i gorących '
      'elementów, z wentylacją, zwłaszcza w ciasnych miejscach (karta '
      'charakterystyki).',
  'Penetrant and cleaner are flammable aerosols — away from the arc and hot '
      'parts, with ventilation, especially in tight spaces (safety data '
      'sheet).',
);

const _sArgon = Tx(
  'Argon / gaz formujący w rurze, zbiorniku lub wykopie wypiera tlen — utrata '
      'przytomności w kilka sekund bez ostrzeżenia; mierz O₂ z zewnątrz, nie '
      'wchodź, nie „poprawiaj” atmosfery tlenem (HSE).',
  'Argon / purge gas in a pipe, vessel or trench displaces oxygen — loss of '
      'consciousness within seconds without warning; measure O₂ from outside, '
      'do not enter, never “improve” the air with oxygen (HSE).',
);

const _sPreheat = Tx(
  'Podgrzewanie palnikiem: rękawice, kontrola temperatury termokredką / '
      'termometrem, palnik pod nadzorem; prace pożarowo niebezpieczne wg '
      'zezwolenia.',
  'Torch preheating: gloves, check the temperature with a crayon / '
      'thermometer, never leave the torch unattended; hot work per the '
      'permit.',
);

const _sPickling = Tx(
  'Pasta trawiąca zawiera kwas azotowy i fluorowodorowy (ok. 20 % HNO₃, 5 % '
      'HF) — rękawice kwasoodporne, okulary, odzież; ból po kontakcie z HF może '
      'pojawić się dopiero po 24 h — przy kontakcie od razu pomoc medyczna '
      '(HSE).',
  'Pickling paste contains nitric and hydrofluoric acid (approx. 20 % HNO₃, '
      '5 % HF) — acid-resistant gloves, goggles, clothing; pain after HF '
      'contact may appear only after 24 h — get medical help at once after '
      'contact (HSE).',
);

const List<String> _repairSourcesStandard = [
  'twi-root',
  'twi-lof',
  'twi-gouging',
  'epri-asme3',
  'cfr-192-245',
  'twi-ndt-delay',
  'class-repairs',
  'api-1104',
  'lincoln-gouging',
  'magnaflux-sds',
];

const List<Tx> _safetyStandard = [_sGrind, _sGouge, _sPt, _sPreheat];

// ── Wady ────────────────────────────────────────────────────────────────────

const _cutCrack = Tx(
  'Pęknięcie wraca po naprawie albo limit napraw ze specyfikacji jest '
      'wyczerpany — wycięcie złącza. API 1104: nieudana naprawa pęknięcia = '
      'wycięcie; rurociągi wg 49 CFR 192.245: pęknięcie dłuższe niż 8 % '
      'długości spoiny = wycięcie.',
  'The crack returns after repair or the repair limit in the specification '
      'is used up — cut the joint out. API 1104: a failed crack repair = cut '
      'out; pipelines per 49 CFR 192.245: a crack longer than 8 % of the weld '
      'length = cut out.',
);

const _rCrackBeyond = DefectStep(
  'crack-beyond',
  Tx('Pęknięcie usuwaj na całej długości i za jego widoczne końce — ile, mówi '
          'procedura naprawy; usunięcie potwierdź PT / MT.',
      'Remove the crack over its full length and beyond its visible ends — '
          'how far is set by the repair procedure; confirm removal by PT / '
          'MT.'),
);

// ── 1xx Pęknięcia ───────────────────────────────────────────────────────────

const _crackCold = WeldDefect(
  id: 'crack_cold',
  group: DefectGroup.cracks,
  refs: [
    Iso6520Ref(100, 'Pęknięcie', 'Crack'),
    Iso6520Ref(101, 'Pęknięcie podłużne', 'Longitudinal crack'),
    Iso6520Ref(102, 'Pęknięcie poprzeczne', 'Transverse crack'),
  ],
  title: Tx('Pęknięcie zimne (wodorowe)', 'Cold (hydrogen) crack'),
  looks: Tx(
    'Pęknięcie w strefie wpływu ciepła lub w spoinie, często pojawia się '
        'dopiero po godzinach od spawania (opóźnione). Powstaje, gdy naraz '
        'występują wodór, twarda struktura i naprężenia (TWI).',
    'A crack in the heat-affected zone or in the weld, often appearing hours '
        'after welding (delayed). It forms when hydrogen, a hard '
        'microstructure and stress occur together (TWI).',
  ),
  processes: _dc,
  materials: {_cs},
  keywords: [
    'wodorowe',
    'opoznione',
    'zimne',
    'swc',
    'hydrogen',
    'cold cracking',
    'delayed',
    'haz',
  ],
  causes: [
    DefectCause(
      id: 'cold-preheat',
      processes: _dc,
      rank: 1,
      cause: Tx('Brak lub za niskie podgrzewanie i temperatura międzyściegowa',
          'No or too low preheat and interpass temperature'),
      check: Tx(
          'Temperatura z WPS zmierzona termokredką / termometrem po obu '
              'stronach rowka, w strefie min. 75 mm od złącza (TWI)? Mróz '
              'albo wilgotny materiał?',
          'WPS temperature measured with a crayon / thermometer on both sides '
              'of the groove, within at least 75 mm of the joint (TWI)? Frost '
              'or damp material?'),
      fix: Tx(
          'Podgrzej wg WPS / EN 1011-2 (grube stale o wysokim CE — nawet do '
              '200 °C, TWI) i utrzymuj temperaturę do końca spawania; warunki '
              'otoczenia — moduł „Warunki do spawania”.',
          'Preheat per the WPS / EN 1011-2 (thick high-CE steels — even up to '
              '200 °C, TWI) and hold it until welding is finished; ambient '
              'conditions — the “Welding conditions” tool.'),
      sources: ['twi-hydrogen'],
    ),
    DefectCause(
      id: 'cold-wet-consumable',
      processes: _slagging,
      rank: 2,
      cause: Tx(
          'Wodór ze spoiwa: zawilgocone elektrody zasadowe, drut proszkowy '
              'albo topnik',
          'Hydrogen from consumables: damp basic electrodes, flux-cored wire '
              'or flux'),
      check: Tx(
          'Elektrody z piecyka i w limicie czasu na powietrzu? Topnik '
              'suszony? Klasa wodoru spoiwa (np. H5, H10) zgodna z WPS?',
          'Electrodes from the oven and within the exposure limit? Flux '
              'dried? Consumable hydrogen class (e.g. H5, H10) as in the WPS?'),
      fix: Tx(
          'Spoiwa niskowodorowe, suszenie elektrod i topników wg producenta '
              '(TWI); czas na powietrzu — moduł „Elektrody zasadowe: czas i '
              'suszenie”.',
          'Low-hydrogen consumables, electrodes and fluxes dried per the '
              'manufacturer (TWI); exposure time — the “Low-hydrogen '
              'electrodes: exposure” tool.'),
      sources: ['twi-hydrogen', 'oerlikon-storage'],
    ),
    DefectCause(
      id: 'cold-surface',
      processes: _dc,
      rank: 2,
      cause: Tx('Wilgoć, rdza, olej lub farba na rowku (źródło wodoru)',
          'Moisture, rust, oil or paint on the groove (a hydrogen source)'),
      check: Tx('Rowek suchy i czysty do metalu? Rosa lub szron rano?',
          'Groove dry and clean to bright metal? Dew or frost in the '
              'morning?'),
      fix: Tx('Oczyść, odtłuść i osusz podgrzaniem przed spawaniem.',
          'Clean, degrease and dry by preheating before welding.'),
      sources: ['twi-hydrogen', 'twi-porosity'],
    ),
    DefectCause(
      id: 'cold-post-heat',
      processes: _dc,
      rank: 3,
      cause: Tx(
          'Złącze wystygło od razu po spawaniu — wodór nie zdążył wyjść',
          'The joint cooled straight after welding — hydrogen had no time to '
              'escape'),
      check: Tx(
          'Czy WPS wymaga utrzymania temperatury / dogrzania po spawaniu '
              '(post-heat)?',
          'Does the WPS require holding the temperature / post-heating after '
              'welding?'),
      fix: Tx(
          'TWI: utrzymanie podgrzania typowo 2–3 h po spawaniu, w przypadkach '
              'wrażliwych typowo 250–300 °C przez 3–4 h — tylko gdy przewiduje '
              'to WPS.',
          'TWI: hold the preheat typically 2–3 h after welding, in sensitive '
              'cases typically 250–300 °C for 3–4 h — only when the WPS calls '
              'for it.'),
      sources: ['twi-hydrogen'],
    ),
    DefectCause(
      id: 'cold-restraint',
      processes: _dc,
      rank: 4,
      cause: Tx(
          'Duże utwierdzenie i naprężenia (sztywny węzeł, zła kolejność '
              'ściegów)',
          'High restraint and stress (rigid joint, wrong run sequence)'),
      check: Tx('Pęknięcie w grani lub pierwszym ściegu sztywnego złącza?',
          'A crack in the root or first run of a rigid joint?'),
      fix: Tx(
          'Kolejność i układ ściegów wg WPS; przy dużym utwierdzeniu zgłoś '
              'technologowi — może być potrzebne wyższe podgrzanie (TWI).',
          'Run sequence and layout per the WPS; with high restraint tell the '
              'welding engineer — higher preheat may be needed (TWI).'),
      sources: ['twi-hydrogen'],
    ),
  ],
  repair: [
    _rCauseFirst,
    _rMark,
    _rCrackBeyond,
    _rRemove,
    _rGouge,
    _rConfirm,
    _rGroove,
    _rPreheat,
    _rWeld,
    _rNdt,
    _rNdtDelay,
    _rLimit,
  ],
  cutOut: _cutCrack,
  safety: _safetyStandard,
  checklist: [
    DefectStep(
      'preheat-measured',
      Tx('Temperatura podgrzania zmierzona po obu stronach rowka',
          'Preheat temperature measured on both sides of the groove'),
    ),
    DefectStep(
      'consumable-dry',
      Tx('Elektrody / drut / topnik suche, w limicie czasu',
          'Electrodes / wire / flux dry, within the time limit'),
      processes: _slagging,
    ),
    DefectStep(
      'groove-dry',
      Tx('Rowek suchy, bez rdzy, oleju i farby',
          'Groove dry, free of rust, oil and paint'),
    ),
    DefectStep(
      'interpass',
      Tx('Temperatura międzyściegowa w zakresie WPS',
          'Interpass temperature within the WPS range'),
    ),
    DefectStep(
      'post-heat',
      Tx('Po spawaniu: utrzymanie temperatury / dogrzanie, jeśli wymaga WPS',
          'After welding: hold / post-heat if the WPS requires it'),
    ),
  ],
  repairSources: [..._repairSourcesStandard, 'twi-hydrogen'],
);

const _crackHot = WeldDefect(
  id: 'crack_hot',
  group: DefectGroup.cracks,
  refs: [
    Iso6520Ref(100, 'Pęknięcie', 'Crack'),
    Iso6520Ref(101, 'Pęknięcie podłużne', 'Longitudinal crack'),
  ],
  title: Tx('Pęknięcie gorące (krystalizacyjne)', 'Hot (solidification) crack'),
  looks: Tx(
    'Pęknięcie wzdłuż osi spoiny, powstaje przy krzepnięciu. Typowe dla '
        'głębokich, wąskich ściegów, stali austenitycznych i aluminium (TWI).',
    'A crack along the weld centreline, formed during solidification. '
        'Typical of deep, narrow beads, austenitic stainless steels and '
        'aluminium (TWI).',
  ),
  processes: _all,
  keywords: [
    'krystalizacyjne',
    'gorace',
    'w osi',
    'solidification',
    'hot cracking',
    'centreline',
    'centerline',
  ],
  causes: [
    DefectCause(
      id: 'hot-bead-shape',
      processes: _all,
      rank: 1,
      cause: Tx('Ścieg za głęboki i za wąski', 'Bead too deep and too narrow'),
      check: Tx(
          'Stosunek głębokości do szerokości ściegu: TWI zaleca 0,5–2; '
              'powyżej 2 rośnie ryzyko pęknięcia w osi.',
          'Bead depth-to-width ratio: TWI recommends 0.5–2; above 2 the risk '
              'of a centreline crack rises.'),
      fix: Tx(
          'Szerszy, płytszy ścieg: prąd i napięcie wg WPS, bez dużego prądu '
              'przy dużej prędkości; SAW — TWI: szerokość / głębokość ok. '
              '1,5.',
          'A wider, shallower bead: current and voltage per the WPS, no high '
              'current with high speed; SAW — TWI: width / depth approx. '
              '1.5.'),
      sources: ['twi-solidification', 'twi-saw-cracking'],
    ),
    DefectCause(
      id: 'hot-al-filler',
      processes: {_tig, _mig},
      materials: {_al},
      rank: 1,
      cause: Tx('Stop 6xxx bez spoiwa albo złe spoiwo do aluminium',
          '6xxx alloy without filler or the wrong aluminium filler'),
      check: Tx(
          'Spoiwo zgodne z WPS (4043 / 5356)? Stop 5xxx spawany spoiwem '
              '4xxx (nie wolno — Hobart)?',
          'Filler as in the WPS (4043 / 5356)? A 5xxx alloy welded with 4xxx '
              'filler (not allowed — Hobart)?'),
      fix: Tx(
          'Do 6xxx zawsze dodawaj spoiwo; dobór — moduł „Dobór spoiwa”; '
              'spoiny nie wklęsłe (Lincoln).',
          'Always add filler to 6xxx; selection — the “Filler metal '
              'selector” tool; no concave welds (Lincoln).'),
      sources: ['hobart-al-cracking', 'lincoln-al'],
    ),
    DefectCause(
      id: 'hot-ss-ferrite',
      processes: {_mma, _mag, _fcg, _tig, _saw},
      materials: {_ss},
      rank: 2,
      cause: Tx('Za mało ferrytu w stopiwie stali austenitycznej',
          'Too little ferrite in austenitic stainless weld metal'),
      check: Tx(
          'Spoiwo zgodne z WPS? TWI: ok. 5–10 % ferrytu w stopiwie ogranicza '
              'pękanie; pomiar ferrytomierzem, jeśli wymaga specyfikacja.',
          'Filler as in the WPS? TWI: approx. 5–10 % ferrite in the weld metal '
              'limits cracking; check with a ferrite meter if the '
              'specification requires it.'),
      fix: Tx(
          'Spoiwo z WPS z kontrolowanym ferrytem; ogranicz wymieszanie '
              'z materiałem rodzimym (mniejsze wtopienie).',
          'Filler from the WPS with controlled ferrite; limit dilution with '
              'the parent metal (less penetration).'),
      sources: ['twi-solidification'],
    ),
    DefectCause(
      id: 'hot-impurities',
      processes: {_mma, _mag, _fcg, _fcs, _saw},
      materials: {_cs},
      rank: 3,
      cause: Tx(
          'Siarka, fosfor lub węgiel w materiale przy dużym wymieszaniu',
          'Sulphur, phosphorus or carbon in the parent metal with high '
              'dilution'),
      check: Tx(
          'Atest: TWI dla stali C-Mn — S + P najwyżej 0,06 %. Pęka głównie '
              'ścieg z dużym wtopieniem?',
          'Certificate: TWI for C-Mn steel — S + P at most 0.06 %. Mostly the '
              'deep-penetration run cracks?'),
      fix: Tx(
          'Mniejsze wtopienie; przy SAW drut z wyższym Mn (TWI) — zmiana '
              'spoiwa tylko wg WPS.',
          'Less penetration; for SAW a higher-Mn wire (TWI) — change the '
              'filler only per the WPS.'),
      sources: ['twi-solidification', 'twi-saw-cracking'],
    ),
    DefectCause(
      id: 'hot-gap',
      processes: _all,
      rank: 3,
      cause: Tx('Za szeroka lub zmienna szczelina, zanieczyszczony rowek',
          'Gap too wide or variable, dirty groove'),
      check: Tx('Szczelina zgodna z WPS na całej długości? Rowek czysty?',
          'Gap per the WPS along the whole length? Groove clean?'),
      fix: Tx('Popraw przygotowanie i sczepienie, usuń zanieczyszczenia (TWI).',
          'Correct the preparation and tacking, remove contamination (TWI).'),
      sources: ['twi-solidification'],
    ),
    DefectCause(
      id: 'hot-crater',
      processes: _all,
      rank: 4,
      cause: Tx('Niewypełniony krater na końcu ściegu',
          'Unfilled crater at the end of the run'),
      check: Tx('Pęknięcie zaczyna się w kraterze?',
          'Does the crack start in the crater?'),
      fix: Tx(
          'Wypełniaj krater na końcu ściegu (TWI) — zobacz „Pęknięcie '
              'w kraterze”.',
          'Fill the crater at the end of the run (TWI) — see “Crater '
              'crack”.'),
      sources: ['twi-solidification'],
    ),
  ],
  repair: [
    _rCauseFirst,
    _rMark,
    _rCrackBeyond,
    _rRemove,
    _rGouge,
    _rConfirm,
    _rGroove,
    _rPreheat,
    _rWeld,
    _rNdt,
    _rLimit,
  ],
  cutOut: _cutCrack,
  safety: _safetyStandard,
  checklist: [
    DefectStep(
      'bead-shape',
      Tx('Kształt ściegu: szerszy niż głęboki', 'Bead shape: wider than deep'),
    ),
    DefectStep(
      'gap-clean',
      Tx('Szczelina i czystość rowka wg WPS',
          'Gap and groove cleanliness per the WPS'),
    ),
    DefectStep(
      'filler-wps',
      Tx('Spoiwo zgodne z WPS (nierdzewka, aluminium)',
          'Filler as in the WPS (stainless, aluminium)'),
      materials: {_ss, _al},
    ),
    DefectStep(
      'crater-filled',
      Tx('Krater wypełniony na końcu ściegu',
          'Crater filled at the end of the run'),
    ),
    DefectStep(
      'params',
      Tx('Prąd i prędkość w zakresie WPS',
          'Current and travel speed within the WPS'),
    ),
  ],
  repairSources: [
    ..._repairSourcesStandard,
    'twi-solidification',
  ],
);

const _crackCrater = WeldDefect(
  id: 'crack_crater',
  group: DefectGroup.cracks,
  refs: [Iso6520Ref(104, 'Pęknięcie w kraterze', 'Crater crack')],
  title: Tx('Pęknięcie w kraterze', 'Crater crack'),
  looks: Tx(
    'Pęknięcie (często gwiaździste) w kraterze na końcu ściegu. EN ISO 5817 '
        'nie dopuszcza go na żadnym poziomie (poz. 1.2).',
    'A crack (often star-shaped) in the crater at the end of a run. EN ISO '
        '5817 does not permit it at any level (item 1.2).',
  ),
  processes: _all,
  keywords: ['krater', 'gwiazdziste', 'koniec sciegu', 'crater', 'star crack'],
  causes: [
    DefectCause(
      id: 'crater-abrupt',
      processes: _all,
      rank: 1,
      cause: Tx('Łuk zgaszony nagle — krater nie wypełniony',
          'Arc stopped abruptly — crater not filled'),
      check: Tx('Na końcu ściegu wklęsły krater z pęknięciem?',
          'A concave crater with a crack at the end of the run?'),
      fix: Tx(
          'Wypełnij krater: dodaj spoiwo przy końcu, stopniowo zmniejszaj '
              'prąd, płytka wybiegowa (TWI).',
          'Fill the crater: add filler at the end, reduce the current '
              'gradually, use a run-off tab (TWI).'),
      sources: ['twi-crater', 'twi-solidification'],
    ),
    DefectCause(
      id: 'crater-tig-slope',
      processes: {_tig},
      rank: 1,
      cause: Tx('Brak opadania prądu (downslope) w TIG',
          'No current downslope in TIG'),
      check: Tx(
          'Spawasz bez pedału / funkcji opadania? Przykład: Fronius TransTig '
              '— opadanie 0,01–9,9 s (fabrycznie 1,0 s).',
          'Welding without a pedal / downslope function? Example: Fronius '
              'TransTig — downslope 0.01–9.9 s (factory 1.0 s).'),
      fix: Tx(
          'Włącz opadanie prądu i dodawaj pręt, gdy prąd spada (Miller); albo '
              'wróć łukiem w poprzednią spoinę (CK).',
          'Turn on downslope and add rod while the current drops (Miller); or '
              'move the arc back onto the weld (CK).'),
      sources: ['miller-tig-problems', 'ck-tig', 'fronius-tig'],
    ),
    DefectCause(
      id: 'crater-al',
      processes: {_tig, _mig},
      materials: {_al},
      rank: 1,
      cause: Tx('Aluminium: duży skurcz krateru',
          'Aluminium: large crater shrinkage'),
      check: Tx('Pęknięcia kraterowe na każdym końcu ściegu?',
          'Crater cracks at every end of the run?'),
      fix: Tx(
          'Na końcu przyspiesz i cofnij się na krótkim odcinku albo kilka '
              'razy zajarz w jeziorku; najlepiej funkcja crater fill (Hobart).',
          'At the end speed up and back-step a short distance or re-strike in '
              'the pool a few times; best — the crater fill function '
              '(Hobart).'),
      sources: ['hobart-al-cracking', 'lincoln-al'],
    ),
    DefectCause(
      id: 'crater-fill',
      processes: _wire,
      rank: 2,
      cause: Tx('Nie używasz funkcji wypełniania krateru (crater fill)',
          'Crater fill function not used'),
      check: Tx('Źródło ma crater fill / tryb 4T z prądem końcowym?',
          'Does the power source have crater fill / 4T with an end current?'),
      fix: Tx('Włącz crater fill (TWI: urządzenie do wypełniania krateru).',
          'Turn on crater fill (TWI: a crater filling device).'),
      sources: ['twi-crater'],
    ),
    DefectCause(
      id: 'crater-grind',
      processes: _all,
      rank: 3,
      cause: Tx('Krater poprzedniego ściegu nie zeszlifowany',
          'Crater of the previous run not ground out'),
      check: Tx('Na zakończeniach ściegów zostały wgłębienia lub rysy?',
          'Are there dips or cracks left at the run ends?'),
      fix: Tx('Zeszlifuj zakończenie przed kolejnym ściegiem (TWI).',
          'Grind the run end before the next run (TWI).'),
      sources: ['twi-crater'],
    ),
  ],
  repair: [
    _rCauseFirst,
    _rMark,
    _rRemove,
    _rConfirm,
    _rGroove,
    _rPreheat,
    _rWeld,
    _rNdt,
    _rNdtDelay,
    _rLimit,
  ],
  cutOut: _cutCrack,
  safety: [_sGrind, _sPt, _sPreheat],
  checklist: [
    DefectStep(
      'crater-filled',
      Tx('Krater wypełniony przed zgaszeniem łuku',
          'Crater filled before the arc stops'),
    ),
    DefectStep(
      'run-end-ground',
      Tx('Zakończenie poprzedniego ściegu zeszlifowane',
          'End of the previous run ground'),
    ),
    DefectStep(
      'run-off',
      Tx('Płytka wybiegowa tam, gdzie się da',
          'Run-off tab wherever possible'),
    ),
    DefectStep(
      'downslope',
      Tx('Opadanie prądu (downslope) włączone', 'Downslope switched on'),
      processes: {_tig},
    ),
    DefectStep(
      'crater-fill-on',
      Tx('Funkcja crater fill włączona', 'Crater fill switched on'),
      processes: _wire,
    ),
  ],
  repairSources: [..._repairSourcesStandard, 'twi-crater'],
);

// ── 2xx Pustki ──────────────────────────────────────────────────────────────

const _porosity = WeldDefect(
  id: 'porosity',
  group: DefectGroup.cavities,
  refs: [
    Iso6520Ref(2011, 'Pęcherz gazowy', 'Gas pore'),
    Iso6520Ref(2012, 'Pęcherze równomiernie rozłożone',
        'Uniformly distributed porosity'),
    Iso6520Ref(2013, 'Gniazdo pęcherzy', 'Clustered (localized) porosity'),
    Iso6520Ref(2014, 'Łańcuch pęcherzy', 'Linear porosity'),
    Iso6520Ref(2016, 'Pęcherz kanalikowy', 'Worm-hole'),
    Iso6520Ref(2017, 'Por powierzchniowy', 'Surface pore'),
  ],
  title: Tx('Porowatość (pęcherze gazowe)', 'Porosity (gas pores)'),
  looks: Tx(
    'Pęcherze gazu w spoinie — pojedyncze, rozproszone, w gnieździe, '
        'w łańcuchu albo otwarte na powierzchni. TWI: już ok. 1 % powietrza '
        'w osłonie daje porowatość, powyżej 1,5 % — duże pory na powierzchni.',
    'Gas pores in the weld — single, scattered, clustered, in a line or open '
        'at the surface. TWI: about 1 % air in the shield already causes '
        'porosity, above 1.5 % — large surface pores.',
  ),
  processes: _all,
  keywords: [
    'pory',
    'pecherze',
    'dziury',
    'porowata',
    'porosity',
    'pores',
    'pinholes',
    'wormhole',
    'blowholes',
  ],
  causes: [
    DefectCause(
      id: 'draught',
      processes: _bottleGas,
      rank: 1,
      cause: Tx('Przeciąg lub wiatr zdmuchuje osłonę gazową',
          'Draught or wind blows the gas shield away'),
      check: Tx(
          'Czy przy spoinie wieje (otwarta brama, wentylator, wiatr)? AWS '
              'D1.1: w osłonie gazu najwyżej 8 km/h (ok. 2,2 m/s) przy '
              'spoinie; Kobelco: powyżej 2 m/s pęcherzy przybywa gwałtownie.',
          'Is there a draught at the weld (open door, fan, wind)? AWS D1.1: '
              'gas-shielded welding at most 8 km/h (approx. 2.2 m/s) at the '
              'weld; Kobelco: above 2 m/s porosity rises sharply.'),
      fix: Tx(
          'Parawan, namiot lub osłona złącza; odwróć wentylator; ocena '
              'warunków — moduł „Warunki do spawania”. Nie podkręcaj gazu na '
              'ślepo — za duży przepływ też daje pory (TWI).',
          'Screen, tent or joint cover; turn the fan away; conditions check — '
              'the “Welding conditions” tool. Do not just turn the gas up — '
              'too much flow also causes pores (TWI).'),
      sources: ['aws-wind', 'kobelco-gas', 'twi-porosity'],
    ),
    DefectCause(
      id: 'mma-wet-electrode',
      processes: {_mma},
      rank: 1,
      cause: Tx('Zawilgocone elektrody (zwłaszcza zasadowe)',
          'Damp electrodes (especially basic)'),
      check: Tx(
          'Elektrody z piecyka czy z otwartej paczki / kołczanu po kilku '
              'godzinach? Przy rutylowych pory, rozprysk i niestabilny łuk to '
              'objawy wilgoci (Oerlikon).',
          'Electrodes from the oven or from an open packet / quiver after '
              'hours? With rutile ones pores, spatter and an unstable arc are '
              'signs of moisture (Oerlikon).'),
      fix: Tx(
          'Elektrody z piecyka-przechowalnika; zawilgocone wysusz wg karty '
              'producenta albo wymień; czas na powietrzu — moduł „Elektrody '
              'zasadowe: czas i suszenie”.',
          'Electrodes from the holding oven; re-dry damp ones per the maker’s '
              'data sheet or replace them; exposure time — the “Low-hydrogen '
              'electrodes: exposure” tool.'),
      sources: ['oerlikon-storage', 'twi-porosity'],
    ),
    DefectCause(
      id: 'saw-wet-flux',
      processes: {_saw},
      rank: 1,
      cause: Tx('Wilgotny topnik', 'Damp flux'),
      check: Tx(
          'Topnik z otwartego worka albo z odzysku bez suszenia? Pory często '
              'w osi spoiny?',
          'Flux from an open bag or recycled without drying? Pores often on '
              'the centreline?'),
      fix: Tx(
          'Susz wg karty topnika (np. Hobart HA-495: 300–350 °C, min. 2 h; '
              'przechowywanie 150 ± 25 °C); sprężone powietrze w obiegu '
              'odzysku suche i bez oleju (TWI).',
          'Dry per the flux data sheet (e.g. Hobart HA-495: 300–350 °C, at '
              'least 2 h; storage 150 ± 25 °C); compressed air in the recovery '
              'system dry and oil-free (TWI).'),
      sources: ['twi-saw-porosity', 'hobart-ha495'],
    ),
    DefectCause(
      id: 'al-hydrogen',
      processes: {_tig, _mig},
      materials: {_al},
      rank: 1,
      cause: Tx('Wodór z tlenku, wilgoci i tłuszczu na aluminium',
          'Hydrogen from oxide, moisture and grease on aluminium'),
      check: Tx(
          'Najpierw odtłuszczone, potem szczotkowane? Ile czasu od '
              'czyszczenia? Materiał przyniesiony z zimna (rosa)?',
          'Degreased first, then brushed? How long since cleaning? Material '
              'brought in from the cold (dew)?'),
      fix: Tx(
          'Odtłuść (aceton), potem szczotka ze stali nierdzewnej używana '
              'tylko do aluminium; tlenek usuwaj w ciągu godzin przed '
              'spawaniem (TWI); materiał wnieś na stanowisko 24 h wcześniej '
              '(Hobart).',
          'Degrease (acetone), then a stainless brush used only for '
              'aluminium; remove the oxide within hours of welding (TWI); '
              'bring the material into the area 24 h beforehand (Hobart).'),
      sources: ['twi-al-porosity', 'lincoln-al', 'hobart-al'],
    ),
    DefectCause(
      id: 'fcaw-s-voltage',
      processes: {_fcs},
      rank: 1,
      cause: Tx('Za wysokie napięcie (za długi łuk) drutem samoosłonowym',
          'Voltage too high (arc too long) with self-shielded wire'),
      check: Tx(
          'Ślady „robaczkowe” (worm tracks) na licu = napięcie za wysokie dla '
              'prędkości podawania (Hobart).',
          'Worm tracks on the face = voltage too high for the wire feed speed '
              '(Hobart).'),
      fix: Tx(
          'Obniżaj napięcie po 0,5 V (Hobart). Lincoln (Innershield), '
              'kolejno: oczyść złącze, obniż napięcie, wydłuż CTWD, zwiększ '
              'podawanie, zmniejsz kąt ciągnięcia.',
          'Lower the voltage in 0.5 V steps (Hobart). Lincoln (Innershield), '
              'in order: clean the joint, lower the voltage, increase CTWD, '
              'increase wire feed, reduce the drag angle.'),
      sources: ['hobart-fcaw-s', 'lincoln-innershield'],
    ),
    DefectCause(
      id: 'mag-gas-flow',
      processes: {_mag},
      rank: 2,
      cause: Tx('Za mały albo za duży przepływ gazu',
          'Gas flow too low or too high'),
      check: Tx(
          'Rotametr na dyszy (nie tylko na reduktorze). Orientacyjnie: '
              'Lincoln — łuk zwarciowy, drut 0,8–1,1 mm: 12–17 l/min; Kemppi '
              '— zwykle 10–20 l/min; SSAB — l/min ≈ średnica wewnętrzna dyszy '
              'w mm.',
          'Flowmeter at the nozzle (not only at the regulator). Roughly: '
              'Lincoln — short arc, 0.8–1.1 mm wire: 12–17 l/min; Kemppi — '
              'typically 10–20 l/min; SSAB — l/min ≈ nozzle bore in mm.'),
      fix: Tx(
          'Ustaw przepływ z WPS; za duży daje turbulencję i zasysanie '
              'powietrza (TWI). Sprawdź, czy w butli jest gaz i czy to '
              'właściwy gaz.',
          'Set the flow from the WPS; too much causes turbulence and draws in '
              'air (TWI). Check that the cylinder is not empty and holds the '
              'right gas.'),
      sources: ['lincoln-mig', 'kemppi-gas', 'ssab-gas', 'twi-porosity'],
    ),
    DefectCause(
      id: 'fcaw-gas-flow',
      processes: {_fcg},
      rank: 2,
      cause: Tx('Za mały albo za duży przepływ gazu',
          'Gas flow too low or too high'),
      check: Tx(
          'Przepływ z karty drutu, np. Lincoln UltraCore 71A85: 40–50 cfh '
              '(ok. 19–24 l/min); rotametr na dyszy.',
          'Flow from the wire data sheet, e.g. Lincoln UltraCore 71A85: '
              '40–50 cfh (approx. 19–24 l/min); flowmeter at the nozzle.'),
      fix: Tx(
          'Ustaw przepływ z WPS / karty drutu; za duży daje turbulencję '
              '(TWI).',
          'Set the flow from the WPS / wire data sheet; too much causes '
              'turbulence (TWI).'),
      sources: ['lincoln-71a85', 'twi-porosity'],
    ),
    DefectCause(
      id: 'mag-nozzle',
      processes: _gasWire,
      rank: 2,
      cause: Tx('Dysza zapchana rozpryskiem albo zatkany dyfuzor gazu',
          'Nozzle clogged with spatter or gas diffuser blocked'),
      check: Tx(
          'Zdejmij dyszę: rozprysk w środku, zatkane otworki dyfuzora, za '
              'mała dysza?',
          'Take the nozzle off: spatter inside, blocked diffuser holes, nozzle '
              'too small?'),
      fix: Tx(
          'Wyczyść albo wymień dyszę i dyfuzor; czyść dyszę regularnie '
              'w trakcie pracy.',
          'Clean or replace the nozzle and diffuser; clean the nozzle '
              'regularly while working.'),
      sources: ['miller-defects', 'tregaskiss-guide', 'kobelco-gas'],
    ),
    DefectCause(
      id: 'tig-post-flow',
      processes: {_tig},
      rank: 2,
      cause: Tx(
          'Za krótki wypływ końcowy gazu (post-flow) albo za wcześnie '
              'odsunięty palnik',
          'Post-flow too short or torch moved away too early'),
      check: Tx(
          'Ustawienie post-flow: Miller — 1 s na każde 10 A, min. 8 s. Pory '
              'w kraterze, wolfram po zgaszeniu siny?',
          'Post-flow setting: Miller — 1 s per 10 A, at least 8 s. Pores in '
              'the crater, tungsten blue after the arc stops?'),
      fix: Tx(
          'Wydłuż post-flow i trzymaj palnik nad kraterem do końca wypływu.',
          'Lengthen the post-flow and keep the torch over the crater until it '
              'ends.'),
      sources: ['miller-tig-gas', 'ck-tig'],
    ),
    DefectCause(
      id: 'mma-long-arc',
      processes: {_mma},
      rank: 2,
      cause: Tx('Za długi łuk — zwłaszcza elektrodą zasadową',
          'Arc too long — especially with a basic electrode'),
      check: Tx(
          'Odległość końca elektrody od jeziorka ≈ średnica elektrody '
              '(Hobart: dla 3,2 mm ok. 3,2 mm)? Łuk trzeszczy i gaśnie?',
          'Electrode tip to pool distance ≈ electrode diameter (Hobart: for '
              '3.2 mm approx. 3.2 mm)? Arc crackles and goes out?'),
      fix: Tx(
          'Krótki, stały łuk — elektroda zasadowa ma słabszą osłonę gazową '
              'niż rutylowa i celulozowa (TWI).',
          'A short, steady arc — a basic electrode has weaker gas shielding '
              'than rutile and cellulosic ones (TWI).'),
      sources: ['hobart-stick', 'twi-consumables'],
    ),
    DefectCause(
      id: 'saw-flux-depth',
      processes: {_saw},
      rank: 2,
      cause: Tx('Za płytka warstwa topnika — łuk przebija',
          'Flux layer too shallow — the arc breaks through'),
      check: Tx(
          'Widać błyski łuku przez topnik? TWI: topnik ma tylko przykrywać '
              'łuk, jego blask ledwo widoczny.',
          'Arc flashes visible through the flux? TWI: the flux should just '
              'cover the arc, its glow barely visible.'),
      fix: Tx(
          'Zwiększ zasyp; za gruby też szkodzi (gorszy kształt ściegu, '
              'trudne usuwanie żużla — TWI).',
          'Increase the flux burden; too deep is also bad (poorer bead shape, '
              'hard slag removal — TWI).'),
      sources: ['twi-saw-flux', 'twi-saw-porosity'],
    ),
    DefectCause(
      id: 'mig-al-gas-flow',
      processes: {_mig},
      rank: 2,
      cause: Tx('Za mało gazu albo zły kąt palnika przy aluminium',
          'Too little gas or wrong torch angle on aluminium'),
      check: Tx(
          'Lincoln: MIG Al 30–100 cfh (ok. 14–47 l/min) zależnie od dyszy '
              'i gazu — więcej niż dla stali. Palnik ciągnięty?',
          'Lincoln: MIG aluminium 30–100 cfh (approx. 14–47 l/min) depending '
              'on nozzle and gas — more than for steel. Torch dragged?'),
      fix: Tx(
          'Przepływ z WPS; technika pchająca 5–10° (Lincoln) — przy '
              'ciągnięciu spoina szara lub czarna.',
          'Flow from the WPS; push technique 5–10° (Lincoln) — dragging gives '
              'a grey or black weld.'),
      sources: ['lincoln-al', 'hobart-al'],
    ),
    DefectCause(
      id: 'fcaw-stickout',
      processes: {_fcg, _fcs},
      rank: 2,
      cause: Tx('Wolny wylot drutu inny niż w karcie drutu',
          'Wire stickout not as in the wire data sheet'),
      check: Tx(
          'Lincoln Innershield: np. NR-232 CTWD 25 mm, NR-5 CTWD 32 mm (wylot '
              '= CTWD − 6 mm); Hobart: drut samoosłonowy najwyżej ok. 32 mm '
              'poza końcówką; UltraCore 71A85: CTWD 25 mm.',
          'Lincoln Innershield: e.g. NR-232 CTWD 25 mm, NR-5 CTWD 32 mm '
              '(stickout = CTWD − 6 mm); Hobart: self-shielded wire at most '
              'approx. 32 mm beyond the tip; UltraCore 71A85: CTWD 25 mm.'),
      fix: Tx(
          'Trzymaj wylot z karty drutu; przy 114 dłuższy wylot (w zakresie '
              'karty) zmniejsza skłonność do porów (Lincoln).',
          'Keep the stickout from the wire data sheet; with 114 a longer '
              'stickout (within the data sheet range) reduces porosity '
              '(Lincoln).'),
      sources: ['lincoln-innershield', 'hobart-fcaw-s', 'lincoln-71a85'],
    ),
    DefectCause(
      id: 'gas-leak',
      processes: _bottleGas,
      rank: 3,
      cause: Tx(
          'Nieszczelność: wąż, szybkozłączka, o-ring, pęknięty izolator lub '
              'dysza — palnik zasysa powietrze',
          'Leak: hose, quick coupling, O-ring, cracked insulator or nozzle — '
              'the torch draws in air'),
      check: Tx(
          'Posmaruj złącza wodą z mydłem (Miller); obejrzyj o-ringi, wąż '
              'i dyszę.',
          'Brush the joints with soapy water (Miller); inspect O-rings, hose '
              'and nozzle.'),
      fix: Tx(
          'Wymień uszkodzone części, dokręć przyłącza; nową lub długo '
              'nieużywaną instalację przedmuchaj przed pierwszą spoiną (TWI).',
          'Replace damaged parts, tighten connections; purge a new or '
              'long-unused gas line before the first weld (TWI).'),
      sources: [
        'twi-porosity',
        'miller-tig-problems',
        'tregaskiss-guide',
        'twi-al-porosity',
      ],
    ),
    DefectCause(
      id: 'contamination',
      processes: _all,
      rank: 3,
      cause: Tx('Rdza, olej, farba, podkład, ocynk lub wilgoć na rowku',
          'Rust, oil, paint, primer, zinc coating or moisture on the groove'),
      check: Tx(
          'Rowek i brzegi czyste do metalu? Podkład grubszy niż dopuszcza '
              'producent (TWI podaje typowo 20 µm na krawędziach złącza '
              'teowego)?',
          'Groove and edges clean to bright metal? Primer thicker than the '
              'maker allows (TWI gives typically 20 µm at T-joint edges)?'),
      fix: Tx(
          'Oczyść do metalu, odtłuść, osusz; przy SAW olej i farba dają '
              'pęcherze kanalikowe, często w osi spoiny (TWI).',
          'Clean to bright metal, degrease, dry; in SAW oil and paint cause '
              'worm-holes, often on the weld centreline (TWI).'),
      sources: ['twi-porosity', 'miller-defects', 'twi-saw-porosity'],
    ),
    DefectCause(
      id: 'tig-gas-flow',
      processes: {_tig},
      rank: 3,
      cause: Tx('Przepływ argonu niedopasowany do dyszy',
          'Argon flow not matched to the cup'),
      check: Tx(
          'Rotametr: Kemppi — elektroda 2,4 mm, dysza nr 6/7: 7–8 l/min; '
              'Miller — 15–20 cfh (ok. 7,1–9,4 l/min). Za duży przepływ = '
              'turbulencja (TWI).',
          'Flowmeter: Kemppi — 2.4 mm electrode, cup no. 6/7: 7–8 l/min; '
              'Miller — 15–20 cfh (approx. 7.1–9.4 l/min). Too much flow = '
              'turbulence (TWI).'),
      fix: Tx(
          'Przepływ z WPS do rozmiaru dyszy; przy przeciągu osłoń stanowisko '
              'zamiast podkręcać gaz.',
          'Flow from the WPS to suit the cup size; in a draught screen the '
              'area instead of turning the gas up.'),
      sources: ['kemppi-tig', 'miller-tig-problems', 'twi-porosity'],
    ),
    DefectCause(
      id: 'filler-dirty',
      processes: {_tig, _mig},
      rank: 3,
      cause: Tx('Zanieczyszczony pręt lub drut (olej, wilgoć, kurz)',
          'Contaminated rod or wire (oil, moisture, dust)'),
      check: Tx(
          'Pręty leżały luzem, bez opakowania? Ślady palców, kurz, nalot?',
          'Rods left loose, unpacked? Finger marks, dust, film?'),
      fix: Tx(
          'Przetrzyj pręt szmatką z acetonem (TWI); spoiwo trzymaj '
              'w zamkniętym opakowaniu, wilgotne spoiwo aluminiowe wysusz '
              '(CK).',
          'Wipe the rod with an acetone cloth (TWI); keep filler in a closed '
              'pack, dry damp aluminium filler (CK).'),
      sources: ['twi-al-porosity-faq', 'ck-tig'],
    ),
    DefectCause(
      id: 'mma-start',
      processes: {_mma},
      rank: 3,
      cause: Tx('Pory na początku ściegu (start elektrodą zasadową)',
          'Pores at the start of the run (basic electrode start)'),
      check: Tx(
          'Pory skupione na pierwszych milimetrach po każdej nowej elektrodzie?',
          'Pores clustered in the first millimetres after each new '
              'electrode?'),
      fix: Tx(
          'Zajarz łuk przed miejscem startu, wróć na początek i dopiero '
              'spawaj dalej (TWI; Kobelco: „backstep”).',
          'Strike the arc ahead of the start point, move back to the start and '
              'only then weld on (TWI; Kobelco: back-step).'),
      sources: ['twi-consumables', 'kobelco-start'],
    ),
    DefectCause(
      id: 'fcaw-wet-wire',
      processes: {_fcg, _fcs},
      rank: 3,
      cause: Tx('Zawilgocony drut proszkowy', 'Damp flux-cored wire'),
      check: Tx('Szpula leżała otwarta w wilgoci lub na mrozie? Rdza na drucie?',
          'Was the spool left open in damp or frost? Rust on the wire?'),
      fix: Tx(
          'Po pracy zdejmij szpulę i trzymaj w opakowaniu w suchym miejscu '
              '(Lincoln: chroń drut przed atmosferą).',
          'After work remove the spool and keep it packed in a dry place '
              '(Lincoln: protect the wire from the atmosphere).'),
      sources: ['lincoln-innershield', 'twi-porosity'],
    ),
    DefectCause(
      id: 'mag-stickout',
      processes: {_mag, _mig},
      rank: 4,
      cause: Tx('Za długi wolny wylot drutu (palnik za daleko)',
          'Wire stickout too long (torch too far away)'),
      check: Tx(
          'Wylot drutu: Lincoln — zwarciowy 6–13 mm, natryskowy 19–25 mm; '
              'Miller — wylot ponad 13 mm sprzyja porom.',
          'Wire stickout: Lincoln — short arc 6–13 mm, spray 19–25 mm; Miller '
              '— stickout over 13 mm promotes pores.'),
      fix: Tx(
          'Trzymaj stały wylot z WPS; dobierz dyszę i cofnięcie końcówki do '
              'rodzaju łuku (Lincoln).',
          'Keep a steady stickout per the WPS; match the nozzle and tip '
              'recess to the transfer mode (Lincoln).'),
      sources: ['lincoln-mig', 'miller-defects'],
    ),
  ],
  repair: [
    _rCauseFirst,
    _rMark,
    _rRemove,
    _rGouge,
    _rConfirm,
    _rGroove,
    _rPreheat,
    _rWeld,
    _rNdt,
    _rLimit,
  ],
  cutOut: Tx(
    'Pory na dużej długości lub w całym przekroju (np. spawane bez gazu) — '
        'rozważ wycięcie całej spoiny zamiast napraw miejscowych; decyduje '
        'specyfikacja / inspektor, także po wyczerpaniu limitu napraw.',
    'Pores over a long length or through the whole section (e.g. welded '
        'without gas) — consider cutting out the whole weld instead of local '
        'repairs; the specification / inspector decides, also once the repair '
        'limit is used up.',
  ),
  safety: [_sGrind, _sGouge, _sPt],
  checklist: [
    DefectStep(
      'no-draught',
      Tx('Brak przeciągu przy spoinie (parawan / osłona)',
          'No draught at the weld (screen / cover)'),
      processes: _bottleGas,
    ),
    DefectStep(
      'flow-measured',
      Tx('Przepływ gazu zmierzony na dyszy', 'Gas flow measured at the nozzle'),
      processes: _bottleGas,
    ),
    DefectStep(
      'nozzle-clean',
      Tx('Dysza czysta, bez rozprysku', 'Nozzle clean, no spatter'),
      processes: _gasWire,
    ),
    DefectStep(
      'groove-clean',
      Tx('Rowek czysty do metalu i suchy', 'Groove clean to bright metal and '
          'dry'),
    ),
    DefectStep(
      'electrodes-oven',
      Tx('Elektrody z piecyka, krótki łuk',
          'Electrodes from the oven, short arc'),
      processes: {_mma},
    ),
    DefectStep(
      'mma-start',
      Tx('Start: zajarzenie przed miejscem startu i powrót',
          'Start: strike ahead of the start point and move back'),
      processes: {_mma},
    ),
    DefectStep(
      'post-flow-set',
      Tx('Post-flow ustawiony (1 s na 10 A, min. 8 s)',
          'Post-flow set (1 s per 10 A, at least 8 s)'),
      processes: {_tig},
    ),
    DefectStep(
      'flux-dry',
      Tx('Topnik suchy (suszony wg karty)', 'Flux dry (dried per the data '
          'sheet)'),
      processes: {_saw},
    ),
    DefectStep(
      'flux-covers',
      Tx('Zasyp topnika przykrywa łuk', 'Flux burden covers the arc'),
      processes: {_saw},
    ),
    DefectStep(
      'al-cleaned',
      Tx('Aluminium odtłuszczone i szczotkowane tuż przed spawaniem',
          'Aluminium degreased and brushed just before welding'),
      processes: {_tig, _mig},
      materials: {_al},
    ),
    DefectStep(
      'fcaw-settings',
      Tx('Napięcie i wylot drutu wg karty drutu',
          'Voltage and stickout per the wire data sheet'),
      processes: {_fcg, _fcs},
    ),
    DefectStep(
      'spool-dry',
      Tx('Szpula drutu sucha, bez rdzy', 'Wire spool dry, no rust'),
      processes: {_fcg, _fcs},
    ),
  ],
  repairSources: _repairSourcesStandard,
);

const _shrinkage = WeldDefect(
  id: 'shrinkage',
  group: DefectGroup.cavities,
  refs: [
    Iso6520Ref(202, 'Jama skurczowa', 'Shrinkage cavity'),
    Iso6520Ref(2024, 'Krater', 'Crater pipe'),
    Iso6520Ref(2025, 'Otwarta jama skurczowa w kraterze', 'End crater pipe'),
  ],
  title: Tx('Jama skurczowa i jama w kraterze', 'Shrinkage cavity and crater '
      'pipe'),
  looks: Tx(
    'Pustka po skurczu krzepnącego metalu — najczęściej w kraterze na końcu '
        'ściegu, często razem z porami (TWI).',
    'A cavity left by the shrinking, solidifying metal — most often in the '
        'crater at the end of a run, often together with pores (TWI).',
  ),
  processes: _all,
  keywords: ['jama', 'krater', 'lejek', 'skurcz', 'crater pipe', 'shrinkage'],
  causes: [
    DefectCause(
      id: 'sh-stop',
      processes: _all,
      rank: 1,
      cause: Tx(
          'Prąd wyłączony przy dużym jeziorku — krater krzepnie gwałtownie',
          'Current switched off with a large pool — the crater solidifies '
              'fast'),
      check: Tx('Lejek lub wgłębienie w kraterze na końcu ściegu?',
          'A pipe or dip in the crater at the end of the run?'),
      fix: Tx(
          'Przed zgaszeniem cofnij łuk lub zjedź nim na ściankę rowka, '
              'stopniowo zmniejszaj prąd, dodaj spoiwo na końcu (TWI, Kemppi).',
          'Before stopping, move the arc back or onto the groove wall, reduce '
              'the current gradually, add filler at the end (TWI, Kemppi).'),
      sources: ['twi-crater', 'kemppi-defects'],
    ),
    DefectCause(
      id: 'sh-tig-filler',
      processes: {_tig},
      rank: 1,
      cause: Tx('TIG: koniec ściegu bez dodawania pręta',
          'TIG: run ended without adding rod'),
      check: Tx('Kończysz ścieg bez pręta albo przed opadaniem prądu?',
          'Do you finish the run without rod or before the downslope?'),
      fix: Tx('Dodawaj pręt do końca, gdy prąd opada (TWI).',
          'Keep adding rod to the end while the current drops (TWI).'),
      sources: ['twi-crater'],
    ),
    DefectCause(
      id: 'sh-crater-fill',
      processes: _wire,
      rank: 2,
      cause: Tx('Bez funkcji wypełniania krateru', 'No crater fill function'),
      check: Tx('Źródło ma crater fill / tryb 4T z prądem końcowym?',
          'Does the power source have crater fill / 4T with an end current?'),
      fix: Tx(
          'Włącz crater fill; drut podawaj do zgaszenia łuku (TWI).',
          'Turn on crater fill; keep feeding wire until the arc stops '
              '(TWI).'),
      sources: ['twi-crater'],
    ),
    DefectCause(
      id: 'sh-grind',
      processes: _all,
      rank: 3,
      cause: Tx('Krater poprzedniej elektrody / ściegu nie zeszlifowany',
          'Crater of the previous electrode / run not ground out'),
      check: Tx('Jamy w miejscach wznowień?', 'Cavities at the restarts?'),
      fix: Tx(
          'Zeszlifuj miejsce zatrzymania przed kolejną elektrodą lub '
              'ściegiem; płytki wybiegowe (TWI).',
          'Grind the stop point before the next electrode or run; use run-off '
              'tabs (TWI).'),
      sources: ['twi-crater'],
    ),
  ],
  repair: [
    _rCauseFirst,
    _rMark,
    _rRemove,
    _rConfirm,
    _rPreheat,
    _rWeld,
    _rNdt,
  ],
  cutOut: Tx(
    'Rzadko potrzebne — jamę usuwa się szlifowaniem; wycięcie tylko przy '
        'wyczerpanym limicie napraw.',
    'Rarely needed — the cavity is ground out; cut out only when the repair '
        'limit is used up.',
  ),
  safety: [_sGrind, _sPt],
  checklist: [
    DefectStep(
      'crater-filled',
      Tx('Krater wypełniony przed zgaszeniem łuku',
          'Crater filled before the arc stops'),
    ),
    DefectStep(
      'stop-ground',
      Tx('Miejsce zatrzymania zeszlifowane przed wznowieniem',
          'Stop point ground before the restart'),
    ),
    DefectStep(
      'run-off',
      Tx('Płytka wybiegowa tam, gdzie się da',
          'Run-off tab wherever possible'),
    ),
    DefectStep(
      'crater-fill-on',
      Tx('Crater fill / opadanie prądu włączone',
          'Crater fill / downslope switched on'),
      processes: {_mag, _fcg, _fcs, _mig, _tig},
    ),
  ],
  repairSources: [..._repairSourcesStandard, 'twi-crater'],
);

// ── 3xx Wtrącenia stałe ─────────────────────────────────────────────────────

const _cutInclusions = Tx(
  'Wtrącenia w wielu warstwach na dużej długości albo limit napraw '
      'wyczerpany — wycięcie spoiny; decyduje specyfikacja.',
  'Inclusions in several layers over a long length or the repair limit used '
      'up — cut the weld out; the specification decides.',
);

const _slag = WeldDefect(
  id: 'slag',
  group: DefectGroup.inclusions,
  refs: [
    Iso6520Ref(301, 'Wtrącenie żużla', 'Slag inclusion'),
    Iso6520Ref(302, 'Wtrącenie topnika', 'Flux inclusion'),
  ],
  title: Tx('Wtrącenie żużla', 'Slag inclusion'),
  looks: Tx(
    'Żużel (przy SAW także topnik) uwięziony w spoinie — zwykle przy ściankach '
        'rowka i między ściegami; wykrywa się go głównie RT / UT.',
    'Slag (in SAW also flux) trapped in the weld — usually at the groove '
        'walls and between runs; found mainly by RT / UT.',
  ),
  processes: _slagging,
  keywords: ['zuzel', 'topnik', 'wtracenie', 'slag', 'flux'],
  causes: [
    DefectCause(
      id: 'slag-cleaning',
      processes: _slagging,
      rank: 1,
      cause: Tx('Żużel nie usunięty dokładnie między ściegami',
          'Slag not fully removed between runs'),
      check: Tx('Po skuciu zostały resztki żużla przy brzegach ściegu?',
          'After chipping, is slag left at the bead edges?'),
      fix: Tx(
          'Skuj i oczyść każdy ścieg (młotek, szczotka, szlifierka) przed '
              'następnym (TWI).',
          'Chip and clean every run (hammer, brush, grinder) before the next '
              'one (TWI).'),
      sources: ['twi-slag'],
    ),
    DefectCause(
      id: 'slag-profile',
      processes: _slagging,
      rank: 2,
      cause: Tx(
          'Wypukły ścieg albo podtopione brzegi — żużel zostaje w rowkach '
              'przy ściankach',
          'Convex bead or undercut edges — slag stays in the grooves at the '
              'walls'),
      check: Tx('Między ściegiem a ścianką rowka ostre wcięcia lub „dołki”?',
          'Sharp notches or pockets between the bead and the groove wall?'),
      fix: Tx(
          'Gładki profil ściegów z zakładką; wcięcia zeszlifuj przed kolejnym '
              'ściegiem (TWI).',
          'Smooth, overlapping beads; grind out notches before the next run '
              '(TWI).'),
      sources: ['twi-slag', 'twi-slag-faq'],
    ),
    DefectCause(
      id: 'slag-mma-technique',
      processes: {_mma},
      rank: 2,
      cause: Tx(
          'Zły kąt elektrody, za gruba elektroda do rowka, brak zatrzymania na '
              'brzegach',
          'Wrong electrode angle, electrode too big for the groove, no pause '
              'at the edges'),
      check: Tx('Elektroda mieści się w rowku? Przy zakosach zatrzymujesz się '
          'na brzegach?',
          'Does the electrode fit the groove? Do you pause at the edges when '
              'weaving?'),
      fix: Tx(
          'Średnica elektrody dobrana do rowka, właściwy kąt, krótkie '
              'zatrzymanie na brzegach (TWI).',
          'Electrode size to suit the groove, correct angle, a short pause at '
              'the edges (TWI).'),
      sources: ['twi-slag'],
    ),
    DefectCause(
      id: 'slag-fcaw',
      processes: {_fcg, _fcs},
      rank: 2,
      cause: Tx(
          'Za wąski rowek albo żużel wyprzedza jeziorko (drut proszkowy)',
          'Groove too narrow or slag running ahead of the pool (flux-cored)'),
      check: Tx('Rowek wąski? Spawasz za wolno albo pchając?',
          'Narrow groove? Welding too slowly or pushing?'),
      fix: Tx(
          'Lincoln: szerszy rowek (60° zamiast 30°, szczelina 6,4 mm), kąt '
              'ciągnięty 20–30°, nigdy pchanie, nieco szybciej; Hobart: kąt '
              'ciągnięty 15–45° (PA, PB, PE), 5–15° pionowo w górę.',
          'Lincoln: wider groove (60° instead of 30°, gap 6.4 mm), drag angle '
              '20–30°, never push, a little faster; Hobart: drag angle 15–45° '
              '(PA, PB, PE), 5–15° vertical up.'),
      sources: ['lincoln-innershield', 'hobart-fcaw-s'],
    ),
    DefectCause(
      id: 'slag-fast',
      processes: _slagging,
      rank: 3,
      cause: Tx('Za szybko — wypukły ścieg z „dołkami” przy liniach wtopienia',
          'Too fast — a convex bead with pockets at the fusion lines'),
      check: Tx('Ścieg wąski i wypukły?', 'Bead narrow and convex?'),
      fix: Tx('Prędkość i napięcie wg WPS (TWI).',
          'Travel speed and voltage per the WPS (TWI).'),
      sources: ['twi-slag-faq'],
    ),
    DefectCause(
      id: 'slag-mma-current',
      processes: {_mma},
      rank: 3,
      cause: Tx('Za duży prąd przy dużej prędkości podtapia ścianki rowka',
          'High current at high speed undercuts the groove walls'),
      check: Tx('Prąd i prędkość zgodne z WPS?',
          'Current and travel speed as in the WPS?'),
      fix: Tx('Prąd i prędkość wg WPS (TWI).',
          'Current and travel speed per the WPS (TWI).'),
      sources: ['twi-slag'],
    ),
  ],
  repair: [
    _rCauseFirst,
    _rMark,
    _rRemove,
    _rGouge,
    _rConfirm,
    _rGroove,
    _rPreheat,
    _rWeld,
    _rNdt,
    _rLimit,
  ],
  cutOut: _cutInclusions,
  safety: _safetyStandard,
  checklist: [
    DefectStep(
      'slag-removed',
      Tx('Żużel usunięty z całego ściegu, także przy ściankach',
          'Slag removed from the whole run, also at the walls'),
    ),
    DefectStep(
      'notches-ground',
      Tx('Wcięcia i wypukłości zeszlifowane przed kolejnym ściegiem',
          'Notches and humps ground before the next run'),
    ),
    DefectStep(
      'overlap-runs',
      Tx('Kolejny ścieg zachodzi na poprzedni', 'Each run overlaps the '
          'previous one'),
    ),
    DefectStep(
      'electrode-groove',
      Tx('Elektroda i kąt dobrane do rowka',
          'Electrode and angle suited to the groove'),
      processes: {_mma},
    ),
    DefectStep(
      'drag-angle',
      Tx('Kąt ciągnięty, bez pchania', 'Drag angle, no pushing'),
      processes: {_fcg, _fcs},
    ),
  ],
  repairSources: [..._repairSourcesStandard, 'twi-slag'],
);

const _oxide = WeldDefect(
  id: 'oxide',
  group: DefectGroup.inclusions,
  refs: [Iso6520Ref(303, 'Wtrącenie tlenków', 'Oxide inclusion')],
  title: Tx('Wtrącenie tlenków', 'Oxide inclusion'),
  looks: Tx(
    'Tlenki uwięzione w spoinie: przy MAG wyspy krzemianowe (szkliste plamki '
        'na licu), przy aluminium film tlenkowy — topi się w 2060 °C, a metal '
        'w 660 °C (TWI).',
    'Oxides trapped in the weld: in MAG silicon islands (glassy spots on the '
        'face), on aluminium the oxide film — it melts at 2060 °C, the metal at '
        '660 °C (TWI).',
  ),
  processes: {_mag, _tig, _mig},
  keywords: ['tlenki', 'krzem', 'wyspy krzemianowe', 'oxide', 'silicon'],
  causes: [
    DefectCause(
      id: 'ox-silicon',
      processes: {_mag},
      rank: 1,
      cause: Tx('Wyspy krzemianowe pozostawione między ściegami',
          'Silicon islands left between runs'),
      check: Tx('Szkliste plamki na licu poprzedniego ściegu?',
          'Glassy spots on the face of the previous run?'),
      fix: Tx(
          'Usuń je przed kolejnym ściegiem — pozostawione wędrują do brzegów, '
              'kolejny ścieg może ich nie przetopić, a łuk na nich jest '
              'niestabilny; mniejsza energia liniowa, usunięta zgorzelina '
              '(Hobart).',
          'Remove them before the next run — left in place they drift to the '
              'toes, the next run may not melt them and the arc is unstable on '
              'them; lower heat input, mill scale removed (Hobart).'),
      sources: ['hobart-silicon'],
    ),
    DefectCause(
      id: 'ox-al-film',
      processes: {_tig, _mig},
      materials: {_al},
      rank: 1,
      cause: Tx('Tlenek aluminium nie usunięty przed spawaniem',
          'Aluminium oxide not removed before welding'),
      check: Tx(
          'Materiał najpierw odtłuszczony, potem szczotkowany szczotką '
              'nierdzewną tylko do aluminium?',
          'Material degreased first, then brushed with a stainless brush used '
              'only for aluminium?'),
      fix: Tx(
          'Najpierw rozpuszczalnik, potem osobna szczotka nierdzewna tylko do '
              'aluminium (Miller); albo trawienie (TWI).',
          'Solvent first, then a separate stainless brush used only for '
              'aluminium (Miller); or chemical etching (TWI).'),
      sources: ['miller-al-clean', 'twi-al-faq'],
    ),
    DefectCause(
      id: 'ox-mill-scale',
      processes: {_mag, _tig},
      rank: 2,
      cause: Tx('Zgorzelina walcownicza lub rdza na rowku',
          'Mill scale or rust on the groove'),
      check: Tx('Ścianki rowka oczyszczone do metalu?',
          'Groove walls cleaned to bright metal?'),
      fix: Tx('Zeszlifuj zgorzelinę z rowka i brzegów (Hobart, TWI).',
          'Grind the mill scale off the groove and edges (Hobart, TWI).'),
      sources: ['hobart-silicon', 'twi-lof'],
    ),
    DefectCause(
      id: 'ox-al-balance',
      processes: {_tig},
      materials: {_al},
      rank: 2,
      cause: Tx('Za mało czyszczenia łukiem AC (balans)',
          'Too little AC cleaning action (balance)'),
      check: Tx('Czarne płatki przy jeziorku? Spawasz prądem stałym?',
          'Black flakes by the pool? Welding on DC?'),
      fix: Tx(
          'Do aluminium zawsze AC; zmniejsz balans, żeby wydłużyć fazę EP '
              '(Miller).',
          'Always AC for aluminium; reduce the balance to lengthen the EP '
              'phase (Miller).'),
      sources: ['miller-tig-problems'],
    ),
    DefectCause(
      id: 'ox-al-push',
      processes: {_mig},
      materials: {_al},
      rank: 2,
      cause: Tx('Palnik ciągnięty zamiast pchany', 'Torch dragged instead of '
          'pushed'),
      check: Tx('Spoina szara lub czarna?', 'Weld grey or black?'),
      fix: Tx('Technika pchająca 5–10° (Lincoln).',
          'Push technique 5–10° (Lincoln).'),
      sources: ['lincoln-al'],
    ),
  ],
  repair: [
    _rCauseFirst,
    _rMark,
    _rRemove,
    _rConfirm,
    _rGroove,
    _rPreheat,
    _rWeld,
    _rNdt,
    _rLimit,
  ],
  cutOut: _cutInclusions,
  safety: [_sGrind, _sPt],
  checklist: [
    DefectStep(
      'scale-removed',
      Tx('Rowek oczyszczony ze zgorzeliny / tlenku',
          'Groove cleaned of mill scale / oxide'),
    ),
    DefectStep(
      'brush-own',
      Tx('Szczotka i tarcza tylko do danego materiału',
          'Brush and disc used only for that material'),
    ),
    DefectStep(
      'silicon-removed',
      Tx('Wyspy krzemianowe usunięte przed kolejnym ściegiem',
          'Silicon islands removed before the next run'),
      processes: {_mag},
    ),
    DefectStep(
      'rod-clean',
      Tx('Pręt czysty, przetarty acetonem', 'Rod clean, wiped with acetone'),
      processes: {_tig},
    ),
    DefectStep(
      'al-solvent-brush',
      Tx('Aluminium: rozpuszczalnik, potem szczotka tylko do aluminium',
          'Aluminium: solvent, then a brush used only for aluminium'),
      processes: {_tig, _mig},
      materials: {_al},
    ),
    DefectStep(
      'mig-push',
      Tx('Technika pchająca', 'Push technique'),
      processes: {_mig},
    ),
  ],
  repairSources: _repairSourcesStandard,
);

const _tungsten = WeldDefect(
  id: 'tungsten',
  group: DefectGroup.inclusions,
  refs: [
    Iso6520Ref(
        3041, 'Wtrącenia metaliczne – wolfram', 'Metallic inclusion – tungsten'),
  ],
  title: Tx('Wtrącenie wolframu', 'Tungsten inclusion'),
  looks: Tx(
    'Odłamek elektrody wolframowej w spoinie; działa jak karb i trzeba go '
        'usunąć (Fronius).',
    'A piece of the tungsten electrode in the weld; it acts as a notch and '
        'must be removed (Fronius).',
  ),
  processes: {_tig},
  keywords: ['wolfram', 'elektroda wolframowa', 'tungsten'],
  causes: [
    DefectCause(
      id: 'tw-touch',
      processes: {_tig},
      rank: 1,
      cause: Tx('Wolfram dotknął jeziorka lub pręta',
          'Tungsten touched the pool or the rod'),
      check: Tx('Na końcówce stopiwo lub kulka, łuk się rozbiegł?',
          'Weld metal or a ball on the tip, arc wandering?'),
      fix: Tx(
          'Przerwij, odetnij zanieczyszczony koniec (lepiej odciąć niż '
              'szlifować — Diamond Ground; Miller: ok. 12,7 mm) i naostrz '
              'ponownie; trzymaj stały odstęp od pręta (CK).',
          'Stop, cut off the contaminated end (cutting beats grinding — '
              'Diamond Ground; Miller: approx. 12.7 mm) and regrind; keep a '
              'steady gap to the rod (CK).'),
      sources: ['dgp-tungsten', 'miller-tig-basics', 'ck-tig'],
    ),
    DefectCause(
      id: 'tw-contact-start',
      processes: {_tig},
      rank: 2,
      cause: Tx('Zajarzenie przez potarcie (scratch start)', 'Scratch start'),
      check: Tx(
          'Źródło bez HF / lift-arc? Elektroda przykleja się przy zajarzeniu?',
          'Power source without HF / lift-arc? Electrode sticks when '
              'striking?'),
      fix: Tx(
          'Zajarzaj HF albo lift-arc — przy lift-arc ryzyko wtrąceń jest małe '
              '(TWI); przy potarciu zajarzaj na płytce miedzianej (CK).',
          'Strike with HF or lift-arc — with lift-arc the risk of inclusions '
              'is small (TWI); with scratch start strike on a copper plate '
              '(CK).'),
      sources: ['twi-tig-equipment', 'fronius-hf', 'ck-tig'],
    ),
    DefectCause(
      id: 'tw-overcurrent',
      processes: {_tig},
      rank: 2,
      cause: Tx('Za duży prąd dla średnicy wolframu',
          'Current too high for the tungsten diameter'),
      check: Tx(
          'Np. 2,4 mm WC20 wg Kemppi: DC 140–230 A, AC 20–150 A. Końcówka '
              'się topi?',
          'E.g. 2.4 mm WC20 per Kemppi: DC 140–230 A, AC 20–150 A. Tip '
              'melting?'),
      fix: Tx(
          'Większa średnica elektrody albo mniejszy prąd (Fronius, CK); dobór '
              '— moduł „Elektroda wolframowa”.',
          'Larger electrode or lower current (Fronius, CK); selection — the '
              '“Tungsten electrode” tool.'),
      sources: ['kemppi-tig', 'fronius-tig', 'ck-tig'],
    ),
    DefectCause(
      id: 'tw-grind',
      processes: {_tig},
      rank: 3,
      cause: Tx(
          'Źle naszlifowana końcówka (rysy w poprzek, krzywy czubek)',
          'Poorly ground tip (cross-grinding marks, bent point)'),
      check: Tx('Rysy szlifowania biegną wzdłuż osi elektrody? Czubek prosty?',
          'Do the grinding marks run along the axis? Point straight?'),
      fix: Tx(
          'Szlifuj wzdłuż osi, na osobnej ściernicy diamentowej tylko do '
              'wolframu (Diamond Ground).',
          'Grind along the axis on a separate diamond wheel used only for '
              'tungsten (Diamond Ground).'),
      sources: ['dgp-tungsten'],
    ),
    DefectCause(
      id: 'tw-stickout',
      processes: {_tig},
      rank: 4,
      cause: Tx('Za duże wysunięcie wolframu z dyszy',
          'Tungsten sticking out too far from the cup'),
      check: Tx(
          'Miller: ok. 3,2–6,4 mm, nie więcej niż średnica dyszy; dalej tylko '
              'z soczewką gazową.',
          'Miller: approx. 3.2–6.4 mm, not more than the cup diameter; further '
              'only with a gas lens.'),
      fix: Tx('Skróć wysunięcie albo załóż soczewkę gazową (gas lens).',
          'Shorten the stickout or fit a gas lens.'),
      sources: ['miller-tig-basics', 'ck-tig'],
    ),
  ],
  repair: [
    _rCauseFirst,
    _rMark,
    _rRemove,
    _rConfirm,
    _rGroove,
    _rPreheat,
    _rWeld,
    _rNdt,
    _rLimit,
  ],
  cutOut: _cutInclusions,
  safety: [_sGrind, _sPt],
  checklist: [
    DefectStep(
      'tip-clean',
      Tx('Końcówka wolframu czysta, szlifowana wzdłuż osi',
          'Tungsten tip clean, ground along the axis'),
    ),
    DefectStep(
      'hf-start',
      Tx('Zajarzenie HF / lift-arc', 'HF / lift-arc start'),
    ),
    DefectStep(
      'size-current',
      Tx('Średnica wolframu dobrana do prądu',
          'Tungsten diameter suited to the current'),
    ),
    DefectStep(
      'stickout-cup',
      Tx('Wysunięcie nie większe niż średnica dyszy',
          'Stickout not more than the cup diameter'),
    ),
    DefectStep(
      'rod-gap',
      Tx('Pręt podawany bez dotykania elektrody',
          'Rod fed without touching the electrode'),
    ),
  ],
  repairSources: [..._repairSourcesStandard, 'fronius-hf'],
);

// ── 4xx Przyklejenie i brak przetopu ────────────────────────────────────────

const _lackOfFusion = WeldDefect(
  id: 'lack_of_fusion',
  group: DefectGroup.fusion,
  refs: [
    Iso6520Ref(401, 'Przyklejenie (brak wtopienia)', 'Lack of fusion'),
    Iso6520Ref(4011, 'Przyklejenie brzegowe', 'Lack of side-wall fusion'),
    Iso6520Ref(4012, 'Przyklejenie międzyściegowe', 'Lack of inter-run fusion'),
    Iso6520Ref(4013, 'Przyklejenie graniowe', 'Lack of root fusion'),
  ],
  title: Tx('Przyklejenie (brak wtopienia)', 'Lack of fusion'),
  looks: Tx(
    'Stopiwo nie zespoliło się ze ścianką rowka, z poprzednim ściegiem albo '
        'w grani. Z zewnątrz często niewidoczne — wykrywa je UT / RT, UT '
        'zwykle skuteczniej (TWI).',
    'The weld metal did not fuse with the groove wall, the previous run or at '
        'the root. Often invisible from outside — found by UT / RT, UT usually '
        'more effectively (TWI).',
  ),
  processes: _all,
  keywords: [
    'przyklejenie',
    'brak wtopienia',
    'zimny zaklad',
    'cold lap',
    'lack of fusion',
    'lof',
  ],
  causes: [
    DefectCause(
      id: 'lof-downhill',
      processes: {_mag, _fcg, _fcs},
      positions: {DefectPosition.pg, DefectPosition.pipeDown},
      rank: 1,
      cause: Tx('Spawanie z góry na dół — jeziorko wyprzedza łuk',
          'Vertical down — the pool runs ahead of the arc'),
      check: Tx(
          'Grubszy materiał spawany w dół? Miller: z góry na dół na cienki '
              'materiał, z dołu do góry od ok. 6,4 mm.',
          'Thicker material welded downhill? Miller: vertical down for thin '
              'material, vertical up from approx. 6.4 mm.'),
      fix: Tx(
          'Spawaj z dołu do góry, jeśli pozwala WPS (Kemppi); łuk na przedniej '
              'krawędzi jeziorka (Miller).',
          'Weld vertical up if the WPS allows it (Kemppi); keep the arc on the '
              'leading edge of the pool (Miller).'),
      sources: ['kemppi-defects', 'miller-fcaw', 'fronius-lsc'],
    ),
    DefectCause(
      id: 'lof-low-heat',
      processes: _all,
      rank: 1,
      cause: Tx('Za mały prąd albo za duża prędkość',
          'Current too low or travel speed too high'),
      check: Tx(
          'Prąd / napięcie / podawanie z WPS? Ścieg „leży” na ściance, brzegi '
              'nie wtopione?',
          'Current / voltage / wire feed as in the WPS? Bead sitting on the '
              'wall, edges not fused?'),
      fix: Tx(
          'Zwiększ prąd lub podawanie, zwolnij do umiarkowanej prędkości '
              '(TWI).',
          'Increase current or wire feed, slow down to a moderate speed '
              '(TWI).'),
      sources: ['twi-lof', 'twi-lof-faq'],
    ),
    DefectCause(
      id: 'lof-flooding',
      processes: {_mma, _mag, _fcg, _fcs, _mig, _saw},
      rank: 2,
      cause: Tx(
          'Jeziorko wyprzedza łuk i zalewa nieprzetopioną ściankę (za wolno '
              'przy dużym prądzie)',
          'The pool runs ahead of the arc and floods an unfused wall (too slow '
              'at high current)'),
      check: Tx('Łuk pracuje na ciekłym metalu, a nie na ściance?',
          'Is the arc playing on liquid metal instead of the wall?'),
      fix: Tx(
          'Trzymaj łuk na przedniej krawędzi jeziorka (Miller), przyspiesz '
              '(TWI).',
          'Keep the arc on the leading edge of the pool (Miller), speed up '
              '(TWI).'),
      sources: ['twi-lof', 'miller-defects'],
    ),
    DefectCause(
      id: 'lof-short-arc',
      processes: {_mag},
      rank: 2,
      cause: Tx('Łuk zwarciowy na grubym materiale — zimne jeziorko',
          'Short-circuit transfer on thick material — a cold pool'),
      check: Tx(
          'Wypełnienie lub pachwina na grubej blasze łukiem zwarciowym? '
              'Lincoln: Ar z 20–50 % CO2 daje zimniejsze jeziorko.',
          'Fill or fillet on thick plate in short arc? Lincoln: Ar with '
              '20–50 % CO2 gives a colder pool.'),
      fix: Tx(
          'Na grube przekroje łuk natryskowy / pulsacyjny albo parametry '
              'z WPS; zwarciowy wymaga stałego, krótkiego CTWD i starannej '
              'techniki (Hobart).',
          'For thick sections spray / pulsed transfer or the WPS settings; '
              'short arc needs a steady, short CTWD and careful technique '
              '(Hobart).'),
      sources: ['lincoln-mig', 'hobart-transfer'],
    ),
    DefectCause(
      id: 'lof-angle',
      processes: _hand,
      rank: 3,
      cause: Tx('Zły kąt palnika / elektrody albo za długi łuk',
          'Wrong torch / electrode angle or arc too long'),
      check: Tx('Łuk skierowany na ścianki? Kąt prowadzenia MAG 0–15° '
          '(Miller)?',
          'Arc aimed at the walls? MAG travel angle 0–15° (Miller)?'),
      fix: Tx(
          'Krótki łuk, kąt 0–15°, przy zakosach zatrzymanie przy ściankach '
              '(TWI).',
          'Short arc, 0–15° angle, a pause at the walls when weaving (TWI).'),
      sources: ['twi-lof-faq', 'miller-defects'],
    ),
    DefectCause(
      id: 'lof-narrow',
      processes: _all,
      rank: 3,
      cause: Tx(
          'Za wąski rowek — łuk (a w MAG dysza) nie sięga ścianek',
          'Groove too narrow — the arc (and in MAG the nozzle) cannot reach '
              'the walls'),
      check: Tx('Kąt rowka i szczelina zgodne z WPS?',
          'Groove angle and gap as in the WPS?'),
      fix: Tx('Przygotowanie wg WPS (moduł „Fazowanie”) (TWI).',
          'Preparation per the WPS (the “Bevel” tool) (TWI).'),
      sources: ['twi-lof'],
    ),
    DefectCause(
      id: 'lof-dirty',
      processes: _all,
      rank: 3,
      cause: Tx('Zgorzelina, olej lub tlenki na ściankach',
          'Mill scale, oil or oxide on the walls'),
      check: Tx('Ścianki i poprzedni ścieg oczyszczone do metalu?',
          'Walls and previous run cleaned to bright metal?'),
      fix: Tx('Oczyść do metalu przed spawaniem i między ściegami (TWI).',
          'Clean to bright metal before welding and between runs (TWI).'),
      sources: ['twi-lof'],
    ),
    DefectCause(
      id: 'lof-arc-blow',
      processes: _dc,
      rank: 4,
      cause: Tx('Dmuch magnetyczny — łuk odchyla się przy DC',
          'Magnetic arc blow — the arc deflects on DC'),
      check: Tx(
          'Łuk ucieka na bok, zwłaszcza przy końcach złącza i przy masie? '
              'Element namagnesowany?',
          'Does the arc swing sideways, especially at joint ends and near the '
              'earth? Is the part magnetised?'),
      fix: Tx(
          'TWI: krótki łuk, mniejszy prąd, w MMA spawaj w kierunku masy, kilka '
              'zacisków masy, owiń przewód wokół elementu, rozmagnesuj; AC '
              'zamiast DC tylko jeśli dopuszcza WPS.',
          'TWI: short arc, lower current, in MMA weld towards the earth, '
              'several earth clamps, wrap the cable around the part, '
              'demagnetise; AC instead of DC only if the WPS allows it.'),
      sources: ['twi-arc-blow'],
    ),
  ],
  repair: [
    _rCauseFirst,
    _rMark,
    _rRemove,
    _rGouge,
    _rConfirm,
    _rGroove,
    _rPreheat,
    _rWeld,
    _rNdt,
    _rLimit,
  ],
  cutOut: Tx(
    'Przyklejenie w grani rury bez dostępu od środka na dużej długości albo '
        'limit napraw wyczerpany — rozważ wycięcie złącza; decyduje '
        'specyfikacja.',
    'Lack of root fusion in a pipe without inside access over a long length '
        'or the repair limit used up — consider cutting the joint out; the '
        'specification decides.',
  ),
  safety: _safetyStandard,
  checklist: [
    DefectStep(
      'params',
      Tx('Prąd, napięcie i prędkość w zakresie WPS',
          'Current, voltage and travel speed within the WPS'),
    ),
    DefectStep(
      'walls-clean',
      Tx('Ścianki i poprzedni ścieg oczyszczone do metalu',
          'Walls and previous run cleaned to bright metal'),
    ),
    DefectStep(
      'arc-leading',
      Tx('Łuk na przedniej krawędzi jeziorka, kierowany na ścianki',
          'Arc on the leading edge of the pool, aimed at the walls'),
    ),
    DefectStep(
      'groove-wps',
      Tx('Kąt rowka i szczelina wg WPS', 'Groove angle and gap per the WPS'),
    ),
    DefectStep(
      'weave-pause',
      Tx('Przy zakosach zatrzymanie przy ściankach',
          'When weaving, pause at the walls'),
      processes: _hand,
    ),
  ],
  repairSources: _repairSourcesStandard,
);

const _lackOfPenetration = WeldDefect(
  id: 'lack_of_penetration',
  group: DefectGroup.fusion,
  refs: [
    Iso6520Ref(402, 'Brak przetopu (niepełny przetop)',
        'Lack of penetration (incomplete penetration)'),
    Iso6520Ref(4021, 'Niepełne przetopienie grani',
        'Incomplete root penetration'),
  ],
  title: Tx('Brak przetopu (niepełny przetop)', 'Lack of penetration'),
  looks: Tx(
    'Grań nie przetopiona na całej grubości — od strony grani widać '
        'niestopione krawędzie rowka.',
    'The root is not penetrated through the full thickness — the unmelted '
        'groove edges are visible from the root side.',
  ),
  processes: _all,
  keywords: [
    'brak przetopu',
    'nieprzetop',
    'gran',
    'lack of penetration',
    'incomplete penetration',
    'root',
  ],
  causes: [
    DefectCause(
      id: 'lop-prep',
      processes: _all,
      rank: 1,
      cause: Tx('Za mała szczelina albo za gruby próg',
          'Gap too small or root face too thick'),
      check: Tx(
          'Szczelina i próg wg WPS na całym obwodzie, także po sczepieniu?',
          'Gap and root face per the WPS all round, also after tacking?'),
      fix: Tx('Popraw przygotowanie i sczepienie (moduł „Fazowanie”) (TWI).',
          'Correct the preparation and tacking (the “Bevel” tool) (TWI).'),
      sources: ['twi-root'],
    ),
    DefectCause(
      id: 'lop-low-heat',
      processes: _all,
      rank: 1,
      cause: Tx('Za mały prąd lub za duża prędkość na graniu',
          'Root run current too low or speed too high'),
      check: Tx('Parametry grani zgodne z WPS?', 'Root settings as in the WPS?'),
      fix: Tx('Parametry grani z WPS, wolniej (TWI).',
          'Root settings from the WPS, slower (TWI).'),
      sources: ['twi-root'],
    ),
    DefectCause(
      id: 'lop-arc-blow',
      processes: _dc,
      rank: 3,
      cause: Tx('Dmuch magnetyczny odchyla łuk od grani',
          'Magnetic arc blow deflects the arc from the root'),
      check: Tx('Łuk ucieka na bok przy DC, zwłaszcza przy końcach złącza?',
          'Does the arc swing sideways on DC, especially at joint ends?'),
      fix: Tx(
          'TWI: krótki łuk, mniejszy prąd, przenieś masę lub kilka zacisków, '
              'rozmagnesuj; AC tylko jeśli dopuszcza WPS.',
          'TWI: short arc, lower current, move the earth or use several '
              'clamps, demagnetise; AC only if the WPS allows it.'),
      sources: ['twi-arc-blow'],
    ),
  ],
  repair: [
    _rCauseFirst,
    _rMark,
    DefectStep(
      'lop-side',
      Tx('Usuń wadę od strony, z której jest dostęp: od grani (wyszlifowanie '
              'i podspawanie) albo od lica — wycięcie do pełnej głębokości '
              'wady (TWI).',
          'Remove the defect from the accessible side: from the root '
              '(grinding and back welding) or from the face — excavation to '
              'the full depth of the defect (TWI).'),
    ),
    _rGouge,
    _rConfirm,
    _rGroove,
    _rPreheat,
    _rWeld,
    _rNdt,
    _rLimit,
  ],
  cutOut: Tx(
    'Rozważ wycięcie złącza, gdy brak przetopu obejmuje dużą część obwodu '
        'rury bez dostępu od środka albo limit napraw jest wyczerpany — '
        'decyduje specyfikacja.',
    'Consider cutting the joint out when the lack of penetration covers much '
        'of a pipe circumference with no inside access or the repair limit is '
        'used up — the specification decides.',
  ),
  safety: _safetyStandard,
  checklist: [
    DefectStep(
      'gap-after-tack',
      Tx('Szczelina i próg zmierzone po sczepieniu',
          'Gap and root face measured after tacking'),
    ),
    DefectStep(
      'root-params',
      Tx('Parametry grani wg WPS', 'Root settings per the WPS'),
    ),
    DefectStep(
      'no-offset',
      Tx('Krawędzie bez uskoku (centrownik)', 'Edges without offset (clamp)'),
    ),
    DefectStep(
      'root-clean',
      Tx('Krawędzie grani czyste, bez zgorzeliny',
          'Root edges clean, no mill scale'),
    ),
  ],
  repairSources: _repairSourcesStandard,
);

// ── 5xx Niezgodności kształtu i wymiarów ────────────────────────────────────

const _rMeasure5817 = DefectStep(
  'measure-5817',
  Tx('Zmierz wadę i porównaj z limitem EN ISO 5817 / specyfikacji (przycisk '
          '„Zobacz limit wg ISO 5817”).',
      'Measure the defect and compare it with the EN ISO 5817 / specification '
          'limit (the “See the ISO 5817 limit” button).'),
);

const _undercut = WeldDefect(
  id: 'undercut',
  group: DefectGroup.shape,
  refs: [
    Iso6520Ref(5011, 'Podtopienie ciągłe', 'Continuous undercut'),
    Iso6520Ref(5012, 'Podtopienie przerywane', 'Intermittent undercut'),
    Iso6520Ref(5013, 'Podtopienie grani (rowek skurczowy)', 'Shrinkage groove'),
  ],
  title: Tx('Podtopienie', 'Undercut'),
  looks: Tx(
    'Rowek wytopiony w materiale wzdłuż brzegu lica (przy 5013 — wzdłuż '
        'brzegów grani); osłabia przekrój i działa jak karb.',
    'A groove melted into the parent metal along the weld toe (for 5013 — '
        'along the root edges); it weakens the section and acts as a notch.',
  ),
  processes: _all,
  keywords: ['podtopienie', 'podciecie', 'rowek skurczowy', 'undercut'],
  causes: [
    DefectCause(
      id: 'uc-pb-pc',
      processes: _hand,
      positions: {DefectPosition.pb, DefectPosition.pc},
      rank: 1,
      cause: Tx(
          'PB / PC: metal spływa z górnego brzegu (ścianka pionowa)',
          'PB / PC: metal runs down off the upper toe (vertical member)'),
      check: Tx('Podtopiony tylko górny brzeg / ścianka pionowa pachwiny?',
          'Only the upper toe / vertical member of the fillet undercut?'),
      fix: Tx(
          'Opuść kąt roboczy o 0–15° w stronę górnej blachy i zatrzymaj się '
              'chwilę przy górnym brzegu (Miller); palnik ustawiony tak, by '
              'wpychał metal w brzeg (TWI).',
          'Lower the work angle by 0–15° towards the upper plate and pause '
              'briefly at the upper toe (Miller); hold the torch so it pushes '
              'metal into the toe (TWI).'),
      sources: ['twi-shape1', 'miller-fcaw'],
    ),
    DefectCause(
      id: 'uc-current-speed',
      processes: _all,
      rank: 1,
      cause: Tx(
          'Szeroki łuk (wysokie napięcie) przy za małym wypełnieniu: za '
              'szybko albo za mały prąd',
          'A wide arc (high voltage) with too little fill: too fast or too '
              'little current'),
      check: Tx(
          'Podtopienie ciągłe wzdłuż obu brzegów? Prąd, napięcie, prędkość '
              'z WPS?',
          'Continuous undercut along both toes? Current, voltage, speed as in '
              'the WPS?'),
      fix: Tx(
          'Zwolnij i / lub zmniejsz prąd, utrzymaj właściwą długość łuku '
              '(TWI).',
          'Slow down and / or reduce the current, keep the correct arc length '
              '(TWI).'),
      sources: ['twi-shape1', 'miller-defects'],
    ),
    DefectCause(
      id: 'uc-long-arc',
      processes: _hand,
      rank: 2,
      cause: Tx('Za długi łuk', 'Arc too long'),
      check: Tx(
          'MMA: łuk dłuższy niż średnica rdzenia elektrody (Miller)? MAG '
              'natryskowy: łuk wyraźnie długi (Hobart)?',
          'MMA: arc longer than the electrode core diameter (Miller)? MAG '
              'spray: arc clearly long (Hobart)?'),
      fix: Tx('Skróć łuk / obniż napięcie (TWI, Kemppi).',
          'Shorten the arc / lower the voltage (TWI, Kemppi).'),
      sources: [
        'twi-shape1',
        'miller-stick',
        'hobart-transfer',
        'kemppi-defects',
      ],
    ),
    DefectCause(
      id: 'uc-weave',
      processes: _hand,
      rank: 2,
      cause: Tx('Za szeroki zakos bez zatrzymania na brzegach',
          'Weave too wide without a pause at the edges'),
      check: Tx('Podtopienie tylko przy brzegach ściegu zakosowego?',
          'Undercut only at the edges of a weaved run?'),
      fix: Tx(
          'Zatrzymaj się chwilę na każdym brzegu; przy szerokim rowku kilka '
              'ściegów zamiast jednego zakosu (Kemppi, Bernard).',
          'Pause briefly at each edge; in a wide groove several runs instead '
              'of one weave (Kemppi, Bernard).'),
      sources: ['kemppi-defects', 'bernard-gmaw'],
    ),
    DefectCause(
      id: 'uc-angle',
      processes: _all,
      rank: 3,
      cause: Tx(
          'Zły kąt palnika / elektrody — łuk kierowany na jedną ściankę',
          'Wrong torch / electrode angle — the arc aimed at one wall'),
      check: Tx(
          'Kąt roboczy w złączu teowym ok. 45°, kąt prowadzenia 5–15° '
              '(Miller)?',
          'Work angle in a T-joint approx. 45°, travel angle 5–15° (Miller)?'),
      fix: Tx(
          'Ustaw kąty wg WPS / instruktażu; powyżej 20–25° kąta prowadzenia '
              'więcej rozprysku i płytszy przetop (Miller).',
          'Set the angles per the WPS / instructions; above 20–25° travel '
              'angle there is more spatter and less penetration (Miller).'),
      sources: ['miller-mig-basics', 'twi-shape1'],
    ),
  ],
  repair: [
    _rCauseFirst,
    _rMeasure5817,
    _rGrindSmooth,
    _rAddRun,
    _rPreheat,
    _rNdt,
  ],
  cutOut: Tx(
    'Zwykle niepotrzebne — podtopienie naprawia się szlifowaniem lub '
        'dodatkowym ściegiem (TWI); wycięcie rozważ, gdy ścianka po naprawie '
        'byłaby poniżej grubości minimalnej — decyduje specyfikacja.',
    'Usually not needed — undercut is repaired by grinding or an extra run '
        '(TWI); consider cutting out when the wall after repair would be below '
        'the minimum thickness — the specification decides.',
  ),
  safety: [_sGrind, _sPreheat],
  checklist: [
    DefectStep(
      'params',
      Tx('Prąd i prędkość wg WPS', 'Current and travel speed per the WPS'),
    ),
    DefectStep(
      'short-arc',
      Tx('Krótki łuk', 'Short arc'),
      processes: _hand,
    ),
    DefectStep(
      'saw-voltage',
      Tx('Napięcie łuku wg WPS', 'Arc voltage per the WPS'),
      processes: {_saw},
    ),
    DefectStep(
      'weave-pause',
      Tx('Zatrzymanie na brzegach przy zakosie', 'Pause at the edges when '
          'weaving'),
      processes: _hand,
    ),
    DefectStep(
      'angle-toe',
      Tx('Kąt palnika / elektrody w stronę brzegu',
          'Torch / electrode angled towards the toe'),
    ),
    DefectStep(
      'pb-pc-upper',
      Tx('PB / PC: łuk lekko w stronę górnej blachy',
          'PB / PC: arc slightly towards the upper plate'),
      processes: _hand,
    ),
  ],
  repairSources: ['twi-shape1'],
);

const _excessWeldMetal = WeldDefect(
  id: 'excess_weld_metal',
  group: DefectGroup.shape,
  refs: [
    Iso6520Ref(502, 'Nadmierny nadlew lica spoiny czołowej',
        'Excess weld metal (butt weld)'),
    Iso6520Ref(505, 'Nieprawidłowy kąt przejścia lica', 'Incorrect weld toe'),
  ],
  title: Tx('Nadmierny nadlew lica', 'Excess weld metal'),
  looks: Tx(
    'Lico za wysokie, z ostrym przejściem w materiał — ostre przejście to '
        'koncentracja naprężeń i niższa trwałość zmęczeniowa (TWI).',
    'The cap is too high with a sharp transition into the parent metal — a '
        'sharp toe concentrates stress and lowers fatigue life (TWI).',
  ),
  processes: _all,
  keywords: ['nadlew', 'wysokie lico', 'kat przejscia', 'excess', 'cap', 'toe'],
  causes: [
    DefectCause(
      id: 'ew-feed-speed',
      processes: _all,
      rank: 1,
      cause: Tx('Za dużo spoiwa w stosunku do prędkości (za wolno)',
          'Too much filler for the travel speed (too slow)'),
      check: Tx('Lico wyraźnie nad materiałem? Prędkość zgodna z WPS?',
          'Cap well above the plate? Travel speed as in the WPS?'),
      fix: Tx(
          'Szybciej lub mniej spoiwa (Kemppi); przy spawaniu zmechanizowanym '
              'większa prędkość albo wyższe napięcie (TWI).',
          'Faster or less filler (Kemppi); in mechanised welding higher '
              'travel speed or higher voltage (TWI).'),
      sources: ['twi-shape1', 'kemppi-defects'],
    ),
    DefectCause(
      id: 'ew-cold',
      processes: _wire,
      rank: 2,
      cause: Tx(
          'Za zimne parametry — wypukły, „sznurkowy” ścieg bez zwilżenia '
              'brzegów',
          'Too cold settings — a convex, ropy bead that does not wet the '
              'edges'),
      check: Tx('Ścieg wąski i wysoki, brzegi nie rozpływają się?',
          'Bead narrow and high, edges not wetting out?'),
      fix: Tx('Podnieś napięcie (Miller).', 'Raise the voltage (Miller).'),
      sources: ['miller-defects'],
    ),
    DefectCause(
      id: 'ew-run-plan',
      processes: _all,
      rank: 2,
      cause: Tx(
          'Źle rozplanowane ściegi — rowek przepełniony ostatnim ściegiem',
          'Poorly planned runs — the groove overfilled by the last run'),
      check: Tx('Przed licem rowek był już prawie pełny?',
          'Was the groove nearly full before the cap?'),
      fix: Tx(
          'Zaplanuj ściegi tak, by na lico zostało niewiele; mniejsza '
              'elektroda (Kemppi).',
          'Plan the runs so little is left for the cap; a smaller electrode '
              '(Kemppi).'),
      sources: ['twi-shape1', 'kemppi-defects'],
    ),
    DefectCause(
      id: 'ew-groove',
      processes: _all,
      rank: 3,
      cause: Tx('Za wąski lub nieukosowany rowek',
          'Groove too narrow or not bevelled'),
      check: Tx('Kąt rowka zgodny z WPS?', 'Groove angle as in the WPS?'),
      fix: Tx('Większy kąt rowka wg WPS (Kemppi).',
          'A wider groove angle per the WPS (Kemppi).'),
      sources: ['kemppi-defects'],
    ),
    DefectCause(
      id: 'ew-mma-slow',
      processes: {_mma},
      rank: 3,
      cause: Tx('MMA: za wolno — szeroki, wypukły ścieg',
          'MMA: too slow — a wide, convex bead'),
      check: Tx('Ścieg szeroki i wypukły przy płytkim przetopie?',
          'Bead wide and convex with shallow penetration?'),
      fix: Tx(
          'Prędkość wg WPS; za szybko z kolei daje ścieg wąski i wysoki '
              '(Miller).',
          'Travel speed per the WPS; too fast in turn gives a narrow, high '
              'bead (Miller).'),
      sources: ['miller-stick'],
    ),
  ],
  repair: [
    _rCauseFirst,
    _rMeasure5817,
    DefectStep(
      'ew-grind',
      Tx('Nadmiar lica zeszlifuj z łagodnym przejściem w materiał, bez zejścia '
              'poniżej jego powierzchni.',
          'Grind the excess cap to a smooth transition into the parent metal '
              'without going below its surface.'),
    ),
    _rNdt,
  ],
  cutOut: Tx('Nie dotyczy — nadlew koryguje się szlifowaniem.',
      'Not applicable — excess metal is corrected by grinding.'),
  safety: [_sGrind],
  checklist: [
    DefectStep(
      'speed',
      Tx('Prędkość wg WPS', 'Travel speed per the WPS'),
    ),
    DefectStep(
      'cap-plan',
      Tx('Ściegi rozplanowane — na lico zostało niewiele',
          'Runs planned — little left for the cap'),
    ),
    DefectStep(
      'voltage-ok',
      Tx('Napięcie nie za niskie (ścieg zwilża brzegi)',
          'Voltage not too low (bead wets the edges)'),
      processes: _wire,
    ),
    DefectStep(
      'smooth-toe',
      Tx('Lico z łagodnym przejściem w materiał',
          'Cap with a smooth transition into the plate'),
    ),
  ],
  repairSources: ['twi-shape1'],
);

const _excessPenetration = WeldDefect(
  id: 'excess_penetration',
  group: DefectGroup.shape,
  refs: [
    Iso6520Ref(504, 'Nadmierny przetop (wyciek grani)', 'Excess penetration'),
  ],
  title: Tx('Nadmierny przetop (wyciek grani)', 'Excess penetration'),
  looks: Tx(
    'Za wysoki nadlew grani, czasem sople stopiwa po stronie grani — w rurze '
        'zwęża przekrój.',
    'Root reinforcement too high, sometimes icicles on the root side — in a '
        'pipe it narrows the bore.',
  ),
  processes: _all,
  keywords: ['wyciek', 'sople', 'nadmierny przetop', 'excess penetration',
      'icicles'],
  causes: [
    DefectCause(
      id: 'ep-gap',
      processes: _all,
      rank: 1,
      cause: Tx('Za duża szczelina albo za mały próg',
          'Gap too large or root face too small'),
      check: Tx('Szczelina i próg zgodne z WPS?',
          'Gap and root face as in the WPS?'),
      fix: Tx('Popraw przygotowanie i sczepienie (TWI).',
          'Correct the preparation and tacking (TWI).'),
      sources: ['twi-shape2'],
    ),
    DefectCause(
      id: 'ep-heat',
      processes: _all,
      rank: 1,
      cause: Tx('Za dużo ciepła na graniu (prąd, za wolno)',
          'Too much heat on the root (current, too slow)'),
      check: Tx('Parametry grani z WPS? Grań zwisa tam, gdzie się '
          'zatrzymałeś?',
          'Root settings as in the WPS? Root sagging where you stopped?'),
      fix: Tx('Mniejszy prąd, szybciej, bez zatrzymań na graniu (TWI).',
          'Lower current, faster, no stops on the root (TWI).'),
      sources: ['twi-shape2'],
    ),
    DefectCause(
      id: 'ep-ctwd',
      processes: _gasWire,
      rank: 2,
      cause: Tx('Za krótki wylot drutu — rośnie prąd',
          'Stickout too short — the current rises'),
      check: Tx(
          'Miller: krótszy CTWD = większy prąd (przykład: 5/8" → 1" obniżyło '
              'prąd z 282 A do 213 A).',
          'Miller: shorter CTWD = higher current (example: 5/8" → 1" lowered '
              'the current from 282 A to 213 A).'),
      fix: Tx('Trzymaj stały wylot z WPS.', 'Keep a steady stickout per the '
          'WPS.'),
      sources: ['miller-stickout'],
    ),
  ],
  repair: [
    _rCauseFirst,
    _rMeasure5817,
    DefectStep(
      'ep-grind',
      Tx('Nadmiar grani zeszlifuj od środka z łagodnym przejściem, jeśli jest '
              'dostęp.',
          'Grind the excess root from the inside to a smooth transition if '
              'there is access.'),
    ),
    _rNdt,
  ],
  cutOut: Tx(
    'Wyciek w rurze bez dostępu od środka ponad limit EN ISO 5817 / '
        'specyfikacji — wycięcie spoiny.',
    'Excess penetration in a pipe with no inside access above the EN ISO '
        '5817 / specification limit — cut the weld out.',
  ),
  safety: [_sGrind],
  checklist: [
    DefectStep(
      'gap-root-face',
      Tx('Szczelina i próg wg WPS', 'Gap and root face per the WPS'),
    ),
    DefectStep(
      'root-params',
      Tx('Parametry grani wg WPS', 'Root settings per the WPS'),
    ),
    DefectStep(
      'steady-speed',
      Tx('Równa prędkość na graniu, bez zatrzymań',
          'Steady speed on the root, no stops'),
    ),
    DefectStep(
      'steady-stickout',
      Tx('Stały wylot drutu', 'Steady wire stickout'),
      processes: _wire,
    ),
  ],
  repairSources: ['twi-shape2'],
);

const _overlap = WeldDefect(
  id: 'overlap',
  group: DefectGroup.shape,
  refs: [Iso6520Ref(506, 'Nawis', 'Overlap')],
  title: Tx('Nawis', 'Overlap'),
  looks: Tx(
    'Stopiwo wylane na materiał przy brzegu spoiny bez zespolenia z nim '
        '(zimny zakład).',
    'Weld metal flowed onto the parent metal at the toe without fusing with '
        'it (cold lap).',
  ),
  processes: _all,
  keywords: ['nawis', 'zimny zaklad', 'overlap', 'cold lap', 'rollover'],
  causes: [
    DefectCause(
      id: 'ov-pb-pc',
      processes: _hand,
      positions: {DefectPosition.pb, DefectPosition.pc},
      rank: 1,
      cause: Tx('PB / PC: stopiwo przewala się na dolny brzeg',
          'PB / PC: metal rolls over onto the lower toe'),
      check: Tx('Kąt roboczy za wysoko, jeziorko za duże?',
          'Work angle too high, pool too large?'),
      fix: Tx(
          'Opuść kąt roboczy o 0–15° (Miller), węższe ściegi zamiast '
              'szerokiego zakosu.',
          'Lower the work angle by 0–15° (Miller), narrower runs instead of '
              'a wide weave.'),
      sources: ['miller-auto', 'miller-fcaw'],
    ),
    DefectCause(
      id: 'ov-pool',
      processes: _all,
      rank: 1,
      cause: Tx(
          'Za duże, „zimne” jeziorko spływa (za wolno, za dużo stopiwa)',
          'A large, cold pool sags (too slow, too much metal)'),
      check: Tx('Nawis przy dolnym brzegu albo przy wolnym prowadzeniu?',
          'Overlap at the lower toe or when travelling slowly?'),
      fix: Tx('Mniejsze jeziorko: niższy prąd albo szybszy posuw (TWI).',
          'A smaller pool: lower current or faster travel (TWI).'),
      sources: ['twi-shape1', 'twi-fillet'],
    ),
    DefectCause(
      id: 'ov-technique',
      processes: _hand,
      rank: 2,
      cause: Tx('Złe prowadzenie elektrody / palnika',
          'Poor electrode / torch manipulation'),
      check: Tx('Kąt i ruch zgodne z instruktażem / WPS?',
          'Angle and motion as instructed / in the WPS?'),
      fix: Tx('Popraw technikę — TWI: to głównie umiejętności spawacza.',
          'Improve the technique — TWI: it is mainly welder skill.'),
      sources: ['twi-shape1'],
    ),
    DefectCause(
      id: 'ov-oxide',
      processes: _all,
      rank: 3,
      cause: Tx(
          'Mocno przylegające tlenki lub zgorzelina — stopiwo nie zwilża '
              'materiału',
          'Tenacious oxide or mill scale — the weld metal does not wet the '
              'plate'),
      check: Tx('Brzegi oczyszczone do metalu?', 'Edges cleaned to bright '
          'metal?'),
      fix: Tx('Oczyść materiał do metalu (TWI).',
          'Clean the plate to bright metal (TWI).'),
      sources: ['twi-shape1'],
    ),
  ],
  repair: [
    _rCauseFirst,
    DefectStep(
      'ov-grind',
      Tx('Zeszlifuj nawis do łagodnego przejścia i sprawdź brzeg PT / MT — '
              'pod nawisem nie może zostać przyklejenie ani podtopienie.',
          'Grind the overlap to a smooth transition and check the toe by PT / '
              'MT — no lack of fusion or undercut may remain under it.'),
    ),
    _rAddRun,
    _rNdt,
  ],
  cutOut: Tx(
    'Zwykle niepotrzebne — nawis usuwa się szlifowaniem; gdy pod nim jest '
        'przyklejenie, napraw jak przyklejenie.',
    'Usually not needed — overlap is ground off; if there is lack of fusion '
        'under it, repair it as lack of fusion.',
  ),
  safety: [_sGrind, _sPt],
  checklist: [
    DefectStep(
      'pool-size',
      Tx('Jeziorko nie za duże (prąd / prędkość wg WPS)',
          'Pool not too large (current / speed per the WPS)'),
    ),
    DefectStep(
      'run-plan',
      Tx('Ściegi ułożone wg planu, bez przepełniania',
          'Runs laid as planned, no overfilling'),
    ),
    DefectStep(
      'edges-clean',
      Tx('Brzegi oczyszczone ze zgorzeliny', 'Edges cleaned of mill scale'),
    ),
    DefectStep(
      'pb-pc-angle',
      Tx('PB / PC: kąt roboczy opuszczony w stronę górnej blachy',
          'PB / PC: work angle lowered towards the upper plate'),
      processes: _hand,
    ),
    DefectStep(
      'narrow-runs',
      Tx('Węższe ściegi zamiast szerokiego zakosu',
          'Narrower runs instead of a wide weave'),
      processes: _hand,
    ),
  ],
  repairSources: ['twi-shape1', 'magnaflux-sds'],
);

const _misalignment = WeldDefect(
  id: 'misalignment',
  group: DefectGroup.shape,
  refs: [
    Iso6520Ref(507, 'Przesunięcie liniowe', 'Linear misalignment'),
    Iso6520Ref(5071, 'Przesunięcie liniowe blach',
        'Linear misalignment between plates'),
    Iso6520Ref(5072, 'Przesunięcie liniowe rur',
        'Linear misalignment between tubes'),
  ],
  title: Tx('Przesunięcie liniowe (uskok krawędzi)', 'Linear misalignment '
      '(hi-lo)'),
  looks: Tx(
    'Krawędzie łączonych elementów nie leżą w jednej płaszczyźnie — uskok '
        'między blachami lub rurami.',
    'The edges of the joined parts are not level — a step between the plates '
        'or pipes.',
  ),
  processes: _all,
  keywords: ['uskok', 'przesuniecie', 'hi lo', 'hilo', 'misalignment',
      'offset', 'centrownik'],
  causes: [
    DefectCause(
      id: 'mis-fit',
      processes: _all,
      rank: 1,
      cause: Tx('Złe dopasowanie przed sczepieniem', 'Poor fit-up before '
          'tacking'),
      check: Tx(
          'Uskok zmierzony na obwodzie w kilku miejscach (np. w 4 '
              'ćwiartkach)?',
          'Offset measured at several points round the joint (e.g. in 4 '
              'quadrants)?'),
      fix: Tx(
          'Ustaw ponownie centrownikiem — wewnętrznym przy dużych średnicach, '
              'zewnętrznym, gdy wewnętrznego nie da się użyć (API 1104); '
              'limity — EN ISO 5817.',
          'Re-align with a clamp — internal on large diameters, external when '
              'an internal one cannot be used (API 1104); limits — EN ISO '
              '5817.'),
      sources: ['api-1104-alignment', 'twi-shape1'],
    ),
    DefectCause(
      id: 'mis-oval',
      processes: _all,
      rank: 2,
      cause: Tx(
          'Owalizacja rur lub różne grubości / tolerancje elementów',
          'Pipe ovality or different wall thickness / tolerances'),
      check: Tx('Różne ścianki (np. rura i kształtka)? Rura owalna?',
          'Different walls (e.g. pipe and fitting)? Pipe oval?'),
      fix: Tx(
          'Rozłóż uskok równomiernie na obwodzie; przy różnych grubościach '
              'przejście z pochyleniem wg rysunku — np. ASME B31.8: '
              'wewnętrzne pochylenie najwyżej 1:4 (Wermac).',
          'Spread the offset evenly round the joint; with different '
              'thicknesses a taper per the drawing — e.g. ASME B31.8: inside '
              'taper at most 1:4 (Wermac).'),
      sources: ['wermac-wall', 'twi-shape1', 'kemppi-defects'],
    ),
    DefectCause(
      id: 'mis-tacks',
      processes: _all,
      rank: 2,
      cause: Tx('Pękające lub za słabe szczepiny, odkształcenie przy spawaniu',
          'Cracking or weak tacks, distortion during welding'),
      check: Tx('Szczepiny pękły, szczelina się zamyka?',
          'Tacks cracked, gap closing?'),
      fix: Tx(
          'Poprawne szczepiny, sztywne mocowanie i kolejność spawania '
              '(Kemppi).',
          'Proper tacks, rigid fixturing and welding sequence (Kemppi).'),
      sources: ['kemppi-defects', 'twi-shape1'],
    ),
  ],
  repair: [
    _rMeasure5817,
    DefectStep(
      'mis-refit',
      Tx('Przed spawaniem: rozetnij szczepiny i ustaw ponownie. Po spawaniu '
              'nadmiernego uskoku nie usuwa się szlifowaniem kosztem ścianki — '
              'decyzja wg specyfikacji / inspektora.',
          'Before welding: cut the tacks and re-align. After welding, '
              'excessive offset is not removed by grinding away the wall — '
              'decision per the specification / inspector.'),
    ),
    _rNdt,
  ],
  cutOut: Tx(
    'Uskok po spawaniu ponad limit EN ISO 5817 / specyfikacji — wycięcie '
        'spoiny i ponowne dopasowanie, chyba że specyfikacja pozwala inaczej.',
    'Offset after welding above the EN ISO 5817 / specification limit — cut '
        'the weld out and re-fit, unless the specification allows otherwise.',
  ),
  safety: [_sGrind],
  checklist: [
    DefectStep(
      'offset-measured',
      Tx('Uskok zmierzony w kilku miejscach obwodu',
          'Offset measured at several points round the joint'),
    ),
    DefectStep(
      'clamp',
      Tx('Centrownik / mocowanie przed sczepieniem',
          'Clamp / fixture before tacking'),
    ),
    DefectStep(
      'tacks-sound',
      Tx('Szczepiny całe, bez pęknięć', 'Tacks sound, no cracks'),
    ),
    DefectStep(
      'taper',
      Tx('Różne grubości: przejście wg rysunku',
          'Different thickness: taper per the drawing'),
    ),
  ],
  repairSources: ['twi-shape1', 'api-1104-alignment'],
);

const _sagging = WeldDefect(
  id: 'sagging',
  group: DefectGroup.shape,
  refs: [Iso6520Ref(509, 'Zwis', 'Sagging')],
  title: Tx('Zwis', 'Sagging'),
  looks: Tx(
    'Stopiwo opadło pod własnym ciężarem — ścieg zwisa, najczęściej '
        'w pozycji naściennej (PC) i pułapowej (PE) (Miller).',
    'The weld metal has sagged under its own weight — the run hangs down, '
        'most often in the horizontal (PC) and overhead (PE) positions '
        '(Miller).',
  ),
  processes: _hand,
  keywords: ['zwis', 'opadniecie', 'sagging', 'sag'],
  causes: [
    DefectCause(
      id: 'sag-pc',
      processes: _hand,
      positions: {DefectPosition.pc, DefectPosition.pb},
      rank: 1,
      cause: Tx('PC / PB: jeziorko spływa na dolny brzeg',
          'PC / PB: the pool runs down to the lower toe'),
      check: Tx('Ścieg ciężki przy dolnym brzegu, górny podtopiony?',
          'Run heavy at the lower toe, upper toe undercut?'),
      fix: Tx(
          'Opuść kąt roboczy o 0–15° (Miller), mniej ciepła, krótki łuk, '
              'węższe ściegi zamiast szerokiego zakosu.',
          'Lower the work angle by 0–15° (Miller), less heat, a short arc, '
              'narrower runs instead of a wide weave.'),
      sources: ['miller-auto', 'miller-fcaw'],
    ),
    DefectCause(
      id: 'sag-overhead',
      processes: _hand,
      positions: {
        DefectPosition.pe,
        DefectPosition.pd,
        DefectPosition.pipeUp,
        DefectPosition.pipeDown,
      },
      rank: 1,
      cause: Tx('Pułap: za duże jeziorko', 'Overhead: pool too large'),
      check: Tx('Spawasz w pułapie z parametrami jak w podolnej?',
          'Welding overhead with flat-position settings?'),
      fix: Tx(
          'Miller: w pułapie parametry niżej o 10–15 %, szybszy posuw, krótkie '
              'ściegi; drut proszkowy — o 15–20 %, najcieńszy drut, minimum '
              'zakosu; MMA — ok. 15 % mniej ciepła niż w podolnej.',
          'Miller: overhead settings 10–15 % lower, faster travel, short runs; '
              'flux-cored — 15–20 % lower, the thinnest wire, minimal weave; '
              'MMA — approx. 15 % less heat than flat.'),
      sources: ['miller-auto', 'miller-fcaw', 'miller-stick'],
    ),
    DefectCause(
      id: 'sag-heat',
      processes: _hand,
      rank: 2,
      cause: Tx('Za dużo stopiwa w jednym ściegu (za wolno, za duży prąd)',
          'Too much metal in one run (too slow, too much current)'),
      check: Tx('Jeden gruby ścieg tam, gdzie WPS przewiduje kilka?',
          'One thick run where the WPS has several?'),
      fix: Tx('Cieńsze ściegi, szybciej, prąd wg WPS — mniejsze jeziorko '
          '(TWI).',
          'Thinner runs, faster, current per the WPS — a smaller pool '
              '(TWI).'),
      sources: ['twi-shape1', 'miller-auto'],
    ),
  ],
  repair: [_rCauseFirst, _rMeasure5817, _rGrindSmooth, _rAddRun, _rNdt],
  cutOut: Tx(
    'Zwykle niepotrzebne — zwis koryguje się szlifowaniem i ewentualnie '
        'dodatkowym ściegiem.',
    'Usually not needed — sagging is corrected by grinding and, if needed, '
        'an extra run.',
  ),
  safety: [_sGrind],
  checklist: [
    DefectStep(
      'position-params',
      Tx('Parametry dla pozycji wg WPS (niżej niż w podolnej)',
          'Settings for the position per the WPS (lower than flat)'),
    ),
    DefectStep(
      'thin-runs',
      Tx('Węższe, cieńsze ściegi', 'Narrower, thinner runs'),
    ),
    DefectStep(
      'pc-angle',
      Tx('PC: kąt roboczy opuszczony w stronę górnej blachy',
          'PC: work angle lowered towards the upper plate'),
    ),
    DefectStep(
      'short-arc',
      Tx('Krótki łuk', 'Short arc'),
    ),
  ],
  repairSources: ['twi-shape1'],
);

const _burnThrough = WeldDefect(
  id: 'burn_through',
  group: DefectGroup.shape,
  refs: [Iso6520Ref(510, 'Przepalenie', 'Burn through')],
  title: Tx('Przepalenie', 'Burn through'),
  looks: Tx(
    'Dziura w spoinie po wypłynięciu jeziorka; najczęściej na cienkim '
        'materiale i w grani.',
    'A hole in the weld where the pool fell through; most often on thin '
        'material and in the root.',
  ),
  processes: _all,
  keywords: ['przepalenie', 'dziura', 'burn through', 'burnthrough', 'hole'],
  causes: [
    DefectCause(
      id: 'bt-heat',
      processes: _all,
      rank: 1,
      cause: Tx('Za dużo ciepła na cienkim materiale',
          'Too much heat on thin material'),
      check: Tx(
          'Miller: przepalenia zwykle przy materiale poniżej 3,2 mm. '
              'Parametry dla tej grubości z WPS?',
          'Miller: burn-through usually on material under 3.2 mm. Settings '
              'for this thickness from the WPS?'),
      fix: Tx('Obniż napięcie i podawanie (prąd), przyspiesz (Miller).',
          'Lower the voltage and wire feed (current), travel faster '
              '(Miller).'),
      sources: ['miller-defects'],
    ),
    DefectCause(
      id: 'bt-gap',
      processes: _all,
      rank: 1,
      cause: Tx('Za duża szczelina', 'Gap too large'),
      check: Tx('Szczelina większa niż w WPS?', 'Gap larger than in the WPS?'),
      fix: Tx(
          'Popraw dopasowanie; przy dużej szczelinie dłuższy wylot drutu lub '
              'zakosy (Bernard), podkładka tylko gdy dopuszcza WPS.',
          'Correct the fit-up; with a large gap a longer stickout or weaving '
              '(Bernard), a backing only if the WPS allows it.'),
      sources: ['bernard-gmaw', 'unimig-burn'],
    ),
    DefectCause(
      id: 'bt-slow',
      processes: _all,
      rank: 2,
      cause: Tx('Za wolno albo zatrzymania w jednym miejscu',
          'Too slow or stopping in one place'),
      check: Tx('Dziura tam, gdzie zwolniłeś lub zrobiłeś zakos?',
          'A hole where you slowed down or weaved?'),
      fix: Tx(
          'Szybszy posuw (nie tak szybki, by podtapiać), ściegi proste zamiast '
              'zakosu, odbierak ciepła z miedzi przy cienkiej blasze (UNIMIG).',
          'Faster travel (not so fast that it undercuts), stringer runs '
              'instead of weaving, a copper heat sink on thin sheet (UNIMIG).'),
      sources: ['unimig-burn'],
    ),
    DefectCause(
      id: 'bt-ctwd',
      processes: _gasWire,
      rank: 3,
      cause: Tx('Za krótki wylot drutu — rośnie prąd',
          'Stickout too short — the current rises'),
      check: Tx('Palnik bliżej materiału niż w WPS?',
          'Torch closer to the work than in the WPS?'),
      fix: Tx('Stały wylot z WPS — za krótki CTWD grozi przepaleniem (Miller).',
          'A steady stickout per the WPS — too short a CTWD risks '
              'burn-through (Miller).'),
      sources: ['miller-stickout'],
    ),
  ],
  repair: [
    _rCauseFirst,
    _rMark,
    DefectStep(
      'bt-clean',
      Tx('Oszlifuj brzegi dziury do zdrowego metalu i nadaj kształt rowka.',
          'Grind the edges of the hole back to sound metal and shape a '
              'groove.'),
    ),
    _rPreheat,
    _rWeld,
    _rNdt,
    _rLimit,
  ],
  cutOut: Tx(
    'Rozważ wycięcie, gdy przepalenie w grani rury zostawiło stopiwo w środku '
        'bez dostępu do usunięcia albo limit napraw jest wyczerpany — decyduje '
        'specyfikacja.',
    'Consider cutting out when burn-through in a pipe root left metal inside '
        'with no access to remove it or the repair limit is used up — the '
        'specification decides.',
  ),
  safety: [_sGrind, _sPreheat],
  checklist: [
    DefectStep(
      'gap-wps',
      Tx('Szczelina wg WPS', 'Gap per the WPS'),
    ),
    DefectStep(
      'thickness-params',
      Tx('Parametry dla tej grubości', 'Settings for this thickness'),
    ),
    DefectStep(
      'steady-travel',
      Tx('Równy posuw, bez zatrzymań', 'Steady travel, no stops'),
    ),
    DefectStep(
      'steady-stickout',
      Tx('Stały wylot drutu', 'Steady wire stickout'),
      processes: _wire,
    ),
  ],
  repairSources: [..._repairSourcesStandard, 'unimig-burn'],
);

const _incompleteFill = WeldDefect(
  id: 'incomplete_fill',
  group: DefectGroup.shape,
  refs: [
    Iso6520Ref(511, 'Niecałkowite wypełnienie rowka',
        'Incompletely filled groove'),
  ],
  title: Tx('Niecałkowite wypełnienie rowka', 'Incompletely filled groove'),
  looks: Tx(
    'Lico poniżej powierzchni materiału — rowek nie został wypełniony na '
        'całej długości lub szerokości.',
    'The cap is below the plate surface — the groove is not filled along its '
        'whole length or width.',
  ),
  processes: _all,
  keywords: ['niedolanie', 'niewypelnienie', 'wypelnienie', 'underfill',
      'underfilled'],
  causes: [
    DefectCause(
      id: 'if-low-deposit',
      processes: _all,
      rank: 1,
      cause: Tx('Za mało spoiwa: za niski prąd / podawanie albo za szybko',
          'Too little filler: current / wire feed too low or too fast'),
      check: Tx('Parametry i prędkość zgodne z WPS?',
          'Settings and travel speed as in the WPS?'),
      fix: Tx('Prąd / podawanie i prędkość wg WPS (TWI, Weld Australia).',
          'Current / wire feed and travel speed per the WPS (TWI, Weld '
              'Australia).'),
      sources: ['twi-shape1', 'weldaus-shape'],
    ),
    DefectCause(
      id: 'if-few-runs',
      processes: _all,
      rank: 1,
      cause: Tx('Za mało ściegów albo rowek szerszy niż w procedurze',
          'Too few runs or a groove wider than in the procedure'),
      check: Tx('Liczba ściegów zgodna z WPS? Szerokość rowka?',
          'Number of runs as in the WPS? Groove width?'),
      fix: Tx('Dołóż ściegi wg WPS; popraw przygotowanie (TWI).',
          'Add runs per the WPS; correct the preparation (TWI).'),
      sources: ['twi-shape1', 'weldaus-shape'],
    ),
  ],
  repair: [_rCauseFirst, _rMeasure5817, _rAddRun, _rPreheat, _rNdt],
  cutOut: Tx('Nie dotyczy — brak wypełnienia uzupełnia się ściegiem.',
      'Not applicable — an underfill is made good with a run.'),
  safety: [_sGrind, _sPreheat],
  checklist: [
    DefectStep(
      'before-cap',
      Tx('Przed licem rowek prawie wypełniony',
          'Groove nearly full before the cap'),
    ),
    DefectStep(
      'runs-wps',
      Tx('Liczba ściegów wg WPS', 'Number of runs per the WPS'),
    ),
    DefectStep(
      'feed-wps',
      Tx('Prąd / podawanie wg WPS', 'Current / wire feed per the WPS'),
    ),
    DefectStep(
      'cap-check',
      Tx('Lico sprawdzone przed zakończeniem spoiny',
          'Cap checked before finishing the weld'),
    ),
  ],
  repairSources: ['twi-shape1', 'weldaus-shape'],
);

const _rootConcavity = WeldDefect(
  id: 'root_concavity',
  group: DefectGroup.shape,
  refs: [Iso6520Ref(515, 'Wklęśnięcie grani', 'Root concavity')],
  title: Tx('Wklęśnięcie grani', 'Root concavity'),
  looks: Tx(
    'Grań cofnięta do środka rowka — płytka „rynna” po stronie grani; częsta '
        'przy TIG (TWI).',
    'The root is drawn back into the groove — a shallow channel on the root '
        'side; common in TIG (TWI).',
  ),
  processes: {_mma, _mag, _fcg, _tig, _mig},
  keywords: ['wklesniecie', 'wklesla gran', 'suck back', 'suckback',
      'root concavity'],
  causes: [
    DefectCause(
      id: 'rc-overhead',
      processes: {_mma, _mag, _fcg, _tig, _mig},
      positions: {
        DefectPosition.pe,
        DefectPosition.pipeUp,
        DefectPosition.pipeDown,
      },
      rank: 1,
      cause: Tx(
          'Dół rury (ok. godz. 6) / pułap: grawitacja ściąga jeziorko — grań '
              'wklęsła',
          'Bottom of the pipe (about 6 o’clock) / overhead: gravity pulls the '
              'pool — the root goes concave'),
      check: Tx('Wklęśnięcie tylko w dolnej części rury lub w pułapie?',
          'Concavity only at the bottom of the pipe or overhead?'),
      fix: Tx(
          'Mniejsze jeziorko i parametry niżej w pułapie (Miller), prowadzenie '
              'wg WPS dla pozycji; nie przegrzewaj grani.',
          'A smaller pool and lower settings overhead (Miller), technique per '
              'the WPS for the position; do not overheat the root.'),
      sources: ['patent-6oclock', 'miller-auto'],
    ),
    DefectCause(
      id: 'rc-purge-pressure',
      processes: {_tig, _mag},
      rank: 1,
      cause: Tx(
          'Za duży przepływ gazu formującego — ciśnienie w rurze wypycha grań '
              'do środka',
          'Too much purge flow — the pressure in the pipe pushes the root '
              'in'),
      check: Tx(
          'HFT: typowo ok. 20 l/min przy przedmuchu i ok. 5 l/min podczas '
              'spawania. Wylot gazu otwarty?',
          'HFT: typically approx. 20 l/min for the purge and approx. 5 l/min '
              'while welding. Gas outlet open?'),
      fix: Tx(
          'Zmniejsz przepływ formowania na czas spawania i zapewnij wylot gazu '
              '(HFT).',
          'Reduce the purge flow while welding and keep a gas outlet open '
              '(HFT).'),
      sources: ['hft-root'],
    ),
    DefectCause(
      id: 'rc-gap-speed',
      processes: {_mma, _mag, _fcg, _tig, _mig},
      rank: 2,
      cause: Tx('Zła szczelina albo za duża prędkość na graniu',
          'Wrong gap or root travel speed too high'),
      check: Tx('Szczelina wg WPS (za mała, czasem za duża)?',
          'Gap per the WPS (too small, sometimes too large)?'),
      fix: Tx('Dopasowanie i parametry wg WPS (TWI).',
          'Fit-up and settings per the WPS (TWI).'),
      sources: ['twi-shape2', 'weldaus-shape'],
    ),
    DefectCause(
      id: 'rc-second-pass',
      processes: {_mma, _mag, _fcg, _tig, _mig},
      rank: 2,
      cause: Tx('Ścieg gorący / drugi ścieg przetopił grań',
          'The hot pass / second run remelted the root'),
      check: Tx('Grań była dobra przed drugim ściegiem?',
          'Was the root good before the second run?'),
      fix: Tx('Mniej ciepła w ściegu gorącym, prowadzenie wg WPS (TWI).',
          'Less heat in the hot pass, technique per the WPS (TWI).'),
      sources: ['twi-shape2'],
    ),
  ],
  repair: [
    _rCauseFirst,
    _rMeasure5817,
    DefectStep(
      'rc-fill',
      Tx('Gdy grań jest zdrowa, a lico za niskie — można dołożyć stopiwa (TWI). '
              'Wklęśnięcie grani poza limitem bez dostępu od środka — naprawa '
              'przez wycięcie od lica.',
          'When the root is sound but the face is low — metal may be added '
              '(TWI). Root concavity over the limit with no inside access — '
              'repair by excavating from the face.'),
    ),
    _rRemove,
    _rGouge,
    _rConfirm,
    _rWeld,
    _rNdt,
    _rLimit,
  ],
  cutOut: Tx(
    'Wklęśnięcie ponad limit na dużej części obwodu rury bez dostępu od '
        'środka — rozważ wycięcie złącza; decyduje specyfikacja.',
    'Concavity over the limit on much of a pipe circumference with no inside '
        'access — consider cutting the joint out; the specification decides.',
  ),
  safety: [_sGrind, _sGouge, _sArgon],
  checklist: [
    DefectStep(
      'gap-wps',
      Tx('Szczelina wg WPS', 'Gap per the WPS'),
    ),
    DefectStep(
      'purge-low',
      Tx('Przepływ formowania zmniejszony na czas spawania, wylot otwarty',
          'Purge flow reduced while welding, outlet open'),
      processes: {_tig, _mag},
    ),
    DefectStep(
      'hot-pass',
      Tx('Ścieg gorący bez przegrzewania grani',
          'Hot pass without overheating the root'),
    ),
    DefectStep(
      'overhead-params',
      Tx('Parametry dla dołu rury / pułapu obniżone wg WPS',
          'Settings for the pipe bottom / overhead lowered per the WPS'),
    ),
  ],
  repairSources: [
    'twi-shape2',
    'hft-root',
    'twi-gouging',
    'lincoln-gouging',
    'hse-argon',
  ],
);

const _rootOxidation = WeldDefect(
  id: 'root_oxidation',
  group: DefectGroup.shape,
  refs: [Iso6520Ref(516, 'Porowatość grani', 'Root porosity')],
  title: Tx('Porowatość grani i cukrowanie (nierdzewka)',
      'Root porosity and sugaring (stainless)'),
  looks: Tx(
    'Gąbczasta, ziarnista, ciemna grań (potocznie „cukrowanie”) — utlenienie '
        'od strony grani przy spawaniu bez formowania. Osłabia złącze i obniża '
        'odporność korozyjną (Miller).',
    'A spongy, granular, dark root (“sugaring”) — oxidation of the root side '
        'when welding without a back purge. It weakens the joint and lowers '
        'corrosion resistance (Miller).',
  ),
  processes: {_tig, _mag},
  materials: {_ss},
  keywords: ['cukrowanie', 'cukier', 'formowanie', 'utlenienie', 'sugaring',
      'purge', 'back purge'],
  causes: [
    DefectCause(
      id: 'purge-none',
      processes: {_tig, _mag},
      rank: 1,
      cause: Tx('Brak formowania grani albo za krótko formowane',
          'No back purge or purge too short'),
      check: Tx(
          'Przed spawaniem min. 5 wymian objętości gazu (TWI)? Tlen przy '
              'wylocie: HFT — dla nierdzewki poniżej 50 ppm.',
          'At least 5 volume changes before welding (TWI)? Oxygen at the '
              'outlet: HFT — below 50 ppm for stainless.'),
      fix: Tx(
          'Formuj przed spawaniem i do zakończenia grani i ściegu gorącego '
              'albo do spadku temperatury grani poniżej ok. 250 °C (TWI); czas '
              '— moduł „Gaz, formowanie i timer”.',
          'Purge before welding and until the root and hot pass are done or '
              'the root has cooled below approx. 250 °C (TWI); time — the '
              '“Gas, purge and timer” tool.'),
      sources: ['twi-tig-equipment', 'hft-purge', 'twi-heat-tint'],
    ),
    DefectCause(
      id: 'purge-leak',
      processes: {_tig, _mag},
      rank: 2,
      cause: Tx(
          'Powietrze wchodzi od strony grani: nieszczelne korki, odklejona '
              'taśma na szczelinie',
          'Air gets in at the root: leaking dams, tape off the gap'),
      check: Tx(
          'Korki szczelne? Taśma na szczelinie zdejmowana na bieżąco przed '
              'łukiem?',
          'Dams tight? Gap tape removed only just ahead of the arc?'),
      fix: Tx('Uszczelnij korki i szczelinę; zmierz tlen przed zajarzeniem '
          '(HFT).',
          'Seal the dams and the gap; measure oxygen before striking the arc '
              '(HFT).'),
      sources: ['hft-purge', 'twi-tig-equipment'],
    ),
    DefectCause(
      id: 'root-heat',
      processes: {_tig, _mag},
      rank: 3,
      cause: Tx('Za dużo ciepła na graniu (prąd, za wolno)',
          'Too much heat on the root (current, too slow)'),
      check: Tx('Grań szeroka i ciemna mimo formowania?',
          'Root wide and dark despite the purge?'),
      fix: Tx('Mniejszy prąd, szybciej (Miller).',
          'Lower current, travel faster (Miller).'),
      sources: ['miller-tig-problems'],
    ),
  ],
  repair: [
    _rCauseFirst,
    DefectStep(
      'ox-remove',
      Tx('Utlenioną grań usuń do zdrowego metalu (od środka, jeśli jest '
              'dostęp) i spawaj ponownie z formowaniem — trawienie nie usuwa '
              'porowatej grani.',
          'Remove the oxidised root to sound metal (from the inside if '
              'accessible) and re-weld with a purge — pickling does not remove '
              'a porous root.'),
    ),
    _rConfirm,
    _rWeld,
    _rNdt,
    _rLimit,
  ],
  cutOut: Tx(
    'Cukrowanie w rurze bez dostępu od środka — grani nie da się naprawić, '
        'wycięcie spoiny i spawanie od nowa z formowaniem; dopuszczalność '
        'koloru grani podaje specyfikacja (np. ASME BPE odsyła do karty AWS '
        'D18 — HFT).',
    'Sugaring in a pipe with no inside access — the root cannot be repaired, '
        'cut the weld out and re-weld with a purge; acceptable root colour '
        'comes from the specification (e.g. ASME BPE refers to the AWS D18 '
        'chart — HFT).',
  ),
  safety: [_sArgon, _sGrind],
  checklist: [
    DefectStep(
      'purge-on',
      Tx('Formowanie podłączone, korki szczelne',
          'Purge connected, dams tight'),
    ),
    DefectStep(
      'o2-measured',
      Tx('Tlen zmierzony przed zajarzeniem', 'Oxygen measured before '
          'striking'),
    ),
    DefectStep(
      'tape',
      Tx('Taśma na szczelinie zdejmowana na bieżąco',
          'Gap tape removed only as you go'),
    ),
    DefectStep(
      'purge-until',
      Tx('Formowanie do końca grani i ściegu gorącego',
          'Purge kept until the root and hot pass are done'),
    ),
  ],
  repairSources: ['hft-purge', 'twi-heat-tint', 'hse-argon'],
);

const _filletShape = WeldDefect(
  id: 'fillet_shape',
  group: DefectGroup.shape,
  refs: [
    Iso6520Ref(503, 'Nadmierna wypukłość spoiny pachwinowej',
        'Excessive convexity (fillet weld)'),
    Iso6520Ref(505, 'Nieprawidłowy kąt przejścia lica', 'Incorrect weld toe'),
    Iso6520Ref(512, 'Nadmierna asymetria spoiny pachwinowej',
        'Excessive asymmetry of fillet weld'),
    Iso6520Ref(5213, 'Za mała grubość spoiny pachwinowej',
        'Insufficient throat thickness'),
    Iso6520Ref(5214, 'Za duża grubość spoiny pachwinowej',
        'Excessive throat thickness'),
  ],
  title: Tx('Zła geometria spoiny pachwinowej', 'Poor fillet weld shape'),
  looks: Tx(
    'Za mała lub za duża grubość a, nierówne ramiona, wypukłe lico. Dla '
        'spoiny płaskiej a ≈ 0,7 × długość ramienia (TWI); przy wypukłej lub '
        'wklęsłej sam pomiar ramienia nie wystarcza.',
    'Throat a too small or too large, unequal legs, a convex face. For a flat '
        'fillet a ≈ 0.7 × leg length (TWI); for a convex or concave one the leg '
        'alone is not enough.',
  ),
  processes: _all,
  keywords: ['pachwina', 'pachwinowa', 'grubosc a', 'ramie', 'asymetria',
      'fillet', 'throat', 'leg'],
  causes: [
    DefectCause(
      id: 'fs-pb-gravity',
      processes: _hand,
      positions: {DefectPosition.pb},
      rank: 1,
      cause: Tx(
          'PB: grawitacja ściąga jeziorko na dolną ściankę — nierówne ramiona',
          'PB: gravity pulls the pool onto the lower plate — unequal legs'),
      check: Tx('Ramię na dolnej ściance dłuższe?',
          'Is the leg on the lower plate longer?'),
      fix: Tx(
          'Kąt roboczy ok. 45° (Miller), mniej stopiwa w jednym przejściu '
              '(Kemppi).',
          'Work angle approx. 45° (Miller), less metal per pass (Kemppi).'),
      sources: ['twi-shape2', 'kemppi-mig-defects', 'miller-mig-basics'],
    ),
    DefectCause(
      id: 'fs-thin',
      processes: _all,
      rank: 1,
      cause: Tx('Za mała grubość a: za szybko przy za małym prądzie',
          'Throat too small: too fast with too little current'),
      check: Tx('Grubość a zmierzona miernikiem w kilku miejscach?',
          'Throat measured with a gauge at several points?'),
      fix: Tx('Prędkość i prąd wg WPS (TWI).',
          'Travel speed and current per the WPS (TWI).'),
      sources: ['twi-shape2'],
    ),
    DefectCause(
      id: 'fs-thick',
      processes: _all,
      rank: 2,
      cause: Tx(
          'Za duża grubość a: wysoki prąd, wolno, dokładanie „na zapas”',
          'Throat too large: high current, slow travel, adding “to be '
              'safe”'),
      check: Tx('Grubość a większa niż na rysunku?',
          'Throat larger than on the drawing?'),
      fix: Tx(
          'Spawaj na wymiar z rysunku — objętość rośnie z kwadratem ramienia: '
              'ramię 8 mm zamiast 6 mm to ok. 1,8 raza więcej stopiwa (TWI).',
          'Weld to the drawing size — volume grows with the square of the leg: '
              'an 8 mm leg instead of 6 mm is approx. 1.8 times the weld metal '
              '(TWI).'),
      sources: ['twi-shape2', 'twi-fillet'],
    ),
    DefectCause(
      id: 'fs-convex',
      processes: _all,
      rank: 2,
      cause: Tx('Wypukłe lico — duża objętość „zimnego” stopiwa',
          'Convex face — a large volume of cold weld metal'),
      check: Tx('Ścieg wysoki, z ostrym przejściem przy brzegach?',
          'Bead high with sharp toes?'),
      fix: Tx(
          'Parametry wg WPS (TWI); przy MAG podnieś napięcie, gdy ścieg '
              '„sznurkowy” (Miller).',
          'Settings per the WPS (TWI); in MAG raise the voltage when the bead '
              'is ropy (Miller).'),
      sources: ['twi-shape2', 'miller-defects'],
    ),
    DefectCause(
      id: 'fs-arc-blow',
      processes: _dc,
      rank: 4,
      cause: Tx('Dmuch magnetyczny odchyla łuk na jedną ściankę',
          'Arc blow deflects the arc onto one plate'),
      check: Tx('Łuk ucieka na bok przy DC?', 'Does the arc swing sideways on '
          'DC?'),
      fix: Tx('Przenieś masę, krótszy łuk (Kemppi, TWI).',
          'Move the earth, shorter arc (Kemppi, TWI).'),
      sources: ['kemppi-mig-defects', 'twi-arc-blow'],
    ),
  ],
  repair: [
    _rCauseFirst,
    _rMeasure5817,
    DefectStep(
      'fs-add',
      Tx('Za mała grubość a: oczyść i dołóż ścieg wg WPS (TWI).',
          'Throat too small: clean and add a run per the WPS (TWI).'),
    ),
    DefectStep(
      'fs-grind',
      Tx('Wypukłość / ostre przejście: zeszlifuj do łagodnego profilu bez '
              'zmniejszania grubości a poniżej wymaganej.',
          'Convexity / sharp toe: grind to a smooth profile without reducing '
              'the throat below the required size.'),
    ),
    _rNdt,
  ],
  cutOut: Tx(
    'Nie dotyczy — geometrię poprawia się ściegiem lub szlifowaniem; ocena wg '
        'EN ISO 5817 / specyfikacji.',
    'Not applicable — the shape is corrected by an extra run or grinding; '
        'assessment per EN ISO 5817 / the specification.',
  ),
  safety: [_sGrind, _sPreheat],
  checklist: [
    DefectStep(
      'throat-gauge',
      Tx('Grubość a zmierzona miernikiem w kilku miejscach',
          'Throat measured with a gauge at several points'),
    ),
    DefectStep(
      'work-angle',
      Tx('Kąt roboczy ok. 45°', 'Work angle approx. 45°'),
      processes: _hand,
    ),
    DefectStep(
      'params',
      Tx('Prędkość i prąd wg WPS', 'Travel speed and current per the WPS'),
    ),
    DefectStep(
      'to-size',
      Tx('Spawanie na wymiar z rysunku, bez dokładania na zapas',
          'Weld to the drawing size, no extra “to be safe”'),
    ),
  ],
  repairSources: ['twi-shape2'],
);

// ── 6xx Niezgodności spawalnicze różne ──────────────────────────────────────

const _strayArc = WeldDefect(
  id: 'stray_arc',
  group: DefectGroup.misc,
  refs: [
    Iso6520Ref(601, 'Ślad zajarzenia (przypadkowe zajarzenie łuku)',
        'Stray arc (arc strike)'),
  ],
  title: Tx('Ślad zajarzenia', 'Arc strike'),
  looks: Tx(
    'Miejscowe nadtopienie materiału poza rowkiem po przypadkowym zajarzeniu '
        'łuku; może zostawić twardą strefę i pęknięcia (Project Materials).',
    'A local melted spot on the parent metal outside the groove from an '
        'accidental arc strike; it may leave a hard zone and cracks (Project '
        'Materials).',
  ),
  processes: _hand,
  keywords: ['zajarzenie', 'slad zajarzenia', 'arc strike', 'stray arc'],
  causes: [
    DefectCause(
      id: 'stray-outside',
      processes: _hand,
      rank: 1,
      cause: Tx('Zajarzanie łuku poza rowkiem',
          'Striking the arc outside the groove'),
      check: Tx('Ślady zajarzeń obok spoiny?',
          'Arc strike marks next to the weld?'),
      fix: Tx('Zajarzaj tylko w rowku albo na płytce startowej (Project '
          'Materials).',
          'Strike only in the groove or on a start tab (Project Materials).'),
      sources: ['arc-strike'],
    ),
  ],
  repair: [
    DefectStep(
      'as-grind',
      Tx('Zeszlifuj ślad do gładkiego konturu i sprawdź MT / PT, czy nie ma '
              'pęknięć (Project Materials).',
          'Grind the mark to a smooth contour and check by MT / PT that there '
              'are no cracks (Project Materials).'),
    ),
    DefectStep(
      'as-hardness',
      Tx('W środowisku kwaśnym (sour service) także twardość, np. do 22 HRC / '
              '248 HV (Project Materials) — limit ze specyfikacji.',
          'In sour service also hardness, e.g. up to 22 HRC / 248 HV (Project '
              'Materials) — the limit comes from the specification.'),
    ),
    DefectStep(
      'as-thickness',
      Tx('Po szlifowaniu sprawdź grubość ścianki — poniżej minimalnej naprawa '
              'spawaniem wg procedury.',
          'After grinding check the wall thickness — below the minimum, repair '
              'by welding per the procedure.'),
    ),
  ],
  cutOut: Tx(
    'Zwykle niepotrzebne; gdy pęknięcie po zajarzeniu sięga głęboko, a '
        'naprawa spawaniem jest niedopuszczalna — decyduje inspektor / '
        'specyfikacja.',
    'Usually not needed; when the crack from the strike goes deep and weld '
        'repair is not allowed — the inspector / specification decides.',
  ),
  safety: [_sGrind, _sPt],
  checklist: [
    DefectStep(
      'strike-groove',
      Tx('Zajarzenie tylko w rowku / na płytce startowej',
          'Strike only in the groove / on a start tab'),
    ),
    DefectStep(
      'holder-rest',
      Tx('Uchwyt i palnik odkładane na izolowane miejsce, nie na element',
          'Holder and torch put down on an insulated spot, not on the part'),
    ),
    DefectStep(
      'earth-close',
      Tx('Masa na czystym metalu, blisko spoiny',
          'Earth clamp on clean metal, close to the weld'),
    ),
  ],
  repairSources: ['arc-strike', 'magnaflux-sds'],
);

const _spatter = WeldDefect(
  id: 'spatter',
  group: DefectGroup.misc,
  refs: [Iso6520Ref(602, 'Rozprysk', 'Spatter')],
  title: Tx('Rozprysk', 'Spatter'),
  looks: Tx(
    'Krople stopiwa przyklejone do materiału obok spoiny. EN ISO 5817: '
        'akceptacja zależy od zastosowania (np. materiał, ochrona przed '
        'korozją).',
    'Droplets of weld metal stuck to the parent metal next to the weld. EN '
        'ISO 5817: acceptance depends on the application (e.g. material, '
        'corrosion protection).',
  ),
  processes: {_mma, _mag, _fcg, _fcs, _mig},
  keywords: ['rozprysk', 'odpryski', 'kulki', 'spatter'],
  causes: [
    DefectCause(
      id: 'sp-voltage',
      processes: {_mag, _mig},
      rank: 1,
      cause: Tx('Napięcie niedopasowane do prędkości podawania drutu',
          'Voltage not matched to the wire feed speed'),
      check: Tx(
          'Drut „stuka” w jeziorko (za niskie napięcie lub za duży prąd — '
              'TWI)? Za wysokie napięcie też daje rozprysk (Miller).',
          'Is the wire stubbing into the pool (voltage too low or current too '
              'high — TWI)? Too high a voltage also causes spatter (Miller).'),
      fix: Tx('Dobierz napięcie do podawania wg WPS / synergii; skróć wylot.',
          'Match the voltage to the wire feed per the WPS / synergic line; '
              'shorten the stickout.'),
      sources: ['twi-spatter', 'miller-defects'],
    ),
    DefectCause(
      id: 'sp-mma-arc',
      processes: {_mma},
      rank: 1,
      cause: Tx('Za długi łuk albo prąd niedopasowany do elektrody',
          'Arc too long or current not suited to the electrode'),
      check: Tx('Łuk dłuższy niż średnica rdzenia elektrody (Miller)?',
          'Arc longer than the electrode core diameter (Miller)?'),
      fix: Tx('Krótszy łuk, prąd z karty elektrody (Miller, Hobart).',
          'A shorter arc, current from the electrode data sheet (Miller, '
              'Hobart).'),
      sources: ['miller-stick', 'hobart-stick'],
    ),
    DefectCause(
      id: 'sp-fcaw-voltage',
      processes: {_fcg, _fcs},
      rank: 1,
      cause: Tx('Napięcie niedopasowane do drutu proszkowego',
          'Voltage not suited to the flux-cored wire'),
      check: Tx('Napięcie z karty drutu? Miller: przy drucie proszkowym zwykle '
          'za niskie.',
          'Voltage from the wire data sheet? Miller: with flux-cored wire '
              'usually too low.'),
      fix: Tx('Podnieś napięcie w zakresie karty drutu (Miller).',
          'Raise the voltage within the wire data sheet range (Miller).'),
      sources: ['miller-defects'],
    ),
    DefectCause(
      id: 'sp-gas',
      processes: {_mag},
      rank: 2,
      cause: Tx('Czysty CO2 zamiast mieszanki', 'Pure CO2 instead of a mix'),
      check: Tx(
          'Butla z CO2? Lincoln: CO2 — ostry łuk, duży rozprysk; Ar z 3–10 % '
              'CO2 lub 1–5 % O2 — minimalny.',
          'A CO2 cylinder? Lincoln: CO2 — a harsh arc, heavy spatter; Ar with '
              '3–10 % CO2 or 1–5 % O2 — minimal.'),
      fix: Tx('Gaz z WPS; mieszanka argonowa, jeśli dopuszcza WPS (TWI).',
          'Gas from the WPS; an argon mix if the WPS allows it (TWI).'),
      sources: ['lincoln-mig', 'twi-spatter'],
    ),
    DefectCause(
      id: 'sp-tip-earth',
      processes: _wire,
      rank: 2,
      cause: Tx('Zużyta końcówka prądowa albo zła masa',
          'Worn contact tip or poor earth'),
      check: Tx('Otwór końcówki owalny, łuk niestabilny? Masa na czystym '
          'metalu, dokręcona?',
          'Tip bore oval, arc unstable? Earth on clean metal, tight?'),
      fix: Tx(
          'Wymień końcówkę, popraw masę (TWI: zła masa daje wahania prądu; '
              'Tregaskiss: zużyta końcówka — niestabilny łuk).',
          'Replace the tip, fix the earth (TWI: a poor earth causes current '
              'swings; Tregaskiss: a worn tip — an unstable arc).'),
      sources: ['twi-spatter', 'tregaskiss-guide'],
    ),
    DefectCause(
      id: 'sp-mma-wet',
      processes: {_mma},
      rank: 2,
      cause: Tx('Wilgotne lub uszkodzone elektrody',
          'Damp or damaged electrodes'),
      check: Tx('Otulina pęknięta, elektrody spoza piecyka?',
          'Cracked coating, electrodes from outside the oven?'),
      fix: Tx('Suche elektrody z piecyka (Kemppi, Oerlikon).',
          'Dry electrodes from the oven (Kemppi, Oerlikon).'),
      sources: ['kemppi-defects', 'oerlikon-storage'],
    ),
    DefectCause(
      id: 'sp-inductance',
      processes: {_mag},
      rank: 3,
      cause: Tx('Za mała indukcyjność (dławik) w łuku zwarciowym',
          'Inductance too low in short-circuit transfer'),
      check: Tx('Lincoln: zbyt szybki narost prądu wyrzuca kroplę.',
          'Lincoln: too fast a current rise expels the droplet.'),
      fix: Tx('Zwiększ indukcyjność — płynniejsze jeziorko, gładsze lico '
          '(Lincoln).',
          'Increase the inductance — a more fluid pool, a smoother face '
              '(Lincoln).'),
      sources: ['lincoln-mig'],
    ),
    DefectCause(
      id: 'sp-dirty',
      processes: {_mma, _mag, _fcg, _fcs, _mig},
      rank: 3,
      cause: Tx('Rdza, olej, farba, zanieczyszczony drut',
          'Rust, oil, paint, contaminated wire'),
      check: Tx('Rowek i drut czyste?', 'Groove and wire clean?'),
      fix: Tx('Oczyść rowek; drut w opakowaniu (Miller, TWI).',
          'Clean the groove; keep the wire packed (Miller, TWI).'),
      sources: ['miller-defects', 'twi-spatter'],
    ),
    DefectCause(
      id: 'sp-mma-polarity',
      processes: {_mma},
      rank: 3,
      cause: Tx('Zła biegunowość', 'Wrong polarity'),
      check: Tx('Biegunowość z karty elektrody (DC+ / DC− / AC)?',
          'Polarity per the electrode data sheet (DC+ / DC− / AC)?'),
      fix: Tx('Ustaw biegunowość wg karty (Kemppi).',
          'Set the polarity per the data sheet (Kemppi).'),
      sources: ['kemppi-defects'],
    ),
    DefectCause(
      id: 'sp-arc-blow',
      processes: {_mma, _mag, _fcg, _fcs},
      rank: 4,
      cause: Tx('Dmuch magnetyczny', 'Magnetic arc blow'),
      check: Tx('Łuk odchyla się, rozprysk po jednej stronie?',
          'Arc deflecting, spatter on one side?'),
      fix: Tx(
          'Przenieś zacisk masy, pochyl elektrodę przeciw dmuchowi, przy MMA AC '
              'jeśli dopuszcza WPS, rozmagnesuj (Kemppi, TWI).',
          'Move the earth clamp, tilt the electrode against the blow, AC for '
              'MMA if the WPS allows it, demagnetise (Kemppi, TWI).'),
      sources: ['kemppi-defects', 'twi-arc-blow'],
    ),
  ],
  repair: [
    _rCauseFirst,
    DefectStep(
      'sp-remove',
      Tx('Rozprysk usuń skrobakiem lub szlifierką bez podcinania materiału; '
              'zakres usunięcia (malowanie, higiena) — ze specyfikacji.',
          'Remove spatter with a scraper or grinder without nicking the '
              'parent metal; how much to remove (painting, hygiene) — from the '
              'specification.'),
    ),
  ],
  cutOut: Tx(
    'Nie dotyczy — rozprysk usuwa się mechanicznie.',
    'Not applicable — spatter is removed mechanically.',
  ),
  safety: [_sGrind],
  checklist: [
    DefectStep(
      'voltage-feed',
      Tx('Napięcie dopasowane do podawania drutu',
          'Voltage matched to the wire feed'),
      processes: _wire,
    ),
    DefectStep(
      'tip-nozzle',
      Tx('Końcówka prądowa i dysza w dobrym stanie',
          'Contact tip and nozzle in good condition'),
      processes: _wire,
    ),
    DefectStep(
      'earth',
      Tx('Masa na czystym metalu, dokręcona', 'Earth on clean metal, tight'),
    ),
    DefectStep(
      'gas-wps',
      Tx('Gaz zgodny z WPS', 'Gas as in the WPS'),
      processes: _gasWire,
    ),
    DefectStep(
      'mma-arc',
      Tx('Krótki łuk, elektrody suche', 'Short arc, dry electrodes'),
      processes: {_mma},
    ),
    DefectStep(
      'mma-current',
      Tx('Prąd i biegunowość z karty elektrody',
          'Current and polarity from the electrode data sheet'),
      processes: {_mma},
    ),
  ],
  repairSources: ['twi-spatter'],
);

const _temperColour = WeldDefect(
  id: 'temper_colour',
  group: DefectGroup.misc,
  refs: [Iso6520Ref(610, 'Barwy nalotowe', 'Temper colour')],
  title: Tx('Barwy nalotowe (przebarwienia nierdzewki)',
      'Temper colours (stainless heat tint)'),
  looks: Tx(
    'Kolorowy tlenek na licu lub grani stali nierdzewnej. Pod nim jest warstwa '
        'zubożona w chrom — obniża odporność korozyjną (TWI). Ocena koloru — '
        'moduł „Przebarwienia”.',
    'A coloured oxide on the face or root of stainless steel. Under it is a '
        'chromium-depleted layer that lowers corrosion resistance (TWI). '
        'Colour assessment — the “Heat tint” tool.',
  ),
  processes: {_tig, _mag, _mma, _fcg},
  materials: {_ss},
  keywords: ['przebarwienia', 'nalot', 'barwy', 'kolor', 'heat tint',
      'discolouration', 'discoloration', 'temper'],
  causes: [
    DefectCause(
      id: 'tint-shield',
      processes: {_tig, _mag},
      rank: 1,
      cause: Tx('Brak formowania grani albo za krótko utrzymana osłona',
          'No back purge or the shield kept too short a time'),
      check: Tx(
          'Formowanie do spadku temperatury grani poniżej ok. 250 °C (TWI)? '
              'Tlen zmierzony (HFT: poniżej 50 ppm)?',
          'Purge kept until the root is below approx. 250 °C (TWI)? Oxygen '
              'measured (HFT: below 50 ppm)?'),
      fix: Tx('Formuj dłużej i sprawdzaj tlen przed zajarzeniem.',
          'Purge longer and check oxygen before striking.'),
      sources: ['twi-heat-tint', 'hft-purge'],
    ),
    DefectCause(
      id: 'tint-heat',
      processes: {_tig, _mag, _mma, _fcg},
      rank: 1,
      cause: Tx('Za dużo ciepła (za duży prąd, za wolno, za długi łuk)',
          'Too much heat (current too high, too slow, arc too long)'),
      check: Tx('Szeroki, ciemny pas nalotu wzdłuż spoiny?',
          'A wide, dark tint band along the weld?'),
      fix: Tx('Mniejszy prąd, szybciej, krótszy łuk, ewentualnie puls '
          '(Miller).',
          'Lower current, faster, a shorter arc, pulse if available '
              '(Miller).'),
      sources: ['miller-tig-problems'],
    ),
    DefectCause(
      id: 'tint-post-flow',
      processes: {_tig},
      rank: 2,
      cause: Tx('Za krótki post-flow — lico i krater stygną bez osłony',
          'Post-flow too short — the face and crater cool unshielded'),
      check: Tx('Post-flow: Miller — 1 s na każde 10 A, min. 8 s?',
          'Post-flow: Miller — 1 s per 10 A, at least 8 s?'),
      fix: Tx('Wydłuż post-flow, trzymaj palnik nad kraterem.',
          'Lengthen the post-flow, hold the torch over the crater.'),
      sources: ['miller-tig-gas'],
    ),
  ],
  repair: [
    DefectStep(
      'tc-mech',
      Tx('Usuń tlenek razem z warstwą zubożoną w chrom: najlepiej '
              'mechanicznie (kulkowanie szklane, szlifowanie), potem trawienie; '
              'szczotkowanie może wcisnąć tlenki w powierzchnię (TWI).',
          'Remove the oxide together with the chromium-depleted layer: best '
              'mechanically (glass bead blasting, grinding), then pickling; '
              'brushing can press oxides into the surface (TWI).'),
    ),
    DefectStep(
      'tc-pickle',
      Tx('Trawienie pastą (ok. 20 % HNO₃ i 5 % HF, działanie 15–60 min — HSE); '
              'szczegóły — moduł „Trawienie i pasywacja”.',
          'Pickling paste (approx. 20 % HNO₃ and 5 % HF, 15–60 min contact — '
              'HSE); details — the “Pickling and passivation” tool.'),
    ),
    DefectStep(
      'tc-passivation',
      Tx('Sama pasywacja nie usuwa barw nalotowych (HFT).',
          'Passivation alone does not remove temper colours (HFT).'),
    ),
  ],
  cutOut: Tx(
    'Przebarwiona grań w rurze bez dostępu do trawienia, ponad dopuszczalny '
        'poziom ze specyfikacji (np. karta AWS D18) — wycięcie spoiny.',
    'A discoloured root in a pipe with no access for pickling, above the '
        'level allowed by the specification (e.g. the AWS D18 chart) — cut the '
        'weld out.',
  ),
  safety: [_sPickling, _sArgon, _sGrind],
  checklist: [
    DefectStep(
      'purge-o2',
      Tx('Formowanie grani i pomiar tlenu', 'Back purge and oxygen check'),
      processes: {_tig, _mag},
    ),
    DefectStep(
      'heat-low',
      Tx('Prąd i prędkość wg WPS, krótki łuk',
          'Current and speed per the WPS, short arc'),
    ),
    DefectStep(
      'post-flow',
      Tx('Post-flow ustawiony', 'Post-flow set'),
      processes: {_tig},
    ),
    DefectStep(
      'colour-chart',
      Tx('Kolor oceniony wg karty / specyfikacji',
          'Colour assessed against the chart / specification'),
    ),
    DefectStep(
      'pickling-plan',
      Tx('Usuwanie nalotu po spawaniu zaplanowane (trawienie)',
          'Tint removal after welding planned (pickling)'),
    ),
  ],
  repairSources: [
    'twi-pickling',
    'hse-pickling',
    'hft-purge',
    'twi-heat-tint',
    'hse-argon',
  ],
);

/// Wszystkie wady w kolejności grup ISO 6520-1.
const List<WeldDefect> kWeldDefects = [
  _crackCold,
  _crackHot,
  _crackCrater,
  _porosity,
  _shrinkage,
  _slag,
  _oxide,
  _tungsten,
  _lackOfFusion,
  _lackOfPenetration,
  _undercut,
  _excessWeldMetal,
  _excessPenetration,
  _overlap,
  _misalignment,
  _sagging,
  _burnThrough,
  _incompleteFill,
  _rootConcavity,
  _rootOxidation,
  _filletShape,
  _strayArc,
  _spatter,
  _temperColour,
];
