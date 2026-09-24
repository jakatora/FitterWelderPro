/// Dimensional series an outside diameter belongs to.
enum OdSeries {
  /// ASME B36.10M / B36.19M only (same OD as the ASME B16.9 fitting bevel).
  asme,

  /// EN 10220 / ISO 4200 series 1 only — the European series for which the
  /// full range of fittings (EN 10253) is standardised.
  en1,

  /// Both ASME B36.10M and EN 10220 series 1 (21.3, 48.3, 60.3, 88.9 …).
  asmeAndEn1,

  /// EN 10220 series 2 (not all fittings standardised).
  en2,

  /// EN 10220 series 3 (special applications, very few fittings).
  en3,

  /// None of the above (e.g. hygienic / regional tube) — check the datasheet.
  other,
}

class NpsRow {
  final String nps;
  final int dn;
  final double odMm;

  /// Centreline bend radius of a ~1.5D (long radius) elbow for this size,
  /// i.e. dimension A of the 90° LR elbow: ASME B16.9-2018 Tab. 6.1-1 and
  /// EN 10253-2:2007 Tab. 11 (model 3D) agree on it for every ASME / EN
  /// series-1 row. For [OdSeries.en2] / [OdSeries.en3] / [OdSeries.other]
  /// rows the value is a legacy reference only (EN 10253-2 Tab. 11 confirms
  /// 57 → 72, 70 → 92, 101.6 → 133, 108 → 142.5 and 159 → 216; the rest are
  /// unverified) — check the elbow datasheet.
  final double rMm;
  final OdSeries series;

  const NpsRow({
    required this.nps,
    required this.dn,
    required this.odMm,
    required this.rMm,
    this.series = OdSeries.other,
  });

  /// `true` when ASME B16.9 / EN 10253 butt-weld elbows are made for this
  /// OD, so take-outs may be read from the B16.9 tables.
  bool get hasB169Elbows =>
      series == OdSeries.asme ||
      series == OdSeries.en1 ||
      series == OdSeries.asmeAndEn1;
}

/// NPS / DN / OD / elbow radius reference, sorted by OD (strictly increasing).
///
/// ODs: ASME B36.10M (= OD at bevel in ASME B16.9-2018) and EN 10220 series
/// 1 / 2 / 3. NPS 3 1/2 is DN90 (ASME B36.10M), not DN80.
const List<NpsRow> kNpsTable = [
  NpsRow(nps: '1/2"', dn: 15, odMm: 21.3, rMm: 38.1, series: OdSeries.asmeAndEn1),
  NpsRow(nps: '3/4"', dn: 20, odMm: 26.7, rMm: 38.1, series: OdSeries.asme),
  NpsRow(nps: '3/4"', dn: 20, odMm: 26.9, rMm: 38.1, series: OdSeries.en1),
  NpsRow(nps: '1"', dn: 25, odMm: 30.0, rMm: 33.5, series: OdSeries.en3),
  NpsRow(nps: '1"', dn: 25, odMm: 33.4, rMm: 38.1, series: OdSeries.asme),
  NpsRow(nps: '1"', dn: 25, odMm: 33.7, rMm: 38.1, series: OdSeries.en1),
  NpsRow(nps: '1 1/4"', dn: 32, odMm: 42.2, rMm: 48.0, series: OdSeries.asme),
  NpsRow(nps: '1 1/4"', dn: 32, odMm: 42.4, rMm: 48.0, series: OdSeries.en1),
  NpsRow(nps: '1 1/2"', dn: 40, odMm: 44.5, rMm: 51.0, series: OdSeries.en3),
  NpsRow(nps: '1 1/2"', dn: 40, odMm: 48.3, rMm: 57.15, series: OdSeries.asmeAndEn1),
  NpsRow(nps: '2"', dn: 50, odMm: 57.0, rMm: 72.0, series: OdSeries.en2),
  NpsRow(nps: '2"', dn: 50, odMm: 60.3, rMm: 76.0, series: OdSeries.asmeAndEn1),
  NpsRow(nps: '2"', dn: 50, odMm: 63.5, rMm: 82.5, series: OdSeries.en2),
  NpsRow(nps: '2 1/2"', dn: 65, odMm: 70.0, rMm: 92.0, series: OdSeries.en2),
  NpsRow(nps: '2 1/2"', dn: 65, odMm: 73.03, rMm: 95.25, series: OdSeries.asme),
  NpsRow(nps: '2 1/2"', dn: 65, odMm: 76.1, rMm: 95.25, series: OdSeries.en1),
  NpsRow(nps: '3"', dn: 80, odMm: 82.5, rMm: 107.5, series: OdSeries.en3),
  NpsRow(nps: '3"', dn: 80, odMm: 88.9, rMm: 114.3, series: OdSeries.asmeAndEn1),
  NpsRow(nps: '3 1/2"', dn: 90, odMm: 101.6, rMm: 133.35, series: OdSeries.asme),
  NpsRow(nps: '4"', dn: 100, odMm: 104.0, rMm: 150.0, series: OdSeries.other),
  NpsRow(nps: '4"', dn: 100, odMm: 108.0, rMm: 142.5, series: OdSeries.en3),
  NpsRow(nps: '4"', dn: 100, odMm: 114.3, rMm: 152.4, series: OdSeries.asmeAndEn1),
  NpsRow(nps: '5"', dn: 125, odMm: 139.7, rMm: 190.5, series: OdSeries.en1),
  NpsRow(nps: '5"', dn: 125, odMm: 141.3, rMm: 190.5, series: OdSeries.asme),
  NpsRow(nps: '6"', dn: 150, odMm: 154.0, rMm: 225.0, series: OdSeries.other),
  NpsRow(nps: '6"', dn: 150, odMm: 159.0, rMm: 216.0, series: OdSeries.en3),
  NpsRow(nps: '6"', dn: 150, odMm: 165.1, rMm: 230.0, series: OdSeries.other),
  NpsRow(nps: '6"', dn: 150, odMm: 168.3, rMm: 228.6, series: OdSeries.asmeAndEn1),
  NpsRow(nps: '8"', dn: 200, odMm: 204.0, rMm: 300.0, series: OdSeries.other),
  NpsRow(nps: '8"', dn: 200, odMm: 219.1, rMm: 304.8, series: OdSeries.asmeAndEn1),
  NpsRow(nps: '10"', dn: 250, odMm: 267.0, rMm: 378.0, series: OdSeries.other),
  NpsRow(nps: '10"', dn: 250, odMm: 273.0, rMm: 381.0, series: OdSeries.asmeAndEn1),
  NpsRow(nps: '12"', dn: 300, odMm: 318.0, rMm: 455.0, series: OdSeries.other),
  // ASME lists 323.8, EN 10220 323.9 — one row, 0.1 mm apart.
  NpsRow(nps: '12"', dn: 300, odMm: 323.9, rMm: 457.2, series: OdSeries.asmeAndEn1),
  NpsRow(nps: '14"', dn: 350, odMm: 355.6, rMm: 533.4, series: OdSeries.asmeAndEn1),
  NpsRow(nps: '14"', dn: 350, odMm: 368.0, rMm: 533.5, series: OdSeries.other),
  NpsRow(nps: '16"', dn: 400, odMm: 406.4, rMm: 609.6, series: OdSeries.asmeAndEn1),
  NpsRow(nps: '16"', dn: 400, odMm: 419.0, rMm: 609.5, series: OdSeries.other),
  NpsRow(nps: '18"', dn: 450, odMm: 457.2, rMm: 685.8, series: OdSeries.asmeAndEn1),
  NpsRow(nps: '20"', dn: 500, odMm: 508.0, rMm: 762.0, series: OdSeries.asmeAndEn1),
  NpsRow(nps: '22"', dn: 550, odMm: 558.8, rMm: 838.2, series: OdSeries.asme),
  NpsRow(nps: '24"', dn: 600, odMm: 609.6, rMm: 914.4, series: OdSeries.asmeAndEn1),
  NpsRow(nps: '26"', dn: 650, odMm: 660.4, rMm: 990.6, series: OdSeries.asme),
  NpsRow(nps: '28"', dn: 700, odMm: 711.2, rMm: 1066.8, series: OdSeries.asmeAndEn1),
  NpsRow(nps: '30"', dn: 750, odMm: 762.0, rMm: 1143.0, series: OdSeries.asme),
  NpsRow(nps: '32"', dn: 800, odMm: 812.8, rMm: 1219.2, series: OdSeries.asmeAndEn1),
  NpsRow(nps: '34"', dn: 850, odMm: 863.6, rMm: 1295.4, series: OdSeries.asme),
  NpsRow(nps: '36"', dn: 900, odMm: 914.4, rMm: 1371.6, series: OdSeries.asmeAndEn1),
  NpsRow(nps: '38"', dn: 950, odMm: 965.2, rMm: 1447.8, series: OdSeries.asme),
  NpsRow(nps: '40"', dn: 1000, odMm: 1016.0, rMm: 1524.0, series: OdSeries.asmeAndEn1),
];

/// Row of a pipe OD for which ASME B16.9 / EN 10253 elbows exist, matched
/// within ±0.5 mm (so ASME 323.8 finds the 323.9 row, 610 finds 609.6).
///
/// Returns `null` for ODs outside ASME B36.10M and EN 10220 series 1
/// (e.g. 104 or 108 mm tube): B16.9 has no elbow for them, and a "nearest
/// size" would silently hand the fitter another pipe's take-out.
NpsRow? b169RowForOd(double odMm, {double toleranceMm = 0.5}) {
  if (!odMm.isFinite || odMm <= 0) return null;
  NpsRow? best;
  var bestDiff = double.infinity;
  for (final r in kNpsTable) {
    if (!r.hasB169Elbows) continue;
    final d = (r.odMm - odMm).abs();
    if (d <= toleranceMm && d < bestDiff) {
      best = r;
      bestDiff = d;
    }
  }
  return best;
}
