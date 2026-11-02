// Search-box matching for pipe-size tables (elbow take-outs, schedules…).
//
// A fitter types the size the way it is written on the ISO or said on site:
// `DN50`, `DN 50`, `50`, `2"`, `2 cale`, `2 in`, `1 1/2"`, `1-1/2"`, `1,5"`.
// Plain numbers keep the old substring behaviour (typing `5` → DN50, DN500…);
// anything with an inch marker is compared to the NPS value exactly, so `2"`
// finds NPS 2 only (not 1/2 or 1 1/2).

/// Inch markers: " '' ″ ” in inch inches cal cala cale cali.
final RegExp _inchSuffix = RegExp(
  r'''^(.*?)\s*(?:"|''|″|”|in\.?|inch(?:es)?|cal[aei]?)$''',
);

/// NPS text ("1 1/2", "3/4", "2", "1-1/2", "1.5", "1,5", `2"`) → inches, or
/// null when it is not a size.
double? parseNpsInches(String text) {
  // Pasted malformed values should never crash live table filtering.
  if (text.length > 128) return null;
  var t = text.trim().replaceAll('"', '').replaceAll('″', '').replaceAll('”', '');
  if (t.isEmpty) return null;
  t = t.replaceAll(',', '.');
  // "1-1/2" / "1 1/2"
  final mixed = RegExp(r'^(\d+)[\s-]+(\d+)\s*/\s*(\d+)$').firstMatch(t);
  if (mixed != null) {
    final whole = int.tryParse(mixed.group(1)!);
    final numerator = int.tryParse(mixed.group(2)!);
    final den = int.tryParse(mixed.group(3)!);
    if (whole == null || numerator == null || den == null || den == 0) return null;
    return whole + numerator / den;
  }
  final frac = RegExp(r'^(\d+)\s*/\s*(\d+)$').firstMatch(t);
  if (frac != null) {
    final numerator = int.tryParse(frac.group(1)!);
    final den = int.tryParse(frac.group(2)!);
    if (numerator == null || den == null || den == 0) return null;
    return numerator / den;
  }
  if (RegExp(r'^\d+(\.\d+)?$').hasMatch(t)) {
    final value = double.tryParse(t);
    return value != null && value.isFinite ? value : null;
  }
  return null;
}

/// True when [query] names the pipe size [dn] / [nps] (empty query = all).
bool sizeQueryMatches(String query, {required int dn, required String nps}) {
  if (query.length > 256) return false;
  final q = query.trim().toLowerCase();
  if (q.isEmpty) return true;

  // Inch notation → exact NPS comparison.
  final inch = _inchSuffix.firstMatch(q);
  if (inch != null) {
    final want = parseNpsInches(inch.group(1)!);
    final have = parseNpsInches(nps);
    if (want == null || have == null) return false;
    return (want - have).abs() < 1e-6;
  }

  // "DN 50" / "dn50" → substring on DN (live typing: DN5 → DN50, DN500).
  final compact = q.replaceAll(RegExp(r'\s+'), '');
  if (compact.startsWith('dn')) {
    final digits = compact.substring(2);
    if (digits.isEmpty) return true;
    return '$dn'.startsWith(digits);
  }

  // Plain text: DN substring or NPS text ("1 1/2", "3/4").
  final npsText = nps.toLowerCase().replaceAll('"', '');
  return '$dn'.contains(q) || npsText.contains(q.replaceAll('"', ''));
}
