// Take-out (CTE = centre-to-end) reference values for butt-weld and flanged
// piping components per ASME B16.9 / B16.11 / B16.5. Used by the ISO notebook
// to auto-populate deducts in the cut calculator instead of forcing the fitter
// to look up tables manually on a clipboard.
//
// All values in mm. LR = Long Radius (1.5D), SR = Short Radius (1D).
// Sources: ASME B16.9 dimensional tables, common shop-fab quick-reference cards.
// These match the values monter routinely uses; for sub-standard or stub-end
// jobs the user can still type a custom value into the row.

class TakeoutEntry {
  final String name; // human label shown in deduct rows
  final int mm;
  const TakeoutEntry(this.name, this.mm);
}

class TakeoutCatalog {
  // Common DNs covered. DN15 / DN20 / DN25 / DN32 / DN40 / DN50 / DN65 /
  // DN80 / DN100 / DN150 / DN200 / DN250 / DN300 are 99% of fab work.
  static const dns = <int>[
    15, 20, 25, 32, 40, 50, 65, 80, 100, 150, 200, 250, 300,
  ];

  /// Convert DN (mm) to NPS (inches × 25.4) for naming.
  static String dnLabel(int dn) {
    // Map to common NPS callouts.
    const m = <int, String>{
      15: '1/2"', 20: '3/4"', 25: '1"', 32: '1¼"', 40: '1½"',
      50: '2"', 65: '2½"', 80: '3"', 100: '4"', 150: '6"',
      200: '8"', 250: '10"', 300: '12"',
    };
    return 'DN$dn (${m[dn] ?? '?'})';
  }

  // ── Elbow 90° LR (1.5D) — ASME B16.9 ──────────────────────────────────────
  static const elbow90LR = <int, int>{
    15: 38, 20: 38, 25: 38, 32: 48, 40: 57, 50: 76, 65: 95, 80: 114,
    100: 152, 150: 229, 200: 305, 250: 381, 300: 457,
  };

  // ── Elbow 90° SR (1D) — ASME B16.9 ────────────────────────────────────────
  static const elbow90SR = <int, int>{
    50: 51, 65: 64, 80: 76, 100: 102, 150: 152, 200: 203, 250: 254, 300: 305,
  };

  // ── Elbow 45° LR (0.625D approx) ──────────────────────────────────────────
  static const elbow45LR = <int, int>{
    15: 16, 20: 19, 25: 22, 32: 25, 40: 29, 50: 35, 65: 44, 80: 51,
    100: 64, 150: 95, 200: 127, 250: 159, 300: 190,
  };

  // ── Equal Tee (run/branch CTE, same for both per B16.9) ──────────────────
  static const tee = <int, int>{
    15: 25, 20: 29, 25: 38, 32: 48, 40: 57, 50: 64, 65: 76, 80: 86,
    100: 102, 150: 143, 200: 178, 250: 216, 300: 254,
  };

  // ── Concentric/Eccentric Reducer — end-to-end length (face-to-face) ──────
  // Listed by the *larger* DN (single value); use 76 mm for DN65×DN50, etc.
  static const reducer = <int, int>{
    25: 51, 32: 51, 40: 64, 50: 76, 65: 89, 80: 89, 100: 102,
    150: 140, 200: 152, 250: 178, 300: 203,
  };

  // ── Cap (butt-weld) — face length ─────────────────────────────────────────
  static const cap = <int, int>{
    15: 25, 20: 32, 25: 38, 32: 38, 40: 38, 50: 38, 65: 51, 80: 64,
    100: 76, 150: 102, 200: 127, 250: 165, 300: 178,
  };

  // ── Weld-neck flange — face thickness (Class 150, RF, B16.5) ─────────────
  static const flangeWN150 = <int, int>{
    15: 11, 20: 12, 25: 14, 32: 16, 40: 17, 50: 19, 65: 22, 80: 24,
    100: 24, 150: 25, 200: 28, 250: 30, 300: 32,
  };

  // ── Gate valve (Class 150 flanged, face-to-face per B16.10) ──────────────
  static const gateValve150 = <int, int>{
    50: 178, 65: 191, 80: 203, 100: 229, 150: 267, 200: 292,
    250: 330, 300: 356,
  };

  // ── Ball valve (Class 150 flanged) ────────────────────────────────────────
  static const ballValve150 = <int, int>{
    50: 178, 65: 191, 80: 203, 100: 229, 150: 267, 200: 292,
    250: 330, 300: 356,
  };

  // ── Check valve (swing, Class 150 flanged) ────────────────────────────────
  static const checkValve150 = <int, int>{
    50: 203, 65: 216, 80: 241, 100: 292, 150: 356, 200: 406,
    250: 495, 300: 533,
  };

  /// All entries available for a given DN. Used by the dialog to build a
  /// picker list. Falls back gracefully if an entry is missing for some DN
  /// (e.g. SR elbow < DN50).
  static List<TakeoutEntry> entriesForDn(int dn) {
    final list = <TakeoutEntry>[];
    void add(String label, Map<int, int> table) {
      final v = table[dn];
      if (v != null) list.add(TakeoutEntry(label, v));
    }
    add('Kolano 90° LR (CTE)', elbow90LR);
    add('Kolano 90° SR (CTE)', elbow90SR);
    add('Kolano 45° LR (CTE)', elbow45LR);
    add('Trójnik (CTE)', tee);
    add('Redukcja (FTF)', reducer);
    add('Zaślepka (face)', cap);
    add('Kołnierz WN cl.150 (face)', flangeWN150);
    add('Zawór zasuwowy cl.150 (FTF)', gateValve150);
    add('Zawór kulowy cl.150 (FTF)', ballValve150);
    add('Zawór zwrotny cl.150 (FTF)', checkValve150);
    return list;
  }
}
