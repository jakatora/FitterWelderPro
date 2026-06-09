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
//
// Examples a fitter would type while reading an ISO:
//   3000               -> 3000
//   3000+525-80        -> 3445
//   5*200+150          -> 1150     (5 lengths of 200 mm + 150 mm tail)
//   (1500+200)*2+100   -> 3500
//   1020,5 + 20        -> 1040.5
//
// Throws FormatException with a human readable message; the message is in PL
// because that is the dominant on-site language and the error toast already
// translates the prefix.

double parseIsoExpression(String expr) {
  final cleaned = _normaliseInput(expr)
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
  return v;
}

// P1-03: Normalise smart-quote / unicode noise welders paste from PDFs &
// WhatsApp BEFORE the strict-charset gate below trips on it.
//
//   - U+2212 (minus sign), U+2010..U+2015 (hyphen variants, en-dash, em-dash,
//     horizontal bar) -> ASCII '-'
//   - Vulgar fractions ½ ¼ ¾ -> 0.5 / 0.25 / 0.75 (decimal so the divide-free
//     parser can handle them; the parser explicitly rejects '/')
//   - Zero-width / bidi marks U+200B..U+200F, U+202A..U+202E, U+FEFF -> dropped
//   - Trailing unit suffix 'mm' / 'in' / '"' -> dropped (welders paste
//     "76 mm" or '3"' from drawings)
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

  // Vulgar fractions -> decimal.
  s = s.replaceAll('½', '0.5');
  s = s.replaceAll('¼', '0.25');
  s = s.replaceAll('¾', '0.75');

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

  // Trailing unit suffix: mm / in / " (case-insensitive, optional ASCII space).
  s = s.replaceAll(RegExp(r'\s*(?:mm|in|")\s*$', caseSensitive: false), '');

  return s;
}

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
