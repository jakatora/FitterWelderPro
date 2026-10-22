/// Aggregate readback of the current sheet; excludes names, IDs and annotations.
class SketchSummary {
  const SketchSummary(
      {required this.pipeCount,
      required this.computedCutCount,
      required this.computedCutTotalMm,
      required this.gapMm});
  final int pipeCount, computedCutCount;
  final double computedCutTotalMm, gapMm;

  /// Exact bounded wire contract; metadata and drawing identity stay local.
  Map<String, Object?> toJson() => {
        'pipe_count': pipeCount,
        'computed_cut_count': computedCutCount,
        'computed_cut_total_mm': computedCutTotalMm,
        'gap_mm': gapMm,
      };
}
