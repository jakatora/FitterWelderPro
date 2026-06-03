import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/elbow_takeouts.dart';
import '../i18n/app_language.dart';
import '../services/iso_parser.dart';
import '../services/iso_pdf_export.dart';
import '../services/takeout_catalog.dart';
import '../utils/haptic.dart';
import '../widgets/help_button.dart';
import '../models/prefab/dim_ref.dart';
import '../services/prefab_engine.dart' as prefab;
import '../models/prefab/end_connection.dart';
import '../services/component_classification.dart';

// ═══════════════════════════════════════════════════════════════════════════
// ISO NOTEBOOK — full piping isometric sketch pad with a built-in cut
// calculator. A fitter draws the run, types the ISO (face-to-face) dimension
// for each segment, lists the take-outs of the components on its ends
// (elbow centre-to-face, flange thickness, valve width…), and the app gives
// back the length of pipe to actually saw:
//
//   CUT = ISO − Σ (component take-outs)
// ═══════════════════════════════════════════════════════════════════════════

enum _Tool {
  // Lines
  pipe, thin, dashed,
  // Fittings & components — drawn on grid points, rotatable
  elbow90, elbow45, tee, olet, reducer, flange, blindFlange, cap,
  gateValve, ballValve, checkValve, globeValve, butterflyValve,
  weld, fieldWeld, support, instrument, spoolBreak,
  // Annotations
  northArrow, flowArrow, text,
}

extension _ToolX on _Tool {
  bool get isLine => index <= _Tool.dashed.index;
  bool get isText => this == _Tool.text;
  bool get isComp => !isLine && !isText;
  bool get isWeld => this == _Tool.weld || this == _Tool.fieldWeld;
}

abstract class _Item {}

/// One component whose take-out is subtracted from the ISO dimension to
/// arrive at the cut length.
class _Deduct {
  final String name;   // human label, e.g. "Elbow 90°", "Flange"
  final String value;  // expression in mm
  const _Deduct(this.name, this.value);
}

/// Full cut calculation for a pipe segment: ISO − Σ deducts.
/// When [deducts] is empty the segment carries a plain dimension; when it is
/// non-empty the on-drawing label shows the resolved CUT in an accent colour.
class _CutCalc {
  final String iso;
  final List<_Deduct> deducts;
  /// How the on-drawing ISO dimension was measured. Phase 1: only consulted
  /// by [_IsoState._resolvedCut] via [prefab.PrefabEngine]; the legacy
  /// [cutMm] getter ignores it for backwards-compat.
  final DimRef ref;
  const _CutCalc(this.iso, {this.deducts = const [], this.ref = DimRef.centreToCentre});

  bool get hasDeducts => deducts.isNotEmpty;

  /// Resolved cut length in mm. NaN if the ISO itself cannot be parsed;
  /// unreadable deducts are skipped (so partial input still gives a number).
  double get cutMm {
    // Parenthesised ISO means "reference only" — never a cut target, so the
    // BOM and on-drawing CUT skip it entirely.
    final t = iso.trim();
    if (t.startsWith('(') && t.endsWith(')')) return double.nan;
    double v;
    try {
      v = parseIsoExpression(iso);
    } catch (_) {
      return double.nan;
    }
    for (final d in deducts) {
      if (d.value.trim().isEmpty) continue;
      try {
        v -= parseIsoExpression(d.value);
      } catch (_) {
        // skip unreadable deduct
      }
    }
    return v;
  }
}

/// Dialog return value: distinguishes "set new value", "remove", "cancel".
/// Carries an optional slope tag for off-axis (drain / vent) segments and
/// the insulation flag for cladded pipe.
class _CalcResult {
  final _CutCalc? calc;
  final String slope;
  final bool insulated;
  final DimRef ref;
  final bool remove;
  const _CalcResult.set(this.calc,
      {this.slope = '',
      this.insulated = false,
      this.ref = DimRef.centreToCentre})
      : remove = false;
  const _CalcResult.removed()
      : calc = null,
        slope = '',
        insulated = false,
        ref = DimRef.centreToCentre,
        remove = true;
}

class _Seg implements _Item {
  final Offset a, b;
  final _Tool t;
  final _CutCalc? calc;
  /// Free-text slope annotation: "1:100", "FALL 25mm", "FALL 5°" etc.
  /// Surfaces on the segment as a small chip; only set when the line was
  /// drawn off-axis (drain falls, vents) — axis-locked lines are level.
  final String slope;
  /// `true` when the pipe is insulated — renders thin dashed lines flanking
  /// the centreline so the iso reads the same way a real shop drawing does
  /// (insulation lines run parallel to the carrier pipe).
  final bool insulated;
  const _Seg(this.a, this.b, this.t,
      {this.calc, this.slope = '', this.insulated = false});
  _Seg withCalc(_CutCalc? c) =>
      _Seg(a, b, t, calc: c, slope: slope, insulated: insulated);
  _Seg withSlope(String s) =>
      _Seg(a, b, t, calc: calc, slope: s, insulated: insulated);
  _Seg withInsulated(bool v) =>
      _Seg(a, b, t, calc: calc, slope: slope, insulated: v);
  bool get hasDim => calc != null;
  bool get hasSlope => slope.isNotEmpty;
}

/// Pipe size + elbow type stored on an elbow component. Drives both the on-
/// drawing label ("DN50 · 2" 90° LR") and the auto CTE subtraction in the
/// CUT-list math: a pipe segment that touches an elbow at either endpoint
/// has that elbow's `cteMm` deducted from the ISO before showing CUT.
enum _ElbowSubtype { lr90, sr90, lr45, sr45 }

extension _ElbowSubtypeX on _ElbowSubtype {
  String get label => switch (this) {
        _ElbowSubtype.lr90 => '90° LR',
        _ElbowSubtype.sr90 => '90° SR',
        _ElbowSubtype.lr45 => '45° LR',
        _ElbowSubtype.sr45 => '45° SR',
      };
}

/// Standard CTE for the given DN + elbow subtype, pulled from
/// [kElbowTakeouts]. Returns 0 only when the table doesn't cover the DN
/// (defensive — the table covers 15..600 which is everything in practice).
int _stdCte(int dn, _ElbowSubtype t) {
  final row = closestByDn(dn);
  return switch (t) {
    _ElbowSubtype.lr90 => row.lr90,
    _ElbowSubtype.sr90 => row.sr90,
    _ElbowSubtype.lr45 => row.lr45,
    _ElbowSubtype.sr45 => row.lr45, // table doesn't distinguish; safe default
  };
}

/// Sum of CTE values from every elbow with a known `cteMm` that lies on one
/// of the segment's endpoints. This is what makes "ISO 500 − 55 (oś
/// kolanka) − 55 (oś kolanka) = CUT 390" math happen automatically — the
/// user just enters the ISO dimension, the table values do the rest.
int _autoElbowDeductFor(_Seg seg, List<_Item> items, double tol) {
  int total = 0;
  for (final it in items) {
    if (it is! _Comp) continue;
    if (!it.isElbow) continue;
    final cte = it.cteMm;
    if (cte == null || cte <= 0) continue;
    if ((it.pos - seg.a).distance < tol || (it.pos - seg.b).distance < tol) {
      total += cte;
    }
  }
  return total;
}

/// Sum of `physicalLengthMm` for every physical component sitting near
/// [endpoint]. Reducer / valve / flange / cap go through here; axial
/// fittings (elbow / tee / olet) are ignored because they're handled by
/// the CTE deduct path. Cap-style face-only components are bucketed under
/// "physical" since the engine still needs them subtracted for FTE / FTF.
int _autoPhysicalDeductFor(Offset endpoint, List<_Item> items, double tol) {
  int sum = 0;
  for (final it in items) {
    if (it is! _Comp) continue;
    try {
      if (!ComponentClassification.isPhysical(it.t.name)) continue;
    } catch (_) {
      continue;
    }
    final len = it.physicalLengthMm;
    if (len == null || len <= 0) continue;
    if ((it.pos - endpoint).distance < tol) sum += len;
  }
  return sum;
}

/// Sum of `physicalLengthMm` for physical components that sit BETWEEN
/// seg.a and seg.b along the pipe (within [tol] of the segment line, but
/// NOT within [tol] of either endpoint). Endpoint-physicals are billed to
/// leftPhysicalLen / rightPhysicalLen — the mid bucket only gets components
/// the user has planted along the run (e.g. a gate valve inside a
/// CTC dimension between two elbows).
int _midPhysicalDeductFor(_Seg seg, List<_Item> items, double tol) {
  final ab = seg.b - seg.a;
  final lenSq = ab.dx * ab.dx + ab.dy * ab.dy;
  if (lenSq < 1) return 0;
  int sum = 0;
  for (final it in items) {
    if (it is! _Comp) continue;
    try {
      if (!ComponentClassification.isPhysical(it.t.name)) continue;
    } catch (_) {
      continue;
    }
    final len = it.physicalLengthMm;
    if (len == null || len <= 0) continue;
    if ((it.pos - seg.a).distance < tol) continue;
    if ((it.pos - seg.b).distance < tol) continue;
    final t = ((it.pos.dx - seg.a.dx) * ab.dx +
            (it.pos.dy - seg.a.dy) * ab.dy) /
        lenSq;
    if (t < 0 || t > 1) continue;
    final foot = seg.a + ab * t;
    if ((it.pos - foot).distance > tol) continue;
    sum += len;
  }
  return sum;
}

class _Comp implements _Item {
  final Offset pos;
  final _Tool t;
  final int dir;
  /// Second leg direction for elbows / tees / reducers. Allows the symbol to
  /// follow the real iso axes of the attached pipes instead of using a fixed
  /// 90° template — an "elbow 90°" in iso paper space sits between any two
  /// of the 6 iso headings (e.g. +I and +II is the 60°-on-paper / 90°-in-3D
  /// elbow that maps to a real horizontal-to-vertical turn).
  /// `null` = single-axis component (valve, flange, weld, etc.) — render
  /// rotates the legacy fixed symbol by `dir * 60°` as before.
  final int? dir2;
  final String label;

  /// Elbow specification — only set on elbow90 / elbow45 components.
  /// `dn` is nominal diameter in mm (15..600); `cteMm` is the centre-to-end
  /// dimension subtracted from any pipe touching this elbow during CUT-list
  /// computation. When `dn` is null the elbow contributes 0 to the deduct
  /// (user hasn't told us the size yet).
  final int? dn;
  final _ElbowSubtype? elbowSubtype;
  final int? cteMm;

  /// Physical face-to-face / face-to-end length in mm for non-axial components.
  /// Null for axial components. For reducer = inlet-face to outlet-face length.
  /// For valve = ASME B16.10 face-to-face. For flange = face thickness from
  /// the welded face to the flange face. For cap = face length.
  final int? physicalLengthMm;

  /// Outlet DN — only set for diameter-change components (reducer). When non-null,
  /// pipes downstream of this component carry this DN instead of the project default.
  final int? dnOut;

  /// Joint type at each end. Drives the Phase 3 auto-weld pass. Null = default (buttWeld).
  final EndConnection? endA;
  final EndConnection? endB;

  const _Comp(
    this.pos,
    this.t, {
    this.dir = 0,
    this.dir2,
    this.label = '',
    this.dn,
    this.elbowSubtype,
    this.cteMm,
    this.physicalLengthMm,
    this.dnOut,
    this.endA,
    this.endB,
  });

  _Comp rotate() => _Comp(pos, t,
      dir: (dir + 1) % 6,
      dir2: dir2 == null ? null : (dir2! + 1) % 6,
      label: label,
      dn: dn,
      elbowSubtype: elbowSubtype,
      cteMm: cteMm,
      physicalLengthMm: physicalLengthMm,
      dnOut: dnOut,
      endA: endA,
      endB: endB);

  _Comp withElbowSpec({int? dn, _ElbowSubtype? subtype, int? cte}) => _Comp(
        pos,
        t,
        dir: dir,
        dir2: dir2,
        label: label,
        dn: dn,
        elbowSubtype: subtype,
        cteMm: cte,
        physicalLengthMm: physicalLengthMm,
        dnOut: dnOut,
        endA: endA,
        endB: endB,
      );

  /// Persist physical-length / outlet-DN / end-connection spec captured by
  /// the reducer / valve / flange / cap spec sheets. Mirrors [withElbowSpec]
  /// for axial components — copies pos/t/dir/dir2/label/cte from `this` and
  /// takes the physical fields purely from the named args (so calling with
  /// no args would clear them — caller is responsible for passing the full
  /// captured spec).
  _Comp withPhysicalSpec({
    required int dn,
    int? dnOut,
    int? physicalLengthMm,
    EndConnection? endA,
    EndConnection? endB,
  }) =>
      _Comp(
        pos,
        t,
        dir: dir,
        dir2: dir2,
        label: label,
        dn: dn,
        elbowSubtype: elbowSubtype,
        cteMm: cteMm,
        physicalLengthMm: physicalLengthMm,
        dnOut: dnOut,
        endA: endA,
        endB: endB,
      );

  bool get isElbow => t == _Tool.elbow90 || t == _Tool.elbow45;
}

class _Note implements _Item {
  final Offset pos;
  final String text;
  const _Note(this.pos, this.text);
  _Note withText(String t) => _Note(pos, t);
}

// ─── Isometric axes ────────────────────────────────────────────────────────────
//
// A piping isometric uses three primary axes 60° apart on paper. This canvas
// uses a triangular grid (rows horizontal, dy = s·√3/2), so the three on-axis
// directions for any line are:
//
//   I   →  0°   (along grid rows)                  — one horizontal real-world axis
//   II  →  60°  (down-right / up-left in screen)   — other horizontal real-world axis
//   III →  120° (down-left / up-right in screen)   — vertical real-world axis (Up/Dn)
//
// The mapping I/II/III ↔ N/E/Up is set by the user via the on-canvas compass
// (see [_AxisMapping]); by default III is vertical because that's how rotated
// 30°-iso paper reads to most pipefitters. Lines that don't fall within ~10°
// of any of these axes are tagged off-axis (sloped lines, drain falls, etc.).

enum _Axis { i, ii, iii, off }

extension _AxisX on _Axis {
  String get label => switch (this) {
        _Axis.i => 'I',
        _Axis.ii => 'II',
        _Axis.iii => 'III',
        _Axis.off => '∼',
      };
}

/// Returns the iso axis a line lies on (or [_Axis.off] for sloped lines).
/// Tolerance of 6° around each primary direction — looser than that would
/// false-positive on near-axis sloped lines that the monter draws on purpose.
_Axis _classifyAxis(Offset a, Offset b) {
  final dx = b.dx - a.dx;
  final dy = b.dy - a.dy;
  if (dx.abs() < 0.5 && dy.abs() < 0.5) return _Axis.off;
  final deg = (math.atan2(dy, dx) * 180 / math.pi + 360) % 180;
  bool near(double t) => (deg - t).abs() <= 6;
  if (near(0) || near(180)) return _Axis.i;
  if (near(60)) return _Axis.ii;
  if (near(120)) return _Axis.iii;
  return _Axis.off;
}

/// 6 iso headings as unit vectors. Index = N arrow `dir` after the symbol
/// refactor (dir=0 is +I = right). Cycling `dir` by 60° walks around the
/// hex; pairs that share an axis differ by 3.
const List<Offset> _isoHeadings = [
  Offset(1, 0),                                  // dir=0 → +I (right)
  Offset(0.5, -0.8660254037844387),              // dir=1 → −III (up-right)
  Offset(-0.5, -0.8660254037844387),             // dir=2 → −II (up-left)
  Offset(-1, 0),                                 // dir=3 → −I (left)
  Offset(-0.5, 0.8660254037844387),              // dir=4 → +III (down-left)
  Offset(0.5, 0.8660254037844387),               // dir=5 → +II (down-right)
];

/// Iso axis for each `dir` of a N-arrow component.
const List<_Axis> _isoAxisByDir = [
  _Axis.i, _Axis.iii, _Axis.ii, _Axis.i, _Axis.iii, _Axis.ii,
];

/// Reasonable physical lengths in mm so the user doesn't have to type the
/// number on every placement. Pulled from ASME B16.10 / B16.5 / B16.9.
/// Mirrors [TakeoutCatalog.flangeWN150] — kept inline so the spec sheet
/// helpers can default-fill without a catalog round-trip.
const Map<int, int> _flangeFaceDefault = {
  15: 11, 20: 12, 25: 14, 32: 16, 40: 17, 50: 19, 65: 22, 80: 24,
  100: 24, 150: 25, 200: 28, 250: 30, 300: 32,
};

/// Class-150 face-to-face dims (B16.10) — applies to gate / globe / ball /
/// check as a sane starting point. Butterfly is wafer-style and much shorter
/// but we keep one table to avoid per-valve-kind branching in the picker.
const Map<int, int> _valveDefault = {
  50: 178, 65: 191, 80: 203, 100: 229, 150: 267, 200: 292, 250: 330, 300: 356,
};

/// Reading derived from an on-canvas North arrow. With no arrow on the
/// drawing, axes stay anonymous (I/II/III); with one, lines get N/E/Up
/// labels and direction (N vs S, E vs W, ↑ vs ↓) computed against the
/// arrow's heading.
class _AxisMapping {
  /// Which iso axis the N-S line lies on, and the unit vector of "+N".
  final _Axis nsAxis;
  final Offset northVec;

  /// The other two axes get default roles: the axis whose "+end" has the
  /// smaller |dx| (i.e. closest to vertical-ish on screen) is treated as
  /// Up-Dn, with +Up pointing toward smaller screen-y. The remaining axis
  /// becomes E-W with +E pointing toward larger screen-x. These defaults
  /// match the common "iso paper with N to upper-left" reading; the user
  /// can override later (planned: long-press compass to swap E/Up).
  final _Axis ewAxis;
  final Offset eastVec;

  final _Axis upAxis;
  final Offset upVec;

  const _AxisMapping({
    required this.nsAxis,
    required this.northVec,
    required this.ewAxis,
    required this.eastVec,
    required this.upAxis,
    required this.upVec,
  });

  /// Build a mapping from a N-arrow `dir` (0..5). Returns null for invalid
  /// dirs (defensive — should never happen).
  static _AxisMapping? fromNorthDir(int dir) {
    if (dir < 0 || dir > 5) return null;
    final nsAxis = _isoAxisByDir[dir];
    final northVec = _isoHeadings[dir];

    // Pick the remaining two axes. For each, pick whichever heading sits in
    // the +x / -y quadrant as the "positive" direction.
    final remaining = <_Axis>[_Axis.i, _Axis.ii, _Axis.iii]
        .where((a) => a != nsAxis)
        .toList();
    Offset positiveHeading(_Axis a) {
      // Find a heading vector that lies on this axis with x ≥ 0; if tied, pick
      // the one with the more-negative y (upward).
      Offset best = _isoHeadings[0];
      double bestScore = -double.infinity;
      for (int i = 0; i < 6; i++) {
        if (_isoAxisByDir[i] != a) continue;
        final v = _isoHeadings[i];
        final score = v.dx * 1.0 + (-v.dy) * 0.001;
        if (score > bestScore) {
          bestScore = score;
          best = v;
        }
      }
      return best;
    }

    // Up = axis with the "more vertical" heading (smaller |dx|).
    final h0 = positiveHeading(remaining[0]);
    final h1 = positiveHeading(remaining[1]);
    final upAxis = (h0.dx.abs() < h1.dx.abs()) ? remaining[0] : remaining[1];
    final ewAxis = upAxis == remaining[0] ? remaining[1] : remaining[0];
    final upVec = upAxis == remaining[0] ? h0 : h1;
    final eastVec = ewAxis == remaining[0] ? h0 : h1;

    // For Up: flip vector so it points up on screen (smaller y).
    final upFinal = upVec.dy <= 0 ? upVec : -upVec;

    return _AxisMapping(
      nsAxis: nsAxis,
      northVec: northVec,
      ewAxis: ewAxis,
      eastVec: eastVec,
      upAxis: upAxis,
      upVec: upFinal,
    );
  }

  /// Returns the role-label (N/S, E/W, ↑/↓) for a directed line A→B if it
  /// lies on one of the mapped axes. Returns empty string for off-axis lines.
  String labelForLine(Offset a, Offset b) {
    final axis = _classifyAxis(a, b);
    if (axis == _Axis.off) return '';
    final v = b - a;
    final len = v.distance;
    if (len < 0.5) return '';
    final unit = Offset(v.dx / len, v.dy / len);

    if (axis == nsAxis) {
      final dot = unit.dx * northVec.dx + unit.dy * northVec.dy;
      return dot >= 0 ? 'N' : 'S';
    }
    if (axis == ewAxis) {
      final dot = unit.dx * eastVec.dx + unit.dy * eastVec.dy;
      return dot >= 0 ? 'E' : 'W';
    }
    if (axis == upAxis) {
      final dot = unit.dx * upVec.dx + unit.dy * upVec.dy;
      return dot >= 0 ? '↑' : '↓';
    }
    return '';
  }

  /// What role does this iso axis play under this mapping? Returns 'N',
  /// 'E', or 'U' for use in the compass legend.
  String roleFor(_Axis a) {
    if (a == nsAxis) return 'N';
    if (a == ewAxis) return 'E';
    if (a == upAxis) return 'U';
    return '';
  }
}

// ─── Screen ───────────────────────────────────────────────────────────────────

class IsoNotebookScreen extends StatefulWidget {
  const IsoNotebookScreen({super.key});
  @override
  State<IsoNotebookScreen> createState() => _IsoState();
}

class _IsoState extends State<IsoNotebookScreen> {
  static const double _s = 32.0;
  static const String _kHintHiddenPref = 'iso_notebook_hint_hidden';
  static const String _kAxisCompassPref = 'iso_notebook_show_axis_compass';
  static const String _kStatusBoxPref = 'iso_notebook_show_status_box';
  static const String _kPaperModePref = 'iso_notebook_paper_mode';

  final List<_Item> _items = [];
  final List<List<_Item>> _undo = [];
  int _version = 0; // bumped on every mutation → forces a repaint

  Offset? _dragA, _dragB;
  _Tool _tool = _Tool.pipe;
  String _projectName = '';

  /// User-dismissable empty-state hint. Persisted across sessions via
  /// SharedPreferences so it doesn't reappear on every app start. The app
  /// bar has a Help button to bring it back when needed.
  bool _hintHidden = false;
  bool _hintLoaded = false;

  /// Overlay toggles + canvas mode. Default to old behaviour (compass +
  /// status box visible, dark canvas) so existing users see no change.
  /// All three flags persist independently — a fitter who hides the axis
  /// legend on the prefab job site keeps it hidden across sessions.
  bool _showAxisCompass = true;
  bool _showStatusBox = true;
  bool _paperMode = false;

  /// Canvas viewport — pan offset and zoom scale applied uniformly to every
  /// world-space draw call AND inversely to every incoming gesture position
  /// so the fitter can scroll a long iso past the screen edge and pinch in
  /// for detailed dimensioning. View state is NOT persisted (always opens
  /// at 1.0 / origin) — each session starts at the canonical view.
  Offset _viewOffset = Offset.zero;
  double _viewScale = 1.0;
  bool _panMode = false;

  /// Convert a raw localPosition (screen coords) to canvas world coords so
  /// every gesture handler that snaps to grid / hit-tests items can stay
  /// scale-agnostic.
  Offset _toWorld(Offset raw) =>
      Offset((raw.dx - _viewOffset.dx) / _viewScale,
          (raw.dy - _viewOffset.dy) / _viewScale);

  /// Zoom around the centre of the canvas (or [focal] when supplied) so
  /// "+" / "-" buttons feel natural — content under the cursor stays under
  /// the cursor.
  void _zoomBy(double factor, {Offset? focal}) {
    final ctx = _canvasKey.currentContext;
    final renderObj = ctx?.findRenderObject();
    if (renderObj is! RenderBox) return;
    final size = renderObj.size;
    final pivot = focal ?? Offset(size.width / 2, size.height / 2);
    final newScale = (_viewScale * factor).clamp(0.25, 6.0);
    final ratio = newScale / _viewScale;
    setState(() {
      _viewOffset = pivot - (pivot - _viewOffset) * ratio;
      _viewScale = newScale;
    });
  }

  @override
  void initState() {
    super.initState();
    _loadPrefs();
  }

  Future<void> _loadPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _hintHidden = prefs.getBool(_kHintHiddenPref) ?? false;
      _showAxisCompass = prefs.getBool(_kAxisCompassPref) ?? true;
      _showStatusBox = prefs.getBool(_kStatusBoxPref) ?? true;
      _paperMode = prefs.getBool(_kPaperModePref) ?? false;
      _hintLoaded = true;
    });
  }

  Future<void> _setHintHidden(bool v) async {
    setState(() => _hintHidden = v);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kHintHiddenPref, v);
  }

  Future<void> _setShowAxisCompass(bool v) async {
    setState(() => _showAxisCompass = v);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kAxisCompassPref, v);
  }

  Future<void> _setShowStatusBox(bool v) async {
    setState(() => _showStatusBox = v);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kStatusBoxPref, v);
  }

  Future<void> _setPaperMode(bool v) async {
    setState(() => _paperMode = v);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kPaperModePref, v);
  }

  /// When true (default), pipes get axis-locked to the nearest iso axis from
  /// the start point. This is how real iso drafting works — every pipe runs
  /// along one of the 3 primary 3D axes. Sloped lines (drain falls, vents)
  /// are the exception; the user can switch the toggle off to draw those.
  bool _axisLock = true;

  /// Wrapped around the CustomPaint so we can rasterise it to PNG for the
  /// PDF export. Capturing via RenderRepaintBoundary.toImage is the cleanest
  /// path that avoids porting the painter to pw.Canvas.
  final GlobalKey _canvasKey = GlobalKey();

  String _tr(String pl, String en) => context.tr(pl: pl, en: en);

  /// First North arrow on the canvas (if any) drives the axis-to-direction
  /// mapping. We re-derive on every paint via [_currentMapping] rather than
  /// caching, because items are mutated by setState and the cost is trivial.
  _AxisMapping? get _currentMapping {
    for (final it in _items) {
      if (it is _Comp && it.t == _Tool.northArrow) {
        return _AxisMapping.fromNorthDir(it.dir);
      }
    }
    return null;
  }

  void _mutate(VoidCallback f) {
    setState(() {
      f();
      _version++;
    });
  }

  // ── isometric snap ──────────────────────────────────────────────────────────
  Offset _snap(Offset raw) {
    final dy = _s * math.sqrt(3) / 2.0;
    Offset best = Offset.zero;
    double bestD = double.infinity;
    for (int dr = -3; dr <= 3; dr++) {
      final row = (raw.dy / dy).round() + dr;
      if (row < 0) continue;
      final y = row * dy;
      final xOff = (row % 2 == 0) ? 0.0 : _s / 2.0;
      for (int dc = -3; dc <= 3; dc++) {
        final col = ((raw.dx - xOff) / _s).round() + dc;
        final pt = Offset(col * _s + xOff, y);
        final d = (raw - pt).distance;
        if (d < bestD) {
          bestD = d;
          best = pt;
        }
      }
    }
    return best;
  }

  double _distToSeg(Offset p, Offset a, Offset b) {
    final ab = b - a;
    final l2 = ab.dx * ab.dx + ab.dy * ab.dy;
    if (l2 == 0) return (p - a).distance;
    var t = ((p.dx - a.dx) * ab.dx + (p.dy - a.dy) * ab.dy) / l2;
    t = t.clamp(0.0, 1.0);
    return (p - (a + ab * t)).distance;
  }

  // ── line drawing (pan) ──────────────────────────────────────────────────────
  void _panStart(DragStartDetails d) {
    if (_panMode) {
      // Pan mode: drag scrolls the canvas instead of drawing. Store the raw
      // starting position so subsequent updates can compute a delta.
      return;
    }
    if (!_tool.isLine) return;
    setState(() {
      _dragA = _snap(_toWorld(d.localPosition));
      _dragB = _dragA;
    });
  }

  void _panUpdate(DragUpdateDetails d) {
    if (_panMode) {
      setState(() => _viewOffset += d.delta);
      return;
    }
    if (!_tool.isLine) return;
    final raw = _toWorld(d.localPosition);
    final next = (_axisLock && _tool == _Tool.pipe && _dragA != null)
        ? _axisSnap(_dragA!, raw)
        : _snap(raw);
    // Snap-tick: each time the snapped endpoint jumps to a different grid
    // intersection, fire a light haptic pulse. Mobile has no hover, so this
    // is the tactile equivalent of a "snap latched" visual tick — the user
    // feels each grid step lock in while dragging, even with gloves on.
    final prev = _dragB;
    if (prev != null && next != prev) {
      unawaited(Haptic.tap());
    }
    setState(() => _dragB = next);
  }

  /// Snap a target point to the closest grid point that lies on one of the
  /// three iso axes through [from]. Picks whichever of the 6 primary
  /// headings is closest in direction to the user's drag, then walks the
  /// integer number of grid steps along that heading to land near [target].
  Offset _axisSnap(Offset from, Offset target) {
    final delta = target - from;
    if (delta.distance < _s * 0.25) return from;
    // Six primary heading unit vectors (length = one grid step _s).
    final dy = _s * math.sqrt(3) / 2;
    final headings = <Offset>[
      Offset(_s, 0),       // +I
      Offset(-_s, 0),      // -I
      Offset(_s / 2, dy),  // +II (down-right)
      Offset(-_s / 2, -dy),// -II (up-left)
      Offset(-_s / 2, dy), // +III (down-left)
      Offset(_s / 2, -dy), // -III (up-right)
    ];
    Offset best = from;
    double bestD = double.infinity;
    for (final h in headings) {
      // Projection of delta onto this heading (positive only — we want the
      // user's drag direction).
      final t = (delta.dx * h.dx + delta.dy * h.dy) / (h.distance * h.distance);
      if (t <= 0) continue;
      final k = math.max(1, t.round());
      final candidate = from + h * k.toDouble();
      final d = (candidate - target).distance;
      if (d < bestD) {
        bestD = d;
        best = candidate;
      }
    }
    return best;
  }

  Future<void> _panEnd(DragEndDetails _) async {
    if (!_tool.isLine || _dragA == null || _dragB == null) return;
    final a = _dragA!, b = _dragB!;
    final tool = _tool;
    setState(() {
      _dragA = null;
      _dragB = null;
    });
    if ((b - a).distance <= _s * 0.25) return;

    _push();
    final seg = _Seg(a, b, tool);
    _mutate(() => _items.add(seg));

    // Glove-friendly confirmation: fitters often can't see the screen at the
    // moment the finger lifts (phone in chest bracket, sun glare). A medium
    // impact on commit confirms the segment landed.
    unawaited(Haptic.saved());

    // Dimensions are entered at the end of the route via the "Wymiary"
    // button in the app bar (or by tapping an individual segment to edit).
    // Auto-insert a 90° elbow at the junction if this pipe meets another
    // pipe at a corner — orientation derived from the bisector angle in
    // isometric screen space, then snapped to the nearest 60° step that
    // _Comp.rotate() understands (dir = 0..5).
    if (tool == _Tool.pipe) {
      _maybeInsertElbows(seg);
    }
  }

  // ── auto-elbow detection ────────────────────────────────────────────────────
  /// When a freshly-placed pipe shares an endpoint with another pipe and the
  /// angle between them is "corner-like" (not straight, not a sharp reversal),
  /// insert an elbow component at the junction with the orientation that
  /// best matches the bisector of the two segments. Picks elbow90 vs elbow45
  /// based on how sharp the on-paper turn is. Drops two weld dots (one per
  /// leg) so the iso reads the same way as a fabrication drawing. Skips if a
  /// component already sits at the junction so the user can still rotate
  /// manually.
  void _maybeInsertElbows(_Seg newSeg) {
    for (final endpoint in [newSeg.a, newSeg.b]) {
      // Collect EVERY pipe touching this endpoint (incl. the new one). 2 pipes
      // → elbow, 3 pipes → tee. Four-way junctions are ambiguous in real iso
      // fabrication and we don't try — the user can place that manually.
      final touching = <_Seg>[];
      for (final it in _items) {
        if (it is! _Seg || it.t != _Tool.pipe) continue;
        if ((it.a - endpoint).distance < _s * 0.25 ||
            (it.b - endpoint).distance < _s * 0.25) {
          touching.add(it);
        }
      }
      if (!touching.contains(newSeg)) touching.add(newSeg);
      final count = touching.length;
      if (count < 2 || count > 3) continue;

      // Outgoing iso-heading per pipe — index into `_isoHeadings`.
      final legs = <int>[];
      for (final p in touching) {
        final v = _outgoing(p, endpoint);
        if (v.distance < 0.01) continue;
        legs.add(_closestIsoHeading(v));
      }
      if (legs.length != count) continue;
      // Drop any duplicate / overlapping pipes (same heading would mean two
      // pipes drawn on top of each other).
      if (legs.toSet().length != legs.length) continue;

      // Existing component at the junction. We REPLACE an existing elbow when
      // the user is upgrading a 2-way junction to a 3-way (drew a branch off
      // an existing corner). A manual component stays untouched.
      final existingIdx = _items.indexWhere((it) =>
          it is _Comp && (it.pos - endpoint).distance < _s * 0.45);
      final existing =
          existingIdx >= 0 ? _items[existingIdx] as _Comp : null;
      final hasExisting = existing != null && !existing.t.isWeld;
      final canReplaceElbow = existing != null && existing.isElbow;

      if (count == 2) {
        if (hasExisting) continue;
        // Two-pipe junction → elbow. Re-derive angle vs leg pair so we can
        // still pick 45° for shallow bends.
        final v1 = _outgoing(touching[0], endpoint);
        final v2 = _outgoing(touching[1], endpoint);
        final dot = v1.dx * v2.dx + v1.dy * v2.dy;
        final cosA = (dot / (v1.distance * v2.distance)).clamp(-1.0, 1.0);
        final angleDeg = math.acos(cosA) * 180 / math.pi;
        if (angleDeg < 100 || angleDeg > 170) continue;
        final elbowKind =
            angleDeg <= 140 ? _Tool.elbow90 : _Tool.elbow45;
        _mutate(() {
          _items.add(_Comp(endpoint, elbowKind, dir: legs[0], dir2: legs[1]));
          _addAutoWeldsAt(endpoint, [legs[0], legs[1]]);
        });
      } else {
        // Three-pipe junction. Look for the colinear pair (legs differing by
        // 3 mod 6) — those are the run; the remaining leg is the branch. If
        // no colinear pair, the geometry is non-standard (e.g. lateral or
        // free-angle) and we let the user place the fitting manually.
        int? runA, runB, branch;
        for (int i = 0; i < 3 && runA == null; i++) {
          for (int j = i + 1; j < 3 && runA == null; j++) {
            if ((legs[i] - legs[j]).abs() == 3) {
              runA = legs[i];
              runB = legs[j];
              branch = legs.firstWhere((l) => l != runA && l != runB);
            }
          }
        }
        if (runA == null || branch == null) continue;
        _mutate(() {
          if (canReplaceElbow) _items.removeAt(existingIdx);
          _items.add(_Comp(endpoint, _Tool.tee, dir: branch!, dir2: runA));
          _addAutoWeldsAt(endpoint, [runA!, runB!, branch]);
        });
      }
    }
  }

  /// Drop a weld dot one half-grid step out along each [dirs] heading from
  /// [junction] so the iso reads with a kropka on every weldable joint. No-op
  /// for headings that already have a weld within tolerance — keeps undo /
  /// redo idempotent and prevents stacking when the user redraws over a
  /// junction. Each weld gets the next global W-NNN number via [_nextWeldNo].
  void _addAutoWeldsAt(Offset junction, List<int> dirs) {
    for (final dir in dirs) {
      if (dir < 0 || dir >= _isoHeadings.length) continue;
      final h = _isoHeadings[dir];
      final pos = Offset(
        junction.dx + h.dx * _s * 0.55,
        junction.dy + h.dy * _s * 0.55,
      );
      final exists = _items.any((it) =>
          it is _Comp && it.t.isWeld && (it.pos - pos).distance < _s * 0.3);
      if (exists) continue;
      _items.add(
        _Comp(pos, _Tool.weld, dir: dir, label: '${_nextWeldNo()}'),
      );
    }
  }

  /// True iff a pipe touches [point] within tolerance — used to gate auto-
  /// weld placement when a physical component is dropped: if there's no pipe
  /// on a given side yet, there's nothing to weld TO, so the weld is held
  /// back until the user draws the pipe.
  bool _pipeTouches(Offset point) {
    final tol = _s * 0.45;
    for (final it in _items) {
      if (it is! _Seg || it.t != _Tool.pipe) continue;
      if ((it.a - point).distance < tol) return true;
      if ((it.b - point).distance < tol) return true;
    }
    return false;
  }

  /// Drop auto-welds on the producesWeld ends of a freshly-placed physical
  /// component. The component sits at [pos] with orientation [dir]; endA is
  /// on the −heading side, endB on the +heading side. Both ends use the same
  /// half-step offset as elbow welds for visual consistency.
  void _addPhysicalCompWelds({
    required Offset pos,
    required int dir,
    required EndConnection endA,
    required EndConnection endB,
  }) {
    final back = (dir + 3) % 6;
    if (endA.producesWeld && _pipeTouches(pos)) {
      _addAutoWeldsAt(pos, [back]);
    }
    if (endB.producesWeld && _pipeTouches(pos)) {
      _addAutoWeldsAt(pos, [dir]);
    }
  }

  /// Walks the segment graph from each reducer outward, rewriting the DN on
  /// every pipe-side reachable through a non-reducer body so the downstream
  /// reads the reducer's outlet DN. Idempotent — re-runs after every mutation
  /// that adds a reducer / pipe.
  ///
  /// Implementation is intentionally minimal: each pipe segment gets a
  /// derived `inferredDnAt(endpoint)` via a BFS that stops at any physical
  /// component carrying `dnOut`. We don't store inferred DN on the segment
  /// (segments are immutable) — `_cutListLines` queries this on demand.
  int? _inferredDnFor(_Seg seg) {
    // Pick whichever endpoint has a known-DN component closest to it via
    // walking the segment graph. Reducer's dnOut wins downstream of its
    // position; an elbow's dn wins as a fallback when reducer is absent.
    final tol = _s * 0.45;
    int? bestDn;
    for (final endpoint in [seg.a, seg.b]) {
      for (final it in _items) {
        if (it is! _Comp) continue;
        if ((it.pos - endpoint).distance >= tol) continue;
        final candidate = it.dnOut ?? it.dn;
        if (candidate != null) {
          bestDn = candidate;
        }
      }
    }
    return bestDn;
  }

  /// Return 0..5 — the index into [_isoHeadings] whose unit vector best
  /// aligns with [v]. Used to convert a free vector (the pipe's outgoing
  /// direction) into one of the 6 iso ends.
  int _closestIsoHeading(Offset v) {
    final len = v.distance;
    if (len < 0.01) return 0;
    final u = Offset(v.dx / len, v.dy / len);
    int best = 0;
    double bestDot = -double.infinity;
    for (int i = 0; i < 6; i++) {
      final h = _isoHeadings[i];
      // Headings are unit-length here, so the dot product = cosine of angle.
      final hDot = h.dx * u.dx + h.dy * u.dy;
      if (hDot > bestDot) {
        bestDot = hDot;
        best = i;
      }
    }
    return best;
  }

  /// Vector pointing from [junction] outward along [seg].
  Offset _outgoing(_Seg seg, Offset junction) {
    final fromA = (seg.a - junction).distance;
    final fromB = (seg.b - junction).distance;
    if (fromA <= fromB) {
      return seg.b - seg.a; // junction is near a → outgoing is a→b
    } else {
      return seg.a - seg.b; // junction is near b → outgoing is b→a
    }
  }

  // ── next weld number ────────────────────────────────────────────────────────
  int _nextWeldNo() {
    int best = 0;
    for (final it in _items) {
      if (it is _Comp && it.t.isWeld) {
        final n = int.tryParse(it.label) ?? 0;
        if (n > best) best = n;
      }
    }
    return best + 1;
  }

  // ── tap ─────────────────────────────────────────────────────────────────────
  Future<void> _tapUp(TapUpDetails d) async {
    if (_panMode) return;
    final raw = _toWorld(d.localPosition);

    if (_tool.isLine) {
      final hit = _nearestSeg(raw);
      if (hit >= 0) {
        final seg = _items[hit] as _Seg;
        final res = await _askCalc(seg.calc,
            slope: seg.slope,
            insulated: seg.insulated,
            segA: seg.a,
            segB: seg.b);
        if (res != null && mounted) {
          _push();
          if (res.remove) {
            _mutate(() => _items[hit] =
                seg.withCalc(null).withSlope('').withInsulated(false));
          } else {
            _mutate(() => _items[hit] = seg
                .withCalc(res.calc)
                .withSlope(res.slope)
                .withInsulated(res.insulated));
          }
        }
      }
      return;
    }

    if (_tool.isText) {
      final hitNote = _items.indexWhere(
        (it) => it is _Note && (it.pos - raw).distance < _s * 1.2,
      );
      if (hitNote >= 0) {
        final note = _items[hitNote] as _Note;
        final txt = await _askText(note.text);
        if (txt != null && mounted) {
          _push();
          _mutate(() {
            if (txt.isEmpty) {
              _items.removeAt(hitNote);
            } else {
              _items[hitNote] = note.withText(txt);
            }
          });
        }
      } else {
        final txt = await _askText('');
        if (txt != null && txt.isNotEmpty && mounted) {
          _push();
          _mutate(() => _items.add(_Note(_snap(raw), txt)));
        }
      }
      return;
    }

    final pt = _snap(raw);
    final idx = _items.indexWhere(
      (it) => it is _Comp && (it.pos - pt).distance < _s * 0.45,
    );
    if (idx >= 0) {
      // Elbows open a spec sheet (DN / type / CTE) — that's the data
      // CUT-list math needs. Tap-rotate stays available via long-press
      // (long-press already deletes; we keep simple double-tap rotation
      // intentional via a second tap on a non-elbow comp). For non-elbow
      // components, simple tap rotates as before.
      final comp = _items[idx] as _Comp;
      if (comp.isElbow) {
        await _editElbowSpec(idx);
        return;
      }
      _push();
      _mutate(() => _items[idx] = comp.rotate());
      return;
    }

    if (_tool == _Tool.instrument) {
      final tag = await _askText('', instrument: true);
      if (tag == null || !mounted) return;
      _push();
      _mutate(() => _items.add(_Comp(pt, _tool, label: tag)));
      return;
    }

    if (_tool == _Tool.reducer) {
      final spec = await _askReducerSpec();
      if (spec == null || !mounted) return;
      _push();
      _mutate(() {
        _items.add(
          _Comp(pt, _tool, label: spec.label).withPhysicalSpec(
            dn: spec.dnIn,
            dnOut: spec.dnOut,
            physicalLengthMm: spec.physicalLengthMm,
            endA: EndConnection.buttWeld,
            endB: EndConnection.buttWeld,
          ),
        );
        _addPhysicalCompWelds(
          pos: pt,
          dir: 0,
          endA: EndConnection.buttWeld,
          endB: EndConnection.buttWeld,
        );
      });
      return;
    }

    if (_tool == _Tool.flange || _tool == _Tool.blindFlange) {
      final spec = await _askFlangeSpec(kind: _tool);
      if (spec == null || !mounted) return;
      _push();
      _mutate(() {
        _items.add(
          _Comp(pt, _tool, label: 'DN${spec.dn} · ${spec.type.code}')
              .withPhysicalSpec(
            dn: spec.dn,
            physicalLengthMm: spec.physicalLengthMm,
            endA: spec.type,
            endB: EndConnection.none,
          ),
        );
        _addPhysicalCompWelds(
          pos: pt,
          dir: 0,
          endA: spec.type,
          endB: EndConnection.none,
        );
      });
      return;
    }

    if (_tool == _Tool.cap) {
      final spec = await _askCapSpec();
      if (spec == null || !mounted) return;
      _push();
      _mutate(() {
        _items.add(
          _Comp(pt, _tool, label: 'DN${spec.dn}').withPhysicalSpec(
            dn: spec.dn,
            physicalLengthMm: spec.physicalLengthMm,
            endA: EndConnection.buttWeld,
            endB: EndConnection.none,
          ),
        );
        _addPhysicalCompWelds(
          pos: pt,
          dir: 0,
          endA: EndConnection.buttWeld,
          endB: EndConnection.none,
        );
      });
      return;
    }

    if (_tool == _Tool.gateValve ||
        _tool == _Tool.ballValve ||
        _tool == _Tool.checkValve ||
        _tool == _Tool.globeValve ||
        _tool == _Tool.butterflyValve) {
      final spec = await _askValveSpec(kind: _tool);
      if (spec == null || !mounted) return;
      _push();
      _mutate(() {
        _items.add(
          _Comp(pt, _tool, label: 'DN${spec.dn}').withPhysicalSpec(
            dn: spec.dn,
            physicalLengthMm: spec.physicalLengthMm,
            endA: spec.endA,
            endB: spec.endB,
          ),
        );
        _addPhysicalCompWelds(
          pos: pt,
          dir: 0,
          endA: spec.endA,
          endB: spec.endB,
        );
      });
      return;
    }

    _push();
    _mutate(() {
      final label = _tool.isWeld ? '${_nextWeldNo()}' : '';
      _items.add(_Comp(pt, _tool, label: label));
    });
  }

  int _nearestSeg(Offset raw) {
    int best = -1;
    double bestD = _s * 0.5;
    for (int i = 0; i < _items.length; i++) {
      final it = _items[i];
      if (it is _Seg) {
        final dist = _distToSeg(raw, it.a, it.b);
        if (dist < bestD) {
          bestD = dist;
          best = i;
        }
      }
    }
    return best;
  }

  void _longPress(LongPressStartDetails d) {
    if (_panMode) return;
    final raw = _toWorld(d.localPosition);
    final pt = _snap(raw);
    final compIdx = _items.indexWhere(
      (it) => it is _Comp && (it.pos - pt).distance < _s * 0.6,
    );
    if (compIdx >= 0) {
      _push();
      _mutate(() => _items.removeAt(compIdx));
      _toastDeleted(_tr('Komponent usunięty', 'Component deleted'));
      return;
    }
    final noteIdx = _items.indexWhere(
      (it) => it is _Note && (it.pos - raw).distance < _s * 1.4,
    );
    if (noteIdx >= 0) {
      _push();
      _mutate(() => _items.removeAt(noteIdx));
      _toastDeleted(_tr('Notatka usunięta', 'Note deleted'));
      return;
    }
    final segIdx = _nearestSeg(raw);
    if (segIdx >= 0) {
      _push();
      _mutate(() => _items.removeAt(segIdx));
      _toastDeleted(_tr('Segment usunięty', 'Segment deleted'));
    }
  }

  // Long-press silently removes whichever element sits under the finger —
  // easy to trigger by accident with gloves on. Surface a brief SnackBar
  // with an Undo action so the gesture isn't a silent data loss.
  void _toastDeleted(String label) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(label),
        duration: const Duration(seconds: 4),
        action: SnackBarAction(
          label: _tr('Cofnij', 'Undo'),
          onPressed: _undoAction,
        ),
      ));
  }

  // ── dimension + cut-calc dialog ─────────────────────────────────────────────
  Future<_CalcResult?> _askCalc(_CutCalc? current,
      {String slope = '',
      bool insulated = false,
      Offset? segA,
      Offset? segB}) async {
    final isoCtrl = TextEditingController(text: current?.iso ?? '');
    final slopeCtrl = TextEditingController(text: slope);
    bool insulFlag = insulated;
    DimRef refLocal = current?.ref ?? DimRef.centreToCentre;
    final rows = <(TextEditingController name, TextEditingController value)>[];
    for (final d in current?.deducts ?? const <_Deduct>[]) {
      rows.add((
        TextEditingController(text: d.name),
        TextEditingController(text: d.value),
      ));
    }
    bool calcMode = current?.hasDeducts ?? false;

    // Wrap the whole dialog flow in try/finally so the controllers are
    // disposed deterministically when the user taps OK, Cancel or the back
    // gesture. Previously each open/close leaked 2-N controllers; over a
    // long session that's measurable jank.
    try {
      return await showDialog<_CalcResult>(
      context: context,
      builder: (dctx) => StatefulBuilder(
        builder: (dctx, setLocal) {
          final cs = Theme.of(dctx).colorScheme;

          // Live evaluation.
          double? isoMm;
          try {
            if (isoCtrl.text.trim().isNotEmpty) {
              isoMm = parseIsoExpression(isoCtrl.text);
            }
          } catch (_) {}
          double deductSum = 0;
          for (final r in rows) {
            if (r.$2.text.trim().isEmpty) continue;
            try {
              deductSum += parseIsoExpression(r.$2.text);
            } catch (_) {}
          }
          final cutMm = (isoMm == null) ? null : isoMm - deductSum;

          void rebuild() => setLocal(() {});

          return AlertDialog(
            title: Text(_tr('Wymiar / cięcie odcinka',
                'Segment dimension / cut')),
            content: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // ── Mode switch ──────────────────────────────────────────
                    SegmentedButton<bool>(
                      segments: [
                        ButtonSegment(
                            value: false,
                            label: Text(_tr('Wymiar', 'Dimension')),
                            icon: const Icon(Icons.straighten)),
                        ButtonSegment(
                            value: true,
                            label: Text(_tr('Oblicz cięcie', 'Cut calc')),
                            icon: const Icon(Icons.content_cut)),
                      ],
                      selected: {calcMode},
                      onSelectionChanged: (s) =>
                          setLocal(() => calcMode = s.first),
                    ),
                    const SizedBox(height: 14),

                    // ── ISO field (used in both modes) ───────────────────────
                    Text(
                      calcMode
                          ? _tr('Wymiar ISO segmentu (czoło-czoło / oś-oś)',
                              'ISO dimension (face-to-face / centre-to-centre)')
                          : _tr('Wymiar odcinka', 'Segment dimension'),
                      style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: cs.onSurfaceVariant,
                          letterSpacing: 0.4),
                    ),
                    const SizedBox(height: 4),
                    TextField(
                      controller: isoCtrl,
                      autofocus: true,
                      keyboardType: TextInputType.text,
                      decoration: InputDecoration(
                        hintText: _tr('np. 1500 lub 3000+525-80',
                            'e.g. 1500 or 3000+525-80'),
                        suffixText: 'mm',
                      ),
                      onChanged: (_) => rebuild(),
                    ),

                    if (calcMode) ...[
                      const SizedBox(height: 14),
                      Row(
                        children: [
                          Text(
                            _tr('Odejmij komponenty', 'Subtract components'),
                            style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: cs.onSurfaceVariant,
                                letterSpacing: 0.4),
                          ),
                          const Spacer(),
                          Text(
                            '${rows.length}',
                            style: TextStyle(
                                fontSize: 11, color: cs.onSurfaceVariant),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      for (var i = 0; i < rows.length; i++)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: Row(
                            children: [
                              Text('−',
                                  style: TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.w800,
                                      color: cs.tertiary)),
                              const SizedBox(width: 6),
                              Expanded(
                                flex: 5,
                                child: TextField(
                                  controller: rows[i].$1,
                                  decoration: InputDecoration(
                                    isDense: true,
                                    hintText: _tr('komponent',
                                        'component'),
                                  ),
                                  onChanged: (_) => rebuild(),
                                ),
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                flex: 4,
                                child: TextField(
                                  controller: rows[i].$2,
                                  keyboardType: TextInputType.text,
                                  decoration: InputDecoration(
                                    isDense: true,
                                    hintText: '76',
                                    suffixText: 'mm',
                                  ),
                                  onChanged: (_) => rebuild(),
                                ),
                              ),
                              IconButton(
                                tooltip: _tr('Usuń komponent', 'Remove component'),
                                icon: const Icon(Icons.close, size: 18),
                                constraints: const BoxConstraints(
                                    minWidth: 48, minHeight: 48),
                                onPressed: () => setLocal(() {
                                  rows.removeAt(i);
                                }),
                              ),
                            ],
                          ),
                        ),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          TextButton.icon(
                            icon: const Icon(Icons.add, size: 18),
                            label: Text(
                                _tr('Dodaj komponent', 'Add component')),
                            onPressed: () => setLocal(() {
                              rows.add((
                                TextEditingController(),
                                TextEditingController(),
                              ));
                            }),
                          ),
                          TextButton.icon(
                            icon: const Icon(Icons.menu_book, size: 18),
                            label: Text(
                                _tr('Katalog ASME', 'ASME catalog')),
                            onPressed: () async {
                              final entry =
                                  await _pickFromCatalog(dctx);
                              if (entry != null) {
                                setLocal(() {
                                  rows.add((
                                    TextEditingController(text: entry.name),
                                    TextEditingController(
                                        text: entry.mm.toString()),
                                  ));
                                });
                              }
                            },
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),

                      // ── Live result card ───────────────────────────────────
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: cs.tertiaryContainer.withValues(alpha: 0.4),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                              color: cs.tertiary.withValues(alpha: 0.5)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Row(
                              children: [
                                Text(_tr('ISO', 'ISO'),
                                    style: TextStyle(
                                        fontSize: 11,
                                        color: cs.onSurfaceVariant)),
                                const Spacer(),
                                Text(
                                  isoMm == null
                                      ? '—'
                                      : '${isoMm.toStringAsFixed(1)} mm',
                                  style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w700,
                                      color: cs.onSurface),
                                ),
                              ],
                            ),
                            if (rows.isNotEmpty) ...[
                              const SizedBox(height: 4),
                              Row(
                                children: [
                                  Text(_tr('Suma odejmowań', 'Total deducts'),
                                      style: TextStyle(
                                          fontSize: 11,
                                          color: cs.onSurfaceVariant)),
                                  const Spacer(),
                                  Text(
                                    '− ${deductSum.toStringAsFixed(1)} mm',
                                    style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w700,
                                        color: cs.tertiary),
                                  ),
                                ],
                              ),
                            ],
                            const Divider(height: 18),
                            // Headline result: stacked label + large number so
                            // the cut value never gets crammed by the label on
                            // narrow dialogs.
                            Text(
                              _tr('CUT — rura do ucięcia',
                                  'CUT — pipe to saw'),
                              style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: cs.onSurfaceVariant,
                                  letterSpacing: 0.6),
                            ),
                            const SizedBox(height: 6),
                            Center(
                              child: Text(
                                cutMm == null
                                    ? '—'
                                    : '${cutMm.toStringAsFixed(1)} mm',
                                style: TextStyle(
                                    fontSize: 26,
                                    fontWeight: FontWeight.w900,
                                    color: (cutMm != null && cutMm < 0)
                                        ? cs.error
                                        : cs.primary,
                                    letterSpacing: -0.5,
                                    height: 1.1),
                              ),
                            ),
                            if (cutMm != null && cutMm < 0)
                              Padding(
                                padding: const EdgeInsets.only(top: 4),
                                child: Text(
                                  _tr(
                                      'Komponenty dłuższe niż ISO — sprawdź wymiary.',
                                      'Components longer than ISO — check dimensions.'),
                                  style: TextStyle(
                                      fontSize: 11, color: cs.error),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ] else if (isoMm != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        '= ${isoMm.toStringAsFixed(1)} mm',
                        style: const TextStyle(
                            fontSize: 14, fontWeight: FontWeight.w800),
                      ),
                    ],

                    const SizedBox(height: 8),
                    Text(
                      _tr(
                          'Możesz wpisać działanie: + − × i nawiasy.',
                          'You can type an expression: + − × and brackets.'),
                      style: TextStyle(
                          fontSize: 11, color: cs.onSurfaceVariant),
                    ),
                    const SizedBox(height: 14),
                    // Slope tag — only relevant for off-axis lines (drains,
                    // vents, condensate falls). Left blank for level pipe.
                    Text(
                      _tr('Spadek (drain / vent)', 'Slope (drain / vent)'),
                      style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: cs.onSurfaceVariant,
                          letterSpacing: 0.4),
                    ),
                    const SizedBox(height: 4),
                    TextField(
                      controller: slopeCtrl,
                      decoration: InputDecoration(
                        hintText: _tr(
                            'np. 1:100, FALL 25mm, 5° w dół',
                            'e.g. 1:100, FALL 25mm, 5° down'),
                        isDense: true,
                      ),
                    ),
                    // ── DimRef picker — only when a physical-length component
                    // (flange, cap, valve, reducer…) sits on at least one end
                    // of this segment. For pure axial-on-both-sides runs the
                    // designer always dimensions centre-to-centre, so we hide
                    // the row entirely to avoid noise.
                    Builder(builder: (_) {
                      bool endHasPhysical(Offset? p) {
                        if (p == null) return false;
                        const physicalTools = <_Tool>{
                          _Tool.reducer,
                          _Tool.flange,
                          _Tool.blindFlange,
                          _Tool.cap,
                          _Tool.gateValve,
                          _Tool.ballValve,
                          _Tool.checkValve,
                          _Tool.globeValve,
                          _Tool.butterflyValve,
                        };
                        for (final it in _items) {
                          if (it is! _Comp) continue;
                          if (!physicalTools.contains(it.t)) continue;
                          if ((it.pos - p).distance < _s * 0.45) return true;
                        }
                        return false;
                      }

                      final showPicker =
                          endHasPhysical(segA) || endHasPhysical(segB);
                      if (!showPicker) return const SizedBox.shrink();
                      final cs2 = Theme.of(dctx).colorScheme;
                      return Padding(
                        padding: const EdgeInsets.only(top: 10),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _tr('Wymiar ISO odnosi się do',
                                  'ISO dimension is measured between'),
                              style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: cs2.onSurfaceVariant,
                                  letterSpacing: 0.4),
                            ),
                            const SizedBox(height: 4),
                            Wrap(
                              spacing: 6,
                              runSpacing: 4,
                              children: [
                                for (final r in DimRef.values)
                                  ChoiceChip(
                                    label: Text(r.code),
                                    selected: refLocal == r,
                                    onSelected: (_) =>
                                        setLocal(() => refLocal = r),
                                  ),
                              ],
                            ),
                          ],
                        ),
                      );
                    }),
                    const SizedBox(height: 6),
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      controlAffinity: ListTileControlAffinity.leading,
                      title: Text(_tr('Rura izolowana', 'Insulated pipe'),
                          style: const TextStyle(fontSize: 13)),
                      value: insulFlag,
                      onChanged: (v) => setLocal(() => insulFlag = v ?? false),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              if (current != null)
                TextButton(
                  onPressed: () =>
                      Navigator.pop(dctx, const _CalcResult.removed()),
                  child: Text(_tr('Usuń', 'Remove'),
                      style: TextStyle(color: Theme.of(dctx).colorScheme.error)),
                ),
              TextButton(
                onPressed: () => Navigator.pop(dctx, null),
                child: Text(_tr('Anuluj', 'Cancel')),
              ),
              ElevatedButton(
                onPressed: () {
                  final iso = isoCtrl.text.trim();
                  if (iso.isEmpty) {
                    Navigator.pop(dctx, const _CalcResult.removed());
                    return;
                  }
                  final deducts = <_Deduct>[];
                  if (calcMode) {
                    for (final r in rows) {
                      final v = r.$2.text.trim();
                      if (v.isEmpty) continue;
                      deducts.add(_Deduct(r.$1.text.trim(), v));
                    }
                  }
                  Navigator.pop(
                      dctx,
                      _CalcResult.set(
                          _CutCalc(iso,
                              deducts: List.unmodifiable(deducts),
                              ref: refLocal),
                          slope: slopeCtrl.text.trim(),
                          insulated: insulFlag,
                          ref: refLocal));
                },
                child: const Text('OK'),
              ),
            ],
          );
        },
      ),
    );
    } finally {
      isoCtrl.dispose();
      slopeCtrl.dispose();
      for (final r in rows) {
        r.$1.dispose();
        r.$2.dispose();
      }
    }
  }

  // ── free text / instrument tag dialog ───────────────────────────────────────
  Future<String?> _askText(String current, {bool instrument = false}) async {
    final ctrl = TextEditingController(text: current);
    try {
      return await showDialog<String>(
      context: context,
      builder: (dctx) => AlertDialog(
        title: Text(instrument
            ? _tr('Oznaczenie instrumentu', 'Instrument tag')
            : _tr('Tekst na rysunku', 'Drawing text')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: ctrl,
              autofocus: true,
              textCapitalization: TextCapitalization.characters,
              decoration: InputDecoration(
                hintText: instrument
                    ? _tr('np. PI-01, TI-12', 'e.g. PI-01, TI-12')
                    : _tr('np. nr linii, EL +100.000',
                        'e.g. line no., EL +100.000'),
              ),
              onSubmitted: (v) => Navigator.pop(dctx, v.trim()),
            ),
            if (!instrument)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  _tr('Numer linii, rzędna, klasa rurociągu, notatka montażowa.',
                      'Line number, elevation, pipe class, erection note.'),
                  style: TextStyle(
                      fontSize: 11,
                      color: Theme.of(dctx).colorScheme.onSurfaceVariant),
                ),
              ),
          ],
        ),
        actions: [
          if (current.isNotEmpty)
            TextButton(
              onPressed: () => Navigator.pop(dctx, ''),
              child: Text(_tr('Usuń', 'Remove'),
                  style: TextStyle(color: Theme.of(dctx).colorScheme.error)),
            ),
          TextButton(
            onPressed: () => Navigator.pop(dctx, null),
            child: Text(_tr('Anuluj', 'Cancel')),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(dctx, ctrl.text.trim()),
            child: const Text('OK'),
          ),
        ],
      ),
    );
    } finally {
      ctrl.dispose();
    }
  }

  /// Sheet that lets the user set DN + elbow subtype + CTE on a single
  /// elbow component. CTE auto-fills from the standard ASME table whenever
  /// DN or subtype changes, but stays user-editable for non-standard parts.
  Future<void> _editElbowSpec(int idx) async {
    final comp = _items[idx] as _Comp;
    int dn = comp.dn ?? 50;
    _ElbowSubtype subtype = comp.elbowSubtype ??
        (comp.t == _Tool.elbow45 ? _ElbowSubtype.lr45 : _ElbowSubtype.lr90);
    final cteCtrl = TextEditingController(
        text: (comp.cteMm ?? _stdCte(dn, subtype)).toString());

    void refillCte() {
      cteCtrl.text = _stdCte(dn, subtype).toString();
    }

    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (sheetCtx) {
        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(sheetCtx).viewInsets.bottom,
          ),
          child: StatefulBuilder(
            builder: (sheetCtx, setLocal) {
              final cs = Theme.of(sheetCtx).colorScheme;
              final row = closestByDn(dn);
              return Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _tr('Specyfikacja kolanka', 'Elbow spec'),
                      style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w900,
                          color: cs.onSurface),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _tr(
                        'CTE = wymiar od osi kolanka do czoła. Odejmowany od ISO rury dotykającej kolanka.',
                        'CTE = centre-to-end. Auto-deducted from any pipe touching this elbow.',
                      ),
                      style: TextStyle(
                          fontSize: 11,
                          color: cs.onSurfaceVariant,
                          height: 1.4),
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(_tr('DN (rozmiar)', 'DN (size)'),
                                  style: TextStyle(
                                      fontSize: 11,
                                      color: cs.onSurfaceVariant)),
                              DropdownButton<int>(
                                isExpanded: true,
                                value: dn,
                                items: const [
                                  15, 20, 25, 32, 40, 50, 65, 80, 100,
                                  125, 150, 200, 250, 300, 350, 400, 450, 500, 600,
                                ]
                                    .map((d) => DropdownMenuItem(
                                          value: d,
                                          child: Text('DN$d  ·  ${closestByDn(d).nps}"'),
                                        ))
                                    .toList(),
                                onChanged: (v) {
                                  if (v == null) return;
                                  setLocal(() {
                                    dn = v;
                                    refillCte();
                                  });
                                },
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(_tr('Typ', 'Type'),
                                  style: TextStyle(
                                      fontSize: 11,
                                      color: cs.onSurfaceVariant)),
                              DropdownButton<_ElbowSubtype>(
                                isExpanded: true,
                                value: subtype,
                                items: _ElbowSubtype.values
                                    .map((s) => DropdownMenuItem(
                                          value: s,
                                          child: Text(s.label),
                                        ))
                                    .toList(),
                                onChanged: (v) {
                                  if (v == null) return;
                                  setLocal(() {
                                    subtype = v;
                                    refillCte();
                                  });
                                },
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: cteCtrl,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: false),
                      decoration: InputDecoration(
                        labelText: _tr('CTE — oś do czoła', 'CTE — centre to end'),
                        helperText: _tr(
                          'Standard ASME: ${_stdCte(dn, subtype)} mm dla DN$dn ${subtype.label}',
                          'ASME standard: ${_stdCte(dn, subtype)} mm for DN$dn ${subtype.label}',
                        ),
                        suffixText: 'mm',
                      ),
                    ),
                    const SizedBox(height: 4),
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(
                        '${row.nps}" · ${subtype.label}',
                        style: TextStyle(
                          fontSize: 11,
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        TextButton.icon(
                          onPressed: () => Navigator.pop(sheetCtx, false),
                          icon: const Icon(Icons.rotate_left),
                          label: Text(_tr('Obróć (60°)', 'Rotate (60°)')),
                        ),
                        Row(
                          children: [
                            TextButton(
                              onPressed: () => Navigator.pop(sheetCtx, null),
                              child: Text(_tr('Anuluj', 'Cancel')),
                            ),
                            const SizedBox(width: 8),
                            ElevatedButton(
                              onPressed: () => Navigator.pop(sheetCtx, true),
                              child: const Text('OK'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ],
                ),
              );
            },
          ),
        );
      },
    );

    if (!mounted) return;
    if (saved == null) {
      cteCtrl.dispose();
      return;
    }
    _push();
    if (saved == false) {
      // "Rotate" branch — preserve spec, rotate orientation.
      _mutate(() => _items[idx] = comp.rotate());
      cteCtrl.dispose();
      return;
    }
    final cteParsed = int.tryParse(cteCtrl.text.trim()) ?? _stdCte(dn, subtype);
    _mutate(() => _items[idx] = comp.withElbowSpec(
          dn: dn,
          subtype: subtype,
          cte: cteParsed,
        ));
    cteCtrl.dispose();
  }

  /// Reducer face-to-face defaults pulled from ASME B16.9 concentric reducer
  /// table (typical, NPS 1/2 → 12). Default-fills the length field so the
  /// monter doesn't type it on every placement.
  static const Map<int, int> _reducerLenDefault = {
    15: 38, 20: 38, 25: 51, 32: 51, 40: 64, 50: 76, 65: 89,
    80: 89, 100: 102, 150: 140, 200: 152, 250: 178, 300: 203,
  };

  Future<({int dnIn, int dnOut, int physicalLengthMm, String label})?>
      _askReducerSpec() async {
    int from = 100;
    int to = 50;
    // 0 = concentric, 1 = eccentric flat-top (pump discharge / steam main),
    // 2 = eccentric flat-bottom (horizontal pump suction — prevents vapor
    // pockets per API 686 §6.5.2). Suffixed to the label so the painter and
    // BOM both see the geometry choice.
    int eccentric = 0;
    final lenCtrl = TextEditingController(
        text: '${_reducerLenDefault[from] ?? 100}');
    try {
      return await showModalBottomSheet<
          ({int dnIn, int dnOut, int physicalLengthMm, String label})>(
        context: context,
        backgroundColor: Theme.of(context).colorScheme.surface,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
        ),
        isScrollControlled: true,
        builder: (bctx) {
          final cs = Theme.of(bctx).colorScheme;
          return StatefulBuilder(
            builder: (bctx, setLocal) => SafeArea(
              child: Padding(
                padding: EdgeInsets.only(
                  left: 16,
                  right: 16,
                  top: 16,
                  bottom: 16 + MediaQuery.of(bctx).viewInsets.bottom,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(_tr('Specyfikacja redukcji', 'Reducer spec'),
                        style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                            color: cs.onSurface)),
                    const SizedBox(height: 8),
                    Row(children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(_tr('z (większy)', 'from (larger)'),
                                style: TextStyle(
                                    fontSize: 10,
                                    color: cs.onSurfaceVariant)),
                            DropdownButton<int>(
                              isExpanded: true,
                              value: from,
                              items: const [15, 20, 25, 32, 40, 50, 65, 80, 100, 150, 200, 250, 300]
                                  .map((d) => DropdownMenuItem(
                                      value: d, child: Text('DN$d')))
                                  .toList(),
                              onChanged: (v) {
                                if (v == null) return;
                                setLocal(() {
                                  from = v;
                                  lenCtrl.text =
                                      '${_reducerLenDefault[v] ?? 100}';
                                });
                              },
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      Text('→',
                          style: TextStyle(
                              fontSize: 22,
                              color: cs.primary,
                              fontWeight: FontWeight.bold)),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(_tr('do (mniejszy)', 'to (smaller)'),
                                style: TextStyle(
                                    fontSize: 10,
                                    color: cs.onSurfaceVariant)),
                            DropdownButton<int>(
                              isExpanded: true,
                              value: to,
                              items: const [15, 20, 25, 32, 40, 50, 65, 80, 100, 150, 200, 250, 300]
                                  .map((d) => DropdownMenuItem(
                                      value: d, child: Text('DN$d')))
                                  .toList(),
                              onChanged: (v) {
                                if (v != null) setLocal(() => to = v);
                              },
                            ),
                          ],
                        ),
                      ),
                    ]),
                    const SizedBox(height: 12),
                    Text(_tr('Długość redukcji (mm)', 'Reducer length (mm)'),
                        style: TextStyle(
                            fontSize: 11, color: cs.onSurfaceVariant)),
                    const SizedBox(height: 4),
                    TextField(
                      controller: lenCtrl,
                      keyboardType: const TextInputType.numberWithOptions(
                          decimal: false, signed: false),
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                        LengthLimitingTextInputFormatter(4),
                      ],
                      decoration: InputDecoration(
                        isDense: true,
                        hintText: _tr('np. 76', 'e.g. 76'),
                        helperText: _tr(
                            'Zakres 1–9999 mm. Domyślne z ASME B16.9 — popraw jeśli inna klasa.',
                            'Range 1–9999 mm. Defaults from ASME B16.9 — adjust for other classes.'),
                        helperMaxLines: 2,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(_tr('Typ', 'Type'),
                        style: TextStyle(
                            fontSize: 11, color: cs.onSurfaceVariant)),
                    const SizedBox(height: 4),
                    SegmentedButton<int>(
                      segments: [
                        ButtonSegment(
                            value: 0,
                            label: Text(_tr('Koncentryczna', 'Concentric'),
                                style: const TextStyle(fontSize: 11))),
                        ButtonSegment(
                            value: 1,
                            label: Text(_tr('Ekscent. ↑', 'Ecc. flat top'),
                                style: const TextStyle(fontSize: 11))),
                        ButtonSegment(
                            value: 2,
                            label: Text(_tr('Ekscent. ↓', 'Ecc. flat bot'),
                                style: const TextStyle(fontSize: 11))),
                      ],
                      selected: {eccentric},
                      onSelectionChanged: (s) =>
                          setLocal(() => eccentric = s.first),
                      showSelectedIcon: false,
                    ),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                          onPressed: () => Navigator.pop(bctx, null),
                          child: Text(_tr('Anuluj', 'Cancel')),
                        ),
                        const SizedBox(width: 8),
                        ElevatedButton(
                          onPressed: () {
                            final hi = from > to ? from : to;
                            final lo = from > to ? to : from;
                            final len = int.tryParse(lenCtrl.text.trim());
                            if (len == null || len <= 0) return;
                            // Suffix only when eccentric — keeps the legacy
                            // "DNx→DNy · L mm" label untouched for concentric
                            // so the BOM hashes (which split on label) do not
                            // shift for existing drawings.
                            final eccSfx = switch (eccentric) {
                              1 => ' · ECC↑',
                              2 => ' · ECC↓',
                              _ => '',
                            };
                            Navigator.pop(bctx, (
                              dnIn: hi,
                              dnOut: lo,
                              physicalLengthMm: len,
                              label: 'DN$hi→DN$lo · $len mm$eccSfx',
                            ));
                          },
                          child: const Text('OK'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      );
    } finally {
      lenCtrl.dispose();
    }
  }

  static const List<int> _dnChoices = [
    15, 20, 25, 32, 40, 50, 65, 80, 100, 150, 200, 250, 300
  ];

  Future<({int dn, int physicalLengthMm, EndConnection type})?> _askFlangeSpec({
    required _Tool kind,
  }) async {
    int dn = 50;
    EndConnection type =
        kind == _Tool.blindFlange ? EndConnection.slipOn : EndConnection.weldNeck;
    final lenCtrl = TextEditingController(text: '${_flangeFaceDefault[dn] ?? 24}');
    try {
      return await showModalBottomSheet<
          ({int dn, int physicalLengthMm, EndConnection type})>(
        context: context,
        backgroundColor: Theme.of(context).colorScheme.surface,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
        ),
        isScrollControlled: true,
        builder: (bctx) {
          final cs = Theme.of(bctx).colorScheme;
          return StatefulBuilder(
            builder: (bctx, setLocal) => SafeArea(
              child: Padding(
                padding: EdgeInsets.only(
                  left: 16,
                  right: 16,
                  top: 16,
                  bottom: 16 + MediaQuery.of(bctx).viewInsets.bottom,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      kind == _Tool.blindFlange
                          ? _tr('Kołnierz ślepy', 'Blind flange')
                          : _tr('Kołnierz', 'Flange'),
                      style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          color: cs.onSurface),
                    ),
                    const SizedBox(height: 8),
                    Text(_tr('Średnica nominalna', 'Nominal diameter'),
                        style: TextStyle(
                            fontSize: 11, color: cs.onSurfaceVariant)),
                    DropdownButton<int>(
                      isExpanded: true,
                      value: dn,
                      items: _dnChoices
                          .map((d) => DropdownMenuItem(
                              value: d, child: Text('DN$d')))
                          .toList(),
                      onChanged: (v) {
                        if (v == null) return;
                        setLocal(() {
                          dn = v;
                          lenCtrl.text = '${_flangeFaceDefault[v] ?? 24}';
                        });
                      },
                    ),
                    const SizedBox(height: 10),
                    Text(_tr('Typ połączenia', 'Connection type'),
                        style: TextStyle(
                            fontSize: 11, color: cs.onSurfaceVariant)),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        for (final t in [
                          EndConnection.weldNeck,
                          EndConnection.slipOn,
                          EndConnection.socketWeld,
                          EndConnection.threaded,
                          EndConnection.lapJoint,
                        ])
                          ChoiceChip(
                            label: Text(t.code,
                                style: const TextStyle(fontSize: 11)),
                            selected: t == type,
                            onSelected: (_) => setLocal(() => type = t),
                          ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Text(_tr('Długość czoła (mm)', 'Face length (mm)'),
                        style: TextStyle(
                            fontSize: 11, color: cs.onSurfaceVariant)),
                    TextField(
                      controller: lenCtrl,
                      keyboardType: const TextInputType.numberWithOptions(
                          decimal: false, signed: false),
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                        LengthLimitingTextInputFormatter(4),
                      ],
                      decoration: InputDecoration(
                        isDense: true,
                        hintText: _tr('np. 24', 'e.g. 24'),
                        helperText: _tr(
                            'Zakres 1–9999 mm. Domyślne z ASME B16.5 — popraw jeśli inna klasa.',
                            'Range 1–9999 mm. Defaults from ASME B16.5 — adjust for other classes.'),
                        helperMaxLines: 2,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                          onPressed: () => Navigator.pop(bctx, null),
                          child: Text(_tr('Anuluj', 'Cancel')),
                        ),
                        const SizedBox(width: 8),
                        ElevatedButton(
                          onPressed: () {
                            final raw = lenCtrl.text.trim();
                            final len = int.tryParse(raw);
                            // Generic "1–9999 mm" told the fitter what was
                            // wrong but not which mistake they made. Split
                            // the three real cases — empty / non-numeric /
                            // out-of-range — and remind them of the ASME
                            // default so they can just press it and move on.
                            String? lenError;
                            if (raw.isEmpty) {
                              lenError = _tr(
                                  'Wpisz długość czoła kołnierza. Domyślnie ${_flangeFaceDefault[dn] ?? 24} mm.',
                                  'Enter the flange face length. Default is ${_flangeFaceDefault[dn] ?? 24} mm.');
                            } else if (len == null) {
                              lenError = _tr(
                                  'Same cyfry — bez jednostek ani kropek.',
                                  'Digits only — no units or decimal points.');
                            } else if (len <= 0) {
                              lenError = _tr(
                                  'Długość musi być większa od zera.',
                                  'Length must be greater than zero.');
                            } else if (len > 9999) {
                              lenError = _tr(
                                  'Maksymalnie 9999 mm — sprawdź, czy nie podałeś średnicy zamiast długości.',
                                  'Max 9999 mm — check you did not enter the diameter instead of the length.');
                            }
                            if (lenError != null) {
                              ScaffoldMessenger.of(bctx)
                                ..clearSnackBars()
                                ..showSnackBar(SnackBar(
                                  content: Text(lenError),
                                  behavior: SnackBarBehavior.floating,
                                  duration: const Duration(seconds: 3),
                                ));
                              return;
                            }
                            Navigator.pop(bctx, (
                              dn: dn,
                              physicalLengthMm: len!,
                              type: type,
                            ));
                          },
                          child: const Text('OK'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      );
    } finally {
      lenCtrl.dispose();
    }
  }

  Future<({
    int dn,
    int physicalLengthMm,
    EndConnection endA,
    EndConnection endB,
  })?> _askValveSpec({required _Tool kind}) async {
    int dn = 50;
    EndConnection endA = EndConnection.buttWeld;
    EndConnection endB = EndConnection.buttWeld;
    final lenCtrl = TextEditingController(text: '${_valveDefault[dn] ?? 178}');
    try {
      return await showModalBottomSheet<({
        int dn,
        int physicalLengthMm,
        EndConnection endA,
        EndConnection endB,
      })>(
        context: context,
        backgroundColor: Theme.of(context).colorScheme.surface,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
        ),
        isScrollControlled: true,
        builder: (bctx) {
          final cs = Theme.of(bctx).colorScheme;
          return StatefulBuilder(
            builder: (bctx, setLocal) => SafeArea(
              child: Padding(
                padding: EdgeInsets.only(
                  left: 16,
                  right: 16,
                  top: 16,
                  bottom: 16 + MediaQuery.of(bctx).viewInsets.bottom,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(compName(kind, _isPl),
                        style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                            color: cs.onSurface)),
                    const SizedBox(height: 8),
                    Text(_tr('Średnica nominalna', 'Nominal diameter'),
                        style: TextStyle(
                            fontSize: 10, color: cs.onSurfaceVariant)),
                    DropdownButton<int>(
                      isExpanded: true,
                      value: dn,
                      items: _dnChoices
                          .map((d) => DropdownMenuItem(
                              value: d, child: Text('DN$d')))
                          .toList(),
                      onChanged: (v) {
                        if (v == null) return;
                        setLocal(() {
                          dn = v;
                          lenCtrl.text = '${_valveDefault[v] ?? 178}';
                        });
                      },
                    ),
                    const SizedBox(height: 10),
                    Text(_tr('Długość face-to-face (mm)',
                        'Face-to-face length (mm)'),
                        style: TextStyle(
                            fontSize: 11, color: cs.onSurfaceVariant)),
                    TextField(
                      controller: lenCtrl,
                      keyboardType: const TextInputType.numberWithOptions(
                          decimal: false, signed: false),
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                        LengthLimitingTextInputFormatter(4),
                      ],
                      textInputAction: TextInputAction.done,
                      decoration: InputDecoration(
                        isDense: true,
                        helperText: _tr(
                            'Zakres 1-9999 mm. Domyślnie B16.10 kl. 150.',
                            'Range 1-9999 mm. Default B16.10 cl. 150.'),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(_tr('Końcówka lewa', 'Left end'),
                        style: TextStyle(
                            fontSize: 10, color: cs.onSurfaceVariant)),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        for (final t in [
                          EndConnection.buttWeld,
                          EndConnection.socketWeld,
                          EndConnection.threaded,
                          EndConnection.weldNeck,
                        ])
                          ChoiceChip(
                            label: Text(t.code,
                                style: const TextStyle(fontSize: 11)),
                            selected: t == endA,
                            onSelected: (_) => setLocal(() => endA = t),
                          ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(_tr('Końcówka prawa', 'Right end'),
                        style: TextStyle(
                            fontSize: 10, color: cs.onSurfaceVariant)),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        for (final t in [
                          EndConnection.buttWeld,
                          EndConnection.socketWeld,
                          EndConnection.threaded,
                          EndConnection.weldNeck,
                        ])
                          ChoiceChip(
                            label: Text(t.code,
                                style: const TextStyle(fontSize: 11)),
                            selected: t == endB,
                            onSelected: (_) => setLocal(() => endB = t),
                          ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                          onPressed: () => Navigator.pop(bctx, null),
                          child: Text(_tr('Anuluj', 'Cancel')),
                        ),
                        const SizedBox(width: 8),
                        ElevatedButton(
                          onPressed: () {
                            final len = int.tryParse(lenCtrl.text.trim());
                            if (len == null || len <= 0) return;
                            Navigator.pop(bctx, (
                              dn: dn,
                              physicalLengthMm: len,
                              endA: endA,
                              endB: endB,
                            ));
                          },
                          child: const Text('OK'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      );
    } finally {
      lenCtrl.dispose();
    }
  }

  Future<({int dn, int physicalLengthMm})?> _askCapSpec() async {
    int dn = 50;
    final lenCtrl =
        TextEditingController(text: '${TakeoutCatalog.cap[dn] ?? 35}');
    try {
      return await showModalBottomSheet<({int dn, int physicalLengthMm})>(
        context: context,
        backgroundColor: Theme.of(context).colorScheme.surface,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
        ),
        isScrollControlled: true,
        builder: (bctx) {
          final cs = Theme.of(bctx).colorScheme;
          return StatefulBuilder(
            builder: (bctx, setLocal) => SafeArea(
              child: Padding(
                padding: EdgeInsets.only(
                  left: 16,
                  right: 16,
                  top: 16,
                  bottom: 16 + MediaQuery.of(bctx).viewInsets.bottom,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(_tr('Zaślepka', 'Cap'),
                        style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                            color: cs.onSurface)),
                    const SizedBox(height: 8),
                    Text(_tr('Średnica nominalna', 'Nominal diameter'),
                        style: TextStyle(
                            fontSize: 10, color: cs.onSurfaceVariant)),
                    DropdownButton<int>(
                      isExpanded: true,
                      value: dn,
                      items: _dnChoices
                          .map((d) => DropdownMenuItem(
                              value: d, child: Text('DN$d')))
                          .toList(),
                      onChanged: (v) {
                        if (v == null) return;
                        setLocal(() {
                          dn = v;
                          lenCtrl.text = '${TakeoutCatalog.cap[v] ?? 35}';
                        });
                      },
                    ),
                    const SizedBox(height: 10),
                    Text(_tr('Długość czoła (mm)', 'Face length (mm)'),
                        style: TextStyle(
                            fontSize: 11, color: cs.onSurfaceVariant)),
                    TextField(
                      controller: lenCtrl,
                      keyboardType: const TextInputType.numberWithOptions(
                          decimal: false, signed: false),
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                        LengthLimitingTextInputFormatter(4),
                      ],
                      textInputAction: TextInputAction.done,
                      decoration: InputDecoration(
                        isDense: true,
                        helperText: _tr(
                            'Zakres 1–9999 mm. Domyślne z B16.9.',
                            'Range 1–9999 mm. Defaults from B16.9.'),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                          onPressed: () => Navigator.pop(bctx, null),
                          child: Text(_tr('Anuluj', 'Cancel')),
                        ),
                        const SizedBox(width: 8),
                        ElevatedButton(
                          onPressed: () {
                            final len = int.tryParse(lenCtrl.text.trim());
                            if (len == null || len <= 0) return;
                            Navigator.pop(bctx,
                                (dn: dn, physicalLengthMm: len));
                          },
                          child: const Text('OK'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      );
    } finally {
      lenCtrl.dispose();
    }
  }

  bool get _isPl => context.language == AppLanguage.pl;

  // ── ASME catalog picker (DN → component) ────────────────────────────────
  /// Two-step picker: first DN, then component type. Returns a [TakeoutEntry]
  /// with the standard CTE/FTF value so the user doesn't have to look up
  /// tables. The chosen DN sticks for the rest of the cut-calc session via
  /// [_lastCatalogDn] (so common DN=100 jobs don't need re-picking).
  int _lastCatalogDn = 50;

  Future<TakeoutEntry?> _pickFromCatalog(BuildContext outer) async {
    final dn = await showModalBottomSheet<int>(
      context: outer,
      backgroundColor: Theme.of(outer).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (bctx) {
        final cs = Theme.of(bctx).colorScheme;
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_tr('Wybierz DN', 'Pick DN'),
                    style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: cs.onSurface)),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final d in TakeoutCatalog.dns)
                      ChoiceChip(
                        label: Text(TakeoutCatalog.dnLabel(d),
                            style: const TextStyle(fontSize: 12)),
                        selected: d == _lastCatalogDn,
                        onSelected: (_) => Navigator.pop(bctx, d),
                      ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
    if (dn == null || !mounted) return null;
    _lastCatalogDn = dn;

    if (!outer.mounted) return null;
    final entries = TakeoutCatalog.entriesForDn(dn);
    return showModalBottomSheet<TakeoutEntry>(
      context: outer,
      backgroundColor: Theme.of(outer).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      isScrollControlled: true,
      builder: (bctx) {
        final cs = Theme.of(bctx).colorScheme;
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _tr('Komponent dla ${TakeoutCatalog.dnLabel(dn)}',
                      'Component for ${TakeoutCatalog.dnLabel(dn)}'),
                  style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: cs.onSurface),
                ),
                const SizedBox(height: 4),
                Text(
                  _tr('Wartości wg ASME B16.5 / B16.9 / B16.10',
                      'Values per ASME B16.5 / B16.9 / B16.10'),
                  style: TextStyle(
                    fontSize: 10,
                    color: cs.onSurfaceVariant,
                    fontStyle: FontStyle.italic,
                  ),
                ),
                const SizedBox(height: 8),
                Flexible(
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        for (final e in entries)
                          ListTile(
                            dense: true,
                            visualDensity: VisualDensity.compact,
                            title: Text(e.name,
                                style: const TextStyle(fontSize: 13)),
                            // ASME catalogue values originate in inches — show
                            // the inch equivalent so a fitter cross-checking an
                            // imperial spool drawing doesn't have to convert.
                            trailing: Text(
                                '${e.mm} mm  (${(e.mm / 25.4).toStringAsFixed(2)}")',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w900,
                                  color: cs.tertiary,
                                )),
                            onTap: () => Navigator.pop(bctx, e),
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _editName() async {
    final ctrl = TextEditingController(text: _projectName);
    try {
      final name = await showDialog<String>(
        context: context,
        builder: (dctx) => AlertDialog(
          title: Text(_tr('Nazwa rysunku / nr linii', 'Drawing name / line no.')),
          content: TextField(
            controller: ctrl,
            autofocus: true,
            textInputAction: TextInputAction.done,
            decoration: InputDecoration(
              hintText: _tr('np. 6"-CWS-1234', 'e.g. 6"-CWS-1234'),
            ),
            onSubmitted: (v) => Navigator.pop(dctx, v.trim()),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dctx, null),
              child: Text(_tr('Anuluj', 'Cancel')),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(dctx, ctrl.text.trim()),
              child: const Text('OK'),
            ),
          ],
        ),
      );
      if (name != null) setState(() => _projectName = name);
    } finally {
      ctrl.dispose();
    }
  }

  // ── summary / BOM ───────────────────────────────────────────────────────────
  List<_Seg> get _pipes =>
      _items.whereType<_Seg>().where((s) => s.t == _Tool.pipe).toList();

  /// Total of all resolved CUTs (deducts already applied).
  /// Resolved CUT for a single segment = manual cut from [_CutCalc] minus
  /// any standard elbow CTEs that sit at this segment's endpoints. Returns
  /// NaN when the manual cut itself is unreadable.
  double _resolvedCut(_Seg seg) {
    final c = seg.calc;
    if (c == null) return double.nan;
    // Parse ISO expression — preserve the original try/catch contract: a
    // garbled formula yields NaN so the BOM rendering can show "(unreadable)".
    double isoMm;
    try {
      isoMm = parseIsoExpression(c.iso);
    } catch (_) {
      return double.nan;
    }
    // Per-end elbow CTE totals (was a single sum in the legacy implementation;
    // PrefabEngine needs them split so refs like centreToFace can credit only
    // the left side). User deduct rows are folded in here too because the
    // user-typed list represents centre-to-end contributions.
    int leftCte = 0;
    int rightCte = 0;
    final tol = _s * 0.45;
    for (final it in _items) {
      if (it is! _Comp) continue;
      if (!it.isElbow) continue;
      final cte = it.cteMm;
      if (cte == null || cte <= 0) continue;
      if ((it.pos - seg.a).distance < tol) leftCte += cte;
      if ((it.pos - seg.b).distance < tol) rightCte += cte;
    }
    // Also subtract any manually typed deduct rows (Phase 1 keeps them as
    // generic centre-to-end style debits so existing drawings keep producing
    // the same CUT). Unreadable rows are skipped, mirroring legacy `cutMm`.
    double manualDeducts = 0;
    for (final d in c.deducts) {
      if (d.value.trim().isEmpty) continue;
      try {
        manualDeducts += parseIsoExpression(d.value);
      } catch (_) {}
    }
    final leftPhys = _autoPhysicalDeductFor(seg.a, _items, tol);
    final rightPhys = _autoPhysicalDeductFor(seg.b, _items, tol);
    final midPhys = _midPhysicalDeductFor(seg, _items, tol);
    final engineCut = prefab.PrefabEngine.cutLengthMm(
      isoValueMm: isoMm,
      ref: c.ref,
      leftCteMm: leftCte,
      rightCteMm: rightCte,
      leftPhysicalLenMm: leftPhys > 0 ? leftPhys : null,
      rightPhysicalLenMm: rightPhys > 0 ? rightPhys : null,
      midPhysicalSumMm: midPhys,
    );
    return engineCut - manualDeducts;
  }

  double get _totalMm {
    double sum = 0;
    for (final s in _pipes) {
      if (s.calc == null) continue;
      final v = _resolvedCut(s);
      if (v.isFinite) sum += v;
    }
    return sum;
  }

  static String compName(_Tool t, bool pl) {
    switch (t) {
      case _Tool.elbow90:         return pl ? 'Kolano 90°' : 'Elbow 90°';
      case _Tool.elbow45:         return pl ? 'Kolano 45°' : 'Elbow 45°';
      case _Tool.tee:             return pl ? 'Trójnik' : 'Tee';
      case _Tool.olet:            return pl ? 'Mufa olet' : 'Olet (weldolet)';
      case _Tool.reducer:         return pl ? 'Redukcja' : 'Reducer';
      case _Tool.flange:          return pl ? 'Kołnierz' : 'Flange';
      case _Tool.blindFlange:     return pl ? 'Kołnierz ślepy' : 'Blind flange';
      case _Tool.cap:             return pl ? 'Zaślepka' : 'Cap';
      case _Tool.gateValve:       return pl ? 'Zawór zasuwowy' : 'Gate valve';
      case _Tool.ballValve:       return pl ? 'Zawór kulowy' : 'Ball valve';
      case _Tool.checkValve:      return pl ? 'Zawór zwrotny' : 'Check valve';
      case _Tool.globeValve:      return pl ? 'Zawór grzybkowy' : 'Globe valve';
      case _Tool.butterflyValve:  return pl ? 'Zawór motylkowy' : 'Butterfly valve';
      case _Tool.weld:            return pl ? 'Spoina warsztatowa' : 'Shop weld';
      case _Tool.fieldWeld:       return pl ? 'Spoina montażowa' : 'Field weld';
      case _Tool.support:         return pl ? 'Podpora' : 'Support';
      case _Tool.instrument:      return pl ? 'Instrument' : 'Instrument';
      case _Tool.spoolBreak:      return pl ? 'Podział spoolu' : 'Spool break';
      case _Tool.northArrow:      return pl ? 'Strzałka północy' : 'North arrow';
      case _Tool.flowArrow:       return pl ? 'Kierunek przepływu' : 'Flow arrow';
      default:                    return t.name;
    }
  }

  /// Build the same cut-list lines used by [_copySummary], but split into a
  /// list (one element per line) so [IsoPdfExport] can render them in a
  /// monospaced PDF block.
  List<String> _cutListLines() {
    final isPl = context.language == AppLanguage.pl;
    final lines = <String>[];
    final pipes = _pipes;
    if (pipes.isEmpty) return lines;
    final tol = _s * 0.45;
    var n = 0;
    for (final s in pipes) {
      n++;
      final c = s.calc;
      if (c == null) {
        lines.add('  $n. ${isPl ? "(bez wymiaru)" : "(no dimension)"}');
        continue;
      }
      final cut = _resolvedCut(s);
      final autoCte = _autoElbowDeductFor(s, _items, tol);
      final leftPhys = _autoPhysicalDeductFor(s.a, _items, tol);
      final rightPhys = _autoPhysicalDeductFor(s.b, _items, tol);
      final midPhys = _midPhysicalDeductFor(s, _items, tol);
      // Mirror engine semantics: physicals on segment ends only contribute
      // when the dimension goes ALL THE WAY THROUGH the body (end-stop
      // refs: faceToEnd, centreToEnd). For face-stop refs (CTF, FTF) the
      // physical body is NOT subtracted, so don't list it as a deduct.
      final endPhysicalsActive = c.ref == DimRef.faceToEnd ||
          c.ref == DimRef.centreToEnd;
      final endPhysSum = endPhysicalsActive ? leftPhys + rightPhys : 0;
      final hasAnyDeduct = c.hasDeducts || autoCte > 0 ||
          endPhysSum > 0 || midPhys > 0;
      final refTag = isPl ? c.ref.labelPl : c.ref.labelEn;
      final cutStr = cut.isFinite
          ? '${cut.toStringAsFixed(1)} mm'
          : (isPl ? '(nieczytelne)' : '(unreadable)');
      final inferredDn = _inferredDnFor(s);
      final dnTag = inferredDn != null ? '  DN$inferredDn' : '';
      if (hasAnyDeduct) {
        lines.add('  $n.$dnTag  ISO: ${c.iso}   [$refTag]');
        for (final d in c.deducts) {
          lines.add('       − ${d.name.isEmpty ? "?" : d.name}: ${d.value}');
        }
        if (autoCte > 0) {
          lines.add('       − ${isPl ? "oś kolanek" : "elbow CTE"}: $autoCte mm');
        }
        if (endPhysicalsActive && leftPhys > 0) {
          lines.add('       − ${isPl ? "komponent (lewy)" : "component (left)"}: $leftPhys mm');
        }
        if (endPhysicalsActive && rightPhys > 0) {
          lines.add('       − ${isPl ? "komponent (prawy)" : "component (right)"}: $rightPhys mm');
        }
        if (midPhys > 0) {
          lines.add('       − ${isPl ? "komponenty w środku" : "mid components"}: $midPhys mm');
        }
        lines.add('     CUT: $cutStr');
      } else {
        lines.add(
            '  $n.$dnTag  ${c.iso}${cut.isFinite ? " = $cutStr" : ""}   [$refTag]');
      }
      if (s.hasSlope) {
        lines.add('       (${isPl ? "spadek" : "slope"}: ${s.slope})');
      }
    }
    lines.add('  ${'-' * 24}');
    lines.add('  ${isPl ? "Suma CUT" : "Total CUT"}: '
        '${_totalMm.toStringAsFixed(1)} mm');
    // Stick-nesting hint: stockyards stock pipe in 6 m and 12 m sticks, so a
    // ceil(total / stick) tells the fitter at a glance how much raw stock to
    // pull off the rack before the saw starts. Lower bound (no kerf, no
    // off-cut), but in practice the fitter buys one extra stick anyway.
    if (_totalMm > 0) {
      final s6 = (_totalMm / 6000).ceil();
      final s12 = (_totalMm / 12000).ceil();
      lines.add('  ${isPl ? "Sztangi" : "Sticks"}: '
          '${isPl ? "≈$s6 × 6 m  lub  $s12 × 12 m" : "~$s6 x 6 m  or  $s12 x 12 m"}');
    }

    // Bill of materials — ASME-style columnar table appended after the
    // cut totals so a single copy/share gives the fitter everything they
    // need (cuts on top, BOM at the bottom, drawing in the PDF).
    final rows = _bomRows();
    if (rows.isNotEmpty) {
      lines.add('');
      lines.add('  ${isPl ? "ZESTAWIENIE MATERIAŁOWE (BOM)" : "BILL OF MATERIALS"}');
      lines.add('  ${'=' * 44}');
      // Column widths tuned for a 44-char monospace block (matches the
      // PDF / share-sheet layout). NO  | QTY    | DESCRIPTION | DN    | SPEC
      lines.add('  ${_pad("NO", 3)} ${_pad("QTY", 8)} '
          '${_pad(isPl ? "OPIS" : "DESCRIPTION", 18)} '
          '${_pad("DN", 6)} ${_pad("SPEC", 5)}');
      lines.add('  ${'-' * 44}');
      for (final r in rows) {
        lines.add('  ${_pad("${r.item}", 3)} ${_pad(r.qty, 8)} '
            '${_pad(r.description, 18)} ${_pad(r.dn, 6)} ${_pad(r.spec, 5)}');
      }
    }
    return lines;
  }

  /// Left-pad / clip a string to exactly [width] visible chars so the
  /// monospace BOM table aligns in copy-paste output.
  static String _pad(String s, int width) {
    if (s.length >= width) return s.substring(0, width);
    return s + ' ' * (width - s.length);
  }

  /// Build BOM as a name→count map for [IsoPdfExport]. Kept for backward
  /// compat with the existing PDF export contract; the richer columnar BOM
  /// used in the on-screen cut list comes from [_bomRows].
  Map<String, int> _bomMap() {
    final isPl = context.language == AppLanguage.pl;
    final counts = <_Tool, int>{};
    for (final it in _items) {
      if (it is _Comp && it.t != _Tool.northArrow && it.t != _Tool.flowArrow) {
        counts[it.t] = (counts[it.t] ?? 0) + 1;
      }
    }
    return {for (final e in counts.entries) compName(e.key, isPl): e.value};
  }

  /// Default project spec tag — used in the BOM SPEC column when the user
  /// hasn't set anything else. Hard-coded to S52 for now; will move to a
  /// per-project setting once the drawing-properties screen lands.
  static const String _defaultSpec = 'S52';

  /// Group components by (kind, DN) and emit professional-style BOM rows:
  ///   ITEM | QTY | DESCRIPTION | DN | SPEC
  ///
  /// Pipes appear as a single row aggregating total length per DN; fittings
  /// are grouped by tool type within DN; welds aren't billed (they're a
  /// labour line, not a material). North / flow arrows skipped. Returns
  /// rows already numbered starting from 1 in BOM reading order
  /// (pipes first, then fittings sorted by descending qty so the most
  /// common parts top the list).
  List<({int item, String qty, String description, String dn, String spec})>
      _bomRows() {
    final isPl = context.language == AppLanguage.pl;
    final tol = _s * 0.45;

    // Pipe lengths bucketed by inferred DN (string key — DN-unknown bucket
    // labelled "-").
    final pipeLenByDn = <String, double>{};
    for (final seg in _pipes) {
      if (seg.calc == null) continue;
      final cut = _resolvedCut(seg);
      if (!cut.isFinite) continue;
      final dn = _inferredDnFor(seg);
      final key = dn != null ? 'DN$dn' : '-';
      pipeLenByDn[key] = (pipeLenByDn[key] ?? 0) + cut;
    }

    // Fittings: group by (tool, dn) into a count.
    final fitCounts = <(String tool, String dn), int>{};
    for (final it in _items) {
      if (it is! _Comp) continue;
      if (it.t.isWeld ||
          it.t == _Tool.northArrow ||
          it.t == _Tool.flowArrow ||
          it.t == _Tool.text ||
          it.t == _Tool.support ||
          it.t == _Tool.spoolBreak) {
        continue;
      }
      // For axial comps without their own DN, try to inherit from a pipe
      // touching this position so flange-to-elbow joints still print a
      // meaningful DN row.
      String dn = it.dn != null ? 'DN${it.dn}' : '-';
      if (dn == '-') {
        for (final p in _pipes) {
          if ((p.a - it.pos).distance < tol || (p.b - it.pos).distance < tol) {
            final inf = _inferredDnFor(p);
            if (inf != null) {
              dn = 'DN$inf';
              break;
            }
          }
        }
      }
      final key = (compName(it.t, isPl), dn);
      fitCounts[key] = (fitCounts[key] ?? 0) + 1;
    }

    final rows =
        <({int item, String qty, String description, String dn, String spec})>[];
    int n = 0;

    // Pipes by DN, sorted so DN-known come first then "-".
    final pipeKeys = pipeLenByDn.keys.toList()
      ..sort((a, b) {
        if (a == '-') return 1;
        if (b == '-') return -1;
        return a.compareTo(b);
      });
    for (final dn in pipeKeys) {
      n++;
      final lenMm = pipeLenByDn[dn]!;
      final lenStr =
          lenMm >= 1000 ? '${(lenMm / 1000).toStringAsFixed(2)} m' : '${lenMm.toStringAsFixed(0)} mm';
      rows.add((
        item: n,
        qty: lenStr,
        description: isPl ? 'Rura (suma cięć)' : 'Pipe (cut total)',
        dn: dn,
        spec: _defaultSpec,
      ));
    }

    // Fittings sorted by qty desc, then alphabetically.
    final fitEntries = fitCounts.entries.toList()
      ..sort((a, b) {
        final c = b.value.compareTo(a.value);
        if (c != 0) return c;
        return a.key.$1.compareTo(b.key.$1);
      });
    for (final e in fitEntries) {
      n++;
      rows.add((
        item: n,
        qty: '${e.value}',
        description: e.key.$1,
        dn: e.key.$2,
        spec: _defaultSpec,
      ));
    }
    return rows;
  }

  Future<void> _exportPdf() async {
    // The capture + encode + share-sheet handoff is multi-second on a busy
    // drawing. Without feedback the user often double-taps the export
    // button thinking nothing happened. Show a persistent snackbar that
    // we dismiss in the finally; the share sheet then opens on top.
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Row(children: [
        const SizedBox(
          width: 16,
          height: 16,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
        const SizedBox(width: 12),
        Text(_tr('Generuję PDF…', 'Generating PDF…')),
      ]),
      duration: const Duration(minutes: 1),
    ));
    try {
      final boundaryCtx = _canvasKey.currentContext;
      final boundary =
          boundaryCtx?.findRenderObject() as RenderRepaintBoundary?;
      // Bare `return` here would leave the 1-minute "Generating PDF…" spinner
      // hanging forever with zero recovery — the canvas being un-mounted is
      // recoverable (scroll the iso back into view + retry) so surface that
      // instead of failing silently.
      if (boundary == null) {
        if (mounted) ScaffoldMessenger.of(context).hideCurrentSnackBar();
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(_tr(
            'Płótno nie jest gotowe — przewiń rysunek z powrotem na ekran i spróbuj ponownie.',
            'Canvas not ready — scroll the drawing back into view and try again.',
          )),
          duration: const Duration(seconds: 4),
          action: SnackBarAction(
            label: _tr('Ponów', 'Retry'),
            onPressed: _exportPdf,
          ),
        ));
        return;
      }
      // Snapshot lines + bom synchronously before the async gap.
      final lines = _cutListLines();
      final bom = _bomMap();
      await IsoPdfExport.export(
        boundary: boundary,
        projectName: _projectName,
        cutListLines: lines,
        bom: bom,
      );
      if (mounted) ScaffoldMessenger.of(context).hideCurrentSnackBar();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).hideCurrentSnackBar();
      if (!mounted) return;
      // Map common failure modes to messages a monter can act on; keep the
      // raw exception in the debug log for support tickets.
      debugPrint('ISO PDF export error: $e');
      String message;
      if (e is FileSystemException) {
        message = _tr(
          'Brak miejsca lub dostępu do pamięci. Sprawdź, czy aplikacja ma uprawnienia.',
          'Storage error. Check the app has permission to save files.',
        );
      } else if (e is StateError) {
        message = _tr(
          'Rysunek nie został jeszcze narysowany — narysuj coś, zanim eksportujesz.',
          'The drawing is empty — draw something before exporting.',
        );
      } else if (e.toString().toLowerCase().contains('share')) {
        message = _tr(
          'Nie mogę otworzyć panelu udostępniania. Zapisz plik ręcznie z folderu pobrane.',
          'Sharing panel is unavailable. Save the file manually from downloads.',
        );
      } else {
        message = _tr(
          'Eksport PDF nie powiódł się. Spróbuj ponownie za chwilę.',
          'PDF export failed. Try again in a moment.',
        );
      }
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(message),
        duration: const Duration(seconds: 4),
      ));
    }
  }

  Future<void> _copySummary() async {
    final isPl = context.language == AppLanguage.pl;
    final buf = StringBuffer();
    buf.writeln(_projectName.isEmpty
        ? _tr('Szkic izometryczny', 'Isometric sketch')
        : _projectName);
    buf.writeln('═' * 32);

    final pipes = _pipes;
    if (pipes.isNotEmpty) {
      buf.writeln(_tr('CUT LIST', 'CUT LIST'));
      var n = 0;
      for (final s in pipes) {
        n++;
        final c = s.calc;
        if (c == null) {
          buf.writeln('  $n. ${_tr('(bez wymiaru)', '(no dimension)')}');
          continue;
        }
        final cut = c.cutMm;
        final cutStr = cut.isFinite
            ? '${cut.toStringAsFixed(1)} mm'
            : _tr('(nieczytelne)', '(unreadable)');
        if (c.hasDeducts) {
          buf.writeln('  $n. ${_tr('ISO', 'ISO')}: ${c.iso}');
          for (final d in c.deducts) {
            final tag = d.name.isEmpty ? '?' : d.name;
            buf.writeln('       − $tag: ${d.value}');
          }
          buf.writeln('     ${_tr('CUT', 'CUT')}: $cutStr');
        } else {
          buf.writeln('  $n. ${c.iso}'
              '${cut.isFinite ? ' = $cutStr' : ''}');
        }
      }
      buf.writeln('  ${'─' * 24}');
      buf.writeln('  ${_tr('Suma CUT', 'Total CUT')}: '
          '${_totalMm.toStringAsFixed(1)} mm');
      buf.writeln('');
    }

    final counts = <_Tool, int>{};
    for (final it in _items) {
      if (it is _Comp && it.t != _Tool.northArrow && it.t != _Tool.flowArrow) {
        counts[it.t] = (counts[it.t] ?? 0) + 1;
      }
    }
    if (counts.isNotEmpty) {
      buf.writeln(_tr('ZESTAWIENIE MATERIAŁOWE (BOM)', 'MATERIAL LIST (BOM)'));
      for (final e in counts.entries) {
        buf.writeln('  ${compName(e.key, isPl)}: ${e.value}');
      }
      buf.writeln('');
    }

    final welds = _items.whereType<_Comp>().where((c) => c.t.isWeld).toList();
    if (welds.isNotEmpty) {
      buf.writeln('${_tr('Spoiny razem', 'Total welds')}: ${welds.length}');
    }

    final notes = _items.whereType<_Note>().toList();
    if (notes.isNotEmpty) {
      buf.writeln('');
      buf.writeln(_tr('OPISY', 'NOTES'));
      for (final nt in notes) {
        buf.writeln('  • ${nt.text}');
      }
    }

    // The summary can be ~1 KB — calling copyToClipboard directly would
    // dump the whole blob into the snackbar. Copy quietly + show a short
    // confirmation chip instead.
    final payload = buf.toString();
    try {
      await Clipboard.setData(ClipboardData(text: payload));
    } catch (e) {
      // Platform clipboard can fail when another app holds focus (Android
      // background restriction) or on locked-down MDM devices. Surface a
      // recoverable message instead of a raw PlatformException.
      debugPrint('Copy summary clipboard error: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(
          content: Text(_tr(
            'Nie udało się skopiować — schowek jest zajęty przez inną aplikację.',
            'Copy failed — clipboard is busy or blocked by another app.',
          )),
          duration: const Duration(seconds: 4),
          action: SnackBarAction(
            label: _tr('Ponów', 'Retry'),
            onPressed: _copySummary,
          ),
        ));
      return;
    }
    await Haptic.copied();
    if (!mounted) return;
    final lineCount = payload.split('\n').length;
    // Polish has three plural forms (1 / few 2-4 / many 5+, with the 12-14
    // teens trap landing in the "many" bucket). English just needs 1 vs n.
    final mod10 = lineCount % 10;
    final mod100 = lineCount % 100;
    final plLine = lineCount == 1
        ? 'linia'
        : (mod10 >= 2 && mod10 <= 4 && (mod100 < 12 || mod100 > 14))
            ? 'linie'
            : 'linii';
    final enLine = lineCount == 1 ? 'line' : 'lines';
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Row(
          children: [
            const ExcludeSemantics(
              child: Icon(Icons.check_circle,
                  color: Colors.greenAccent, size: 18),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(_tr(
                'Skopiowano zestawienie ($lineCount $plLine) do schowka.',
                'Copied summary ($lineCount $enLine) to clipboard.',
              )),
            ),
          ],
        ),
        duration: const Duration(milliseconds: 1600),
      ));
  }

  // ── undo / clear ────────────────────────────────────────────────────────────
  void _push() => _undo.add(List.from(_items));

  void _undoAction() {
    if (_undo.isEmpty) return;
    _mutate(() => _items..clear()..addAll(_undo.removeLast()));
  }

  Future<void> _clear() async {
    if (_items.isEmpty) return;
    final wiped = _items.length;
    // The "Clear all" icon sits next to common AppBar actions (Export, Help) —
    // an accidental tap on a non-trivial drawing would auto-dismiss the Undo
    // snackbar in seconds and silently wipe real work. Gate non-trivial wipes
    // behind an explicit confirmation; small drawings stay frictionless.
    if (wiped >= 3) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (dctx) => AlertDialog(
          title: Text(_tr('Wyczyścić rysunek?', 'Clear drawing?')),
          content: Text(_tr(
            'Usunąć wszystkie elementy ($wiped el.)? Można cofnąć w ciągu kilku sekund.',
            'Remove all items ($wiped)? You can undo for a few seconds.',
          )),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dctx, false),
              child: Text(_tr('Anuluj', 'Cancel')),
            ),
            TextButton(
              onPressed: () => Navigator.pop(dctx, true),
              child: Text(
                _tr('Wyczyść', 'Clear'),
                style: TextStyle(color: Theme.of(dctx).colorScheme.error),
              ),
            ),
          ],
        ),
      );
      if (ok != true || !mounted) return;
    }
    _push();
    _mutate(_items.clear);
    // Destructive action — surface a visible undo handle next to the wipe so
    // an accidental tap on "Clear all" isn't a silent data loss.
    if (!mounted) return;
    // Plural-aware item count. English needs 1 vs n. Polish "el." abbrev is
    // count-neutral so we leave it as-is.
    final enItem = wiped == 1 ? 'item' : 'items';
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(_tr(
          'Wyczyszczono rysunek ($wiped el.).',
          'Drawing cleared ($wiped $enItem).',
        )),
        duration: const Duration(seconds: 5),
        action: SnackBarAction(
          label: _tr('Cofnij', 'Undo'),
          onPressed: _undoAction,
        ),
      ));
  }

  // ── batch dimension entry (called from "Wymiary" button) ──────────────────
  /// Opens a bottom sheet listing every pipe segment that doesn't yet have
  /// a dimension and lets the user fill them all in one pass. Tap-edit on
  /// individual segments still works as before — this is a quick "do them
  /// all at the end" shortcut the user explicitly asked for.
  Future<void> _enterAllDimensions() async {
    final pipes = <_Seg>[];
    for (final it in _items) {
      if (it is _Seg && it.t == _Tool.pipe) pipes.add(it);
    }
    if (pipes.isEmpty) return;

    final controllers = <_Seg, TextEditingController>{
      for (final p in pipes)
        p: TextEditingController(text: p.calc?.iso ?? ''),
    };

    // Component CTE / physical-length inputs surface here so the fitter can
    // enter everything in one pass and hit "Oblicz cut list" — no need to
    // tap each elbow individually. We only ask about comps that lack the
    // data CUT-list math actually consumes (elbows without cteMm, physical
    // components without physicalLengthMm). Comps already specced stay
    // untouched.
    final compsNeedingData = <_Comp>[];
    for (final it in _items) {
      if (it is! _Comp) continue;
      if (it.isElbow && (it.cteMm == null || it.cteMm! <= 0)) {
        compsNeedingData.add(it);
        continue;
      }
      try {
        if (ComponentClassification.isPhysical(it.t.name) &&
            (it.physicalLengthMm == null || it.physicalLengthMm! <= 0)) {
          compsNeedingData.add(it);
        }
      } catch (_) {}
    }
    final compControllers = <_Comp, TextEditingController>{
      for (final c in compsNeedingData)
        c: TextEditingController(
          text: c.isElbow
              ? (c.cteMm?.toString() ?? '')
              : (c.physicalLengthMm?.toString() ?? ''),
        ),
    };

    try {
      final saved = await showModalBottomSheet<bool>(
        context: context,
        isScrollControlled: true,
        builder: (sheetCtx) {
          return Padding(
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(sheetCtx).viewInsets.bottom,
            ),
            child: _DimensionsSheet(
              segments: pipes,
              controllers: controllers,
              components: compsNeedingData,
              componentControllers: compControllers,
              tr: (pl, en) => sheetCtx.tr(pl: pl, en: en),
              compName: (t) => compName(t, sheetCtx.language == AppLanguage.pl),
            ),
          );
        },
      );

      if (saved == true && mounted) {
        _push();
        _mutate(() {
          for (final entry in controllers.entries) {
            final txt = entry.value.text.trim();
            final idx = _items.indexOf(entry.key);
            if (idx < 0) continue;
            if (txt.isEmpty) {
              _items[idx] = entry.key.withCalc(null);
            } else {
              _items[idx] = entry.key.withCalc(_CutCalc(txt));
            }
          }
          for (final entry in compControllers.entries) {
            final raw = entry.value.text.trim();
            if (raw.isEmpty) continue;
            final v = int.tryParse(raw);
            if (v == null || v <= 0) continue;
            final idx = _items.indexOf(entry.key);
            if (idx < 0) continue;
            final c = entry.key;
            if (c.isElbow) {
              _items[idx] = c.withElbowSpec(
                dn: c.dn ?? 50,
                subtype: c.elbowSubtype ?? _ElbowSubtype.lr90,
                cte: v,
              );
            } else {
              _items[idx] = c.withPhysicalSpec(
                dn: c.dn ?? 50,
                dnOut: c.dnOut,
                physicalLengthMm: v,
                endA: c.endA,
                endB: c.endB,
              );
            }
          }
        });
        if (mounted) await _showCutListResult();
      }
    } finally {
      for (final c in controllers.values) {
        c.dispose();
      }
      for (final c in compControllers.values) {
        c.dispose();
      }
    }
  }

  /// Result panel shown after the fitter hits "Oblicz cut list". Renders
  /// the same lines the copy-summary path produces, plus a "Kopiuj" action
  /// so the brygadzista can paste the list into a message / order to the
  /// prefab shop.
  Future<void> _showCutListResult() async {
    final lines = _cutListLines();
    if (lines.isEmpty) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) {
        final cs = Theme.of(ctx).colorScheme;
        return DraggableScrollableSheet(
          initialChildSize: 0.7,
          maxChildSize: 0.95,
          minChildSize: 0.4,
          expand: false,
          builder: (ctx2, scroll) {
            return Container(
              decoration: BoxDecoration(
                color: cs.surface,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
              ),
              child: Column(
                children: [
                  const SizedBox(height: 8),
                  Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: cs.onSurfaceVariant.withValues(alpha: 0.3),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
                    child: Row(
                      children: [
                        Icon(Icons.content_cut, color: cs.primary),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            _tr('Lista cięć (CUT LIST)', 'Cut list'),
                            style: Theme.of(ctx2).textTheme.titleMedium,
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.copy_outlined),
                          tooltip: _tr('Kopiuj', 'Copy'),
                          onPressed: () async {
                            await Clipboard.setData(
                              ClipboardData(text: lines.join('\n')),
                            );
                            if (!ctx2.mounted) return;
                            ScaffoldMessenger.of(ctx2).showSnackBar(SnackBar(
                              content: Text(_tr(
                                  'Skopiowano do schowka',
                                  'Copied to clipboard')),
                              duration: const Duration(seconds: 2),
                            ));
                          },
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: ListView(
                      controller: scroll,
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                      children: [
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: cs.surfaceContainerHigh,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: SelectableText(
                            lines.join('\n'),
                            style: const TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 12,
                              height: 1.4,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  SafeArea(
                    top: false,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                      child: SizedBox(
                        width: double.infinity,
                        child: FilledButton(
                          onPressed: () => Navigator.pop(ctx2),
                          child: Text(_tr('Zamknij', 'Close')),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  // Prefix catalogue — kept in sync with the early-return branches in _drawNote.
  // Order matches the painting precedence (HT- before HT, etc.).
  static const List<({String prefix, String pl, String en})> _kNotePrefixes = [
    (prefix: 'EL', pl: 'Rzędna — chip z trójkątną flagą i wartością',           en: 'Elevation tag — chip with triangle flag and value'),
    (prefix: "CONT'D",
        pl: 'Kontynuacja linii — strzałka "→" przed tekstem',
        en: 'Continuation — leading arrow "→" before text'),
    (prefix: 'WALL / FLOOR / CEILING',
        pl: 'Przejście przez przegrodę — kreskowany pasek',
        en: 'Penetration through wall/floor/ceiling — hatched bar'),
    (prefix: 'TIE / TIE-IN',
        pl: 'Punkt przyłączenia — okrąg z krzyżem',
        en: 'Tie-in point — circle with cross'),
    (prefix: 'BL',
        pl: 'Battery limit — pionowa linia łańcuchowa',
        en: 'Battery limit — vertical chain-dashed line'),
    (prefix: 'MATCH',
        pl: 'Match line — gruba przerywana z etykietą',
        en: 'Match line — thick dashed with label'),
    (prefix: 'EQ / VESSEL / TANK / PUMP',
        pl: 'Symbol urządzenia — prostokąt + ikona',
        en: 'Equipment symbol — rectangle with icon'),
    (prefix: 'HT',
        pl: 'Heat trace — falista linia obok rury',
        en: 'Heat trace — wavy line beside the pipe'),
    (prefix: 'STEAM / WATER / GAS / AIR / OIL / N2',
        pl: 'Medium procesowe — kolorowy chip z nazwą',
        en: 'Process medium — coloured chip with name'),
    (prefix: 'SCALE',
        pl: 'Skala rysunku — pasek z krzyżykami jak na linijce',
        en: 'Drawing scale — bar with ruler-style cross-hairs'),
    (prefix: 'DWG ID',
        pl: 'Numer rysunku — chip w stylu title-block',
        en: 'Drawing ID — title-block style chip'),
    (prefix: 'TITLE / REV / DATE / BY',
        pl: 'Pola title-block — etykieta : wartość',
        en: 'Title-block fields — label : value layout'),
    (prefix: 'INS',
        pl: 'Izolacja — gruba podwójna linia wokół rury',
        en: 'Insulation — thick double line around the pipe'),
    (prefix: 'DRAIN / DR',
        pl: 'Spust — strzałka skierowana w dół',
        en: 'Drain — downward arrow marker'),
    (prefix: 'VENT / VT',
        pl: 'Odpowietrznik — strzałka skierowana w górę',
        en: 'Vent — upward arrow marker'),
    (prefix: 'PR',
        pl: 'Pressure rating — chip ze stopniem ciśnienia',
        en: 'Pressure rating — chip with class'),
    (prefix: 'TP',
        pl: 'Test pressure — chip z ciśnieniem próby',
        en: 'Test pressure — chip with test value'),
    (prefix: 'SCH',
        pl: 'Schedule rury — kompaktowy chip',
        en: 'Pipe schedule — compact chip'),
    (prefix: 'CS / SS / DSS / ALU / TI / CU',
        pl: 'Materiał — chip z kodem materiału',
        en: 'Material — chip with material code'),
    (prefix: 'HT-####',
        pl: 'Numer wytopu — chip z prefiksem certyfikatu',
        en: 'Mill heat number — certificate-style chip'),
    (prefix: 'ACT',
        pl: 'Napęd zaworu — chip z symbolem siłownika (M/MOV/PV/EHV)',
        en: 'Valve actuator — chip with actuator glyph (M/MOV/PV/EHV)'),
  ];

  void _showNotePrefixHelp(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) {
        final cs = Theme.of(ctx).colorScheme;
        final isPl = context.language == AppLanguage.pl;
        return DraggableScrollableSheet(
          initialChildSize: 0.7,
          minChildSize: 0.4,
          maxChildSize: 0.95,
          expand: false,
          builder: (_, scrollCtrl) => Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Icon(Icons.label_outline, color: cs.primary),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _tr('Prefiksy notatek (NOTE)',
                            'Note prefixes (NOTE tool)'),
                        style: Theme.of(ctx).textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      tooltip: _tr('Zamknij', 'Close'),
                      onPressed: () => Navigator.of(ctx).pop(),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  _tr(
                    'Zaczynając notatkę od któregokolwiek z poniższych prefiksów, Zeszyt ISO rysuje dedykowany symbol zamiast zwykłego tekstu.',
                    'Starting a note with any of the prefixes below makes the ISO Notebook draw a dedicated symbol instead of plain text.',
                  ),
                  style:
                      Theme.of(ctx).textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: ListView.separated(
                    controller: scrollCtrl,
                    itemCount: _kNotePrefixes.length,
                    separatorBuilder: (_, __) => Divider(
                      height: 1,
                      color: cs.outlineVariant.withValues(alpha: 0.5),
                    ),
                    itemBuilder: (_, i) {
                      final row = _kNotePrefixes[i];
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SizedBox(
                              width: 120,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: cs.primaryContainer,
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  row.prefix,
                                  style: TextStyle(
                                    fontFamily: 'monospace',
                                    fontWeight: FontWeight.w700,
                                    fontSize: 12.5,
                                    color: cs.onPrimaryContainer,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Padding(
                                padding: const EdgeInsets.only(top: 2),
                                child: Text(
                                  isPl ? row.pl : row.en,
                                  style: const TextStyle(fontSize: 13, height: 1.4),
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // ── build ───────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    // Single pass over _items for everything the summary bar + appbar need.
    // _pipes/_dimensionedCount/_totalMm each walk _items independently and
    // _totalMm additionally re-walks _items per pipe inside _resolvedCut,
    // so calling all three in build() used to be quadratic-ish on every frame.
    final pipes = _pipes;
    final pipeCount = pipes.length;
    int dimensioned = 0;
    double totalMm = 0;
    for (final s in pipes) {
      if (s.calc == null) continue;
      dimensioned++;
      final v = _resolvedCut(s);
      if (v.isFinite) totalMm += v;
    }
    final hasComp = _items.any((it) => it is _Comp || it is _Note);
    final mapping = _currentMapping;
    return Scaffold(
      appBar: AppBar(
        title: Tooltip(
          message: _tr(
              'Dotknij, aby zmienić nazwę projektu',
              'Tap to rename the project'),
          child: GestureDetector(
            onTap: _editName,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: Text(
                    _projectName.isEmpty
                        ? _tr('Zeszyt ISO', 'ISO Notebook')
                        : _projectName,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 6),
                Icon(Icons.edit_outlined, size: 16, color: cs.onSurfaceVariant),
              ],
            ),
          ),
        ),
        actions: [
          HelpButton(help: kHelpIsoNotebook),
          IconButton(
            icon: const Icon(Icons.label_outline),
            tooltip: _tr('Prefiksy notatek', 'Note prefixes'),
            onPressed: () => _showNotePrefixHelp(context),
          ),
          IconButton(
            icon: const Icon(Icons.straighten),
            tooltip: _tr('Wprowadź wymiary', 'Enter dimensions'),
            onPressed: pipeCount == 0 ? null : _enterAllDimensions,
          ),
          IconButton(
            icon: const Icon(Icons.copy_all_outlined),
            tooltip: _tr('Kopiuj zestawienie', 'Copy summary'),
            onPressed: (pipeCount == 0 && !hasComp) ? null : _copySummary,
          ),
          IconButton(
            icon: const Icon(Icons.undo),
            tooltip: _tr('Cofnij', 'Undo'),
            onPressed: _undo.isEmpty ? null : _undoAction,
          ),
          IconButton(
            icon: AnimatedSwitcher(
              duration: const Duration(milliseconds: 180),
              transitionBuilder: (child, anim) => ScaleTransition(
                scale: anim,
                child: FadeTransition(opacity: anim, child: child),
              ),
              child: Icon(
                _axisLock ? Icons.lock : Icons.lock_open,
                key: ValueKey<bool>(_axisLock),
              ),
            ),
            tooltip: _axisLock
                ? _tr('Wyłącz blokadę osi (slope)', 'Disable axis lock (slope)')
                : _tr('Włącz blokadę osi', 'Enable axis lock'),
            // On phones the tooltip only fires on long-press, so most users
            // never see what the lock actually changed. A short SnackBar
            // names the new mode and explains the practical effect.
            onPressed: () {
              setState(() => _axisLock = !_axisLock);
              ScaffoldMessenger.of(context)
                ..hideCurrentSnackBar()
                ..showSnackBar(SnackBar(
                  content: Text(_axisLock
                      ? _tr(
                          'Blokada osi: WŁ. — rury trzymają się 3 osi izo',
                          'Axis lock: ON — pipes snap to the 3 iso axes')
                      : _tr(
                          'Blokada osi: WYŁ. — wolne rysowanie pod kątem (slope)',
                          'Axis lock: OFF — free-angle drawing (slope)')),
                  duration: const Duration(seconds: 2),
                ));
            },
          ),
          IconButton(
            icon: const Icon(Icons.picture_as_pdf_outlined),
            tooltip: _tr('Eksportuj PDF', 'Export PDF'),
            onPressed: _items.isEmpty ? null : _exportPdf,
          ),
          IconButton(
            icon: Icon(_hintHidden
                ? Icons.help_outline
                : Icons.help_outlined),
            tooltip: _tr('Pokaż instrukcję', 'Show hint'),
            onPressed: () => _setHintHidden(false),
          ),
          IconButton(
            icon: const Icon(Icons.delete_sweep_outlined),
            tooltip: _tr('Wyczyść', 'Clear all'),
            onPressed: _items.isEmpty ? null : _clear,
          ),
          // Overlay + appearance toggles. Single popup keeps app bar from
          // crowding past the safe-area on small phones. State changes are
          // persisted so the fitter's preferred view sticks across sessions.
          PopupMenuButton<String>(
            icon: const Icon(Icons.tune),
            tooltip: _tr('Widok', 'View'),
            onSelected: (key) {
              switch (key) {
                case 'axis':
                  _setShowAxisCompass(!_showAxisCompass);
                  break;
                case 'status':
                  _setShowStatusBox(!_showStatusBox);
                  break;
                case 'paper':
                  _setPaperMode(!_paperMode);
                  break;
                case 'pan':
                  setState(() => _panMode = !_panMode);
                  break;
                case 'zoom_in':
                  _zoomBy(1.25);
                  break;
                case 'zoom_out':
                  _zoomBy(0.8);
                  break;
                case 'reset_view':
                  setState(() {
                    _viewOffset = Offset.zero;
                    _viewScale = 1.0;
                  });
                  break;
              }
            },
            itemBuilder: (ctx) => [
              CheckedPopupMenuItem<String>(
                value: 'pan',
                checked: _panMode,
                child: Text(_tr('Przesuń arkusz (pan)', 'Pan canvas')),
              ),
              PopupMenuItem<String>(
                value: 'zoom_in',
                child: Row(children: [
                  const Icon(Icons.zoom_in, size: 20),
                  const SizedBox(width: 8),
                  Text(_tr('Powiększ', 'Zoom in')),
                ]),
              ),
              PopupMenuItem<String>(
                value: 'zoom_out',
                child: Row(children: [
                  const Icon(Icons.zoom_out, size: 20),
                  const SizedBox(width: 8),
                  Text(_tr('Pomniejsz', 'Zoom out')),
                ]),
              ),
              PopupMenuItem<String>(
                value: 'reset_view',
                child: Row(children: [
                  const Icon(Icons.center_focus_strong, size: 20),
                  const SizedBox(width: 8),
                  Text(_tr('Resetuj widok', 'Reset view')),
                ]),
              ),
              const PopupMenuDivider(),
              CheckedPopupMenuItem<String>(
                value: 'axis',
                checked: _showAxisCompass,
                child: Text(_tr('Panel kierunkowy (OSIE)',
                    'Direction legend (AXES)')),
              ),
              CheckedPopupMenuItem<String>(
                value: 'status',
                checked: _showStatusBox,
                child:
                    Text(_tr('Panel statusu (ISO/SEG/CUT)', 'Status panel')),
              ),
              CheckedPopupMenuItem<String>(
                value: 'paper',
                checked: _paperMode,
                child: Text(_tr('Tryb papierowy (jasny)',
                    'Paper mode (light)')),
              ),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          _Toolbar(tool: _tool, onTool: (t) => setState(() => _tool = t), cs: cs),
          Expanded(
            child: Stack(
              children: [
                Positioned.fill(
                  child: GestureDetector(
                    onPanStart: _panStart,
                    onPanUpdate: _panUpdate,
                    onPanEnd: _panEnd,
                    onTapUp: _tapUp,
                    onLongPressStart: _longPress,
                    child: RepaintBoundary(
                      key: _canvasKey,
                      child: Semantics(
                        label: _tr(
                          'Płótno szkicu izometrycznego — przeciągnij aby rysować, dotknij aby wybrać',
                          'Isometric sketch canvas — drag to draw, tap to select',
                        ),
                        container: true,
                        child: CustomPaint(
                          painter: _Painter(
                            items: _items,
                            version: _version,
                            dragA: _dragA,
                            dragB: _dragB,
                            tool: _tool,
                            s: _s,
                            cs: cs,
                            mapping: mapping,
                            projectName: _projectName,
                            // Ghost extension shows which iso axis the snap is
                            // locked to — only meaningful for the pipe tool with
                            // axis-lock on. Other line tools fall back to free
                            // grid snap, so the hint would be misleading.
                            axisLock: _axisLock && _tool == _Tool.pipe,
                            showStatusBox: _showStatusBox,
                            paperMode: _paperMode,
                            viewOffset: _viewOffset,
                            viewScale: _viewScale,
                          ),
                          size: Size.infinite,
                        ),
                      ),
                    ),
                  ),
                ),
                // Compass legend — fixed top-right, pass-through taps below.
                // Hidden via app-bar "Widok" menu when the fitter wants
                // the canvas un-occluded for a busy iso.
                if (_showAxisCompass)
                  Positioned(
                    top: 8,
                    right: 8,
                    child: IgnorePointer(
                      child: _AxisCompass(cs: cs, mapping: mapping),
                    ),
                  ),
                // Empty-state hint — only shows when the canvas is bare so
                // the first-time user knows what to do; disappears on first
                // pipe so it never gets in the way of real work. Users can
                // dismiss it via the ×; preference persists across sessions
                // and is re-enabled from the app bar Help button.
                if (_items.isEmpty && _hintLoaded && !_hintHidden)
                  Positioned(
                    bottom: 16,
                    left: 16,
                    right: 16,
                    child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        decoration: BoxDecoration(
                          color: cs.surface.withValues(alpha: 0.92),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                              color: cs.primary.withValues(alpha: 0.4), width: 1),
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(Icons.touch_app_outlined, color: cs.primary, size: 16),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    _tr('Jak narysować rurociąg',
                                        'How to draw a route'),
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w900,
                                      color: cs.primary,
                                      letterSpacing: 1.0,
                                    ),
                                  ),
                                ),
                                InkWell(
                                  onTap: () => _setHintHidden(true),
                                  child: Padding(
                                    padding: const EdgeInsets.all(4),
                                    child: Icon(Icons.close,
                                        size: 16, color: cs.onSurfaceVariant),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text(
                              _tr(
                                '1. Wybierz "Rura" z paska narzędzi\n'
                                '2. Przeciągnij palcem po siatce\n'
                                '3. Kolanka wstawiają się automatycznie\n'
                                '4. Dotknij linii, by wpisać wymiar\n'
                                '5. Przytrzymaj element, by go usunąć (z Cofnij)\n'
                                'Wskazówka: pasek KSZTAŁTKI przewija się w bok — przeciągnij, by zobaczyć resztę',
                                '1. Pick "Pipe" from the toolbar\n'
                                '2. Drag across the grid\n'
                                '3. Elbows auto-insert at corners\n'
                                '4. Tap a line to enter its dimension\n'
                                '5. Long-press an element to delete it (with Undo)\n'
                                'Tip: the FITTINGS row scrolls sideways — drag to see the rest',
                              ),
                              style: TextStyle(
                                fontSize: 11.5,
                                height: 1.45,
                                color: cs.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
              ],
            ),
          ),
          _SummaryBar(
            tool: _tool,
            pipeCount: pipeCount,
            dimensioned: dimensioned,
            totalMm: totalMm,
            cs: cs,
          ),
        ],
      ),
    );
  }
}

// ─── Toolbar ──────────────────────────────────────────────────────────────────

class _Toolbar extends StatelessWidget {
  final _Tool tool;
  final ValueChanged<_Tool> onTool;
  final ColorScheme cs;
  const _Toolbar({required this.tool, required this.onTool, required this.cs});

  @override
  Widget build(BuildContext context) {
    final lineItems = <(_Tool, IconData, String)>[
      (_Tool.pipe,   Icons.remove,          context.tr(pl: 'Rura',   en: 'Pipe')),
      (_Tool.thin,   Icons.horizontal_rule, context.tr(pl: 'Linia',  en: 'Line')),
      (_Tool.dashed, Icons.more_horiz,      context.tr(pl: 'Ukryta', en: 'Hidden')),
    ];
    final fittingItems = <(_Tool, IconData, String)>[
      (_Tool.elbow90,        Icons.turn_right,            context.tr(pl: 'Kolano 90°', en: 'Elbow 90°')),
      (_Tool.elbow45,        Icons.turn_slight_right,     context.tr(pl: 'Kolano 45°', en: 'Elbow 45°')),
      (_Tool.tee,            Icons.call_split,            context.tr(pl: 'Trójnik',    en: 'Tee')),
      (_Tool.olet,           Icons.arrow_drop_up,         context.tr(pl: 'Olet',       en: 'Olet')),
      (_Tool.reducer,        Icons.compress,              context.tr(pl: 'Redukcja',   en: 'Reducer')),
      (_Tool.flange,         Icons.view_column_outlined,  context.tr(pl: 'Kołnierz',   en: 'Flange')),
      (_Tool.blindFlange,    Icons.stop_circle_outlined,  context.tr(pl: 'Ślepy',      en: 'Blind')),
      (_Tool.cap,            Icons.crop_square,           context.tr(pl: 'Zaślepka',   en: 'Cap')),
      (_Tool.gateValve,      Icons.settings_input_svideo, context.tr(pl: 'Zasuwa',     en: 'Gate v.')),
      (_Tool.ballValve,      Icons.circle,                context.tr(pl: 'Kulowy',     en: 'Ball v.')),
      (_Tool.checkValve,     Icons.play_arrow,            context.tr(pl: 'Zwrotny',    en: 'Check v.')),
      (_Tool.globeValve,     Icons.adjust,                context.tr(pl: 'Grzybek',    en: 'Globe v.')),
      (_Tool.butterflyValve, Icons.disc_full,             context.tr(pl: 'Motylek',    en: 'Butterfly')),
      (_Tool.weld,           Icons.radio_button_unchecked,context.tr(pl: 'Spoina W',   en: 'Shop weld')),
      (_Tool.fieldWeld,      Icons.radio_button_checked,  context.tr(pl: 'Spoina M',   en: 'Field weld')),
      (_Tool.support,        Icons.change_history,        context.tr(pl: 'Podpora',    en: 'Support')),
      (_Tool.instrument,     Icons.circle_outlined,       context.tr(pl: 'Instrument', en: 'Instrument')),
      (_Tool.spoolBreak,     Icons.content_cut,           context.tr(pl: 'Podział',    en: 'Spool brk')),
    ];
    final annoItems = <(_Tool, IconData, String)>[
      (_Tool.northArrow, Icons.navigation, context.tr(pl: 'Północ',   en: 'North')),
      (_Tool.flowArrow,  Icons.east,       context.tr(pl: 'Przepływ', en: 'Flow')),
      (_Tool.text,       Icons.text_fields,context.tr(pl: 'Tekst',    en: 'Text')),
    ];

    Widget chip((_Tool, IconData, String) e) {
      final sel = tool == e.$1;
      return GestureDetector(
        onTap: () => onTool(e.$1),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          margin: const EdgeInsets.symmetric(horizontal: 3),
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
          decoration: BoxDecoration(
            color: sel ? cs.primaryContainer : Colors.transparent,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: sel ? cs.primary : cs.outlineVariant,
              width: sel ? 1.5 : 1.0,
            ),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(e.$2, size: 15, color: sel ? cs.primary : cs.onSurfaceVariant),
            const SizedBox(width: 4),
            Text(e.$3,
              style: TextStyle(
                fontSize: 11,
                fontWeight: sel ? FontWeight.bold : FontWeight.normal,
                color: sel ? cs.primary : cs.onSurface,
              )),
          ]),
        ),
      );
    }

    Widget groupLabel(String s) => Padding(
          padding: const EdgeInsets.only(right: 4),
          child: Text(s,
              style: TextStyle(
                  fontSize: 10,
                  color: cs.onSurfaceVariant,
                  fontWeight: FontWeight.w700)),
        );

    return Container(
      color: cs.surfaceContainerHigh,
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.fromLTRB(8, 5, 8, 2),
          child: Row(children: [
            groupLabel(context.tr(pl: 'LINIE', en: 'LINES')),
            ...lineItems.map(chip),
            const SizedBox(width: 10),
            Container(width: 1, height: 20, color: cs.outlineVariant),
            const SizedBox(width: 10),
            groupLabel(context.tr(pl: 'KSZTAŁTKI', en: 'FITTINGS')),
            ...fittingItems.map(chip),
          ]),
        ),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.fromLTRB(8, 0, 8, 5),
          child: Row(children: [
            groupLabel(context.tr(pl: 'OPISY', en: 'ANNOTATIONS')),
            ...annoItems.map(chip),
          ]),
        ),
      ]),
    );
  }
}

// ─── Summary bar ──────────────────────────────────────────────────────────────

class _SummaryBar extends StatelessWidget {
  final _Tool tool;
  final int pipeCount;
  final int dimensioned;
  final double totalMm;
  final ColorScheme cs;
  const _SummaryBar({
    required this.tool,
    required this.pipeCount,
    required this.dimensioned,
    required this.totalMm,
    required this.cs,
  });

  @override
  Widget build(BuildContext context) {
    final String hint;
    if (tool.isLine) {
      hint = context.tr(
          pl: 'Przeciągnij rurę → wpisz ISO. Dotknij → edytuj • przytrzymaj → usuń',
          en: 'Drag a pipe → enter ISO. Tap → edit • long-press → remove');
    } else if (tool.isText) {
      hint = context.tr(
          pl: 'Dotknij → dodaj/edytuj tekst (nr linii, rzędna) • przytrzymaj → usuń',
          en: 'Tap → add/edit text (line no., elevation) • long-press → remove');
    } else if (tool == _Tool.spoolBreak) {
      hint = context.tr(
          pl: 'Postaw na rurze, by podzielić rurociąg na spoole (SP-001…) wysyłane osobno do montażu',
          en: 'Place on a pipe to split the route into spools (SP-001…) shipped separately to the site');
    } else if (tool == _Tool.elbow90 || tool == _Tool.elbow45) {
      // Re-tapping a placed elbow opens its DN/type/CTE spec sheet
      // (needed for the CUT take-out), NOT the generic rotate-again
      // behaviour — without this hint the spec dialog feels hidden.
      hint = context.tr(
          pl: 'Dotknij → umieść • ponownie → wpisz DN/typ (CTE) • przytrzymaj → usuń',
          en: 'Tap → place • again → enter DN/type (CTE) • long-press → remove');
    } else {
      hint = context.tr(
          pl: 'Dotknij → umieść • ponownie → obróć • przytrzymaj → usuń',
          en: 'Tap → place • again → rotate • long-press → remove');
    }

    return Container(
      color: cs.surfaceContainerHigh,
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 6),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (pipeCount > 0)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                children: [
                  Icon(Icons.content_cut, size: 14, color: cs.primary),
                  const SizedBox(width: 6),
                  Text(
                    '${context.tr(pl: 'Odcinki', en: 'Segments')}: '
                    '$dimensioned/$pipeCount',
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: cs.onSurface),
                  ),
                  const Spacer(),
                  Text(
                    '${context.tr(pl: 'Suma CUT', en: 'Total CUT')}: '
                    '${totalMm.toStringAsFixed(1)} mm',
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: cs.primary),
                  ),
                ],
              ),
            ),
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(
              tool.isComp ? Icons.info_outline : Icons.touch_app_outlined,
              size: 14,
              color: cs.onSurfaceVariant,
            ),
            const SizedBox(width: 6),
            Flexible(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 180),
                transitionBuilder: (child, anim) =>
                    FadeTransition(opacity: anim, child: child),
                child: Text(hint,
                  key: ValueKey<String>(hint),
                  style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
                  overflow: TextOverflow.ellipsis),
              ),
            ),
          ]),
        ],
      ),
    );
  }
}

// ─── Painter ──────────────────────────────────────────────────────────────────

class _Painter extends CustomPainter {
  final List<_Item> items;
  final int version; // ticks on every mutation so shouldRepaint catches it
  final Offset? dragA, dragB;
  final _Tool tool;
  final double s;
  final ColorScheme cs;
  final _AxisMapping? mapping;
  final String projectName;
  final bool axisLock;
  final bool showStatusBox;
  final bool paperMode;
  final Offset viewOffset;
  final double viewScale;

  const _Painter({
    required this.items,
    required this.version,
    required this.dragA,
    required this.dragB,
    required this.tool,
    required this.s,
    required this.cs,
    required this.mapping,
    required this.projectName,
    this.axisLock = false,
    this.showStatusBox = true,
    this.paperMode = false,
    this.viewOffset = Offset.zero,
    this.viewScale = 1.0,
  });

  /// Background colour — white in paper mode, theme surface otherwise.
  /// Centralised so every paint path uses the same lookup; lets the rest of
  /// the painter stay agnostic about which mode it is rendering in.
  Color get _bgColor =>
      paperMode ? const Color(0xFFFAF9F2) : cs.surface;

  /// Foreground "ink" colour — black-ish in paper mode for classic engineering
  /// paper look; theme primary in dark mode.
  Color get _inkColor =>
      paperMode ? const Color(0xFF1A1A1A) : cs.primary;

  /// Grid colour — soft gray in paper mode, theme onSurface low alpha
  /// in dark mode.
  Color get _gridColor =>
      paperMode
          ? const Color(0x33606060)
          : cs.onSurface.withValues(alpha: 0.10);

  static const _sqrt3 = 1.7320508075688772;

  @override
  void paint(Canvas canvas, Size size) {
    _drawBg(canvas, size);
    // World-space layers go through the viewport transform so pan / zoom
    // moves the drawing under the fixed overlays (status box + legend stay
    // anchored to screen edges in their original screen coords).
    canvas.save();
    canvas.translate(viewOffset.dx, viewOffset.dy);
    canvas.scale(viewScale);
    _drawGrid(canvas, size);
    _drawItems(canvas);
    if (dragA != null && dragB != null) _drawPreview(canvas);
    canvas.restore();
    if (showStatusBox) _drawTitleBlock(canvas, size);
    _drawColorLegend(canvas, size);
  }

  void _drawColorLegend(Canvas canvas, Size size) {
    const boxW = 60.0;
    const boxH = 72.0;
    const margin = 12.0;
    final ox = size.width - boxW - margin;
    final oy = size.height - boxH - margin;
    final rect = Rect.fromLTWH(ox, oy, boxW, boxH);

    canvas.drawRect(rect, Paint()..color = cs.surface.withValues(alpha: 0.9));
    canvas.drawRect(
      rect,
      Paint()
        ..color = cs.primary.withValues(alpha: 0.8)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0,
    );

    const rows = <(Color, String)>[
      (Color(0xFF4A9EFF), 'I'),
      (Color(0xFF2ECC71), 'II'),
      (Color(0xFFE8C14B), 'III'),
    ];
    const pad = 6.0;
    const rowH = 14.0;
    const barW = 12.0;
    const barH = 3.0;
    for (int i = 0; i < rows.length; i++) {
      final (color, label) = rows[i];
      final yMid = oy + pad + i * rowH + rowH / 2;
      canvas.drawRect(
        Rect.fromLTWH(ox + pad, yMid - barH / 2, barW, barH),
        Paint()..color = color,
      );
      final tp = TextPainter(
        text: TextSpan(
          text: label,
          style: TextStyle(
            color: cs.onSurface,
            fontSize: 9,
            fontWeight: FontWeight.w700,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(ox + pad + barW + 4, yMid - tp.height / 2));
    }
    // Slope row uses error colour to match _drawSlope chip.
    final yMid = oy + pad + rows.length * rowH + rowH / 2;
    canvas.drawRect(
      Rect.fromLTWH(ox + pad, yMid - barH / 2, barW, barH),
      Paint()..color = cs.error,
    );
    final tpSlope = TextPainter(
      text: TextSpan(
        text: 'slope',
        style: TextStyle(
          color: cs.onSurface,
          fontSize: 9,
          fontWeight: FontWeight.w700,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tpSlope.paint(canvas, Offset(ox + pad + barW + 4, yMid - tpSlope.height / 2));
  }

  /// Title block in the bottom-left corner of the canvas. Real iso drawings
  /// always have one in the corner with the line number, date, sheet number
  /// and total. We get it for free in the PDF export this way (the title
  /// block is part of the painter, not a Flutter widget overlay).
  void _drawTitleBlock(Canvas canvas, Size size) {
    // Single pass over `items` — was three lazy chains (whereType+where+toList
    // for pipes, whereType+where+length for comps). Painter runs on every
    // frame the canvas needs repainting (drag, snap preview, axis lock
    // toggle), so the per-frame allocations added up on routes with 100+
    // items.
    var pipeCount = 0;
    var dimensioned = 0;
    var compCount = 0;
    double total = 0;
    for (final it in items) {
      if (it is _Seg) {
        if (it.t != _Tool.pipe) continue;
        pipeCount++;
        final c = it.calc;
        if (c == null) continue;
        dimensioned++;
        final v = c.cutMm;
        if (v.isFinite) total += v;
      } else if (it is _Comp) {
        if (it.t == _Tool.northArrow || it.t == _Tool.flowArrow) continue;
        compCount++;
      }
    }
    if (pipeCount == 0 && projectName.isEmpty) return;

    final now = DateTime.now();
    final dateStamp =
        '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';

    final lines = <(String, String)>[
      (projectName.isEmpty ? 'ISO' : 'LINE', projectName.isEmpty ? '—' : projectName),
      ('DATE', dateStamp),
      ('SEG', '$dimensioned / $pipeCount'),
      ('CUT', '${total.toStringAsFixed(0)} mm'),
      ('BOM', '$compCount'),
    ];

    final pad = 8.0;
    final colW = 38.0;
    final lineH = 13.0;
    final boxW = 168.0;
    final boxH = lines.length * lineH + pad * 2 + 14; // +14 for title row
    final ox = pad;
    final oy = size.height - boxH - pad;
    final rect = Rect.fromLTWH(ox, oy, boxW, boxH);

    canvas.drawRect(rect, Paint()..color = cs.surface.withValues(alpha: 0.92));
    canvas.drawRect(
      rect,
      Paint()
        ..color = cs.primary.withValues(alpha: 0.8)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2,
    );
    // Header bar
    final headerRect = Rect.fromLTWH(ox, oy, boxW, 14);
    canvas.drawRect(headerRect, Paint()..color = cs.primary.withValues(alpha: 0.18));

    final tpHeader = TextPainter(
      text: TextSpan(
        text: 'FITTER WELDER PRO · ISO',
        style: TextStyle(
          color: cs.primary,
          fontSize: 8.5,
          fontWeight: FontWeight.w900,
          letterSpacing: 1.2,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tpHeader.paint(canvas, Offset(ox + pad, oy + 2));

    for (int i = 0; i < lines.length; i++) {
      final y = oy + 14 + pad + i * lineH;
      final tpLabel = TextPainter(
        text: TextSpan(
          text: lines[i].$1,
          style: TextStyle(
            color: cs.onSurfaceVariant,
            fontSize: 9,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.5,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tpLabel.paint(canvas, Offset(ox + pad, y));
      final tpVal = TextPainter(
        text: TextSpan(
          text: lines[i].$2,
          style: TextStyle(
            color: cs.onSurface,
            fontSize: 10,
            fontWeight: FontWeight.w700,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: boxW - colW - pad * 2);
      tpVal.paint(canvas, Offset(ox + pad + colW, y - 1));
    }
  }

  void _drawBg(Canvas canvas, Size size) {
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, size.height),
      Paint()..color = _bgColor,
    );
  }

  void _drawGrid(Canvas canvas, Size size) {
    final dy = s * _sqrt3 / 2.0;
    final cStep = _sqrt3 * s;
    final gridPaint = Paint()
      ..color = _gridColor
      ..strokeWidth = 0.65;

    for (double y = 0; y <= size.height + dy; y += dy) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }
    {
      final cMin = -_sqrt3 * size.width - cStep;
      final cMax = size.height + cStep;
      int k = (cMin / cStep).floor();
      while (k * cStep <= cMax) {
        final c = k * cStep;
        double x1, y1, x2, y2;
        if (c >= 0) { x1 = 0; y1 = c; }
        else        { x1 = -c / _sqrt3; y1 = 0; }
        final yR = _sqrt3 * size.width + c;
        if (yR <= size.height) { x2 = size.width; y2 = yR; }
        else                   { x2 = (size.height - c) / _sqrt3; y2 = size.height; }
        if (x2 >= 0 && x1 <= size.width) {
          canvas.drawLine(Offset(x1, y1), Offset(x2, y2), gridPaint);
        }
        k++;
      }
    }
    {
      final cMin = -cStep;
      final cMax = size.height + _sqrt3 * size.width + cStep;
      int k = (cMin / cStep).floor();
      while (k * cStep <= cMax) {
        final c = k * cStep;
        double x1, y1, x2, y2;
        if (c >= 0 && c <= size.height) { x1 = 0; y1 = c; }
        else if (c > size.height)       { x1 = (c - size.height) / _sqrt3; y1 = size.height; }
        else                            { x1 = c / _sqrt3; y1 = 0; }
        final yR = c - _sqrt3 * size.width;
        if (yR >= 0 && yR <= size.height) { x2 = size.width; y2 = yR; }
        else if (yR < 0)                  { x2 = c / _sqrt3; y2 = 0; }
        else                              { x2 = (c - size.height) / _sqrt3; y2 = size.height; }
        if (x2 >= 0 && x1 <= size.width) {
          canvas.drawLine(Offset(x1, y1), Offset(x2, y2), gridPaint);
        }
        k++;
      }
    }

    final dotPaint = Paint()
      ..color = paperMode
          ? const Color(0x66606060)
          : cs.onSurface.withValues(alpha: 0.22)
      ..strokeCap = StrokeCap.round;
    final rows = (size.height / dy).ceil() + 2;
    final cols = (size.width / s).ceil() + 4;
    for (int row = 0; row <= rows; row++) {
      final y = row * dy;
      final xOff = (row % 2 == 0) ? 0.0 : s / 2.0;
      for (int col = -1; col <= cols; col++) {
        canvas.drawCircle(Offset(col * s + xOff, y), 1.5, dotPaint);
      }
    }
  }

  void _drawItems(Canvas canvas) {
    for (final it in items) {
      if (it is _Seg) _drawSeg(canvas, it.a, it.b, it.t, alpha: 1.0);
    }
    // Insulation overlay — drawn after main pipes so cladding sits outside.
    for (final it in items) {
      if (it is _Seg && it.t == _Tool.pipe && it.insulated) {
        _drawInsulationOverlay(canvas, it);
      }
    }
    // Auto-weld marker — small open circle at every collinear pipe junction
    // (two pipe segments end at the same point with no fitting between them).
    // Tells the fitter "here goes a shop butt weld" without forcing them to
    // place a weld component manually.
    _drawAutoWelds(canvas);
    // Axis label on every pipe — small chip at midpoint, opposite side from
    // the dimension chip if the segment has one. Off-axis lines get a warning
    // colour to flag drafting errors (sloped pipes are rare in iso).
    for (final it in items) {
      if (it is _Seg && it.t == _Tool.pipe) _drawAxisTag(canvas, it);
    }
    for (final it in items) {
      if (it is _Seg && it.calc != null) _drawDim(canvas, it);
    }
    for (final it in items) {
      if (it is _Seg && it.hasSlope) _drawSlope(canvas, it);
    }
    for (final it in items) {
      if (it is _Comp) {
        _drawComp(canvas, it);
        if (it.label.isNotEmpty) _drawCompLabel(canvas, it);
        if (it.isElbow && it.dn != null) _drawElbowSpecLabel(canvas, it);
        _drawMissingDataRing(canvas, it);
      }
    }
    _drawJointLabels(canvas);
    _drawSpoolNumbers(canvas);
    for (final it in items) {
      if (it is _Note) _drawNote(canvas, it);
    }
  }

  /// Sequential SP-001, SP-002 … tags on every spool break so the prefab
  /// shop can track each spool through fabrication. Same reading-order sort
  /// as _drawJointLabels; chip sits ABOVE the symbol to clear any joint
  /// circle that lives in the lower-left.
  void _drawSpoolNumbers(Canvas canvas) {
    final breaks = <_Comp>[];
    for (final it in items) {
      if (it is _Comp && it.t == _Tool.spoolBreak) breaks.add(it);
    }
    if (breaks.isEmpty) return;
    breaks.sort((a, b) {
      final dy = a.pos.dy.compareTo(b.pos.dy);
      if (dy != 0) return dy;
      return a.pos.dx.compareTo(b.pos.dx);
    });
    for (int i = 0; i < breaks.length; i++) {
      final c = breaks[i];
      final label = 'SP-${(i + 1).toString().padLeft(3, '0')}';
      final tp = TextPainter(
        text: TextSpan(
          text: label,
          style: TextStyle(
            color: cs.tertiary,
            fontSize: 9.5,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.3,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      final pos = c.pos + Offset(0, -s * 0.55);
      final rect = Rect.fromCenter(
          center: pos, width: tp.width + 6, height: tp.height + 3);
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(3)),
        Paint()..color = cs.surface,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(3)),
        Paint()
          ..color = cs.tertiary.withValues(alpha: 0.85)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.0,
      );
      tp.paint(canvas, pos - Offset(tp.width / 2, tp.height / 2));
    }
  }

  /// Auto-derived alphabetic joint labels (A, B, C … Z, AA, AB …) sitting in
  /// a tiny circle next to every non-weld, non-arrow component. Mirrors the
  /// way a real ASME iso tags joints for cross-referencing with the BOM and
  /// weld map. Sort order is top-to-bottom, left-to-right so the alphabet
  /// runs across the drawing in reading order. Index-based assignment is
  /// recomputed every frame — no storage on _Comp.
  void _drawJointLabels(Canvas canvas) {
    final tagged = <_Comp>[];
    for (final it in items) {
      if (it is! _Comp) continue;
      if (it.t.isWeld) continue;
      if (it.t == _Tool.northArrow ||
          it.t == _Tool.flowArrow ||
          it.t == _Tool.text) {
        continue;
      }
      tagged.add(it);
    }
    tagged.sort((a, b) {
      final dy = a.pos.dy.compareTo(b.pos.dy);
      if (dy != 0) return dy;
      return a.pos.dx.compareTo(b.pos.dx);
    });

    for (int i = 0; i < tagged.length; i++) {
      final c = tagged[i];
      final letter = _alphaLabel(i);
      // Sit on the lower-left of the symbol so it doesn't clash with the
      // existing upper-right CTE / spec labels. Half-grid offset so it
      // visibly belongs to this component without overlapping it.
      final pos = c.pos + Offset(-s * 0.42, s * 0.4);
      const r = 7.5;
      canvas.drawCircle(pos, r, Paint()..color = cs.surface);
      canvas.drawCircle(
        pos,
        r,
        Paint()
          ..color = cs.primary.withValues(alpha: 0.85)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2,
      );
      final tp = TextPainter(
        text: TextSpan(
          text: letter,
          style: TextStyle(
            color: cs.primary,
            fontSize: 9,
            fontWeight: FontWeight.w900,
            letterSpacing: 0.5,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, pos - Offset(tp.width / 2, tp.height / 2));
    }
  }

  /// 0 → A, 25 → Z, 26 → AA, 27 → AB, etc. Base-26 numeric labelling so
  /// drawings with >26 components keep producing unique tags without
  /// rolling over.
  static String _alphaLabel(int i) {
    var n = i;
    final buf = StringBuffer();
    while (true) {
      buf.write(String.fromCharCode(65 + (n % 26)));
      n = n ~/ 26 - 1;
      if (n < 0) break;
    }
    return buf.toString().split('').reversed.join();
  }

  /// Slope tag chip on a sloped pipe — text chip with a tiny downhill-arrow
  /// glyph PLUS short perpendicular hash marks along the segment to call
  /// attention to the fact that this run is intentionally off-level (drain
  /// side, vent etc.). Matches the ASME convention of hatching a sloped
  /// pipe so it can't be confused with horizontal lines on a busy iso.
  void _drawSlope(Canvas canvas, _Seg seg) {
    final d = seg.b - seg.a;
    final len = d.distance;
    if (len < s * 0.6) return;
    final norm = Offset(-d.dy / len, d.dx / len);
    final anchor = seg.a + d * 0.25;
    final pos = anchor + norm * 15;
    final color = cs.error;

    // Hash marks: 4 short ticks perpendicular to the segment, equally
    // spaced along the middle 50% of the run so they don't crowd the
    // endpoints. Each tick straddles the centreline by ±0.16 * s.
    final hashPaint = Paint()
      ..color = color.withValues(alpha: 0.65)
      ..strokeWidth = 1.6
      ..strokeCap = StrokeCap.round;
    const ticks = 4;
    for (int i = 0; i < ticks; i++) {
      final t = 0.30 + (i / (ticks - 1)) * 0.40;
      final centre = seg.a + d * t;
      final off = Offset(norm.dx * s * 0.18, norm.dy * s * 0.18);
      canvas.drawLine(centre - off, centre + off, hashPaint);
    }

    // Reversed-fall tag: monter can flip the downhill arrow toward the
    // opposite end by tagging the slope with "REV" or a leading "-".
    final raw = seg.slope;
    final revRe = RegExp(r'^\s*-\s*|\bREV(?:ERSED)?\b\s*', caseSensitive: false);
    final reversed = revRe.hasMatch(raw);
    final cleaned = raw.replaceAll(revRe, '').trim();
    final arrow = reversed ? '↙' : '↘';
    final text = '$arrow $cleaned';
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.w800,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    final rect = Rect.fromCenter(
        center: pos, width: tp.width + 10, height: tp.height + 4);
    final rr = RRect.fromRectAndRadius(rect, const Radius.circular(4));
    canvas.drawRRect(rr, Paint()..color = cs.surface);
    canvas.drawRRect(
      rr,
      Paint()
        ..color = color.withValues(alpha: 0.6)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.9,
    );
    tp.paint(canvas, pos - Offset(tp.width / 2, tp.height / 2));
  }

  /// Tiny coloured chip with the axis Roman numeral ("I", "II", "III") so the
  /// monter sees at a glance which 3D direction this pipe runs in. Drawn on
  /// the opposite side from the dim chip to avoid overlap.
  void _drawAxisTag(Canvas canvas, _Seg seg) {
    final axis = _classifyAxis(seg.a, seg.b);
    final mid = (seg.a + seg.b) / 2;
    final d = seg.b - seg.a;
    final len = d.distance;
    if (len < s * 0.6) return; // too short to bother
    final norm = Offset(-d.dy / len, d.dx / len);
    // Sit on the same side as the dim chip if there's no dim, otherwise flip.
    final side = seg.calc != null ? -1.0 : 1.0;
    final pos = mid + norm * 15 * side;

    final color = switch (axis) {
      _Axis.i => const Color(0xFF4A9EFF),   // blue
      _Axis.ii => const Color(0xFF2ECC71),  // green
      _Axis.iii => const Color(0xFFE8C14B), // gold
      _Axis.off => cs.error,
    };
    // With an N-arrow placed, prefer the directional label (N/S/E/W/↑/↓);
    // without one, fall back to the anonymous Roman numeral.
    final String text;
    if (axis == _Axis.off) {
      text = '⚠';
    } else {
      final dirLabel = mapping?.labelForLine(seg.a, seg.b) ?? '';
      text = dirLabel.isNotEmpty ? dirLabel : axis.label;
    }
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.w900,
          letterSpacing: 0.5,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    final rect = Rect.fromCenter(
        center: pos, width: tp.width + 8, height: tp.height + 3);
    final rr = RRect.fromRectAndRadius(rect, const Radius.circular(4));
    canvas.drawRRect(
      rr,
      Paint()..color = color.withValues(alpha: 0.14),
    );
    canvas.drawRRect(
      rr,
      Paint()
        ..color = color.withValues(alpha: 0.45)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.8,
    );
    tp.paint(canvas, pos - Offset(tp.width / 2, tp.height / 2));
  }

  void _drawSeg(Canvas canvas, Offset a, Offset b, _Tool t, {double alpha = 1.0}) {
    final color = cs.primary.withValues(alpha: alpha);
    switch (t) {
      case _Tool.pipe:
        // Faint tint inside the pipe stroke matches the axis tag colour so
        // I/II/III are distinguishable from a quick visual scan even without
        // reading the chips. Off-axis stays primary.
        final axis = _classifyAxis(a, b);
        final tint = switch (axis) {
              _Axis.i => const Color(0xFF4A9EFF),
              _Axis.ii => const Color(0xFF2ECC71),
              _Axis.iii => const Color(0xFFE8C14B),
              _Axis.off => cs.primary,
            };
        // Mix tint with primary so it's only a subtle cast.
        final strokeColor = Color.lerp(color, tint, 0.35) ?? color;
        canvas.drawLine(a, b,
          Paint()..color = strokeColor..strokeWidth = 5.0..strokeCap = StrokeCap.round);
        canvas.drawCircle(a, 5.5, Paint()..color = strokeColor);
        canvas.drawCircle(b, 5.5, Paint()..color = strokeColor);
      case _Tool.thin:
        canvas.drawLine(a, b,
          Paint()..color = color..strokeWidth = 1.5..strokeCap = StrokeCap.round);
      case _Tool.dashed:
        _dashed(canvas, a, b,
          Paint()..color = color..strokeWidth = 2.0..strokeCap = StrokeCap.round);
      default: break;
    }
  }

  /// Auto-weld pass: every grid point where two pipe segments meet, with
  /// no component already there and no elbow/tee already inserted, gets a
  /// small open circle marking a shop butt weld. The marker is purely
  /// visual — it does NOT add a `_Comp` to [items], so the BOM/weld count
  /// stays under the user's manual control.
  void _drawAutoWelds(Canvas canvas) {
    // Bucket endpoints by snapped grid position. We compare positions with
    // a tolerance of s*0.25 (same as junction detection elsewhere).
    final endpoints = <Offset>[];
    final compPositions = <Offset>[];
    for (final it in items) {
      if (it is _Seg && it.t == _Tool.pipe) {
        endpoints.add(it.a);
        endpoints.add(it.b);
      }
      if (it is _Comp) compPositions.add(it.pos);
    }
    bool nearAny(Offset p, List<Offset> list) {
      for (final q in list) {
        if ((q - p).distance < s * 0.45) return true;
      }
      return false;
    }

    final junctionPaint = Paint()
      ..color = cs.tertiary
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;
    final junctionFill = Paint()..color = cs.surface;

    // For each unique endpoint, count how many other endpoints land within
    // tolerance. Skip points that already host a fitting.
    final seen = <Offset>[];
    for (final p in endpoints) {
      if (nearAny(p, seen)) continue;
      seen.add(p);
      if (nearAny(p, compPositions)) continue;
      var count = 0;
      for (final q in endpoints) {
        if ((q - p).distance < s * 0.45) count++;
      }
      // count is 2+ when two segments share this point. count==1 is a free
      // end (open pipe stub or connection to equipment); skip those.
      if (count >= 2) {
        canvas.drawCircle(p, 5.0, junctionFill);
        canvas.drawCircle(p, 5.0, junctionPaint);
      }
    }
  }

  /// Parallel dashed lines flanking an insulated pipe. Drawn AFTER the main
  /// pipe so the cladding sits visually outside the carrier; offset matches
  /// roughly the line weight so the insulation reads at a glance.
  void _drawInsulationOverlay(Canvas canvas, _Seg seg) {
    final d = seg.b - seg.a;
    final len = d.distance;
    if (len < 1) return;
    final norm = Offset(-d.dy / len, d.dx / len);
    const off = 7.0; // ~ pipe stroke width + a margin
    final colour = cs.primary.withValues(alpha: 0.55);
    final p = Paint()
      ..color = colour
      ..strokeWidth = 1.2
      ..strokeCap = StrokeCap.round;
    _dashed(canvas, seg.a + norm * off, seg.b + norm * off, p);
    _dashed(canvas, seg.a - norm * off, seg.b - norm * off, p);
  }

  void _dashed(Canvas canvas, Offset a, Offset b, Paint p) {
    const dash = 8.0, gap = 6.0;
    final total = (b - a).distance;
    if (total < 1) return;
    final dir = (b - a) / total;
    double pos = 0;
    bool on = true;
    while (pos < total) {
      final len = math.min(on ? dash : gap, total - pos);
      if (on) canvas.drawLine(a + dir * pos, a + dir * (pos + len), p);
      pos += len;
      on = !on;
    }
  }

  /// Dimension line drawn the same way a draughtsman plots an iso:
  ///   1. thin extension lines from each pipe endpoint, perpendicular to
  ///      the pipe, offset OUTWARD slightly,
  ///   2. dim line parallel to the pipe, between the extensions,
  ///   3. 30° tick-marks at both ends (iso convention — not arrows),
  ///   4. the dimension value centred on the dim line with a small surface
  ///      backdrop so it stays legible over the grid.
  void _drawDim(Canvas canvas, _Seg seg) {
    final c = seg.calc!;
    final d = seg.b - seg.a;
    final len = d.distance;
    if (len < 1) return;
    final unit = Offset(d.dx / len, d.dy / len);
    final norm = Offset(-unit.dy, unit.dx);

    // Auto-deduct elbow CTEs that sit at the segment's endpoints so the
    // CUT shown on the drawing matches what the fitter must saw.
    final autoDeduct = _autoElbowDeductFor(seg, items, s * 0.45);
    final base = c.cutMm;
    final cutMm = base.isFinite ? base - autoDeduct : base;
    final hasAuto = autoDeduct > 0;
    final isCut = c.hasDeducts || hasAuto;
    final accent = isCut ? cs.tertiary : cs.primary;

    // Dim line sits ~16 px out from the pipe centreline (away from the axis
    // chip on the opposite side).
    const dimOffset = 16.0;
    final extA = seg.a + norm * dimOffset;
    final extB = seg.b + norm * dimOffset;
    // Slight extra extension so the tick marks read as terminators, not
    // overshoots.
    final beyondA = seg.a + norm * (dimOffset + 4);
    final beyondB = seg.b + norm * (dimOffset + 4);

    final thin = Paint()
      ..color = accent.withValues(alpha: 0.85)
      ..strokeWidth = 0.9
      ..strokeCap = StrokeCap.round;

    // 1. Extension lines.
    canvas.drawLine(seg.a + norm * 4, beyondA, thin);
    canvas.drawLine(seg.b + norm * 4, beyondB, thin);
    // 2. Dim line.
    canvas.drawLine(extA, extB, thin);
    // 3. 30° tick marks at both ends.
    final tickHalf = Offset(unit.dx + norm.dx, unit.dy + norm.dy) * 3.5;
    canvas.drawLine(extA - tickHalf, extA + tickHalf, thin);
    canvas.drawLine(extB - tickHalf, extB + tickHalf, thin);

    final isoTrim = c.iso.trim();
    final isRef = isoTrim.startsWith('(') && isoTrim.endsWith(')');
    String label;
    if (isRef) {
      label = '(REF) $isoTrim';
    } else if (!cutMm.isFinite) {
      // Unreadable expression: paint the raw ISO so the user sees what they
      // typed, but cap the chip width — a pasted 60-char garbled string would
      // otherwise span the whole canvas and bury adjacent labels.
      final raw = c.iso;
      label = raw.isEmpty ? '?' : (raw.length > 14 ? '${raw.substring(0, 13)}…' : raw);
    } else {
      label = cutMm == cutMm.roundToDouble()
          ? cutMm.toStringAsFixed(0)
          : cutMm.toStringAsFixed(1);
    }

    final tp = TextPainter(
      text: TextSpan(
        text: label,
        style: TextStyle(
          color: isRef ? cs.onSurfaceVariant : accent,
          fontSize: 11.5,
          fontWeight: FontWeight.w900,
          fontStyle: isRef ? FontStyle.italic : FontStyle.normal,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    final mid = (extA + extB) / 2;
    // Move text just above the dim line on the side away from the pipe.
    final textCentre = mid + norm * (tp.height * 0.5 + 1);
    final rect = Rect.fromCenter(
      center: textCentre,
      width: tp.width + 8,
      height: tp.height + 2,
    );
    canvas.drawRect(
      rect,
      Paint()..color = cs.surface.withValues(alpha: 0.95),
    );
    tp.paint(canvas, Offset(rect.left + 4, rect.top));

    // Second line shows the resolved CUT explicitly when auto-deduct
    // applied — so the user sees both the ISO they typed AND the CUT.
    if (isCut && base.isFinite && cutMm.isFinite && base != cutMm) {
      final isoStr = base == base.roundToDouble()
          ? base.toStringAsFixed(0)
          : base.toStringAsFixed(1);
      final sub = TextPainter(
        text: TextSpan(
          text: 'ISO $isoStr',
          style: TextStyle(
            color: cs.onSurfaceVariant,
            fontSize: 9,
            fontWeight: FontWeight.w700,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      final subRect = Rect.fromCenter(
        center: textCentre + norm * (tp.height + 2),
        width: sub.width + 6,
        height: sub.height + 1,
      );
      canvas.drawRect(
        subRect,
        Paint()..color = cs.surface.withValues(alpha: 0.95),
      );
      sub.paint(canvas, Offset(subRect.left + 3, subRect.top));
    }
  }

  void _drawNote(Canvas canvas, _Note note) {
    // Elevation tags — text matching "EL +<num>" or "EL.+<num>" or any case
    // variant render as a tagged-flag marker (small triangle pointing at the
    // anchor point, then the EL string in a chip). Matches the look of real
    // ASME isos where every key point carries an elevation reference.
    final isEl = RegExp(r'^\s*EL\.?\s*[+-]?\s*\d', caseSensitive: false)
        .hasMatch(note.text);
    final isCont = RegExp(r"^\s*CONT'?D?\b", caseSensitive: false)
        .hasMatch(note.text);
    final isPenetration = RegExp(
            r"^\s*(WALL|FLOOR|CEILING|SCIANA|PODLOGA|SUFIT)\b",
            caseSensitive: false)
        .hasMatch(note.text);
    final isTieIn = RegExp(r"^\s*(TIE|TIE-IN)\b", caseSensitive: false)
        .hasMatch(note.text);
    final isBatteryLimit = RegExp(
            r"^\s*(BL|BATTERY LIMIT|GRANICA)\b",
            caseSensitive: false)
        .hasMatch(note.text);
    final isMatchLine = RegExp(
            r"^\s*(MATCH|MATCH ?LINE|LINIA)\b",
            caseSensitive: false)
        .hasMatch(note.text);
    final isEquipment = RegExp(
            r"^\s*(EQ|VESSEL|TANK|PUMP|URZADZENIE)\b",
            caseSensitive: false)
        .hasMatch(note.text);
    final isHeatTrace = RegExp(
            r"^\s*(HT|HEAT ?TRACE|TRACING)\b",
            caseSensitive: false)
        .hasMatch(note.text);
    final isInsulation =
        RegExp(r"^\s*INS\b", caseSensitive: false).hasMatch(note.text);
    final mediumMatch = RegExp(
            r"^\s*(STEAM|WATER|GAS|AIR|OIL|N2|CW|HW|PARA|WODA|POWIETRZE)\b",
            caseSensitive: false)
        .firstMatch(note.text);
    final isScale =
        RegExp(r"^\s*SCALE\b", caseSensitive: false).hasMatch(note.text);
    final isDwgId = RegExp(r"^\s*(DWG|DRAWING) ?ID\b", caseSensitive: false)
        .hasMatch(note.text);
    final titleBlockMatch = RegExp(
            r"^\s*(TITLE|REV|DATE|BY|PROJECT|DOC|RYS\.|TYTUL)\s*[:=]\s*(.*)$",
            caseSensitive: false)
        .firstMatch(note.text);
    final isDrain = RegExp(r"^\s*(DRAIN|DR|SPUST)\b", caseSensitive: false)
        .hasMatch(note.text);
    final isVent = RegExp(r"^\s*(VENT|VT|ODP)\b", caseSensitive: false)
        .hasMatch(note.text);
    final isPressureRating =
        RegExp(r"^\s*PR\b", caseSensitive: false).hasMatch(note.text);
    final isTestPressure =
        RegExp(r"^\s*TP\b", caseSensitive: false).hasMatch(note.text);
    final isSch =
        RegExp(r"^\s*SCH", caseSensitive: false).hasMatch(note.text);
    final isMaterial = RegExp(
            r"^\s*(CS|SS|SS316L?|DSS|ALU|TI|CU|MAT)\b",
            caseSensitive: false)
        .hasMatch(note.text);
    // Mill heat number (HT-####) — must be checked before isHeatTrace, whose
    // "HT" branch also fires on this prefix.
    final isHeatNumber =
        RegExp(r"^\s*HT-", caseSensitive: false).hasMatch(note.text);
    // Valve actuator callout (ACT=MOV, ACT M, ACT=PV, ACT EHV…). ASME piping
    // isos mark every powered valve with the actuator type next to the body so
    // commissioning teams know whether to expect a handwheel, motor, pneumatic
    // or solenoid driver. Drawn as a small actuator glyph (square housing with
    // a top crank stub) followed by the text, in a tertiary-accent chip.
    final isActuator =
        RegExp(r"^\s*ACT\b", caseSensitive: false).hasMatch(note.text);

    final tp = TextPainter(
      text: TextSpan(
        text: isCont ? '→ ${note.text}' : note.text,
        style: TextStyle(
          color: cs.onSurface,
          fontSize: 12.5,
          fontWeight: FontWeight.w700,
          fontFeatures: isScale
              ? const [FontFeature.tabularFigures()]
              : null,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    if (isScale) {
      // Title-block scale entry: rectangular border (no fill) with ruler-style
      // cross-hairs at each end so the chip reads like a drafting scale bar.
      final rect = Rect.fromCenter(
          center: note.pos, width: tp.width + 18, height: tp.height + 8);
      canvas.drawRect(
        rect,
        Paint()
          ..color = cs.onSurface
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5,
      );
      final tick = Paint()
        ..color = cs.onSurface
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2;
      const tickArm = 3.0;
      // Left cross-hair: vertical bar through edge + horizontal stub outward.
      canvas.drawLine(
        Offset(rect.left, rect.center.dy - tickArm),
        Offset(rect.left, rect.center.dy + tickArm),
        tick,
      );
      canvas.drawLine(
        Offset(rect.left - tickArm, rect.center.dy),
        Offset(rect.left + tickArm, rect.center.dy),
        tick,
      );
      canvas.drawLine(
        Offset(rect.right, rect.center.dy - tickArm),
        Offset(rect.right, rect.center.dy + tickArm),
        tick,
      );
      canvas.drawLine(
        Offset(rect.right - tickArm, rect.center.dy),
        Offset(rect.right + tickArm, rect.center.dy),
        tick,
      );
      tp.paint(canvas, note.pos - Offset(tp.width / 2, tp.height / 2));
      return;
    }

    if (isDwgId) {
      // Stamp-style ID chip: tabular figures so the hash reads as a fixed-pitch
      // identifier, with outlineVariant fill so it blends into the sheet like
      // a rubber stamp rather than competing with active callouts.
      final idTp = TextPainter(
        text: TextSpan(
          text: '# ${note.text}',
          style: TextStyle(
            color: cs.onSurface,
            fontSize: 12.0,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.3,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      final rect = Rect.fromCenter(
          center: note.pos, width: idTp.width + 14, height: idTp.height + 7);
      final rr = RRect.fromRectAndRadius(rect, const Radius.circular(3));
      canvas.drawRRect(rr, Paint()..color = cs.outlineVariant);
      canvas.drawRRect(
        rr,
        Paint()
          ..color = cs.onSurface.withValues(alpha: 0.55)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.0,
      );
      idTp.paint(canvas, note.pos - Offset(idTp.width / 2, idTp.height / 2));
      return;
    }

    if (isSch) {
      // Pipe-schedule stamp (SCH40 / SCH80 / SCH10S …): thick square border +
      // wide letter-spacing so the chip reads like the spec stamp rolled onto
      // the pipe at the mill rather than a soft callout.
      final schTp = TextPainter(
        text: TextSpan(
          text: note.text.toUpperCase(),
          style: TextStyle(
            color: cs.onSurface,
            fontSize: 10,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.8,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      final rect = Rect.fromCenter(
          center: note.pos, width: schTp.width + 14, height: schTp.height + 7);
      canvas.drawRect(rect, Paint()..color = cs.surface);
      canvas.drawRect(
        rect,
        Paint()
          ..color = cs.onSurface
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.0,
      );
      schTp.paint(canvas, note.pos - Offset(schTp.width / 2, schTp.height / 2));
      return;
    }

    if (isMaterial) {
      // Material designation chip (CS, SS316L, DSS, ALU…): monospace tabular
      // figures so the alloy code reads as a fixed-pitch spec stamp, secondary
      // container fill to flag it as a material attribute rather than geometry.
      final matTp = TextPainter(
        text: TextSpan(
          text: note.text.toUpperCase(),
          style: TextStyle(
            color: cs.onSecondaryContainer,
            fontSize: 11,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.6,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      final rect = Rect.fromCenter(
          center: note.pos, width: matTp.width + 16, height: matTp.height + 8);
      final rr = RRect.fromRectAndRadius(rect, const Radius.circular(14));
      canvas.drawRRect(rr, Paint()..color = cs.secondaryContainer);
      matTp.paint(canvas, note.pos - Offset(matTp.width / 2, matTp.height / 2));
      return;
    }

    if (titleBlockMatch != null) {
      // Title-block entry: prefix tag (TITLE / REV / DATE / …) sits in a
      // filled sub-chip on the left, value floats to the right. Mirrors a
      // real drafting title-block row where the field label is bordered
      // off from the value cell.
      final label = titleBlockMatch.group(1)!.toUpperCase();
      final value = titleBlockMatch.group(2)!.trim();
      final labelTp = TextPainter(
        text: TextSpan(
          text: label,
          style: TextStyle(
            color: cs.onSurface,
            fontSize: 10.5,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.5,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      final valueTp = TextPainter(
        text: TextSpan(
          text: value.isEmpty ? '—' : value,
          style: TextStyle(
            color: cs.onSurface,
            fontSize: 12.0,
            fontWeight: FontWeight.w700,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      const padX = 7.0;
      const padY = 5.0;
      final labelCellW = labelTp.width + padX * 2;
      final valueCellW = valueTp.width + padX * 2;
      final totalW = labelCellW + valueCellW;
      final totalH =
          (labelTp.height > valueTp.height ? labelTp.height : valueTp.height) +
              padY * 2;
      final rect = Rect.fromCenter(
          center: note.pos, width: totalW, height: totalH);
      final rr = RRect.fromRectAndRadius(rect, const Radius.circular(3));
      canvas.drawRRect(rr, Paint()..color = cs.surface);
      final labelRect = Rect.fromLTWH(
          rect.left, rect.top, labelCellW, rect.height);
      canvas.drawRect(labelRect, Paint()..color = cs.surfaceContainerHigh);
      canvas.drawRRect(
        rr,
        Paint()
          ..color = cs.outlineVariant
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.0,
      );
      // Divider between label and value cells.
      canvas.drawLine(
        Offset(labelRect.right, rect.top),
        Offset(labelRect.right, rect.bottom),
        Paint()
          ..color = cs.outlineVariant
          ..strokeWidth = 1.0,
      );
      labelTp.paint(
        canvas,
        Offset(
          labelRect.left + padX,
          labelRect.center.dy - labelTp.height / 2,
        ),
      );
      valueTp.paint(
        canvas,
        Offset(
          labelRect.right + padX,
          rect.center.dy - valueTp.height / 2,
        ),
      );
      return;
    }

    if (isEl) {
      // Anchor triangle pointing left → at note.pos, chip floats to the
      // right so the user's tap-point doubles as the elevation datum.
      final chipCenter = note.pos + Offset(tp.width / 2 + 14, 0);
      final rect = Rect.fromCenter(
          center: chipCenter, width: tp.width + 14, height: tp.height + 8);
      final rr = RRect.fromRectAndRadius(rect, const Radius.circular(3));
      canvas.drawRRect(rr, Paint()..color = cs.surface);
      canvas.drawRRect(
        rr,
        Paint()
          ..color = cs.tertiary.withValues(alpha: 0.85)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.3,
      );
      // Datum triangle ▶ pointing at note.pos.
      final tri = Path()
        ..moveTo(note.pos.dx, note.pos.dy)
        ..lineTo(note.pos.dx + 6, note.pos.dy - 4)
        ..lineTo(note.pos.dx + 6, note.pos.dy + 4)
        ..close();
      canvas.drawPath(
        tri,
        Paint()..color = cs.tertiary..style = PaintingStyle.fill,
      );
      tp.paint(canvas, chipCenter - Offset(tp.width / 2, tp.height / 2));
      return;
    }

    if (isDrain) {
      // Drain stubs on real isos pop off the bottom of a process line; the
      // leading down-arrow doubles as the flow-direction marker so the fitter
      // doesn't need to chase the routing back to read intent.
      final drainTp = TextPainter(
        text: TextSpan(
          children: [
            TextSpan(
              text: '↓ ',
              style: TextStyle(
                color: cs.onSurface,
                fontSize: 14,
                fontWeight: FontWeight.w800,
              ),
            ),
            TextSpan(
              text: note.text,
              style: TextStyle(
                color: cs.onSurface,
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      final rect = Rect.fromCenter(
          center: note.pos, width: drainTp.width + 14, height: drainTp.height + 7);
      final rr = RRect.fromRectAndRadius(rect, const Radius.circular(4));
      canvas.drawRRect(rr, Paint()..color = cs.surface);
      canvas.drawRRect(
        rr,
        Paint()
          ..color = cs.tertiary
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.3,
      );
      drainTp.paint(
          canvas, note.pos - Offset(drainTp.width / 2, drainTp.height / 2));
      return;
    }

    if (isVent) {
      // High-point vents sit on the top of a horizontal run; the up-arrow
      // glyph mirrors the drain chip so the fitter parses vent-vs-drain at a
      // glance without re-reading the prefix.
      final ventTp = TextPainter(
        text: TextSpan(
          children: [
            TextSpan(
              text: '↑ ',
              style: TextStyle(
                color: cs.onSurface,
                fontSize: 14,
                fontWeight: FontWeight.w800,
              ),
            ),
            TextSpan(
              text: note.text,
              style: TextStyle(
                color: cs.onSurface,
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      final rect = Rect.fromCenter(
          center: note.pos, width: ventTp.width + 14, height: ventTp.height + 7);
      final rr = RRect.fromRectAndRadius(rect, const Radius.circular(4));
      canvas.drawRRect(rr, Paint()..color = cs.surface);
      canvas.drawRRect(
        rr,
        Paint()
          ..color = const Color(0xFF4A9EFF)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.3,
      );
      ventTp.paint(
          canvas, note.pos - Offset(ventTp.width / 2, ventTp.height / 2));
      return;
    }

    if (isCont) {
      // Continuation tags ("CONT'D ON DWG-…" / "CONT'D FROM DWG-…") sit on the
      // page edge in real isos; render as an outlined chip whose left edge
      // carries a small ">" arrowhead pointing INTO the chip, signalling the
      // flow crosses to another drawing.
      final rect = Rect.fromCenter(
          center: note.pos, width: tp.width + 16, height: tp.height + 8);
      final rr = RRect.fromRectAndRadius(rect, const Radius.circular(5));
      canvas.drawRRect(rr, Paint()..color = cs.surface);
      canvas.drawRRect(
        rr,
        Paint()
          ..color = cs.primary
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.3,
      );
      final ax = rect.left;
      final ay = rect.center.dy;
      final arrow = Path()
        ..moveTo(ax - 5, ay - 4)
        ..lineTo(ax + 1, ay)
        ..lineTo(ax - 5, ay + 4);
      canvas.drawPath(
        arrow,
        Paint()
          ..color = cs.primary
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.6
          ..strokeJoin = StrokeJoin.round,
      );
      tp.paint(canvas, note.pos - Offset(tp.width / 2, tp.height / 2));
      return;
    }

    if (isPenetration) {
      // ASME convention: pipes passing through walls/floors/ceilings are
      // marked with a hatched rectangle around the callout, so the fitter
      // knows the structure must be drilled / sleeved at that station.
      final rect = Rect.fromCenter(
          center: note.pos, width: tp.width + 16, height: tp.height + 10);
      canvas.drawRect(rect, Paint()..color = cs.surface);
      final hatchPaint = Paint()
        ..color = cs.onSurfaceVariant.withValues(alpha: 0.65)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.9;
      canvas.save();
      canvas.clipRect(rect);
      const step = 6.0;
      // 45° hatch lines stepping across the rectangle's diagonal extent.
      final diag = rect.width + rect.height;
      for (double off = -rect.height; off < diag; off += step) {
        final x0 = rect.left + off;
        final y0 = rect.top;
        final x1 = x0 + rect.height;
        final y1 = rect.bottom;
        canvas.drawLine(Offset(x0, y0), Offset(x1, y1), hatchPaint);
      }
      canvas.restore();
      canvas.drawRect(
        rect,
        Paint()
          ..color = cs.onSurface.withValues(alpha: 0.75)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2,
      );
      // Solid backdrop behind the text so the hatch doesn't muddy the label.
      final textBg = Rect.fromCenter(
          center: note.pos, width: tp.width + 6, height: tp.height + 2);
      canvas.drawRect(textBg, Paint()..color = cs.surface);
      tp.paint(canvas, note.pos - Offset(tp.width / 2, tp.height / 2));
      return;
    }

    if (isTieIn) {
      // Standard ASME iso tie-in symbol: circle with an X through it placed
      // at the connection point to existing piping, with the callout chip
      // floating above so the marker itself stays unobstructed.
      final radius = s * 0.35;
      final accent = Paint()
        ..color = cs.error
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6;
      canvas.drawCircle(note.pos, radius, Paint()..color = cs.surface);
      canvas.drawCircle(note.pos, radius, accent);
      final d = radius * 0.7071; // cos 45° — X arms end on the circle
      canvas.drawLine(
        Offset(note.pos.dx - d, note.pos.dy - d),
        Offset(note.pos.dx + d, note.pos.dy + d),
        accent,
      );
      canvas.drawLine(
        Offset(note.pos.dx - d, note.pos.dy + d),
        Offset(note.pos.dx + d, note.pos.dy - d),
        accent,
      );
      final chipCenter =
          note.pos - Offset(0, radius + tp.height / 2 + 6);
      final chipRect = Rect.fromCenter(
          center: chipCenter, width: tp.width + 12, height: tp.height + 7);
      final chipRR = RRect.fromRectAndRadius(chipRect, const Radius.circular(4));
      canvas.drawRRect(chipRR, Paint()..color = cs.surface);
      canvas.drawRRect(
        chipRR,
        Paint()
          ..color = cs.error.withValues(alpha: 0.85)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2,
      );
      tp.paint(canvas, chipCenter - Offset(tp.width / 2, tp.height / 2));
      return;
    }

    if (isBatteryLimit) {
      // ASME plot-plan convention: a battery-limit / scope boundary is drawn
      // as a long vertical dashed line at the station where the contractor's
      // scope ends; the label chip floats to one side so the line itself
      // stays the dominant visual cue.
      final half = s * 1.5 / 2;
      final blPaint = Paint()
        ..color = cs.tertiary
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4;
      const dash = 4.0;
      const gap = 4.0;
      for (double y = -half; y < half; y += dash + gap) {
        final y0 = note.pos.dy + y;
        final y1 = note.pos.dy + math.min(y + dash, half);
        canvas.drawLine(Offset(note.pos.dx, y0), Offset(note.pos.dx, y1), blPaint);
      }
      final chipCenter = note.pos + Offset(tp.width / 2 + 12, 0);
      final chipRect = Rect.fromCenter(
          center: chipCenter, width: tp.width + 12, height: tp.height + 7);
      final chipRR = RRect.fromRectAndRadius(chipRect, const Radius.circular(4));
      canvas.drawRRect(chipRR, Paint()..color = cs.surface);
      canvas.drawRRect(
        chipRR,
        Paint()
          ..color = cs.tertiary.withValues(alpha: 0.85)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2,
      );
      tp.paint(canvas, chipCenter - Offset(tp.width / 2, tp.height / 2));
      return;
    }

    if (isMatchLine) {
      // ASME match-line convention: when the run continues on another sheet
      // along this break, draw a sawtooth across note.pos so the fitter sees
      // the seam itself, with the label parked below.
      final amp = s * 0.20;
      final len = s * 1.4;
      final half = len / 2;
      final mlPaint = Paint()
        ..color = cs.secondary
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4
        ..strokeJoin = StrokeJoin.round;
      const segs = 4;
      final step = len / segs;
      final path = Path()..moveTo(note.pos.dx - half, note.pos.dy);
      for (int i = 0; i < segs; i++) {
        final x = note.pos.dx - half + step * (i + 1);
        final y = note.pos.dy + (i.isEven ? -amp : amp);
        path.lineTo(x, y);
      }
      canvas.drawPath(path, mlPaint);

      final chipCenter = note.pos + Offset(0, amp + tp.height / 2 + 6);
      final chipRect = Rect.fromCenter(
          center: chipCenter, width: tp.width + 12, height: tp.height + 7);
      final chipRR = RRect.fromRectAndRadius(chipRect, const Radius.circular(4));
      canvas.drawRRect(chipRR, Paint()..color = cs.surface);
      canvas.drawRRect(
        chipRR,
        Paint()
          ..color = cs.secondary.withValues(alpha: 0.85)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2,
      );
      tp.paint(canvas, chipCenter - Offset(tp.width / 2, tp.height / 2));
      return;
    }

    if (isEquipment) {
      // ASME convention: a connection to vessels / pumps / tanks is shown as a
      // dashed boundary box at the equipment nozzle, signalling the iso scope
      // ends at the flange face of out-of-scope equipment.
      final rect = Rect.fromCenter(
          center: note.pos,
          width: math.max(80.0, tp.width + 14),
          height: math.max(40.0, tp.height + 14));
      canvas.drawRect(rect, Paint()..color = cs.surface);
      final eqPaint = Paint()
        ..color = cs.primary
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4;
      const dash = 5.0;
      const gap = 3.0;
      // Walk the perimeter clockwise from top-left, alternating ink and gap.
      void dashEdge(Offset a, Offset b) {
        final total = (b - a).distance;
        final dir = (b - a) / total;
        double pos = 0;
        bool on = true;
        while (pos < total) {
          final len = math.min(on ? dash : gap, total - pos);
          if (on) {
            canvas.drawLine(a + dir * pos, a + dir * (pos + len), eqPaint);
          }
          pos += len;
          on = !on;
        }
      }
      dashEdge(rect.topLeft, rect.topRight);
      dashEdge(rect.topRight, rect.bottomRight);
      dashEdge(rect.bottomRight, rect.bottomLeft);
      dashEdge(rect.bottomLeft, rect.topLeft);
      tp.paint(canvas, note.pos - Offset(tp.width / 2, tp.height / 2));
      return;
    }

    if (isHeatNumber) {
      // Mill heat number stamp (HT-####): tabular figures so the trace ID
      // reads as fixed-pitch, dashed thin border drawn from short segments to
      // signal "traceability record" without competing with active callouts.
      final htTp = TextPainter(
        text: TextSpan(
          text: note.text.toUpperCase(),
          style: TextStyle(
            color: cs.onSurface,
            fontSize: 11.5,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.4,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      final rect = Rect.fromCenter(
          center: note.pos, width: htTp.width + 14, height: htTp.height + 7);
      final rr = RRect.fromRectAndRadius(rect, const Radius.circular(3));
      canvas.drawRRect(rr, Paint()..color = cs.outlineVariant);
      final border = Paint()
        ..color = cs.onSurface.withValues(alpha: 0.55)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.9;
      const dash = 3.5;
      const gap = 2.5;
      void dashEdge(Offset a, Offset b) {
        final total = (b - a).distance;
        final dir = (b - a) / total;
        double pos = 0;
        bool on = true;
        while (pos < total) {
          final len = math.min(on ? dash : gap, total - pos);
          if (on) {
            canvas.drawLine(a + dir * pos, a + dir * (pos + len), border);
          }
          pos += len;
          on = !on;
        }
      }
      dashEdge(rect.topLeft, rect.topRight);
      dashEdge(rect.topRight, rect.bottomRight);
      dashEdge(rect.bottomRight, rect.bottomLeft);
      dashEdge(rect.bottomLeft, rect.topLeft);
      htTp.paint(canvas, note.pos - Offset(htTp.width / 2, htTp.height / 2));
      return;
    }

    if (isHeatTrace) {
      // Heat-tracing callouts get a warm-orange chip with a dashed-line glyph
      // ("- - -") to the left of the text — the dash marks evoke the trace
      // cable itself, so the insulation contractor spots the tagged segment
      // at a glance.
      const trace = Color(0xFFE8954B);
      const dashGlyph = '- - - ';
      final glyphTp = TextPainter(
        text: const TextSpan(
          text: dashGlyph,
          style: TextStyle(
            color: trace,
            fontSize: 12.5,
            fontWeight: FontWeight.w900,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      final width = glyphTp.width + tp.width + 14;
      final height = math.max(glyphTp.height, tp.height) + 8;
      final rect = Rect.fromCenter(
          center: note.pos, width: width, height: height);
      final rr = RRect.fromRectAndRadius(rect, const Radius.circular(4));
      canvas.drawRRect(rr, Paint()..color = cs.surface);
      canvas.drawRRect(
        rr,
        Paint()
          ..color = trace
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.3,
      );
      final innerLeft = rect.left + 7;
      glyphTp.paint(
        canvas,
        Offset(innerLeft, rect.center.dy - glyphTp.height / 2),
      );
      tp.paint(
        canvas,
        Offset(innerLeft + glyphTp.width, rect.center.dy - tp.height / 2),
      );
      return;
    }

    if (isInsulation) {
      // Insulation thickness callout (INS-50, INS-100…): chip with a leading
      // "parallel-lines" glyph — two short horizontal bars stacked like a
      // jacket cross-section — and a dashed border so insulator scope reads
      // distinct from heat-trace and medium chips.
      const iconW = 11.0;
      const iconGap = 6.0;
      final width = iconW + iconGap + tp.width + 14;
      final height = tp.height + 8;
      final rect = Rect.fromCenter(
          center: note.pos, width: width, height: height);
      canvas.drawRect(rect, Paint()..color = cs.surface);
      final accent = Paint()
        ..color = cs.secondary
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.3;
      const dash = 4.0;
      const gap = 3.0;
      void dashEdge(Offset a, Offset b) {
        final total = (b - a).distance;
        final dir = (b - a) / total;
        double pos = 0;
        bool on = true;
        while (pos < total) {
          final len = math.min(on ? dash : gap, total - pos);
          if (on) {
            canvas.drawLine(a + dir * pos, a + dir * (pos + len), accent);
          }
          pos += len;
          on = !on;
        }
      }
      dashEdge(rect.topLeft, rect.topRight);
      dashEdge(rect.topRight, rect.bottomRight);
      dashEdge(rect.bottomRight, rect.bottomLeft);
      dashEdge(rect.bottomLeft, rect.topLeft);
      // Two stacked horizontal bars — the jacket cross-section glyph.
      final iconLeft = rect.left + 7;
      final iconRight = iconLeft + iconW;
      final barPaint = Paint()
        ..color = cs.secondary
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6
        ..strokeCap = StrokeCap.round;
      canvas.drawLine(
        Offset(iconLeft, rect.center.dy - 3),
        Offset(iconRight, rect.center.dy - 3),
        barPaint,
      );
      canvas.drawLine(
        Offset(iconLeft, rect.center.dy + 3),
        Offset(iconRight, rect.center.dy + 3),
        barPaint,
      );
      tp.paint(
        canvas,
        Offset(iconRight + iconGap, rect.center.dy - tp.height / 2),
      );
      return;
    }

    if (isPressureRating) {
      // Pressure-rating chips (PR=10 bar, PR=ANSI150, …) get a shield glyph so
      // the fitter parses "rated component" at a glance — shields are the
      // industry-standard mark for ASME / EN pressure classes on iso sheets.
      const iconW = 11.0;
      const iconH = 13.0;
      const iconGap = 6.0;
      final width = iconW + iconGap + tp.width + 14;
      final height = math.max(iconH, tp.height) + 8;
      final rect = Rect.fromCenter(
          center: note.pos, width: width, height: height);
      final rr = RRect.fromRectAndRadius(rect, const Radius.circular(4));
      canvas.drawRRect(rr, Paint()..color = cs.surfaceContainerHighest);
      canvas.drawRRect(
        rr,
        Paint()
          ..color = cs.primary
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.3,
      );
      // Pentagon shield: flat top, sides taper down to a centred point.
      final iconLeft = rect.left + 7;
      final iconCx = iconLeft + iconW / 2;
      final iconTop = rect.center.dy - iconH / 2;
      final shoulder = iconTop + iconH * 0.55;
      final shield = Path()
        ..moveTo(iconLeft, iconTop)
        ..lineTo(iconLeft + iconW, iconTop)
        ..lineTo(iconLeft + iconW, shoulder)
        ..lineTo(iconCx, iconTop + iconH)
        ..lineTo(iconLeft, shoulder)
        ..close();
      canvas.drawPath(
        shield,
        Paint()..color = cs.primary.withValues(alpha: 0.18),
      );
      canvas.drawPath(
        shield,
        Paint()
          ..color = cs.primary
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.3
          ..strokeJoin = StrokeJoin.round,
      );
      tp.paint(
        canvas,
        Offset(iconLeft + iconW + iconGap, rect.center.dy - tp.height / 2),
      );
      return;
    }

    if (isTestPressure) {
      // Hydrostatic test-pressure tags (TP=15 bar, TP 30 bar…): italicised so
      // the QA team distinguishes test conditions from operating pressure (PR),
      // with a leading test-bench glyph — gauge triangle flanked by two stub
      // pipe sections — drawn fresh because the chip uses italic + tertiary
      // accents that the shared `tp` painter does not carry.
      final italicTp = TextPainter(
        text: TextSpan(
          text: note.text,
          style: TextStyle(
            color: cs.onSurface,
            fontSize: 12.5,
            fontWeight: FontWeight.w700,
            fontStyle: FontStyle.italic,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      const iconW = 14.0;
      const iconH = 10.0;
      const iconGap = 6.0;
      final width = iconW + iconGap + italicTp.width + 14;
      final height = math.max(iconH, italicTp.height) + 8;
      final rect = Rect.fromCenter(
          center: note.pos, width: width, height: height);
      final rr = RRect.fromRectAndRadius(rect, const Radius.circular(4));
      canvas.drawRRect(rr, Paint()..color = cs.surface);
      canvas.drawRRect(
        rr,
        Paint()
          ..color = cs.tertiary
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.3,
      );
      final iconLeft = rect.left + 7;
      final iconCy = rect.center.dy;
      final accent = Paint()
        ..color = cs.tertiary
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round;
      const stubLen = 3.5;
      const triHalfW = 3.0;
      final triTop = iconCy - iconH / 2;
      final triBot = iconCy + iconH / 2;
      final triCx = iconLeft + iconW / 2;
      // Left pipe stub.
      canvas.drawLine(
        Offset(iconLeft, iconCy),
        Offset(iconLeft + stubLen, iconCy),
        accent,
      );
      // Right pipe stub.
      canvas.drawLine(
        Offset(iconLeft + iconW - stubLen, iconCy),
        Offset(iconLeft + iconW, iconCy),
        accent,
      );
      // Central gauge triangle (apex up).
      final tri = Path()
        ..moveTo(triCx, triTop)
        ..lineTo(triCx + triHalfW, triBot)
        ..lineTo(triCx - triHalfW, triBot)
        ..close();
      canvas.drawPath(
        tri,
        Paint()..color = cs.tertiary.withValues(alpha: 0.2),
      );
      canvas.drawPath(tri, accent);
      italicTp.paint(
        canvas,
        Offset(iconLeft + iconW + iconGap, iconCy - italicTp.height / 2),
      );
      return;
    }

    if (mediumMatch != null) {
      // Service-medium callouts mirror site colour-banding tape: a small chip
      // tinted by fluid so the fitter / insulator spots STEAM vs WATER vs GAS
      // without reading the label. CW / HW / PARA / WODA / POWIETRZE alias to
      // their parent medium colours.
      final key = mediumMatch.group(1)!.toUpperCase();
      final medium = switch (key) {
        'STEAM' || 'PARA' => const Color(0xFFE85B5B),
        'WATER' || 'WODA' || 'CW' || 'HW' => const Color(0xFF4A9EFF),
        'GAS' => const Color(0xFFE8C14B),
        'AIR' || 'POWIETRZE' => const Color(0xFF6CE0E0),
        'OIL' => const Color(0xFF8B5A2B),
        'N2' => const Color(0xFFA67BFF),
        _ => cs.secondary,
      };
      final rect = Rect.fromCenter(
          center: note.pos, width: tp.width + 14, height: tp.height + 8);
      final rr = RRect.fromRectAndRadius(rect, const Radius.circular(3));
      canvas.drawRRect(rr, Paint()..color = medium.withValues(alpha: 0.55));
      canvas.drawRRect(
        rr,
        Paint()
          ..color = medium
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2,
      );
      tp.paint(canvas, note.pos - Offset(tp.width / 2, tp.height / 2));
      return;
    }

    if (isActuator) {
      // Square housing with a short stem + crank stub on top — the schematic
      // shape used on ASME piping isos to mark valve actuator type. The text
      // (ACT=MOV / ACT M / ACT PV / ACT EHV) sits in a tertiary-accent chip
      // so commissioning teams pick it out from neighbouring valve labels.
      const iconW = 12.0;
      const iconH = 10.0;
      const iconGap = 6.0;
      const stemH = 4.0;
      final width = iconW + iconGap + tp.width + 14;
      final height = math.max(iconH + stemH + 2, tp.height) + 8;
      final rect = Rect.fromCenter(
          center: note.pos, width: width, height: height);
      final rr = RRect.fromRectAndRadius(rect, const Radius.circular(4));
      canvas.drawRRect(rr, Paint()..color = cs.surface);
      canvas.drawRRect(
        rr,
        Paint()
          ..color = cs.tertiary
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.3,
      );
      final iconLeft = rect.left + 7;
      final iconCx = iconLeft + iconW / 2;
      // Housing centred vertically; stem rises above it so the icon reads as
      // "driver on top of the valve".
      final housingTop = rect.center.dy - iconH / 2 + stemH / 2;
      final housingRect = Rect.fromLTWH(iconLeft, housingTop, iconW, iconH);
      canvas.drawRect(
        housingRect,
        Paint()..color = cs.tertiary.withValues(alpha: 0.18),
      );
      canvas.drawRect(
        housingRect,
        Paint()
          ..color = cs.tertiary
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.3,
      );
      // Stem + crank stub on top — the classic actuator marker.
      final stem = Paint()
        ..color = cs.tertiary
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4
        ..strokeCap = StrokeCap.round;
      canvas.drawLine(
        Offset(iconCx, housingTop),
        Offset(iconCx, housingTop - stemH),
        stem,
      );
      canvas.drawLine(
        Offset(iconCx - iconW * 0.25, housingTop - stemH),
        Offset(iconCx + iconW * 0.25, housingTop - stemH),
        stem,
      );
      tp.paint(
        canvas,
        Offset(iconLeft + iconW + iconGap, rect.center.dy - tp.height / 2),
      );
      return;
    }

    final rect = Rect.fromCenter(
      center: note.pos, width: tp.width + 12, height: tp.height + 7);
    final rr = RRect.fromRectAndRadius(rect, const Radius.circular(5));
    canvas.drawRRect(rr, Paint()..color = cs.secondaryContainer);
    canvas.drawRRect(
      rr,
      Paint()
        ..color = cs.secondary.withValues(alpha: 0.5)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0,
    );
    tp.paint(canvas, note.pos - Offset(tp.width / 2, tp.height / 2));
  }

  void _drawPreview(Canvas canvas) {
    canvas.drawCircle(dragA!, 7.0, Paint()..color = cs.primary);
    _drawSeg(canvas, dragA!, dragB!, tool, alpha: 0.45);
    canvas.drawCircle(dragB!, 5.5,
      Paint()..color = cs.primary.withValues(alpha: 0.6));

    // Ghost-line indicator: when axis-lock is on, sketch a thin dashed
    // extension past dragB along the locked iso axis so the user sees which
    // heading the snap will commit to before lifting the finger.
    if (!axisLock) return;
    final delta = dragB! - dragA!;
    final len = delta.distance;
    if (len < s * 0.5) return;
    final unit = Offset(delta.dx / len, delta.dy / len);
    final tail = dragB! + unit * (s * 2.0);
    final ghost = Paint()
      ..color = cs.primary.withValues(alpha: 0.28)
      ..strokeWidth = 1.0
      ..style = PaintingStyle.stroke;
    const dash = 4.0;
    const gap = 4.0;
    final segLen = (tail - dragB!).distance;
    var t = 0.0;
    while (t < segLen) {
      final a = dragB! + unit * t;
      final b = dragB! + unit * math.min(t + dash, segLen);
      canvas.drawLine(a, b, ghost);
      t += dash + gap;
    }
  }

  void _drawComp(Canvas canvas, _Comp c) {
    canvas.save();
    canvas.translate(c.pos.dx, c.pos.dy);
    // Elbow with two specific legs renders along the actual iso headings of
    // the connected pipes (no canvas rotation) — for every other symbol the
    // legacy 60°-step rotation still applies.
    if (c.t == _Tool.elbow90 && c.dir2 != null) {
      _symElbowIso(canvas, s * 0.46, c.dir, c.dir2!);
      canvas.restore();
      return;
    }
    canvas.rotate(-c.dir * math.pi / 3.0);
    final r = s * 0.46;
    switch (c.t) {
      case _Tool.elbow90:         _symElbow90(canvas, r);   break;
      case _Tool.elbow45:         _symElbow45(canvas, r);   break;
      case _Tool.tee:             _symTee(canvas, r);       break;
      case _Tool.olet:            _symOlet(canvas, r);      break;
      case _Tool.reducer:
        // ECC↑ = flat top (steam mains), ECC↓ = flat bottom (pump suction).
        // Otherwise concentric — kept as the default symmetric trapezoid.
        final ecc = c.label.contains('ECC↑')
            ? 1
            : c.label.contains('ECC↓')
                ? -1
                : 0;
        _symReducer(canvas, r, ecc);
        break;
      case _Tool.flange:          _symFlange(canvas, r);    break;
      case _Tool.blindFlange:     _symBlind(canvas, r);     break;
      case _Tool.cap:             _symCap(canvas, r);       break;
      case _Tool.gateValve:       _symGate(canvas, r);      break;
      case _Tool.ballValve:       _symBall(canvas, r);      break;
      case _Tool.checkValve:      _symCheck(canvas, r);     break;
      case _Tool.globeValve:      _symGlobe(canvas, r);     break;
      case _Tool.butterflyValve:  _symButterfly(canvas, r); break;
      case _Tool.weld:            _symWeld(canvas, r, false); break;
      case _Tool.fieldWeld:       _symWeld(canvas, r, true);  break;
      case _Tool.support:         _symSupport(canvas, r);   break;
      case _Tool.instrument:      _symInstrument(canvas, r);break;
      case _Tool.spoolBreak:      _symSpoolBreak(canvas, r);break;
      case _Tool.northArrow:      _symNorth(canvas, r);     break;
      case _Tool.flowArrow:       _symFlow(canvas, r);      break;
      default: break;
    }
    canvas.restore();
  }

  /// Red dashed ring around any component whose cut-list spec is incomplete:
  /// an elbow without DN, or a physical fitting without a recorded length.
  /// Surfaces missing data visually so the fitter notices it before BOM export.
  void _drawMissingDataRing(Canvas canvas, _Comp c) {
    bool missing = false;
    if (c.isElbow && c.dn == null) missing = true;
    try {
      if (ComponentClassification.isPhysical(c.t.name) &&
          c.physicalLengthMm == null) {
        missing = true;
      }
    } catch (_) {}
    if (!missing) return;
    final radius = s * 0.52;
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..color = cs.error;
    const dashOn = 4.0;
    const dashOff = 3.0;
    final circumference = 2 * math.pi * radius;
    final step = dashOn + dashOff;
    final n = (circumference / step).floor();
    final sweepOn = (dashOn / radius);
    final sweepStep = (step / radius);
    final rect = Rect.fromCircle(center: c.pos, radius: radius);
    for (int i = 0; i < n; i++) {
      canvas.drawArc(rect, i * sweepStep, sweepOn, false, paint);
    }
  }

  /// Two-line tag drawn on the upper-right of an elbow component:
  ///   line 1 — DN + NPS                    (e.g. "DN50  2"")
  ///   line 2 — subtype + CTE in mm         (e.g. "90° LR · 76 mm")
  /// CTE shown in accent so the fitter spots the deducted value at a glance.
  void _drawElbowSpecLabel(Canvas canvas, _Comp c) {
    final dn = c.dn;
    if (dn == null) return;
    final row = closestByDn(dn);
    final subtype = c.elbowSubtype ??
        (c.t == _Tool.elbow45 ? _ElbowSubtype.lr45 : _ElbowSubtype.lr90);
    final cte = c.cteMm ?? _stdCte(dn, subtype);

    final line1 = TextSpan(
      text: 'DN$dn  ${row.nps}"',
      style: TextStyle(
        color: cs.onSurface,
        fontSize: 9.5,
        fontWeight: FontWeight.w800,
      ),
    );
    final line2 = TextSpan(
      children: [
        TextSpan(
          text: '${subtype.label}  ',
          style: TextStyle(
            color: cs.onSurfaceVariant,
            fontSize: 9,
          ),
        ),
        TextSpan(
          text: '$cte mm',
          style: TextStyle(
            color: cs.tertiary,
            fontSize: 9.5,
            fontWeight: FontWeight.w900,
          ),
        ),
      ],
    );
    final isLR = subtype == _ElbowSubtype.lr90 || subtype == _ElbowSubtype.lr45;
    final dMult = isLR ? 1.5 : 1.0;
    final radiusMm = (dn * dMult).round();
    final line3 = TextSpan(
      text: isLR
          ? 'R=1.5D · R=$radiusMm mm'
          : 'R=1.0D · R=$radiusMm mm',
      style: TextStyle(
        color: cs.onSurfaceVariant,
        fontSize: 8.5,
      ),
    );
    final tp1 = TextPainter(text: line1, textDirection: TextDirection.ltr)
      ..layout();
    final tp2 = TextPainter(text: line2, textDirection: TextDirection.ltr)
      ..layout();
    final tp3 = TextPainter(text: line3, textDirection: TextDirection.ltr)
      ..layout();
    final w = math.max(math.max(tp1.width, tp2.width), tp3.width) + 8;
    final h = tp1.height + tp2.height + tp3.height + 5;
    final centre = c.pos + Offset(s * 0.55, -s * 0.65);
    final rect = Rect.fromCenter(center: centre, width: w, height: h);
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(4)),
      Paint()..color = cs.surface.withValues(alpha: 0.95),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(4)),
      Paint()
        ..color = cs.tertiary.withValues(alpha: 0.45)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.8,
    );
    tp1.paint(canvas, Offset(rect.left + 4, rect.top + 1));
    tp2.paint(canvas, Offset(rect.left + 4, rect.top + tp1.height + 2));
    tp3.paint(
        canvas, Offset(rect.left + 4, rect.top + tp1.height + tp2.height + 3));
  }

  void _drawCompLabel(Canvas canvas, _Comp c) {
    // Weld labels may carry an NDT inspection suffix (RT/UT/PT/MT/VT) that
    // a fitter appends to flag which method qualified the weld. Render the
    // suffix italic + accent so it reads as metadata, not part of the W-N tag.
    if (c.t.isWeld) {
      final ndt = RegExp(r"\b(RT|UT|PT|MT|VT)\b").firstMatch(c.label);
      if (ndt != null) {
        final prefix = c.label.substring(0, ndt.start);
        final suffix = c.label.substring(ndt.start, ndt.end);
        final tail = c.label.substring(ndt.end);
        final tpNdt = TextPainter(
          text: TextSpan(
            style: TextStyle(
              color: cs.error,
              fontSize: 10.5,
              fontWeight: FontWeight.w800,
            ),
            children: [
              TextSpan(text: prefix),
              TextSpan(
                text: suffix,
                style: const TextStyle(fontStyle: FontStyle.italic),
              ),
              if (tail.isNotEmpty) TextSpan(text: tail),
            ],
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        final posNdt = c.pos + Offset(s * 0.32, -s * 0.36);
        final rectNdt = Rect.fromCenter(
            center: posNdt, width: tpNdt.width + 6, height: tpNdt.height + 3);
        canvas.drawRRect(
          RRect.fromRectAndRadius(rectNdt, const Radius.circular(3)),
          Paint()..color = cs.surface,
        );
        tpNdt.paint(
            canvas, posNdt - Offset(tpNdt.width / 2, tpNdt.height / 2));
        return;
      }
    }
    final tp = TextPainter(
      text: TextSpan(
        text: c.label,
        style: TextStyle(
          color: c.t.isWeld ? cs.error : cs.onSurface,
          fontSize: 10.5,
          fontWeight: FontWeight.w800,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    final pos = c.t == _Tool.instrument
        ? c.pos
        : c.pos + Offset(s * 0.32, -s * 0.36);
    if (c.t != _Tool.instrument) {
      final rect = Rect.fromCenter(
        center: pos, width: tp.width + 6, height: tp.height + 3);
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(3)),
        Paint()..color = cs.surface,
      );
    }
    tp.paint(canvas, pos - Offset(tp.width / 2, tp.height / 2));
  }

  Paint get _pipePaint => Paint()
    ..color = _inkColor
    ..strokeWidth = 5.0
    ..strokeCap = StrokeCap.round
    ..style = PaintingStyle.stroke;

  Paint get _symPaint => Paint()
    ..color = paperMode ? const Color(0xFF333333) : cs.secondary
    ..strokeWidth = 2.8
    ..strokeCap = StrokeCap.round
    ..style = PaintingStyle.stroke;

  Paint get _symFill => Paint()
    ..color = paperMode ? const Color(0xFF333333) : cs.secondary
    ..style = PaintingStyle.fill;

  /// Elbow rendered with two stubs along the actual iso headings of the
  /// connected pipes. [legA] / [legB] are indices into `_isoHeadings`
  /// (0..5 ↔ +I, −III, −II, −I, +III, +II). The arc bridges the angle
  /// between the two stubs at a small radius; the centre dot marks the
  /// elbow's CTE (centre-to-end) reference for the take-out.
  void _symElbowIso(Canvas canvas, double r, int legA, int legB) {
    final hA = _isoHeadings[legA];
    final hB = _isoHeadings[legB];
    final p = _pipePaint;
    canvas.drawLine(Offset.zero, Offset(hA.dx * r, hA.dy * r), p);
    canvas.drawLine(Offset.zero, Offset(hB.dx * r, hB.dy * r), p);

    // Arc: short way between the two leg directions. Each leg vector points
    // OUTWARD from the junction; the arc must run along the inner side, so
    // we sweep from one leg's angle to the other and pick the smaller sweep.
    final aStart = math.atan2(hA.dy, hA.dx);
    final aEnd = math.atan2(hB.dy, hB.dx);
    double sweep = aEnd - aStart;
    if (sweep > math.pi) sweep -= 2 * math.pi;
    if (sweep < -math.pi) sweep += 2 * math.pi;
    final arcR = r * 0.42;
    canvas.drawArc(
      Rect.fromCircle(center: Offset.zero, radius: arcR),
      aStart,
      sweep,
      false,
      Paint()
        ..color = cs.secondary
        ..strokeWidth = 2.6
        ..style = PaintingStyle.stroke,
    );
    canvas.drawCircle(Offset.zero, 4.5, Paint()..color = cs.secondary);
  }

  void _symElbow90(Canvas canvas, double r) {
    final p = _pipePaint;
    canvas.drawLine(Offset(-r, 0), Offset.zero, p);
    canvas.drawLine(Offset.zero, Offset(0, r), p);
    final arcR = r * 0.45;
    canvas.drawArc(
      Rect.fromCircle(center: Offset(-arcR, arcR), radius: arcR),
      -math.pi / 2, math.pi / 2, false,
      Paint()..color = cs.secondary..strokeWidth = 2.5..style = PaintingStyle.stroke);
    canvas.drawCircle(Offset.zero, 4.5, Paint()..color = cs.secondary);
  }

  void _symElbow45(Canvas canvas, double r) {
    final p = _pipePaint;
    canvas.drawLine(Offset(-r, 0), Offset.zero, p);
    canvas.drawLine(Offset.zero, Offset(r * 0.5, r * 0.866), p);
    canvas.drawCircle(Offset.zero, 4.5, Paint()..color = cs.secondary);
  }

  void _symTee(Canvas canvas, double r) {
    final p = _pipePaint;
    canvas.drawLine(Offset(-r, 0), Offset(r, 0), p);
    canvas.drawLine(Offset.zero, Offset(0, -r),
      Paint()..color = cs.secondary..strokeWidth = 5.0
        ..strokeCap = StrokeCap.round..style = PaintingStyle.stroke);
    canvas.drawCircle(Offset.zero, 5.0, Paint()..color = cs.secondary);
  }

  /// [ecc] — 0 = concentric (symmetric trapezoid), +1 = eccentric flat-top
  /// (top edge horizontal, taper on the bottom — used on steam mains to drain
  /// condensate), -1 = eccentric flat-bottom (bottom edge horizontal — used on
  /// horizontal pump suction to prevent vapour pockets).
  void _symReducer(Canvas canvas, double r, [int ecc = 0]) {
    final p = _pipePaint;
    canvas.drawLine(Offset(-r, 0), Offset(-r * 0.28, 0), p);
    canvas.drawLine(Offset(r * 0.12, 0), Offset(r, 0),
      Paint()..color = cs.primary..strokeWidth = 3.0
        ..strokeCap = StrokeCap.round..style = PaintingStyle.stroke);
    // Concentric: top + bottom both taper symmetrically. Flat-top: top edge
    // stays horizontal at the large radius; small bore is pinned to the top.
    // Flat-bottom mirrors that. Small-bore diameter (smB - smT) is preserved
    // so the small end still reads as the right relative size.
    const lgY = 0.38; // large radius (×r), top is -lgY
    const smY = 0.18; // small radius (×r), top is -smY
    final xL = -r * 0.28; // large face x
    final xS =  r * 0.12; // small face x
    Path path;
    if (ecc > 0) {
      // Flat top: top runs straight from large face to small face.
      path = Path()
        ..moveTo(xL, -r * lgY)
        ..lineTo(xS, -r * lgY)
        ..lineTo(xS, -r * lgY + r * 2 * smY)
        ..lineTo(xL,  r * lgY)
        ..close();
    } else if (ecc < 0) {
      // Flat bottom: bottom runs straight.
      path = Path()
        ..moveTo(xL, -r * lgY)
        ..lineTo(xS,  r * lgY - r * 2 * smY)
        ..lineTo(xS,  r * lgY)
        ..lineTo(xL,  r * lgY)
        ..close();
    } else {
      path = Path()
        ..moveTo(xL, -r * lgY)
        ..lineTo(xS, -r * smY)
        ..lineTo(xS,  r * smY)
        ..lineTo(xL,  r * lgY)
        ..close();
    }
    canvas.drawPath(path, _symPaint..strokeWidth = 2.5);
    // Reduction-direction arrow tag (ASME B16.9 convention) — a short axial
    // arrow large-face → small-face with an "R" tail tag so the fitter reads
    // reduction sense at a glance without parsing the DNx→DNy chip. For
    // ecc<0 (flat bottom) we mirror below the body to clear the flat edge.
    final tagY = ecc < 0 ? r * 0.62 : -r * 0.62;
    final tagPaint = Paint()
      ..color = cs.secondary
      ..strokeWidth = 1.4
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    final shaftL = xL - r * 0.02;
    final shaftR = xS + r * 0.02;
    canvas.drawLine(Offset(shaftL, tagY), Offset(shaftR, tagY), tagPaint);
    final headPath = Path()
      ..moveTo(shaftR, tagY)
      ..lineTo(shaftR - r * 0.10, tagY - r * 0.06)
      ..lineTo(shaftR - r * 0.10, tagY + r * 0.06)
      ..close();
    canvas.drawPath(headPath, Paint()..color = cs.secondary);
    final rTag = TextPainter(
      text: TextSpan(
        text: 'R',
        style: TextStyle(
          color: cs.secondary,
          fontSize: 8.0,
          fontWeight: FontWeight.w800,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    rTag.paint(canvas,
        Offset(shaftL - rTag.width - 2, tagY - rTag.height / 2));
  }

  void _symFlange(Canvas canvas, double r) {
    final p = _pipePaint;
    canvas.drawLine(Offset(-r, 0), Offset(-r * 0.22, 0), p);
    canvas.drawLine(Offset(r * 0.22, 0), Offset(r, 0), p);
    final sp = _symPaint..strokeWidth = 3.2;
    canvas.drawLine(Offset(-r * 0.22, -r * 0.48), Offset(-r * 0.22, r * 0.48), sp);
    canvas.drawLine(Offset( r * 0.22, -r * 0.48), Offset( r * 0.22, r * 0.48), sp);
  }

  void _symBlind(Canvas canvas, double r) {
    final p = _pipePaint;
    canvas.drawLine(Offset(-r, 0), Offset(-r * 0.16, 0), p);
    final sp = _symPaint..strokeWidth = 3.4;
    canvas.drawLine(Offset(-r * 0.16, -r * 0.5), Offset(-r * 0.16, r * 0.5), sp);
    final cap = Path()
      ..moveTo(-r * 0.16, -r * 0.5)
      ..lineTo(r * 0.12, -r * 0.32)
      ..lineTo(r * 0.12, r * 0.32)
      ..lineTo(-r * 0.16, r * 0.5)
      ..close();
    canvas.drawPath(cap, Paint()
      ..color = cs.secondary.withValues(alpha: 0.55)
      ..style = PaintingStyle.fill);
  }

  void _symCap(Canvas canvas, double r) {
    final p = _pipePaint;
    canvas.drawLine(Offset(-r, 0), Offset(-r * 0.12, 0), p);
    final dome = Path()
      ..moveTo(-r * 0.12, -r * 0.42)
      ..quadraticBezierTo(r * 0.5, 0, -r * 0.12, r * 0.42)
      ..close();
    canvas.drawPath(dome, Paint()
      ..color = cs.secondary.withValues(alpha: 0.55)
      ..style = PaintingStyle.fill);
    canvas.drawPath(dome, _symPaint..strokeWidth = 2.4);
  }

  void _symGate(Canvas canvas, double r) {
    final p = _pipePaint;
    canvas.drawLine(Offset(-r, 0), Offset(-r * 0.3, 0), p);
    canvas.drawLine(Offset(r * 0.3, 0), Offset(r, 0), p);
    final t1 = Path()
      ..moveTo(-r * 0.3, -r * 0.38)..lineTo(0, 0)..lineTo(-r * 0.3, r * 0.38)..close();
    final t2 = Path()
      ..moveTo(r * 0.3, -r * 0.38)..lineTo(0, 0)..lineTo(r * 0.3, r * 0.38)..close();
    canvas.drawPath(t1, _symFill);
    canvas.drawPath(t2, _symFill);
    canvas.drawLine(Offset.zero, Offset(0, -r * 0.5), _symPaint..strokeWidth = 2.5);
  }

  void _symBall(Canvas canvas, double r) {
    final p = _pipePaint;
    canvas.drawLine(Offset(-r, 0), Offset(-r * 0.3, 0), p);
    canvas.drawLine(Offset(r * 0.3, 0), Offset(r, 0), p);
    final t1 = Path()
      ..moveTo(-r * 0.3, -r * 0.38)..lineTo(0, 0)..lineTo(-r * 0.3, r * 0.38)..close();
    final t2 = Path()
      ..moveTo(r * 0.3, -r * 0.38)..lineTo(0, 0)..lineTo(r * 0.3, r * 0.38)..close();
    canvas.drawPath(t1, _symFill);
    canvas.drawPath(t2, _symFill);
    canvas.drawCircle(Offset.zero, r * 0.2, Paint()..color = cs.surface);
    canvas.drawCircle(Offset.zero, r * 0.2, _symPaint..strokeWidth = 2.4);
    canvas.drawLine(Offset.zero, Offset(0, -r * 0.55), _symPaint..strokeWidth = 2.5);
  }

  void _symCheck(Canvas canvas, double r) {
    final p = _pipePaint;
    canvas.drawLine(Offset(-r, 0), Offset(-r * 0.34, 0), p);
    canvas.drawLine(Offset(r * 0.34, 0), Offset(r, 0), p);
    final tri = Path()
      ..moveTo(-r * 0.34, -r * 0.38)
      ..lineTo(r * 0.34, 0)
      ..lineTo(-r * 0.34, r * 0.38)
      ..close();
    canvas.drawPath(tri, _symFill);
    canvas.drawLine(Offset(r * 0.34, -r * 0.4), Offset(r * 0.34, r * 0.4),
      _symPaint..strokeWidth = 2.6);
  }

  void _symWeld(Canvas canvas, double r, bool field) {
    canvas.drawLine(Offset(-r * 0.55, 0), Offset(-r * 0.2, 0), _pipePaint);
    canvas.drawLine(Offset(r * 0.2, 0), Offset(r * 0.55, 0), _pipePaint);
    if (field) {
      canvas.drawCircle(Offset.zero, r * 0.24,
        Paint()..color = cs.error..strokeWidth = 2.8..style = PaintingStyle.stroke);
      canvas.drawCircle(Offset.zero, r * 0.07,
        Paint()..color = cs.error..style = PaintingStyle.fill);
    } else {
      canvas.drawCircle(Offset.zero, r * 0.24,
        Paint()..color = cs.secondary..strokeWidth = 2.8..style = PaintingStyle.stroke);
      canvas.drawCircle(Offset.zero, r * 0.07, _symFill);
    }
  }

  void _symSupport(Canvas canvas, double r) {
    final p = _pipePaint;
    canvas.drawLine(Offset(-r * 0.6, 0), Offset(r * 0.6, 0), p);
    final tri = Path()
      ..moveTo(0, 0)
      ..lineTo(-r * 0.32, r * 0.55)
      ..lineTo(r * 0.32, r * 0.55)
      ..close();
    canvas.drawPath(tri, _symPaint..strokeWidth = 2.4);
    canvas.drawLine(Offset(-r * 0.5, r * 0.55), Offset(r * 0.5, r * 0.55),
      _symPaint..strokeWidth = 2.4);
  }

  void _symInstrument(Canvas canvas, double r) {
    canvas.drawLine(Offset.zero, Offset(0, -r * 0.55),
      _symPaint..strokeWidth = 1.8);
    final c = Offset(0, -r * 0.95);
    canvas.drawCircle(c, r * 0.4, Paint()..color = cs.surface);
    canvas.drawCircle(c, r * 0.4, _symPaint..strokeWidth = 2.2);
  }

  void _symNorth(Canvas canvas, double r) {
    // Drawn pointing along +X (iso axis I, right) at dir=0 so the 60° rotation
    // steps cycle through the 6 iso headings (axis I/II/III × ±). This lets
    // [northArrowAxisMapping] read the arrow's heading straight off `dir`.
    final shaft = Paint()
      ..color = cs.tertiary
      ..strokeWidth = 2.6
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(Offset(-r * 0.7, 0), Offset(r * 0.55, 0), shaft);
    final head = Path()
      ..moveTo(r * 0.95, 0)
      ..lineTo(r * 0.45, -r * 0.28)
      ..lineTo(r * 0.45, r * 0.28)
      ..close();
    canvas.drawPath(head, Paint()..color = cs.tertiary);
    final tickPaint = _symPaint..strokeWidth = 1.4;
    for (int i = 0; i < 8; i++) {
      final a = i * math.pi / 4;
      final cosA = math.cos(a), sinA = math.sin(a);
      // N (along +X here) gets a double mark — two parallel ticks offset
      // perpendicular to the radial — so the cardinal stays distinguishable.
      if (i == 0) {
        const off = 0.06;
        for (final s in const [-1.0, 1.0]) {
          canvas.drawLine(
            Offset(r * cosA - s * r * off * sinA,
                r * sinA + s * r * off * cosA),
            Offset(r * 1.08 * cosA - s * r * off * sinA,
                r * 1.08 * sinA + s * r * off * cosA),
            tickPaint,
          );
        }
      } else {
        canvas.drawLine(
          Offset(r * cosA, r * sinA),
          Offset(r * 1.08 * cosA, r * 1.08 * sinA),
          tickPaint,
        );
      }
    }
    final tp = TextPainter(
      text: TextSpan(
        text: 'N',
        style: TextStyle(
            color: cs.tertiary, fontSize: 13, fontWeight: FontWeight.w900),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, Offset(r * 0.72, -tp.height / 2));
  }

  void _symFlow(Canvas canvas, double r) {
    final paint = Paint()
      ..color = cs.tertiary
      ..strokeWidth = 3.0
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(Offset(-r * 0.6, 0), Offset(r * 0.35, 0), paint);
    final head = Path()
      ..moveTo(r * 0.62, 0)
      ..lineTo(r * 0.2, -r * 0.3)
      ..lineTo(r * 0.2, r * 0.3)
      ..close();
    canvas.drawPath(head, Paint()..color = cs.tertiary);
  }

  /// Olet (weldolet / sockolet / threadolet) — a branch take-off without a
  /// full tee, welded directly onto a header. Drawn as a stubby triangle on
  /// the header centreline pointing toward the branch.
  void _symOlet(Canvas canvas, double r) {
    final p = _pipePaint;
    canvas.drawLine(Offset(-r, 0), Offset(r, 0), p); // header
    final stub = Path()
      ..moveTo(-r * 0.25, 0)
      ..lineTo(0, -r * 0.85)
      ..lineTo(r * 0.25, 0)
      ..close();
    canvas.drawPath(stub, _symFill);
    canvas.drawPath(stub, _symPaint);
  }

  /// Globe valve — circular body with the line crossing through; a small
  /// inset square represents the seat / plug. Class flag drawn as a tick at
  /// the top stem.
  void _symGlobe(Canvas canvas, double r) {
    final p = _pipePaint;
    canvas.drawLine(Offset(-r, 0), Offset(r, 0), p);
    canvas.drawCircle(Offset.zero, r * 0.55, _symPaint);
    canvas.drawCircle(Offset.zero, r * 0.22, Paint()..color = cs.secondary);
    // Stem
    canvas.drawLine(Offset(0, -r * 0.55), Offset(0, -r * 0.95), _symPaint);
    // Handwheel — short crossbar at top.
    canvas.drawLine(Offset(-r * 0.3, -r * 0.95), Offset(r * 0.3, -r * 0.95),
        _symPaint);
  }

  /// Butterfly valve — two open triangles facing each other along the line
  /// to suggest the disc plate seen edge-on.
  void _symButterfly(Canvas canvas, double r) {
    final p = _pipePaint;
    canvas.drawLine(Offset(-r, 0), Offset(r, 0), p);
    final body = Path()
      ..moveTo(-r * 0.7, -r * 0.55)
      ..lineTo(r * 0.7, r * 0.55)
      ..lineTo(-r * 0.7, r * 0.55)
      ..lineTo(r * 0.7, -r * 0.55)
      ..close();
    canvas.drawPath(body, _symPaint);
    canvas.drawCircle(Offset.zero, 3.5, Paint()..color = cs.secondary);
    canvas.drawLine(Offset(0, -r * 0.55), Offset(0, -r * 0.95), _symPaint);
  }

  /// Spool-break marker — a single zig-zag perpendicular to the pipe with
  /// the "BREAK" label, telling prefab where this assembly splits into
  /// shippable spools.
  void _symSpoolBreak(Canvas canvas, double r) {
    final stroke = Paint()
      ..color = cs.error
      ..strokeWidth = 2.0
      ..strokeCap = StrokeCap.round;
    final zig = Path()
      ..moveTo(0, -r * 0.9)
      ..lineTo(r * 0.25, -r * 0.45)
      ..lineTo(-r * 0.25, 0)
      ..lineTo(r * 0.25, r * 0.45)
      ..lineTo(0, r * 0.9);
    canvas.drawPath(zig, stroke..style = PaintingStyle.stroke);
    final tp = TextPainter(
      text: TextSpan(
        text: 'BRK',
        style: TextStyle(
            color: cs.error, fontSize: 8, fontWeight: FontWeight.w900),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, Offset(r * 0.55, -tp.height / 2));
  }

  @override
  bool shouldRepaint(_Painter old) =>
      version != old.version ||
      dragA != old.dragA ||
      dragB != old.dragB ||
      tool != old.tool ||
      axisLock != old.axisLock ||
      showStatusBox != old.showStatusBox ||
      paperMode != old.paperMode ||
      viewOffset != old.viewOffset ||
      viewScale != old.viewScale;
}

// ═══════════════════════════════════════════════════════════════════════════
// Bottom sheet — batch dimension entry for all pipe segments.
// ═══════════════════════════════════════════════════════════════════════════
class _DimensionsSheet extends StatefulWidget {
  final List<_Seg> segments;
  final Map<_Seg, TextEditingController> controllers;
  final List<_Comp> components;
  final Map<_Comp, TextEditingController> componentControllers;
  final String Function(String pl, String en) tr;
  final String Function(_Tool tool) compName;

  const _DimensionsSheet({
    required this.segments,
    required this.controllers,
    required this.components,
    required this.componentControllers,
    required this.tr,
    required this.compName,
  });

  @override
  State<_DimensionsSheet> createState() => _DimensionsSheetState();
}

class _DimensionsSheetState extends State<_DimensionsSheet> {
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return DraggableScrollableSheet(
      initialChildSize: 0.8,
      maxChildSize: 0.95,
      minChildSize: 0.4,
      expand: false,
      builder: (ctx, scrollCtrl) {
        return Container(
          decoration: BoxDecoration(
            color: cs.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            children: [
              const SizedBox(height: 8),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: cs.onSurfaceVariant.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
                child: Row(
                  children: [
                    Icon(Icons.straighten, color: cs.primary),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        widget.tr('Wymiary segmentów',
                            'Segment dimensions'),
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: cs.primaryContainer,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        '${widget.segments.length}',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          color: cs.onPrimaryContainer,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text(
                  widget.tr(
                    'Wprowadź wymiar ISO dla każdej rury (np. "3000", "3000+525-80", "5*200+150"). Puste pole = bez wymiaru.',
                    'Enter ISO dimension for each pipe (e.g. "3000", "3000+525-80", "5*200+150"). Empty = no dimension.',
                  ),
                  style: TextStyle(
                    fontSize: 11,
                    color: cs.onSurfaceVariant,
                    height: 1.4,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: ListView.separated(
                  controller: scrollCtrl,
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                  // segments + optional components section header + each comp.
                  itemCount: widget.segments.length +
                      (widget.components.isEmpty
                          ? 0
                          : 1 + widget.components.length),
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, i) {
                    if (i >= widget.segments.length) {
                      final compIdx = i - widget.segments.length;
                      if (compIdx == 0) {
                        return Padding(
                          padding: const EdgeInsets.only(top: 8, bottom: 4),
                          child: Row(children: [
                            Icon(Icons.settings_input_composite,
                                color: cs.secondary, size: 18),
                            const SizedBox(width: 8),
                            Text(
                              widget.tr(
                                  'Komponenty — wymiary do osi (mm)',
                                  'Components — centre-to-end dim (mm)'),
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w800,
                                color: cs.onSurfaceVariant,
                                letterSpacing: 0.4,
                              ),
                            ),
                          ]),
                        );
                      }
                      final comp = widget.components[compIdx - 1];
                      final cctrl = widget.componentControllers[comp]!;
                      final dnTag = comp.dn != null ? ' · DN${comp.dn}' : '';
                      return Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: cs.surfaceContainerHigh,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: cs.outlineVariant),
                        ),
                        child: Row(children: [
                          Container(
                            width: 32,
                            height: 32,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: cs.secondary.withValues(alpha: 0.15),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(Icons.tune,
                                size: 16, color: cs.secondary),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '${widget.compName(comp.t)}$dnTag',
                                  style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700),
                                ),
                                const SizedBox(height: 4),
                                TextField(
                                  controller: cctrl,
                                  keyboardType: const TextInputType
                                      .numberWithOptions(decimal: false),
                                  textInputAction: TextInputAction.next,
                                  decoration: InputDecoration(
                                    isDense: true,
                                    hintText: comp.isElbow
                                        ? widget.tr(
                                            'Do osi (CTE) np. 76',
                                            'Centre-to-end e.g. 76')
                                        : widget.tr(
                                            'Długość fizyczna np. 178',
                                            'Physical length e.g. 178'),
                                    suffixText: 'mm',
                                    border: const OutlineInputBorder(),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ]),
                      );
                    }
                    final seg = widget.segments[i];
                    final ctrl = widget.controllers[seg]!;
                    final hasCalc = seg.calc != null;
                    return Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: cs.surfaceContainerHigh,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: hasCalc
                              ? cs.primary.withValues(alpha: 0.3)
                              : cs.outlineVariant,
                        ),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 32,
                            height: 32,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: cs.primary.withValues(alpha: 0.15),
                              shape: BoxShape.circle,
                            ),
                            child: Text(
                              '${i + 1}',
                              style: TextStyle(
                                fontWeight: FontWeight.w800,
                                color: cs.primary,
                                fontSize: 13,
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            // No `onChanged: setState` here — the row's
                            // visual state doesn't depend on the typed
                            // text, only `seg.calc` (which is captured at
                            // sheet open). Calling setState on every
                            // keystroke would rebuild the entire ListView
                            // (N rows) for nothing — visible jank on
                            // routes with 50+ pipes. Controller text is
                            // read once on save in `_enterAllDimensions`.
                            child: TextField(
                              controller: ctrl,
                              keyboardType: const TextInputType
                                  .numberWithOptions(
                                  decimal: true, signed: true),
                              textInputAction:
                                  i == widget.segments.length - 1
                                      ? TextInputAction.done
                                      : TextInputAction.next,
                              decoration: InputDecoration(
                                isDense: true,
                                hintText: widget.tr(
                                    'Wymiar ISO (mm)',
                                    'ISO dimension (mm)'),
                                suffixText: 'mm',
                                border: const OutlineInputBorder(),
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
              SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                  child: Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => Navigator.pop(context, false),
                          child: Text(
                              widget.tr('Anuluj', 'Cancel')),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        flex: 2,
                        child: FilledButton.icon(
                          onPressed: () => Navigator.pop(context, true),
                          icon: const Icon(Icons.content_cut),
                          label: Text(widget.tr(
                              'Oblicz cut list', 'Calculate cut list')),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

// ─── Axis compass legend ──────────────────────────────────────────────────────
//
// Floating chip top-right of canvas. Shows the three iso axes (I/II/III) with
// the colour code used on per-line axis tags so the monter learns at a glance
// which direction is which. Static for now; future iteration will let the user
// rotate the mapping (drag/tap to swap which screen axis = real-world N/E/Up).

class _AxisCompass extends StatelessWidget {
  final ColorScheme cs;
  final _AxisMapping? mapping;
  const _AxisCompass({required this.cs, required this.mapping});

  static const _blue = Color(0xFF4A9EFF);
  static const _green = Color(0xFF2ECC71);
  static const _gold = Color(0xFFE8C14B);

  static const _axisColors = <_Axis, Color>{
    _Axis.i: _blue,
    _Axis.ii: _green,
    _Axis.iii: _gold,
  };

  String _roleLabel(BuildContext context, _Axis a) {
    final role = mapping?.roleFor(a);
    if (role == 'N') return context.tr(pl: 'N–S', en: 'N–S');
    if (role == 'E') return context.tr(pl: 'E–W', en: 'E–W');
    if (role == 'U') return context.tr(pl: 'góra/dół', en: 'up/down');
    return switch (a) {
      _Axis.i => context.tr(pl: 'poziom A', en: 'horiz A'),
      _Axis.ii => context.tr(pl: 'poziom B', en: 'horiz B'),
      _Axis.iii => context.tr(pl: 'pion', en: 'vertical'),
      _Axis.off => '',
    };
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: cs.surface.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: cs.outlineVariant, width: 0.8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            mapping == null
                ? context.tr(pl: 'OSIE ISO', en: 'ISO AXES')
                : context.tr(pl: 'KIERUNKI 3D', en: '3D DIRECTIONS'),
            style: TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.w900,
              color: cs.onSurfaceVariant,
              letterSpacing: 1.0,
            ),
          ),
          const SizedBox(height: 6),
          SizedBox(
            width: 64,
            height: 64,
            // Compass is purely decorative — the axis label above and the
            // legend rows below already announce the same info to screen
            // readers, so hide the painter to avoid duplicate semantics.
            child: ExcludeSemantics(
              child: CustomPaint(painter: _AxisCompassPainter(mapping: mapping)),
            ),
          ),
          const SizedBox(height: 6),
          for (final a in const [_Axis.i, _Axis.ii, _Axis.iii])
            _legendRow(
              _axisColors[a]!,
              mapping?.roleFor(a).isNotEmpty == true
                  ? mapping!.roleFor(a)
                  : a.label,
              _roleLabel(context, a),
            ),
          if (mapping == null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                context.tr(
                  pl: 'Postaw strzałkę N — osie dostaną N/E/↑',
                  en: 'Place N arrow — axes get N/E/↑',
                ),
                style: TextStyle(
                  fontSize: 8,
                  fontStyle: FontStyle.italic,
                  color: cs.onSurfaceVariant,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _legendRow(Color c, String tag, String label) {
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Container(
          width: 16,
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
          decoration: BoxDecoration(
            color: c.withValues(alpha: 0.18),
            borderRadius: BorderRadius.circular(3),
            border: Border.all(color: c.withValues(alpha: 0.5), width: 0.7),
          ),
          child: Text(tag,
              style: TextStyle(
                fontSize: 8,
                fontWeight: FontWeight.w900,
                color: c,
              )),
        ),
        const SizedBox(width: 5),
        Text(label,
            style: TextStyle(
              fontSize: 9,
              color: cs.onSurfaceVariant,
            )),
      ]),
    );
  }
}

class _AxisCompassPainter extends CustomPainter {
  static const _blue = Color(0xFF4A9EFF);
  static const _green = Color(0xFF2ECC71);
  static const _gold = Color(0xFFE8C14B);
  static const _sqrt3 = 1.7320508075688772;

  final _AxisMapping? mapping;
  const _AxisCompassPainter({required this.mapping});

  String _labelFor(_Axis a) {
    if (mapping == null) return a.label;
    final role = mapping!.roleFor(a);
    return role.isNotEmpty ? role : a.label;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    const r = 24.0;

    // Three axes through centre: I = horizontal (0°), II = 60°, III = 120°.
    final dirs = <(Offset, Color, _Axis)>[
      (Offset(r, 0), _blue, _Axis.i),
      (Offset(r * 0.5, r * _sqrt3 / 2), _green, _Axis.ii),
      (Offset(-r * 0.5, r * _sqrt3 / 2), _gold, _Axis.iii),
    ];

    for (final d in dirs) {
      final v = d.$1;
      final color = d.$2;
      final label = _labelFor(d.$3);
      final paint = Paint()
        ..color = color
        ..strokeWidth = 1.8
        ..strokeCap = StrokeCap.round;
      canvas.drawLine(c - v, c + v, paint);
      final unit = v / v.distance;
      final perp = Offset(-unit.dy, unit.dx);
      final tip = c + v;
      canvas.drawLine(tip, tip - unit * 5 + perp * 3, paint);
      canvas.drawLine(tip, tip - unit * 5 - perp * 3, paint);

      final tp = TextPainter(
        text: TextSpan(
          text: label,
          style: TextStyle(
            color: color,
            fontSize: 9,
            fontWeight: FontWeight.w900,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, tip + unit * 3 - Offset(tp.width / 2, tp.height / 2));
    }
  }

  @override
  bool shouldRepaint(covariant _AxisCompassPainter old) =>
      old.mapping?.nsAxis != mapping?.nsAxis;
}
