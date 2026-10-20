// Pure calculations behind the "Kalkulatory montera" tabs
// (lib/screens/fitter_tools_screen.dart). No Flutter imports — every number
// the fitter sees on those tabs comes from here and is pinned by
// test/domain/fitter/fitter_calcs_test.dart.

import 'dart:math' as math;

double _rad(double deg) => deg * math.pi / 180.0;
double _deg(double rad) => rad * 180.0 / math.pi;

// ── Slope cut (single mitre) ─────────────────────────────────────────────────

/// Saw settings for a single mitre cut that gives a [slopePct] % fall.
class SlopeSawAngles {
  /// α = atan(p/100): deviation from a square cut. On a band saw / mitre saw
  /// whose scale reads 0° for a square cut this is the number to set.
  final double fromSquareDeg;

  /// 90° − α: the same cut read on a scale where 90° is square (angle between
  /// blade and pipe axis).
  final double scale90Deg;
  const SlopeSawAngles(this.fromSquareDeg, this.scale90Deg);
}

SlopeSawAngles slopeSawAngles(double slopePct) {
  final a = _deg(math.atan(slopePct / 100.0));
  return SlopeSawAngles(a, 90.0 - a);
}

/// Axial height difference Δh across a pipe of outside diameter [odMm] for a
/// single mitre cut that gives a [slopePct] % fall: Δh = D·tan α with
/// α = atan(p/100), i.e. D·p/100. (D·sin α — used until 2026-09 — is the
/// length along the slanted cut face, not what the fitter marks off.)
/// Same convention as `pipe_slope_screen.dart` (rise = length·tan α).
double slopeCutDeltaMm(double odMm, double slopePct) =>
    odMm * math.tan(math.atan(slopePct / 100.0));

// ── Elbow cut (trim an elbow along its arcs) ────────────────────────────────

class ElbowCutResult {
  final double longCutMm; // extrados mark
  final double shortCutMm; // intrados mark
  final double longRemainMm;
  final double shortRemainMm;
  final double remainAngleDeg;

  /// OD implied by the two tape measurements: (L − S) / θ_rad.
  final double odDerivedMm;
  const ElbowCutResult({
    required this.longCutMm,
    required this.shortCutMm,
    required this.longRemainMm,
    required this.shortRemainMm,
    required this.remainAngleDeg,
    required this.odDerivedMm,
  });
}

/// Arcs are proportional to the angle: cut = total × θ_target / θ_base.
/// Returns null for impossible input (L ≤ S, non-positive sides, target
/// outside (0, base)).
ElbowCutResult? elbowCut({
  required double baseAngleDeg,
  required double extradosMm,
  required double intradosMm,
  required double targetAngleDeg,
}) {
  if (extradosMm <= 0 || intradosMm <= 0 || extradosMm <= intradosMm) {
    return null;
  }
  if (targetAngleDeg <= 0 || targetAngleDeg >= baseAngleDeg) return null;
  final ratio = targetAngleDeg / baseAngleDeg;
  final l = extradosMm * ratio;
  final s = intradosMm * ratio;
  return ElbowCutResult(
    longCutMm: l,
    shortCutMm: s,
    longRemainMm: extradosMm - l,
    shortRemainMm: intradosMm - s,
    remainAngleDeg: baseAngleDeg - targetAngleDeg,
    odDerivedMm: (extradosMm - intradosMm) / _rad(baseAngleDeg),
  );
}

// ── Elbow rotation → distance along the circumference ───────────────────────

enum RotationError { noSize, noRotation }

class RotationArc {
  final double circumferenceMm;
  final double degrees;
  final double arcMm;

  /// More than one full turn (> 360° / > 100 %) — almost always a typo.
  bool get overFullTurn => degrees > 360.0;
  const RotationArc(this.circumferenceMm, this.degrees, this.arcMm);
}

/// Circumference: [circumferenceMm] when > 0, otherwise π × [odMm] (a typed
/// "0" circumference is treated as empty, never as a zero-size pipe).
/// Rotation: [degrees] when > 0, otherwise [percent] when > 0.
({RotationArc? arc, RotationError? error}) rotationArc({
  double? odMm,
  double? circumferenceMm,
  double? percent,
  double? degrees,
}) {
  final double circ;
  if (circumferenceMm != null && circumferenceMm > 0) {
    circ = circumferenceMm;
  } else if (odMm != null && odMm > 0) {
    circ = math.pi * odMm;
  } else {
    return (arc: null, error: RotationError.noSize);
  }
  final double deg;
  if (degrees != null && degrees > 0) {
    deg = degrees;
  } else if (percent != null && percent > 0) {
    deg = 360.0 * percent / 100.0;
  } else {
    return (arc: null, error: RotationError.noRotation);
  }
  return (arc: RotationArc(circ, deg, circ * deg / 360.0), error: null);
}

// ── Concentric reducer trim ─────────────────────────────────────────────────

/// Distance from the LARGE end at which a conical reducer has diameter
/// [targetMm], assuming the cone runs over the whole [lengthMm]:
/// x = L × (D_large − D) / (D_large − D_small). Null when invalid.
double? reducerCutFromLargeMm({
  required double d1Mm,
  required double d2Mm,
  required double lengthMm,
  required double targetMm,
}) {
  if (lengthMm <= 0 || (d1Mm - d2Mm).abs() < 1e-4) return null;
  final big = math.max(d1Mm, d2Mm);
  final small = math.min(d1Mm, d2Mm);
  if (targetMm > big || targetMm < small) return null;
  return lengthMm * (big - targetMm) / (big - small);
}

// ── Pipe weight ─────────────────────────────────────────────────────────────

enum PipeMaterial { ss304, ss316, cs, al }

/// Density in kg/m³.
///  • 304 / 304L (1.4301 / 1.4307): 7 900 — EN 10088-1; Industeel UR 304L
///    data sheet "Density: 7900 kg/m3".
///  • 316 / 316L (1.4401 / 1.4404): 8 000 — EN 10088-1; TEAM EDELSTAHL
///    1.4404 "Density kg/dm³ 8,0".
///  • carbon steel 7 850, aluminium 2 700.
const Map<PipeMaterial, double> kPipeDensityKgM3 = {
  PipeMaterial.ss304: 7900,
  PipeMaterial.ss316: 8000,
  PipeMaterial.cs: 7850,
  PipeMaterial.al: 2700,
};

/// m = ρ × π × (OD − t) × t, kg/m (OD, t in mm).
double pipeMassKgPerM(double odMm, double wallMm, double densityKgM3) =>
    densityKgM3 * math.pi * (odMm - wallMm) * wallMm / 1e6;

// ── Thermal expansion ───────────────────────────────────────────────────────

enum ExpansionMaterial { ss316L, ss304L, cs, cuNi, al }

/// Mean linear expansion coefficient, 1/K (20–100 °C).
///  • 316L and 304L: 16.0 × 10⁻⁶ — EN 10088 data (Industeel UR 304L
///    "20 - 100 °C: 16"). The old 17.2 for 304L was a US 0–100 °F-based value.
const Map<ExpansionMaterial, double> kExpansionAlpha = {
  ExpansionMaterial.ss316L: 16.0e-6,
  ExpansionMaterial.ss304L: 16.0e-6,
  ExpansionMaterial.cs: 12.0e-6,
  ExpansionMaterial.cuNi: 17.0e-6,
  ExpansionMaterial.al: 23.6e-6,
};

/// ΔL = α × L × ΔT, in mm for [lengthM] in metres.
double thermalExpansionMm(double alphaPerK, double lengthM, double deltaK) =>
    alphaPerK * lengthM * deltaK * 1000.0;

// ── Bevel (butt-weld joint preparation) ─────────────────────────────────────

enum BevelJoint {
  /// Single-V: every pipe end bevelled from the outside only.
  v,

  /// Double-V (X): bevelled from both faces, root face in the middle.
  x,
}

/// How the entered angle is meant.
enum BevelAngleConvention {
  /// Included groove angle α between the two bevels — EN ISO 9692-1
  /// designates the V groove by its included angle (e.g. 60°).
  grooveIncluded,

  /// Bevel angle β of ONE pipe end — ASME B16.25 (37.5° ± 2.5°).
  perSide,
}

/// β from the entered value: included → α / 2, per side → as entered.
double bevelPerSideDeg(double angleDeg, BevelAngleConvention c) =>
    c == BevelAngleConvention.grooveIncluded ? angleDeg / 2.0 : angleDeg;

/// Converts an angle value between conventions (37.5 per side ↔ 75 included).
double convertBevelAngle(double angleDeg,
    {required BevelAngleConvention from, required BevelAngleConvention to}) {
  if (from == to) return angleDeg;
  return to == BevelAngleConvention.grooveIncluded
      ? angleDeg * 2.0
      : angleDeg / 2.0;
}

enum BevelInputError { thickness, angle, rootFace, gap }

class BevelGeometry {
  final BevelJoint joint;

  /// β — bevel angle of one pipe end.
  final double perSideDeg;

  /// α = 2β — included groove angle.
  final double grooveDeg;

  /// Bevel depth from ONE face: V → t − b, X → (t − b) / 2.
  final double depthPerFaceMm;

  /// Bevel width at the surface on one pipe end, one face: h × tan β.
  final double widthPerSideMm;

  /// Groove opening at the surface of each bevelled face: g + 2w.
  final double grooveOpeningMm;

  const BevelGeometry({
    required this.joint,
    required this.perSideDeg,
    required this.grooveDeg,
    required this.depthPerFaceMm,
    required this.widthPerSideMm,
    required this.grooveOpeningMm,
  });

  /// Number of faces that get a bevel: 1 (V) or 2 (X).
  int get bevelledFaces => joint == BevelJoint.x ? 2 : 1;
}

/// Validates the raw inputs; null = OK. Nothing defaults silently: an empty
/// field arrives here as null and is reported.
BevelInputError? validateBevel({
  required double? wallMm,
  required double? angleDeg,
  required BevelAngleConvention convention,
  required double? rootFaceMm,
  required double? gapMm,
}) {
  if (wallMm == null || wallMm <= 0) return BevelInputError.thickness;
  if (angleDeg == null) return BevelInputError.angle;
  final beta = bevelPerSideDeg(angleDeg, convention);
  if (!(beta > 0 && beta < 60)) return BevelInputError.angle;
  if (rootFaceMm == null || rootFaceMm < 0 || rootFaceMm >= wallMm) {
    return BevelInputError.rootFace;
  }
  if (gapMm == null || gapMm < 0) return BevelInputError.gap;
  return null;
}

/// Geometry of a V or X preparation. Call [validateBevel] first.
BevelGeometry bevelGeometry({
  required BevelJoint joint,
  required double wallMm,
  required double angleDeg,
  required BevelAngleConvention convention,
  required double rootFaceMm,
  required double gapMm,
}) {
  final beta = bevelPerSideDeg(angleDeg, convention);
  final total = wallMm - rootFaceMm;
  final h = joint == BevelJoint.x ? total / 2.0 : total;
  final w = h * math.tan(_rad(beta));
  return BevelGeometry(
    joint: joint,
    perSideDeg: beta,
    grooveDeg: 2.0 * beta,
    depthPerFaceMm: h,
    widthPerSideMm: w,
    grooveOpeningMm: gapMm + 2.0 * w,
  );
}
