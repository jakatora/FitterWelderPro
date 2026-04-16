class BarPlan {
  final List<double> piecesMm;
  final double remainingMm;
  final int cutsCount;

  /// [cutsCount] is the number of saw cuts required to obtain [piecesMm]
  /// from a single stock bar.
  ///
  /// Kerf is per *cut* (as per spec), not per *piece*.
  ///
  /// Examples:
  /// - 1 piece equal to full bar (6000 from 6000): 0 cuts
  /// - 3 pieces that exactly consume the bar (2000+2000+2000): 2 cuts
  /// - 3 pieces with leftover scrap: 3 cuts
  BarPlan({required this.piecesMm, required this.remainingMm, required this.cutsCount});
}

List<BarPlan> nestCutsToBars({
  required List<double> cutsMm,
  required double stockLengthMm,
  required double sawKerfMm,
}) {
  if (stockLengthMm <= 0) return [];
  final cuts = List<double>.from(cutsMm);
  cuts.sort((a, b) => b.compareTo(a));

  final plans = <BarPlan>[];

  // Expand very long cuts into "full bars + remainder" so the fitter can see
  // how many stock lengths are required.
  final expanded = <double>[];
  for (final c in cuts) {
    if (c <= 0) continue;
    if (c <= stockLengthMm) {
      expanded.add(c);
    } else {
      var remaining = c;
      while (remaining > stockLengthMm) {
        expanded.add(stockLengthMm);
        remaining -= stockLengthMm;
      }
      if (remaining > 0) expanded.add(remaining);
    }
  }

  expanded.sort((a, b) => b.compareTo(a));

  while (expanded.isNotEmpty) {
    final pieces = <double>[];
    // Take first (largest)
    final first = expanded.removeAt(0);
    pieces.add(first);

    // Packing heuristic uses a conservative per-piece kerf while selecting.
    // We recompute the true remaining and cut count at the end of the bar plan.
    double remaining = stockLengthMm - (first + sawKerfMm);

    // Best-fit fill
    while (true) {
      final maxPieceAllowed = remaining - sawKerfMm;
      if (maxPieceAllowed <= 0) break;

      int pickedIndex = -1;
      double pickedValue = 0;
      for (var i = 0; i < expanded.length; i++) {
        final v = expanded[i];
        if (v <= maxPieceAllowed && v > pickedValue) {
          pickedValue = v;
          pickedIndex = i;
        }
      }
      if (pickedIndex == -1) break;

      pieces.add(pickedValue);
      expanded.removeAt(pickedIndex);
      remaining -= (pickedValue + sawKerfMm);
    }

    // Remaining can't be negative due to checks, but clamp.
    if (remaining < 0) remaining = 0;

    // Recompute using kerf-per-cut rules.
    final sumPieces = pieces.fold<double>(0, (a, b) => a + b);
    final fullyConsumed = (stockLengthMm - sumPieces).abs() < 1e-6;
    final cutsCount = fullyConsumed ? (pieces.length <= 1 ? 0 : pieces.length - 1) : pieces.length;
    var trueRemaining = stockLengthMm - sumPieces - (cutsCount * sawKerfMm);
    if (trueRemaining < 0) trueRemaining = 0;

    plans.add(BarPlan(piecesMm: pieces, remainingMm: trueRemaining, cutsCount: cutsCount));
  }

  return plans;
}
