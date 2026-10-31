// ignore_for_file: prefer_const_constructors

import 'package:flutter/material.dart';

import '../config/app_links.dart';
import '../config/feature_flags.dart';
import '../i18n/app_language.dart';

// Help v2 — searchable knowledge base for fitters and welders.
// Each entry has bilingual (PL/EN) question + answer + tags for fuzzy matching.
// Categories are sorted by relevance to daily fitter/welder work.
//
// Sourced from:
//   - Original 21 entries from the legacy help_screen.dart
//   - 100-iteration piping_knowledge.md research base
//   - ASME B31.3 / API 1104 / NACE MR0175 / AWS D1.1 hands-on practice
//   - Wpisy do modułów z fali 2026-10 (t8/5, prace pożarowe, elektrody,
//     PCC-1, pogoda, stożki, słownik, spoina pachwinowa, twardość, akord,
//     import do wyceny): liczby i normy WYŁĄCZNIE z kodu domeny tych modułów
//     (lib/domain/…, komentarze ze źródłami). Zmieniasz moduł — popraw wpis.
//     Liczby PL i EN muszą być te same (test/data/help_entries_test.dart).
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
          'Rozwiązanie: low-H electrody (E7018-H4) z piecyka, z pilnowanym czasem na powietrzu (AWS D1.1: E70XX 4 h), '
          'po przekroczeniu suszone wg karty producenta (AWS D1.1 dla E7018: 260–430 °C, min. 2 h), '
          'preheat 150-300°C, slower cool z dehydrogenation hold 200°C × 2-4 h. '
          'Czas i suszenie elektrod: narzędzie „Elektrody zasadowe: czas i suszenie”.',
          'Cold cracking after cooling = hydrogen embrittlement in HAZ — typical for high-strength steels (P91, X65+). '
          'Causes: moist electrode/wire, no preheat, fast cooling. '
          'Fix: low-H electrodes (E7018-H4) from the holding oven, with the exposure time watched (AWS D1.1: E70XX 4 h), '
          're-dried per the maker’s data sheet once it is exceeded (AWS D1.1 for E7018: 260–430 °C, 2 h min.), '
          'preheat 150-300°C, slow cool with dehydrogenation hold 200°C × 2-4 h. '
          'Electrode exposure and re-drying: the "Low-hydrogen electrodes: exposure" tool.',
        ),
        tags: ['cracks', 'pekanie', 'cold-cracking', 'hydrogen', 'preheat', 'p91', 'haz', 'e7018', 'suszenie'],
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
      HelpEntry(
        id: 'cone-development',
        question: _bi(
          'Jak rozwinąć stożek ścięty (lej, redukcję z blachy)?',
          'How do I lay out a truncated cone (hopper, plate reducer)?',
        ),
        answer: _bi(
          'Rozwinięcie stożka współosiowego to wycinek pierścienia: promień łuku dużego R = (Dm/2)/sin α, łuku małego r, '
          'a R − r = L (tworząca); kąt wycinka θ = 360°·sin α (α — kąt połówkowy od osi). '
          'Liczy się po osi obojętnej, czyli w połowie grubości blachy. Ścianka stożka jest pochylona, więc przy średnicy '
          'zewnętrznej Dm = D − t/cos α, przy wewnętrznej D + t/cos α — pominięcie 1/cos α daje błąd średnicy 0,41·t przy 45° '
          'i całe t przy 60°. '
          'Przy R ponad 3000 mm cyrkiel jest za duży — trasuj z tabeli rzędnych od cięciwy. Wycinek ponad 300° źle się zwija — '
          'dziel na co najmniej 2 części. '
          'Narzędzie „Rozwinięcie stożka i przejść” dobiera liczbę części (1, 2, 3, 4, 6, 8 albo 12) do arkusza, podaje cięciwę, '
          'strzałkę i przekątną kontrolną oraz szablon 1:1.',
          'A concentric cone lays out as a ring sector: large arc radius R = (Dm/2)/sin α, small arc radius r, '
          'and R − r = L (slant height); sector angle θ = 360°·sin α (α — half-angle from the axis). '
          'Work on the neutral axis, i.e. mid-thickness. The cone wall is inclined, so from the outside '
          'diameter Dm = D − t/cos α, from the inside D + t/cos α — dropping the 1/cos α gives a diameter error of 0.41·t at 45° '
          'and a full t at 60°. '
          'With R above 3000 mm a trammel is too big — mark out from the table of ordinates off the chord. A sector over 300° rolls badly — '
          'split it into at least 2 parts. '
          'The "Cone & transition layout" tool picks the number of parts (1, 2, 3, 4, 6, 8 or 12) for the sheet, gives the chord, '
          'rise and check diagonal and a 1:1 template.',
        ),
        tags: ['stozek', 'cone', 'lej', 'hopper', 'rozwiniecie', 'layout', 'wycinek', 'redukcja', 'blacha', 'plate', 'os obojetna'],
      ),
      HelpEntry(
        id: 'transition-square-round',
        question: _bi(
          'Stożek mimośrodowy albo przejście kwadrat–koło — jak trasować?',
          'Eccentric cone or square-to-round transition — how do I mark it out?',
        ),
        answer: _bi(
          'Triangulacją: aplikacja podaje tabelę linii prawdziwych (tworzących) i cięciw mierzonych NA BLASZE. Klasyczna triangulacja '
          'z cięciwami z rzutu skraca obwód — o ok. 1,14 % przy 12 podziałach (0,29 % przy 24); tu kąt rozwinięcia jest liczony '
          'dokładnie, więc obwód się zgadza. Podział obwodu: 12, 16, 24, 32 albo 48. '
          'Przejście prostokąt–koło to 4 trójkąty płaskie (bok prostokąta + punkt koła) i 4 wycinki stożków ukośnych '
          'z wierzchołkami w narożach. Części: 1, 2 albo 4; szew w połowie boku albo w narożu; koło może być przesunięte '
          'względem prostokąta. '
          'Grubość: przejście liczy wymiar zewnętrzny / wewnętrzny jak dla ścianki pionowej (∓ t); gdy ścianki są pochylone '
          'ponad 30°, ekran ostrzega o różnicy — wtedy wymiaruj po średniej. Narzędzie „Rozwinięcie stożka i przejść”.',
          'By triangulation: the app gives a table of true lengths (generators) and of chords measured ON THE PLATE. Classic triangulation '
          'with chords taken from the plan view shortens the circumference — by about 1.14 % with 12 divisions (0.29 % with 24); here the '
          'development angle is worked out exactly, so the circumference comes out right. Divisions: 12, 16, 24, 32 or 48. '
          'A rectangle-to-round transition is 4 flat triangles (a side of the rectangle + a point of the circle) and 4 oblique cone '
          'sectors with apexes at the corners. Parts: 1, 2 or 4; seam at the middle of a side or at a corner; the circle may be '
          'offset from the rectangle. '
          'Thickness: the transition takes the outside / inside size as for a vertical wall (∓ t); where walls slope more than '
          '30° the screen warns about the difference — then dimension to the mean. The "Cone & transition layout" tool.',
        ),
        tags: ['przejscie', 'transition', 'kwadrat kolo', 'square to round', 'mimosrodowy', 'eccentric', 'triangulacja', 'triangulation', 'stozek', 'cone'],
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
          'Twardość (ISO 15156-2:2020, tab. A.1): spoina od strony grani, SWC i materiał rodzimy CS ≤ 250 HV (HV10 lub HV5); '
          '22 HRC to osobny limit dla pomiaru metodą HRC, nie przeliczenie (22 HRC ≈ 248 HV wg ASTM E140). Ni content ≤1% w CS. '
          'PWHT wymagany dla wszystkich CS welds. '
          'Bolts: tylko B7M/L7M (lower hardness vs B7); B16 zabronione. NIGDY high-strength (>1240 MPa). '
          'HIC-tested plate per NACE TM0284 (CLR ≤15%, CTR ≤5%, CSR ≤2%).',
          'Threshold: H₂S partial pressure ≥0.05 psi (0.3 kPa) or H₂S in water ≥1.45 ppm → compliance required. '
          'Hardness (ISO 15156-2:2020, Table A.1): weld root side, HAZ and CS base metal ≤ 250 HV (HV10 or HV5); '
          '22 HRC is a separate limit for HRC testing, not a conversion (22 HRC ≈ 248 HV per ASTM E140). Ni content ≤1% in CS. '
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
      HelpEntry(
        id: 'hardness-sour-limit',
        question: _bi(
          'Twardość spoiny w środowisku H₂S: 250 HV czy 22 HRC?',
          'Weld hardness in sour (H₂S) service: 250 HV or 22 HRC?',
        ),
        answer: _bi(
          'NACE MR0175 / ISO 15156-2:2020, tab. A.1 (stal węglowa, C-Mn, niskostopowa): spoina od strony grani, SWC i materiał '
          'rodzimy ≤ 250 HV (HV10 lub HV5). Lico nieeksponowane do 275 HV tylko przy spełnieniu wszystkich trzech warunków: zgoda '
          'użytkownika urządzenia, materiał rodzimy grubszy niż 9 mm, lico nie styka się ze środowiskiem kwaśnym. '
          '22 HRC to osobny limit dla pomiaru metodą HRC — na spoinach tylko na warunkach 7.3.3.2 (m.in. PWHT w WPS). „248 HV” '
          'to przeliczenie 22 HRC wg ASTM E140 — dla spoin norma podaje 250 HV, więc nie zamieniaj jednego limitu na drugi przeliczeniem. '
          'Odkuwki ASTM A105 ≤ 187 HB, kształtki A234 WPB/WPC ≤ 197 HB (A.2.1.3). '
          'Narzędzie „Twardość: przelicznik i limity” ocenia serię pomiarów: wynik równy limitowi = OK; pomiar pusty albo spoza '
          'tablicy przeliczeń nigdy nie daje zielonego.',
          'NACE MR0175 / ISO 15156-2:2020, Table A.1 (carbon, C-Mn and low-alloy steel): weld root side, HAZ and base '
          'metal ≤ 250 HV (HV10 or HV5). An unexposed weld cap up to 275 HV only when all three conditions are met: the equipment '
          'user agrees, parent material thicker than 9 mm, the cap is not in contact with the sour environment. '
          '22 HRC is a separate limit for HRC testing — on welds only under 7.3.3.2 (e.g. PWHT in the WPS). "248 HV" '
          'is 22 HRC converted per ASTM E140 — for welds the standard gives 250 HV, so do not swap one limit for the other by conversion. '
          'ASTM A105 forgings ≤ 187 HB, A234 WPB/WPC fittings ≤ 197 HB (A.2.1.3). '
          'The "Hardness: converter and limits" tool judges a series of readings: a result equal to the limit = OK; an empty reading '
          'or one outside the conversion table never gives green.',
        ),
        tags: ['twardosc', 'hardness', 'hv10', 'hrc', 'nace', 'mr0175', 'iso 15156', 'h2s', 'sour-service', 'kwasne'],
      ),
      HelpEntry(
        id: 'hardness-wpqr-b313',
        question: _bi(
          'Jaki limit twardości przy kwalifikowaniu technologii (WPQR) i po PWHT?',
          'What hardness limit applies to procedure qualification (WPQR) and after PWHT?',
        ),
        answer: _bi(
          'EN ISO 15614-1:2004+A2:2012, tab. 2 (maks. HV10, grupy wg ISO/TR 15608): gr. 1 i 2 — 380 bez obróbki cieplnej, 320 po '
          'obróbce; gr. 3 — 450 / 380 (stal o min. Re > 890 MPa — wartości ustala się osobno); gr. 4 i 5 — 380 / 320. Wydanie 2017 '
          'podniosło limit gr. 4 i 5 po obróbce do 350 HV10 — to wg źródła wtórnego, sprawdź w normie z kontraktu; obowiązuje '
          'wydanie przywołane w kontrakcie. '
          'ASME B31.3 wyd. 2008–2012, tab. 331.1.1 (twardość po PWHT): P-No 3 i 4 — 225 HB; P-No 5A, 5B, 5C — 241 HB; P-No 6 '
          '(nierdzewna martenzytyczna) — 241 HB. Wydania 2014 i nowsze tej kolumny nie mają — wtedy twardość po PWHT ocenia się '
          'wg specyfikacji projektu. '
          'Wszystkie te limity są w narzędziu „Twardość: przelicznik i limity” z normą, wydaniem i tabelą.',
          'EN ISO 15614-1:2004+A2:2012, Table 2 (max. HV10, groups per ISO/TR 15608): groups 1 and 2 — 380 not heat-treated, 320 '
          'heat-treated; group 3 — 450 / 380 (steel with min. yield > 890 MPa — special values apply); groups 4 and 5 — 380 / 320. The 2017 '
          'edition raised the heat-treated limit for groups 4 and 5 to 350 HV10 — per a secondary source, check the standard named in the '
          'contract; the edition invoked by the contract governs. '
          'ASME B31.3 2008–2012 editions, Table 331.1.1 (hardness after PWHT): P-No 3 and 4 — 225 HB; P-No 5A, 5B, 5C — 241 HB; P-No 6 '
          '(martensitic stainless) — 241 HB. The 2014 and later editions do not have this column — post-PWHT hardness is then judged '
          'to the project specification. '
          'All these limits are in the "Hardness: converter and limits" tool with the standard, edition and table.',
        ),
        tags: ['twardosc', 'hardness', 'wpqr', 'iso 15614-1', 'hv10', 'pwht', 'b31.3', 'brinell', 'hb', 'kwalifikowanie'],
      ),
      HelpEntry(
        id: 'hardness-conversion',
        question: _bi(
          'Czy mogę przeliczyć HRC albo HB na HV?',
          'Can I convert HRC or HB to HV?',
        ),
        answer: _bi(
          'Tylko dla stali niestopowych i niskostopowych oraz staliwa — wg ISO 18265:2013, tab. A.1, interpolacją między wierszami, '
          'bez wychodzenia poza tablicę: HV 80–940, HB do 618 (650 HV), HRC od 20,3 (240 HV) do 68,0, HRB 41,0–99,5. '
          'Poza tym zakresem aplikacja nie podaje wyniku, a pomiar nie jest oceniany. '
          'Dla stali nierdzewnej i austenitycznej tablica nie obowiązuje — mierz w tej samej skali, w której jest limit. '
          'Wytrzymałość Rm z twardości (80–650 HV) jest tylko orientacyjna, a ocena po przeliczeniu skali — przybliżona. '
          'Narzędzie „Twardość: przelicznik i limity”.',
          'Only for unalloyed and low-alloy steels and cast steel — per ISO 18265:2013, Table A.1, by interpolation between rows, '
          'never beyond the table: HV 80–940, HB up to 618 (650 HV), HRC from 20.3 (240 HV) to 68.0, HRB 41.0–99.5. '
          'Outside that range the app gives no result and the reading is not judged. '
          'For stainless and austenitic steel the table does not apply — measure in the same scale as the limit. '
          'Tensile strength Rm from hardness (80–650 HV) is only indicative, and a verdict after a scale conversion is approximate. '
          'The "Hardness: converter and limits" tool.',
        ),
        tags: ['przelicznik', 'converter', 'twardosc', 'hardness', 'hrc', 'hv', 'hb', 'hrb', 'iso 18265', 'rm', 'conversion'],
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
          'P91 (P-No 15E) wg ASME B31.3 (wyd. 2014+) i B31.1-2022: 705–775 °C, '
          '1 h na 25 mm grubości, min. 30 min (powyżej 125 mm: 5 h + 15 min na każde kolejne 25 mm). '
          'Nagrzewanie i chłodzenie powyżej 315 °C: maks. 335 °C/h podzielone przez połowę grubości w calach (nie więcej niż 335 °C/h). '
          'Specyfikacje projektów często zawężają zakres do 730–760 °C — wiąże WPS i procedura PWHT. '
          'Górnej granicy nie przekraczaj: powyżej 800 °C spoina do wycięcia (reaustenityzacja). '
          'Strefa pęknięć typu IV (drobnoziarnista SWC) — równomierna temperatura w całej strefie, termopary i wykres do dokumentacji. '
          'Cały cykl policzysz w narzędziu „Obróbka cieplna po spawaniu".',
          'P91 (P-No 15E) per ASME B31.3 (2014+) and B31.1-2022: 705–775 °C, '
          '1 h per 25 mm of thickness, min 30 min (above 125 mm: 5 h + 15 min for each further 25 mm). '
          'Heating and cooling above 315 °C: max 335 °C/h divided by half the thickness in inches (not more than 335 °C/h). '
          'Project specifications often narrow the range to 730–760 °C — the WPS and PWHT procedure govern. '
          'Never exceed the upper limit: above 800 °C the weld is cut out (re-austenitisation). '
          'Type IV cracking zone (fine-grained HAZ) — uniform temperature across it, thermocouples and a chart for the records. '
          'Plan the whole cycle in the "Post-weld heat treatment" tool.',
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
          'Za niskie HI = fast cooling, hardening, hydrogen cracking risk. '
          'To energia łuku (ASME IX, bez sprawności procesu). Energia liniowa wg EN 1011-1 ma sprawność k: '
          'Q = k × V × I × 60 / (v × 1000) — tej liczby potrzebuje t8/5 (narzędzie „Czas stygnięcia t8/5”).',
          'HI [kJ/mm] = (V × I × 60) / (travel_speed_mm/min × 1000). '
          'Example: 22 V × 110 A × 60 / (200 mm/min × 1000) = 0.726 kJ/mm. '
          'P91 WPS range: 1.0-2.5 kJ/mm, do NOT exceed upper. '
          'Too high HI = coarse-grain HAZ, low toughness, wider Type IV. '
          'Too low HI = fast cooling, hardening, hydrogen cracking risk. '
          'This is arc energy (ASME IX, no process efficiency). Heat input per EN 1011-1 includes the efficiency k: '
          'Q = k × V × I × 60 / (v × 1000) — that is the number t8/5 needs (the "Cooling time t8/5" tool).',
        ),
        tags: ['heat-input', 'wps', 'p91', 'kj-mm', 'formula', 'energia liniowa', 'en 1011-1'],
      ),
      HelpEntry(
        id: 't85-cooling-time',
        question: _bi(
          'Co to jest czas stygnięcia t8/5 i skąd wziąć okno?',
          'What is the t8/5 cooling time and where does the window come from?',
        ),
        answer: _bi(
          't8/5 to czas, w jakim spoina i SWC stygną od 800 °C do 500 °C. Przy stalach drobnoziarnistych o podwyższonej '
          'wytrzymałości (S460–S960, QT / TMCP) WPS albo producent stali podaje okno t8/5: za krótko — twarda, krucha SWC; '
          'za długo — spada udarność i wytrzymałość. '
          'Przykłady z kart producentów: Strenx 960 E 5–15 s, Strenx 700 E 5–20 s, DILLIMAX 890 5–12 s, DILLIMAX 690 5–20 s — '
          'producenci zmieniają je między wydaniami, więc sprawdź aktualną kartę swojej stali. '
          'Narzędzie „Czas stygnięcia t8/5” liczy wg EN 1011-2:2001 zał. D: przepływ 3D dla grubej blachy, 2D dla cienkiej, '
          'granica to grubość przejściowa d_t. To model uproszczony, szacunek — wiążą WPS/WPQR i zalecenia producenta stali.',
          't8/5 is the time the weld and HAZ take to cool from 800 °C to 500 °C. For fine-grained higher-strength steels '
          '(S460–S960, QT / TMCP) the WPS or the steel maker gives a t8/5 window: too short — hard, brittle HAZ; '
          'too long — toughness and strength drop. '
          'Examples from steel makers’ leaflets: Strenx 960 E 5–15 s, Strenx 700 E 5–20 s, DILLIMAX 890 5–12 s, DILLIMAX 690 5–20 s — '
          'makers change them between editions, so check the current sheet for your steel. '
          'The "Cooling time t8/5" tool works to EN 1011-2:2001 Annex D: 3D flow for thick plate, 2D for thin, '
          'the boundary being the transition thickness d_t. It is a simplified model, an estimate — the WPS/WPQR and the steel maker’s recommendations are binding.',
        ),
        tags: ['t8/5', 't85', 'czas stygniecia', 'cooling time', 'stygniecie', 'swc', 'haz', 'en 1011-2', 'strenx', 'dillimax', 'tmcp'],
      ),
      HelpEntry(
        id: 't85-hit-window',
        question: _bi(
          't8/5 wychodzi za krótki albo za długi — co zmienić?',
          't8/5 comes out too short or too long — what do I change?',
        ),
        answer: _bi(
          'Za krótki (stygnie za szybko) — zwiększ energię liniową Q albo temperaturę podgrzewania / międzyściegową T0. '
          'Za długi — zmniejsz Q albo T0. Sekcja „Jak trafić w okno” podaje zakres Q, prędkość spawania przy Twoim U i I '
          'oraz zakres T0 — każdy wiersz zmienia jeden parametr. T0 nie niżej niż minimum podgrzewania z WPS (zimne pęknięcia) '
          'i nie wyżej niż maks. temperatura międzyściegowa z WPS. '
          'Q to energia liniowa wg EN 1011-1, ze sprawnością procesu k: Q = k·U·I·60/(v·1000) [kJ/mm] — energia łuku z WPS '
          'wg ASME IX (bez k) to inna liczba. W cienkiej blasze (przepływ 2D) błąd Q wchodzi do kwadratu. '
          'Jednościegowa spoina pachwinowa ma współczynnik kształtu F2 jako przedział (narożna 0,67–0,9, teowa 0,45–0,67), '
          'więc wynik też jest przedziałem — „w oknie” tylko wtedy, gdy mieści się w nim cały.',
          'Too short (cools too fast) — raise the heat input Q or the preheat / interpass temperature T0. '
          'Too long — lower Q or T0. The "How to hit the window" section gives the Q range, the travel speed at your U and I '
          'and the T0 range — each line changes one parameter. T0 not below the WPS minimum preheat (cold cracking) '
          'and not above the WPS maximum interpass temperature. '
          'Q is the EN 1011-1 heat input, with the process efficiency k: Q = k·U·I·60/(v·1000) [kJ/mm] — the WPS arc energy '
          'per ASME IX (no k) is a different number. In thin plate (2D flow) an error in Q is squared. '
          'A single-run fillet weld has the shape factor F2 as a range (corner 0.67–0.9, T-joint 0.45–0.67), '
          'so the result is a range too — "within the window" only when all of it fits.',
        ),
        tags: ['t8/5', 't85', 'okno', 'window', 'energia liniowa', 'heat input', 'podgrzewanie', 'preheat', 'predkosc spawania', 'travel speed'],
      ),
    ],
  ),

  // ════════════════════════════════════════════════════════════════════════
  // 5b. POGODA I ELEKTRODY — narzędzia „Warunki do spawania” i „Elektrody
  // zasadowe: czas i suszenie” (liczby z weather_conditions.dart
  // i electrode_exposure.dart)
  // ════════════════════════════════════════════════════════════════════════
  HelpCategory(
    id: 'weather-electrodes',
    title: _bi('Pogoda i elektrody', 'Weather & electrodes'),
    subtitle: _bi('Mróz, wiatr, rosa, elektrody zasadowe', 'Frost, wind, dew, low-hydrogen rods'),
    icon: Icons.thermostat,
    accentArgb: 0xFF4FC3F7,
    entries: [
      HelpEntry(
        id: 'weather-wind-rain-frost',
        question: _bi(
          'Czy mogę spawać na wietrze, w deszczu albo na mrozie?',
          'Can I weld in wind, rain or frost?',
        ),
        answer: _bi(
          'Domyślne progi narzędzia „Warunki do spawania” (z norm; specyfikacja projektu może je zmienić): '
          'mróz poniżej −18 °C przy złączu — nie spawać bez ogrzewanego namiotu (AWS D1.1:2020 §7.11.2: 0 °F = −17,8 °C); '
          'deszcz, śnieg, mokre albo oblodzone złącze — tylko pod dachem namiotu, na suchym złączu (parawan nie chroni przed opadem); '
          'TIG, MIG/MAG, FCAW-G i spawanie gazowe — wiatr przy spoinie najwyżej 2,2 m/s (AWS D1.1 §7.11.1: 5 mph, w SI 8 km/h), '
          'inaczej osłona albo metoda bez gazu (111, 114); '
          'silny wiatr powyżej 10,8 m/s (6° Beauforta) — bez zamkniętego namiotu nie spawać. To próg praktyczny aplikacji: '
          'AWS D1.1, EN 1090-2 §7.5.3 i EN 1011-1 §5.2 wymagają ochrony przed wiatrem, ale nie podają liczby. '
          'Gorącą spoinę chroń przed deszczem i wiatrem, aż ostygnie. Stan powierzchni złącza oceniasz sam — '
          '„nie sprawdzono” nigdy nie daje zielonego werdyktu.',
          'Default thresholds of the "Welding conditions" tool (from the codes; the project specification may change them): '
          'frost below −18 °C at the joint — no welding without a heated enclosure (AWS D1.1:2020 §7.11.2: 0 °F = −17.8 °C); '
          'rain, snow, a wet or icy joint — only under the roof of an enclosure, on a dry joint (a windbreak does not keep rain off); '
          'TIG, MIG/MAG, FCAW-G and oxy-fuel welding — wind at the weld at most 2.2 m/s (AWS D1.1 §7.11.1: 5 mph, 8 km/h in SI), '
          'otherwise a shelter or a process without gas (111, 114); '
          'strong wind above 10.8 m/s (Beaufort 6) — no welding without a closed enclosure. This is the app’s practical threshold: '
          'AWS D1.1, EN 1090-2 §7.5.3 and EN 1011-1 §5.2 require protection from wind but give no number. '
          'Keep rain and wind off the hot weld until it cools. You judge the joint surface yourself — '
          '"not checked" never gives a green verdict.',
        ),
        tags: ['pogoda', 'weather', 'wiatr', 'wind', 'deszcz', 'rain', 'mroz', 'frost', 'namiot', 'enclosure', 'parawan', 'aws-d1.1', 'beaufort'],
      ),
      HelpEntry(
        id: 'weather-cold-dew-point',
        question: _bi(
          'Stal jest zimna albo zaparowana — do ilu stopni podgrzać złącze?',
          'The steel is cold or damp — how warm must the joint be?',
        ),
        answer: _bi(
          'Narzędzie „Warunki do spawania” bierze najwyższe z wymagań: każdy materiał min. 10 °C (ASME B31.3 tab. 330.1.1); '
          'stal węglowa i niskostopowa zimniejsza niż 0 °C — podgrzać do ≥ 21 °C i utrzymać w trakcie spawania '
          '(AWS D1.1:2020 tab. 5.8: poniżej 32 °F podgrzać do 70 °F); minimalne podgrzewanie z WPS, jeśli jest wyższe. '
          'Rosa: powierzchnia stali co najmniej 3 K ponad punktem rosy (przy ujemnym — ponad punktem szronu), inaczej osusz złącze grzaniem. '
          'To praktyka z malowania (ISO 8502-4), nie wymóg norm spawalniczych. Punkt rosy aplikacja liczy z temperatury i wilgotności powietrza. '
          'Mierz stal termometrem kontaktowym — rano i przy bezchmurnym niebie bywa zimniejsza od powietrza. Grzej i sprawdzaj '
          'po obu stronach złącza w pasie co najmniej 75 mm (ASME B31.3 §330.1.4: większe z 75 mm i 1,5 × grubości).',
          'The "Welding conditions" tool takes the highest requirement: any material min. 10 °C (ASME B31.3 Table 330.1.1); '
          'carbon and low-alloy steel colder than 0 °C — preheat to ≥ 21 °C and hold it while welding '
          '(AWS D1.1:2020 Table 5.8: below 32 °F preheat to 70 °F); the WPS minimum preheat if it is higher. '
          'Dew: the steel surface at least 3 K above the dew point (when that is below zero — above the frost point), otherwise dry the joint by heating. '
          'This is coating practice (ISO 8502-4), not a welding-code requirement. The app works out the dew point from air temperature and humidity. '
          'Measure the steel with a contact thermometer — in the morning and under a clear sky it is often colder than the air. Heat and check '
          'both sides of the joint over at least 75 mm (ASME B31.3 §330.1.4: the larger of 75 mm and 1.5 × thickness).',
        ),
        tags: ['punkt rosy', 'dew point', 'rosa', 'szron', 'kondensacja', 'zimna stal', 'cold steel', 'podgrzewanie', 'preheat', 'wilgotnosc', 'humidity'],
      ),
      HelpEntry(
        id: 'electrode-exposure-limit',
        question: _bi(
          'Ile elektrody zasadowe (E7018) mogą leżeć poza piecykiem?',
          'How long can low-hydrogen electrodes (E7018) stay out of the oven?',
        ),
        answer: _bi(
          'AWS D1.1:2020 tab. 7.1 (kol. A): A5.1 E70XX (E7016, E7018) — 4 h; E70XXR / E70XXHZR (np. E7018-1 H4R) i E7018M — 9 h; '
          'A5.5: E70XX-X — 4 h, E80XX-X — 2 h, E90XX-X — 1 h, E100XX-X i E110XX-X — 0,5 h. Dłuższe czasy (kol. B) tylko po badaniu wg D1.1. '
          'Kołczan albo termos NIE zatrzymuje licznika — to też czas na powietrzu. '
          'EN ISO 2560-A i 18275-A nie podają czasu — obowiązuje karta producenta. Aplikacja przyjmuje ostrożnie limit AWS tej samej '
          'wytrzymałości (E 38/42/46/50 B: 4 h, E 55: 1 h, E 62/69: 0,5 h) — to założenie, nadpisz je z karty albo WPS. '
          'Opakowanie próżniowe po otwarciu (wg producentów): Lincoln SAHARA ReadyPack 8 h (12 h przy ≤ 27 °C i ≤ 70 % RH), '
          'Böhler DRY SYSTEM 9 h, Kobelco ok. 8 h (niektóre produkty 4 h). '
          'Narzędzie „Elektrody zasadowe: czas i suszenie” liczy czas każdej partii, przypomina przed końcem limitu i prowadzi dziennik QC z PDF.',
          'AWS D1.1:2020 Table 7.1 (column A): A5.1 E70XX (E7016, E7018) — 4 h; E70XXR / E70XXHZR (e.g. E7018-1 H4R) and E7018M — 9 h; '
          'A5.5: E70XX-X — 4 h, E80XX-X — 2 h, E90XX-X — 1 h, E100XX-X and E110XX-X — 0.5 h. Longer times (column B) only after testing per D1.1. '
          'A quiver or rod canister does NOT stop the clock — it is still exposure time. '
          'EN ISO 2560-A and 18275-A give no time — the maker’s data sheet governs. The app cautiously takes the AWS limit of the same '
          'strength (E 38/42/46/50 B: 4 h, E 55: 1 h, E 62/69: 0.5 h) — an assumption, override it from the data sheet or the WPS. '
          'Vacuum pack once opened (per the makers): Lincoln SAHARA ReadyPack 8 h (12 h at ≤ 27 °C and ≤ 70 % RH), '
          'Böhler DRY SYSTEM 9 h, Kobelco about 8 h (some products 4 h). '
          'The "Low-hydrogen electrodes: exposure" tool times each batch, reminds you before the limit ends and keeps a QC log with a PDF.',
        ),
        tags: ['elektrody', 'electrodes', 'e7018', 'zasadowe', 'niskowodorowe', 'low-hydrogen', 'piecyk', 'oven', 'czas na powietrzu', 'exposure', 'aws-d1.1', 'kolczan'],
      ),
      HelpEntry(
        id: 'electrode-oven-redry',
        question: _bi(
          'Elektrody wróciły do piecyka — czas liczy się od nowa? Kiedy suszyć ponownie?',
          'Electrodes went back into the oven — does the clock restart? When must they be re-dried?',
        ),
        answer: _bi(
          'Piecyk-przechowalnik min. 120 °C. Jeśli elektrody wróciły do niego PRZED końcem limitu i przeleżały co najmniej 4 h — '
          'limit liczy się od nowa (AWS D1.1:2020 7.3.2.2). Krócej — licznik tylko stoi, a po wyjęciu liczy dalej. '
          'Po przekroczeniu limitu piecyk-przechowalnik nie pomaga: ponowne suszenie w piecu suszarniczym albo złom. '
          'Suszenie: AWS A5.1 — 260–430 °C, min. 2 h; AWS A5.5 — 370–430 °C, min. 1 h; EN ISO 2560-A / 18275-A — zwykle '
          '300–350 °C, 2 h (np. OK 48.00: 350 °C / 2 h), wg karty producenta; AWS D1.5 (mosty) — 230–290 °C, min. 2 h. '
          'Czas suszenia liczy się od osiągnięcia temperatury. '
          'AWS D1.1: najwyżej jedno ponowne suszenie; producenci EN zwykle dopuszczają 2–3 — sprawdź kartę. Zamoczone elektrody — tylko złom. '
          'Liczby z AWS D1.1:2020 — tekstu wydania 2025 nie sprawdzono; WPS i producent mogą być ostrzejsi.',
          'Holding oven min. 120 °C. If the electrodes went back in BEFORE the limit ran out and stayed there at least 4 h — '
          'the limit restarts (AWS D1.1:2020 7.3.2.2). Shorter — the clock only pauses and carries on once they are out. '
          'After the limit is exceeded the holding oven does not help: re-dry in a drying oven or scrap. '
          'Re-drying: AWS A5.1 — 260–430 °C, 2 h min.; AWS A5.5 — 370–430 °C, 1 h min.; EN ISO 2560-A / 18275-A — typically '
          '300–350 °C, 2 h (e.g. OK 48.00: 350 °C / 2 h), per the maker’s data sheet; AWS D1.5 (bridges) — 230–290 °C, 2 h min. '
          'Drying time counts from reaching temperature. '
          'AWS D1.1: re-dry no more than once; EN makers usually allow 2–3 — check the data sheet. Electrodes that got wet — scrap only. '
          'Numbers from AWS D1.1:2020 — the 2025 edition text has not been checked; the WPS and the maker may be stricter.',
        ),
        tags: ['suszenie', 'redry', 're-dry', 'rebake', 'piecyk', 'holding oven', 'elektrody', 'electrodes', 'e7018', 'aws-d1.1', 'aws-d1.5'],
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
          'ASME PCC-1, metoda Legacy (tab. 1) — rundy 1–3 w gwiazdę (na krzyż): '
          'dociągnięcie wstępne ≤ 20 % momentu docelowego (15–30 N·m), '
          '1) 20–30 % momentu docelowego, '
          '2) 50–70 %, '
          '3) 100 %. '
          '4) Runda okrężna 100 %, aż nakrętki przestaną się obracać (kilka śrub się relaxuje przy innych). '
          '5) Po co najmniej 4 h powtórz rundę 4. Po każdej rundzie sprawdź, czy szczelina jest równa. '
          'Bez star pattern → uneven gasket compression → blow-out. Smar ten sam, który przyjęto do momentu (współczynnik K), '
          'nigdy na uszczelkę; anti-seize: Cu-based dla CS, Ni-based dla SS. Moment policzysz w narzędziu „Moment śrub”.',
          'ASME PCC-1, Legacy method (Table 1) — rounds 1–3 in a star (cross) pattern: '
          'snug-up ≤ 20 % of target torque (15–30 N·m), '
          '1) 20–30 % of target torque, '
          '2) 50–70 %, '
          '3) 100 %. '
          '4) Circular round at 100 % until the nuts stop turning (some bolts relax when others tighten). '
          '5) After at least 4 h repeat round 4. After every round check that the gap is even. '
          'Without star pattern → uneven gasket compression → blow-out. Use the same lubricant the torque was based on (nut factor K), '
          'never on the gasket; anti-seize: Cu-based for CS, Ni-based for SS. Work out the torque in the "Bolt torque" tool.',
        ),
        tags: ['torque', 'star-pattern', 'asme-pcc-1', 'flange', 'bolt-up', 'legacy', 'rundy'],
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
      HelpEntry(
        id: 'flange-pcc1-alignment',
        question: _bi(
          'Jakie tolerancje osiowania kołnierzy przed skręceniem (ASME PCC-1)?',
          'What flange alignment tolerances apply before bolting up (ASME PCC-1)?',
        ),
        answer: _bi(
          'ASME PCC-1-2019 zał. E (kołnierze w spoczynku, bez ściągania): '
          'przesunięcie osi (high/low) ≤ 1,5 mm (1/16") — liniał na OD jednego kołnierza, 4 punkty co 90°; '
          'równoległość — różnica największej i najmniejszej szczeliny ≤ 0,8 mm (1/32"), szczelinomierz na zewnętrznej średnicy '
          'powierzchni uszczelniającej; otwory — śruba przechodzi przez oba pod kątem prostym, przesunięcie ≤ 3 mm (1/8"); '
          'szczelina ≤ 2 × grubość uszczelki; siła do zestawienia bez urządzeń < 10 % docelowego obciążenia śrub, żadna śruba > 20 % — '
          'jeśli trzeba więcej, decyduje inżynier. '
          'Granice w mm i w calach nie są dokładnym przeliczeniem (1/16" = 1,5875 mm) — oceniaj w układzie, w którym mierzysz. '
          'PCC-1-2022 przebudował zał. E; źródła podają te same liczby, ale brzmienia limitów siły nie potwierdzono, a zakład '
          'może mieć ostrzejsze tolerancje. '
          'Narzędzie „Odbiór połączenia kołnierzowego” daje werdykt i protokół PDF — zielony tylko wtedy, gdy każde kryterium '
          'jest zmierzone w granicy i lista montażu odhaczona.',
          'ASME PCC-1-2019 Appendix E (flanges at rest, not pulled together): '
          'centerline high/low ≤ 1.5 mm (1/16") — straight edge on the OD of one flange, 4 points 90° apart; '
          'parallelism — difference between the largest and the smallest gap ≤ 0.8 mm (1/32"), feeler gauge at the OD of the '
          'gasket seating surface; bolt holes — a bolt passes through both at a right angle, offset ≤ 3 mm (1/8"); '
          'gap ≤ 2 × gasket thickness; force to align without devices < 10 % of the total target bolt load, no bolt > 20 % — '
          'if more is needed, the engineer decides. '
          'The mm and inch limits are not an exact conversion (1/16" = 1.5875 mm) — judge in the system you measure in. '
          'PCC-1-2022 rebuilt Appendix E; sources give the same numbers, but the wording of the force limits is unconfirmed, and '
          'the site may have tighter tolerances. '
          'The "Flange joint check" tool gives a verdict and a PDF record — green only when every criterion '
          'is measured within limits and the assembly checklist is ticked.',
        ),
        tags: ['pcc-1', 'asme-pcc-1', 'osiowanie', 'alignment', 'kolnierz', 'flange', 'szczelina', 'gap', 'high-low', 'rownoleglosc', 'parallelism'],
      ),
      HelpEntry(
        id: 'flange-face-damage',
        question: _bi(
          'Rysa albo wżer na przylgu kołnierza — da się jeszcze skręcać?',
          'A scratch or pit on the flange face — can it still be bolted up?',
        ),
        answer: _bi(
          'ASME PCC-1-2019 zał. D, tab. D-2: dopuszczalna głębokość zależy od tego, jak daleko uszkodzenie sięga w poprzek '
          'szerokości osadzenia uszczelki w (rd — rzut promieniowy uszkodzenia). '
          'Uszczelki twarde (spiralne, kammprofile, metalowe): rd < w/4 — do 0,76 mm, w/4 ≤ rd < w/2 — do 0,25 mm, '
          'rd ≥ w/2 — niedopuszczalne. '
          'Uszczelki miękkie (płaskie niemetalowe, PTFE): rd < w/4 — do 1,27 mm, w/4 ≤ rd < w/2 — do 0,76 mm, '
          'w/2 ≤ rd < 3w/4 — do 0,13 mm, rd ≥ 3w/4 — niedopuszczalne. '
          'Płaskość powierzchni (tab. D-1): uszczelki twarde < 0,15 mm, miękkie < 0,25 mm. '
          'Przed skręceniem przylgi czyste — bez rdzy, farby i resztek starej uszczelki; uszczelka nowa, nigdy używana ponownie.',
          'ASME PCC-1-2019 Appendix D, Table D-2: the allowed depth depends on how far the damage reaches across '
          'the gasket seating width w (rd — radial projection of the damage). '
          'Hard gaskets (spiral wound, kammprofile, metal): rd < w/4 — up to 0.76 mm, w/4 ≤ rd < w/2 — up to 0.25 mm, '
          'rd ≥ w/2 — not acceptable. '
          'Soft gaskets (flat non-metallic, PTFE): rd < w/4 — up to 1.27 mm, w/4 ≤ rd < w/2 — up to 0.76 mm, '
          'w/2 ≤ rd < 3w/4 — up to 0.13 mm, rd ≥ 3w/4 — not acceptable. '
          'Face flatness (Table D-1): hard gaskets < 0.15 mm, soft < 0.25 mm. '
          'Before bolting up the faces are clean — no rust, paint or old gasket residue; the gasket is new, never reused.',
        ),
        tags: ['przylga', 'flange face', 'rysa', 'scratch', 'wzer', 'pit', 'uszkodzenie', 'damage', 'pcc-1', 'kolnierz', 'flange', 'plaskosc'],
      ),
      HelpEntry(
        id: 'flange-thread-protrusion',
        question: _bi(
          'Ile zwojów gwintu ma wystawać nad nakrętką?',
          'How many threads must stick out past the nut?',
        ),
        answer: _bi(
          'ASME PCC-1 nie podaje liczby zwojów. Wymaga pełnego zaangażowania gwintu na całej wysokości nakrętki '
          '(PCC-1 para. 8.2; ASME B31.3 335.2.3). W praktyce zwykle wystaje co najmniej 1 pełny zwój, a specyfikacje '
          'zakładów żądają 1–3 zwojów — sprawdź swoją. '
          'Przy okazji: śruby i nakrętki w gatunku ze specyfikacji (np. A193 B7 / A194 2H), smar ten sam, który przyjęto '
          'do obliczenia momentu (współczynnik K), i nigdy na uszczelkę.',
          'ASME PCC-1 gives no thread count. It requires full thread engagement over the whole nut height '
          '(PCC-1 para. 8.2; ASME B31.3 335.2.3). In practice at least 1 full thread usually sticks out, and plant '
          'specifications ask for 1–3 threads — check yours. '
          'Also: studs and nuts of the specified grade (e.g. A193 B7 / A194 2H), the same lubricant the torque '
          'was based on (nut factor K), and never on the gasket.',
        ),
        tags: ['gwint', 'thread', 'zwoje', 'nakretka', 'nut', 'sruby', 'studs', 'pcc-1', 'kolnierz', 'flange'],
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
          'Wokół miejsca hot work (welding, grinding, cutting) materiały palne usuwa się w **promieniu 10.7 m (35 ft)** — '
          'tak OSHA 29 CFR 1910.252; FM Global podaje 11 m w poziomie i co najmniej 5 m w pionie. '
          'Polski przepis (rozp. MSWiA, § 36) nie podaje odległości — obowiązuje zezwolenie zakładu. '
          'Usuń materiały palne, zakryj fire-resistant blankets, polej wodą podłogę palną, zakryj kratki ściekowe (sparks → vapors w kanalizacji = BLEVE). '
          'Fire watch PO zakończeniu pracy: NFPA 51B:2019 — co najmniej 1 h (starsze wydania 30 min), OSHA — co najmniej 30 min, '
          'w Polsce wg zezwolenia. Atmospheric test: DGW (LEL) ≤ 10 % albo mniej wg zezwolenia, O₂ 19.5-23.5%, H₂S/CO/NH₃ per spec. '
          'Checklista i protokół: narzędzie „Prace pożarowo niebezpieczne”.',
          'Within the hot work area (welding, grinding, cutting) combustibles are cleared for a **radius of 10.7 m (35 ft)** — '
          'that is OSHA 29 CFR 1910.252; FM Global gives 11 m horizontally and at least 5 m vertically. '
          'The Polish regulation (Ministry of the Interior, § 36) gives no distance — the site permit governs. '
          'Remove combustibles, cover with fire blankets, wet combustible floors, cover drains (sparks → vapors in sewer = BLEVE). '
          'Fire watch AFTER work: NFPA 51B:2019 — at least 1 h (older editions 30 min), OSHA — at least 30 min, '
          'in Poland per the permit. Atmospheric test: LEL ≤ 10 % or less per the permit, O₂ 19.5-23.5%, H₂S/CO/NH₃ per spec. '
          'Checklist and record: the "Hot work permit" tool.',
        ),
        tags: ['hot-work', 'nfpa-51b', 'fire-watch', '35-ft', 'permit', 'osha', 'dozor'],
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
        // Wartości jak w lib/domain/welding/shade_number.dart (tabele ANSI
        // Z49.1 / AWS F2.2 i minimum OSHA 1910.133, EN 169). Wcześniej wpis
        // powoływał się na ANSI Z87.1 (to norma samych ochron oczu) i podawał
        // stopnie jaśniejsze od zaleceń.
        answer: _bi(
          'Wg ANSI Z49.1 / AWS F2.2 — stopień zalecany, w nawiasie minimum OSHA 1910.133 (im wyższy, tym ciemniej): '
          '**MMA**: 60–160 A → 10 (8), 160–250 A → 12 (10), 250–550 A → 14 (11). '
          '**TIG**: do 50 A → 10 (8), 50–150 A → 12 (8), 150–500 A → 14 (10). '
          '**MIG/MAG, FCAW**: 60–160 A → 11 (10), 160–250 A → 12 (10), 250–500 A → 14 (10). '
          '**Żłobienie łukowo-powietrzne** do 500 A → 12 (10). '
          'Zacznij ciemniej i rozjaśniaj do dobrej widoczności, ale nie poniżej minimum. '
          'Europejska EN 169 daje zwykle o 1–2 stopnie jaśniej (np. TIG 100 A → 10, MAG 200 A → 11) i rozróżnia MIG na stopach lekkich (aluminium: do 1 stopnia ciemniej niż stal). '
          'Dobór dla procesu i prądu: narzędzie „Filtr przyłbicy: stopień zaciemnienia”.',
          'Per ANSI Z49.1 / AWS F2.2 — suggested shade, OSHA 1910.133 minimum in brackets (higher = darker): '
          '**SMAW**: 60–160 A → 10 (8), 160–250 A → 12 (10), 250–550 A → 14 (11). '
          '**GTAW (TIG)**: up to 50 A → 10 (8), 50–150 A → 12 (8), 150–500 A → 14 (10). '
          '**GMAW, FCAW**: 60–160 A → 11 (10), 160–250 A → 12 (10), 250–500 A → 14 (10). '
          '**Air carbon arc gouging** up to 500 A → 12 (10). '
          'Start darker and go lighter until you see the weld zone well, but never below the minimum. '
          'European EN 169 is usually 1–2 shades lighter (e.g. TIG 100 A → 10, MAG 200 A → 11) and treats MIG on light alloys separately (aluminium: up to 1 shade darker than steel). '
          'Pick by process and current: the “Welding filter: shade number” tool.',
        ),
        tags: ['shade', 'helmet', 'ansi-z49', 'en-169', 'smaw', 'tig', 'mig', 'ppe'],
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
      HelpEntry(
        id: 'hot-work-prep',
        question: _bi(
          'Co przygotować przed spawaniem, cięciem albo szlifowaniem w miejscu zagrożonym pożarem?',
          'What must be ready before welding, cutting or grinding where there is a fire risk?',
        ),
        answer: _bi(
          'W Polsce prace niebezpieczne pod względem pożarowym reguluje rozporządzenie MSWiA z 7 czerwca 2010 '
          '(t.j. Dz.U. 2023 poz. 822), § 36. Przed pracą: ocena zagrożenia i ustalony sposób zabezpieczenia, wskazane osoby '
          'odpowiedzialne, pracują tylko osoby upoważnione i zapoznane z zagrożeniami. Przy pracy: zabezpieczone materiały palne '
          'w miejscu pracy i w rejonach przyległych, sprzęt gaśniczy na miejscu, tylko sprawny sprzęt, kontrola miejsca po zakończeniu. '
          'Rozporządzenie o BHP przy spawaniu (27 kwietnia 2000): strefa rozprysku także poniżej stanowiska, bezpieczniki przy gazach '
          'palnych, butle chronione przed nagrzaniem powyżej 35 °C, przewód powrotny przy samej spoinie. '
          'Przepis NIE podaje odległości w metrach ani czasu dozoru — obowiązuje zezwolenie zakładu. Praktyka: FM Global — materiały '
          'palne usunięte w promieniu 11 m w poziomie i co najmniej 5 m w pionie; OSHA — 35 ft (10,7 m). '
          'Narzędzie „Prace pożarowo niebezpieczne” prowadzi przez listę (przed / w trakcie / po), zapisuje pomiar atmosfery '
          'i daje protokół PDF — to lista pomocnicza, nie zastępuje zezwolenia.',
          'In Poland hot work is governed by the Regulation of the Minister of the Interior of 7 June 2010 '
          '(consolidated Dz.U. 2023 item 822), § 36. Before work: hazards assessed and precautions agreed, responsible persons '
          'named, only authorised workers who were briefed on the hazards. During work: combustibles protected at the work point '
          'and in adjacent areas, fire-fighting equipment on site, only equipment in good order, the area inspected afterwards. '
          'The welding health and safety regulation (27 April 2000): spatter zone including below the work point, flashback '
          'arrestors on fuel gases, cylinders protected from heating above 35 °C, return lead right at the weld. '
          'The regulation gives NO distances in metres and no watch time — the site permit governs. Practice: FM Global — '
          'combustibles cleared for 11 m horizontally and at least 5 m vertically; OSHA — 35 ft (10.7 m). '
          'The "Hot work permit" tool walks you through the checklist (before / during / after), records the gas test '
          'and gives a PDF record — it is a checklist aid, not a permit.',
        ),
        tags: ['hot-work', 'prace pozarowe', 'pozarowo niebezpieczne', 'zezwolenie', 'permit', 'mswia', 'bhp', 'fm global', 'iskry', 'sparks'],
      ),
      HelpEntry(
        id: 'hot-work-lel-watch',
        question: _bi(
          'Jaki dopuszczalny % DGW i jak długo dozór po pracy?',
          'What % LEL is allowed and how long is the fire watch after work?',
        ),
        answer: _bi(
          'Rozp. MSWiA § 36 ust. 2: w pomieszczeniach i przy urządzeniach zagrożonych wybuchem oraz tam, gdzie były łatwo palne '
          'ciecze lub palne gazy — praca tylko przy stężeniu nieprzekraczającym 10 % DGW (dolnej granicy wybuchowości). '
          'Zakłady często wymagają mniej (0 % albo 5 % DGW) — obowiązuje wartość z zezwolenia. Aplikacja przyjmuje próg 0–10 %: '
          'wynik równy progowi przechodzi, wyższy to STOP; liczy się najpóźniejszy w czasie pomiar, a bez wpisanego pomiaru '
          'nie ma zielonego stanu. '
          'Czasu dozoru po pracy polski przepis nie podaje — wg zezwolenia. Praktyka: NFPA 51B:2019 — co najmniej 1 h '
          '(wcześniejsze wydania 30 min) i monitorowanie do kolejnych 3 h; OSHA 1910.252 — co najmniej 30 min; FM Global — '
          '30 albo 60 min i monitoring do 5 h, wg kategorii pracy. '
          '„Jak wczoraj” kopiuje miejsce, osoby, próg i czas dozoru, ale nigdy zaznaczeń ani pomiarów — stanowisko sprawdza się na nowo.',
          'Regulation § 36(2): in rooms and at equipment with an explosion hazard and wherever flammable liquids or gases '
          'have been — work only at a concentration not above 10 % LEL (lower explosive limit). '
          'Sites often require less (0 % or 5 % LEL) — the permit value applies. The app accepts a limit of 0–10 %: '
          'a reading equal to the limit passes, a higher one means STOP; the latest reading in time counts, and without '
          'an entered reading there is no green status. '
          'The Polish regulation gives no post-work watch time — per the permit. Practice: NFPA 51B:2019 — at least 1 h '
          '(earlier editions 30 min) and monitoring for up to 3 more hours; OSHA 1910.252 — at least 30 min; FM Global — '
          '30 or 60 min and monitoring up to 5 h, by work category. '
          '"Same as yesterday" copies the location, people, limit and watch time, but never the ticks or readings — the work area is checked anew.',
        ),
        tags: ['dgw', 'lel', 'eksplozymetr', 'gas test', 'pomiar atmosfery', 'dozor', 'fire watch', 'hot-work', 'nfpa-51b', 'zezwolenie'],
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
      HelpEntry(
        id: 'glossary-site-languages',
        question: _bi(
          'Jak jest „podtopienie” albo „brak przetopu” po niemiecku, niderlandzku czy norwesku?',
          'What is "undercut" or "lack of penetration" in German, Dutch or Norwegian?',
        ),
        answer: _bi(
          'Narzędzie „Słownik spawalniczy” — PL · EN · DE · NL · NO, działa bez internetu. Wpisz słowo w którymkolwiek z tych '
          'języków (polskie, niemieckie i norweskie znaki niepotrzebne), numer niezgodności ISO 6520-1 (np. 5011 — podtopienie ciągłe) '
          'albo numer procesu ISO 4063 (np. 135). '
          'Wybierz swój język docelowy (DE, NL, NO albo EN) — zostanie zapamiętany. Rozwinięty termin pokazuje wszystkie pięć języków, '
          'definicję i numer normy; każde tłumaczenie skopiujesz. „Pokaż rozmówcy” wyświetla termin dużym napisem na cały ekran, '
          'a przycisk albo dwuklik obraca go o 180° — podajesz telefon majstrowi. Ulubione terminy oznaczysz gwiazdką. '
          'W słowniku są tylko terminy potwierdzone we wszystkich pięciu językach. W Norwegii nazwy niezgodności funkcjonują '
          'głównie po angielsku i z numerem, a pozycje spawania podaje się kodem („stilling PF”).',
          'The "Welding dictionary" tool — PL · EN · DE · NL · NO, works offline. Type a word in any of these '
          'languages (no need for Polish, German or Norwegian characters), an ISO 6520-1 imperfection number (e.g. 5011 — continuous undercut) '
          'or an ISO 4063 process number (e.g. 135). '
          'Pick your target language (DE, NL, NO or EN) — it is remembered. An expanded term shows all five languages, '
          'the definition and the standard number; each translation can be copied. "Show to the other person" displays the term in large '
          'letters full screen, and a button or double tap turns it 180° — you hand the phone to the foreman. Mark favourite terms with a star. '
          'The dictionary holds only terms confirmed in all five languages. In Norway imperfection names are used '
          'mostly in English and by number, and welding positions are given by code ("stilling PF").',
        ),
        tags: ['slownik', 'dictionary', 'glossary', 'tlumaczenie', 'translation', 'niemiecki', 'german', 'norweski', 'norwegian', 'niderlandzki', 'dutch', 'iso 6520', 'za granica'],
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
          'ASME B31.3 §345.4.2: **P_test ≥ 1.5 × P_design × S_T/S** — S_T to naprężenie dopuszczalne w temp. próby, S w temp. obliczeniowej (S_T/S ≤ 6.5; w ambient T zwykle S_T/S = 1 → 1.5 × P_design). '
          'Pneumatic (§345.5.4): P_test ≥ 1.1 × P_design. '
          'Hold time: min 10 min (§345.2.2(a)), praktycznie 1-4 h dla wiarygodnej leak detection. '
          'Fluid: water default (incompressible, low stored energy). Avoid chloride water on SS (>50 ppm = pitting risk). '
          'Pneumatic test allowed only when hydro impractical (cryogenic, vacuum) — duże zagrożenie energii.',
          'ASME B31.3 §345.4.2: **P_test ≥ 1.5 × P_design × S_T/S** — S_T is the allowable stress at test temperature, S at design temperature (S_T/S ≤ 6.5; at ambient design T usually S_T/S = 1 → 1.5 × P_design). '
          'Pneumatic (§345.5.4): P_test ≥ 1.1 × P_design. '
          'Hold time: min 10 min (§345.2.2(a)), practical 1-4 h for reliable leak detection. '
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
      HelpEntry(
        id: 'fillet-weld-capacity',
        question: _bi(
          'Ile udźwignie spoina pachwinowa (wspornik, ucho, podpora)?',
          'How much load can a fillet weld carry (bracket, lug, support)?',
        ),
        answer: _bi(
          'Wg EN 1993-1-8 (w Polsce PN-EN 1993-1-8:2006 + AC:2009), metoda uproszczona: F_w,Rd = fvw,d · a · Σl_eff, '
          'gdzie fvw,d = fu / (√3 · βw · γM2), γM2 = 1,25. '
          'βw: S235 — 0,80, S275 — 0,85, S355 — 0,90, S420 i S460 — 1,0; fu (t ≤ 40 mm): S235 — 360, S275 — 430, S355 — 490, '
          'S420 — 520, S460 — 540 MPa. Długość efektywna każdej spoiny l_eff = l − 2a (spoina obwodowa rury do blachy: π·D, '
          'bez odejmowania). '
          'Metoda kierunkowa: siła w poprzek spoiny daje ok. 1,22 razy więcej niż wzdłuż. Ciężar (obciążenie stałe) mnóż × 1,35, '
          'obciążenie zmienne × 1,5 — chyba że wpisujesz już siłę obliczeniową. '
          'Narzędzie „Nośność spoiny pachwinowej” sprawdza TYLKO spoinę — nie blachy, śruby, wyboczenie ani zmęczenie — '
          'i nie zastępuje projektu konstruktora.',
          'Per EN 1993-1-8 (in Poland PN-EN 1993-1-8:2006 + AC:2009), simplified method: F_w,Rd = fvw,d · a · Σl_eff, '
          'where fvw,d = fu / (√3 · βw · γM2), γM2 = 1.25. '
          'βw: S235 — 0.80, S275 — 0.85, S355 — 0.90, S420 and S460 — 1.0; fu (t ≤ 40 mm): S235 — 360, S275 — 430, S355 — 490, '
          'S420 — 520, S460 — 540 MPa. Effective length of each weld l_eff = l − 2a (circumferential tube-to-plate weld: π·D, '
          'nothing deducted). '
          'Directional method: a force across the weld gives about 1.22 times more than along it. Multiply dead weight (permanent load) × 1.35 '
          'and variable load × 1.5 — unless you already enter the design force. '
          'The "Fillet weld resistance" tool checks ONLY the weld — not the plates, bolts, buckling or fatigue — '
          'and does not replace the structural engineer’s design.',
        ),
        tags: ['spoina pachwinowa', 'fillet weld', 'nosnosc', 'resistance', 'capacity', 'eurokod', 'eurocode', 'en 1993-1-8', 'wspornik', 'bracket', 'ucho', 'lug'],
      ),
      HelpEntry(
        id: 'fillet-throat-leg',
        question: _bi(
          'Grubość a czy bok z — i jakie a wystarczy?',
          'Throat a or leg z — and what throat is enough?',
        ),
        answer: _bi(
          'Na rysunku „a” to grubość obliczeniowa spoiny pachwinowej, „z” — długość boku. Dla ścianek pod kątem prostym a = z/√2 '
          '(z = a·√2); przy innym kącie tak nie przeliczaj. EN 1993-1-8 traktuje jako pachwinowe spoiny przy kącie między ściankami 60°–120°. '
          'Zasady: a ≥ 3 mm; spoina krótsza niż max(30 mm; 6a) nie przenosi obciążeń; przy spoinie dłuższej niż 150a nośność '
          'zmniejsza współczynnik βLw (długie połączenia), a od 900a spoina jest za długa dla tej grubości a. '
          'Wpisz siłę, a narzędzie „Nośność spoiny pachwinowej” poda najmniejsze a (w górę do 0,1 mm i do całego mm) oraz bok z. '
          'Jeśli nie wystarcza nawet największe a dopuszczalne dla tej długości — potrzebna dłuższa spoina albo więcej spoin.',
          'On a drawing "a" is the fillet weld throat thickness and "z" the leg length. For walls at a right angle a = z/√2 '
          '(z = a·√2); at any other angle do not convert like that. EN 1993-1-8 treats welds as fillet welds for an angle between the walls of 60°–120°. '
          'Rules: a ≥ 3 mm; a weld shorter than max(30 mm; 6a) carries no load; above 150a the long-joint factor βLw '
          'reduces the resistance, and from 900a the weld is too long for that throat a. '
          'Enter the force and the "Fillet weld resistance" tool gives the smallest a (rounded up to 0.1 mm and to a whole mm) and the leg z. '
          'If even the largest a allowed for this length is not enough — you need a longer weld or more welds.',
        ),
        tags: ['grubosc a', 'throat', 'bok z', 'leg', 'spoina pachwinowa', 'fillet weld', 'wymiar spoiny', 'weld size'],
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

  // ════════════════════════════════════════════════════════════════════════
  // 14. APLIKACJA I KONTO — jak działa sama aplikacja (czat, dane, skaner,
  // asystent, kopia, kontakt). Apple 1.2 / Google Play: kontakt i usuwanie
  // danych mają być łatwe do znalezienia, nie tylko w profilu.
  // ════════════════════════════════════════════════════════════════════════
  HelpCategory(
    id: 'app-account',
    title: _bi('Aplikacja i konto', 'App and account'),
    subtitle: _bi('Czat, dane, skaner, asystent, kopia',
        'Chat, data, scanner, assistant, backup'),
    icon: Icons.smartphone,
    accentArgb: 0xFF9BA3C7,
    entries: [
      HelpEntry(
        id: 'app-chat-report',
        question: _bi(
          'Jak zgłosić wiadomość albo zablokować kogoś na czacie?',
          'How do I report a message or block someone in chat?',
        ),
        answer: _bi(
          'Stuknij ⋮ przy wiadomości (albo ją przytrzymaj) i wybierz „Zgłoś wiadomość" lub „Zablokuj autora". '
          'Zgłoszona wiadomość od razu znika u Ciebie, a po 3 zgłoszeniach od różnych osób — u wszystkich; zgłoszenie trafia do kolejki moderacji. '
          'Blokada działa tylko na Twoim telefonie i autor się o niej nie dowie. Odblokujesz go w Profilu → Zablokowani.',
          'Tap ⋮ next to a message (or long-press it) and choose "Report message" or "Block author". '
          'A reported message disappears for you right away, and after 3 reports from different people — for everyone; the report goes to the moderation queue. '
          'A block works only on your phone and the author is not told. Undo it in Profile → Blocked.',
        ),
        tags: ['czat', 'chat', 'zgloszenie', 'zglos', 'report', 'blokada', 'block', 'moderacja'],
      ),
      HelpEntry(
        id: 'app-delete-data',
        question: _bi(
          'Gdzie usunąć swoje dane?',
          'Where do I delete my data?',
        ),
        answer: _bi(
          'Profil → „Usuń moje dane". Najpierw usuwamy z serwera Twoje wiadomości z czatu, zgłoszenia i identyfikator instalacji, '
          'potem z telefonu: imię i nazwisko, zgody (zasady, skaner), historię asystenta, listę zablokowanych i tożsamość spawacza. '
          'Projekty, cut listy i dziennik spoin zostają. Bez aplikacji napisz na ${AppLinks.supportEmail}.',
          'Profile → "Delete my data". First we delete your chat messages, reports and installation identifier from the server, '
          'then from the phone: your name, consents (rules, scanner), the assistant history, your block list and welder identity. '
          'Projects, cut lists and the weld journal stay. Without the app, write to ${AppLinks.supportEmail}.',
        ),
        tags: ['usun-dane', 'usun', 'dane', 'rodo', 'prywatnosc', 'delete', 'gdpr', 'privacy'],
      ),
      HelpEntry(
        id: 'app-scanner',
        question: _bi(
          'Co wysyła skaner rysunków i jaki ma limit?',
          'What does the drawing scanner send and what is the limit?',
        ),
        answer: _bi(
          'Po Twojej zgodzie zdjęcie rysunku idzie na nasz serwer, a stamtąd do Anthropic (model Claude), który odczytuje wymiary i elementy. '
          'Serwer nie zapisuje zdjęcia. Skaner jest darmowy, z limitem $kAiScanDailyLimitPerDevice skanów dziennie na telefon. '
          'Niepewne wartości są oznaczone — sprawdź je z rysunkiem. Zgodę wycofasz w Profilu → Zgody.',
          'With your consent the drawing photo goes to our server and on to Anthropic (the Claude model), which reads the dimensions and components. '
          'The server does not store the photo. The scanner is free, with a limit of $kAiScanDailyLimitPerDevice scans a day per phone. '
          'Uncertain values are flagged — check them against the drawing. Withdraw consent in Profile → Consents.',
        ),
        tags: ['skaner', 'scanner', 'zdjecie', 'rysunek', 'iso', 'limit', 'anthropic'],
      ),
      HelpEntry(
        id: 'app-assistant',
        question: _bi(
          'Co wysyła asystent?',
          'What does the assistant send?',
        ),
        answer: _bi(
          'Polecenia rozpoznane na telefonie („otwórz kalkulator", „zapisz parametry") nie opuszczają telefonu. '
          'Tryb „Odpowiedz" i polecenia, których telefon nie rozpozna, wysyłają treść pytania i kilka ostatnich wiadomości rozmowy na nasz serwer i do Anthropic — bez imienia i nazwiska. '
          'Nie zapisujemy pytań ani odpowiedzi. Mowę na tekst zamienia system telefonu.',
          'Commands recognised on the phone ("open the calculator", "save parameters") never leave the phone. '
          '"Answer" mode and commands the phone cannot recognise send the question and a few recent messages to our server and to Anthropic — without your name. '
          'We do not store questions or answers. Speech is turned into text by the phone\'s system.',
        ),
        tags: ['asystent', 'assistant', 'ai', 'mikrofon', 'glos', 'voice', 'anthropic'],
      ),
      HelpEntry(
        id: 'app-backup',
        question: _bi(
          'Jak przenieść dane na nowy telefon?',
          'How do I move my data to a new phone?',
        ),
        answer: _bi(
          'Profil → „Kopia zapasowa" tworzy jeden plik ZIP (projekty, cut listy, dziennik spoin, zdjęcia, rejestr uprawnień, Biblioteka WPS, historia ferrytu i PMI). '
          'Zapisz go albo wyślij sobie, a na nowym telefonie: Profil → „Przywróć z pliku" (nadpisuje dane na tym telefonie). '
          'Na Androidzie z włączoną kopią Google system może też sam odtworzyć projekty i dziennik — bez imienia, zgód i identyfikatora czatu.',
          'Profile → "Back up my data" creates one ZIP file (projects, cut lists, weld journal, photos, qualification register, WPS library, ferrite and PMI history). '
          'Save it or send it to yourself, and on the new phone: Profile → "Restore from a file" (overwrites the data on that phone). '
          'On Android with Google backup on, the system may also restore projects and the journal itself — without your name, consents or chat identifier.',
        ),
        tags: ['kopia', 'backup', 'przywroc', 'restore', 'nowy-telefon', 'zip'],
      ),
      HelpEntry(
        id: 'app-pin',
        question: _bi(
          'Jak przypiąć narzędzie na ekranie głównym?',
          'How do I pin a tool to the home screen?',
        ),
        answer: _bi(
          'Przytrzymaj narzędzie w menu Montera, Spawacza albo w wynikach wyszukiwania — trafi do „Przypięte" na górze ekranu głównego. '
          'Tak samo je odepniesz. Wyszukiwarka na ekranie głównym znajduje też Czat, Profil, „Usuń moje dane" i zasady.',
          'Long-press a tool in the Fitter or Welder menu or in search results — it goes to "Pinned" at the top of the home screen. '
          'Do the same to unpin it. The home screen search also finds Chat, Profile, "Delete my data" and the rules.',
        ),
        tags: ['przypnij', 'pin', 'ulubione', 'favorite', 'wyszukiwarka'],
      ),
      HelpEntry(
        id: 'app-contact',
        question: _bi(
          'Jak się z nami skontaktować?',
          'How do I contact you?',
        ),
        answer: _bi(
          'Napisz na ${AppLinks.supportEmail} — pytania, błędy, prośby o usunięcie danych. Adres jest też w Profilu → „Kontakt".',
          'Write to ${AppLinks.supportEmail} — questions, bugs, data deletion requests. The address is also in Profile → "Contact".',
        ),
        tags: ['kontakt', 'contact', 'email', 'support', 'pomoc'],
      ),
    ],
  ),

  // ════════════════════════════════════════════════════════════════════════
  // WYCENY I KOSZTY — narzędzia „Wyceny spawalnicze” i „Ile brać za godzinę”
  // ════════════════════════════════════════════════════════════════════════
  HelpCategory(
    id: 'quotes-costs',
    title: _bi('Wyceny i koszty', 'Quotes and costs'),
    subtitle: _bi('Cena roboty, DI, spoiwo, stawka', 'Job price, DI, filler, rate'),
    icon: Icons.request_quote_outlined,
    accentArgb: 0xFF35C88B,
    entries: [
      HelpEntry(
        id: 'quote-dia-inch',
        question: _bi(
          'Co to jest cal-średnica (DI) i jak z niej liczyć cenę?',
          'What is a diameter-inch (DI) and how do I price with it?',
        ),
        answer: _bi(
          'Cal-średnica (dia-inch, DI) = rozmiar rury NPS w calach × liczba spoin. 10 spoin DN100 (4") = 40 DI, '
          '4 spoiny DN150 (6") = 24 DI. Firmy rurociągowe rozliczają spawanie w zł/DI, bo DI rośnie razem '
          'z ilością pracy. Uwaga: zwykła stawka DI zakłada typowe ścianki (STD/Sch 40) — grubsze ścianki, '
          'nierdzewka, P91 czy pozycja 6G to dużo więcej stopiwa i czasu. W „Wycenach spawalniczych” zobaczysz '
          'Twoją cenę netto na DI i porównasz ją ze stawką rynkową.',
          'Diameter-inch (DI) = pipe size NPS in inches × number of welds. 10 welds DN100 (4") = 40 DI, '
          '4 welds DN150 (6") = 24 DI. Piping contractors price welding per DI because DI grows with the amount '
          'of work. Note: a plain DI rate assumes typical walls (STD/Sch 40) — thicker walls, stainless, P91 or '
          '6G mean far more weld metal and time. "Welding quotes" shows your net price per DI and compares it '
          'with the market rate.',
        ),
        tags: ['di', 'dia-inch', 'cal', 'cal-srednica', 'wycena', 'cena', 'stawka', 'quote'],
      ),
      HelpEntry(
        id: 'quote-filler-per-weld',
        question: _bi(
          'Ile spoiwa i czasu idzie na jedną spoinę rury?',
          'How much filler and time does one pipe weld take?',
        ),
        answer: _bi(
          'Masa stopiwa = pole przekroju rowka × długość spoiny × gęstość. Przykład: DN100 Sch 40 (Ø114,3 × 6,02), '
          'rowek V 60°, stal węglowa — ok. 0,11 kg stopiwa; DN150 STD (7,11 mm) — ok. 0,21 kg. Kupić trzeba więcej: '
          'elektrody MMA zostawiają ogarki i żużel (uzysk ok. 60%), pręty TIG ok. 95%, drut MAG ok. 92%. '
          'Czas łuku = stopiwo ÷ wydajność stapiania (TIG ok. 0,5 kg/h, MMA ok. 1 kg/h), a czas spawania to czas '
          'łuku podzielony przez współczynnik jarzenia (ok. 30–40%) i wydłużony w pozycjach wymuszonych. '
          'Wszystko to liczy narzędzie „Wyceny spawalnicze” — z listą zakupów w pełnych paczkach.',
          'Weld metal mass = groove cross-section × weld length × density. Example: DN100 Sch 40 (Ø114.3 × 6.02), '
          '60° V groove, carbon steel — about 0.11 kg; DN150 STD (7.11 mm) — about 0.21 kg. You buy more: '
          'MMA electrodes leave stubs and slag (about 60% efficiency), TIG rods about 95%, MAG wire about 92%. '
          'Arc time = deposit ÷ deposition rate (TIG about 0.5 kg/h, MMA about 1 kg/h); welding time is arc time '
          'divided by the arc duty (about 30–40%) and stretched in difficult positions. '
          '"Welding quotes" works all of this out — with a shopping list in full packs.',
        ),
        tags: ['spoiwo', 'stopiwo', 'elektrody', 'drut', 'zuzycie', 'filler', 'consumption', 'czas', 'kg'],
      ),
      HelpEntry(
        id: 'quote-duty-cycle',
        question: _bi(
          'Co to jest współczynnik jarzenia łuku i czemu wycena „z łuku” jest za niska?',
          'What is arc duty and why is pricing "from arc time" too low?',
        ),
        answer: _bi(
          'Łuk pali się tylko przez część czasu spawania: resztę zjada czyszczenie między ściegami, wymiana '
          'elektrody, szlifowanie zakończeń, kontrola temperatury międzyściegowej. Przy MMA łuk to zwykle ok. 30% '
          'czasu, przy TIG 30–40%, przy MAG/FCAW 40% i więcej. Do tego dochodzi przygotowanie: fazowanie, ustawienie, '
          'sczepianie — często tyle samo co spawanie. Wycena tylko z czasu łuku zaniża robociznę 3–4 razy. '
          'Zmierz na swojej brygadzie i popraw „Założenia procesów” w wycenie.',
          'The arc burns only part of the welding time: the rest goes to cleaning between passes, changing '
          'electrodes, grinding stops and starts, checking interpass temperature. With MMA the arc is usually about '
          '30% of the time, TIG 30–40%, MAG/FCAW 40% and more. Then there is prep: bevelling, fit-up, tacking — often '
          'as long as the welding. Pricing from arc time alone undercuts labour 3–4 times. '
          'Measure it on your crew and adjust "Process assumptions" in the quote.',
        ),
        tags: ['jarzenie', 'duty cycle', 'arc time', 'czas luku', 'robocizna', 'wycena', 'labour'],
      ),
      HelpEntry(
        id: 'quote-hourly-rate',
        question: _bi(
          'Ile brać za godzinę na własnej działalności?',
          'What should I charge per hour when self-employed?',
        ),
        answer: _bi(
          'Stawka musi pokryć: to, co chcesz mieć na rękę, koszty firmy (ZUS, składka zdrowotna, księgowość, auto, '
          'sprzęt do wymiany, OC, BHP) i podatek — a dzieli się ją tylko przez godziny, które naprawdę zafakturujesz. '
          'Dojazdy, przestoje, papiery, urlop i przerwy między zleceniami to zwykle 25–40% czasu bez zapłaty. '
          'Narzędzie „Ile brać za godzinę” liczy stawkę minimalną i dniówkę, a z wyceny wpisuje ją jednym dotknięciem. '
          'Stawkę podatku (zwłaszcza ryczałtu dla Twojego PKD) i ZUS potwierdź z księgowym.',
          'Your rate must cover what you want to take home, business costs (social and health contributions, '
          'accounting, van, equipment to replace, liability insurance, PPE) and tax — divided only by the hours you '
          'actually bill. Travel, downtime, paperwork, holidays and gaps between jobs are usually 25–40% of unpaid '
          'time. "What to charge per hour" works out the minimum rate and day rate, and fills it into a quote with '
          'one tap. Confirm the tax rate and contributions with your accountant.',
        ),
        tags: ['stawka', 'godzina', 'zus', 'podatek', 'ryczalt', 'b2b', 'dzialalnosc', 'rate', 'hourly'],
      ),
      HelpEntry(
        id: 'quote-client-vs-internal',
        question: _bi(
          'Co wysłać klientowi, a co zostawić dla siebie?',
          'What do I send the client and what do I keep?',
        ),
        answer: _bi(
          '„Oferta PDF dla klienta” zawiera zakres (pozycje i ilości), cenę netto, VAT, brutto, termin realizacji '
          'i warunki — bez stawek godzinowych, narzutu, zysku i założeń. „Kosztorys wewnętrzny” ma wszystko: '
          'każdy składnik kosztu, godziny, kilogramy, butle i założenia procesów — do Twojej kontroli albo dla szefa. '
          'Wycena pamięta stawki z dnia utworzenia, więc wysłana oferta nie zmieni się po podwyżce cen.',
          '"Client quote PDF" holds the scope (items and quantities), net price, VAT, gross, lead time and terms — '
          'without hourly rates, overhead, profit and assumptions. "Internal cost estimate" has everything: every '
          'cost element, hours, kilograms, cylinders and process assumptions — for you or your boss. '
          'A quote keeps the rates from the day it was created, so a sent quote does not change after a price rise.',
        ),
        tags: ['oferta', 'pdf', 'klient', 'kosztorys', 'narzut', 'zysk', 'quote', 'client'],
      ),
      HelpEntry(
        id: 'quote-import-welds',
        question: _bi(
          'Jak wziąć do wyceny spoiny ze skanu, dziennika albo projektu CUT?',
          'How do I bring welds from a scan, the journal or a CUT project into a quote?',
        ),
        answer: _bi(
          'W wycenie dotknij „Importuj spoiny (skan ISO, dziennik)” i wybierz źródło: zapisany odczyt skanera izometryku '
          '(mapa spoin z rysunku), dziennik spoin (projekt albo pakiet testowy, np. wycena dokończenia pakietu) albo projekt CUT '
          '(trasa z listy cięć). '
          'Podgląd grupuje spoiny po rodzaju złącza, wymiarze i pozycji, np. „12 × doczołowa DN100 Sch 40, PF / 5G” — odznacz, '
          'co nie wchodzi, a pozycję zmienisz przy grupie. Oznaczenia: BW — doczołowa; SW (mufa) i FW — pachwina z a ≈ 0,77 × '
          'ścianka (w górę do 0,5 mm, min. 3 mm; ASME B31.3 rys. 328.5.2C); BR — króciec nasadzany. Brak oznaczenia — doczołowa, '
          'brak pozycji — PA w warsztacie, PF na obiekcie; oba pokazane jako założenie.',
          'In the quote tap "Import welds (ISO scan, journal)" and pick the source: a stored isometric scanner reading '
          '(the weld map of the drawing), the weld journal (a project or a test package, e.g. a quote to finish a package) or a CUT project '
          '(a route from the cut list). '
          'The preview groups the welds by joint type, size and position, e.g. "12 × butt weld DN100 Sch 40, PF / 5G" — untick '
          'what is not in the job, and change the position on the group. Codes: BW — butt weld; SW (socket) and FW — fillet with a ≈ 0.77 × '
          'wall (rounded up to 0.5 mm, min. 3 mm; ASME B31.3 Fig. 328.5.2C); BR — set-on branch. No code — butt weld, '
          'no position — PA in the shop, PF in the field; both are shown as assumptions.',
        ),
        tags: ['import', 'importuj spoiny', 'import welds', 'skan', 'scan', 'dziennik', 'journal', 'cut', 'wycena', 'quote', 'spoiny', 'welds'],
      ),
      HelpEntry(
        id: 'quote-import-skipped',
        question: _bi(
          'Dlaczego część spoin z importu jest „pominięta” albo „do sprawdzenia”?',
          'Why are some imported welds "skipped" or "to check"?',
        ),
        answer: _bi(
          'Import nie zgaduje wymiarów: spoina bez OD albo ścianki jest pominięta, tak samo wymiar, z którym wycena byłaby błędna '
          '(ścianka ≥ promień, literówka typu „114300”). W dzienniku wymiar musi być liczbą („114,3”, „Ø114,3 mm”) — „DN100” to nie '
          'średnica (DN100 rury higienicznej to Ø104, nie Ø114,3). '
          'Projekt CUT nie zapisuje, jak kołnierze i zawory łączą się z rurą — wybierz w podglądzie: kołnierz WN / zawór BW — '
          'doczołowa, SO / SW — pachwinowa, luźny, gwintowany albo kołnierzowy — bez spoiny; „Nie wiem” zostawia je do sprawdzenia. '
          'Do sprawdzenia trafia też kształtka bez typu i koniec kształtki bez rury po drugiej stronie. '
          'Spoiny z CUT: na każdym końcu odcinka przy kształtce (rura–kolano–rura to 2, trójnik 3, redukcja 2) i doczołowa rura–rura '
          'na każdy podział odcinka dłuższego niż sztanga. Końce otwarte są bez spoiny, a olety i króćce nasadzane (BR) nie są '
          'zapisane w projekcie CUT — dopisz je ręcznie.',
          'The import never guesses sizes: a weld without an OD or wall is skipped, and so is a size that would make the quote wrong '
          '(wall ≥ radius, a typo like "114300"). In the journal the size must be a number ("114.3", "Ø114.3 mm") — "DN100" is not a '
          'diameter (DN100 hygienic tube is Ø104, not Ø114.3). '
          'A CUT project does not record how flanges and valves join the pipe — pick it in the preview: weld neck flange / BW valve — '
          'butt weld, SO / SW — fillet weld, lap-joint, threaded or flanged — no weld; "Not sure" leaves them to check. '
          'A fitting without a type and a fitting end with no pipe on the other side also go to check. '
          'Welds from CUT: at every end of a pipe piece that meets a fitting (pipe–elbow–pipe is 2, a tee 3, a reducer 2) and a pipe-to-pipe '
          'butt weld for every split of a piece longer than the stock bar. Open ends have no weld, and olets and set-on branches (BR) are '
          'not recorded in a CUT project — add them by hand.',
        ),
        tags: ['import', 'pominiete', 'skipped', 'do sprawdzenia', 'to check', 'cut', 'kolnierz', 'flange', 'zawor', 'valve', 'wymiar', 'od'],
      ),
      HelpEntry(
        id: 'piecework-di-rate',
        question: _bi(
          'Jak sprawdzić, ile zarobiłem na akordzie (zł/DI albo za spoinę)?',
          'How do I check my piecework pay (per DI or per weld)?',
        ),
        answer: _bi(
          'Narzędzie „Akord: ile zarobiłem” liczy z dziennika spoin — spoina po spoinie, żeby dało się sprawdzić rozliczenie od firmy. '
          'Stawka: za cal-średnicę (zł/DI) albo za spoinę. DI spoiny = rozmiar NPS w calach z jej OD (tabela B36.10M / B36.19M); '
          'OD spoza tabeli — OD / 25,4, oznaczone „≈”. Spoina bez OD w trybie DI NIE jest wliczana — trafia na listę pominiętych, '
          'dopóki nie uzupełnisz wymiaru. '
          'Dopłaty to procent PODSTAWY spoiny i sumują się, nie mnożą: materiał (nierdzewna, inne), pozycja (2G; 5G — także PF, PG, '
          'PH, PJ; 6G — także H-L045, J-L045; 1G/PA bez dopłaty), gruba ścianka (od Sch 80 albo od progu w mm). '
          'Liczy się data spoiny z dziennika, status nie ma znaczenia. Kwoty są przed podatkiem, zaokrąglone do grosza na każdej '
          'spoinie; zestawienie wyślesz tekstem albo jako PDF.',
          'The "Piecework: what I earned" tool works from the weld journal — weld by weld, so you can check the company’s settlement. '
          'Rate: per dia-inch (zł/DI) or per weld. A weld’s DI = NPS size in inches from its OD (B36.10M / B36.19M table); '
          'an OD outside the table — OD / 25.4, marked "≈". In DI mode a weld without an OD is NOT counted — it goes on the skipped list '
          'until you fill in the size. '
          'Surcharges are a percentage of the weld’s BASE and add up, not multiply: material (stainless, other), position (2G; 5G — also PF, PG, '
          'PH, PJ; 6G — also H-L045, J-L045; 1G/PA no surcharge), heavy wall (from Sch 80 or from a mm threshold). '
          'The weld date in the journal counts, the status does not. Amounts are before tax, rounded to the grosz on each '
          'weld; send the summary as text or as a PDF.',
        ),
        tags: ['akord', 'piecework', 'zarobek', 'earnings', 'di', 'dia-inch', 'stawka', 'rate', 'doplata', 'surcharge', 'rozliczenie'],
      ),
      HelpEntry(
        id: 'piecework-rejects-split',
        question: _bi(
          'Odrzucona spoina, naprawa, dwóch spawaczy — jak to liczy akord?',
          'Rejected weld, repair, two welders — how does piecework count it?',
        ),
        answer: _bi(
          'Spoina odrzucona = ma naprawę (R1, R2…) albo status NOK lub wynik NOK któregokolwiek badania (VT, PT, MT, RT, UT). '
          'Potrącenie to ustawiony % wartości spoiny (podstawa + dopłaty) — 100 % oznacza spoinę za 0 zł. Naprawa może być płatna '
          'osobno: % wartości spoiny za każdy rekord naprawy. Potrącenia i naprawy liczą się w okresie spoiny (data z dziennika), '
          'nie w dniu naprawy. '
          'Spoina z kilkoma spawaczami (stemple: spawacz, grań, lico) — każdy składnik dzielony bez gubienia groszy, przy dwóch '
          'spawaczach po połowie. „Cała brygada” liczy każdą spoinę raz, w całości. '
          'Minimum dzienne działa tylko dla jednego spawacza: dzień, który dał mniej, jest dopłacany do minimum — chyba że tego dnia '
          'są spoiny pominięte (bez OD); wtedy najpierw uzupełnij wymiar w dzienniku.',
          'A rejected weld = it has a repair (R1, R2…) or a NOK status or a NOK result of any test (VT, PT, MT, RT, UT). '
          'The deduction is the set % of the weld’s value (base + surcharges) — 100 % means the weld pays 0 zł. A repair can be paid '
          'separately: % of the weld value for every repair record. Deductions and repairs count in the period of the weld (journal date), '
          'not on the day of the repair. '
          'A weld with several welders (stamps: welder, root, cap) — every part is split without losing a grosz, with two '
          'welders half each. "Whole crew" counts every weld once, in full. '
          'The daily minimum works only for a single welder: a day that paid less is topped up to the minimum — unless that day '
          'has skipped welds (no OD); then fill in the size in the journal first.',
        ),
        tags: ['akord', 'piecework', 'naprawa', 'repair', 'odrzucona', 'rejected', 'potracenie', 'deduction', 'brygada', 'crew', 'minimum dzienne'],
      ),
    ],
  ),
];
