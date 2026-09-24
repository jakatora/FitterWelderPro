import '../models/segment.dart';
import 'bar_nesting.dart';

/// Short segment tag the saw operator writes on the cut piece: `S03` for
/// segment 3 (the number the fitter sees as "Segment 3" in the project).
/// Two digits minimum so a printed list sorts and aligns; longer numbers are
/// kept whole (`S123`).
String segmentLabel(Segment s) => 'S${s.seqNo.toString().padLeft(2, '0')}';

/// One diameter + wall group of the cut list, already nested into bars.
class CutListGroup {
  final double diameterMm;
  final double wallMm;

  /// Cut lengths of this group, sorted descending.
  final List<double> cutsMm;

  /// The same cuts with their segment labels, same order as [cutsMm].
  final List<CutRequest> pieces;
  final List<BarPlan> plans;

  const CutListGroup({
    required this.diameterMm,
    required this.wallMm,
    required this.cutsMm,
    required this.plans,
    this.pieces = const [],
  });

  /// First part of every cut that is longer than a stock bar and had to be
  /// split (one entry per such cut, in bar order).
  List<BarPiece> get splitCuts => [
        for (final plan in plans)
          for (final piece in plan.pieces)
            if (piece.isSplit && piece.part == 1) piece,
      ];

  /// Segment label → 1-based numbers of the bars (within this group) that
  /// carry a piece of it. A split cut lists every bar it spans.
  Map<String, List<int>> get barsByLabel {
    final result = <String, List<int>>{};
    for (var i = 0; i < plans.length; i++) {
      for (final piece in plans[i].pieces) {
        final label = piece.label;
        if (label == null) continue;
        final bars = result.putIfAbsent(label, () => <int>[]);
        if (!bars.contains(i + 1)) bars.add(i + 1);
      }
    }
    return result;
  }
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

  /// Every cut longer than a stock bar, across all groups (first part of
  /// each). Each one needs an extra joining weld — see [oversizeCutWarning].
  List<BarPiece> get splitCuts => [for (final g in groups) ...g.splitCuts];
}

/// Groups [segments] by diameter + wall (in order of first appearance) and
/// nests each group into stock bars with [nestPiecesToBars]. Every piece on a
/// bar carries its segment label ([segmentLabel]) and the segment's ISO
/// expression as reference.
///
/// Pure function (no I/O, no network) so the summary can be checked in tests.
CutListSummary summarizeCutList({
  required List<Segment> segments,
  required double stockLengthMm,
  required double sawKerfMm,
}) {
  final order = <String>[];
  final dims = <String, List<double>>{};
  final cutsByKey = <String, List<CutRequest>>{};
  for (final s in segments) {
    final key = '${s.diameterMm}|${s.wallThicknessMm}';
    if (!cutsByKey.containsKey(key)) {
      order.add(key);
      dims[key] = [s.diameterMm, s.wallThicknessMm];
      cutsByKey[key] = <CutRequest>[];
    }
    final iso = s.isoExpr.trim();
    cutsByKey[key]!.add(CutRequest(
      s.cutMm,
      label: segmentLabel(s),
      reference: iso.isEmpty ? null : iso,
    ));
  }

  final groups = <CutListGroup>[];
  for (final key in order) {
    final requests = cutsByKey[key]!;
    // Stable descending sort: equal lengths keep segment order.
    final indices = [for (var i = 0; i < requests.length; i++) i]
      ..sort((a, b) {
        final byLength = requests[b].lengthMm.compareTo(requests[a].lengthMm);
        return byLength != 0 ? byLength : a.compareTo(b);
      });
    final sorted = [for (final i in indices) requests[i]];
    groups.add(CutListGroup(
      diameterMm: dims[key]![0],
      wallMm: dims[key]![1],
      cutsMm: List<double>.unmodifiable([for (final r in sorted) r.lengthMm]),
      pieces: List<CutRequest>.unmodifiable(sorted),
      plans: List<BarPlan>.unmodifiable(nestPiecesToBars(
        cuts: sorted,
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

/// `S01: 3293` — one piece as the saw operator reads it (label, then mm).
/// An unlabelled piece is just its length.
String formatBarPiece(BarPiece piece) {
  final mm = piece.lengthMm.toStringAsFixed(0);
  final tag = piece.tag;
  return tag == null ? mm : '$tag: $mm';
}

/// All pieces of one bar: `S01: 3293 + S02: 2500`.
String formatBarPieces(BarPlan plan) =>
    plan.pieces.map(formatBarPiece).join(' + ');

/// Warning for a cut longer than the stock bar. [piece] is any part of the
/// split cut (its source length and part count are what matter).
///
/// PL: `S03: odcinek 7000 mm dłuższy niż sztanga 6000 mm — dzielony na
/// 2 części; potrzebna dodatkowa spoina łącząca; uwzględnij gap.`
///
/// [withLabel] false drops the leading `S03: ` (for a CSV row that already
/// carries the label in its own column).
String oversizeCutWarning(
  BarPiece piece, {
  required double stockLengthMm,
  required bool english,
  bool withLabel = true,
}) {
  final parts = piece.partCount;
  final welds = parts - 1;
  final length = piece.sourceLengthMm.toStringAsFixed(0);
  final stock = stockLengthMm.toStringAsFixed(0);
  final prefix = withLabel && piece.label != null ? '${piece.label}: ' : '';
  if (english) {
    final weldText = welds == 1
        ? 'an extra joining weld is needed'
        : '$welds extra joining welds are needed';
    return '${prefix}piece $length mm is longer than the $stock mm stock bar '
        '— split into $parts parts; $weldText; allow for the gap.';
  }
  final String weldText;
  if (welds == 1) {
    weldText = 'potrzebna dodatkowa spoina łącząca';
  } else if (_plPaucal(welds)) {
    weldText = 'potrzebne $welds dodatkowe spoiny łączące';
  } else {
    weldText = 'potrzebnych $welds dodatkowych spoin łączących';
  }
  return '${prefix}odcinek $length mm dłuższy niż sztanga $stock mm — '
      'dzielony na $parts części; $weldText; uwzględnij gap.';
}

/// PL "2-4" plural form (2, 3, 4, 22, 23, 24 … but not 12-14).
bool _plPaucal(int n) {
  final mod10 = n % 10;
  final mod100 = n % 100;
  return mod10 >= 2 && mod10 <= 4 && (mod100 < 12 || mod100 > 14);
}

/// Plain-text cut list for the share sheet / clipboard: one line per bar with
/// segment labels, plus a warning line for every cut longer than a bar.
String buildCutListText({
  required String projectName,
  required String materialGroup,
  required double stockLengthMm,
  required double sawKerfMm,
  required CutListSummary summary,
  required bool english,
}) {
  final buf = StringBuffer();
  final stock = stockLengthMm.toStringAsFixed(0);
  final kerf = sawKerfMm.toStringAsFixed(1);
  buf.writeln('CUT LIST — $projectName');
  buf.writeln(english
      ? 'Material: $materialGroup  Stock: $stock mm  Kerf: $kerf mm'
      : 'Materiał: $materialGroup  Sztanga: $stock mm  Rzaz: $kerf mm');
  buf.writeln();

  final splits = summary.splitCuts;
  if (splits.isNotEmpty) {
    for (final piece in splits) {
      final warning = oversizeCutWarning(
        piece,
        stockLengthMm: stockLengthMm,
        english: english,
      );
      buf.writeln('${english ? 'WARNING' : 'UWAGA'}: $warning');
    }
    buf.writeln();
  }

  for (var g = 0; g < summary.groups.length; g++) {
    final group = summary.groups[g];
    if (g > 0) buf.writeln();
    buf.writeln('Ø${group.diameterMm.toStringAsFixed(1)} × '
        '${group.wallMm.toStringAsFixed(1)}:');
    for (var i = 0; i < group.plans.length; i++) {
      final plan = group.plans[i];
      final rest = plan.remainingMm.toStringAsFixed(0);
      buf.writeln(english
          ? '  Bar ${i + 1}: ${formatBarPieces(plan)}  (remaining $rest mm)'
          : '  Sztanga ${i + 1}: ${formatBarPieces(plan)}  (zostaje $rest mm)');
    }
  }
  return buf.toString();
}
