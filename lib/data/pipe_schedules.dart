// Pipe wall thickness per ASME B36.10M (carbon/alloy) and B36.19M (stainless),
// in millimetres. Only the schedules a typical fitter actually meets on site
// are listed: STD, XS, XXS, Sch 10S, 40, 80, 160.
//
// A fitter on a refinery reads "DN50 Sch80" from the ISO and needs the wall
// thickness on the spot to set bevel depth, choose a grinder disc and pick
// the AMP range. The table is offline so it works in a cellar / vessel.

class PipeRow {
  final int dn;        // nominal diameter
  final String nps;    // NPS marking
  final double od;     // outside diameter, mm
  /// Wall thicknesses keyed by schedule. Null means "not normally produced
  /// in that size" — we hide the cell.
  final Map<String, double?> walls;
  const PipeRow({
    required this.dn,
    required this.nps,
    required this.od,
    required this.walls,
  });
}

/// Schedules shown in column order.
const List<String> kSchedules = [
  '10S', 'STD', '40', '80', '160', 'XS', 'XXS',
];

const List<PipeRow> kPipeWalls = [
  PipeRow(dn: 15, nps: '1/2', od: 21.3, walls: {
    '10S': 2.11, 'STD': 2.77, '40': 2.77, '80': 3.73, '160': 4.78,
    'XS': 3.73, 'XXS': 7.47,
  }),
  PipeRow(dn: 20, nps: '3/4', od: 26.7, walls: {
    '10S': 2.11, 'STD': 2.87, '40': 2.87, '80': 3.91, '160': 5.56,
    'XS': 3.91, 'XXS': 7.82,
  }),
  PipeRow(dn: 25, nps: '1', od: 33.4, walls: {
    '10S': 2.77, 'STD': 3.38, '40': 3.38, '80': 4.55, '160': 6.35,
    'XS': 4.55, 'XXS': 9.09,
  }),
  PipeRow(dn: 32, nps: '1 1/4', od: 42.2, walls: {
    '10S': 2.77, 'STD': 3.56, '40': 3.56, '80': 4.85, '160': 6.35,
    'XS': 4.85, 'XXS': 9.70,
  }),
  PipeRow(dn: 40, nps: '1 1/2', od: 48.3, walls: {
    '10S': 2.77, 'STD': 3.68, '40': 3.68, '80': 5.08, '160': 7.14,
    'XS': 5.08, 'XXS': 10.15,
  }),
  PipeRow(dn: 50, nps: '2', od: 60.3, walls: {
    '10S': 2.77, 'STD': 3.91, '40': 3.91, '80': 5.54, '160': 8.74,
    'XS': 5.54, 'XXS': 11.07,
  }),
  PipeRow(dn: 65, nps: '2 1/2', od: 73.0, walls: {
    '10S': 3.05, 'STD': 5.16, '40': 5.16, '80': 7.01, '160': 9.53,
    'XS': 7.01, 'XXS': 14.02,
  }),
  PipeRow(dn: 80, nps: '3', od: 88.9, walls: {
    '10S': 3.05, 'STD': 5.49, '40': 5.49, '80': 7.62, '160': 11.13,
    'XS': 7.62, 'XXS': 15.24,
  }),
  PipeRow(dn: 100, nps: '4', od: 114.3, walls: {
    '10S': 3.05, 'STD': 6.02, '40': 6.02, '80': 8.56, '160': 13.49,
    'XS': 8.56, 'XXS': 17.12,
  }),
  PipeRow(dn: 125, nps: '5', od: 141.3, walls: {
    '10S': 3.40, 'STD': 6.55, '40': 6.55, '80': 9.53, '160': 15.88,
    'XS': 9.53, 'XXS': 19.05,
  }),
  PipeRow(dn: 150, nps: '6', od: 168.3, walls: {
    '10S': 3.40, 'STD': 7.11, '40': 7.11, '80': 10.97, '160': 18.26,
    'XS': 10.97, 'XXS': 21.95,
  }),
  PipeRow(dn: 200, nps: '8', od: 219.1, walls: {
    '10S': 3.76, 'STD': 8.18, '40': 8.18, '80': 12.70, '160': 23.01,
    'XS': 12.70, 'XXS': 22.23,
  }),
  PipeRow(dn: 250, nps: '10', od: 273.0, walls: {
    '10S': 4.19, 'STD': 9.27, '40': 9.27, '80': 15.09, '160': 28.58,
    'XS': 12.70, 'XXS': 25.40,
  }),
  PipeRow(dn: 300, nps: '12', od: 323.8, walls: {
    '10S': 4.57, 'STD': 9.53, '40': 10.31, '80': 17.48, '160': 33.32,
    'XS': 12.70, 'XXS': 25.40,
  }),
  PipeRow(dn: 350, nps: '14', od: 355.6, walls: {
    '10S': 4.78, 'STD': 9.53, '40': 11.13, '80': 19.05, '160': 35.71,
    'XS': 12.70, 'XXS': null,
  }),
  PipeRow(dn: 400, nps: '16', od: 406.4, walls: {
    '10S': 4.78, 'STD': 9.53, '40': 12.70, '80': 21.44, '160': 40.49,
    'XS': 12.70, 'XXS': null,
  }),
  PipeRow(dn: 450, nps: '18', od: 457.0, walls: {
    '10S': 4.78, 'STD': 9.53, '40': 14.27, '80': 23.83, '160': 45.24,
    'XS': 12.70, 'XXS': null,
  }),
  PipeRow(dn: 500, nps: '20', od: 508.0, walls: {
    '10S': 5.54, 'STD': 9.53, '40': 15.09, '80': 26.19, '160': 50.01,
    'XS': 12.70, 'XXS': null,
  }),
  PipeRow(dn: 600, nps: '24', od: 610.0, walls: {
    '10S': 6.35, 'STD': 9.53, '40': 17.48, '80': 30.96, '160': 59.54,
    'XS': 12.70, 'XXS': null,
  }),
];

/// Density (kg/dm³) for the mass calculation in the lookup screen.
/// Carbon/alloy steel ≈ 7.85, austenitic stainless ≈ 7.93.
const double kDensityCarbon = 7.85;
const double kDensityStainless = 7.93;

/// Returns mass per metre for [row] at [schedule], or null if not produced.
double? massPerMeter(PipeRow row, String schedule, {bool stainless = false}) {
  final w = row.walls[schedule];
  if (w == null) return null;
  // Mass (kg/m) = π × (OD − wall) × wall × ρ × 10⁻³
  final density = stainless ? kDensityStainless : kDensityCarbon;
  return 3.141592653589793 * (row.od - w) * w * density * 1e-3;
}
