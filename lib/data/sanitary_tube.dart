// Sanitary / hygienic TUBE dimensions for food, dairy and pharmaceutical
// piping. This is deliberately separate from pipe schedules (B36.10): in
// hygienic work the line is "tube", sized by OUTSIDE DIAMETER, not NPS/DN,
// and the wall is thin and (within a standard) constant.
//
// Two systems cover almost all of Europe-based food & pharma sites:
//   • ASME BPE / ASTM A270 — imperial OD tube (the pharma default)
//   • DIN 11850 — metric dairy tube (the food-industry default in the EU)
//
// All values in millimetres. Imperial originals kept in the label.

class SanitaryTube {
  /// Human label, e.g. '1"' or 'DN40'.
  final String size;
  /// Outside diameter, mm.
  final double od;
  /// Nominal wall thickness, mm.
  final double wall;
  /// Imperial wall callout where relevant (BWG / inch), else ''.
  final String wallNote;
  const SanitaryTube({
    required this.size,
    required this.od,
    required this.wall,
    this.wallNote = '',
  });

  double get id => od - 2 * wall;

  /// Mass per metre, kg/m, austenitic stainless (ρ ≈ 7.93 kg/dm³).
  double get massPerMeter =>
      3.141592653589793 * (od - wall) * wall * 7.93 * 1e-3;

  /// Internal volume, litres per metre — drives the purge-gas calculation.
  double get litresPerMeter => 3.141592653589793 * id * id / 4.0 * 1e-3;
}

/// ASME BPE / ASTM A270 — imperial OD tube, the pharmaceutical standard.
/// Wall: 0.065" up to 3", 0.083" at 4", 0.109" at 6" (BPE nominal).
const List<SanitaryTube> kBpeTube = [
  SanitaryTube(size: '1/4"',  od: 6.35,   wall: 0.89, wallNote: '0.035"'),
  SanitaryTube(size: '3/8"',  od: 9.53,   wall: 0.89, wallNote: '0.035"'),
  SanitaryTube(size: '1/2"',  od: 12.70,  wall: 1.65, wallNote: '0.065"'),
  SanitaryTube(size: '3/4"',  od: 19.05,  wall: 1.65, wallNote: '0.065"'),
  SanitaryTube(size: '1"',    od: 25.40,  wall: 1.65, wallNote: '0.065"'),
  SanitaryTube(size: '1 1/2"',od: 38.10,  wall: 1.65, wallNote: '0.065"'),
  SanitaryTube(size: '2"',    od: 50.80,  wall: 1.65, wallNote: '0.065"'),
  SanitaryTube(size: '2 1/2"',od: 63.50,  wall: 1.65, wallNote: '0.065"'),
  SanitaryTube(size: '3"',    od: 76.20,  wall: 1.65, wallNote: '0.065"'),
  SanitaryTube(size: '4"',    od: 101.60, wall: 2.11, wallNote: '0.083"'),
  SanitaryTube(size: '6"',    od: 152.40, wall: 2.77, wallNote: '0.109"'),
];

/// DIN 11850 series 2 — metric dairy tube, the EU food-industry default.
const List<SanitaryTube> kDin11850Tube = [
  SanitaryTube(size: 'DN10',  od: 13.0,  wall: 1.5),
  SanitaryTube(size: 'DN15',  od: 19.0,  wall: 1.5),
  SanitaryTube(size: 'DN20',  od: 23.0,  wall: 1.5),
  SanitaryTube(size: 'DN25',  od: 29.0,  wall: 1.5),
  SanitaryTube(size: 'DN32',  od: 35.0,  wall: 1.5),
  SanitaryTube(size: 'DN40',  od: 41.0,  wall: 1.5),
  SanitaryTube(size: 'DN50',  od: 53.0,  wall: 1.5),
  SanitaryTube(size: 'DN65',  od: 70.0,  wall: 2.0),
  SanitaryTube(size: 'DN80',  od: 85.0,  wall: 2.0),
  SanitaryTube(size: 'DN100', od: 104.0, wall: 2.0),
  SanitaryTube(size: 'DN125', od: 129.0, wall: 2.0),
  SanitaryTube(size: 'DN150', od: 154.0, wall: 2.0),
];
