import 'dart:math' as math;

/// Starting-point parameter estimator for autogenous orbital TIG welding of
/// thin-wall austenitic stainless tube (the food & pharma default joint).
///
/// IMPORTANT: these are STARTING values for setting up a coupon, not a
/// procedure. The qualified value always comes from the WPS and a passed
/// test weld. The screen states this in plain language.
///
/// Heuristics (consistent with weld-head manufacturer schedule guidance):
///  • Base (flat / 1G-down) current scales with wall thickness, with a small
///    diameter term because a larger mass sinks a little more heat.
///  • The orbit is split into 4 levels; current tapers as the arc climbs to
///    the overhead position so the pool does not drop out.
///  • Travel speed is set so heat input stays in the thin-wall band; it eases
///    off slightly as the wall gets thicker.
class OrbitalEstimate {
  final double circumferenceMm;
  /// Current per orbital level, level 1 = flat-down … level 4 = overhead.
  final List<double> levelCurrentA;
  final double travelSpeedMmMin;
  /// Seconds for one full revolution (≈ arc time of the weld).
  final double weldTimeSec;
  /// Suggested number of passes (1 for the thinnest tube).
  final int passes;
  /// Approximate heat input, kJ/mm, at the base current (η = 0.6 for TIG).
  final double heatInputKJmm;

  OrbitalEstimate({
    required this.circumferenceMm,
    required this.levelCurrentA,
    required this.travelSpeedMmMin,
    required this.weldTimeSec,
    required this.passes,
    required this.heatInputKJmm,
  });
}

/// [odMm] tube outside diameter, [wallMm] wall thickness, [arcVolts] the TIG
/// arc voltage used for the heat-input figure (typically 9–12 V).
OrbitalEstimate estimateOrbital({
  required double odMm,
  required double wallMm,
  double arcVolts = 10,
}) {
  final circ = math.pi * odMm;

  // Base flat current: ~48 A per mm of wall, plus a gentle OD term.
  final base = 48.0 * wallMm + 0.12 * odMm;

  // Four-level taper: flat / vertical-down / vertical-up / overhead.
  final levels = <double>[
    base,
    base * 0.92,
    base * 0.84,
    base * 0.78,
  ].map((a) => (a).roundToDouble()).toList();

  // Travel speed: 120 mm/min for the thinnest wall, easing to ~80 mm/min
  // around 3 mm wall.
  final travel = (130.0 - 18.0 * wallMm).clamp(70.0, 140.0);

  final weldTime = circ / travel * 60.0;

  // One pass up to ~2.5 mm wall; a fill pass above that.
  final passes = wallMm <= 2.5 ? 1 : 2;

  // Heat input kJ/mm = η · V · I / (v in mm/s) / 1000.
  final vMmS = travel / 60.0;
  final hi = 0.6 * arcVolts * base / vMmS / 1000.0;

  return OrbitalEstimate(
    circumferenceMm: circ,
    levelCurrentA: levels,
    travelSpeedMmMin: travel.toDouble(),
    weldTimeSec: weldTime,
    passes: passes,
    heatInputKJmm: hi,
  );
}
