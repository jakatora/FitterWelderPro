import '../models/segment.dart';
import 'bar_nesting.dart';

/// One diameter + wall group of the cut list, already nested into bars.
class CutListGroup {
  final double diameterMm;
  final double wallMm;

  /// Cut lengths of this group, sorted descending.
  final List<double> cutsMm;
  final List<BarPlan> plans;

  const CutListGroup({
    required this.diameterMm,
    required this.wallMm,
    required this.cutsMm,
    required this.plans,
  });
}

/// Totals shown in the cut-list summary (PDF header block and screen boxes).
class CutListSummary {
  final List<CutListGroup> groups;
  final int segmentCount;
  final double stockLengthMm;

  const CutListSummary({
    required this.groups,
    required this.segmentCount,
    required this.stockLengthMm,
  });

  int get totalBars => groups.fold<int>(0, (s, g) => s + g.plans.length);

  /// Net pipe length = sum of all pieces laid out on bars (same rule as the
  /// summary screen; non-positive cuts are ignored by the nesting).
  double get totalNetMm => groups.fold<double>(
        0,
        (s, g) => s +
            g.plans.fold<double>(
              0,
              (a, b) => a + b.piecesMm.fold<double>(0, (x, v) => x + v),
            ),
      );

  double get totalWasteMm => groups.fold<double>(
        0,
        (s, g) => s + g.plans.fold<double>(0, (a, b) => a + b.remainingMm),
      );

  /// Waste as a percentage of all stock bars used; 0 when no bars.
  double get wastePct {
    final material = totalBars * stockLengthMm;
    return material > 0 ? totalWasteMm / material * 100 : 0.0;
  }
}

/// Groups [segments] by diameter + wall (in order of first appearance) and
/// nests each group into stock bars with [nestCutsToBars].
///
/// Pure function (no I/O, no network) so the summary can be checked in tests.
CutListSummary summarizeCutList({
  required List<Segment> segments,
  required double stockLengthMm,
  required double sawKerfMm,
}) {
  final order = <String>[];
  final dims = <String, List<double>>{};
  final cutsByKey = <String, List<double>>{};
  for (final s in segments) {
    final key = '${s.diameterMm}|${s.wallThicknessMm}';
    if (!cutsByKey.containsKey(key)) {
      order.add(key);
      dims[key] = [s.diameterMm, s.wallThicknessMm];
      cutsByKey[key] = <double>[];
    }
    cutsByKey[key]!.add(s.cutMm);
  }

  final groups = <CutListGroup>[];
  for (final key in order) {
    final sorted = List<double>.from(cutsByKey[key]!)
      ..sort((a, b) => b.compareTo(a));
    groups.add(CutListGroup(
      diameterMm: dims[key]![0],
      wallMm: dims[key]![1],
      cutsMm: List<double>.unmodifiable(sorted),
      plans: List<BarPlan>.unmodifiable(nestCutsToBars(
        cutsMm: sorted,
        stockLengthMm: stockLengthMm,
        sawKerfMm: sawKerfMm,
      )),
    ));
  }

  return CutListSummary(
    groups: List<CutListGroup>.unmodifiable(groups),
    segmentCount: segments.length,
    stockLengthMm: stockLengthMm,
  );
}
