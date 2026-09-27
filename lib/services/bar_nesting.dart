/// One piece of pipe the cut list asks for, before it is laid out on bars.
///
/// [label] identifies the source segment on the saw (`S03`), [reference] is
/// the dimension as written on the drawing (the segment's ISO expression), so
/// a piece on the bar plan can be traced back to where it goes.
class CutRequest {
  final double lengthMm;
  final String? label;
  final String? reference;

  /// Id of the source segment — what a piece ticked off at the saw is
  /// remembered by (`cut_marks`). Null for callers that only have lengths.
  final String? sourceId;

  const CutRequest(this.lengthMm, {this.label, this.reference, this.sourceId});
}

/// Length on the cut list, the ONE rounding rule of the screen, the PDF, the
/// CSV and the shared text: 0.1 mm, a trailing `.0` dropped (`3293`,
/// `1234.5`). The bars used to print whole millimetres and the segment table
/// one decimal, so the same CUT read 1235 in one place and 1234.5 in another.
String formatCutMm(double mm) {
  if (!mm.isFinite) return '—';
  final tenths = (mm * 10).round();
  if (tenths == 0) return '0';
  final s = (tenths / 10).toStringAsFixed(1);
  return s.endsWith('.0') ? s.substring(0, s.length - 2) : s;
}

/// Parts a cut of [cutMm] is split into when it is longer than a stock bar:
/// full bars, then the rest — shortened by the root gap of every extra
/// joining weld, so the spool welded back together is [cutMm] long.
///
/// `n` parts need `n − 1` joining welds, each opening a [joinGapMm] gap:
/// the parts add up to `cutMm − joinGapMm × (n − 1)`. When the gap makes the
/// last part zero or negative (a cut just over a bar), the last two parts
/// share what is left evenly instead of printing an impossible length.
/// A cut that fits the bar comes back whole.
List<double> splitCutLengths(
  double cutMm, {
  required double stockLengthMm,
  double joinGapMm = 0,
}) {
  if (!(stockLengthMm > 0) || cutMm <= stockLengthMm) return [cutMm];
  final gap = joinGapMm.isFinite && joinGapMm > 0 ? joinGapMm : 0.0;
  var n = 2;
  while (cutMm - gap * (n - 1) > n * stockLengthMm) {
    n++;
  }
  final net = cutMm - gap * (n - 1);
  final parts = List<double>.filled(n - 1, stockLengthMm, growable: true)
    ..add(net - (n - 1) * stockLengthMm);
  if (parts.last <= 0) {
    final rest = net - (n - 2) * stockLengthMm;
    parts
      ..removeRange(n - 2, n)
      ..addAll([rest / 2, rest / 2]);
  }
  return parts;
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

  /// Id of the source segment ([CutRequest.sourceId]).
  final String? sourceId;

  /// Every part of the split cut, in part order (just [lengthMm] when not
  /// split) — what the oversize warning prints.
  final List<double> partLengthsMm;

  /// Root gap taken off per joining weld when the cut was split.
  final double joinGapMm;

  const BarPiece({
    required this.lengthMm,
    this.label,
    this.reference,
    this.part = 1,
    this.partCount = 1,
    double? sourceLengthMm,
    this.sourceId,
    List<double>? partLengthsMm,
    this.joinGapMm = 0,
  })  : sourceLengthMm = sourceLengthMm ?? lengthMm,
        partLengthsMm = partLengthsMm ?? const [];

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
///
/// A cut longer than a bar is split by [splitCutLengths]: [joinGapMm] (the
/// project's root gap) comes off the parts once per extra joining weld.
List<BarPlan> nestPiecesToBars({
  required List<CutRequest> cuts,
  required double stockLengthMm,
  required double sawKerfMm,
  double joinGapMm = 0,
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
        sourceId: cut.sourceId,
      ));
      continue;
    }
    final parts = splitCutLengths(
      c,
      stockLengthMm: stockLengthMm,
      joinGapMm: joinGapMm,
    );
    final gap = joinGapMm.isFinite && joinGapMm > 0 ? joinGapMm : 0.0;
    for (var p = 0; p < parts.length; p++) {
      expanded.add(BarPiece(
        lengthMm: parts[p],
        label: cut.label,
        reference: cut.reference,
        part: p + 1,
        partCount: parts.length,
        sourceLengthMm: c,
        sourceId: cut.sourceId,
        partLengthsMm: List<double>.unmodifiable(parts),
        joinGapMm: gap,
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
