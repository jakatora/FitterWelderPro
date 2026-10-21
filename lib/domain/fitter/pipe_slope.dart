// Pure pipe-slope geometry behind "Spadek rury"
// (lib/screens/pipe_slope_screen.dart). No Flutter imports — the screen and
// the voice assistant both get their numbers from here; pinned by
// test/domain/fitter/pipe_slope_test.dart.
//
// Pipe slope formulas (length = horizontal projection, not the sloping pipe):
//   Rise  = Length × slope% / 100
//   Angle = atan(Rise / Length) = atan(slope% / 100)  [in degrees]
//   mm per metre = slope% × 10
//
// Verification (Length=6000mm, slope=1%):
//   Rise = 6000 × 0.01 = 60mm
//   Angle = atan(0.01) ≈ 0.5729°
//   mm/m  = 10

import 'dart:math' as math;

/// One solved slope: all three related dimensions plus the derived angle and
/// mm per horizontal metre. Lengths in mm, slope in %, angle in degrees.
class PipeSlopeResult {
  const PipeSlopeResult({
    required this.lengthMm,
    required this.riseMm,
    required this.slopePct,
    required this.angleDeg,
    required this.mmPerM,
  });

  /// Horizontal projection of the run, mm.
  final double lengthMm;

  /// Height difference between the ends, mm.
  final double riseMm;
  final double slopePct;

  /// Slope angle from the horizontal, degrees.
  final double angleDeg;

  /// Height difference per horizontal metre, mm/m.
  final double mmPerM;
}

bool _positive(double v) => v.isFinite && v > 0;

double _deg(double rad) => rad * 180.0 / math.pi;

PipeSlopeResult? _finite(PipeSlopeResult r) => [
      r.lengthMm,
      r.riseMm,
      r.slopePct,
      r.angleDeg,
      r.mmPerM
    ].every((v) => v.isFinite)
        ? r
        : null;

/// Rise over a horizontal [lengthMm] at [slopePct] % ("Długość → Wznios").
/// `null` unless both inputs are finite and > 0 and the result is finite.
PipeSlopeResult? slopeRiseFromLength({
  required double lengthMm,
  required double slopePct,
}) {
  if (!_positive(lengthMm) || !_positive(slopePct)) return null;
  return _finite(PipeSlopeResult(
    lengthMm: lengthMm,
    riseMm: lengthMm * slopePct / 100.0,
    slopePct: slopePct,
    angleDeg: _deg(math.atan(slopePct / 100.0)),
    mmPerM: slopePct * 10.0,
  ));
}

/// Horizontal length that gives [riseMm] at [slopePct] % ("Wznios → Długość").
/// `null` unless both inputs are finite and > 0 and the result is finite.
PipeSlopeResult? slopeLengthFromRise({
  required double riseMm,
  required double slopePct,
}) {
  if (!_positive(riseMm) || !_positive(slopePct)) return null;
  return _finite(PipeSlopeResult(
    lengthMm: riseMm / (slopePct / 100.0),
    riseMm: riseMm,
    slopePct: slopePct,
    angleDeg: _deg(math.atan(slopePct / 100.0)),
    mmPerM: slopePct * 10.0,
  ));
}

/// Slope % of a run with horizontal [lengthMm] and [riseMm] ("Wyznacz %").
/// The angle is atan(rise / length), exactly as the screen computes it.
/// `null` unless both inputs are finite and > 0 and the result is finite.
PipeSlopeResult? slopeFromLengthAndRise({
  required double lengthMm,
  required double riseMm,
}) {
  if (!_positive(lengthMm) || !_positive(riseMm)) return null;
  final slopePct = (riseMm / lengthMm) * 100.0;
  return _finite(PipeSlopeResult(
    lengthMm: lengthMm,
    riseMm: riseMm,
    slopePct: slopePct,
    angleDeg: _deg(math.atan(riseMm / lengthMm)),
    mmPerM: slopePct * 10.0,
  ));
}

/// Slope angle from the horizontal for [slopePct] %: atan(% / 100), degrees.
/// 1 % is not 1°. `null` unless [slopePct] is finite and > 0.
double? slopeAngleDeg(double slopePct) =>
    _positive(slopePct) ? _deg(math.atan(slopePct / 100.0)) : null;

/// Height difference per horizontal metre for [slopePct] %: % × 10, mm/m.
/// `null` unless [slopePct] is finite and > 0 (and the result is finite).
double? slopeMmPerM(double slopePct) {
  if (!_positive(slopePct)) return null;
  final v = slopePct * 10.0;
  return v.isFinite ? v : null;
}

/// Rise : horizontal-run ratio as percent; no rounded preset substitution.
double? slopePercentFromRatio(double rise, double run) {
  if (!_positive(rise) || !_positive(run)) return null;
  final percent = (rise / run) * 100;
  return _positive(percent) ? percent : null;
}

/// The actual native input shortcuts; 0.67% is a rounded 1:150 label.
const pipeSlopePresets = <(String, String)>[
  ('0.5', '1:200'),
  ('0.67', '1:150'),
  ('1', '1:100'),
  ('2', '1:50'),
];
