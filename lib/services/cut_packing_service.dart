class CutPackingService {
  /// Packs CUT lengths into stock bars (default 6000mm).
  ///
  /// Logic matches the workshop workflow:
  /// 1) Start a bar with the largest remaining cut.
  /// 2) Keep adding the largest cut that fits in the remaining space.
  /// 3) If nothing fits, start a new bar.
  static List<List<double>> packGreedyLargestThatFits(
    List<double> cuts, {
    double stockLength = 6000,
  }) {
    final remainingCuts = List<double>.from(cuts)
      ..sort((a, b) => b.compareTo(a));

    final List<List<double>> bars = [];

    while (remainingCuts.isNotEmpty) {
      final bar = <double>[];
      var sum = 0.0;

      // Start with the largest piece.
      final first = remainingCuts.removeAt(0);
      bar.add(first);
      sum += first;

      while (true) {
        final remaining = stockLength - sum;
        if (remaining <= 0) break;

        // List is sorted descending, so the first that fits is the largest that fits.
        var bestIndex = -1;
        for (var i = 0; i < remainingCuts.length; i++) {
          if (remainingCuts[i] <= remaining) {
            bestIndex = i;
            break;
          }
        }

        if (bestIndex == -1) break;

        final picked = remainingCuts.removeAt(bestIndex);
        bar.add(picked);
        sum += picked;
      }

      bars.add(bar);
    }

    return bars;
  }
}
