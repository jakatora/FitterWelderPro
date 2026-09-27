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
  var t = text.trim().replaceAll('"', '').replaceAll('″', '').replaceAll('”', '');
  if (t.isEmpty) return null;
  t = t.replaceAll(',', '.');
  // "1-1/2" / "1 1/2"
  final mixed = RegExp(r'^(\d+)[\s-]+(\d+)\s*/\s*(\d+)$').firstMatch(t);
  if (mixed != null) {
    final den = int.parse(mixed.group(3)!);
    if (den == 0) return null;
    return int.parse(mixed.group(1)!) + int.parse(mixed.group(2)!) / den;
  }
  final frac = RegExp(r'^(\d+)\s*/\s*(\d+)$').firstMatch(t);
  if (frac != null) {
    final den = int.parse(frac.group(2)!);
    if (den == 0) return null;
    return int.parse(frac.group(1)!) / den;
  }
  if (RegExp(r'^\d+(\.\d+)?$').hasMatch(t)) return double.parse(t);
  return null;
}

/// True when [query] names the pipe size [dn] / [nps] (empty query = all).
bool sizeQueryMatches(String query, {required int dn, required String nps}) {
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
