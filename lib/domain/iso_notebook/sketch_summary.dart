/// Aggregate readback of the current sheet; excludes names, IDs and annotations.
class SketchSummary {
  const SketchSummary(
      {required this.pipeCount,
      required this.computedCutCount,
      required this.computedCutTotalMm,
      required this.gapMm});
  final int pipeCount, computedCutCount;
  final double computedCutTotalMm, gapMm;
}
