/// One piece of pipe the cut list asks for, before it is laid out on bars.
///
/// [label] identifies the source segment on the saw (`S03`), [reference] is
/// the dimension as written on the drawing (the segment's ISO expression), so
/// a piece on the bar plan can be traced back to where it goes.
class CutRequest {
  final double lengthMm;
  final String? label;
  final String? reference;

  const CutRequest(this.lengthMm, {this.label, this.reference});
}

/// One piece laid out on a stock bar.
///
/// A requested cut longer than the stock bar is split into full bars plus a
/// remainder (see [nestPiecesToBars]). Every part keeps the label of its
/// source cut and knows which part it is, so the plan says `S03 (1/2)` and
/// `S03 (2/2)` instead of silently listing `6000` and `1000` — those two
/// parts need an extra joining weld that the fitter has to plan for.
class BarPiece {
  final double lengthMm;
  final String? label;
  final String? reference;

  /// 1-based part number; 1 when the cut fits on one bar.
  final int part;

  /// Number of parts the source cut was split into; 1 when not split.
  final int partCount;

  /// The full length that was requested (equal to [lengthMm] when not split).
  final double sourceLengthMm;

  const BarPiece({
    required this.lengthMm,
    this.label,
    this.reference,
    this.part = 1,
    this.partCount = 1,
    double? sourceLengthMm,
  }) : sourceLengthMm = sourceLengthMm ?? lengthMm;

  /// True when the source cut is longer than a stock bar and this is one of
  /// its parts.
  bool get isSplit => partCount > 1;

  /// Short tag for the saw operator: `S03`, `S03 (1/2)`, `(1/2)` for an
  /// unlabelled split part, or null for an unlabelled whole piece.
  String? get tag {
    if (!isSplit) return label;
    final partTag = '($part/$partCount)';
    return label == null ? partTag : '$label $partTag';
  }
}

class BarPlan {
  /// Pieces cut from this bar, in the order the nesting placed them.
  final List<BarPiece> pieces;
  final double remainingMm;
  final int cutsCount;

  /// [cutsCount] is the number of saw cuts required to obtain [pieces]
  /// from a single stock bar.
  ///
  /// Kerf is per *cut* (as per spec), not per *piece*.
  ///
  /// Examples:
  /// - 1 piece equal to full bar (6000 from 6000): 0 cuts
  /// - 3 pieces that exactly consume the bar (2000+2000+2000): 2 cuts
  /// - 3 pieces with leftover scrap: 3 cuts
  BarPlan({
    required List<BarPiece> pieces,
    required this.remainingMm,
    required this.cutsCount,
  })  : pieces = List<BarPiece>.unmodifiable(pieces),
        piecesMm = List<double>.unmodifiable([for (final p in pieces) p.lengthMm]);

  /// Lengths of [pieces], same order.
  final List<double> piecesMm;

  /// True when at least one piece on this bar is part of a split cut.
  bool get hasSplitPiece => pieces.any((p) => p.isSplit);
}

/// Unlabelled variant of [nestPiecesToBars], kept for callers that only have
/// lengths. Produces exactly the same bars.
List<BarPlan> nestCutsToBars({
  required List<double> cutsMm,
  required double stockLengthMm,
  required double sawKerfMm,
}) {
  return nestPiecesToBars(
    cuts: [for (final c in cutsMm) CutRequest(c)],
    stockLengthMm: stockLengthMm,
    sawKerfMm: sawKerfMm,
  );
}

/// Lays the requested [cuts] out on stock bars of [stockLengthMm]
/// (first-fit-decreasing with best fit for the remaining space).
///
/// Every piece on the result carries the label of the cut it came from. Ties
/// between equal lengths keep the input order, so the same cut list always
/// gives the same labels on the same bars.
List<BarPlan> nestPiecesToBars({
  required List<CutRequest> cuts,
  required double stockLengthMm,
  required double sawKerfMm,
}) {
  if (stockLengthMm <= 0) return [];

  // Stable descending sort: equal lengths keep their input order.
  final order = [for (var i = 0; i < cuts.length; i++) i]
    ..sort((a, b) {
      final byLength = cuts[b].lengthMm.compareTo(cuts[a].lengthMm);
      return byLength != 0 ? byLength : a.compareTo(b);
    });

  // Expand very long cuts into "full bars + remainder" so the fitter can see
  // how many stock lengths are required. Each part is tagged (1/n … n/n):
  // splitting a cut means an extra joining weld.
  final expanded = <BarPiece>[];
  for (final index in order) {
    final cut = cuts[index];
    final c = cut.lengthMm;
    // A non-finite length is garbage input; an infinite one used to spin the
    // split loop below forever.
    if (!c.isFinite || c <= 0) continue;
    if (c <= stockLengthMm) {
      expanded.add(BarPiece(
        lengthMm: c,
        label: cut.label,
        reference: cut.reference,
      ));
      continue;
    }
    final parts = <double>[];
    var remaining = c;
    while (remaining > stockLengthMm) {
      parts.add(stockLengthMm);
      remaining -= stockLengthMm;
    }
    if (remaining > 0) parts.add(remaining);
    for (var p = 0; p < parts.length; p++) {
      expanded.add(BarPiece(
        lengthMm: parts[p],
        label: cut.label,
        reference: cut.reference,
        part: p + 1,
        partCount: parts.length,
        sourceLengthMm: c,
      ));
    }
  }

  // Stable again: pieces were appended in (length desc, input order), so a
  // stable sort by length keeps that order among equal lengths.
  final indexed = [for (var i = 0; i < expanded.length; i++) (i, expanded[i])]
    ..sort((a, b) {
      final byLength = b.$2.lengthMm.compareTo(a.$2.lengthMm);
      return byLength != 0 ? byLength : a.$1.compareTo(b.$1);
    });
  final queue = [for (final e in indexed) e.$2];

  final plans = <BarPlan>[];
  while (queue.isNotEmpty) {
    final pieces = <BarPiece>[];
    // Take first (largest)
    final first = queue.removeAt(0);
    pieces.add(first);

    // Packing heuristic uses a conservative per-piece kerf while selecting.
    // We recompute the true remaining and cut count at the end of the bar plan.
    double remaining = stockLengthMm - (first.lengthMm + sawKerfMm);

    // Best-fit fill
    while (true) {
      final maxPieceAllowed = remaining - sawKerfMm;
      if (maxPieceAllowed <= 0) break;

      int pickedIndex = -1;
      double pickedValue = 0;
      for (var i = 0; i < queue.length; i++) {
        final v = queue[i].lengthMm;
        if (v <= maxPieceAllowed && v > pickedValue) {
          pickedValue = v;
          pickedIndex = i;
        }
      }
      if (pickedIndex == -1) break;

      pieces.add(queue.removeAt(pickedIndex));
      remaining -= (pickedValue + sawKerfMm);
    }

    // Recompute using kerf-per-cut rules.
    final sumPieces = pieces.fold<double>(0, (a, b) => a + b.lengthMm);
    final fullyConsumed = (stockLengthMm - sumPieces).abs() < 1e-6;
    final cutsCount = fullyConsumed
        ? (pieces.length <= 1 ? 0 : pieces.length - 1)
        : pieces.length;
    var trueRemaining = stockLengthMm - sumPieces - (cutsCount * sawKerfMm);
    if (trueRemaining < 0) trueRemaining = 0;

    plans.add(BarPlan(
      pieces: pieces,
      remainingMm: trueRemaining,
      cutsCount: cutsCount,
    ));
  }

  return plans;
}
