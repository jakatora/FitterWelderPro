import '../utils/decimal_input_text.dart';
import '../models/project.dart';
import '../models/segment.dart';
import 'bar_nesting.dart';

/// Short segment tag the saw operator writes on the cut piece: `S03` for
/// segment 3 (the number the fitter sees as "Segment 3" in the project).
/// Two digits minimum so a printed list sorts and aligns; longer numbers are
/// kept whole (`S123`).
///
/// A segment with a piece mark from the drawing (schema v22, `SP02-03`)
/// carries it next to the number — `S03 SP02-03` — so the piece off the saw
/// can be found on the isometric by QC and by the foreman. The `S03` stays
/// in front: it is unique in the project, a typed mark need not be.
String segmentLabel(Segment s) {
  final tag = 'S${s.seqNo.toString().padLeft(2, '0')}';
  final mark = s.label;
  return mark == null ? tag : '$tag $mark';
}

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
///
/// Segments whose Ø and wall differ only by floating-point noise
/// (114.3 / 114.30000000000001) are one pipe: grouped at 0.01 mm, well below
/// the 0.1 mm between the closest real ODs (EN 76.1 / sanitary 76.2).
///
/// [joinGapMm] — the project's root gap — is taken off a cut that has to be
/// split over several bars, once per extra joining weld ([splitCutLengths]).
CutListSummary summarizeCutList({
  required List<Segment> segments,
  required double stockLengthMm,
  required double sawKerfMm,
  double joinGapMm = 0,
}) {
  final order = <String>[];
  final dims = <String, List<double>>{};
  final cutsByKey = <String, List<CutRequest>>{};
  for (final s in segments) {
    final key = cutGroupKey(s.diameterMm, s.wallThicknessMm);
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
      sourceId: s.id,
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
        joinGapMm: joinGapMm,
      )),
    ));
  }

  return CutListSummary(
    groups: List<CutListGroup>.unmodifiable(groups),
    segmentCount: segments.length,
    stockLengthMm: stockLengthMm,
  );
}

/// Group key of a Ø × wall on the cut list, at 0.01 mm — see
/// [summarizeCutList]. Also how the PDF finds a segment's group again.
String cutGroupKey(double diameterMm, double wallMm) =>
    '${diameterMm.toStringAsFixed(2)}|${wallMm.toStringAsFixed(2)}';

/// `S01: 3293` — one piece as the saw operator reads it (label, then mm,
/// rounded by [formatCutMm]). An unlabelled piece is just its length.
String formatBarPiece(BarPiece piece) {
  final mm = formatCutMm(piece.lengthMm);
  final tag = piece.tag;
  return tag == null ? mm : '$tag: $mm';
}

/// All pieces of one bar: `S01: 3293 + S02: 2500`.
String formatBarPieces(BarPlan plan) =>
    plan.pieces.map(formatBarPiece).join(' + ');

/// Warning for a cut longer than the stock bar, with the RESULT of the split
/// — the parts to cut, already shortened by the joining welds' gap — rather
/// than an instruction to work it out. [piece] is any part of the split cut.
///
/// PL: `S03: odcinek 7000 mm dłuższy niż sztanga 6000 mm — dzielony na
/// 2 części: 6000 + 997 mm (odjęto gap 3 mm dodatkowej spoiny łączącej).`
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
  final length = formatCutMm(piece.sourceLengthMm);
  final stock = formatCutMm(stockLengthMm);
  final prefix = withLabel && piece.label != null ? '${piece.label}: ' : '';
  final lengths = piece.partLengthsMm.length == parts
      ? '${piece.partLengthsMm.map(formatCutMm).join(' + ')} mm'
      : null;
  final gap = formatCutMm(piece.joinGapMm);
  final hasGap = piece.joinGapMm > 0;
  if (english) {
    final split = lengths == null ? '$parts parts' : '$parts parts: $lengths';
    final String tail;
    if (hasGap) {
      tail = welds == 1
          ? '($gap mm gap of the extra joining weld taken off).'
          : '($gap mm gap × $welds extra joining welds taken off).';
    } else {
      final weldText = welds == 1
          ? 'an extra joining weld'
          : '$welds extra joining welds';
      tail = '$weldText (project gap 0 mm — nothing taken off).';
    }
    return '${prefix}piece $length mm is longer than the $stock mm stock bar '
        '— split into $split${hasGap ? ' ' : '; '}$tail';
  }
  final split = lengths == null ? '$parts części' : '$parts części: $lengths';
  final String tail;
  if (hasGap) {
    if (welds == 1) {
      tail = '(odjęto gap $gap mm dodatkowej spoiny łączącej).';
    } else if (_plPaucal(welds)) {
      tail = '(odjęto gap $gap mm × $welds dodatkowe spoiny łączące).';
    } else {
      tail = '(odjęto gap $gap mm × $welds dodatkowych spoin łączących).';
    }
  } else {
    final String weldText;
    if (welds == 1) {
      weldText = 'dodatkowa spoina łącząca';
    } else if (_plPaucal(welds)) {
      weldText = '$welds dodatkowe spoiny łączące';
    } else {
      weldText = '$welds dodatkowych spoin łączących';
    }
    tail = '$weldText (gap projektu 0 mm — nic nie odjęto).';
  }
  return '${prefix}odcinek $length mm dłuższy niż sztanga $stock mm — '
      'dzielony na $split${hasGap ? ' ' : '; '}$tail';
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
  ProjectIdentity? identity,
}) {
  final buf = StringBuffer();
  final stock = stockLengthMm.toStringAsFixed(0);
  final kerf = sawKerfMm.toStringAsFixed(1);
  buf.writeln('CUT LIST — $projectName');
  // Line / ISO / revision / client / class under the title, so the list
  // sent to the storeroom or the foreman names the job it belongs to.
  if (identity != null && identity.isNotEmpty) {
    buf.writeln(identity.summary(english: english));
  }
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
    buf.writeln('Ø${decimalInputText(group.diameterMm)} × '
        '${decimalInputText(group.wallMm)}:');
    for (var i = 0; i < group.plans.length; i++) {
      final plan = group.plans[i];
      final rest = formatCutMm(plan.remainingMm);
      buf.writeln(english
          ? '  Bar ${i + 1}: ${formatBarPieces(plan)}  (remaining $rest mm)'
          : '  Sztanga ${i + 1}: ${formatBarPieces(plan)}  (zostaje $rest mm)');
    }
  }
  return buf.toString();
}
