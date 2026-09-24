// Take-out (CTE = centre-to-end) reference values for butt-weld and flanged
// piping components. Used by the ISO notebook and the scan-to-project planner
// to auto-populate deducts in the cut calculator instead of forcing the fitter
// to look up tables manually on a clipboard.
//
// All values in mm, taken from the METRIC columns of the standards:
//   ASME B16.9-2018  — elbows (Tab. 6.1-1 LR, 6.1-4 SR, 6.1-6 3D), tees
//                      (6.1-7), caps (6.1-10), reducers (6.1-11);
//   ASME B16.5       — Class 150 weld-neck flanges (C = disc thickness,
//                      Y = length through hub, both incl. the 1.6 mm RF);
//   ASME B16.10      — Class 150 valve face-to-face.
// For sub-standard or stub-end jobs the user can still type a custom value
// into the row. Pinned by test/takeout_catalog_test.dart.

import 'dart:math' as math;

import '../data/elbow_takeouts.dart';

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

  // ── Elbow 90° LR — ASME B16.9 Tab. 6.1-1, A ───────────────────────────────
  // NPS 1/2, 3/4 and 1 are all 38 mm (1.50 in.); from NPS 1-1/4 A = 1.5 × NPS.
  static const elbow90LR = <int, int>{
    15: 38, 20: 38, 25: 38, 32: 48, 40: 57, 50: 76, 65: 95, 80: 114,
    100: 152, 150: 229, 200: 305, 250: 381, 300: 457,
  };

  // ── Elbow 90° SR — ASME B16.9 Tab. 6.1-4, A = 1.0 × NPS ──────────────────
  // Short radius exists from NPS 1 up only: no DN15 / DN20 entry on purpose.
  static const elbow90SR = <int, int>{
    25: 25, 32: 32, 40: 38, 50: 51, 65: 64, 80: 76, 100: 102, 150: 152,
    200: 203, 250: 254, 300: 305,
  };

  // ── Elbow 45° LR — ASME B16.9 Tab. 6.1-1, B ───────────────────────────────
  // (There is no 45° short radius elbow in B16.9.)
  static const elbow45LR = <int, int>{
    15: 16, 20: 19, 25: 22, 32: 25, 40: 29, 50: 35, 65: 44, 80: 51,
    100: 64, 150: 95, 200: 127, 250: 159, 300: 190,
  };

  // ── Equal Tee — ASME B16.9 Tab. 6.1-7, run C = outlet M ──────────────────
  // DN100: C = 4.12 in. = 105 mm (was 102 until the 2026-09 audit).
  static const tee = <int, int>{
    15: 25, 20: 29, 25: 38, 32: 48, 40: 57, 50: 64, 65: 76, 80: 86,
    100: 105, 150: 143, 200: 178, 250: 216, 300: 254,
  };

  // ── Concentric/Eccentric Reducer — ASME B16.9 Tab. 6.1-11, end-to-end H ──
  // Listed by the *larger* DN (single value per large end; the smallest
  // large end in B16.9 is NPS 3/4 × 1/2).
  static const reducer = <int, int>{
    20: 38, 25: 51, 32: 51, 40: 64, 50: 76, 65: 89, 80: 89, 100: 102,
    150: 140, 200: 152, 250: 178, 300: 203,
  };

  // ── Cap — ASME B16.9 Tab. 6.1-10, length E ────────────────────────────────
  // E applies up to the tabulated limiting wall (NPS 4: 8.64 mm, i.e. STD and
  // XS). Heavier walls use the longer E1 (NPS 2: 44, 2-1/2: 51, 3: 64,
  // 4: 76, 6: 102, 8: 127, 10: 152, 12: 178). Until the 2026-09 audit this
  // table mixed E1 into the standard-wall column (DN100 read 76 instead of 64).
  static const cap = <int, int>{
    15: 25, 20: 25, 25: 38, 32: 38, 40: 38, 50: 38, 65: 38, 80: 51,
    100: 64, 150: 89, 200: 102, 250: 127, 300: 152,
  };

  // ── Class 150 RF flange — ASME B16.5 column C, DISC thickness ────────────
  // Right for slip-on / socket / threaded flanges (the pipe passes through
  // the disc). NOT the take-out of a weld neck — see [flangeWN150Y].
  // (The name is historical; `scan_to_project` still reads it.)
  static const flangeWN150 = <int, int>{
    15: 11, 20: 12, 25: 14, 32: 16, 40: 17, 50: 19, 65: 22, 80: 24,
    100: 24, 150: 25, 200: 28, 250: 30, 300: 32,
  };

  // ── Class 150 RF weld-neck flange — ASME B16.5 column Y ──────────────────
  // Length through hub, raised face included — the pipe is butt-welded to
  // the END of the hub, so this is what a WN flange takes out of the run.
  // NPS 8 and NPS 10 are both 4.00 in. = 101.6 mm.
  static const flangeWN150Y = <int, int>{
    15: 48, 20: 52, 25: 56, 32: 57, 40: 62, 50: 64, 65: 70, 80: 70,
    100: 76, 150: 89, 200: 102, 250: 102, 300: 114,
  };

  // ── Gate valve — ASME B16.10 Class 150 RF, solid wedge / double disc ─────
  static const gateValve150 = <int, int>{
    50: 178, 65: 191, 80: 203, 100: 229, 150: 267, 200: 292,
    250: 330, 300: 356,
  };

  // ── Ball valve — ASME B16.10 Class 150 RF, SHORT pattern ─────────────────
  // (Long pattern from NPS 6 is longer: 394 / 457 / 533 / 610.)
  static const ballValve150 = <int, int>{
    50: 178, 65: 191, 80: 203, 100: 229, 150: 267, 200: 292,
    250: 330, 300: 356,
  };

  // ── Swing check valve — ASME B16.10 Class 150 RF ─────────────────────────
  // Column "globe / lift check / swing check", with the B16.10 footnote that
  // swing check NPS 6 is 356 (globe/lift check NPS 6: 406). Until the
  // 2026-09 audit DN200–DN300 were shifted one size down (406/495/533).
  static const checkValve150 = <int, int>{
    50: 203, 65: 216, 80: 241, 100: 292, 150: 356, 200: 495,
    250: 622, 300: 698,
  };

  // ── Globe / lift check valve — ASME B16.10 Class 150 RF ──────────────────
  static const globeValve150 = <int, int>{
    50: 203, 65: 216, 80: 241, 100: 292, 150: 406, 200: 495,
    250: 622, 300: 698,
  };

  /// All entries available for a given DN. Used by the dialog to build a
  /// picker list. Falls back gracefully if an entry is missing for some DN
  /// (e.g. SR elbow below DN25, valves below DN50).
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
    add('Kołnierz WN cl.150 (Y, przez szyjkę)', flangeWN150Y);
    add('Kołnierz SO cl.150 (tarcza C)', flangeWN150);
    add('Zawór zasuwowy cl.150 (FTF)', gateValve150);
    add('Zawór kulowy cl.150 (FTF)', ballValve150);
    add('Zawór zwrotny cl.150 (FTF)', checkValve150);
    add('Zawór grzybkowy cl.150 (FTF)', globeValve150);
    return list;
  }
}

/// Elbow radius family in ASME B16.9-2018.
enum ElbowRadiusType {
  /// Short radius, R = 1.0 × NPS — Table 6.1-4 (NPS 1 and up only).
  short1D,

  /// Long radius, R = 1.5 × NPS (38 mm for NPS 1/2–1) — Table 6.1-1.
  long15D,

  /// 3D radius, R = 3 × NPS — Table 6.1-6 (NPS 3/4 and up).
  long3D,
}

/// Where a take-out value came from — shown to the fitter next to the number.
enum TakeoutBasis {
  /// Tabulated A of the 90° elbow.
  tableA90,

  /// Tabulated B of the 45° elbow.
  tableB45,

  /// Segment of a 90° elbow, B16.9 §6.2.4: Bs = A × tan(θ/2).
  segment,
}

class ElbowTakeoutResult {
  /// Centre-to-end take-out at the requested angle, mm.
  final double mm;

  /// Tabulated A of the 90° elbow of the same family (= its bend radius), mm.
  final int a90Mm;
  final TakeoutBasis basis;
  final ElbowTakeout row;
  final ElbowRadiusType type;
  const ElbowTakeoutResult({
    required this.mm,
    required this.a90Mm,
    required this.basis,
    required this.row,
    required this.type,
  });
}

/// Centre-to-end take-out of a B16.9 butt-weld elbow of nominal size [dn],
/// radius family [type], bent through [angleDeg] (0 < θ ≤ 90).
///
///  • θ = 90° → tabulated A,
///  • θ = 45° → tabulated B where B16.9 lists a 45° elbow (LR, 3D),
///  • any other θ (and SR 45°, which B16.9 does not make) → segment of the
///    90° elbow per B16.9 §6.2.4: Bs = A × tan(θ/2).
///
/// Returns `null` — never a guess — when the DN is not in the table (no
/// "nearest DN" substitution), when the family does not exist at that size
/// (SR below NPS 1, 3D at NPS 1/2) or when θ is outside (0°, 90°].
ElbowTakeoutResult? b169ElbowTakeout({
  required int dn,
  required ElbowRadiusType type,
  required double angleDeg,
}) {
  if (!angleDeg.isFinite || angleDeg <= 0 || angleDeg > 90) return null;
  final row = elbowTakeoutForDn(dn);
  if (row == null) return null;
  final int? a90;
  final int? b45;
  switch (type) {
    case ElbowRadiusType.short1D:
      a90 = row.sr90;
      b45 = null; // B16.9 has no 45° short radius elbow
    case ElbowRadiusType.long15D:
      a90 = row.lr90;
      b45 = row.lr45;
    case ElbowRadiusType.long3D:
      a90 = row.r3d90;
      b45 = row.r3d45;
  }
  if (a90 == null) return null;
  if (angleDeg == 90) {
    return ElbowTakeoutResult(
        mm: a90.toDouble(),
        a90Mm: a90,
        basis: TakeoutBasis.tableA90,
        row: row,
        type: type);
  }
  if (angleDeg == 45 && b45 != null) {
    return ElbowTakeoutResult(
        mm: b45.toDouble(),
        a90Mm: a90,
        basis: TakeoutBasis.tableB45,
        row: row,
        type: type);
  }
  return ElbowTakeoutResult(
      mm: a90 * math.tan(angleDeg * math.pi / 360.0),
      a90Mm: a90,
      basis: TakeoutBasis.segment,
      row: row,
      type: type);
}
