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

  /// Where the dimension stops at the pipe's end `a` / `b`, as chosen (or
  /// confirmed) in the dimension window — both set or both null.
  ///
  /// Null on a dimension typed before the window asked per end: then [ref]
  /// decides, as it always did. A DimRef cannot name every pair (a spool
  /// between two weld-neck flanges is "through the body" at BOTH ends) and
  /// does not say which end is which; explicit stops do both.
  SideStop? get stopA;
  SideStop? get stopB;
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
// Node geometry — which leg of a tee / olet a pipe is
// ─────────────────────────────────────────────────────────────────────────

/// How a pipe meets the tee or olet sitting on one of its ends.
enum SketchLegRole {
  /// Straight through: another pipe leaves the same point in the opposite
  /// direction (the run of a tee, the header at an olet).
  run,

  /// The odd one out: the two other pipes at the point run straight through
  /// each other and this one does not.
  branch,

  /// The drawing does not say (the other legs are not drawn, or no two of
  /// them are in line).
  unknown,
}

bool _sameLine(SketchPipe x, SketchPipe y, double tol) =>
    identical(x, y) ||
    ((x.a - y.a).distance < tol && (x.b - y.b).distance < tol) ||
    ((x.a - y.b).distance < tol && (x.b - y.a).distance < tol);

/// Unit vector from [p] along [q], when [q] has an end on [p].
Offset? _awayFrom(SketchPipe q, Offset p, double tol) {
  final Offset other;
  if ((q.a - p).distance < tol) {
    other = q.b;
  } else if ((q.b - p).distance < tol) {
    other = q.a;
  } else {
    return null;
  }
  final d = other - p;
  final len = d.distance;
  if (len < 1e-6) return null;
  return d / len;
}

bool _opposite(Offset u, Offset v) => u.dx * v.dx + u.dy * v.dy < -0.98;

/// Which leg [pipe] is at the node [p], judged from the other [pipes] that
/// end on the same point. On an isometric, lines that are opposite on paper
/// are opposite in space, so "in line" is read straight off the sketch.
SketchLegRole sketchLegRoleAt(
  SketchPipe pipe,
  Offset p,
  Iterable<SketchPipe> pipes,
  double tol,
) {
  final mine = _awayFrom(pipe, p, tol);
  if (mine == null) return SketchLegRole.unknown;
  final others = <Offset>[];
  for (final q in pipes) {
    if (_sameLine(q, pipe, tol)) continue;
    final d = _awayFrom(q, p, tol);
    if (d != null) others.add(d);
  }
  if (others.any((d) => _opposite(d, mine))) return SketchLegRole.run;
  for (var i = 0; i < others.length; i++) {
    for (var j = i + 1; j < others.length; j++) {
      if (_opposite(others[i], others[j])) return SketchLegRole.branch;
    }
  }
  return SketchLegRole.unknown;
}

/// `true` for a tee whose branch is smaller than its run (DN given on both).
bool sketchIsReducingTee(SketchComponent c) {
  if (c.toolName != 'tee') return false;
  final run = c.dn;
  final branch = c.dnOut;
  return run != null && branch != null && branch != run;
}

/// Outlet take-out M (centre of the run to the end of the branch) of a
/// reducing tee, ASME B16.9 Tab. 6.1-7 — null when the table has no such
/// pair (never interpolated).
int? sketchReducingTeeOutletM(SketchComponent c) {
  if (!sketchIsReducingTee(c)) return null;
  final v = TakeoutCatalog.reducingTeeOutletM[c.dn!]?[c.dnOut!];
  return (v != null && v > 0) ? v : null;
}

/// Take-out of the tee [c] for a pipe that is its [role] leg:
///   * an equal tee: C for every leg (the fitter's own CTE, else B16.9);
///   * a reducing tee, run leg: C of the run size (the fitter's own CTE,
///     else B16.9 [TakeoutCatalog.tee]);
///   * a reducing tee, branch leg: M from B16.9 Tab. 6.1-7;
///   * a reducing tee on a leg the drawing does not identify: null — C and
///     M differ, and picking one is a guess.
int? sketchTeeTakeoutFor(SketchComponent c, SketchLegRole role) {
  if (!sketchIsReducingTee(c)) return sketchAxialTakeoutOf(c);
  switch (role) {
    case SketchLegRole.run:
      return sketchAxialTakeoutOf(c);
    case SketchLegRole.branch:
      return sketchReducingTeeOutletM(c);
    case SketchLegRole.unknown:
      return null;
  }
}

/// `true` when the olet [c] sits on [endpoint] of [pipe] and [pipe] is the
/// HEADER there — another pipe continues straight on from the same point.
///
/// A header is not cut at an olet (the olet is welded onto its outside), so
/// such a pipe gets neither the olet's take-out nor a root gap at that end.
/// Two lines meeting at an olet are one pipe drawn twice; the plan refuses
/// them (see `sketch_to_project.dart`).
bool sketchIsOletHeaderEnd(
  SketchComponent c,
  SketchPipe pipe,
  Offset endpoint,
  Iterable<SketchPipe> pipes,
  double tol,
) =>
    c.toolName == 'olet' &&
    _onPoint(c, endpoint, tol) &&
    sketchLegRoleAt(pipe, endpoint, pipes, tol) == SketchLegRole.run;

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

  /// Components without a take-out of their own that a hand-typed catalog
  /// row ("Kolano 90° LR (CTE)") stands in for. Not missing: the fitter
  /// booked them himself.
  final List<SketchComponent> claimedByHand;

  /// Reducing tees on an end where the drawing does not show whether this
  /// pipe is the run or the branch (subset of [missing]).
  final List<SketchComponent> teeRoleUnknown;

  /// Olets this pipe runs straight past (it is the header there): no
  /// take-out, no gap — see [sketchIsOletHeaderEnd].
  final List<SketchComponent> oletHeaderEnds;

  const SketchAxialTakeouts({
    required this.leftMm,
    required this.rightMm,
    required this.missing,
    this.claimedByHand = const [],
    this.teeRoleUnknown = const [],
    this.oletHeaderEnds = const [],
  });

  int get totalMm => leftMm + rightMm;
}

/// Resolves the axial take-outs on both ends of [pipe] (`a` = left,
/// `b` = right).
///
/// [manual] is the pipe's hand-entered deduct list; rows whose name matches
/// a catalog label for a component found here suppress ONE automatic
/// contribution of that kind, so the manual path and the automatic one can
/// coexist without double-counting. A row is matched to a component that
/// has NO take-out of its own first: that is the fitting the fitter typed it
/// for. Matching it to a specced one instead took the second fitting's
/// take-out away and left the pipe long by a whole CTE.
///
/// [pipes] (the other lines of the sketch) tell a tee's run from its branch
/// and the header at an olet; without them every leg of a reducing tee is
/// "unknown" and an olet always takes its take-out, as before.
SketchAxialTakeouts sketchAxialTakeoutsFor(
  SketchPipe pipe,
  Iterable<SketchComponent> components,
  double tol, {
  List<SketchDeduct> manual = const [],
  Iterable<SketchPipe> pipes = const [],
}) {
  final unclaimed = <String, int>{};
  for (final d in manual) {
    if (d.value.trim().isEmpty) continue;
    final key = d.name.trim().toLowerCase();
    if (key.isEmpty) continue;
    unclaimed[key] = (unclaimed[key] ?? 0) + 1;
  }
  bool claimByHand(String toolName) {
    for (final alias in isoManualDeductAliases(toolName)) {
      final n = unclaimed[alias];
      if (n != null && n > 0) {
        unclaimed[alias] = n - 1;
        return true;
      }
    }
    return false;
  }

  // Axial components on the ends, each with the take-out it gives THIS pipe.
  final found = <(SketchComponent, bool onA, int? cte)>[];
  final oletHeader = <SketchComponent>[];
  final roleUnknown = <SketchComponent>[];
  for (final it in components) {
    final onA = _onPoint(it, pipe.a, tol);
    final onB = _onPoint(it, pipe.b, tol);
    if (!onA && !onB) continue;
    if (!sketchIsAxialTool(it.toolName)) continue;
    final end = onA ? pipe.a : pipe.b;
    if (sketchIsOletHeaderEnd(it, pipe, end, pipes, tol)) {
      oletHeader.add(it);
      continue;
    }
    int? cte;
    if (it.toolName == 'tee') {
      final role = sketchLegRoleAt(pipe, end, pipes, tol);
      cte = sketchTeeTakeoutFor(it, role);
      if (cte == null &&
          role == SketchLegRole.unknown &&
          sketchIsReducingTee(it)) {
        roleUnknown.add(it);
      }
    } else {
      cte = sketchAxialTakeoutOf(it);
    }
    found.add((it, onA, cte));
  }

  var left = 0;
  var right = 0;
  final missing = <SketchComponent>[];
  final byHand = <SketchComponent>[];
  // Pass 1: fittings with nothing to deduct — a matching hand row is theirs.
  for (final (it, _, cte) in found) {
    if (cte != null) continue;
    if (claimByHand(it.toolName)) {
      byHand.add(it);
    } else {
      missing.add(it);
    }
  }
  // Pass 2: the rest take their own take-out unless a row is still left.
  for (final (it, onA, cte) in found) {
    if (cte == null) continue;
    if (claimByHand(it.toolName)) continue;
    if (onA) {
      left += cte;
    } else {
      right += cte;
    }
  }
  return SketchAxialTakeouts(
    leftMm: left,
    rightMm: right,
    missing: missing,
    claimedByHand: byHand,
    teeRoleUnknown: roleUnknown.where(missing.contains).toList(),
    oletHeaderEnds: oletHeader,
  );
}

// ─────────────────────────────────────────────────────────────────────────
// What sits on an end, and where a dimension can stop there
// ─────────────────────────────────────────────────────────────────────────

/// What sits on one end of a pipe, as far as the dimension is concerned.
enum SketchEndKind {
  /// Nothing fitted (a free end, a weld dot, a support): the pipe itself.
  free,

  /// An elbow / tee / olet — dimensioned to its centreline.
  axial,

  /// A flange — dimensioned to its sealing (gasket) face.
  flange,

  /// A valve, reducer, cap or blind — dimensioned to the face the pipe meets.
  body,
}

/// Kind of the end [endpoint] (an axial fitting wins over a body sharing the
/// point).
SketchEndKind sketchEndKindAt(
  Offset endpoint,
  Iterable<SketchComponent> components,
  double tol,
) {
  var kind = SketchEndKind.free;
  for (final it in components) {
    if (!_onPoint(it, endpoint, tol)) continue;
    if (sketchIsAxialTool(it.toolName)) return SketchEndKind.axial;
    if (sketchIsPhysicalTool(it.toolName)) {
      if (it.toolName == 'flange') {
        kind = SketchEndKind.flange;
      } else if (kind == SketchEndKind.free) {
        kind = SketchEndKind.body;
      }
    }
  }
  return kind;
}

/// The stop a dimension to an end of [kind] normally has — the segment
/// builder's defaults (`_defaultRefPoint`), so the notebook and the builder
/// give the same CUT for the same drawing:
///   * elbow / tee / olet: the centreline;
///   * flange: its sealing face, i.e. THROUGH the flange (a weld neck's Y
///     comes off the pipe) — the builder's FACE_FAR;
///   * valve and the other bodies: the face the pipe meets (nothing off);
///   * nothing fitted: the pipe end.
SideStop sketchDefaultStopFor(SketchEndKind kind) {
  switch (kind) {
    case SketchEndKind.axial:
      return SideStop.centre;
    case SketchEndKind.flange:
      return SideStop.end;
    case SketchEndKind.body:
    case SketchEndKind.free:
      return SideStop.face;
  }
}

/// The stops a fitter can pick for an end of [kind], default first.
List<SideStop> sketchStopOptionsFor(SketchEndKind kind) {
  switch (kind) {
    case SketchEndKind.axial:
      return const [SideStop.centre, SideStop.face];
    case SketchEndKind.flange:
      return const [SideStop.end, SideStop.face];
    case SketchEndKind.body:
      return const [SideStop.face, SideStop.end];
    case SketchEndKind.free:
      return const [SideStop.face];
  }
}

/// A stop at an end of [kind] in words a fitter uses — never a code.
({String pl, String en}) sketchStopWords(SketchEndKind kind, SideStop stop) {
  switch (kind) {
    case SketchEndKind.axial:
      return stop == SideStop.centre
          ? (pl: 'do osi kształtki', en: 'to the fitting centreline')
          : (
              pl: 'do końca kształtki (spoina)',
              en: 'to the fitting end (weld)'
            );
    case SketchEndKind.flange:
      return stop == SideStop.end
          ? (
              pl: 'do przylgi kołnierza (odejmuje szyjkę Y)',
              en: 'to the flange gasket face (takes off the hub Y)'
            )
          : (
              pl: 'do spoiny kołnierza (koniec szyjki, bez Y)',
              en: 'to the flange weld (hub end, no Y)'
            );
    case SketchEndKind.body:
      return stop == SideStop.end
          ? (
              pl: 'przez korpus do drugiego czoła (odejmuje długość)',
              en: 'through the body to its far face (takes off its length)'
            )
          : (
              pl: 'do czoła elementu (nic nie odejmuje)',
              en: 'to the component face (nothing off)'
            );
    case SketchEndKind.free:
      return (pl: 'do końca rury', en: 'to the pipe end');
  }
}

/// Default stops for a new dimension on [pipe]: end `a`, end `b`.
({SideStop a, SideStop b}) sketchDefaultStops(
  SketchPipe pipe,
  Iterable<SketchComponent> components,
  double tol,
) =>
    (
      a: sketchDefaultStopFor(sketchEndKindAt(pipe.a, components, tol)),
      b: sketchDefaultStopFor(sketchEndKindAt(pipe.b, components, tol)),
    );

/// `true` when [dim] is a dimension from before the per-end choice whose
/// reference was never picked (still the old default, centre–centre) while a
/// flange / valve / reducer / cap sits on an end. Such a dimension may have
/// been measured to the flange face or through it — the old default read it
/// as "to the near face" and left a WN spool long by Y. It is flagged and
/// kept out of a project until the fitter confirms it in the window.
bool sketchRefUnconfirmed(
  SketchPipe pipe,
  Iterable<SketchComponent> components,
  double tol,
) {
  final dim = pipe.dimension;
  if (dim == null || dim.isReference) return false;
  if (dim.stopA != null && dim.stopB != null) return false;
  if (dim.ref != DimRef.centreToCentre) return false;
  bool bodied(Offset p) {
    final k = sketchEndKindAt(p, components, tol);
    return k == SketchEndKind.flange || k == SketchEndKind.body;
  }

  return bodied(pipe.a) || bodied(pipe.b);
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
    final t =
        ((it.pos.dx - pipe.a.dx) * ab.dx + (it.pos.dy - pipe.a.dy) * ab.dy) /
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
///
/// With [pipe] and [pipes] given, an olet the pipe runs straight past (it is
/// the header there, [sketchIsOletHeaderEnd]) is not a weld on this pipe.
bool sketchEndIsWelded(
  Offset endpoint,
  Iterable<SketchComponent> components,
  double tol, {
  SketchPipe? pipe,
  Iterable<SketchPipe> pipes = const [],
}) {
  for (final it in components) {
    if (!_onPoint(it, endpoint, tol)) continue;
    if (pipe != null && sketchIsOletHeaderEnd(it, pipe, endpoint, pipes, tol)) {
      continue;
    }
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
  double tol, {
  Iterable<SketchPipe> pipes = const [],
}) =>
    PrefabEngine.weldCountForEnds(
      startIsOpenEnd:
          !sketchEndIsWelded(pipe.a, components, tol, pipe: pipe, pipes: pipes),
      endIsOpenEnd:
          !sketchEndIsWelded(pipe.b, components, tol, pipe: pipe, pipes: pipes),
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

  /// The stop the engine used at end `a` (left) and `b` (right) — the
  /// fitter's explicit choice, or what [ref] resolved to. Null when the
  /// engine had nothing to work from.
  final SideStop? stopA;
  final SideStop? stopB;

  /// True when the stops were picked per end in the dimension window.
  final bool explicitStops;

  /// Hand-typed rows whose value does not parse ("3+", "7,,5"). While any is
  /// here there is NO cut: a row the fitter typed and the arithmetic skipped
  /// would leave the pipe long by exactly that row.
  final List<SketchDeduct> unreadableDeducts;

  /// See [sketchRefUnconfirmed].
  final bool refUnconfirmed;

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
    this.stopA,
    this.stopB,
    this.explicitStops = false,
    this.unreadableDeducts = const [],
    this.refUnconfirmed = false,
  });

  /// THE cut length: engine result minus the hand-typed rows. NaN when the
  /// engine refused (nothing to cut) or a typed row is unreadable; may be
  /// negative when the typed rows exceed what is left — the screen flags
  /// that.
  double get cutMm =>
      unreadableDeducts.isNotEmpty ? double.nan : engineCutMm - manualDeductMm;

  /// What end `a` / `b` takes off at its stop (take-out, body or nothing).
  double get deductAMm => _sideMm(stopA, axial.leftMm, leftPhysicalMm);
  double get deductBMm => _sideMm(stopB, axial.rightMm, rightPhysicalMm);

  static double _sideMm(SideStop? s, int cte, int body) => switch (s) {
        SideStop.centre => cte.toDouble(),
        SideStop.end => body.toDouble(),
        SideStop.face || null => 0,
      };

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
  Iterable<SketchPipe> pipes = const [],
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
  final lines = pipes is List<SketchPipe> ? pipes : pipes.toList();
  final axial =
      sketchAxialTakeoutsFor(pipe, comps, tol, manual: c.deducts, pipes: lines);
  // A row that does not parse is NOT skipped: it is listed, and the pipe
  // has no cut until it is fixed (spec §2 rule 6 — an uncertain number never
  // quietly becomes a cut length).
  var manual = 0.0;
  final unreadable = <SketchDeduct>[];
  for (final d in c.deducts) {
    if (d.value.trim().isEmpty) continue;
    try {
      final v = parseIsoExpression(d.value);
      if (!v.isFinite) throw const FormatException('non-finite');
      manual += v;
    } catch (_) {
      unreadable.add(d);
    }
  }
  final leftPhys = sketchPhysicalDeductAt(pipe.a, comps, tol);
  final rightPhys = sketchPhysicalDeductAt(pipe.b, comps, tol);
  final midPhys = sketchMidPhysicalDeduct(pipe, comps, tol);
  final gap = sanitizeSketchGap(gapMm);
  final welds = sketchWeldCount(pipe, comps, tol, pipes: lines);
  final explicit = c.stopA != null && c.stopB != null;
  final stops = explicit
      ? (left: c.stopA!, right: c.stopB!)
      : PrefabEngine.resolveSideStops(
          ref: c.ref,
          leftCteMm: axial.leftMm,
          rightCteMm: axial.rightMm,
          leftPhysicalLenMm: leftPhys,
          rightPhysicalLenMm: rightPhys,
          leftIsPhysical: leftPhys > 0,
          rightIsPhysical: rightPhys > 0,
        );
  final engine = PrefabEngine.cutLengthMm(
    isoValueMm: isoMm,
    // Explicit stops need no DimRef; a legacy dimension resolves its ref.
    ref: explicit ? null : c.ref,
    leftStop: explicit ? c.stopA : null,
    rightStop: explicit ? c.stopB : null,
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
    stopA: stops?.left,
    stopB: stops?.right,
    explicitStops: explicit,
    unreadableDeducts: unreadable,
    refUnconfirmed: sketchRefUnconfirmed(pipe, comps, tol),
  );
}

/// THE cut length of [pipe] in millimetres — what the notebook draws, lists,
/// exports and what a project created from the sketch stores. NaN when there
/// is nothing to cut (no dimension, reference dimension, unreadable ISO or
/// deduct row, engine refusal).
double sketchCutMm(
  SketchPipe pipe,
  Iterable<SketchComponent> components, {
  double tol = kSketchJointTolerance,
  double gapMm = 0,
  Iterable<SketchPipe> pipes = const [],
}) =>
    sketchCutBreakdown(pipe, components, tol: tol, gapMm: gapMm, pipes: pipes)
        ?.cutMm ??
    double.nan;

/// Nominal size a pipe carries, read off the components on its ends (a
/// reducer's outlet DN wins over its inlet; the last component found wins,
/// as the notebook's cut list has always read it). Null when none says.
///
/// A reducing tee gives its branch size only to its branch leg — with
/// [pipes] to tell the legs apart; its run legs (and any leg the drawing
/// does not identify) keep the run size.
int? sketchInferredDn(
  SketchPipe pipe,
  Iterable<SketchComponent> components,
  double tol, {
  Iterable<SketchPipe> pipes = const [],
}) {
  int? best;
  for (final endpoint in [pipe.a, pipe.b]) {
    for (final it in components) {
      if (!_onPoint(it, endpoint, tol)) continue;
      int? candidate;
      if (it.toolName == 'tee') {
        candidate = sketchIsReducingTee(it) &&
                sketchLegRoleAt(pipe, endpoint, pipes, tol) ==
                    SketchLegRole.branch
            ? it.dnOut
            : it.dn;
      } else {
        candidate = it.dnOut ?? it.dn;
      }
      if (candidate != null) best = candidate;
    }
  }
  return best;
}
