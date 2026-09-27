import 'dart:math' as math;

// Pure purge (backing-gas) helpers for Pipes → Gases / AMP.
//
// O₂ model: the same exponential dilution (perfect mixing) as the O₂ tab in
// Welder tools: C(t) = C₀·e^(−Q·t/V). With N = Q·t/V volume changes this is
// C = C₀·e^(−N). It is an estimate only — sealing, turbulence and vents
// change the real result, which is why the UI says to verify with an O₂
// analyser.

/// Starting O₂ in the section (air) — same default C₀ as the O₂ tab.
const double kPurgeAirO2Ppm = 210000;

/// Residual O₂ [ppm] after [volumeChanges] volume changes: C₀·e^(−N).
double residualO2PpmAfterVolumeChanges(double volumeChanges,
    {double c0Ppm = kPurgeAirO2Ppm}) {
  return c0Ppm * math.exp(-volumeChanges);
}

/// Volume changes needed to dilute [c0Ppm] down to [targetPpm]:
/// N = ln(C₀ / target). Returns 0 when the target is already met.
double volumeChangesForTargetPpm(double targetPpm,
    {double c0Ppm = kPurgeAirO2Ppm}) {
  if (!(targetPpm > 0)) return double.infinity;
  if (targetPpm >= c0Ppm) return 0;
  return math.log(c0Ppm / targetPpm);
}

// Backing-gas flow guidance — Huntingdon Fusion Techniques, white paper
// WP-269 "Shielding Gas and Purging Techniques during Welding – Part 2":
// pre-purge "a typical gas flow rate of 15-20 l/min" with about five volume
// changes; for welding "the gas flow can be reduced to approximately five
// l/min" and "should be barely perceptible at the exit point"; "Excessive
// flow can raise internal pipe pressure, potentially leading to concave weld
// root geometry".

/// Typical pre-purge (before the arc) flow, lower end [L/min].
const double kPrePurgeFlowLpmMin = 15;

/// Typical pre-purge (before the arc) flow, upper end [L/min].
const double kPrePurgeFlowLpmMax = 20;

/// Flow to reduce to while welding [L/min] — about this or less.
const double kWeldingPurgeFlowLpmMax = 5;

// Outlet (vent) velocity bands used by Pipes → Gases. HEURISTIC, not a
// code: very high velocity through small vent holes means the outlet chokes
// and the pipe pressurises (concave root). One set of numbers for the
// warning text AND the "golden middle" button, so the button can never
// recommend a flow that the same screen then warns about (review G4: the
// old per-hole rule gave 11 m/s against a 6 m/s warning).

/// Below this the outlet is "very open" [m/s].
const double kVentVelocityLowMs = 0.5;

/// Upper end of the comfortable band [m/s].
const double kVentVelocityComfortMs = 3.0;

/// Above this: back-pressure warning [m/s].
const double kVentVelocityBackPressureMs = 6.0;

/// "Golden middle" target inside the comfortable band [m/s].
const double kVentVelocityTargetMs = 2.0;

/// Total vent area [mm²] of [holes] round holes Ø[holeDiaMm].
double ventAreaMm2({required int holes, required double holeDiaMm}) =>
    holes <= 0 || !(holeDiaMm > 0)
        ? 0
        : holes * math.pi * holeDiaMm * holeDiaMm / 4;

/// Mean outlet velocity [m/s] for [flowLpm] through the vents.
double ventVelocityMs({
  required double flowLpm,
  required int holes,
  required double holeDiaMm,
}) {
  final a = ventAreaMm2(holes: holes, holeDiaMm: holeDiaMm);
  if (a <= 0) return double.infinity;
  return flowLpm * 1e6 / 60 / a / 1000; // mm³/s ÷ mm² = mm/s → m/s
}

/// Flow [L/min] giving [velocityMs] at the outlet.
double flowForVentVelocityLpm({
  required double velocityMs,
  required int holes,
  required double holeDiaMm,
}) =>
    ventAreaMm2(holes: holes, holeDiaMm: holeDiaMm) *
    velocityMs *
    1000 *
    60 /
    1e6;
