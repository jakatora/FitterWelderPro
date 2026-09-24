// Material catalog for heat-input / preheat calculation. Lets the welder
// pick a named grade (A106 B, P91, 304L…) instead of typing the chemistry
// row by row. Compositions are typical / nominal — for critical jobs the
// welder still has to read the actual MTR, but for shop training and routine
// fab these defaults are within tolerance.
//
// Sources:
//   - ASME II Part A (specifications)
//   - ASME Section IX QW/QB-422 (P-numbers). Grade 91 (9Cr-1Mo-V) is
//     P-No 15E — ASME split creep-strength-enhanced ferritic steels out of
//     P-No 5B; a P-5B qualification does not cover P-15E.
//   - Preheat CODE minimum is NOT stored here — it is computed from P-No and
//     thickness in lib/domain/welding/preheat.dart (ASME B31.3 Tab. 330.1.1).
//     The `practice*` notes below are typical WPS practice, not a code value.

class MaterialSpec {
  final String key;       // short code shown in the picker
  final String name;      // full descriptive name

  /// ASME Section IX P-No (QW/QB-422) — '1', '5A', '15E', '10H'…
  final String pNo;
  final double c, mn, cr, mo, v, ni, cu;

  /// Typical heat-input window of WPS for this grade in kJ/mm — reference
  /// only. The welder's own WPS range is what the result is checked against.
  final double hiMin, hiMax;

  /// Typical WPS practice for preheat / interpass (PL / EN). Not a code
  /// minimum and not a calculation result.
  final String practicePl, practiceEn;

  final String notesPl, notesEn;

  const MaterialSpec({
    required this.key,
    required this.name,
    required this.pNo,
    this.c = 0,
    this.mn = 0,
    this.cr = 0,
    this.mo = 0,
    this.v = 0,
    this.ni = 0,
    this.cu = 0,
    this.hiMin = 1.0,
    this.hiMax = 2.5,
    required this.practicePl,
    required this.practiceEn,
    this.notesPl = '',
    this.notesEn = '',
  });

  /// Numeric part of the P-No (15E → 15, 5A → 5, 10H → 10).
  int get pNoBase =>
      int.parse(RegExp(r'^\d+').firstMatch(pNo)?.group(0) ?? '0');

  /// Ferritic low-alloy / martensitic groups where low-hydrogen consumables
  /// are standard practice regardless of CE (C-Mo, Cr-Mo, Grade 91, 410).
  /// Not for austenitic (P-8), duplex (P-10H) or nickel alloys (P-4x).
  bool get lowHydrogenAdvised =>
      const {'3', '4', '5A', '5B', '5C', '6', '15E'}.contains(pNo);
}

class MaterialCatalog {
  static const all = <MaterialSpec>[
    // ── P-No 1 — C-Mn steels ───────────────────────────────────────────────
    MaterialSpec(
      key: 'A106 B',
      name: 'ASTM A106 Gr.B (seamless C-Mn pipe)',
      pNo: '1',
      c: 0.25, mn: 1.06, cr: 0.0, mo: 0.0, v: 0.0, ni: 0.0, cu: 0.0,
      hiMin: 1.0, hiMax: 2.5,
      practicePl: 'Min. kodowe ASME B31.3: 10 °C (t < 25 mm), 80 °C (t ≥ 25 mm). '
          'Przy wysokim CE potrzeba więcej — patrz metody.',
      practiceEn: 'Code min. ASME B31.3: 10 °C (t < 25 mm), 80 °C (t ≥ 25 mm). '
          'A high CE needs more — see the methods.',
      notesPl: 'Najczęstsza rura procesowa CS. CE ~0.43.',
      notesEn: 'The most common CS process pipe. CE ~0.43.',
    ),
    MaterialSpec(
      key: 'A53 B',
      name: 'ASTM A53 Gr.B (ERW/seamless C-Mn pipe)',
      pNo: '1',
      c: 0.30, mn: 1.20, cr: 0.0, mo: 0.0, v: 0.0, ni: 0.0, cu: 0.0,
      hiMin: 1.0, hiMax: 2.5,
      practicePl: 'Min. kodowe ASME B31.3: 10 °C (t < 25 mm), 80 °C (t ≥ 25 mm). '
          'Przy wysokim CE potrzeba więcej — patrz metody.',
      practiceEn: 'Code min. ASME B31.3: 10 °C (t < 25 mm), 80 °C (t ≥ 25 mm). '
          'A high CE needs more — see the methods.',
      notesPl: 'Tańszy zamiennik A106, niższa jakość szwu.',
      notesEn: 'Cheaper alternative to A106, lower seam quality.',
    ),
    MaterialSpec(
      key: 'A516 70',
      name: 'ASTM A516 Gr.70 (pressure vessel plate)',
      pNo: '1',
      c: 0.27, mn: 1.20, cr: 0.0, mo: 0.0, v: 0.02, ni: 0.0, cu: 0.0,
      hiMin: 1.5, hiMax: 3.5,
      practicePl: 'Typowo w WPS: 100 °C (>32 mm: 150 °C).',
      practiceEn: 'Typical WPS: 100 °C (>32 mm: 150 °C).',
      notesPl: 'Płaszcz zbiornika, kotła. Wymaga PWHT >38 mm.',
      notesEn: 'Vessel / boiler shell. PWHT required >38 mm.',
    ),
    // ── P-No 3 — C-Mo / Mn-Mo ──────────────────────────────────────────────
    MaterialSpec(
      key: 'A335 P1',
      name: 'A335 P1 (C-½Mo pipe)',
      pNo: '3',
      c: 0.20, mn: 0.50, cr: 0.0, mo: 0.50, v: 0.0, ni: 0.0, cu: 0.0,
      hiMin: 1.0, hiMax: 2.5,
      practicePl: 'Typowo w WPS: 100 °C.',
      practiceEn: 'Typical WPS: 100 °C.',
      notesPl: 'Rura wysokotemp. do ~520 °C. Mo poprawia odporność na pełzanie.',
      notesEn: 'High-temperature pipe up to ~520 °C. Mo improves creep strength.',
    ),
    // ── P-No 4 — 1¼Cr-½Mo ─────────────────────────────────────────────────
    MaterialSpec(
      key: 'P11 / T11',
      name: 'A335 P11 (1¼Cr-½Mo)',
      pNo: '4',
      c: 0.15, mn: 0.50, cr: 1.20, mo: 0.55, v: 0.0, ni: 0.0, cu: 0.0,
      hiMin: 1.5, hiMax: 3.0,
      practicePl: 'Typowo w WPS: 150–200 °C, interpass max 300 °C.',
      practiceEn: 'Typical WPS: 150–200 °C, interpass max 300 °C.',
      notesPl: 'PWHT obowiązkowe powyżej 13 mm.',
      notesEn: 'PWHT mandatory above 13 mm.',
    ),
    // ── P-No 5A — 2¼Cr-1Mo ────────────────────────────────────────────────
    MaterialSpec(
      key: 'P22 / T22',
      name: 'A335 P22 (2¼Cr-1Mo)',
      pNo: '5A',
      c: 0.12, mn: 0.45, cr: 2.25, mo: 1.0, v: 0.0, ni: 0.0, cu: 0.0,
      hiMin: 1.5, hiMax: 3.0,
      practicePl: 'Typowo w WPS: 200–250 °C, interpass max 300 °C.',
      practiceEn: 'Typical WPS: 200–250 °C, interpass max 300 °C.',
      notesPl: 'Rafineria, hydrocracker. PWHT typowo 690–720 °C / 1 h na cal.',
      notesEn: 'Refinery, hydrocracker. PWHT typically 690–720 °C / 1 h per inch.',
    ),
    // ── P-No 15E — 9Cr-1Mo-V (Grade 91, CSEF) ─────────────────────────────
    MaterialSpec(
      key: 'P91 / T91',
      name: 'A335 P91 (9Cr-1Mo-V martensitic)',
      pNo: '15E',
      c: 0.10, mn: 0.45, cr: 9.0, mo: 1.0, v: 0.20, ni: 0.30, cu: 0.0,
      hiMin: 1.0, hiMax: 2.5,
      practicePl: 'Typowo w WPS: 200–250 °C, interpass 250–300 °C (KRYTYCZNE).',
      practiceEn: 'Typical WPS: 200–250 °C, interpass 250–300 °C (CRITICAL).',
      notesPl: 'PWHT 750–770 °C / 1 h na cal OBOWIĄZKOWE. Tylko E9015-B9.',
      notesEn: 'PWHT 750–770 °C / 1 h per inch MANDATORY. E9015-B9 only.',
    ),
    // ── P-No 6 — Martensitic SS ────────────────────────────────────────────
    MaterialSpec(
      key: '410 SS',
      name: '410 / F6a (12% Cr martensitic SS)',
      pNo: '6',
      c: 0.12, mn: 0.50, cr: 12.5, mo: 0.0, v: 0.0, ni: 0.0, cu: 0.0,
      hiMin: 1.0, hiMax: 2.5,
      practicePl: 'Typowo w WPS: 200 °C.',
      practiceEn: 'Typical WPS: 200 °C.',
      notesPl: 'Trim zaworu, klamry. Bardzo wrażliwa na pękanie.',
      notesEn: 'Valve trim, clamps. Very crack-sensitive.',
    ),
    // ── P-No 8 — Austenitic SS ─────────────────────────────────────────────
    MaterialSpec(
      key: '304 / 304L',
      name: 'AISI 304 / 304L (18-8 austenitic SS)',
      pNo: '8',
      c: 0.03, mn: 1.50, cr: 18.5, mo: 0.0, v: 0.0, ni: 8.5, cu: 0.0,
      hiMin: 0.5, hiMax: 1.8,
      practicePl: 'Bez podgrzewania. Interpass < 175 °C.',
      practiceEn: 'No preheat. Interpass < 175 °C.',
      notesPl: 'Niskie HI ogranicza sensytyzację. Argon czysty lub 98Ar/2N₂.',
      notesEn: 'Low HI limits sensitisation. Pure argon or 98Ar/2N₂.',
    ),
    MaterialSpec(
      key: '316 / 316L',
      name: 'AISI 316 / 316L (Mo austenitic SS)',
      pNo: '8',
      c: 0.03, mn: 1.50, cr: 17.0, mo: 2.5, v: 0.0, ni: 12.0, cu: 0.0,
      hiMin: 0.5, hiMax: 1.8,
      practicePl: 'Bez podgrzewania. Interpass < 175 °C.',
      practiceEn: 'No preheat. Interpass < 175 °C.',
      notesPl: 'Standard farmaceutyczny. Drut ER316L. Ryzyko sensytyzacji w 500–800 °C.',
      notesEn: 'Pharma standard. ER316L wire. Sensitisation risk at 500–800 °C.',
    ),
    MaterialSpec(
      key: '321',
      name: 'AISI 321 (Ti-stabilised austenitic SS)',
      pNo: '8',
      c: 0.05, mn: 1.50, cr: 17.5, mo: 0.0, v: 0.0, ni: 9.5, cu: 0.0,
      hiMin: 0.5, hiMax: 1.8,
      practicePl: 'Bez podgrzewania. Interpass < 175 °C.',
      practiceEn: 'No preheat. Interpass < 175 °C.',
      notesPl: 'Ti zamiast Nb. Rura żaroodporna do 870 °C.',
      notesEn: 'Ti instead of Nb. Heat-resistant pipe up to 870 °C.',
    ),
    MaterialSpec(
      key: '347',
      name: 'AISI 347 (Nb-stabilised austenitic SS)',
      pNo: '8',
      c: 0.05, mn: 1.50, cr: 18.0, mo: 0.0, v: 0.0, ni: 10.5, cu: 0.0,
      hiMin: 0.5, hiMax: 1.8,
      practicePl: 'Bez podgrzewania. Interpass < 175 °C.',
      practiceEn: 'No preheat. Interpass < 175 °C.',
      notesPl: 'Wymagany w rafinerii dla T > 425 °C (NACE).',
      notesEn: 'Required in refineries for T > 425 °C (NACE).',
    ),
    // ── P-No 10H — Duplex / Super Duplex ───────────────────────────────────
    MaterialSpec(
      key: '2205 Duplex',
      name: 'UNS S32205 (22Cr Duplex)',
      pNo: '10H',
      c: 0.03, mn: 1.50, cr: 22.0, mo: 3.0, v: 0.0, ni: 5.5, cu: 0.0,
      hiMin: 0.5, hiMax: 2.5,
      practicePl: 'Bez podgrzewania. Interpass < 150 °C.',
      practiceEn: 'No preheat. Interpass < 150 °C.',
      notesPl: 'Krytyczne okno HI. Powyżej 2.5 kJ/mm: faza σ. Tlen < 100 ppm w Ar.',
      notesEn: 'Critical HI window. Above 2.5 kJ/mm: σ phase. O₂ < 100 ppm in Ar.',
    ),
    MaterialSpec(
      key: '2507 SuperDuplex',
      name: 'UNS S32750 (25Cr Super Duplex)',
      pNo: '10H',
      c: 0.03, mn: 1.20, cr: 25.0, mo: 4.0, v: 0.0, ni: 7.0, cu: 0.0,
      hiMin: 0.5, hiMax: 1.8,
      practicePl: 'Bez podgrzewania. Interpass < 100 °C.',
      practiceEn: 'No preheat. Interpass < 100 °C.',
      notesPl: 'Jeszcze ciaśniejsze okno HI. Tlen < 50 ppm.',
      notesEn: 'Even tighter HI window. O₂ < 50 ppm.',
    ),
    // ── P-No 41-45 — Ni alloys ─────────────────────────────────────────────
    MaterialSpec(
      key: 'Inconel 625',
      name: 'UNS N06625 (Ni-Cr-Mo, Inconel 625)',
      pNo: '43',
      c: 0.04, mn: 0.20, cr: 21.5, mo: 9.0, v: 0.0, ni: 60.0, cu: 0.0,
      hiMin: 0.5, hiMax: 1.5,
      practicePl: 'Bez podgrzewania. Interpass < 120 °C.',
      practiceEn: 'No preheat. Interpass < 120 °C.',
      notesPl: 'Niskie HI! Drut ERNiCrMo-3. GTAW w czystym Ar.',
      notesEn: 'Low HI! ERNiCrMo-3 wire. GTAW in pure Ar.',
    ),
    MaterialSpec(
      key: 'Monel 400',
      name: 'UNS N04400 (Ni-Cu, Monel 400)',
      pNo: '42',
      c: 0.15, mn: 1.50, cr: 0.0, mo: 0.0, v: 0.0, ni: 66.0, cu: 31.0,
      hiMin: 0.6, hiMax: 1.8,
      practicePl: 'Bez podgrzewania.',
      practiceEn: 'No preheat.',
      notesPl: 'Drut ERNiCu-7. GTAW w czystym argonie.',
      notesEn: 'ERNiCu-7 wire. GTAW in pure argon.',
    ),
  ];

  static MaterialSpec? findByKey(String key) {
    for (final m in all) {
      if (m.key == key) return m;
    }
    return null;
  }
}
