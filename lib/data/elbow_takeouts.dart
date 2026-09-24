/// Centre-to-end (a.k.a. take-out / face-to-centre) dimensions of butt-weld
/// elbows per ASME B16.9-2018, in millimetres. The numbers are the standard's
/// OWN metric columns (they are not re-rounded inch conversions — e.g. NPS 5
/// LR 90° is 190 mm in B16.9, not round(7.50 × 25.4) = 191).
///
///  lr90  — Table 6.1-1, 90° long radius elbow, dimension A. A is also the
///          bend radius R. From NPS 1-1/4 up A = 1.5 × NPS; NPS 1/2, 3/4 and
///          1 are all 38 mm (1.50 in.) — NOT 1.5 × NPS.
///  lr45  — Table 6.1-1, 45° long radius elbow, dimension B.
///  sr90  — Table 6.1-4, 90° short radius elbow, A = 1.0 × NPS. B16.9 lists
///          short radius elbows only from NPS 1 up, so DN15 and DN20 are
///          `null` — there is no standard value to show.
///  r3d90 / r3d45 — Table 6.1-6, 3D radius elbows, A and B (from NPS 3/4 up).
///
/// B16.9 has NO 45° short radius elbow. Any angle that is not tabulated is a
/// segment of a 90° elbow, for which B16.9 §6.2.4 gives
/// Bs = A × tan(θ/2) — see `b169ElbowTakeout` in services/takeout_catalog.dart.
///
/// A fitter on site checks against this instead of pulling a paper catalogue
/// in dust or rain.
///
/// NOTE (audit fix 2026-07-07): the lr45 column for DN90–DN600 previously used
/// lr90/2 (ratio 0.5) which OVERSTATED the 45° takeout by ~20% — a 45° elbow's
/// centre-to-end is tan(22.5°)/tan(45°) = 0.414 of the 90°, not 0.5. Corrected
/// to the standard B16.9 values (matching services/takeout_catalog.dart), and
/// pinned by test/elbow_takeouts_test.dart so it cannot regress.
///
/// NOTE (audit fix 2026-09-24): DN15/DN20 used to show sr90 = 25 mm — a size
/// B16.9 does not make. Now `null`; 3D radius columns added from Table 6.1-6.
const List<ElbowTakeout> kElbowTakeouts = [
  ElbowTakeout(dn: 15,  nps: '1/2',   npsIn: 0.5,  lr90: 38,  sr90: null, lr45: 16,  r3d90: null, r3d45: null),
  ElbowTakeout(dn: 20,  nps: '3/4',   npsIn: 0.75, lr90: 38,  sr90: null, lr45: 19,  r3d90: 57,   r3d45: 24),
  ElbowTakeout(dn: 25,  nps: '1',     npsIn: 1,    lr90: 38,  sr90: 25,   lr45: 22,  r3d90: 76,   r3d45: 31),
  ElbowTakeout(dn: 32,  nps: '1 1/4', npsIn: 1.25, lr90: 48,  sr90: 32,   lr45: 25,  r3d90: 95,   r3d45: 39),
  ElbowTakeout(dn: 40,  nps: '1 1/2', npsIn: 1.5,  lr90: 57,  sr90: 38,   lr45: 29,  r3d90: 114,  r3d45: 47),
  ElbowTakeout(dn: 50,  nps: '2',     npsIn: 2,    lr90: 76,  sr90: 51,   lr45: 35,  r3d90: 152,  r3d45: 63),
  ElbowTakeout(dn: 65,  nps: '2 1/2', npsIn: 2.5,  lr90: 95,  sr90: 64,   lr45: 44,  r3d90: 190,  r3d45: 79),
  ElbowTakeout(dn: 80,  nps: '3',     npsIn: 3,    lr90: 114, sr90: 76,   lr45: 51,  r3d90: 229,  r3d45: 95),
  ElbowTakeout(dn: 90,  nps: '3 1/2', npsIn: 3.5,  lr90: 133, sr90: 89,   lr45: 57,  r3d90: 267,  r3d45: 111),
  ElbowTakeout(dn: 100, nps: '4',     npsIn: 4,    lr90: 152, sr90: 102,  lr45: 64,  r3d90: 305,  r3d45: 127),
  ElbowTakeout(dn: 125, nps: '5',     npsIn: 5,    lr90: 190, sr90: 127,  lr45: 79,  r3d90: 381,  r3d45: 157),
  ElbowTakeout(dn: 150, nps: '6',     npsIn: 6,    lr90: 229, sr90: 152,  lr45: 95,  r3d90: 457,  r3d45: 189),
  ElbowTakeout(dn: 200, nps: '8',     npsIn: 8,    lr90: 305, sr90: 203,  lr45: 127, r3d90: 610,  r3d45: 252),
  ElbowTakeout(dn: 250, nps: '10',    npsIn: 10,   lr90: 381, sr90: 254,  lr45: 159, r3d90: 762,  r3d45: 316),
  ElbowTakeout(dn: 300, nps: '12',    npsIn: 12,   lr90: 457, sr90: 305,  lr45: 190, r3d90: 914,  r3d45: 378),
  ElbowTakeout(dn: 350, nps: '14',    npsIn: 14,   lr90: 533, sr90: 356,  lr45: 222, r3d90: 1067, r3d45: 441),
  ElbowTakeout(dn: 400, nps: '16',    npsIn: 16,   lr90: 610, sr90: 406,  lr45: 254, r3d90: 1219, r3d45: 505),
  ElbowTakeout(dn: 450, nps: '18',    npsIn: 18,   lr90: 686, sr90: 457,  lr45: 286, r3d90: 1372, r3d45: 568),
  ElbowTakeout(dn: 500, nps: '20',    npsIn: 20,   lr90: 762, sr90: 508,  lr45: 318, r3d90: 1524, r3d45: 632),
  ElbowTakeout(dn: 600, nps: '24',    npsIn: 24,   lr90: 914, sr90: 610,  lr45: 381, r3d90: 1829, r3d45: 757),
];

class ElbowTakeout {
  final int dn;
  final String nps;

  /// Nominal pipe size in inches (e.g. 1.5 for NPS 1-1/2).
  final double npsIn;

  /// 90° long radius, centre-to-end A (= bend radius), B16.9 Table 6.1-1.
  final int lr90;

  /// 90° short radius, centre-to-end A, B16.9 Table 6.1-4. `null` below
  /// NPS 1 — B16.9 has no short radius elbow there.
  final int? sr90;

  /// 45° long radius, centre-to-end B, B16.9 Table 6.1-1.
  final int lr45;

  /// 90° 3D radius, centre-to-end A, B16.9 Table 6.1-6 (`null` for NPS 1/2).
  final int? r3d90;

  /// 45° 3D radius, centre-to-end B, B16.9 Table 6.1-6 (`null` for NPS 1/2).
  final int? r3d45;

  const ElbowTakeout({
    required this.dn,
    required this.nps,
    required this.npsIn,
    required this.lr90,
    required this.sr90,
    required this.lr45,
    required this.r3d90,
    required this.r3d45,
  });
}

/// Exact row for [dn], or `null` when B16.9 elbows of that size are not in
/// the table. Use this (not [closestByDn]) wherever a number is computed —
/// a "nearest" row silently turns DN110 into DN100.
ElbowTakeout? elbowTakeoutForDn(int dn) {
  for (final e in kElbowTakeouts) {
    if (e.dn == dn) return e;
  }
  return null;
}

/// Returns the closest takeout entry by DN. Useful when a fitter only knows
/// the nominal diameter — never returns null because the table covers DN15–DN600.
ElbowTakeout closestByDn(int dn) {
  ElbowTakeout best = kElbowTakeouts.first;
  int bestDiff = (kElbowTakeouts.first.dn - dn).abs();
  for (final e in kElbowTakeouts) {
    final d = (e.dn - dn).abs();
    if (d < bestDiff) {
      bestDiff = d;
      best = e;
    }
  }
  return best;
}
