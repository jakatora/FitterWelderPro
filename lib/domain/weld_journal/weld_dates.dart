/// Date handling for the weld journal.
///
/// Dates are stored as `YYYY-MM-DD` text (they sort, filter and export as
/// plain strings). The editor used to accept anything, so "2026-0" or
/// "30.02" reached the database and later fell out of the PDF date range and
/// the date filter. [normalizeWeldDate] is the gate the editor now uses.
///
/// Pure Dart: no Flutter, no I/O.
library;

final RegExp _iso = RegExp(r'^(\d{4})-(\d{1,2})-(\d{1,2})$');
final RegExp _pl = RegExp(r'^(\d{1,2})\.(\d{1,2})\.(\d{4})$');
final RegExp _strictIso = RegExp(r'^\d{4}-\d{2}-\d{2}$');

/// Normalises what a welder typed into `YYYY-MM-DD`.
///
/// Accepts ISO (`2026-9-4` is padded) and the Polish `DD.MM.RRRR`. Returns
/// `''` for an empty field (the date is optional) and null for anything that
/// is not a real calendar date — the caller must then refuse to save.
///
/// The year must lie in [kMinWeldYear] .. (today's year + 1): `2062-09-01`
/// or `0026-09-01` are typos, not dates — such a weld used to drop silently
/// out of the continuity count and stretch the PDF "date range". A date in
/// the future but within that window is accepted; [isFutureWeldDate] lets
/// the caller warn about it.
String? normalizeWeldDate(String raw, {DateTime? today}) {
  final dt = _parseDate(raw);
  if (dt == null) return raw.trim().isEmpty ? '' : null;
  final now = today ?? DateTime.now();
  if (dt.year < kMinWeldYear || dt.year > now.year + 1) return null;
  return isoDate(dt);
}

/// The calendar date in [raw] (ISO or `DD.MM.RRRR`), or null.
DateTime? _parseDate(String raw) {
  final s = raw.trim();
  if (s.isEmpty) return null;
  int y, m, d;
  final iso = _iso.firstMatch(s);
  final pl = _pl.firstMatch(s);
  if (iso != null) {
    y = int.parse(iso.group(1)!);
    m = int.parse(iso.group(2)!);
    d = int.parse(iso.group(3)!);
  } else if (pl != null) {
    d = int.parse(pl.group(1)!);
    m = int.parse(pl.group(2)!);
    y = int.parse(pl.group(3)!);
  } else {
    return null;
  }
  if (m < 1 || m > 12 || d < 1 || d > 31) return null;
  final dt = DateTime(y, m, d);
  // DateTime rolls 30.02 over into March; a real date survives unchanged.
  if (dt.year != y || dt.month != m || dt.day != d) return null;
  return dt;
}

/// Earliest year the journal accepts.
const int kMinWeldYear = 2000;

/// `YYYY-MM-DD` [iso] later than [today] (date only).
bool isFutureWeldDate(String iso, {DateTime? today}) {
  if (!_strictIso.hasMatch(iso)) return false;
  final now = today ?? DateTime.now();
  return iso.compareTo(isoDate(now)) > 0;
}

/// True for a complete, existing `YYYY-MM-DD` date.
bool isIsoWeldDate(String s) {
  if (!_strictIso.hasMatch(s)) return false;
  final dt = _parseDate(s);
  return dt != null && isoDate(dt) == s;
}

/// `YYYY-MM-DD` of [d].
String isoDate(DateTime d) => '${d.year.toString().padLeft(4, '0')}-'
    '${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';
