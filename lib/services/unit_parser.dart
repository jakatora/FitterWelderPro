/// Centralised length-input parser.
///
/// Pipefitters / welders type dimensions in mixed units: plain millimetres,
/// straight inches (`59"`, `2.5 in`), or imperial feet-inch combos
/// (`4' 11"`, `4 feet 11.5 inches`). Both the PrefabEngine and the dimension
/// sheet UI need to interpret these the same way, so the parsing rules live
/// here instead of being duplicated.
///
/// Internal base unit across the app is millimetres — every successful parse
/// returns mm. Conversions use exact factors: 1 in = 25.4 mm, 1 ft = 12 in.
library;

class UnitParser {
  static const double _mmPerInch = 25.4;
  static const double _inchesPerFoot = 12.0;

  /// Parses a length expression into millimetres, or returns null if the
  /// input cannot be understood. Whitespace and case are ignored.
  static double? parseToMm(String text) {
    final raw = text.trim();
    if (raw.isEmpty) return null;

    final normalised = raw.toLowerCase();

    // Try feet-inch combo first — it's the most specific shape and the inch
    // / millimetre branches would otherwise greedily match the leading feet
    // number.
    final feetInch = _tryFeetInch(normalised);
    if (feetInch != null) return feetInch;

    final inches = _tryInches(normalised);
    if (inches != null) return inches;

    return _tryMillimetres(normalised);
  }

  /// Returns null when the input is a valid length, otherwise a short
  /// human-readable reason suitable for `TextField.errorText`.
  static String? validate(String text) {
    if (text.trim().isEmpty) return 'missing value';
    return parseToMm(text) == null ? 'invalid number' : null;
  }

  // --- internal helpers ---------------------------------------------------

  static final RegExp _feetInchRe = RegExp(
    r'''^\s*(\d+(?:\.\d+)?)\s*(?:'|ft|feet|foot)\s*(?:(\d+(?:\.\d+)?)\s*(?:"|in|inch|inches|''))?\s*$''',
  );

  static final RegExp _inchesRe = RegExp(
    r'''^\s*(\d+(?:\.\d+)?)\s*(?:"|in|inch|inches|'')\s*$''',
  );

  static final RegExp _mmRe = RegExp(
    r'^\s*(\d+(?:\.\d+)?)\s*(?:mm|millimetre|millimetres|millimeter|millimeters)?\s*$',
  );

  static double? _tryFeetInch(String s) {
    final m = _feetInchRe.firstMatch(s);
    if (m == null) return null;
    final feet = double.tryParse(m.group(1)!);
    if (feet == null) return null;
    double inches = 0;
    if (m.group(2) != null) {
      final parsed = double.tryParse(m.group(2)!);
      if (parsed == null) return null;
      inches = parsed;
    }
    return (feet * _inchesPerFoot + inches) * _mmPerInch;
  }

  static double? _tryInches(String s) {
    final m = _inchesRe.firstMatch(s);
    if (m == null) return null;
    final inches = double.tryParse(m.group(1)!);
    if (inches == null) return null;
    return inches * _mmPerInch;
  }

  static double? _tryMillimetres(String s) {
    final m = _mmRe.firstMatch(s);
    if (m == null) return null;
    return double.tryParse(m.group(1)!);
  }
}
