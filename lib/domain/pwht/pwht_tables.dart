// Tabele PWHT z norm — DANE BEZPIECZEŃSTWA-KRYTYCZNE.
//
// Zasada: każda liczba ma komentarz ze źródłem (norma, tabela, wydanie).
// Czego nie dało się potwierdzić w tekście normy — tego tu NIE MA (lepiej
// mniej grup, ale prawdziwych). Przed użyciem sprawdź wydanie normy wskazane
// w specyfikacji projektu.
//
// ── ASME B31.3 (Process Piping) ────────────────────────────────────────────
// Wartości przepisane z tekstu normy (weryfikacja 2026-10-16, odczyt
// z kopii PDF wydań):
//   • B31.3-2020: Tab. 331.1.1, Tab. 331.1.3, §331.1.3, §331.1.4, §331.2.6,
//   • B31.3-2024: te same wartości; tabele przemianowane na 331.1.1-1,
//     331.1.2-1, 331.1.3-1, 330.1.1-1.
//   • B31.3-2018 / 2022: wg spisów zmian („Summary of Changes”) tabele bez
//     zmian liczbowych względem 2020 — nie czytane bezpośrednio.
// Wydanie 2014 przebudowało cały rozdział 331 (ujednolicenie z B31.1) i różni
// się od powyższych w dwóch miejscach używanych tutaj: P-No 15E 730–775 °C
// (zamiast 705–775 °C) oraz P-No 3 — podgrzewanie 95 °C powyżej 16 mm
// (zamiast 13 mm). Wydania ≤ 2012 to INNA tabela (P-No 1 dopiero > 19/20 mm,
// 2,4 min/mm z minimum 1 h, twardości HB) — moduł jej NIE odtwarza.
//
// ── ASME B31.1 (Power Piping) ──────────────────────────────────────────────
// Wartości przepisane z tekstu B31.1-2022 (rewizja B31.1-2020), str. 103–109:
// Tab. 132.1.1-1, Tab. 132.2-1, §131.6.2, §132.4, §132.5, §132.7,
// Tab. 131.4.1-1. Wydania 2024 nie sprawdzano.
//
// ── AWS D10.10/D10.10M:2021 ────────────────────────────────────────────────
// Liczba STREF REGULACJI dla rury poziomej wg tytułów rys. 8.3–8.6 (spis
// rysunków z oficjalnego podglądu normy, pubs.aws.org). Wzorów na pasmo
// grzane (HB) i strefę gradientu (GCB) moduł NIE podaje — wzór HB2 nie był
// czytelny w dostępnym tekście, a wydania 2021 nie dało się sprawdzić.

import 'pwht_cycle.dart';

/// Tekst dwujęzyczny.
class PwhtBiText {
  const PwhtBiText(this.pl, this.en);
  final String pl;
  final String en;
}

/// Norma, wg której liczony jest plan.
enum PwhtCode {
  asmeB313(
    'ASME B31.3',
    'Rurociągi procesowe (rafinerie, chemia, energetyka przemysłowa). '
        'Wartości z wydań 2020 i 2024 (2018 i 2022 — bez zmian liczbowych). '
        'Wydanie 2014 różni się dla P-No 3 i 15E; wydania ≤ 2012 mają inną '
        'tabelę.',
    'Process piping (refineries, chemical and industrial power plants). '
        'Values from the 2020 and 2024 editions (2018 and 2022 — no numeric '
        'changes). The 2014 edition differs for P-No 3 and 15E; editions '
        '≤ 2012 use a different table.',
  ),
  asmeB311(
    'ASME B31.1',
    'Rurociągi energetyczne (elektrownie, kotłownie). Wartości z wydania '
        '2022 — Tab. 132.1.1-1 i 132.2-1. Inne wydanie w specyfikacji — '
        'sprawdź tabelę.',
    'Power piping (power plants, boiler houses). Values from the 2022 '
        'edition — Tables 132.1.1-1 and 132.2-1. Another edition in the '
        'specification — check the table.',
  );

  const PwhtCode(this.label, this.scopePl, this.scopeEn);
  final String label;
  final String scopePl;
  final String scopeEn;
}

/// Grupa materiału (ASME P-No) — z odpowiednikiem EN ISO 15608 do opisu.
enum PwhtMaterial { p1, p3, p4, p5a, p15e, p8 }

class PwhtMaterialInfo {
  const PwhtMaterialInfo({
    required this.pNo,
    required this.isoGroup,
    required this.alloyPl,
    required this.alloyEn,
    required this.grades,
  });

  /// „P-No 1” — numeracja ASME BPVC Section IX QW/QB-420.
  final String pNo;

  /// Typowy odpowiednik grupy wg EN ISO/TR 15608 — opisowo (P-No i grupy
  /// ISO nie pokrywają się 1:1; wiąże grupa z WPS).
  final String isoGroup;
  final String alloyPl;
  final String alloyEn;

  /// Przykładowe gatunki ASTM · EN.
  final String grades;
}

PwhtMaterialInfo pwhtMaterialInfo(PwhtMaterial m) => switch (m) {
      // EN ISO/TR 15608 gr. 1.1 (ReH ≤ 275 MPa) i 1.2 (275–360 MPa).
      PwhtMaterial.p1 => const PwhtMaterialInfo(
          pNo: 'P-No 1',
          isoGroup: '1.1–1.2',
          alloyPl: 'stal węglowa',
          alloyEn: 'carbon steel',
          grades: 'A106 B, A105, A234 WPB · P235GH, P265GH'),
      // C-½Mo; 16Mo3 — EN ISO/TR 15608 gr. 1.2 (Mo ≤ 0,7 % mieści się
      // w grupie 1).
      PwhtMaterial.p3 => const PwhtMaterialInfo(
          pNo: 'P-No 3',
          isoGroup: '1.2',
          alloyPl: 'C-½Mo',
          alloyEn: 'C-½Mo',
          grades: 'A335 P1, A182 F1 · 16Mo3'),
      // 1¼Cr-½Mo / 1Cr-½Mo; 13CrMo4-5 — gr. 5.1.
      PwhtMaterial.p4 => const PwhtMaterialInfo(
          pNo: 'P-No 4',
          isoGroup: '5.1',
          alloyPl: '1¼Cr-½Mo',
          alloyEn: '1¼Cr-½Mo',
          grades: 'A335 P11/P12, A182 F11/F12 · 13CrMo4-5'),
      // 2¼Cr-1Mo; 10CrMo9-10 — gr. 5.2.
      PwhtMaterial.p5a => const PwhtMaterialInfo(
          pNo: 'P-No 5A',
          isoGroup: '5.2',
          alloyPl: '2¼Cr-1Mo',
          alloyEn: '2¼Cr-1Mo',
          grades: 'A335 P22, A182 F22 · 10CrMo9-10'),
      // 9Cr-1Mo-V (CSEF); X10CrMoVNb9-1 — gr. 6.4 (spójnie z preheat.dart:
      // P91 = P-No 15E).
      PwhtMaterial.p15e => const PwhtMaterialInfo(
          pNo: 'P-No 15E',
          isoGroup: '6.4',
          alloyPl: '9Cr-1Mo-V (P91)',
          alloyEn: '9Cr-1Mo-V (P91)',
          grades: 'A335 P91, A182 F91, A234 WP91 · X10CrMoVNb9-1'),
      // Austenityczne Cr-Ni; 1.4301 / 1.4404 — gr. 8.1.
      PwhtMaterial.p8 => const PwhtMaterialInfo(
          pNo: 'P-No 8',
          isoGroup: '8.1',
          alloyPl: 'stal austenityczna',
          alloyEn: 'austenitic stainless',
          grades: 'A312 TP304/304L/316/316L · 1.4301, 1.4404'),
    };

/// Zakres temperatury wytrzymania — °C i °F dokładnie jak w tabeli normy
/// (norma podaje obie skale; nie przeliczamy).
class PwhtTempRange {
  const PwhtTempRange(this.minC, this.maxC, this.minF, this.maxF);
  final int minC;
  final int maxC;
  final int minF;
  final int maxF;
}

/// Warunek zwolnienia z PWHT.
class PwhtCondition {
  const PwhtCondition(this.text, {this.appliesAboveMm});
  final PwhtBiText text;

  /// Warunek dotyczy tylko grubości > tej wartości; null = zawsze.
  final double? appliesAboveMm;

  bool appliesTo(double tMm) => appliesAboveMm == null || tMm > appliesAboveMm!;
}

/// Zwolnienie z obowiązkowego PWHT dla spoin doczołowych (rowkowych).
class PwhtExemption {
  const PwhtExemption({
    required this.maxThicknessMm,
    required this.conditions,
    required this.source,
  });

  /// Zwolnienie obejmuje grubość kontrolną ≤ tej wartości; null = każdą.
  final double? maxThicknessMm;
  final List<PwhtCondition> conditions;
  final String source;

  bool covers(double tMm) => maxThicknessMm == null || tMm <= maxThicknessMm!;

  List<PwhtCondition> conditionsFor(double tMm) => [
        for (final c in conditions)
          if (c.appliesTo(tMm)) c
      ];
}

/// Minimalny czas wytrzymania w formacie ASME:
///
///   t ≤ [proportionalUpToMm]:  1 h na każde 25 mm (proporcjonalnie),
///                              nie mniej niż [minMinutes];
///   t > [proportionalUpToMm]:  czas dla [proportionalUpToMm] + 15 min za
///                              każde dodatkowe 25 mm.
///
/// Norma nie mówi, czy niepełne 25 mm liczyć proporcjonalnie. Moduł liczy
/// KAŻDE ROZPOCZĘTE 25 mm (strona bezpieczna — czas minimalny nie może
/// wyjść krótszy niż przy odczycie „w górę”). Wynik zaokrąglany w górę do
/// pełnej minuty.
class PwhtHoldTimeRule {
  const PwhtHoldTimeRule({
    required this.minMinutes,
    required this.proportionalUpToMm,
    required this.formula,
  });

  /// Minimum dla cienkich ścianek [min].
  final int minMinutes;

  /// Do tej grubości 1 h/25 mm; powyżej — +15 min za każde rozpoczęte 25 mm.
  final double proportionalUpToMm;

  /// Pełny opis reguły (do planu).
  final PwhtBiText formula;

  /// Krótki opis odcinka reguły, który obowiązuje dla grubości [tMm].
  PwhtBiText segmentFor(double tMm) {
    if (tMm <= proportionalUpToMm) {
      return PwhtBiText(
          '1 h/25 mm, min. $minMinutes min', '1 h/25 mm, $minMinutes min min.');
    }
    final baseH = (proportionalUpToMm / 25).round();
    final l = proportionalUpToMm.round();
    return PwhtBiText('$baseH h + 15 min/25 mm ponad $l mm',
        '$baseH h + 15 min/25 mm over $l mm');
  }

  /// `null` dla grubości ≤ 0 / nieskończonej.
  int? minutesFor(double tMm) {
    if (!tMm.isFinite || tMm <= 0) return null;
    final double m;
    if (tMm <= proportionalUpToMm) {
      final prop = 60.0 * tMm / 25.0;
      m = prop < minMinutes ? minMinutes.toDouble() : prop;
    } else {
      final extra = ((tMm - proportionalUpToMm) / 25.0 - 1e-9).ceil();
      m = 60.0 * proportionalUpToMm / 25.0 + 15.0 * extra;
    }
    return (m - 1e-9).ceil();
  }
}

/// Wiersz tabeli normy dla grupy materiału.
class PwhtTableEntry {
  const PwhtTableEntry({
    required this.code,
    required this.material,
    required this.holdRange,
    required this.holdTime,
    required this.exemption,
    required this.notRequiredByTable,
    required this.notes,
    required this.source,
  });

  final PwhtCode code;
  final PwhtMaterial material;

  /// null = tabela nie podaje (np. P-No 8).
  final PwhtTempRange? holdRange;
  final PwhtHoldTimeRule? holdTime;

  /// null = brak zwolnienia — PWHT zawsze wymagane.
  final PwhtExemption? exemption;

  /// Tabela nie wymaga PWHT dla tej grupy (chyba że WPS / specyfikacja).
  final bool notRequiredByTable;
  final List<PwhtBiText> notes;

  /// Norma, tabela i wydanie — drukowane w planie.
  final String source;
}

// ════════════════════════════════════════════════════════════════════════════
// ASME B31.3-2020 / 2024 — Tab. 331.1.1 (temperatura, czas) i Tab. 331.1.3
// (zwolnienia z obowiązkowego PWHT)
// ════════════════════════════════════════════════════════════════════════════

const _b313Source = 'ASME B31.3-2020/2024, Table 331.1.1';
const _b313ExemptionSource = 'ASME B31.3-2020/2024, Table 331.1.3';

// Tab. 331.1.1, kolumny „Minimum Holding Time at Temperature for Control
// Thickness” — jedna wspólna komórka dla P-No 1 … 11A:
//   do 50 mm (2 in.): 1 h/25 mm (1 hr/in.); 15 min min.
//   ponad 50 mm: 2 hr plus 15 min for each additional 25 mm over 50 mm.
const _b313HoldStandard = PwhtHoldTimeRule(
  minMinutes: 15, // Tab. 331.1.1: „15 min min.”
  proportionalUpToMm: 50, // Tab. 331.1.1: „Up to 50 mm (2 in.)”
  formula: PwhtBiText(
    '1 h/25 mm, min. 15 min (do 50 mm); powyżej 50 mm: 2 h + 15 min za '
        'każde rozpoczęte 25 mm ponad 50 mm',
    '1 h/25 mm, 15 min min. (up to 50 mm); over 50 mm: 2 h + 15 min for '
        'each started 25 mm over 50 mm',
  ),
);

// Tab. 331.1.1, wiersz P-No 15E, Group No. 1:
//   do 50 mm: 1 h/25 mm (1 hr/in.); 30 min min.
//   ponad 50 mm: 1 h/25 mm up to 125 mm (5 in.) plus 15 min for each
//   additional 25 mm over 125 mm.
const _b313Hold15E = PwhtHoldTimeRule(
  minMinutes: 30, // Tab. 331.1.1, P-No 15E: „30 min min.”
  proportionalUpToMm: 125, // Tab. 331.1.1, P-No 15E: „up to 125 mm (5 in.)”
  formula: PwhtBiText(
    '1 h/25 mm, min. 30 min (do 125 mm); powyżej 125 mm: 5 h + 15 min za '
        'każde rozpoczęte 25 mm ponad 125 mm',
    '1 h/25 mm, 30 min min. (up to 125 mm); over 125 mm: 5 h + 15 min for '
        'each started 25 mm over 125 mm',
  ),
);

// Tab. 331.1.3, uwagi wspólne dla wszystkich wierszy.
const _b313ExemptionGeneral = [
  // Tab. 331.1.3 Note (4).
  PwhtCondition(PwhtBiText(
    'Zwolnienie nie obowiązuje, gdy PWHT wymaga projektant lub WPS '
        '(uwaga 4 Tab. 331.1.3).',
    'No exemption applies when the designer or the WPS requires PWHT '
        '(Table 331.1.3 Note 4).',
  )),
];

// Tab. 331.1.3: „Multiple layer welds are used when the nominal material
// thickness > 5 mm (3/16 in.) [Note (6)]” — wspólne dla P-No 1, 3, 4, 5A.
const _b313Multilayer = PwhtCondition(
  PwhtBiText(
    'Spawanie wielowarstwowe (grubość nominalna > 5 mm). Spoina '
        'jednościegowa — tylko gdy WPS kwalifikowano na spoinie '
        'jednościegowej z energią liniową ±10 % (uwaga 6).',
    'Multiple layer welds (nominal thickness > 5 mm). A single-pass weld '
        'only if the WPS was qualified with single-pass welds at ±10 % heat '
        'input (Note 6).',
  ),
  appliesAboveMm: 5, // Tab. 331.1.3: „> 5 mm (3/16 in.)”
);

const List<PwhtTableEntry> _b313 = [
  // ── P-No 1, Group Nos. 1–3 ────────────────────────────────────────────
  PwhtTableEntry(
    code: PwhtCode.asmeB313,
    material: PwhtMaterial.p1,
    // Tab. 331.1.1: 595 to 650 (1,100 to 1,200).
    holdRange: PwhtTempRange(595, 650, 1100, 1200),
    holdTime: _b313HoldStandard,
    // Tab. 331.1.3, P-No 1 all Group Nos.: control thickness „All”,
    // type of weld „All”.
    exemption: PwhtExemption(
      maxThicknessMm: null,
      conditions: [
        // Tab. 331.1.3: „A preheat of 95°C (200°F) is applied prior to
        // welding on any nominal material thickness > 25 mm (1 in.)”.
        PwhtCondition(
          PwhtBiText(
            'Podgrzewanie wstępne min. 95 °C przed spawaniem '
                '(grubość nominalna > 25 mm).',
            'Preheat of 95 °C (200 °F) applied before welding '
                '(nominal thickness > 25 mm).',
          ),
          appliesAboveMm: 25,
        ),
        _b313Multilayer,
        ..._b313ExemptionGeneral,
      ],
      source: _b313ExemptionSource,
    ),
    notRequiredByTable: false,
    notes: [
      // K331.1.1(a) (rozdz. IX, wysokie ciśnienie).
      PwhtBiText(
        'Rurociągi wysokociśnieniowe (rozdz. IX B31.3, K331.1.1): zwolnienie '
            'P-No 1 nie obowiązuje powyżej 19 mm grubości kontrolnej.',
        'High pressure piping (B31.3 Chapter IX, K331.1.1): the P-No 1 '
            'exemption does not apply above 19 mm control thickness.',
      ),
      // §331.1.6(c) + Tab. 331.1.2.
      PwhtBiText(
        'Niższa temperatura z dłuższym czasem (Tab. 331.1.2) — tylko gdy '
            'określi ją projektant.',
        'A lower temperature with a longer time (Table 331.1.2) — only when '
            'specified by the designer.',
      ),
    ],
    source: _b313Source,
  ),

  // ── P-No 3, Group Nos. 1 and 2 ────────────────────────────────────────
  PwhtTableEntry(
    code: PwhtCode.asmeB313,
    material: PwhtMaterial.p3,
    // Tab. 331.1.1: 595 to 650 (1,100 to 1,200).
    holdRange: PwhtTempRange(595, 650, 1100, 1200),
    holdTime: _b313HoldStandard,
    exemption: PwhtExemption(
      // Tab. 331.1.3, P-No 3: control thickness ≤ 16 mm (5/8 in.), all welds.
      maxThicknessMm: 16,
      conditions: [
        // Tab. 331.1.3 (2018+): preheat 95 °C on nominal thickness > 13 mm
        // (1/2 in.). W wydaniu 2014: > 16 mm.
        PwhtCondition(
          PwhtBiText(
            'Podgrzewanie wstępne min. 95 °C przed spawaniem '
                '(grubość nominalna > 13 mm).',
            'Preheat of 95 °C (200 °F) applied before welding '
                '(nominal thickness > 13 mm).',
          ),
          appliesAboveMm: 13,
        ),
        // Tab. 331.1.3: „A specified carbon content of the base materials
        // ≤ 0.25%”.
        PwhtCondition(PwhtBiText(
          'Wymagana (wg specyfikacji materiału) zawartość węgla w materiałach '
              'rodzimych ≤ 0,25 %.',
          'Specified carbon content of the base materials ≤ 0.25 %.',
        )),
        _b313Multilayer,
        ..._b313ExemptionGeneral,
      ],
      source: _b313ExemptionSource,
    ),
    notRequiredByTable: false,
    notes: [
      // §341.3.1(a).
      PwhtBiText(
        'Badania spoin wykonuj po zakończeniu obróbki cieplnej (§341.3.1(a)).',
        'Examine the welds after heat treatment is completed (§341.3.1(a)).',
      ),
      PwhtBiText(
        'Niższa temperatura z dłuższym czasem (Tab. 331.1.2) — tylko gdy '
            'określi ją projektant.',
        'A lower temperature with a longer time (Table 331.1.2) — only when '
            'specified by the designer.',
      ),
    ],
    source: _b313Source,
  ),

  // ── P-No 4, Group No. 1 (temperatura: Group Nos. 1 and 2) ─────────────
  PwhtTableEntry(
    code: PwhtCode.asmeB313,
    material: PwhtMaterial.p4,
    // Tab. 331.1.1: P-No 4, Group Nos. 1 and 2 — 650 to 705 (1,200 to 1,300).
    holdRange: PwhtTempRange(650, 705, 1200, 1300),
    holdTime: _b313HoldStandard,
    exemption: PwhtExemption(
      // Tab. 331.1.3, P-No 4 Group No. 1, groove welds: ≤ 16 mm (5/8 in.).
      maxThicknessMm: 16,
      conditions: [
        // Tab. 331.1.3: „Mandatory preheat has been applied” — wartość
        // z Tab. 330.1.1: P-No 4 — 120 °C (250 °F).
        PwhtCondition(PwhtBiText(
          'Zastosowano obowiązkowe podgrzewanie wstępne (Tab. 330.1.1: '
              'P-No 4 — min. 120 °C).',
          'Mandatory preheat has been applied (Table 330.1.1: P-No 4 — '
              '120 °C / 250 °F min.).',
        )),
        // Tab. 331.1.3: „Specified carbon content of the base materials
        // ≤ 0.15%”.
        PwhtCondition(PwhtBiText(
          'Wymagana (wg specyfikacji materiału) zawartość węgla w materiałach '
              'rodzimych ≤ 0,15 %.',
          'Specified carbon content of the base materials ≤ 0.15 %.',
        )),
        _b313Multilayer,
        ..._b313ExemptionGeneral,
      ],
      source: _b313ExemptionSource,
    ),
    notRequiredByTable: false,
    notes: [
      PwhtBiText(
        'Zwolnienie liczone dla spoin doczołowych. Spoiny kątowe, nasadowe, '
            'uszczelniające i mocowania mają w Tab. 331.1.3 osobne warunki. '
            'Zwolnienie dotyczy tylko Group No. 1.',
        'The exemption shown is for groove welds. Fillet, socket and seal '
            'welds and attachments have separate rows in Table 331.1.3. The '
            'exemption covers Group No. 1 only.',
      ),
      // K331.1.1(b).
      PwhtBiText(
        'Rurociągi wysokociśnieniowe (rozdz. IX, K331.1.1): zwolnienie '
            'P-No 4 nie obowiązuje.',
        'High pressure piping (Chapter IX, K331.1.1): the P-No 4 exemption '
            'does not apply.',
      ),
      // §341.3.1(a).
      PwhtBiText(
        'Badania spoin wykonuj po zakończeniu obróbki cieplnej (§341.3.1(a)).',
        'Examine the welds after heat treatment is completed (§341.3.1(a)).',
      ),
    ],
    source: _b313Source,
  ),

  // ── P-No 5A, Group No. 1 ──────────────────────────────────────────────
  PwhtTableEntry(
    code: PwhtCode.asmeB313,
    material: PwhtMaterial.p5a,
    // Tab. 331.1.1: 675 to 760 (1,250 to 1,400).
    holdRange: PwhtTempRange(675, 760, 1250, 1400),
    holdTime: _b313HoldStandard,
    exemption: PwhtExemption(
      // Tab. 331.1.3, P-No 5A Group No. 1, groove welds: ≤ 16 mm (5/8 in.).
      maxThicknessMm: 16,
      conditions: [
        // „Mandatory preheat has been applied” — Tab. 330.1.1: P-No 5A —
        // 150 °C (300 °F) dla SMTS ≤ 414 MPa (60 ksi), 200 °C (400 °F) powyżej.
        PwhtCondition(PwhtBiText(
          'Zastosowano obowiązkowe podgrzewanie wstępne (Tab. 330.1.1: '
              'P-No 5A — min. 150 °C przy Rm min. ≤ 414 MPa, 200 °C powyżej).',
          'Mandatory preheat has been applied (Table 330.1.1: P-No 5A — '
              '150 °C min. for SMTS ≤ 414 MPa, 200 °C above).',
        )),
        // Tab. 331.1.3: „Specified carbon content of the base materials
        // ≤ 0.15%”.
        PwhtCondition(PwhtBiText(
          'Wymagana (wg specyfikacji materiału) zawartość węgla w materiałach '
              'rodzimych ≤ 0,15 %.',
          'Specified carbon content of the base materials ≤ 0.15 %.',
        )),
        _b313Multilayer,
        ..._b313ExemptionGeneral,
      ],
      source: _b313ExemptionSource,
    ),
    notRequiredByTable: false,
    notes: [
      PwhtBiText(
        'Zwolnienie liczone dla spoin doczołowych. Spoiny kątowe, nasadowe, '
            'uszczelniające i mocowania mają w Tab. 331.1.3 osobne warunki '
            '(np. nasadowe tylko dla rury ≤ 5 mm).',
        'The exemption shown is for groove welds. Fillet, socket and seal '
            'welds and attachments have separate rows in Table 331.1.3 '
            '(e.g. socket welds only for pipe ≤ 5 mm).',
      ),
      // K331.1.1(b).
      PwhtBiText(
        'Rurociągi wysokociśnieniowe (rozdz. IX, K331.1.1): zwolnienie '
            'P-No 5A nie obowiązuje.',
        'High pressure piping (Chapter IX, K331.1.1): the P-No 5A exemption '
            'does not apply.',
      ),
      // §341.3.1(a).
      PwhtBiText(
        'Badania spoin wykonuj po zakończeniu obróbki cieplnej (§341.3.1(a)).',
        'Examine the welds after heat treatment is completed (§341.3.1(a)).',
      ),
    ],
    source: _b313Source,
  ),

  // ── P-No 15E, Group No. 1 (P91) ───────────────────────────────────────
  PwhtTableEntry(
    code: PwhtCode.asmeB313,
    material: PwhtMaterial.p15e,
    // Tab. 331.1.1 (2016+): 705 to 775 (1,300 to 1,425) [Notes (6), (7)].
    // W wydaniu 2014: 730 to 775 (1,350 to 1,425).
    holdRange: PwhtTempRange(705, 775, 1300, 1425),
    holdTime: _b313Hold15E,
    // Tab. 331.1.3: P-No 15E — „No exemptions from PWHT”.
    exemption: null,
    notRequiredByTable: false,
    notes: [
      // Tab. 331.1.1 Note (6).
      PwhtBiText(
        'Grubość nominalna ≤ 13 mm: minimalna temperatura wytrzymania może '
            'wynosić 675 °C (uwaga 6 Tab. 331.1.1).',
        'Nominal thickness ≤ 13 mm: the minimum holding temperature may be '
            '675 °C (1,250 °F) (Table 331.1.1 Note 6).',
      ),
      // Tab. 331.1.1 Note (7).
      PwhtBiText(
        'Ni + Mn w spoiwie ≤ 1,2 %, chyba że projektant określi inaczej — '
            'wtedy maks. temperatura = dolna temperatura przemiany spoiwa, '
            'nie wyżej niż 800 °C. Przekroczenie → spoina do wycięcia '
            '(uwaga 7 Tab. 331.1.1).',
        'Filler Ni + Mn ≤ 1.2 % unless the designer specifies otherwise — '
            'then the max temperature is the filler lower transformation '
            'temperature, never above 800 °C. Exceeded → the weld is cut out '
            '(Table 331.1.1 Note 7).',
      ),
      // §341.3.1(a).
      PwhtBiText(
        'Badania spoin wykonuj po zakończeniu obróbki cieplnej (§341.3.1(a)).',
        'Examine the welds after heat treatment is completed (§341.3.1(a)).',
      ),
    ],
    source: _b313Source,
  ),

  // ── P-No 8, Group Nos. 1–4 ────────────────────────────────────────────
  PwhtTableEntry(
    code: PwhtCode.asmeB313,
    material: PwhtMaterial.p8,
    // Tab. 331.1.1: „PWHT not required unless required by WPS”;
    // Tab. 331.1.3: „PWHT neither required nor prohibited”.
    holdRange: null,
    holdTime: null,
    exemption: null,
    notRequiredByTable: true,
    notes: [
      PwhtBiText(
        'Tab. 331.1.3: PWHT ani wymagane, ani zabronione. Jeżeli WPS '
            'przewiduje obróbkę — parametry wyłącznie z WPS.',
        'Table 331.1.3: PWHT neither required nor prohibited. If the WPS '
            'calls for a heat treatment — parameters from the WPS only.',
      ),
    ],
    source: _b313Source,
  ),
];

// ════════════════════════════════════════════════════════════════════════════
// ASME B31.1-2022 — Tab. 132.1.1-1 (temperatura, czas) i Tab. 132.2-1
// (zwolnienia z obowiązkowego PWHT)
// ════════════════════════════════════════════════════════════════════════════

const _b311Source = 'ASME B31.1-2022, Table 132.1.1-1';
const _b311ExemptionSource = 'ASME B31.1-2022, Table 132.2-1';

// Tab. 132.1.1-1 ma te same czasy co B31.3: „≤2 in. (50 mm): 1 hr/in.
// (25 mm), 15 min minimum; >2 in.: 2 hr plus 15 min for each additional inch
// (25 mm) over 2 in. (50 mm)” — wspólna komórka od P-No 1 do 10I;
// P-No 15E: „1 hr/in., 30 min minimum; 1 hr/in. up to 5 in. (125 mm) plus
// 15 min for each additional inch over 5 in.” → reguły _b313Hold* pasują.

// Tab. 132.2-1 Note (4).
const _b311ExemptionGeneral = [
  PwhtCondition(PwhtBiText(
    'Zwolnienie nie obowiązuje, gdy PWHT wymaga projektant lub WPS '
        '(uwaga 4 Tab. 132.2-1).',
    'No exemption applies when the designer or the WPS requires PWHT '
        '(Table 132.2-1 Note 4).',
  )),
];

// Tab. 132.2-1: „Multiple layer welds are used when the nominal material
// thickness > 3/16 in. (5 mm) [Note (6)]”.
const _b311Multilayer = PwhtCondition(
  PwhtBiText(
    'Spawanie wielowarstwowe (grubość nominalna > 5 mm). Spoina '
        'jednościegowa — tylko gdy WPS kwalifikowano na spoinie '
        'jednościegowej z energią liniową ±10 % (uwaga 6).',
    'Multiple layer welds (nominal thickness > 5 mm). A single-pass weld '
        'only if the WPS was qualified with single-pass welds at ±10 % heat '
        'input (Note 6).',
  ),
  appliesAboveMm: 5, // Tab. 132.2-1: „> 3/16 in. (5 mm)”
);

// §132.3.2: zwolnienia mogą opierać się na rzeczywistym składzie (analiza
// wytopowa / wyrobu) zamiast limitów specyfikacji.
const _b311ChemistryNote = PwhtBiText(
  'Warunki składu mogą opierać się na analizie wytopowej lub wyrobu '
      'zamiast limitów specyfikacji (§132.3.2).',
  'Chemistry conditions may be based on the ladle or product analysis '
      'instead of the specification limits (§132.3.2).',
);

const List<PwhtTableEntry> _b311 = [
  // ── P-No 1, Groups 1–3 ────────────────────────────────────────────────
  PwhtTableEntry(
    code: PwhtCode.asmeB311,
    material: PwhtMaterial.p1,
    // Tab. 132.1.1-1: 1,100 to 1,200 (595 to 650).
    holdRange: PwhtTempRange(595, 650, 1100, 1200),
    holdTime: _b313HoldStandard,
    // Tab. 132.2-1, P-No 1 all Groups: control thickness „All”, weld „All”.
    exemption: PwhtExemption(
      maxThicknessMm: null,
      conditions: [
        // „A preheat of 200°F (95°C) is applied prior to welding on any
        // nominal material thickness > 1 in. (25 mm)”.
        PwhtCondition(
          PwhtBiText(
            'Podgrzewanie wstępne min. 95 °C przed spawaniem '
                '(grubość nominalna > 25 mm).',
            'Preheat of 95 °C (200 °F) applied before welding '
                '(nominal thickness > 25 mm).',
          ),
          appliesAboveMm: 25,
        ),
        _b311Multilayer,
        ..._b311ExemptionGeneral,
      ],
      source: _b311ExemptionSource,
    ),
    notRequiredByTable: false,
    notes: [
      // Tab. 132.1.1-2 + §132.1.1.
      PwhtBiText(
        'Niższa temperatura z dłuższym czasem — Tab. 132.1.1-2.',
        'A lower temperature with a longer time — Table 132.1.1-2.',
      ),
    ],
    source: _b311Source,
  ),

  // ── P-No 3, Groups 1 and 2 ────────────────────────────────────────────
  PwhtTableEntry(
    code: PwhtCode.asmeB311,
    material: PwhtMaterial.p3,
    // Tab. 132.1.1-1: 1,100 to 1,200 (595 to 650).
    holdRange: PwhtTempRange(595, 650, 1100, 1200),
    holdTime: _b313HoldStandard,
    exemption: PwhtExemption(
      // Tab. 132.2-1, P-No 3: control thickness ≤ 5/8 in. (16 mm), all welds.
      maxThicknessMm: 16,
      conditions: [
        // „A preheat of 200°F (95°C) … on any nominal material thickness
        // > 5/8 in. (16 mm)” (B31.1-2022; B31.3-2018+ ma tu 13 mm).
        PwhtCondition(
          PwhtBiText(
            'Podgrzewanie wstępne min. 95 °C przed spawaniem '
                '(grubość nominalna > 16 mm).',
            'Preheat of 95 °C (200 °F) applied before welding '
                '(nominal thickness > 16 mm).',
          ),
          appliesAboveMm: 16,
        ),
        // „Specified carbon content of the base materials ≤ 0.25%”.
        PwhtCondition(PwhtBiText(
          'Wymagana (wg specyfikacji materiału) zawartość węgla w materiałach '
              'rodzimych ≤ 0,25 %.',
          'Specified carbon content of the base materials ≤ 0.25 %.',
        )),
        _b311Multilayer,
        ..._b311ExemptionGeneral,
      ],
      source: _b311ExemptionSource,
    ),
    notRequiredByTable: false,
    notes: [
      _b311ChemistryNote,
      PwhtBiText(
        'Niższa temperatura z dłuższym czasem — Tab. 132.1.1-2.',
        'A lower temperature with a longer time — Table 132.1.1-2.',
      ),
    ],
    source: _b311Source,
  ),

  // ── P-No 4, Group 1 (temperatura: Groups 1 and 2) ─────────────────────
  PwhtTableEntry(
    code: PwhtCode.asmeB311,
    material: PwhtMaterial.p4,
    // Tab. 132.1.1-1: 1,200 to 1,300 (650 to 705).
    holdRange: PwhtTempRange(650, 705, 1200, 1300),
    holdTime: _b313HoldStandard,
    exemption: PwhtExemption(
      // Tab. 132.2-1, P-No 4 Group 1, groove welds: ≤ 5/8 in. (16 mm).
      maxThicknessMm: 16,
      conditions: [
        // „The mandatory preheat has been applied” — Tab. 131.4.1-1:
        // P-No 4 — 250 °F (120 °C).
        PwhtCondition(PwhtBiText(
          'Zastosowano obowiązkowe podgrzewanie wstępne (Tab. 131.4.1-1: '
              'P-No 4 — min. 120 °C).',
          'Mandatory preheat has been applied (Table 131.4.1-1: P-No 4 — '
              '120 °C / 250 °F min.).',
        )),
        // „Specified carbon content of the base materials ≤ 0.20%”
        // (B31.1-2022; w B31.3 dla P-No 4 jest 0,15 %).
        PwhtCondition(PwhtBiText(
          'Wymagana (wg specyfikacji materiału) zawartość węgla w materiałach '
              'rodzimych ≤ 0,20 %.',
          'Specified carbon content of the base materials ≤ 0.20 %.',
        )),
        _b311Multilayer,
        ..._b311ExemptionGeneral,
      ],
      source: _b311ExemptionSource,
    ),
    notRequiredByTable: false,
    notes: [
      PwhtBiText(
        'Zwolnienie liczone dla spoin doczołowych. Spoiny kątowe, nasadowe, '
            'uszczelniające i mocowania mają w Tab. 132.2-1 osobne warunki. '
            'Zwolnienie dotyczy tylko Group 1.',
        'The exemption shown is for groove welds. Fillet, socket and seal '
            'welds and attachments have separate rows in Table 132.2-1. The '
            'exemption covers Group 1 only.',
      ),
      _b311ChemistryNote,
    ],
    source: _b311Source,
  ),

  // ── P-No 5A, Group 1 ──────────────────────────────────────────────────
  PwhtTableEntry(
    code: PwhtCode.asmeB311,
    material: PwhtMaterial.p5a,
    // Tab. 132.1.1-1: 1,250 to 1,400 (675 to 760).
    holdRange: PwhtTempRange(675, 760, 1250, 1400),
    holdTime: _b313HoldStandard,
    exemption: PwhtExemption(
      // Tab. 132.2-1, P-No 5A Group 1, groove welds: ≤ 5/8 in. (16 mm).
      maxThicknessMm: 16,
      conditions: [
        // „The mandatory preheat has been applied” — Tab. 131.4.1-1:
        // P-No 5A — 300 °F (150 °C) dla SMTS ≤ 60 ksi (414 MPa),
        // 400 °F (205 °C) powyżej.
        PwhtCondition(PwhtBiText(
          'Zastosowano obowiązkowe podgrzewanie wstępne (Tab. 131.4.1-1: '
              'P-No 5A — min. 150 °C przy Rm min. ≤ 414 MPa, 205 °C powyżej).',
          'Mandatory preheat has been applied (Table 131.4.1-1: P-No 5A — '
              '150 °C min. for SMTS ≤ 414 MPa, 205 °C above).',
        )),
        // „Specified carbon content of the base materials ≤ 0.15%”.
        PwhtCondition(PwhtBiText(
          'Wymagana (wg specyfikacji materiału) zawartość węgla w materiałach '
              'rodzimych ≤ 0,15 %.',
          'Specified carbon content of the base materials ≤ 0.15 %.',
        )),
        _b311Multilayer,
        ..._b311ExemptionGeneral,
      ],
      source: _b311ExemptionSource,
    ),
    notRequiredByTable: false,
    notes: [
      PwhtBiText(
        'Zwolnienie liczone dla spoin doczołowych. Spoiny kątowe, nasadowe, '
            'uszczelniające i mocowania mają w Tab. 132.2-1 osobne warunki.',
        'The exemption shown is for groove welds. Fillet, socket and seal '
            'welds and attachments have separate rows in Table 132.2-1.',
      ),
      _b311ChemistryNote,
    ],
    source: _b311Source,
  ),

  // ── P-No 15E, Group 1 (P91) ───────────────────────────────────────────
  PwhtTableEntry(
    code: PwhtCode.asmeB311,
    material: PwhtMaterial.p15e,
    // Tab. 132.1.1-1: 1,300 to 1,425 (705 to 775) [Notes (6), (7)].
    holdRange: PwhtTempRange(705, 775, 1300, 1425),
    holdTime: _b313Hold15E,
    // Tab. 132.2-1: P-No 15E — „No exemptions to PWHT”.
    exemption: null,
    notRequiredByTable: false,
    notes: [
      // §131.6.2(b).
      PwhtBiText(
        'Przed rozpoczęciem PWHT schłodź spoinę poniżej temperatury końca '
            'przemiany martenzytycznej spoiwa: ok. 190 °C przy Ni + Mn '
            '≤ 1,2 %, ok. 95 °C przy Ni + Mn > 1,2 % (§131.6.2(b)).',
        'Before PWHT starts, cool the weld below the filler martensite '
            'finish temperature: approx. 190 °C (375 °F) for Ni + Mn ≤ 1.2 %, '
            'approx. 95 °C (200 °F) for Ni + Mn > 1.2 % (§131.6.2(b)).',
      ),
      // §131.6.2(a).
      PwhtBiText(
        'Po spawaniu, przed PWHT: wygrzewanie odwodorujące 260–400 °C, '
            '1 h/25 mm grubości stopiwa, albo zwolnienie z niego na '
            'warunkach §131.6.2(a) (m.in. spoiwa H4).',
        'After welding, before PWHT: hydrogen bakeout at 260–400 °C, '
            '1 hr/in. of deposited weld thickness, or the exemption under '
            '§131.6.2(a) (e.g. H4 consumables).',
      ),
      // Tab. 132.1.1-1 Note (6).
      PwhtBiText(
        'Grubość nominalna ≤ 13 mm: minimalna temperatura wytrzymania może '
            'wynosić 675 °C (uwaga 6 Tab. 132.1.1-1).',
        'Nominal thickness ≤ 13 mm: the minimum holding temperature may be '
            '675 °C (1,250 °F) (Table 132.1.1-1 Note 6).',
      ),
      // Tab. 132.1.1-1 Note (7).
      PwhtBiText(
        'Ni + Mn w spoiwie ≤ 1,2 %, chyba że projektant określi inaczej — '
            'wtedy maks. temperatura = A1 spoiwa, nie wyżej niż 800 °C. '
            'Przekroczenie → spoina do wycięcia (uwaga 7 Tab. 132.1.1-1).',
        'Filler Ni + Mn ≤ 1.2 % unless the designer specifies otherwise — '
            'then the max temperature is the filler A1, never above 800 °C. '
            'Exceeded → the weld is cut out (Table 132.1.1-1 Note 7).',
      ),
    ],
    source: _b311Source,
  ),

  // ── P-No 8, Groups 1–4 ────────────────────────────────────────────────
  PwhtTableEntry(
    code: PwhtCode.asmeB311,
    material: PwhtMaterial.p8,
    // Tab. 132.1.1-1: „PWHT not required unless required by WPS”;
    // Tab. 132.2-1: „PWHT neither required nor prohibited”.
    holdRange: null,
    holdTime: null,
    exemption: null,
    notRequiredByTable: true,
    notes: [
      PwhtBiText(
        'Tab. 132.2-1: PWHT ani wymagane, ani zabronione. Jeżeli WPS '
            'przewiduje obróbkę — parametry wyłącznie z WPS.',
        'Table 132.2-1: PWHT neither required nor prohibited. If the WPS '
            'calls for a heat treatment — parameters from the WPS only.',
      ),
    ],
    source: _b311Source,
  ),
];

List<PwhtTableEntry> _tableFor(PwhtCode code) => switch (code) {
      PwhtCode.asmeB313 => _b313,
      PwhtCode.asmeB311 => _b311,
    };

List<PwhtMaterial> pwhtMaterialsFor(PwhtCode code) =>
    [for (final e in _tableFor(code)) e.material];

PwhtTableEntry? pwhtTableEntry(PwhtCode code, PwhtMaterial m) {
  final table = _tableFor(code);
  for (final e in table) {
    if (e.material == m) return e;
  }
  return null;
}

// ════════════════════════════════════════════════════════════════════════════
// Szybkości nagrzewania i chłodzenia
// ════════════════════════════════════════════════════════════════════════════

// ASME B31.3-2020/2024 §331.1.4 (tekst od wydania 2014): „Above 315°C
// (600°F), the rate of heating and cooling shall not exceed 335°C/h
// (600°F/hr) divided by one-half the maximum material thickness in inches at
// the weld, but in no case shall the rate exceed 335°C/h (600°F/hr).”
//
//   v = 335 / (t[in] / 2) = 335 · 2 · 25,4 / t[mm] = 17 018 / t[mm]  °C/h,
//   v ≤ 335 °C/h (limit obowiązuje do t ≈ 50,8 mm).
// Norma nie podaje dolnej granicy („nie musi być mniejsza niż”) ani szybkości
// chłodzenia poniżej 315 °C (poza P-No 7, 10I, 11A, 62 — nie w tym module).
const PwhtRateRule _b313Rates = PwhtRateRule(
  id: 'b313-331.1.4',
  namePl: 'ASME B31.3 §331.1.4',
  nameEn: 'ASME B31.3 §331.1.4',
  source: 'ASME B31.3-2020/2024 §331.1.4',
  controlTempC: 315, // „Above 315°C (600°F)”
  heatCoefficient: 335 * 2 * 25.4, // 335 °C/h ÷ (t[in] / 2), t w mm
  heatCapCPerH: 335, // „in no case shall the rate exceed 335°C/h”
  coolCoefficient: 335 * 2 * 25.4, // ta sama reguła dla chłodzenia
  coolCapCPerH: 335,
  floorCPerH: null, // §331.1.4 nie podaje dolnej granicy
  notePl: 'Ta sama reguła dla nagrzewania i chłodzenia: 335 °C/h podzielone '
      'przez połowę największej grubości w calach, nie więcej niż 335 °C/h.',
  noteEn: 'One rule for heating and cooling: 335 °C/h divided by one-half '
      'the maximum thickness in inches, never more than 335 °C/h.',
  belowControlPl: 'B31.3 nie określa szybkości — wg procedury PWHT',
  belowControlEn: 'B31.3 sets no rate — per the PWHT procedure',
);

// ASME B31.1-2022 §132.5 — ta sama reguła: „Above 600°F (315°C), the rate
// of heating and cooling shall not exceed 600°F/hr (335°C/h) divided by
// one-half the maximum thickness of material in inches at the weld, but in no
// case shall the rate exceed 600°F/hr (335°C/h).”
const PwhtRateRule _b311Rates = PwhtRateRule(
  id: 'b311-132.5',
  namePl: 'ASME B31.1 §132.5',
  nameEn: 'ASME B31.1 §132.5',
  source: 'ASME B31.1-2022 §132.5',
  controlTempC: 315, // „Above 600°F (315°C)”
  heatCoefficient: 335 * 2 * 25.4, // 335 °C/h ÷ (t[in] / 2), t w mm
  heatCapCPerH: 335, // „in no case shall the rate exceed 600°F/hr (335°C/h)”
  coolCoefficient: 335 * 2 * 25.4,
  coolCapCPerH: 335,
  floorCPerH: null, // §132.5 nie podaje dolnej granicy
  notePl: 'Ta sama reguła dla nagrzewania i chłodzenia: 335 °C/h podzielone '
      'przez połowę największej grubości w calach, nie więcej niż 335 °C/h.',
  noteEn: 'One rule for heating and cooling: 335 °C/h divided by one-half '
      'the maximum thickness in inches, never more than 335 °C/h.',
  belowControlPl: 'B31.1 nie określa szybkości — wg procedury PWHT',
  belowControlEn: 'B31.1 sets no rate — per the PWHT procedure',
);

PwhtRateRule? pwhtRateRuleFor(PwhtCode code) => switch (code) {
      PwhtCode.asmeB313 => _b313Rates,
      PwhtCode.asmeB311 => _b311Rates,
    };

// ════════════════════════════════════════════════════════════════════════════
// Pasmo wytrzymania przy grzaniu miejscowym (soak band)
// ════════════════════════════════════════════════════════════════════════════

class PwhtSoakBandRule {
  const PwhtSoakBandRule({
    required this.thicknessMultiplier,
    required this.formula,
    required this.source,
  });

  /// Szerokość pasma = mnożnik × grubość.
  final double thicknessMultiplier;
  final PwhtBiText formula;
  final String source;
}

// ASME B31.3-2020/2024 §331.2.6 (tekst od wydania 2014): „Welds may be
// locally postweld heat treated by heating a circumferential band around the
// entire component with the weld located in the center of the band. The
// width of the band heated to the specified temperature range shall be at
// least three times the wall thickness at the weld of the thickest part
// being joined.” (Wydania ≤ 2012 mówiły o 25 mm poza spoiną — inna reguła.)
const _b313SoakBand = PwhtSoakBandRule(
  thicknessMultiplier: 3, // „at least three times the wall thickness”
  formula: PwhtBiText(
    'min. 3 × grubość ścianki w spoinie, spoina na środku pasma, pasmo '
        'na całym obwodzie',
    'min. 3 × wall thickness at the weld, weld at the band centre, band '
        'around the full circumference',
  ),
  source: 'ASME B31.3-2020/2024 §331.2.6',
);

// ASME B31.1-2022 §132.7: „… with the weld located in the approximate
// center of the band. The width of the band heated to the specified
// temperature range shall be at least three times the wall thickness at the
// weld of the thickest part being joined.”
const _b311SoakBand = PwhtSoakBandRule(
  thicknessMultiplier: 3, // „at least three times the wall thickness”
  formula: PwhtBiText(
    'min. 3 × grubość ścianki w spoinie, spoina w przybliżeniu na środku '
        'pasma, pasmo na całym obwodzie',
    'min. 3 × wall thickness at the weld, weld at about the band centre, '
        'band around the full circumference',
  ),
  source: 'ASME B31.1-2022 §132.7',
);

PwhtSoakBandRule? soakBandRuleFor(PwhtCode code) => switch (code) {
      PwhtCode.asmeB313 => _b313SoakBand,
      PwhtCode.asmeB311 => _b311SoakBand,
    };

// ════════════════════════════════════════════════════════════════════════════
// Strefy regulacji grzania miejscowego — AWS D10.10/D10.10M:2021
// ════════════════════════════════════════════════════════════════════════════

/// Zalecana liczba stref regulacji dla spoiny doczołowej rury POZIOMEJ.
class PwhtControlZones {
  const PwhtControlZones({
    required this.zones,
    required this.npsRange,
    required this.source,
  });

  /// Liczba stref; null = powyżej NPS 30 (norma nie podaje jednej liczby).
  final int? zones;

  /// Zakres średnic z tytułu rysunku, np. „NPS 8–12 (DN 200–300)”.
  final String npsRange;
  final String source;
}

// AWS D10.10/D10.10M:2021, spis rysunków (oficjalny podgląd, pubs.aws.org):
//   rys. 8.3 — „up to NPS 6 [DN 150] and One Control Zone”,
//   rys. 8.4 — „NPS 8 and up to NPS 12 [DN 200 to DN 300] and Two Control
//              Zones”,
//   rys. 8.5 — „from NPS 14 and up through NPS 18 [DN 350 to DN 450] and
//              Three Control Zones”,
//   rys. 8.6 — „NPS 20 and up to NPS 30 [DN 500 to DN 750] and Four
//              Control Zones”;
// wszystkie dla „Piping in the Horizontal Position”. Średnice zewnętrzne
// NPS: NPS 6 = 168,3 mm, NPS 12 = 323,8 mm (EN: 323,9), NPS 18 = 457,2 mm
// (18 in), NPS 30 = 762 mm (30 in). Średnica między przedziałami (rura
// niestandardowa) → przedział WYŻSZY (więcej stref — strona bezpieczna).
const _d1010Source = 'AWS D10.10/D10.10M:2021, Fig. 8.3–8.6';

/// `null` dla średnicy ≤ 0 / nieznanej.
PwhtControlZones? d1010ControlZones(double? outsideDiameterMm) {
  final od = outsideDiameterMm;
  if (od == null || !od.isFinite || od <= 0) return null;
  if (od <= 168.3) {
    return const PwhtControlZones(
        zones: 1, npsRange: '≤ NPS 6 (DN 150)', source: _d1010Source);
  }
  if (od <= 323.9) {
    return const PwhtControlZones(
        zones: 2, npsRange: 'NPS 8–12 (DN 200–300)', source: _d1010Source);
  }
  if (od <= 457.2) {
    return const PwhtControlZones(
        zones: 3, npsRange: 'NPS 14–18 (DN 350–450)', source: _d1010Source);
  }
  if (od <= 762) {
    return const PwhtControlZones(
        zones: 4, npsRange: 'NPS 20–30 (DN 500–750)', source: _d1010Source);
  }
  return const PwhtControlZones(
      zones: null, npsRange: '> NPS 30 (DN 750)', source: _d1010Source);
}

/// Minimalna szerokość pasma wytrzymania [mm] dla spoiny obwodowej.
/// `null` dla grubości ≤ 0. [weldWidthMm] nie zmienia minimum normy — ekran
/// ostrzega osobno, gdy spoina jest szersza niż pasmo.
double? soakBandWidthMm({
  required PwhtCode code,
  required double thicknessMm,
  double? weldWidthMm,
}) {
  if (!thicknessMm.isFinite || thicknessMm <= 0) return null;
  final rule = soakBandRuleFor(code);
  if (rule == null) return null;
  return rule.thicknessMultiplier * thicknessMm;
}
