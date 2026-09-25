import '../models/segment.dart';

final RegExp _lastNumber = RegExp(r'(\d+)(\D*)$');

/// The piece mark after [previous]: its last group of digits plus one, zero
/// padding kept — `SP02-03` → `SP02-04`, `S9` → `S10`, `12` → `13`,
/// `L-100/7A` → `L-100/8A`. Null when [previous] has no digits to count on
/// (nothing is invented).
String? nextPieceLabel(String? previous) {
  final s = previous?.trim() ?? '';
  final m = _lastNumber.firstMatch(s);
  if (m == null) return null;
  final digits = m.group(1)!;
  final suffix = m.group(2)!;
  final prefix = s.substring(0, m.start);
  final next = (BigInt.parse(digits) + BigInt.one).toString();
  return '$prefix${next.padLeft(digits.length, '0')}$suffix';
}

/// Suggestion for the mark of the next segment of a project: the mark after
/// the last labelled segment (highest seq_no), skipping any mark already used
/// in the project. Null when no segment has a mark yet, or the last mark has
/// no number to continue — then the fitter types the first one himself.
String? suggestNextSegmentLabel(Iterable<Segment> segments) {
  final ordered = segments.toList()..sort((a, b) => a.seqNo.compareTo(b.seqNo));
  String? last;
  for (final s in ordered.reversed) {
    if (s.label != null) {
      last = s.label;
      break;
    }
  }
  if (last == null) return null;
  final taken = {
    for (final s in ordered)
      if (s.label != null) s.label!.toUpperCase(),
  };
  var candidate = nextPieceLabel(last);
  for (var i = 0; candidate != null && i < 1000; i++) {
    if (!taken.contains(candidate.toUpperCase())) return candidate;
    candidate = nextPieceLabel(candidate);
  }
  return null;
}
