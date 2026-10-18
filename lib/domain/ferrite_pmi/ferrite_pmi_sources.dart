/// Źródła i wartości normowe modułu „Ferryt i PMI”.
///
/// KAŻDA liczba normowa w module jest tutaj, ze źródłem i wydaniem.
/// Czego nie potwierdzono w tekście normy albo w dwóch niezależnych
/// źródłach — nie ma (albo jest oznaczone „przyjęte w aplikacji”).
///
/// Weryfikacja 2026-10-18:
///  • ASTM A240/A240M-25a (wiersze jak w -20a), ASME SA-240 BPVC II-A 2025
///    (= A240-17), A312/A312M-25 (= -24 = SA-312 2025), A790/A790M-24,
///    A335/A335M-23 — odczytane z tekstu norm (PDF);
///  • EN 10088-1:2014 (wycofana; wyd. 2023 zmieniło skład 1.4404 — nowe
///    wartości niepotwierdzone), EN 10216-5:2013/2021, EN 10095:1999 —
///    przedruki producentów i baz materiałowych; EN 10216-2:2013+A1:2019
///    i EN 10028-2:2017 — tekst normy porównany z Salzgitter Mannesmann
///    i h2abc (szczegóły przy gatunku);
///  • ferryt: ISO 17781:2017 (spis treści — tekst 5.3.2; liczby z dwóch
///    niezależnych źródeł wtórnych), API TR 938-C wyd. 2 (2011; dwa źródła
///    wtórne), IOGP S-705 (2020; tekst dokumentu), ASME VIII-1 UHA-51
///    (trzy źródła wtórne), wymagania licencjodawców mocznika (literatura
///    branżowa + karta producenta).
///
/// Celowo POMINIĘTE (niepotwierdzone): zakresy NORSOK M-601:2016 (30–70 %
/// tylko z fragmentów nieoficjalnych kopii; potwierdzony tekst Rev.2 1997
/// jest nieaktualny), wartości API TR 938-C wyd. 2015 i 2024, liczby
/// FN z tekstu API RP 582, granica 316L w UHA-51 (źródła sprzeczne: FN ≤ 5
/// albo ≤ 10), ferryt spoin w instalacjach mocznika (jedno źródło),
/// współczynnik przeliczenia FN ↔ % (źródła sprzeczne).
///
/// Czysty Dart.
library;

import 'ferrite.dart';
import 'pmi.dart';

class FerritePmiSource {
  final String pl;
  final String en;
  const FerritePmiSource(this.pl, this.en);
  String label({required bool en}) => en ? this.en : pl;
}

// ═══════════════════════════════════════════════════════════════════════════
// FERRYT — PRESETY (TYPOWE — DECYDUJE SPECYFIKACJA)
// ═══════════════════════════════════════════════════════════════════════════

const Set<FerriteLocation> _weld = {FerriteLocation.weld};
const Set<FerriteLocation> _haz = {FerriteLocation.hazA, FerriteLocation.hazB};
const Set<FerriteLocation> _base = {FerriteLocation.base};

const String _iso17781 = 'ISO 17781:2017';
const String _iso17781SrcPl =
    '$_iso17781, 5.3.2 (kryteria przyjęcia) — liczby wg R. Francis, '
    'G. Byrne, Stainless Steel World 01/02.2022, tab. 1 oraz Outokumpu '
    '(R. Vishnu, 2021)';
const String _iso17781SrcEn =
    '$_iso17781, 5.3.2 (acceptance criteria) — figures per R. Francis, '
    'G. Byrne, Stainless Steel World Jan/Feb 2022, Table 1 and Outokumpu '
    '(R. Vishnu, 2021)';
const String _iso17781NotePl =
    'Norma: udział objętościowy z metalografii (ASTM E562 / E1245). Odczyt '
    'ferrytomierza jest orientacyjny — czy wolno nim odbierać, decyduje '
    'specyfikacja.';
const String _iso17781NoteEn =
    'Standard: volume fraction by metallography (ASTM E562 / E1245). A '
    'ferritescope reading is indicative — the specification decides whether '
    'it may be used for acceptance.';

const String _api938c = 'API TR 938-C, wyd. 2 (2011)';
const String _api938cEn = 'API TR 938-C, 2nd ed. (2011)';
const String _api938cSrcPl =
    '$_api938c — wg Hosseini i in., Welding in the World 2018 oraz '
    'Outokumpu (2021); numeru punktu nie potwierdzono';
const String _api938cSrcEn =
    '$_api938cEn — per Hosseini et al., Welding in the World 2018 and '
    'Outokumpu (2021); clause number not confirmed';
const String _api938cNotePl =
    'Wydania 2015 i 2024 (aktualne: wyd. 4, 2024) — wartości '
    'niepotwierdzone; obowiązuje wydanie przywołane w kontrakcie.';
const String _api938cNoteEn =
    'Editions 2015 and 2024 (current: 4th ed., 2024) — values not '
    'confirmed; the edition invoked by the contract governs.';

/// Presety — wartości TYPOWE. Wszystkie granice włącznie.
const List<FerritePreset> kFerritePresets = [
  FerritePreset(
    id: 'iso17781_weld',
    group: FerritePresetGroup.duplex,
    requirement:
        FerriteRequirement(min: 30, max: 70, unit: FerriteUnit.percent),
    appliesTo: _weld,
    titlePl: 'Duplex — spoina w stanie po spawaniu ($_iso17781)',
    titleEn: 'Duplex — weld, as-welded ($_iso17781)',
    sourcePl: _iso17781SrcPl,
    sourceEn: _iso17781SrcEn,
    notePl: 'Ten sam zakres dla lean duplex, 22Cr i 25Cr. SWC — norma osobnego '
        'zakresu nie podaje (nie potwierdzono). $_iso17781NotePl',
    noteEn: 'Same range for lean duplex, 22Cr and 25Cr. HAZ — no separate '
        'range confirmed. $_iso17781NoteEn',
  ),
  FerritePreset(
    id: 'iso17781_base',
    group: FerritePresetGroup.duplex,
    requirement:
        FerriteRequirement(min: 35, max: 60, unit: FerriteUnit.percent),
    appliesTo: _base,
    titlePl: 'Duplex — materiał rodzimy ($_iso17781)',
    titleEn: 'Duplex — base metal ($_iso17781)',
    sourcePl: _iso17781SrcPl,
    sourceEn: _iso17781SrcEn,
    notePl: _iso17781NotePl,
    noteEn: _iso17781NoteEn,
  ),
  FerritePreset(
    id: 'api938c_2011_weld',
    group: FerritePresetGroup.duplex,
    requirement:
        FerriteRequirement(min: 25, max: 60, unit: FerriteUnit.percent),
    appliesTo: _weld,
    titlePl: 'Duplex, rafineria — spoina ($_api938c)',
    titleEn: 'Duplex, refinery — weld zone ($_api938cEn)',
    sourcePl: _api938cSrcPl,
    sourceEn: _api938cSrcEn,
    notePl: _api938cNotePl,
    noteEn: _api938cNoteEn,
  ),
  FerritePreset(
    id: 'api938c_2011_haz',
    group: FerritePresetGroup.duplex,
    requirement:
        FerriteRequirement(min: 40, max: 65, unit: FerriteUnit.percent),
    appliesTo: _haz,
    titlePl: 'Duplex, rafineria — SWC ($_api938c)',
    titleEn: 'Duplex, refinery — HAZ ($_api938cEn)',
    sourcePl: _api938cSrcPl,
    sourceEn: _api938cSrcEn,
    notePl: _api938cNotePl,
    noteEn: _api938cNoteEn,
  ),
  FerritePreset(
    id: 'api938c_2011_base',
    group: FerritePresetGroup.duplex,
    requirement:
        FerriteRequirement(min: 30, max: 65, unit: FerriteUnit.percent),
    appliesTo: _base,
    titlePl: 'Duplex, rafineria — materiał rodzimy ($_api938c)',
    titleEn: 'Duplex, refinery — base metal ($_api938cEn)',
    sourcePl: _api938cSrcPl,
    sourceEn: _api938cSrcEn,
    notePl: _api938cNotePl,
    noteEn: _api938cNoteEn,
  ),
  FerritePreset(
    id: 'iogp_s705_fn3_10',
    group: FerritePresetGroup.austenitic,
    requirement: FerriteRequirement(min: 3, max: 10, unit: FerriteUnit.fn),
    appliesTo: _weld,
    // IOGP S-705 (2020) 12.13.3: co najmniej 3 odczyty FN na spoinę.
    minReadings: 3,
    titlePl: 'Spoina austenityczna — praca > 350 °C, < −101 °C albo PWHT '
        '(IOGP S-705:2020)',
    titleEn: 'Austenitic weld — service > 350 °C, < −101 °C or PWHT '
        '(IOGP S-705:2020)',
    sourcePl: 'IOGP S-705 (06.2020, uzupełnienie API RP 582 wyd. 3, 2016), '
        '12.13.1; min. 3 odczyty na spoinę — 12.13.3',
    sourceEn: 'IOGP S-705 (June 2020, supplement to API RP 582 3rd ed. '
        '2016), 12.13.1; at least 3 readings per weld — 12.13.3',
    notePl: 'Spoiny produkcyjne. Dolna granica chroni przed pękaniem na '
        'gorąco, górna — przed kruchością (faza sigma, niska temperatura). '
        'Poza tymi warunkami pracy zakres ustala specyfikacja. Tekst API RP '
        '582 — niepotwierdzony.',
    noteEn: 'Production welds. The lower limit guards against hot cracking, '
        'the upper one against embrittlement (sigma phase, low temperature). '
        'Outside these service conditions the specification sets the range. '
        'API RP 582 text — not confirmed.',
  ),
  FerritePreset(
    id: 'asme_uha51_308l',
    group: FerritePresetGroup.lowFerrite,
    requirement: FerriteRequirement(min: 4, max: 14, unit: FerriteUnit.fn),
    appliesTo: _weld,
    titlePl: 'Kriogenika — spoiwo 308L, próba udarności w −196 °C '
        '(ASME VIII-1 UHA-51)',
    titleEn: 'Cryogenic — 308L filler, impact test at −196 °C '
        '(ASME VIII-1 UHA-51)',
    sourcePl: 'ASME BPVC VIII-1 UHA-51 — wg Meyer Tool & Mfg. (wyd. 2010) '
        'i NASA/Jacobs/Swagelok (2023); numer akapitu zmienia się między '
        'wydaniami',
    sourceEn: 'ASME BPVC VIII-1 UHA-51 — per Meyer Tool & Mfg. (2010 ed.) '
        'and NASA/Jacobs/Swagelok (2023); paragraph number changes between '
        'editions',
    notePl: 'Warunek dla spoiwa 308L przy MDMT poniżej −196 °C (próba '
        'udarności w −196 °C). Dla 316L źródła są sprzeczne (FN ≤ 5 albo '
        '≤ 10) — wpisz zakres ze specyfikacji. Pozostałe warunki — w kodzie '
        'w wydaniu z kontraktu.',
    noteEn: 'Condition for 308L filler at MDMT below −196 °C (impact test at '
        '−196 °C). For 316L the sources conflict (FN ≤ 5 or ≤ 10) — enter '
        'the specification range. Other conditions — in the code edition '
        'invoked by the contract.',
  ),
  FerritePreset(
    id: 'urea_316lug_base',
    group: FerritePresetGroup.lowFerrite,
    requirement: FerriteRequirement(max: 0.6, unit: FerriteUnit.percent),
    appliesTo: _base,
    titlePl: 'Mocznik — 316L Urea Grade, materiał rodzimy (licencjodawcy)',
    titleEn: 'Urea — 316L Urea Grade, base metal (licensors)',
    sourcePl: 'Wymaganie licencjodawców instalacji mocznika, nie norma '
        'publiczna — wg A. Eijkenboom, M. Brouwer (UreaKnowHow, 2019), '
        'M. Brouwer (2009); karta Alleima 3R60 Urea Grade (2023): ≤ 0,6 %',
    sourceEn: 'Urea licensors’ requirement, not a public standard — per '
        'A. Eijkenboom, M. Brouwer (UreaKnowHow, 2019), M. Brouwer (2009); '
        'Alleima 3R60 Urea Grade datasheet (2023): ≤ 0.6 %',
    notePl: 'Spoiny w instalacjach mocznika — wymagania licencjodawcy '
        '(niepotwierdzone tu): wpisz zakres ze specyfikacji.',
    noteEn: 'Welds in urea plants — licensor requirements (not confirmed '
        'here): enter the specification range.',
  ),
];

FerritePreset? ferritePresetById(String id) =>
    kFerritePresets.where((p) => p.id == id).firstOrNull;

/// FN a % ferrytu — notatka na ekranie (bez wpływu na werdykt).
String ferriteFnPercentNote({required bool en}) => en
    ? 'FN (Ferrite Number, EN ISO 8249:2018 / AWS A4.2M:2020) is a '
        'calibration scale of magnetic instruments; % is the volume fraction '
        'of ferrite (metallography, ASTM E562). They are not the same and the '
        'relation is not unique: older sources say FN overstates % at higher '
        'ferrite (about 1.3–1.5×, Outokumpu 2021), newer duplex data give '
        'FN ≈ 1.1 × % (ISO/TR 22824:2024 per Quackatz et al. 2024). '
        'Therefore the app does not convert between them.'
    : 'FN (Ferrite Number, EN ISO 8249:2018 / AWS A4.2M:2020) to umowna '
        'skala kalibracji przyrządów magnetycznych; % to udział objętościowy '
        'ferrytu (metalografia, ASTM E562). To nie to samo, a zależność nie '
        'jest jednoznaczna: starsze źródła podają, że FN zawyża % przy '
        'wyższym ferrycie (ok. 1,3–1,5×, Outokumpu 2021), nowsze dane dla '
        'duplex — FN ≈ 1,1 × % (ISO/TR 22824:2024 wg Quackatz i in. 2024). '
        'Dlatego aplikacja nie przelicza jednego na drugie.';

// ═══════════════════════════════════════════════════════════════════════════
// PMI — TABELA GATUNKÓW
// ═══════════════════════════════════════════════════════════════════════════

const String _a240 = 'ASTM A240/A240M-25a';
const String _sa240 = 'ASME SA-240 (BPVC II-A 2025 = ASTM A240-17)';
const String _a312 = 'ASTM A312/A312M-25';
const String _a240a312 = 'ASTM A240/A240M-25a, A312/A312M-25';
const String _a240a790 = 'ASTM A240/A240M-25a, A790/A790M-24';
const String _a335 = 'ASTM A335/A335M-23';

const String _astmPl = 'tab. 1 — tekst normy (PDF), sprawdzone 2026-10-18';
const String _astmEn = 'Table 1 — standard text (PDF), checked 2026-10-18';

/// EN 10088-1:2014 — wycofana (zastąpiona EN 10088-1:2023); wg listy zmian
/// DIN EN 10088-1:2024-04 skład zmieniono tylko m.in. dla 1.4404 (nowych
/// wartości nie potwierdzono — patrz notatka 1.4404).
const String _en10088 = 'EN 10088-1:2014';
const String _en10216_5 = 'EN 10216-5:2013/2021';
const String _en10216 = 'EN 10216-2:2013+A1:2019';
const String _en10028 = 'EN 10028-2:2017';
const String _enPl = 'analiza wytopowa; przedruki: thyssenkrupp Materials '
    '(karty 2017–2020), Deutsche Edelstahlwerke (2015–2016), ISER Merkblatt '
    '821 (2014); sprawdzone 2026-10-18. Wyd. 2023 — skład bez zmian wg listy '
    'zmian DIN EN 10088-1:2024-04';
const String _enEn = 'heat analysis; reprints: thyssenkrupp Materials '
    '(sheets 2017–2020), Deutsche Edelstahlwerke (2015–2016), ISER Merkblatt '
    '821 (2014); checked 2026-10-18. 2023 ed. — composition unchanged per '
    'the DIN EN 10088-1:2024-04 change list';
const String _en10216_5Pl = 'analiza wytopowa; thyssenkrupp Materials '
    '(karta 1.4301, 03.2020, wiersz rur bez szwu) i tubingchina; wyd. 2021 — '
    'skład jak 2013 (przedmowa normy); sprawdzone 2026-10-18';
const String _en10216_5En = 'heat analysis; thyssenkrupp Materials (1.4301 '
    'sheet, 03.2020, seamless tube row) and tubingchina; 2021 ed. — '
    'composition as 2013 (foreword); checked 2026-10-18';
const String _crMoPl = 'tekst normy (kopia) porównany z Salzgitter '
    'Mannesmann i h2abc, sprawdzone 2026-10-18';
const String _crMoEn = 'standard text (copy) compared with Salzgitter '
    'Mannesmann and h2abc, checked 2026-10-18';
const String _en10216NotePl = ' EN 10216-2 zastąpiła wyd. 2024 — skład wg '
    'jednego źródła bez zmian (niepotwierdzone).';
const String _en10216NoteEn = ' EN 10216-2 was superseded by the 2024 '
    'edition — composition unchanged per one source (not confirmed).';

const PmiRange _mn2 = PmiRange(max: 2.0);
const PmiRange _si075 = PmiRange(max: 0.75);
const PmiRange _si1 = PmiRange(max: 1.0);

const PmiCarbonLinkedMin _ti5cN = PmiCarbonLinkedMin(
    factor: 5, plusN: true, cMax: 0.08, nMax: 0.10);

const List<PmiGrade> kPmiGrades = [
  // ── Austenityczne ─────────────────────────────────────────────────────
  PmiGrade(
    id: '1.4301',
    family: PmiFamily.austenitic,
    title: '1.4301 / 304',
    keyElements: {PmiElement.cr, PmiElement.ni},
    controlElements: {PmiElement.mo: '316'},
    notePl: 'A240-25a ma wyższe Cr i Ni niż A240-17 (= SA-240 BPVC 2025) — '
        'blacha z atestem A240 i SA-240 musi spełnić część wspólną. Rury '
        'EN 10216-5: Cr od 17,0 (EN 10088: od 17,5).',
    noteEn: 'A240-25a has higher Cr and Ni than A240-17 (= SA-240 BPVC '
        '2025) — plate dual-certified A240/SA-240 must meet both. EN 10216-5 '
        'tubes: Cr from 17.0 (EN 10088: from 17.5).',
    specs: [
      PmiSpec(
        key: 'en',
        standard: _en10088,
        designation: 'X5CrNi18-10',
        carbonText: 'C ≤ 0,07',
        ranges: {
          PmiElement.cr: PmiRange(min: 17.5, max: 19.5),
          PmiElement.ni: PmiRange(min: 8.0, max: 10.5),
          PmiElement.mn: _mn2,
          PmiElement.si: _si1,
        },
        sourcePl: '$_en10088, $_enPl',
        sourceEn: '$_en10088, $_enEn',
      ),
      PmiSpec(
        key: 'en10216',
        standard: _en10216_5,
        designation: 'X5CrNi18-10 (rury bez szwu)',
        carbonText: 'C ≤ 0,07',
        ranges: {
          PmiElement.cr: PmiRange(min: 17.0, max: 19.5),
          PmiElement.ni: PmiRange(min: 8.0, max: 10.5),
          PmiElement.mn: _mn2,
          PmiElement.si: _si1,
        },
        sourcePl: '$_en10216_5, $_en10216_5Pl',
        sourceEn: '$_en10216_5, $_en10216_5En',
      ),
      PmiSpec(
        key: 'a240',
        standard: _a240,
        designation: '304 (S30400)',
        carbonText: 'C ≤ 0,08',
        ranges: {
          PmiElement.cr: PmiRange(min: 18.0, max: 20.0),
          PmiElement.ni: PmiRange(min: 8.0, max: 11.0),
          PmiElement.mn: _mn2,
          PmiElement.si: _si075,
        },
        sourcePl: '$_a240, $_astmPl',
        sourceEn: '$_a240, $_astmEn',
      ),
      PmiSpec(
        key: 'sa240',
        standard: _sa240,
        designation: '304 (S30400)',
        carbonText: 'C ≤ 0,07',
        ranges: {
          PmiElement.cr: PmiRange(min: 17.5, max: 19.5),
          PmiElement.ni: PmiRange(min: 8.0, max: 10.5),
          PmiElement.mn: _mn2,
          PmiElement.si: _si075,
        },
        sourcePl: '$_sa240, $_astmPl',
        sourceEn: '$_sa240, $_astmEn',
      ),
      PmiSpec(
        key: 'a312',
        standard: _a312,
        designation: 'TP304',
        carbonText: 'C ≤ 0,08',
        ranges: {
          PmiElement.cr: PmiRange(min: 18.0, max: 20.0),
          PmiElement.ni: PmiRange(min: 8.0, max: 11.0),
          PmiElement.mn: _mn2,
          PmiElement.si: _si1,
        },
        sourcePl: '$_a312, $_astmPl',
        sourceEn: '$_a312, $_astmEn',
      ),
    ],
  ),
  PmiGrade(
    id: '1.4307',
    family: PmiFamily.austenitic,
    title: '1.4307 / 304L',
    keyElements: {PmiElement.cr, PmiElement.ni},
    controlElements: {PmiElement.mo: '316L'},
    carbonCritical: true,
    specs: [
      PmiSpec(
        key: 'en',
        standard: _en10088,
        designation: 'X2CrNi18-9',
        carbonText: 'C ≤ 0,030',
        ranges: {
          PmiElement.cr: PmiRange(min: 17.5, max: 19.5),
          PmiElement.ni: PmiRange(min: 8.0, max: 10.5),
          PmiElement.mn: _mn2,
          PmiElement.si: _si1,
        },
        sourcePl: '$_en10088, $_enPl',
        sourceEn: '$_en10088, $_enEn',
      ),
      PmiSpec(
        key: 'a240',
        standard: _a240,
        designation: '304L (S30403)',
        carbonText: 'C ≤ 0,030',
        ranges: {
          PmiElement.cr: PmiRange(min: 18.0, max: 20.0),
          PmiElement.ni: PmiRange(min: 8.0, max: 12.0),
          PmiElement.mn: _mn2,
          PmiElement.si: _si075,
        },
        sourcePl: '$_a240, $_astmPl',
        sourceEn: '$_a240, $_astmEn',
      ),
      PmiSpec(
        key: 'sa240',
        standard: _sa240,
        designation: '304L (S30403)',
        carbonText: 'C ≤ 0,030',
        ranges: {
          PmiElement.cr: PmiRange(min: 17.5, max: 19.5),
          PmiElement.ni: PmiRange(min: 8.0, max: 12.0),
          PmiElement.mn: _mn2,
          PmiElement.si: _si075,
        },
        sourcePl: '$_sa240, $_astmPl',
        sourceEn: '$_sa240, $_astmEn',
      ),
      PmiSpec(
        key: 'a312',
        standard: _a312,
        designation: 'TP304L',
        carbonText: 'C ≤ 0,035 (0,040 przy małej średnicy / cienkiej ściance)',
        ranges: {
          PmiElement.cr: PmiRange(min: 18.0, max: 20.0),
          PmiElement.ni: PmiRange(min: 8.0, max: 13.0),
          PmiElement.mn: _mn2,
          PmiElement.si: _si1,
        },
        sourcePl: '$_a312, $_astmPl',
        sourceEn: '$_a312, $_astmEn',
      ),
    ],
  ),
  PmiGrade(
    id: '1.4401',
    family: PmiFamily.austenitic,
    title: '1.4401 / 316',
    keyElements: {PmiElement.cr, PmiElement.ni, PmiElement.mo},
    specs: [
      PmiSpec(
        key: 'en',
        standard: _en10088,
        designation: 'X5CrNiMo17-12-2',
        carbonText: 'C ≤ 0,07',
        ranges: {
          PmiElement.cr: PmiRange(min: 16.5, max: 18.5),
          PmiElement.ni: PmiRange(min: 10.0, max: 13.0),
          PmiElement.mo: PmiRange(min: 2.0, max: 2.5),
          PmiElement.mn: _mn2,
          PmiElement.si: _si1,
        },
        sourcePl: '$_en10088, $_enPl',
        sourceEn: '$_en10088, $_enEn',
      ),
      PmiSpec(
        key: 'a240',
        standard: _a240,
        designation: '316 (S31600)',
        carbonText: 'C ≤ 0,08',
        ranges: {
          PmiElement.cr: PmiRange(min: 16.0, max: 18.0),
          PmiElement.ni: PmiRange(min: 10.0, max: 14.0),
          PmiElement.mo: PmiRange(min: 2.0, max: 3.0),
          PmiElement.mn: _mn2,
          PmiElement.si: _si075,
        },
        sourcePl: '$_a240, $_astmPl',
        sourceEn: '$_a240, $_astmEn',
      ),
      PmiSpec(
        key: 'a312',
        standard: _a312,
        designation: 'TP316',
        carbonText: 'C ≤ 0,08',
        ranges: {
          PmiElement.cr: PmiRange(min: 16.0, max: 18.0),
          PmiElement.ni: PmiRange(min: 10.0, max: 14.0),
          PmiElement.mo: PmiRange(min: 2.0, max: 3.0),
          PmiElement.mn: _mn2,
          PmiElement.si: _si1,
        },
        sourcePl: '$_a312, $_astmPl',
        sourceEn: '$_a312, $_astmEn',
      ),
    ],
  ),
  PmiGrade(
    id: '1.4404',
    family: PmiFamily.austenitic,
    title: '1.4404 / 316L',
    keyElements: {PmiElement.cr, PmiElement.ni, PmiElement.mo},
    carbonCritical: true,
    notePl: 'EN: wartości z EN 10088-1:2014. W EN 10088-1:2023 skład 1.4404 '
        'zmieniono — nowych wartości nie potwierdzono; gdy zamówienie '
        'przywołuje wyd. 2023, sprawdź zakres w normie.',
    noteEn: 'EN: values from EN 10088-1:2014. EN 10088-1:2023 changed the '
        '1.4404 composition — new values not confirmed; when the order '
        'invokes the 2023 edition, check the range in the standard.',
    specs: [
      PmiSpec(
        key: 'en',
        standard: _en10088,
        designation: 'X2CrNiMo17-12-2',
        carbonText: 'C ≤ 0,030',
        ranges: {
          PmiElement.cr: PmiRange(min: 16.5, max: 18.5),
          PmiElement.ni: PmiRange(min: 10.0, max: 13.0),
          PmiElement.mo: PmiRange(min: 2.0, max: 2.5),
          PmiElement.mn: _mn2,
          PmiElement.si: _si1,
        },
        sourcePl: '$_en10088, analiza wytopowa; przedruki: thyssenkrupp '
            'Materials (2017), Deutsche Edelstahlwerke (2015–2016), ISER '
            'Merkblatt 821 (2014); sprawdzone 2026-10-18. W wyd. 2023 skład '
            'zmieniony — niepotwierdzone',
        sourceEn: '$_en10088, heat analysis; reprints: thyssenkrupp '
            'Materials (2017), Deutsche Edelstahlwerke (2015–2016), ISER '
            'Merkblatt 821 (2014); checked 2026-10-18. Changed in the 2023 '
            'ed. — not confirmed',
      ),
      PmiSpec(
        key: 'a240',
        standard: _a240,
        designation: '316L (S31603)',
        carbonText: 'C ≤ 0,030',
        ranges: {
          PmiElement.cr: PmiRange(min: 16.0, max: 18.0),
          PmiElement.ni: PmiRange(min: 10.0, max: 14.0),
          PmiElement.mo: PmiRange(min: 2.0, max: 3.0),
          PmiElement.mn: _mn2,
          PmiElement.si: _si075,
        },
        sourcePl: '$_a240, $_astmPl',
        sourceEn: '$_a240, $_astmEn',
      ),
      PmiSpec(
        key: 'a312',
        standard: _a312,
        designation: 'TP316L',
        carbonText: 'C ≤ 0,035 (0,040 przy małej średnicy / cienkiej ściance)',
        ranges: {
          PmiElement.cr: PmiRange(min: 16.0, max: 18.0),
          PmiElement.ni: PmiRange(min: 10.0, max: 14.0),
          PmiElement.mo: PmiRange(min: 2.0, max: 3.0),
          PmiElement.mn: _mn2,
          PmiElement.si: _si1,
        },
        sourcePl: '$_a312, $_astmPl',
        sourceEn: '$_a312, $_astmEn',
      ),
    ],
  ),
  PmiGrade(
    id: '1.4571',
    family: PmiFamily.austenitic,
    title: '1.4571 / 316Ti',
    keyElements: {PmiElement.cr, PmiElement.ni, PmiElement.mo, PmiElement.ti},
    notePl: 'Minimum Ti zależy od C (i N wg ASTM) — XRF potwierdzi je tylko '
        'przy Ti ≥ k × Cmax; wg ASTM (5 × (0,08 + 0,10) = 0,90 > 0,70) '
        'nigdy — potrzebny atest albo OES.',
    noteEn: 'The Ti minimum depends on C (and N per ASTM) — XRF can confirm '
        'it only when Ti ≥ k × Cmax; per ASTM (5 × (0.08 + 0.10) = 0.90 > '
        '0.70) never — the certificate or OES is needed.',
    specs: [
      PmiSpec(
        key: 'en',
        standard: _en10088,
        designation: 'X6CrNiMoTi17-12-2',
        carbonText: 'C ≤ 0,08',
        ranges: {
          PmiElement.cr: PmiRange(min: 16.5, max: 18.5),
          PmiElement.ni: PmiRange(min: 10.5, max: 13.5),
          PmiElement.mo: PmiRange(min: 2.0, max: 2.5),
          PmiElement.ti: PmiRange(
              max: 0.70, carbonMin: PmiCarbonLinkedMin(factor: 5, cMax: 0.08)),
          PmiElement.mn: _mn2,
          PmiElement.si: _si1,
        },
        sourcePl: '$_en10088, $_enPl',
        sourceEn: '$_en10088, $_enEn',
      ),
      PmiSpec(
        key: 'astm',
        standard: _a240a312,
        designation: '316Ti / TP316Ti (S31635)',
        carbonText: 'C ≤ 0,08, N ≤ 0,10',
        ranges: {
          PmiElement.cr: PmiRange(min: 16.0, max: 18.0),
          PmiElement.ni: PmiRange(min: 10.0, max: 14.0),
          PmiElement.mo: PmiRange(min: 2.0, max: 3.0),
          PmiElement.ti: PmiRange(max: 0.70, carbonMin: _ti5cN),
          PmiElement.mn: _mn2,
          PmiElement.si: _si075,
        },
        sourcePl: '$_a240a312, $_astmPl',
        sourceEn: '$_a240a312, $_astmEn',
      ),
    ],
  ),
  PmiGrade(
    id: '1.4541',
    family: PmiFamily.austenitic,
    title: '1.4541 / 321',
    keyElements: {PmiElement.cr, PmiElement.ni, PmiElement.ti},
    controlElements: {PmiElement.mo: '316Ti'},
    notePl: 'Minimum Ti zależy od C (i N wg ASTM) — XRF potwierdzi je tylko '
        'przy Ti ≥ k × Cmax; wg ASTM (5 × (0,08 + 0,10) = 0,90 > 0,70) '
        'nigdy — potrzebny atest albo OES.',
    noteEn: 'The Ti minimum depends on C (and N per ASTM) — XRF can confirm '
        'it only when Ti ≥ k × Cmax; per ASTM (5 × (0.08 + 0.10) = 0.90 > '
        '0.70) never — the certificate or OES is needed.',
    specs: [
      PmiSpec(
        key: 'en',
        standard: _en10088,
        designation: 'X6CrNiTi18-10',
        carbonText: 'C ≤ 0,08',
        ranges: {
          PmiElement.cr: PmiRange(min: 17.0, max: 19.0),
          PmiElement.ni: PmiRange(min: 9.0, max: 12.0),
          PmiElement.ti: PmiRange(
              max: 0.70, carbonMin: PmiCarbonLinkedMin(factor: 5, cMax: 0.08)),
          PmiElement.mn: _mn2,
          PmiElement.si: _si1,
        },
        sourcePl: '$_en10088, $_enPl',
        sourceEn: '$_en10088, $_enEn',
      ),
      PmiSpec(
        key: 'a240',
        standard: _a240,
        designation: '321 (S32100)',
        carbonText: 'C ≤ 0,08, N ≤ 0,10',
        ranges: {
          PmiElement.cr: PmiRange(min: 17.0, max: 19.0),
          PmiElement.ni: PmiRange(min: 9.0, max: 12.0),
          PmiElement.ti: PmiRange(max: 0.70, carbonMin: _ti5cN),
          PmiElement.mn: _mn2,
          PmiElement.si: _si075,
        },
        sourcePl: '$_a240, $_astmPl',
        sourceEn: '$_a240, $_astmEn',
      ),
      PmiSpec(
        key: 'a312',
        standard: _a312,
        designation: 'TP321',
        carbonText: 'C ≤ 0,08, N ≤ 0,10',
        ranges: {
          PmiElement.cr: PmiRange(min: 17.0, max: 19.0),
          PmiElement.ni: PmiRange(min: 9.0, max: 12.0),
          PmiElement.ti: PmiRange(max: 0.70, carbonMin: _ti5cN),
          PmiElement.mn: _mn2,
          PmiElement.si: _si1,
        },
        sourcePl: '$_a312, $_astmPl',
        sourceEn: '$_a312, $_astmEn',
      ),
    ],
  ),
  PmiGrade(
    id: '1.4539',
    family: PmiFamily.austenitic,
    title: '1.4539 / 904L',
    keyElements: {PmiElement.cr, PmiElement.ni, PmiElement.mo, PmiElement.cu},
    carbonCritical: true,
    notePl: 'Rury 904L — ASTM A312 (N08904); B677 od wyd. -23 nie obejmuje '
        'N08904.',
    noteEn: '904L pipe — ASTM A312 (N08904); B677 no longer covers N08904 '
        'since the -23 edition.',
    specs: [
      PmiSpec(
        key: 'en',
        standard: _en10088,
        designation: 'X1NiCrMoCu25-20-5',
        carbonText: 'C ≤ 0,020',
        ranges: {
          PmiElement.cr: PmiRange(min: 19.0, max: 21.0),
          PmiElement.ni: PmiRange(min: 24.0, max: 26.0),
          PmiElement.mo: PmiRange(min: 4.0, max: 5.0),
          PmiElement.cu: PmiRange(min: 1.2, max: 2.0),
          PmiElement.mn: _mn2,
          PmiElement.si: PmiRange(max: 0.70),
        },
        sourcePl: '$_en10088, $_enPl',
        sourceEn: '$_en10088, $_enEn',
      ),
      PmiSpec(
        key: 'astm',
        standard: _a240a312,
        designation: '904L (N08904)',
        carbonText: 'C ≤ 0,020',
        ranges: {
          PmiElement.cr: PmiRange(min: 19.0, max: 23.0),
          PmiElement.ni: PmiRange(min: 23.0, max: 28.0),
          PmiElement.mo: PmiRange(min: 4.0, max: 5.0),
          PmiElement.cu: PmiRange(min: 1.0, max: 2.0),
          PmiElement.mn: _mn2,
          PmiElement.si: _si1,
        },
        sourcePl: '$_a240a312, $_astmPl',
        sourceEn: '$_a240a312, $_astmEn',
      ),
    ],
  ),
  PmiGrade(
    id: '1.4845',
    family: PmiFamily.austenitic,
    title: '1.4845 / 310S',
    keyElements: {PmiElement.cr, PmiElement.ni},
    controlElements: {PmiElement.mo: null},
    notePl: 'Stal żaroodporna — nie ma jej w EN 10216-5; rury wg EN 10296-2 '
        '/ EN 10297-2 (ten sam skład).',
    noteEn: 'Heat-resisting steel — not in EN 10216-5; tubes per EN 10296-2 '
        '/ EN 10297-2 (same composition).',
    specs: [
      PmiSpec(
        key: 'en',
        standard: 'EN 10095:1999',
        designation: 'X8CrNi25-21',
        carbonText: 'C ≤ 0,10',
        ranges: {
          PmiElement.cr: PmiRange(min: 24.0, max: 26.0),
          PmiElement.ni: PmiRange(min: 19.0, max: 22.0),
          PmiElement.mn: _mn2,
          PmiElement.si: PmiRange(max: 1.5),
        },
        sourcePl: 'EN 10095:1999 (+AC:2001; w EN 10088-1 skład identyczny) — '
            'analiza wytopowa; przedruki: thyssenkrupp Materials (04.2020), '
            'Schoeller Werk (2024), Euro Inox; sprawdzone 2026-10-18',
        sourceEn: 'EN 10095:1999 (+AC:2001; same composition in EN 10088-1) '
            '— heat analysis; reprints: thyssenkrupp Materials (04.2020), '
            'Schoeller Werk (2024), Euro Inox; checked 2026-10-18',
      ),
      PmiSpec(
        key: 'a240',
        standard: _a240,
        designation: '310S (S31008)',
        carbonText: 'C ≤ 0,08',
        ranges: {
          PmiElement.cr: PmiRange(min: 24.0, max: 26.0),
          PmiElement.ni: PmiRange(min: 19.0, max: 22.0),
          PmiElement.mn: _mn2,
          PmiElement.si: PmiRange(max: 1.5),
        },
        sourcePl: '$_a240, $_astmPl',
        sourceEn: '$_a240, $_astmEn',
      ),
      PmiSpec(
        key: 'a312',
        standard: _a312,
        designation: 'TP310S',
        carbonText: 'C ≤ 0,08',
        ranges: {
          PmiElement.cr: PmiRange(min: 24.0, max: 26.0),
          PmiElement.ni: PmiRange(min: 19.0, max: 22.0),
          PmiElement.mo: PmiRange(max: 0.75),
          PmiElement.mn: _mn2,
          PmiElement.si: _si1,
        },
        sourcePl: '$_a312, $_astmPl',
        sourceEn: '$_a312, $_astmEn',
      ),
    ],
  ),
  // ── Duplex ────────────────────────────────────────────────────────────
  PmiGrade(
    id: '1.4462',
    family: PmiFamily.duplex,
    title: '1.4462 / 2205 (S32205, S31803)',
    keyElements: {PmiElement.cr, PmiElement.ni, PmiElement.mo},
    carbonCritical: true,
    notePl: 'S32205 to węższy zakres Cr i Mo niż S31803. N (ważny dla '
        'duplex) — XRF go nie mierzy.',
    noteEn: 'S32205 has narrower Cr and Mo ranges than S31803. N (important '
        'for duplex) — XRF does not measure it.',
    specs: [
      PmiSpec(
        key: 'en',
        standard: _en10088,
        designation: 'X2CrNiMoN22-5-3',
        carbonText: 'C ≤ 0,030, N 0,10–0,22',
        ranges: {
          PmiElement.cr: PmiRange(min: 21.0, max: 23.0),
          PmiElement.ni: PmiRange(min: 4.5, max: 6.5),
          PmiElement.mo: PmiRange(min: 2.5, max: 3.5),
          PmiElement.mn: _mn2,
          PmiElement.si: _si1,
        },
        sourcePl: '$_en10088, $_enPl',
        sourceEn: '$_en10088, $_enEn',
      ),
      PmiSpec(
        key: 's32205',
        standard: _a240a790,
        designation: '2205 (S32205)',
        carbonText: 'C ≤ 0,030, N 0,14–0,20',
        ranges: {
          PmiElement.cr: PmiRange(min: 22.0, max: 23.0),
          PmiElement.ni: PmiRange(min: 4.5, max: 6.5),
          PmiElement.mo: PmiRange(min: 3.0, max: 3.5),
          PmiElement.mn: _mn2,
          PmiElement.si: _si1,
        },
        sourcePl: '$_a240a790, $_astmPl',
        sourceEn: '$_a240a790, $_astmEn',
      ),
      PmiSpec(
        key: 's31803',
        standard: _a240a790,
        designation: 'S31803',
        carbonText: 'C ≤ 0,030, N 0,08–0,20',
        ranges: {
          PmiElement.cr: PmiRange(min: 21.0, max: 23.0),
          PmiElement.ni: PmiRange(min: 4.5, max: 6.5),
          PmiElement.mo: PmiRange(min: 2.5, max: 3.5),
          PmiElement.mn: _mn2,
          PmiElement.si: _si1,
        },
        sourcePl: '$_a240a790, $_astmPl',
        sourceEn: '$_a240a790, $_astmEn',
      ),
    ],
  ),
  PmiGrade(
    id: '1.4410',
    family: PmiFamily.duplex,
    title: '1.4410 / 2507 (S32750)',
    keyElements: {PmiElement.cr, PmiElement.ni, PmiElement.mo},
    carbonCritical: true,
    notePl: 'ASTM wymaga też Cr + 3,3 Mo + 16 N ≥ 41 — bez N (XRF go nie '
        'mierzy) nie da się tego sprawdzić.',
    noteEn: 'ASTM also requires Cr + 3.3 Mo + 16 N ≥ 41 — without N (XRF '
        'does not measure it) this cannot be checked.',
    specs: [
      PmiSpec(
        key: 'en',
        standard: _en10088,
        designation: 'X2CrNiMoN25-7-4',
        carbonText: 'C ≤ 0,030, N 0,24–0,35',
        ranges: {
          PmiElement.cr: PmiRange(min: 24.0, max: 26.0),
          PmiElement.ni: PmiRange(min: 6.0, max: 8.0),
          PmiElement.mo: PmiRange(min: 3.0, max: 4.5),
          PmiElement.mn: _mn2,
          PmiElement.si: _si1,
        },
        sourcePl: '$_en10088, $_enPl',
        sourceEn: '$_en10088, $_enEn',
      ),
      PmiSpec(
        key: 's32750',
        standard: _a240a790,
        designation: '2507 (S32750)',
        carbonText: 'C ≤ 0,030, N 0,24–0,32',
        ranges: {
          PmiElement.cr: PmiRange(min: 24.0, max: 26.0),
          PmiElement.ni: PmiRange(min: 6.0, max: 8.0),
          PmiElement.mo: PmiRange(min: 3.0, max: 5.0),
          PmiElement.mn: PmiRange(max: 1.2),
          PmiElement.si: PmiRange(max: 0.8),
          PmiElement.cu: PmiRange(max: 0.5),
        },
        sourcePl: '$_a240a790, $_astmPl',
        sourceEn: '$_a240a790, $_astmEn',
      ),
    ],
  ),
  // ── Cr-Mo ─────────────────────────────────────────────────────────────
  PmiGrade(
    id: '1.7335',
    family: PmiFamily.crMo,
    title: '1.7335 / 13CrMo4-5 (P12, P11)',
    keyElements: {PmiElement.cr, PmiElement.mo},
    notePl: 'Uwaga: ASTM P11 to 1¼Cr-½Mo (Cr 1,00–1,50, Si 0,50–1,00), a '
        '13CrMo4-5 to 1Cr-½Mo — bliżej P12. To nie są zamienniki: oceniaj wg '
        'normy z zamówienia. P11 od P12 najłatwiej odróżnić po Si.',
    noteEn: 'Note: ASTM P11 is 1¼Cr-½Mo (Cr 1.00–1.50, Si 0.50–1.00) while '
        '13CrMo4-5 is 1Cr-½Mo — closer to P12. They are not substitutes: '
        'judge to the standard on the order. P11 vs P12 is easiest by Si.',
    specs: [
      PmiSpec(
        key: 'en',
        standard: _en10216,
        designation: '13CrMo4-5 (rury)',
        carbonText: 'C 0,10–0,17 (ścianka ≥ 30 mm: +0,02)',
        ranges: {
          PmiElement.cr: PmiRange(min: 0.70, max: 1.15),
          PmiElement.mo: PmiRange(min: 0.40, max: 0.60),
          PmiElement.mn: PmiRange(min: 0.40, max: 0.70),
          PmiElement.si: PmiRange(max: 0.35),
          PmiElement.ni: PmiRange(max: 0.30),
          PmiElement.cu: PmiRange(max: 0.30),
        },
        sourcePl: '$_en10216, $_crMoPl.$_en10216NotePl',
        sourceEn: '$_en10216, $_crMoEn.$_en10216NoteEn',
      ),
      PmiSpec(
        key: 'en10028',
        standard: _en10028,
        designation: '13CrMo4-5 (blachy)',
        carbonText: 'C 0,08–0,18',
        ranges: {
          PmiElement.cr: PmiRange(min: 0.70, max: 1.15),
          PmiElement.mo: PmiRange(min: 0.40, max: 0.60),
          PmiElement.mn: PmiRange(min: 0.40, max: 1.00),
          PmiElement.si: PmiRange(max: 0.35),
          PmiElement.cu: PmiRange(max: 0.30),
        },
        sourcePl: '$_en10028, $_crMoPl',
        sourceEn: '$_en10028, $_crMoEn',
      ),
      PmiSpec(
        key: 'p12',
        standard: _a335,
        designation: 'P12 (K11562)',
        carbonText: 'C 0,05–0,15',
        ranges: {
          PmiElement.cr: PmiRange(min: 0.80, max: 1.25),
          PmiElement.mo: PmiRange(min: 0.44, max: 0.65),
          PmiElement.mn: PmiRange(min: 0.30, max: 0.61),
          PmiElement.si: PmiRange(max: 0.50),
        },
        sourcePl: '$_a335, $_astmPl',
        sourceEn: '$_a335, $_astmEn',
      ),
      PmiSpec(
        key: 'p11',
        standard: _a335,
        designation: 'P11 (K11597)',
        carbonText: 'C 0,05–0,15',
        ranges: {
          PmiElement.cr: PmiRange(min: 1.00, max: 1.50),
          PmiElement.mo: PmiRange(min: 0.44, max: 0.65),
          PmiElement.mn: PmiRange(min: 0.30, max: 0.60),
          PmiElement.si: PmiRange(min: 0.50, max: 1.00),
        },
        sourcePl: '$_a335, $_astmPl',
        sourceEn: '$_a335, $_astmEn',
      ),
    ],
  ),
  PmiGrade(
    id: '1.7380',
    family: PmiFamily.crMo,
    title: '1.7380 / 10CrMo9-10 (P22)',
    keyElements: {PmiElement.cr, PmiElement.mo},
    specs: [
      PmiSpec(
        key: 'en',
        standard: _en10216,
        designation: '10CrMo9-10 (rury)',
        carbonText: 'C 0,08–0,14',
        ranges: {
          PmiElement.cr: PmiRange(min: 2.00, max: 2.50),
          PmiElement.mo: PmiRange(min: 0.90, max: 1.10),
          PmiElement.mn: PmiRange(min: 0.30, max: 0.70),
          PmiElement.si: PmiRange(max: 0.50),
          PmiElement.ni: PmiRange(max: 0.30),
          PmiElement.cu: PmiRange(max: 0.30),
        },
        sourcePl: '$_en10216, $_crMoPl.$_en10216NotePl',
        sourceEn: '$_en10216, $_crMoEn.$_en10216NoteEn',
      ),
      PmiSpec(
        key: 'en10028',
        standard: _en10028,
        designation: '10CrMo9-10 (blachy)',
        carbonText: 'C 0,08–0,14',
        ranges: {
          PmiElement.cr: PmiRange(min: 2.00, max: 2.50),
          PmiElement.mo: PmiRange(min: 0.90, max: 1.10),
          PmiElement.mn: PmiRange(min: 0.40, max: 0.80),
          PmiElement.si: PmiRange(max: 0.50),
          PmiElement.cu: PmiRange(max: 0.30),
        },
        sourcePl: '$_en10028, $_crMoPl',
        sourceEn: '$_en10028, $_crMoEn',
      ),
      PmiSpec(
        key: 'p22',
        standard: _a335,
        designation: 'P22 (K21590)',
        carbonText: 'C 0,05–0,15',
        ranges: {
          PmiElement.cr: PmiRange(min: 1.90, max: 2.60),
          PmiElement.mo: PmiRange(min: 0.87, max: 1.13),
          PmiElement.mn: PmiRange(min: 0.30, max: 0.60),
          PmiElement.si: PmiRange(max: 0.50),
        },
        sourcePl: '$_a335, $_astmPl',
        sourceEn: '$_a335, $_astmEn',
      ),
    ],
  ),
  PmiGrade(
    id: '1.4903',
    family: PmiFamily.crMo,
    title: '1.4903 / X10CrMoVNb9-1 (P91)',
    keyElements: {PmiElement.cr, PmiElement.mo, PmiElement.v, PmiElement.nb},
    carbonCritical: true,
    notePl: 'O P91 decydują też C i N (XRF ich nie mierzy). A335-23 typ 2: '
        'w analizie wyrobu szersze zakresy (Mo 0,80–1,05, V 0,16–0,27, '
        'Nb 0,05–0,11) — tu analiza wytopowa.',
    noteEn: 'C and N also define P91 (XRF does not measure them). A335-23 '
        'Type 2: product analysis has wider ranges (Mo 0.80–1.05, V '
        '0.16–0.27, Nb 0.05–0.11) — heat analysis shown here.',
    specs: [
      PmiSpec(
        key: 'en',
        standard: _en10216,
        designation: 'X10CrMoVNb9-1 (rury)',
        carbonText: 'C 0,08–0,12, N 0,030–0,070',
        ranges: {
          PmiElement.cr: PmiRange(min: 8.00, max: 9.50),
          PmiElement.mo: PmiRange(min: 0.85, max: 1.05),
          PmiElement.v: PmiRange(min: 0.18, max: 0.25),
          PmiElement.nb: PmiRange(min: 0.06, max: 0.10),
          PmiElement.ni: PmiRange(max: 0.40),
          PmiElement.mn: PmiRange(min: 0.30, max: 0.60),
          PmiElement.si: PmiRange(min: 0.20, max: 0.50),
          PmiElement.cu: PmiRange(max: 0.30),
          PmiElement.ti: PmiRange(max: 0.01),
        },
        // Ni ≤ 0,40 sprawdzone 2026-10-18 ponownie (przegląd: „może 0,30?”):
        // Salzgitter Mannesmann, strona EN 10216-2 X10CrMoVNb9-1 — Ni max
        // 0,40; ICAST, karta „BS 10216-2 EN 1.4903” — Ni 0,400 max; skan
        // EN 10216-2:2013+A1:2019 tab. 2 (odczyt wcześniejszy) — 0,40.
        // 0,30 to EN 10028-2:2017 (blachy) — osobny wariant niżej.
        sourcePl: '$_en10216, $_crMoPl; Ni ≤ 0,40 także wg ICAST (BS EN '
            '10216-2, 1.4903) — blachy EN 10028-2: Ni ≤ 0,30.'
            '$_en10216NotePl',
        sourceEn: '$_en10216, $_crMoEn; Ni ≤ 0.40 also per ICAST (BS EN '
            '10216-2, 1.4903) — EN 10028-2 plate: Ni ≤ 0.30.'
            '$_en10216NoteEn',
      ),
      PmiSpec(
        key: 'en10028',
        standard: _en10028,
        designation: 'X10CrMoVNb9-1 (blachy)',
        carbonText: 'C 0,08–0,12, N 0,030–0,070',
        ranges: {
          PmiElement.cr: PmiRange(min: 8.00, max: 9.50),
          PmiElement.mo: PmiRange(min: 0.85, max: 1.05),
          PmiElement.v: PmiRange(min: 0.18, max: 0.25),
          PmiElement.nb: PmiRange(min: 0.06, max: 0.10),
          PmiElement.ni: PmiRange(max: 0.30),
          PmiElement.mn: PmiRange(min: 0.30, max: 0.60),
          PmiElement.si: PmiRange(max: 0.50),
          PmiElement.cu: PmiRange(max: 0.30),
        },
        sourcePl: '$_en10028, $_crMoPl',
        sourceEn: '$_en10028, $_crMoEn',
      ),
      PmiSpec(
        key: 'p91t1',
        standard: '$_a335 — P91 typ 1',
        designation: 'P91 typ 1 (K91560)',
        carbonText: 'C 0,08–0,12, N 0,030–0,070',
        ranges: {
          PmiElement.cr: PmiRange(min: 8.00, max: 9.50),
          PmiElement.mo: PmiRange(min: 0.85, max: 1.05),
          PmiElement.v: PmiRange(min: 0.18, max: 0.25),
          PmiElement.nb: PmiRange(min: 0.06, max: 0.10),
          PmiElement.ni: PmiRange(max: 0.40),
          PmiElement.mn: PmiRange(min: 0.30, max: 0.60),
          PmiElement.si: PmiRange(min: 0.20, max: 0.50),
          PmiElement.ti: PmiRange(max: 0.01),
        },
        sourcePl: '$_a335, $_astmPl',
        sourceEn: '$_a335, $_astmEn',
      ),
      PmiSpec(
        key: 'p91t2',
        standard: '$_a335 — P91 typ 2',
        designation: 'P91 typ 2 (analiza wytopowa)',
        carbonText: 'C 0,08–0,12, N 0,035–0,070',
        ranges: {
          PmiElement.cr: PmiRange(min: 8.00, max: 9.50),
          PmiElement.mo: PmiRange(min: 0.85, max: 1.05),
          PmiElement.v: PmiRange(min: 0.18, max: 0.25),
          PmiElement.nb: PmiRange(min: 0.06, max: 0.10),
          PmiElement.ni: PmiRange(max: 0.20),
          PmiElement.cu: PmiRange(max: 0.10),
          PmiElement.mn: PmiRange(min: 0.30, max: 0.50),
          PmiElement.si: PmiRange(min: 0.20, max: 0.40),
          PmiElement.ti: PmiRange(max: 0.01),
        },
        sourcePl: '$_a335, $_astmPl',
        sourceEn: '$_a335, $_astmEn',
      ),
    ],
  ),
];

PmiGrade? pmiGradeById(String id) =>
    kPmiGrades.where((g) => g.id == id).firstOrNull;

/// Ostrzeżenie XRF / węgiel — na ekranie PMI i w protokole.
String pmiCarbonNote({required bool en}) => en
    ? 'XRF does not measure carbon (nor nitrogen). 304 vs 304L and 316 vs '
        '316L differ only in C — they cannot be told apart without OES (spark '
        'spectrometer) or a laboratory; for low-carbon grades (“L”, duplex, '
        '904L, P91) the best verdict is “conforming (carbon not verified)”. '
        'P91 (C 0.08–0.12 %, N 0.030–0.070 %): XRF shows Cr, Mo, V and Nb but '
        'cannot confirm C or N — telling it apart from other 9Cr steels '
        'reliably needs OES / laboratory. The table ranges are heat '
        'analyses; product-analysis tolerances and PMI acceptance follow the '
        'project PMI procedure.'
    : 'XRF nie mierzy węgla (ani azotu). 304 i 304L oraz 316 i 316L różnią '
        'się tylko C — bez OES (spektrometr iskrowy) albo laboratorium nie da '
        'się ich rozróżnić; przy gatunkach niskowęglowych („L”, duplex, 904L, '
        'P91) najlepszy werdykt to „zgodny (bez weryfikacji C)”. P91 '
        '(C 0,08–0,12 %, N 0,030–0,070 %): XRF pokaże Cr, Mo, V i Nb, ale nie '
        'potwierdzi C ani N — pewne odróżnienie od innych stali 9Cr wymaga '
        'OES / laboratorium. Zakresy w tabeli to analiza wytopowa; odchyłki '
        'analizy wyrobu i kryteria PMI określa procedura PMI projektu.';

// ═══════════════════════════════════════════════════════════════════════════
// LISTA ŹRÓDEŁ (ekran „Źródła i wartości”)
// ═══════════════════════════════════════════════════════════════════════════

const List<FerritePmiSource> kFerritePmiSources = [
  FerritePmiSource(
    'Ferryt — pomiar: EN ISO 8249:2018 (FN w stopiwie austenitycznym '
        'i duplex, metoda magnetyczna; nie dotyczy wyrobów lanych, kutych '
        'i walcowanych), AWS A4.2M:2020 (= ISO 8249:2018 MOD). Udział '
        'objętościowy % — metalografia (ASTM E562 / E1245).',
    'Ferrite — measurement: EN ISO 8249:2018 (FN in austenitic and duplex '
        'weld metal, magnetic method; not for cast, forged or wrought '
        'products), AWS A4.2M:2020 (= ISO 8249:2018 MOD). Volume % — '
        'metallography (ASTM E562 / E1245).',
  ),
  FerritePmiSource(
    'Duplex: ISO 17781:2017, 5.3.2 — spoina po spawaniu 30–70 %, materiał '
        'rodzimy 35–60 % (wg Francis i Byrne 2022 oraz Outokumpu 2021); '
        'API TR 938-C wyd. 2 (2011) — spoina 25–60 %, SWC 40–65 %, materiał '
        'rodzimy 30–65 % (wg Hosseini i in. 2018 oraz Outokumpu 2021). '
        'NORSOK M-601:2016 — zakresów nie potwierdzono, w aplikacji brak.',
    'Duplex: ISO 17781:2017, 5.3.2 — as-welded weld 30–70 %, base metal '
        '35–60 % (per Francis and Byrne 2022 and Outokumpu 2021); API TR '
        '938-C 2nd ed. (2011) — weld 25–60 %, HAZ 40–65 %, base metal '
        '30–65 % (per Hosseini et al. 2018 and Outokumpu 2021). NORSOK '
        'M-601:2016 — ranges not confirmed, not in the app.',
  ),
  FerritePmiSource(
    'Spoiny austenityczne: IOGP S-705 (2020), uzupełnienie API RP 582 '
        'wyd. 3 (2016) — 12.13.1: FN 3–10 przy pracy > 350 °C, < −101 °C '
        'albo PWHT; 12.13.3: min. 3 odczyty na spoinę. ASME BPVC VIII-1 '
        'UHA-51 — spoiwo 308L FN 4–14 (próba udarności w −196 °C; wg Meyer '
        'Tool i NASA 2023).',
    'Austenitic welds: IOGP S-705 (2020), supplement to API RP 582 3rd ed. '
        '(2016) — 12.13.1: FN 3–10 for service > 350 °C, < −101 °C or '
        'PWHT; 12.13.3: at least 3 readings per weld. ASME BPVC VIII-1 UHA-51 '
        '— 308L filler FN 4–14 (impact test at −196 °C; per Meyer Tool and '
        'NASA 2023).',
  ),
  FerritePmiSource(
    'Mocznik: 316L Urea Grade — ferryt materiału rodzimego ≤ 0,6 % '
        '(wymaganie licencjodawców; Eijkenboom i Brouwer 2019, Brouwer 2009, '
        'karta Alleima 3R60).',
    'Urea: 316L Urea Grade — base metal ferrite ≤ 0.6 % (licensors’ '
        'requirement; Eijkenboom and Brouwer 2019, Brouwer 2009, Alleima '
        '3R60 datasheet).',
  ),
  FerritePmiSource(
    'FN a %: zależność niejednoznaczna (Outokumpu 2021: FN zawyża % ok. '
        '1,3–1,5× przy wyższym ferrycie; ISO/TR 22824:2024 wg Quackatz i in. '
        '2024: FN ≈ 1,1 × %) — aplikacja nie przelicza.',
    'FN vs %: the relation is not unique (Outokumpu 2021: FN overstates % '
        'by about 1.3–1.5× at higher ferrite; ISO/TR 22824:2024 per Quackatz '
        'et al. 2024: FN ≈ 1.1 × %) — the app does not convert.',
  ),
  FerritePmiSource(
    'PMI, stale nierdzewne — EN 10088-1:2014 (wycofana; EN 10088-1:2023 '
        'zmieniła m.in. skład 1.4404 — nowych wartości nie potwierdzono), '
        'EN 10216-5:2013/2021 (rury; 1.4301 Cr od 17,0), EN 10095:1999 '
        '(1.4845); ASTM A240/A240M-25a (blachy; wiersze jak w -20a), ASME SA-240 BPVC '
        'II-A 2025 (= ASTM A240-17 — inne Cr/Ni dla 304 i 304L), ASTM '
        'A312/A312M-25 (rury), ASTM A790/A790M-24 (rury duplex). Tekst norm '
        'ASTM sprawdzony 2026-10-18.',
    'PMI, stainless — EN 10088-1:2014 (withdrawn; EN 10088-1:2023 changed '
        'e.g. the 1.4404 composition — new values not confirmed), EN '
        '10216-5:2013/2021 (tubes; 1.4301 Cr from 17.0), EN 10095:1999 '
        '(1.4845); ASTM '
        'A240/A240M-25a (plate; rows as in -20a), ASME SA-240 BPVC II-A 2025 '
        '(= ASTM A240-17 — different Cr/Ni for 304 and 304L), ASTM '
        'A312/A312M-25 (pipe), ASTM A790/A790M-24 (duplex pipe). ASTM texts '
        'checked 2026-10-18.',
  ),
  FerritePmiSource(
    'PMI, stale Cr-Mo — EN 10216-2:2013+A1:2019 (rury bez szwu do pracy '
        'w podwyższonej temperaturze; zastąpiona wyd. 2024), EN 10028-2:2017 '
        '(blachy — inne Mn, Ni); ASTM A335/A335M-23 (P11, P12, P22, P91 typ '
        '1 i 2). Zakresy to analiza wytopowa — odchyłki analizy wyrobu '
        '(np. EN 10028-2 tab. 2) i kryteria PMI określa procedura projektu.',
    'PMI, Cr-Mo steels — EN 10216-2:2013+A1:2019 (seamless tubes for '
        'elevated temperature; superseded by the 2024 ed.), EN 10028-2:2017 '
        '(plate — different Mn, Ni); ASTM A335/A335M-23 (P11, P12, P22, P91 '
        'Type 1 and 2). Ranges are heat analyses — product-analysis '
        'tolerances (e.g. EN 10028-2 Table 2) and PMI criteria follow the '
        'project procedure.',
  ),
  FerritePmiSource(
    'Przyjęte w aplikacji: niepewność przyrządu podaje użytkownik '
        '(domyślnie 0); odczyt bliżej granicy niż niepewność → „do '
        'weryfikacji”; dobór pierwiastków kluczowych; każdy pierwiastek '
        'z dolną granicą w normie jest wymagany; próg „resztkowy” dla '
        'pierwiastka spoza składu gatunku — 0,5 % (Ti, Nb 0,1 %; V 0,2 %; '
        'Si, Cu 1,0 %): powyżej → „niezgodny”, w niepewności → „do '
        'weryfikacji”; Mo jako pierwiastek kontrolny w 304, 304L, 321, 310S '
        '(brak odczytu → „do weryfikacji”); suma odczytów > 100 % = błąd '
        'wpisu; ferryt: domyślnie min. 1 odczyt na miejsce.',
    'Adopted by the app: the instrument uncertainty is entered by the user '
        '(default 0); a reading closer to a limit than the uncertainty → '
        '“to be verified”; choice of key elements; every element with a '
        'lower limit in the standard is required; a “residual” threshold '
        'for an element outside the grade composition — 0.5 % (Ti, Nb '
        '0.1 %; V 0.2 %; Si, Cu 1.0 %): above → “non-conforming”, within '
        'the uncertainty → “to be verified”; Mo as a control element in 304, '
        '304L, 321, 310S (no reading → “to be verified”); readings adding up '
        'to > 100 % = input error; ferrite: at least 1 reading per location '
        'by default.',
  ),
];
