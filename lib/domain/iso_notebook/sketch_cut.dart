/// CUT of one pipe drawn in the ISO notebook — the single formula behind the
/// notebook's drawing, its cut list, its PDF and the CUT project created from
/// a sketch (`sketch_to_project.dart`).
///
/// It used to live inside `iso_notebook_screen.dart` over the screen's private
/// model classes, so nothing outside the screen could compute the number the
/// fitter sees on the sketch. A project created from the sketch has to store
/// exactly that number; the only way to guarantee it is for both to call the
/// same code. The screen's model classes implement the small interfaces below
/// ([SketchComponent], [SketchPipe], [SketchDimension], [SketchDeduct]), so
/// the screen hands its own objects in without copying them.
///
/// Pure: no widgets, no database. All lengths are millimetres.
library;

import 'dart:ui' show Offset;

import '../../models/prefab/dim_ref.dart';
import '../../models/prefab/end_connection.dart';
import '../../services/component_classification.dart';
import '../../services/iso_parser.dart';
import '../../services/prefab_engine.dart';
import '../../services/takeout_catalog.dart';

// ─────────────────────────────────────────────────────────────────────────
// What the formula reads off a sketch
// ─────────────────────────────────────────────────────────────────────────

/// A symbol placed on the sketch (fitting, valve, weld dot, marker…).
abstract interface class SketchComponent {
  Offset get pos;

  /// The palette tool's name (`elbow90`, `gateValve`, `weld`…) — the
  /// vocabulary of [ComponentClassification].
  String get toolName;

  /// Nominal size the fitter gave the component, if any.
  int? get dn;

  /// Centre-to-end take-out the fitter entered (elbow, tee, olet).
  int? get cteMm;

  /// Length along the run of a bodied component (valve, flange, reducer, cap).
  int? get physicalLengthMm;

  /// Outlet DN of a reducer.
  int? get dnOut;

  /// Joint type at each end of a bodied component; null = butt weld.
  EndConnection? get endA;
  EndConnection? get endB;
}

/// One hand-typed deduct row of the CUT calculator.
abstract interface class SketchDeduct {
  String get name;
  String get value;
}

/// The dimension typed on a line, with its CUT calculator.
abstract interface class SketchDimension {
  /// ISO expression as typed (`2000`, `3000+525-80`, `(1500)`).
  String get iso;

  /// How the dimension was measured.
  DimRef get ref;

  /// Hand-typed deduct rows.
  List<SketchDeduct> get deducts;

  /// "(1500)" — a reference dimension, printed but never sawn.
  bool get isReference;
}

/// A line of the sketch between two grid points.
abstract interface class SketchPipe {
  Offset get a;
  Offset get b;

  /// Null while the line has no dimension.
  SketchDimension? get dimension;
}

/// Grid step of the notebook canvas (world units per grid cell).
const double kSketchGridStep = 32.0;

/// How close a component must sit to a pipe end to count as ON that end —
/// the tolerance the notebook has always used (0.45 of a grid step).
const double kSketchJointTolerance = kSketchGridStep * 0.45;

// ─────────────────────────────────────────────────────────────────────────
// Classification
// ─────────────────────────────────────────────────────────────────────────

/// `true` when [toolName] is dimensioned to its CENTRELINE (elbow / tee /
/// olet).
///
/// Wraps [ComponentClassification.isAxial], which throws on tool names it
/// cannot classify (line tools, annotations). A throw here must not be read
/// as "axial" — it would push an unpriced symbol into the take-out sum — so
/// it is treated as not-axial.
bool sketchIsAxialTool(String toolName) {
  try {
    return ComponentClassification.isAxial(toolName);
  } catch (_) {
    return false;
  }
}

/// `true` when [toolName] has a body of its own along the run (valve,
/// reducer, flange, cap). Unclassifiable names are not physical.
bool sketchIsPhysicalTool(String toolName) {
  try {
    return ComponentClassification.isPhysical(toolName);
  } catch (_) {
    return false;
  }
}

/// Centre-to-end take-out (mm) of an axial component, or `null` when the
/// component carries no usable dimension.
///
/// Resolution order:
///   1. the CTE the fitter entered on the component,
///   2. for a tee, ASME B16.9 run/branch CTE for its DN,
///   3. nothing — and the caller must SAY so rather than quietly using 0.
///
/// An elbow's CTE only ever comes from its spec sheet. An olet deliberately
/// has no table fallback: a weldolet sits on the OUTSIDE of the run, so its
/// take-out is not the B16.9 tee CTE.
int? sketchAxialTakeoutOf(SketchComponent c) {
  if (!sketchIsAxialTool(c.toolName)) return null;
  final explicit = c.cteMm;
  if (explicit != null && explicit > 0) return explicit;
  if (c.toolName == 'elbow90' || c.toolName == 'elbow45') return null;
  if (c.toolName != 'tee') return null;
  final dn = c.dn;
  if (dn == null) return null;
  final v = TakeoutCatalog.tee[dn];
  return (v != null && v > 0) ? v : null;
}

/// Catalog deduct labels that already represent the take-out of the fitting
/// named [toolName], lower-cased.
///
/// The manual deduct picker writes these exact strings into a deduct row's
/// name. When such a row is present the fitter has ALREADY booked that
/// fitting by hand, so the automatic pass must stand down for one component
/// of that kind — otherwise the take-out is subtracted twice and the pipe
/// comes out short.
Set<String> isoManualDeductAliases(String toolName) {
  switch (toolName) {
    case 'elbow90':
      return const {'kolano 90° lr (cte)', 'kolano 90° sr (cte)'};
    case 'elbow45':
      return const {'kolano 45° lr (cte)'};
    case 'tee':
      return const {'trójnik (cte)'};
    default:
      return const {};
  }
}

bool _onPoint(SketchComponent c, Offset p, double tol) =>
    (c.pos - p).distance < tol;

// ─────────────────────────────────────────────────────────────────────────
// Take-outs
// ─────────────────────────────────────────────────────────────────────────

/// Automatic axial take-outs for one pipe, split per end, plus the axial
/// components on its ends that could NOT be resolved.
class SketchAxialTakeouts {
  final int leftMm;
  final int rightMm;

  /// Axial components sitting on an end with no usable take-out. They
  /// contribute 0 — the cut list and the canvas must flag them so the fitter
  /// sees a gap instead of trusting a silently short subtraction.
  final List<SketchComponent> missing;

  const SketchAxialTakeouts({
    required this.leftMm,
    required this.rightMm,
    required this.missing,
  });

  int get totalMm => leftMm + rightMm;
}

/// Resolves the axial take-outs on both ends of [pipe] (`a` = left,
/// `b` = right).
///
/// [manual] is the pipe's hand-entered deduct list; rows whose name matches
/// a catalog label for a component found here suppress ONE automatic
/// contribution of that kind, so the manual path and the automatic one can
/// coexist without double-counting.
SketchAxialTakeouts sketchAxialTakeoutsFor(
  SketchPipe pipe,
  Iterable<SketchComponent> components,
  double tol, {
  List<SketchDeduct> manual = const [],
}) {
  final unclaimed = <String, int>{};
  for (final d in manual) {
    if (d.value.trim().isEmpty) continue;
    final key = d.name.trim().toLowerCase();
    if (key.isEmpty) continue;
    unclaimed[key] = (unclaimed[key] ?? 0) + 1;
  }
  bool claimedByHand(String toolName) {
    for (final alias in isoManualDeductAliases(toolName)) {
      final n = unclaimed[alias];
      if (n != null && n > 0) {
        unclaimed[alias] = n - 1;
        return true;
      }
    }
    return false;
  }

  var left = 0;
  var right = 0;
  final missing = <SketchComponent>[];
  for (final it in components) {
    final onA = _onPoint(it, pipe.a, tol);
    final onB = _onPoint(it, pipe.b, tol);
    if (!onA && !onB) continue;
    if (!sketchIsAxialTool(it.toolName)) continue;
    final cte = sketchAxialTakeoutOf(it);
    if (cte == null) {
      missing.add(it);
      continue;
    }
    if (claimedByHand(it.toolName)) continue;
    if (onA) {
      left += cte;
    } else {
      right += cte;
    }
  }
  return SketchAxialTakeouts(leftMm: left, rightMm: right, missing: missing);
}

/// Sum of the body lengths of the physical components sitting on
/// [endpoint]. Axial fittings are handled by [sketchAxialTakeoutsFor].
int sketchPhysicalDeductAt(
  Offset endpoint,
  Iterable<SketchComponent> components,
  double tol,
) {
  var sum = 0;
  for (final it in components) {
    if (!sketchIsPhysicalTool(it.toolName)) continue;
    final len = it.physicalLengthMm;
    if (len == null || len <= 0) continue;
    if (_onPoint(it, endpoint, tol)) sum += len;
  }
  return sum;
}

/// Physical components ON the line of [pipe] but on neither end (a valve
/// planted inside a dimensioned run). [withLength] true → only those with a
/// body length, false → only those WITHOUT one.
List<SketchComponent> _midPhysicals(
  SketchPipe pipe,
  Iterable<SketchComponent> components,
  double tol, {
  required bool withLength,
}) {
  final ab = pipe.b - pipe.a;
  final lenSq = ab.dx * ab.dx + ab.dy * ab.dy;
  if (lenSq < 1) return const [];
  final out = <SketchComponent>[];
  for (final it in components) {
    if (!sketchIsPhysicalTool(it.toolName)) continue;
    final len = it.physicalLengthMm;
    final hasLength = len != null && len > 0;
    if (hasLength != withLength) continue;
    if (_onPoint(it, pipe.a, tol) || _onPoint(it, pipe.b, tol)) continue;
    final t = ((it.pos.dx - pipe.a.dx) * ab.dx +
            (it.pos.dy - pipe.a.dy) * ab.dy) /
        lenSq;
    if (t < 0 || t > 1) continue;
    final foot = pipe.a + ab * t;
    if ((it.pos - foot).distance > tol) continue;
    out.add(it);
  }
  return out;
}

/// Sum of the body lengths of physical components BETWEEN the two ends of
/// [pipe] (on its line, not on an end). They add to the dimensioned span no
/// matter how the ends were measured.
int sketchMidPhysicalDeduct(
  SketchPipe pipe,
  Iterable<SketchComponent> components,
  double tol,
) {
  var sum = 0;
  for (final it in _midPhysicals(pipe, components, tol, withLength: true)) {
    sum += it.physicalLengthMm!;
  }
  return sum;
}

/// Physical components on the run of [pipe] whose length is unknown — they
/// contribute nothing, which is a gap and not a fact.
List<SketchComponent> sketchMidPhysicalsWithoutLength(
  SketchPipe pipe,
  Iterable<SketchComponent> components,
  double tol,
) =>
    _midPhysicals(pipe, components, tol, withLength: false);

// ─────────────────────────────────────────────────────────────────────────
// Welds (root gap)
// ─────────────────────────────────────────────────────────────────────────

/// Whether the pipe is WELDED at [endpoint] — i.e. whether a root gap is
/// left open there and has to come off the cut.
///
/// A pipe end is welded when a fitting sits on it: an axial fitting (elbow,
/// tee, olet) always, a bodied one (valve, reducer, flange, cap) unless all
/// of its end connections are non-welded (threaded, grooved, none). Nothing
/// on the end — a free pipe end, a weld dot, a support, a marker — is the
/// segment builder's OPEN_END: no weld, no gap. This is the notebook's
/// reading of [PrefabEngine.weldCountForEnds], and the kind a project row
/// gets for that end follows the same rule (see `sketch_to_project.dart`), so
/// the recompute of saved segments counts the same welds.
bool sketchEndIsWelded(
  Offset endpoint,
  Iterable<SketchComponent> components,
  double tol,
) {
  for (final it in components) {
    if (!_onPoint(it, endpoint, tol)) continue;
    if (sketchIsAxialTool(it.toolName)) return true;
    if (sketchIsPhysicalTool(it.toolName)) {
      final a = it.endA ?? EndConnection.buttWeld;
      final b = it.endB ?? EndConnection.buttWeld;
      if (a.producesWeld || b.producesWeld) return true;
    }
  }
  return false;
}

/// Welds — and root gaps — on [pipe]: [PrefabEngine.weldCountForEnds] with
/// [sketchEndIsWelded] on each end.
int sketchWeldCount(
  SketchPipe pipe,
  Iterable<SketchComponent> components,
  double tol,
) =>
    PrefabEngine.weldCountForEnds(
      startIsOpenEnd: !sketchEndIsWelded(pipe.a, components, tol),
      endIsOpenEnd: !sketchEndIsWelded(pipe.b, components, tol),
    );

/// A gap value the formula accepts: finite and positive, else 0 — a
/// nonsense gap is not a reason to LENGTHEN a pipe.
double sanitizeSketchGap(double gapMm) =>
    (gapMm.isFinite && gapMm > 0) ? gapMm : 0.0;

// ─────────────────────────────────────────────────────────────────────────
// The CUT
// ─────────────────────────────────────────────────────────────────────────

/// Everything the CUT of one pipe is made of. [cutMm] is THE number; the
/// rest explains it (and lets a project row reproduce it).
class SketchCutBreakdown {
  final double isoMm;
  final DimRef ref;
  final SketchAxialTakeouts axial;
  final int leftPhysicalMm;
  final int rightPhysicalMm;
  final int midPhysicalMm;

  /// Sum of the readable hand-typed deduct rows.
  final double manualDeductMm;
  final double gapMm;
  final int welds;

  /// Engine result before the manual rows (NaN when the engine refused).
  final double engineCutMm;

  const SketchCutBreakdown({
    required this.isoMm,
    required this.ref,
    required this.axial,
    required this.leftPhysicalMm,
    required this.rightPhysicalMm,
    required this.midPhysicalMm,
    required this.manualDeductMm,
    required this.gapMm,
    required this.welds,
    required this.engineCutMm,
  });

  /// THE cut length: engine result minus the hand-typed rows. NaN when the
  /// engine refused (nothing to cut); may be negative when the typed rows
  /// exceed what is left — the screen flags that.
  double get cutMm => engineCutMm - manualDeductMm;

  /// What the root gaps take off: gap × welds.
  double get gapTotalMm => gapMm * welds;
}

/// The breakdown of [pipe]'s CUT, or null when the pipe carries no
/// dimension, a reference dimension, or an ISO text that does not parse.
SketchCutBreakdown? sketchCutBreakdown(
  SketchPipe pipe,
  Iterable<SketchComponent> components, {
  double tol = kSketchJointTolerance,
  double gapMm = 0,
}) {
  final c = pipe.dimension;
  if (c == null || c.isReference) return null;
  final double isoMm;
  try {
    isoMm = parseIsoExpression(c.iso);
  } catch (_) {
    return null;
  }
  final comps = components is List<SketchComponent>
      ? components
      : components.toList(growable: false);
  final axial = sketchAxialTakeoutsFor(pipe, comps, tol, manual: c.deducts);
  // Unreadable manual rows are skipped: dropping ONE bad deduct preserves the
  // rest of the math (the cut list shows the row as typed).
  var manual = 0.0;
  for (final d in c.deducts) {
    if (d.value.trim().isEmpty) continue;
    try {
      manual += parseIsoExpression(d.value);
    } catch (_) {}
  }
  final leftPhys = sketchPhysicalDeductAt(pipe.a, comps, tol);
  final rightPhys = sketchPhysicalDeductAt(pipe.b, comps, tol);
  final midPhys = sketchMidPhysicalDeduct(pipe, comps, tol);
  final gap = sanitizeSketchGap(gapMm);
  final welds = sketchWeldCount(pipe, comps, tol);
  final engine = PrefabEngine.cutLengthMm(
    isoValueMm: isoMm,
    ref: c.ref,
    leftCteMm: axial.leftMm,
    rightCteMm: axial.rightMm,
    leftPhysicalLenMm: leftPhys > 0 ? leftPhys : null,
    rightPhysicalLenMm: rightPhys > 0 ? rightPhys : null,
    midPhysicalSumMm: midPhys,
    // Tell the engine which side is physical so centreToFace credits ONLY
    // the centre side's CTE (not both).
    leftIsPhysical: leftPhys > 0,
    rightIsPhysical: rightPhys > 0,
    // The root gap, once per welded end — the segment builder's rule. With
    // the sketch gap at 0 (the default) this is exactly the old number.
    weldGapMm: gap,
    weldCount: welds,
  );
  return SketchCutBreakdown(
    isoMm: isoMm,
    ref: c.ref,
    axial: axial,
    leftPhysicalMm: leftPhys,
    rightPhysicalMm: rightPhys,
    midPhysicalMm: midPhys,
    manualDeductMm: manual,
    gapMm: gap,
    welds: welds,
    engineCutMm: engine,
  );
}

/// THE cut length of [pipe] in millimetres — what the notebook draws, lists,
/// exports and what a project created from the sketch stores. NaN when there
/// is nothing to cut (no dimension, reference dimension, unreadable ISO,
/// engine refusal).
double sketchCutMm(
  SketchPipe pipe,
  Iterable<SketchComponent> components, {
  double tol = kSketchJointTolerance,
  double gapMm = 0,
}) =>
    sketchCutBreakdown(pipe, components, tol: tol, gapMm: gapMm)?.cutMm ??
    double.nan;

/// Nominal size a pipe carries, read off the components on its ends (a
/// reducer's outlet DN wins over its inlet; the last component found wins,
/// as the notebook's cut list has always read it). Null when none says.
int? sketchInferredDn(
  SketchPipe pipe,
  Iterable<SketchComponent> components,
  double tol,
) {
  int? best;
  for (final endpoint in [pipe.a, pipe.b]) {
    for (final it in components) {
      if (!_onPoint(it, endpoint, tol)) continue;
      final candidate = it.dnOut ?? it.dn;
      if (candidate != null) best = candidate;
    }
  }
  return best;
}
