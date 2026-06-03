// Material catalog for heat-input / preheat calculation. Lets the welder
// pick a named grade (A106 B, P91, 304L…) instead of typing the chemistry
// row by row. Compositions are typical / nominal — for critical jobs the
// welder still has to read the actual MTR, but for shop training and routine
// fab these defaults are within tolerance.
//
// Sources:
//   - ASME II Part A (specifications)
//   - ASME Section IX QW-422 (P-numbers + typical ranges)
//   - AWS D1.1 Annex (HI windows per process)

class MaterialSpec {
  final String key;       // short code shown in the picker
  final String name;      // full descriptive name
  final int pNumber;      // ASME Section IX P-No (welding qualification grouping)
  final double c, mn, cr, mo, v, ni, cu;
  /// Typical WPS heat input window in kJ/mm.
  final double hiMin, hiMax;
  /// Recommended preheat (°C). Range string for human reading.
  final String preheatNote;
  final String notes;

  const MaterialSpec({
    required this.key,
    required this.name,
    required this.pNumber,
    this.c = 0,
    this.mn = 0,
    this.cr = 0,
    this.mo = 0,
    this.v = 0,
    this.ni = 0,
    this.cu = 0,
    this.hiMin = 1.0,
    this.hiMax = 2.5,
    this.preheatNote = '50–100 °C',
    this.notes = '',
  });
}

class MaterialCatalog {
  static const all = <MaterialSpec>[
    // ── P-No 1 — C-Mn steels ───────────────────────────────────────────────
    MaterialSpec(
      key: 'A106 B',
      name: 'ASTM A106 Gr.B (seamless C-Mn pipe)',
      pNumber: 1,
      c: 0.25, mn: 1.06, cr: 0.0, mo: 0.0, v: 0.0, ni: 0.0, cu: 0.0,
      hiMin: 1.0, hiMax: 2.5,
      preheatNote: '10 °C (>25 mm: 50 °C)',
      notes: 'Najczęstsza rura procesowa CS w pętli. CE ~0.43.',
    ),
    MaterialSpec(
      key: 'A53 B',
      name: 'ASTM A53 Gr.B (ERW/seamless C-Mn pipe)',
      pNumber: 1,
      c: 0.30, mn: 1.20, cr: 0.0, mo: 0.0, v: 0.0, ni: 0.0, cu: 0.0,
      hiMin: 1.0, hiMax: 2.5,
      preheatNote: '10 °C (>25 mm: 50 °C)',
      notes: 'Tańszy zamiennik A106, niższa jakość seam.',
    ),
    MaterialSpec(
      key: 'A516 70',
      name: 'ASTM A516 Gr.70 (pressure vessel plate)',
      pNumber: 1,
      c: 0.27, mn: 1.20, cr: 0.0, mo: 0.0, v: 0.02, ni: 0.0, cu: 0.0,
      hiMin: 1.5, hiMax: 3.5,
      preheatNote: '100 °C (>32 mm: 150 °C)',
      notes: 'Płaszcz zbiornika, kotła. Wymaga PWHT >38 mm.',
    ),
    // ── P-No 3 — C-Mo / Mn-Mo ──────────────────────────────────────────────
    MaterialSpec(
      key: 'A335 P1',
      name: 'A335 P1 (C-½Mo pipe)',
      pNumber: 3,
      c: 0.20, mn: 0.50, cr: 0.0, mo: 0.50, v: 0.0, ni: 0.0, cu: 0.0,
      hiMin: 1.0, hiMax: 2.5,
      preheatNote: '100 °C',
      notes: 'Rura wysokotemp. do ~520 °C. Mo poprawia creep.',
    ),
    // ── P-No 4 — 1¼Cr-½Mo ─────────────────────────────────────────────────
    MaterialSpec(
      key: 'P11 / T11',
      name: 'A335 P11 (1¼Cr-½Mo)',
      pNumber: 4,
      c: 0.15, mn: 0.50, cr: 1.20, mo: 0.55, v: 0.0, ni: 0.0, cu: 0.0,
      hiMin: 1.5, hiMax: 3.0,
      preheatNote: '150–200 °C, max interpass 300 °C',
      notes: 'PWHT obowiązkowe powyżej 13 mm.',
    ),
    // ── P-No 5A — 2¼Cr-1Mo ────────────────────────────────────────────────
    MaterialSpec(
      key: 'P22 / T22',
      name: 'A335 P22 (2¼Cr-1Mo)',
      pNumber: 5,
      c: 0.12, mn: 0.45, cr: 2.25, mo: 1.0, v: 0.0, ni: 0.0, cu: 0.0,
      hiMin: 1.5, hiMax: 3.0,
      preheatNote: '200–250 °C, max interpass 300 °C',
      notes: 'Rafineria, hydrocracker. PWHT 690–720 °C / 1 h-cal.',
    ),
    // ── P-No 5B — 9Cr-1Mo-V (Grade 91) ─────────────────────────────────────
    MaterialSpec(
      key: 'P91 / T91',
      name: 'A335 P91 (9Cr-1Mo-V martensitic)',
      pNumber: 5,
      c: 0.10, mn: 0.45, cr: 9.0, mo: 1.0, v: 0.20, ni: 0.30, cu: 0.0,
      hiMin: 1.0, hiMax: 2.5,
      preheatNote: '200–250 °C, interpass 250–300 °C (KRYT.)',
      notes: 'PWHT 750–770 °C / 1 h-cal OBOWIĄZKOWE. Tylko E9015-B9.',
    ),
    // ── P-No 6 — Martensitic SS ────────────────────────────────────────────
    MaterialSpec(
      key: '410 SS',
      name: '410 / F6a (12% Cr martensitic SS)',
      pNumber: 6,
      c: 0.12, mn: 0.50, cr: 12.5, mo: 0.0, v: 0.0, ni: 0.0, cu: 0.0,
      hiMin: 1.0, hiMax: 2.5,
      preheatNote: '200 °C',
      notes: 'Trim zaworu, klamry. Bardzo wrażliwa na cracking.',
    ),
    // ── P-No 8 — Austenitic SS ─────────────────────────────────────────────
    MaterialSpec(
      key: '304 / 304L',
      name: 'AISI 304 / 304L (18-8 austenitic SS)',
      pNumber: 8,
      c: 0.03, mn: 1.50, cr: 18.5, mo: 0.0, v: 0.0, ni: 8.5, cu: 0.0,
      hiMin: 0.5, hiMax: 1.8,
      preheatNote: 'Bez preheat. Interpass <175 °C.',
      notes: 'Niski HI ogranicza sensitization. Argon pure or 98Ar/2N2.',
    ),
    MaterialSpec(
      key: '316 / 316L',
      name: 'AISI 316 / 316L (Mo austenitic SS)',
      pNumber: 8,
      c: 0.03, mn: 1.50, cr: 17.0, mo: 2.5, v: 0.0, ni: 12.0, cu: 0.0,
      hiMin: 0.5, hiMax: 1.8,
      preheatNote: 'Bez preheat. Interpass <175 °C.',
      notes: 'Standard farma. ER316L drut. Sensitization risk @ 500–800°C.',
    ),
    MaterialSpec(
      key: '321',
      name: 'AISI 321 (Ti-stabilised austenitic SS)',
      pNumber: 8,
      c: 0.05, mn: 1.50, cr: 17.5, mo: 0.0, v: 0.0, ni: 9.5, cu: 0.0,
      hiMin: 0.5, hiMax: 1.8,
      preheatNote: 'Bez preheat. Interpass <175 °C.',
      notes: 'Ti zamiast Nb. Rura żaroodporna do 870 °C.',
    ),
    MaterialSpec(
      key: '347',
      name: 'AISI 347 (Nb-stabilised austenitic SS)',
      pNumber: 8,
      c: 0.05, mn: 1.50, cr: 18.0, mo: 0.0, v: 0.0, ni: 10.5, cu: 0.0,
      hiMin: 0.5, hiMax: 1.8,
      preheatNote: 'Bez preheat. Interpass <175 °C.',
      notes: 'Wymagany w refinery dla T >425 °C (NACE).',
    ),
    // ── P-No 10H — Duplex / Super Duplex ───────────────────────────────────
    MaterialSpec(
      key: '2205 Duplex',
      name: 'UNS S32205 (22Cr Duplex)',
      pNumber: 10,
      c: 0.03, mn: 1.50, cr: 22.0, mo: 3.0, v: 0.0, ni: 5.5, cu: 0.0,
      hiMin: 0.5, hiMax: 2.5,
      preheatNote: 'Bez preheat. Interpass <150 °C.',
      notes: 'KRYT. okno HI. Powyżej 2.5 kJ/mm: σ-phase. Tlen <100 ppm w Ar.',
    ),
    MaterialSpec(
      key: '2507 SuperDuplex',
      name: 'UNS S32750 (25Cr Super Duplex)',
      pNumber: 10,
      c: 0.03, mn: 1.20, cr: 25.0, mo: 4.0, v: 0.0, ni: 7.0, cu: 0.0,
      hiMin: 0.5, hiMax: 1.8,
      preheatNote: 'Bez preheat. Interpass <100 °C.',
      notes: 'Jeszcze ciaśniejsze okno HI. Tlen <50 ppm.',
    ),
    // ── P-No 41-45 — Ni alloys ─────────────────────────────────────────────
    MaterialSpec(
      key: 'Inconel 625',
      name: 'UNS N06625 (Ni-Cr-Mo, Inconel 625)',
      pNumber: 43,
      c: 0.04, mn: 0.20, cr: 21.5, mo: 9.0, v: 0.0, ni: 60.0, cu: 0.0,
      hiMin: 0.5, hiMax: 1.5,
      preheatNote: 'Bez preheat. Interpass <120 °C.',
      notes: 'Niski HI! ERNiCrMo-3 drut. Ar pure GTAW.',
    ),
    MaterialSpec(
      key: 'Monel 400',
      name: 'UNS N04400 (Ni-Cu, Monel 400)',
      pNumber: 42,
      c: 0.15, mn: 1.50, cr: 0.0, mo: 0.0, v: 0.0, ni: 66.0, cu: 31.0,
      hiMin: 0.6, hiMax: 1.8,
      preheatNote: 'Bez preheat.',
      notes: 'ERNiCu-7 drut. Czysty argon GTAW.',
    ),
  ];

  static MaterialSpec? findByKey(String key) {
    for (final m in all) {
      if (m.key == key) return m;
    }
    return null;
  }
}
