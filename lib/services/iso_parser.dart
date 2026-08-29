// ISO expression parser used in segment builder and notebook screens.
//
// Supported syntax (in order of precedence):
//   - parentheses:        (300 + 50)
//   - unary minus:        -150
//   - multiplication:     5*200, 5x200, 5×200 (kept multiplication-only on purpose:
//                         pipes are measured, not divided — division is almost
//                         never used in real drawings and adds parsing pitfalls)
//   - addition/subtract:  3000 + 525 - 80
//   - decimal separator:  1020.5 or 1020,5 (comma normalised to dot)
//   - mixed fractions:    4½ or 4 1/2 (an implicit ADDITION: 4 + 1/2)
//   - unit suffix:        3000 mm / 76" / 76 in — inches are converted, not
//                         dropped (see _splitUnitSuffix)
//
// Examples a fitter would type while reading an ISO:
//   3000               -> 3000
//   3000+525-80        -> 3445
//   5*200+150          -> 1150     (5 lengths of 200 mm + 150 mm tail)
//   (1500+200)*2+100   -> 3500
//   1020,5 + 20        -> 1040.5
//   76"                -> 1930.4   (imperial isometric, converted to mm)
//   4½"                -> 114.3
//
// The result is ALWAYS millimetres — the app's internal base unit — so callers
// stay unit-agnostic no matter what the fitter typed.
//
// Throws FormatException with a human readable message; the message is in PL
// because that is the dominant on-site language and the error toast already
// translates the prefix.

import 'unit_parser.dart';

/// Millimetres per inch, deliberately *borrowed* from [UnitParser] rather than
/// re-declared here.
///
/// WHY: this parser used to delete a trailing inch suffix without converting,
/// so `76"` returned 76 mm instead of 1930.4 mm — a 25.4x under-measurement on
/// every imperial isometric. The one-line fix is to write `* 25.4` right here,
/// but the app would then carry two independent copies of the same conversion
/// factor, and the day somebody corrects one of them the other keeps cutting
/// pipe wrong. [UnitParser] keeps the factor private, so we ask it to convert a
/// known 1 inch instead of duplicating the number.
final double? _mmPerInch = UnitParser.parseToMm('1in');

/// Parses an ISO dimension expression and returns the length in MILLIMETRES.
///
/// The optional trailing unit applies to the whole expression, not just to the
/// last number: `70+6"` is 76 inches (1930.4 mm), not 70 mm + 6 inches.
double parseIsoExpression(String expr) {
  // The unit suffix has to come off before the strict charset gate below
  // (which knows nothing about letters or quotes), but the value it implies
  // must survive all the way to the return — that is the whole bug this
  // function used to have.
  final split = _splitUnitSuffix(_normaliseInput(expr));

  final cleaned = split.body
      .replaceAll(' ', '')
      .replaceAll('\t', '')
      .replaceAll(',', '.')
      .replaceAll('x', '*')
      .replaceAll('X', '*')
      .replaceAll('×', '*')
      .replaceAll('·', '*');

  if (cleaned.isEmpty) throw const FormatException('empty');

  if (RegExp(r'[^0-9+\-*.()]').hasMatch(cleaned)) {
    throw const FormatException('bad chars');
  }

  final p = _Parser(cleaned);
  final v = p.parseExpression();
  if (!p.eof) throw const FormatException('trailing tokens');
  return split.inches ? _inchesToMm(v) : v;
}

/// Trailing unit suffix, case-insensitive, with optional whitespace before it:
/// `mm` (already the base unit) or an inch marker (`"`, `''`, `in`, `inch`,
/// `inches`). The alternatives are ordered longest-first so `76inch` consumes
/// `inch` rather than leaving a stray `ch` behind.
///
/// Feet (`'`) are intentionally NOT accepted here: a single apostrophe is
/// already spoken for as a thousands separator in this parser (`1'234`), and
/// silently reading `5'` as 1524 mm in one screen while another reads it as 5
/// is worse than not supporting it. Feet-inch input goes through
/// [UnitParser.parseToMm] on the dimension sheet.
final RegExp _unitSuffixRe = RegExp(
  r'''\s*(mm|inches|inch|in|"|'')\s*$''',
  caseSensitive: false,
);

/// Splits a normalised expression into its arithmetic [body] and whether that
/// body is expressed in [inches]. No suffix means millimetres, which keeps
/// every existing unit-less call site behaving exactly as before.
({String body, bool inches}) _splitUnitSuffix(String s) {
  final m = _unitSuffixRe.firstMatch(s);
  if (m == null) return (body: s, inches: false);
  final unit = m.group(1)!.toLowerCase();
  return (body: s.substring(0, m.start), inches: unit != 'mm');
}

/// Converts an inch value to millimetres using the app's single conversion
/// factor. Throws FormatException (the type every call site already catches)
/// if that factor could not be obtained, because returning an unconverted
/// number is precisely the 25.4x cutting error this file exists to prevent.
double _inchesToMm(double inches) {
  final factor = _mmPerInch;
  if (factor == null) {
    throw const FormatException('no inch factor');
  }
  return inches * factor;
}

// P1-03: Normalise smart-quote / unicode noise welders paste from PDFs &
// WhatsApp BEFORE the strict-charset gate below trips on it.
//
//   - U+2212 (minus sign), U+2010..U+2015 (hyphen variants, en-dash, em-dash,
//     horizontal bar) -> ASCII '-'
//   - Vulgar fractions ½ ¼ ¾ -> 0.5 / 0.25 / 0.75 (decimal so the divide-free
//     parser can handle them; the parser explicitly rejects '/'). Directly
//     after a number they are an implicit ADDITION and are expanded as
//     '(4+0.5)' — see the mixed-fraction block below.
//   - Zero-width / bidi marks U+200B..U+200F, U+202A..U+202E, U+FEFF -> dropped
//   - A single thousands separator (NBSP U+00A0 / narrow NBSP U+202F /
//     apostrophe ') between a digit and a group of exactly three digits is
//     dropped so "1 234" / "1'234" parses as 1234. Regular ASCII space is
//     already stripped further down; comma is handled there too (treated as
//     decimal, not thousands — consistent with the existing PL behaviour).
String _normaliseInput(String expr) {
  var s = expr;

  // Unicode minus / dashes -> '-'.
  s = s.replaceAll('−', '-');
  s = s.replaceAll(RegExp(r'[‐-―]'), '-');

  // Zero-width / bidi / BOM marks. The whole point is to strip these from
  // user input — they must appear in the regex literal. The lint exists to
  // warn humans, not to break us: silence it here with the per-line ignore.
  // ignore: text_direction_code_point_in_literal
  s = s.replaceAll(RegExp(r'[​-‏‪-‮﻿]'), '');

  // Single thousands separator between digits: NBSP / narrow NBSP / ' .
  s = s.replaceAllMapped(
    RegExp(r"(\d)[  '](\d{3})(?!\d)"),
    (m) => '${m[1]}${m[2]}',
  );

  // Mixed numbers. WHY the brackets: '½' used to be rewritten to the bare
  // string '0.5', so '4½' concatenated into '40.5' — off by a factor of nine
  // on a dimension a fitter reads off an imperial ISO every day. A fraction
  // sitting straight after a number is an implicit '+', and the sum has to be
  // bracketed so a neighbouring '*' or '-' cannot tear it apart ('4½*2' is
  // (4+0.5)*2 = 9, never 4+0.5*2 = 5).
  //
  // The whole part is captured with its decimals so multi-digit and decimal
  // numbers stay intact: '104½' -> '(104+0.5)', not '10(4+0.5)'.
  s = s.replaceAllMapped(_asciiMixedFractionRe, (m) {
    final numerator = double.tryParse(m[2]!);
    final denominator = double.tryParse(m[3]!);
    // Leave a nonsense fraction alone; the '/' then trips the charset gate
    // and the fitter gets an error instead of a silently wrong length.
    if (numerator == null || denominator == null || denominator == 0) {
      return m[0]!;
    }
    return '(${m[1]}+${numerator / denominator})';
  });
  s = s.replaceAllMapped(
    _vulgarMixedFractionRe,
    (m) => '(${m[1]}+${_vulgarFractions[m[2]]})',
  );

  // Fraction with no whole part in front of it: '½' on its own is just 0.5.
  for (final entry in _vulgarFractions.entries) {
    s = s.replaceAll(entry.key, entry.value);
  }

  return s;
}

/// Vulgar fraction glyphs a fitter can type or paste, and their decimal value.
/// Decimal (not `1/2`) because this parser rejects division on purpose.
const Map<String, String> _vulgarFractions = {
  '½': '0.5',
  '¼': '0.25',
  '¾': '0.75',
};

/// A whole number followed by a vulgar fraction: `4½`, `4 ½`, `104½`, `10,5½`.
/// The glyph class is derived from [_vulgarFractions] so the two can never
/// drift apart — a glyph matched here but missing from the map would splice
/// the string `null` into the expression.
final RegExp _vulgarMixedFractionRe =
    RegExp('(\\d+(?:[.,]\\d+)?)\\s*([${_vulgarFractions.keys.join()}])');

/// A whole number followed by an ASCII fraction: `4 1/2`, `4 3/4`.
///
/// Only this MIXED form is accepted. A bare `3/4` is numerically identical to
/// the division `3/4`, and this parser rejects division deliberately (see the
/// file header), so accepting bare fractions would quietly reopen `3000/2`.
/// `4 1/2` cannot be read as arithmetic at all, so there is nothing to confuse
/// it with.
final RegExp _asciiMixedFractionRe = RegExp(r'(\d+(?:[.,]\d+)?)\s+(\d+)/(\d+)');

class _Parser {
  final String s;
  int i = 0;
  _Parser(this.s);

  bool get eof => i >= s.length;

  double parseExpression() {
    double v = _parseTerm();
    while (!eof && (s[i] == '+' || s[i] == '-')) {
      final op = s[i++];
      final rhs = _parseTerm();
      v = (op == '+') ? v + rhs : v - rhs;
    }
    return v;
  }

  double _parseTerm() {
    double v = _parseUnary();
    while (!eof && s[i] == '*') {
      i++;
      v *= _parseUnary();
    }
    return v;
  }

  double _parseUnary() {
    if (!eof && (s[i] == '+' || s[i] == '-')) {
      final op = s[i++];
      final v = _parseUnary();
      return op == '-' ? -v : v;
    }
    return _parseAtom();
  }

  double _parseAtom() {
    if (eof) throw const FormatException('unexpected end');
    if (s[i] == '(') {
      i++;
      final v = parseExpression();
      if (eof || s[i] != ')') throw const FormatException('missing )');
      i++;
      return v;
    }
    final start = i;
    while (!eof && (RegExp(r'[0-9.]').hasMatch(s[i]))) {
      i++;
    }
    if (start == i) throw const FormatException('expected number');
    final lex = s.substring(start, i);
    final parsed = double.tryParse(lex);
    if (parsed == null) throw FormatException('bad number "$lex"');
    return parsed;
  }
}
