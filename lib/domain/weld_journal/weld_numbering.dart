/// Weld numbers: natural ordering, "next number" suggestion and duplicate
/// detection.
///
/// Three bugs the audit found in the journal screen, fixed here as pure,
/// tested functions:
///   * the list was ordered by `weld_no` as TEXT, so "W10" came before "W9";
///   * the suggester stripped every non-digit and glued the digits together
///     ("SP-001-W005" → 1005 → "W-1006");
///   * nothing warned about a number already used in the same project.
///
/// Pure Dart: no Flutter, no I/O.
library;

import 'weld_entry.dart';

final RegExp _chunk = RegExp(r'\d+|\D+');
final RegExp _lastNumber = RegExp(r'(\d+)(\D*)$');

/// Natural comparison of two weld numbers: digit runs compare by value, text
/// runs case-insensitively. "W9" < "W10", "SP-001-W002" < "SP-001-W010".
///
/// Numbers of equal value but different spelling ("W05" / "W5") fall back
/// to a plain string comparison so the order is still total and stable.
int compareWeldNos(String a, String b) {
  final ca = _chunk.allMatches(a.trim()).map((m) => m.group(0)!).toList();
  final cb = _chunk.allMatches(b.trim()).map((m) => m.group(0)!).toList();
  final n = ca.length < cb.length ? ca.length : cb.length;
  for (var i = 0; i < n; i++) {
    final x = ca[i];
    final y = cb[i];
    final xd = _isDigits(x);
    final yd = _isDigits(y);
    int c;
    if (xd && yd) {
      c = _compareDigitRuns(x, y);
    } else if (xd != yd) {
      // Digits sort before text ("1" < "A"), as in a file manager.
      c = xd ? -1 : 1;
    } else {
      c = x.toLowerCase().compareTo(y.toLowerCase());
    }
    if (c != 0) return c;
  }
  final byLength = ca.length.compareTo(cb.length);
  if (byLength != 0) return byLength;
  return a.compareTo(b);
}

bool _isDigits(String s) {
  if (s.isEmpty) return false;
  final c = s.codeUnitAt(0);
  return c >= 0x30 && c <= 0x39;
}

/// Compares two digit runs by value without parsing (any length is fine).
int _compareDigitRuns(String x, String y) {
  final sx = x.replaceFirst(RegExp(r'^0+(?=\d)'), '');
  final sy = y.replaceFirst(RegExp(r'^0+(?=\d)'), '');
  if (sx.length != sy.length) return sx.length.compareTo(sy.length);
  return sx.compareTo(sy);
}

/// Copy of [entries] in natural weld-number order; project breaks ties.
List<WeldEntry> sortWeldEntries(Iterable<WeldEntry> entries) {
  final out = List<WeldEntry>.of(entries);
  out.sort((a, b) {
    final c = compareWeldNos(a.weldNo, b.weldNo);
    if (c != 0) return c;
    return a.projectName.toLowerCase().compareTo(b.projectName.toLowerCase());
  });
  return out;
}

/// Increments the LAST digit run of [weldNo], keeping everything before and
/// after it and the zero padding: "SP-001-W005" → "SP-001-W006",
/// "W-009" → "W-010", "W-999" → "W-1000", "W-005A" → "W-006A".
/// Returns null when there is no digit to increment.
String? incrementWeldNo(String weldNo) {
  final s = weldNo.trim();
  final m = _lastNumber.firstMatch(s);
  if (m == null) return null;
  final digits = m.group(1)!;
  final suffix = m.group(2)!;
  final prefix = s.substring(0, m.start);
  final next = (BigInt.parse(digits) + BigInt.one).toString();
  return '$prefix${next.padLeft(digits.length, '0')}$suffix';
}

String _projectKey(String name) => name.trim().toLowerCase();
String _noKey(String no) => no.trim().toUpperCase();

/// Suggests the next weld number in [projectName].
///
/// Looks at every entry of that project (matched trimmed and
/// case-insensitively; soft-deleted ones included, so a deleted joint's
/// number is not handed out again) and increments the naturally highest
/// number that has a digit. A project with no numbered weld starts at
/// "W-001". The result is never a number already used in the project.
String suggestNextWeldNo(Iterable<WeldEntry> entries,
    {required String projectName}) {
  final key = _projectKey(projectName);
  final inProject =
      entries.where((e) => _projectKey(e.projectName) == key).toList();
  final used = inProject.map((e) => _noKey(e.weldNo)).toSet();

  String? best;
  for (final e in inProject) {
    final no = e.weldNo.trim();
    if (incrementWeldNo(no) == null) continue;
    if (best == null || compareWeldNos(no, best) > 0) best = no;
  }

  var candidate = best == null ? 'W-001' : incrementWeldNo(best)!;
  // Safety net: never suggest a number that is already taken.
  var guard = 0;
  while (used.contains(_noKey(candidate)) && guard++ < 10000) {
    candidate = incrementWeldNo(candidate)!;
  }
  return candidate;
}

/// Live entries of the same project that carry [candidate]'s weld number
/// (trimmed, case-insensitive), excluding [candidate] itself.
///
/// A warning, not a constraint: journals written before this check may
/// already hold duplicates, and a UNIQUE index would make them unreadable.
List<WeldEntry> findDuplicateWeldNos(
    Iterable<WeldEntry> entries, WeldEntry candidate) {
  final no = _noKey(candidate.weldNo);
  if (no.isEmpty) return const [];
  final project = _projectKey(candidate.projectName);
  return entries
      .where((e) =>
          e.id != candidate.id &&
          !e.isDeleted &&
          _projectKey(e.projectName) == project &&
          _noKey(e.weldNo) == no)
      .toList();
}
