/// Pure logic kernel for CUT-list math.
///
/// `iso_notebook_screen` adapts its private `_Seg`/`_Comp` types into the
/// primitive args accepted here, so this engine has no dependency on UI
/// model classes. All lengths are millimetres (the app's internal base unit);
/// the UI layer is the only place that knows about display units.
///
/// Tests live in `test/services/prefab_engine_test.dart`.
library;

import '../models/prefab/dim_ref.dart';

/// Where the ISO dimension stops on ONE side of a segment.
///
/// A [DimRef] names a PAIR of stops but not which side each one belongs to:
/// `CTF` is the same code whether the centre is at the left anchor or at the
/// right one. The `leftIsPhysical` / `rightIsPhysical` flags cannot close
/// that gap either — they say WHICH side carries a body, not whether that
/// body lies inside the dimensioned span for the chosen reference point (the
/// very same valve contributes 0 at a [face] stop and its whole body at an
/// [end] stop). A caller that knows its own geometry states both stops and
/// the engine never has to guess.
enum SideStop {
  /// The dimension stops AT the component face, so none of the component
  /// lies inside the dimensioned span: this side subtracts nothing.
  face,

  /// The dimension runs THROUGH the component to its far end, so this side
  /// subtracts the component's physical body length.
  end,

  /// The dimension stops at the component's axial centreline, so this side
  /// subtracts its centre-to-end take-out.
  centre,
}

/// The stop a stored reference-point code stands for, or null for a code
/// that names no stop (legacy `'FACE'`, an empty half, garbage).
///
/// The codes are the ones `segments.iso_ref` holds, `START|END`, written by
/// the segment builder (`IsoRefPoint.code`) and by the scan review:
///   * `FACE_NEAR`, `OPEN` — the dimension stops at the face the pipe meets
///     (or at a free pipe end), nothing of the anchor lies in the span;
///   * `AXIS`, `CENTER` — it stops on the anchor's centreline;
///   * `FACE_FAR` — it runs through the anchor's body to its far face.
///
/// One table for every reader: the builder maps its enum through it, and a
/// saved row is decoded with it when the project's gap changes, so a code can
/// never mean one stop on screen and another in the recompute.
SideStop? sideStopForRefCode(String code) {
  switch (code) {
    case 'FACE_NEAR':
    case 'OPEN':
      return SideStop.face;
    case 'AXIS':
    case 'CENTER':
      return SideStop.centre;
    case 'FACE_FAR':
      return SideStop.end;
  }
  return null;
}

class PrefabEngine {
  const PrefabEngine._();

  /// CUT of a pipe between two anchors whose stops are known exactly, each
  /// with the length that stop takes off ([startOffsetMm] / [endOffsetMm]:
  /// the take-out for a centre stop, the body for an end stop, ignored for a
  /// face stop), less [gapMm] × [welds]. NaN when there is nothing to cut.
  ///
  /// This is the rule every anchored caller shares — the segment builder, the
  /// scan review, and the recompute of saved segments after a project's gap
  /// changes — so a segment saved on one of those paths and reopened on
  /// another comes back with the same number.
  static double anchoredCutMm({
    required double isoMm,
    required SideStop startStop,
    required double startOffsetMm,
    required SideStop endStop,
    required double endOffsetMm,
    required double gapMm,
    required int welds,
  }) {
    return cutLengthMm(
      isoValueMm: isoMm,
      leftStop: startStop,
      rightStop: endStop,
      leftCteMm: startStop == SideStop.centre ? startOffsetMm : null,
      leftPhysicalLenMm: startStop == SideStop.end ? startOffsetMm : null,
      rightCteMm: endStop == SideStop.centre ? endOffsetMm : null,
      rightPhysicalLenMm: endStop == SideStop.end ? endOffsetMm : null,
      weldGapMm: gapMm,
      weldCount: welds,
    );
  }

  /// Which stop [cutLengthMm] gives each side for the same arguments, or null
  /// when it has nothing to work from (it would return NaN).
  ///
  /// Public so a caller that measured by [DimRef] can store what was actually
  /// subtracted on each side — the scan review writes these stops into
  /// `segments.iso_ref` — instead of a guess that reopens as a different cut.
  static ({SideStop left, SideStop right})? resolveSideStops({
    DimRef? ref,
    num? leftCteMm,
    num? rightCteMm,
    num? leftPhysicalLenMm,
    num? rightPhysicalLenMm,
    bool leftIsPhysical = false,
    bool rightIsPhysical = false,
    SideStop? leftStop,
    SideStop? rightStop,
  }) {
    return _resolveStops(
      ref: ref,
      leftStop: leftStop,
      rightStop: rightStop,
      leftIsPhysical: leftIsPhysical,
      rightIsPhysical: rightIsPhysical,
      lc: (leftCteMm ?? 0).toDouble(),
      rc: (rightCteMm ?? 0).toDouble(),
      lp: (leftPhysicalLenMm ?? 0).toDouble(),
      rp: (rightPhysicalLenMm ?? 0).toDouble(),
    );
  }

  /// Cut length of a pipe segment in millimetres, given the ISO dimension
  /// between two anchors and how that dimension was measured.
  ///
  /// The engine is direction-agnostic: it sums per-side contributions based
  /// on which [SideStop] applies to each side, then picks values out of
  /// `leftCteMm` / `rightCteMm` (axial — for sides that stop at centre)
  /// and `leftPhysicalLenMm` / `rightPhysicalLenMm` (physical body — for
  /// sides that go all the way through to the end). DimRef pairs are
  /// symmetric: `CTF` covers both axial-physical and physical-axial spool
  /// orders, so callers don't have to canonicalize side ordering before
  /// dispatching.
  ///
  /// Per-side contribution rules:
  ///   centre  → that side's CTE (it ends at the axial centreline)
  ///   face    → 0 (the dimension stops AT the face — no body subtracted)
  ///   end     → that side's physical body length (the dimension goes ALL
  ///             the way through the component to its far end, so the pipe
  ///             stops at the component's face, which is body-length short)
  ///
  /// Each rule applies to ONE side. Every DimRef therefore spends exactly
  /// two contributions — one per anchor — and the only open question is
  /// which side gets which. [leftStop] / [rightStop] answer it outright, and
  /// with both given [ref] is not needed at all (pass null): that also
  /// covers shapes DimRef cannot name, such as a dimension running through
  /// the body at BOTH anchors. Without them the engine falls back to:
  ///   * exactly one side flagged physical → that side takes the stop that
  ///     consumes a body (`end`, or `face` for the centre/face pair, which
  ///     is the side a bodied component sits on in CTF);
  ///   * otherwise the assignment that subtracts MORE wins — the same
  ///     conservative tie-break the CTF path has always used.
  ///
  /// Both fall-backs still spend one contribution per side. The FTE and CTE
  /// branches used to subtract the body of BOTH ends (CTE both CTEs on top
  /// of that), contradicting the per-side rules right above them: an FTE run
  /// between two DN100 valves lost 458 mm instead of 229 and the pipe came
  /// back 229 mm short — scrap, on a dimension the fitter had read correctly.
  ///
  /// `midPhysicalSumMm` is always subtracted — components living between
  /// the two ends add to the dimensioned span no matter how the ends were
  /// measured.
  ///
  /// `weldGapMm` × `weldCount` is subtracted last: the root gap left open at
  /// each joint is length the saw must not take. Both default to 0 so that
  /// callers which never modelled the gap keep their exact numbers.
  ///
  /// Who actually passes a gap — "one engine" does not mean more than this:
  ///   * the segment builder and the scan review do, with the project's
  ///     `gap_mm` and [weldCountForEnds] welds, both through
  ///     [anchoredCutMm] (the scan review used to save gap 0 and pass none);
  ///   * the ISO notebook does NOT: it has no gap setting and calls this with
  ///     the defaults. With a project gap above 0 the same run therefore comes
  ///     out `gap × welds` longer in the notebook than in the builder. The
  ///     engine agreeing with itself does not make those two screens agree —
  ///     only the notebook passing a gap would.
  ///
  /// The four component-length parameters take `num` rather than `int` so a
  /// caller holding sub-millimetre take-outs (a 76.2 mm elbow) does not have
  /// to round before asking. `int` arguments still satisfy `num`, so this is
  /// invisible to callers that pass whole millimetres.
  static double cutLengthMm({
    required double isoValueMm,
    DimRef? ref,
    num? leftCteMm,
    num? rightCteMm,
    num? leftPhysicalLenMm,
    num? rightPhysicalLenMm,
    num midPhysicalSumMm = 0,
    bool leftIsPhysical = false,
    bool rightIsPhysical = false,
    SideStop? leftStop,
    SideStop? rightStop,
    double weldGapMm = 0,
    int weldCount = 0,
  }) {
    // P0-09: also guard non-finite ISO (e.g. `1e500` → infinity from the
    // parser). The legacy NaN-only guard let infinity through which then
    // poisoned every downstream sum.
    if (!isoValueMm.isFinite) return double.nan;

    final lc = (leftCteMm ?? 0).toDouble();
    final rc = (rightCteMm ?? 0).toDouble();
    final lp = (leftPhysicalLenMm ?? 0).toDouble();
    final rp = (rightPhysicalLenMm ?? 0).toDouble();

    final stops = _resolveStops(
      ref: ref,
      leftStop: leftStop,
      rightStop: rightStop,
      leftIsPhysical: leftIsPhysical,
      rightIsPhysical: rightIsPhysical,
      lc: lc,
      rc: rc,
      lp: lp,
      rp: rp,
    );
    // Neither an explicit stop pair nor a DimRef: there is no rule to apply,
    // and inventing one is how a wrong length reaches the saw. NaN is the
    // engine's established "do not cut this" signal.
    if (stops == null) return double.nan;

    final endsSum = _sideDeduction(stops.left, lc, lp) +
        _sideDeduction(stops.right, rc, rp);

    // A negative gap or a negative weld count is nonsense input, not a
    // reason to ADD length to the pipe.
    final gapTotal = (weldGapMm.isFinite && weldGapMm > 0 && weldCount > 0)
        ? weldGapMm * weldCount
        : 0.0;

    final cut = isoValueMm - endsSum - midPhysicalSumMm.toDouble() - gapTotal;

    // P0-09: <=0 sentinel — propagating a negative number to the cut list
    // appears in the BOM as a plausible-looking small number; NaN forces
    // the warning chip to fire.
    if (!cut.isFinite || cut <= 0) return double.nan;
    return cut;
  }

  /// What one side takes off the dimension, per the rules documented on
  /// [cutLengthMm]. The single place those three rules are spelled out in
  /// code, so a side can never be charged twice for one stop.
  static double _sideDeduction(SideStop stop, double cteMm, double physicalMm) {
    switch (stop) {
      case SideStop.centre:
        return cteMm;
      case SideStop.face:
        return 0;
      case SideStop.end:
        return physicalMm;
    }
  }

  /// The pair of stops a [DimRef] describes — in no particular side order,
  /// because the code itself carries none.
  static (SideStop, SideStop) _stopPairFor(DimRef ref) {
    switch (ref) {
      case DimRef.centreToCentre:
        return (SideStop.centre, SideStop.centre);
      case DimRef.centreToFace:
        return (SideStop.centre, SideStop.face);
      case DimRef.faceToFace:
        return (SideStop.face, SideStop.face);
      case DimRef.faceToEnd:
        return (SideStop.face, SideStop.end);
      case DimRef.centreToEnd:
        return (SideStop.centre, SideStop.end);
    }
  }

  /// Works out which stop belongs to which side, or null when there is
  /// nothing to work from. See [cutLengthMm] for the precedence order.
  static ({SideStop left, SideStop right})? _resolveStops({
    required DimRef? ref,
    required SideStop? leftStop,
    required SideStop? rightStop,
    required bool leftIsPhysical,
    required bool rightIsPhysical,
    required double lc,
    required double rc,
    required double lp,
    required double rp,
  }) {
    // Told outright — no DimRef needed, nothing to guess.
    if (leftStop != null && rightStop != null) {
      return (left: leftStop, right: rightStop);
    }
    if (ref == null) return null;

    final (a, b) = _stopPairFor(ref);

    // One side pinned: the other takes what is left of the pair. A pinned
    // stop that is not in the pair contradicts `ref`; guessing which of the
    // two the caller meant would be worse than dropping the hint, so that
    // case falls through to the rules below.
    if (leftStop != null && (leftStop == a || leftStop == b)) {
      return (left: leftStop, right: leftStop == a ? b : a);
    }
    if (rightStop != null && (rightStop == a || rightStop == b)) {
      return (left: rightStop == a ? b : a, right: rightStop);
    }

    // Symmetric pair (CTC, FTF): both sides get the same stop, so no
    // ordering question exists.
    if (a == b) return (left: a, right: b);

    // Exactly one bodied side: that side is the one the dimension either
    // stops at (CTF) or runs through (FTE, CTE), so the axial stop goes to
    // the other side. This is the flag pair's real job — narrowing the
    // ordering — rather than deciding whether a body counts at all.
    if (leftIsPhysical != rightIsPhysical) {
      final bodied = (a == SideStop.end || b == SideStop.end)
          ? SideStop.end
          : (a == SideStop.centre ? b : a);
      final other = bodied == a ? b : a;
      return leftIsPhysical
          ? (left: bodied, right: other)
          : (left: other, right: bodied);
    }

    // Both sides bodied, or neither: the drawing code alone cannot say which
    // anchor was measured which way. Take the assignment that subtracts more
    // — the tie-break the CTF path already used ("credit the larger CTE"),
    // now applied to every asymmetric pair instead of only that one.
    final direct = _sideDeduction(a, lc, lp) + _sideDeduction(b, rc, rp);
    final swapped = _sideDeduction(b, lc, lp) + _sideDeduction(a, rc, rp);
    return direct >= swapped ? (left: a, right: b) : (left: b, right: a);
  }

  /// How many welded joints — and therefore how many root gaps — a pipe run
  /// between two anchors has: one for every anchor the pipe is welded to, none
  /// for a free end (OPEN_END: the pipe simply stops there, nothing is welded
  /// and no gap is left open).
  ///
  /// The single rule behind `weldCount` for every caller that has anchors
  /// rather than a drawing: the segment builder (its CUT, its breakdown and
  /// its diagram label), the scan review and the recompute of saved segments
  /// after a project's gap changes. The builder used to decide this from the
  /// START alone (`START == OPEN_END ? 1 : 2`), so an elbow → open end run lost
  /// two gaps for its one weld and an open → open run lost one gap for none —
  /// both times a pipe cut short by the gap, which cannot be welded back on.
  static int weldCountForEnds({
    required bool startIsOpenEnd,
    required bool endIsOpenEnd,
  }) =>
      (startIsOpenEnd ? 0 : 1) + (endIsOpenEnd ? 0 : 1);

  /// Whether the notebook should prompt the user to pick a `DimRef`.
  ///
  /// Per user directive 2026-05-31: axial-on-both-sides defaults to CTC
  /// silently; any physical end forces the picker because the source drawing
  /// can have measured against face or end with no way to infer which.
  static bool needsDimRefPicker({
    required bool leftIsPhysical,
    required bool rightIsPhysical,
  }) {
    return leftIsPhysical || rightIsPhysical;
  }
}
