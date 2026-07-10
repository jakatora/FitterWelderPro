/// Centre-to-face (a.k.a. takeout / face-to-centre) dimensions for butt-weld
/// pipe elbows per ASME B16.9 / B16.28, in millimetres.
///
///  LR 90° = 1.5 × NPS (long radius)  — centre-to-end
///  SR 90° = 1.0 × NPS (short radius, B16.28)
///  LR 45° = per ASME B16.9 45° LR table (centre-to-end ≈ 1.5·OD·tan 22.5°)
///  SR 45° is identical to LR for many DN — provided for completeness.
///
/// All values are dimensional standard values. A fitter on site checks against
/// this instead of pulling a paper catalogue in dust or rain.
///
/// NOTE (audit fix 2026-07-07): the lr45 column for DN90–DN600 previously used
/// lr90/2 (ratio 0.5) which OVERSTATED the 45° takeout by ~20% — a 45° elbow's
/// centre-to-end is tan(22.5°)/tan(45°) = 0.414 of the 90°, not 0.5. Corrected
/// to the standard B16.9 values (matching services/takeout_catalog.dart), and
/// pinned by test/elbow_takeouts_test.dart so it cannot regress.
const List<ElbowTakeout> kElbowTakeouts = [
  ElbowTakeout(dn: 15,  nps: '1/2',   lr90: 38,  sr90: 25,  lr45: 16),
  ElbowTakeout(dn: 20,  nps: '3/4',   lr90: 38,  sr90: 25,  lr45: 19),
  ElbowTakeout(dn: 25,  nps: '1',     lr90: 38,  sr90: 25,  lr45: 22),
  ElbowTakeout(dn: 32,  nps: '1 1/4', lr90: 48,  sr90: 32,  lr45: 25),
  ElbowTakeout(dn: 40,  nps: '1 1/2', lr90: 57,  sr90: 38,  lr45: 29),
  ElbowTakeout(dn: 50,  nps: '2',     lr90: 76,  sr90: 51,  lr45: 35),
  ElbowTakeout(dn: 65,  nps: '2 1/2', lr90: 95,  sr90: 64,  lr45: 44),
  ElbowTakeout(dn: 80,  nps: '3',     lr90: 114, sr90: 76,  lr45: 51),
  ElbowTakeout(dn: 90,  nps: '3 1/2', lr90: 133, sr90: 89,  lr45: 57),
  ElbowTakeout(dn: 100, nps: '4',     lr90: 152, sr90: 102, lr45: 64),
  ElbowTakeout(dn: 125, nps: '5',     lr90: 190, sr90: 127, lr45: 79),
  ElbowTakeout(dn: 150, nps: '6',     lr90: 229, sr90: 152, lr45: 95),
  ElbowTakeout(dn: 200, nps: '8',     lr90: 305, sr90: 203, lr45: 127),
  ElbowTakeout(dn: 250, nps: '10',    lr90: 381, sr90: 254, lr45: 159),
  ElbowTakeout(dn: 300, nps: '12',    lr90: 457, sr90: 305, lr45: 190),
  ElbowTakeout(dn: 350, nps: '14',    lr90: 533, sr90: 356, lr45: 222),
  ElbowTakeout(dn: 400, nps: '16',    lr90: 610, sr90: 406, lr45: 254),
  ElbowTakeout(dn: 450, nps: '18',    lr90: 686, sr90: 457, lr45: 286),
  ElbowTakeout(dn: 500, nps: '20',    lr90: 762, sr90: 508, lr45: 318),
  ElbowTakeout(dn: 600, nps: '24',    lr90: 914, sr90: 610, lr45: 381),
];

class ElbowTakeout {
  final int dn;
  final String nps;
  final int lr90;
  final int sr90;
  final int lr45;
  const ElbowTakeout({
    required this.dn,
    required this.nps,
    required this.lr90,
    required this.sr90,
    required this.lr45,
  });
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
