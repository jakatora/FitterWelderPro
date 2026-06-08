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

class PrefabEngine {
  const PrefabEngine._();

  /// Cut length of a pipe segment in millimetres, given the ISO dimension
  /// between two anchors and how that dimension was measured (`ref`).
  ///
  /// The engine is direction-agnostic: it sums per-side contributions based
  /// on which DimRef stop-type applies to each side, then picks values out
  /// of `leftCteMm` / `rightCteMm` (axial — for sides that stop at centre)
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
  /// `midPhysicalSumMm` is always subtracted — components living between
  /// the two ends add to the dimensioned span no matter how the ends were
  /// measured.
  static double cutLengthMm({
    required double isoValueMm,
    required DimRef ref,
    int? leftCteMm,
    int? rightCteMm,
    int? leftPhysicalLenMm,
    int? rightPhysicalLenMm,
    int midPhysicalSumMm = 0,
    bool leftIsPhysical = false,
    bool rightIsPhysical = false,
  }) {
    // P0-09: also guard non-finite ISO (e.g. `1e500` → infinity from the
    // parser). The legacy NaN-only guard let infinity through which then
    // poisoned every downstream sum.
    if (!isoValueMm.isFinite) return double.nan;

    final lc = leftCteMm ?? 0;
    final rc = rightCteMm ?? 0;
    final lp = leftPhysicalLenMm ?? 0;
    final rp = rightPhysicalLenMm ?? 0;
    final cteBoth = lc + rc;
    final phyBoth = lp + rp;

    double cut;
    switch (ref) {
      case DimRef.centreToCentre:
        cut = isoValueMm - cteBoth - midPhysicalSumMm;
        break;
      case DimRef.centreToFace:
        // P0-09: subtract ONLY the centre side's CTE — the face side stops
        // at the face (no body subtracted). If the caller signals which
        // side is physical via leftIsPhysical/rightIsPhysical, the face is
        // the physical side and we credit the OTHER side's CTE only.
        // Legacy behaviour (sum both CTEs) was a 55-76 mm over-subtraction
        // on every elbow→flange spool, producing pipe undersized at
        // fit-up — scrap risk on every job.
        final double centreCte;
        if (leftIsPhysical && !rightIsPhysical) {
          centreCte = rc.toDouble();
        } else if (!leftIsPhysical && rightIsPhysical) {
          centreCte = lc.toDouble();
        } else {
          // Caller didn't tell us which side is the face. Fall back to
          // the more conservative behaviour: credit the larger CTE so we
          // don't over-cut. If both sides are zero or equal this matches
          // the legacy single-side credit.
          centreCte = lc > rc ? lc.toDouble() : rc.toDouble();
        }
        cut = isoValueMm - centreCte - midPhysicalSumMm;
        break;
      case DimRef.faceToFace:
        cut = isoValueMm - midPhysicalSumMm;
        break;
      case DimRef.faceToEnd:
        cut = isoValueMm - phyBoth - midPhysicalSumMm;
        break;
      case DimRef.centreToEnd:
        cut = isoValueMm - cteBoth - phyBoth - midPhysicalSumMm;
        break;
    }
    // P0-09: <=0 sentinel — propagating a negative number to the cut list
    // appears in the BOM as a plausible-looking small number; NaN forces
    // the warning chip to fire.
    if (!cut.isFinite || cut <= 0) return double.nan;
    return cut;
  }

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
