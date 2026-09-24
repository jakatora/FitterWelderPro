/// Keyboard, input filter and parser for every numeric field in the app.
///
/// WHY this file exists: `TextInputType.number` opens the iOS number pad, and
/// that pad has NO decimal key and NO comma. A fitter could not type 60,3 /
/// 114,3 / 76,2 at all — the best he could do was `1143`, which is ten times
/// the pipe, or give up. The fix used to be applied field by field (and missed
/// on ~70 fields), so the rule now lives here and a source-level test
/// (`test/widgets/number_field_test.dart`) fails the build when a screen
/// reaches for the bare keypad again.
///
/// Every numeric field uses the same three pieces:
///
/// ```dart
/// TextField(
///   keyboardType: numberKeyboard(),          // decimal pad with , / .
///   inputFormatters: numberInputFormatters(), // digits , .  (and - if signed)
///   ...
/// );
/// final v = parseDecimal(controller.text);    // comma == dot, spaces ignored
/// ```
///
/// Pass `signed: true` only where a negative value is physically meaningful
/// (a temperature); pass `decimal: false` for counts (number of holes,
/// seconds, DN) — those still get the numeric pad, never the bare
/// `TextInputType.number`.
library;

import 'package:flutter/services.dart';

export '../utils/decimal_parse.dart' show parseDecimal;

/// Keyboard for a numeric field.
///
/// On iOS: `decimal: true` → decimal pad (digits + the locale's separator,
/// a comma on a Polish phone); `signed: true` → numbers & punctuation (has
/// the minus key). On Android the numeric keyboard carries `-` `,` `.`.
TextInputType numberKeyboard({bool decimal = true, bool signed = false}) =>
    TextInputType.numberWithOptions(decimal: decimal, signed: signed);

/// One character a numeric field accepts: a digit, either decimal separator
/// (the keyboard shows whichever the phone's locale uses, a paste may bring
/// the other) and — only when [signed] — the minus sign.
RegExp numberInputPattern({bool decimal = true, bool signed = false}) =>
    RegExp('[${_charClass(decimal: decimal, signed: signed)}]');

/// Input formatters matching [numberKeyboard] with the same options — see
/// [NumberInputFormatter] for what they let through.
List<TextInputFormatter> numberInputFormatters({
  bool decimal = true,
  bool signed = false,
}) {
  if (decimal) return signed ? _signedDecimalFormatters : _decimalFormatters;
  return signed ? _signedIntegerFormatters : _integerFormatters;
}

/// Accepts an edit only when every character of the result matches
/// [allowed] (a pattern for ONE character).
///
/// An edit that would bring in any other character is REFUSED as a whole —
/// the field keeps its previous text — instead of having the character cut
/// out. Cutting characters out of a paste turns a different number into a
/// valid-looking one: `1e5` → `15`, `2 1/2` → `212`, `-10` → `10` (the sign
/// lost on a length). On a numeric keypad nothing else can be typed anyway,
/// so in practice this only ever bites a paste — and there it must.
///
/// An edit that does not ADD a forbidden character is always accepted, so a
/// field filled programmatically with something odd can still be corrected
/// with backspace.
class CharsetInputFormatter extends TextInputFormatter {
  final RegExp allowed;

  /// Drop white space instead of refusing it (a copied number often carries
  /// a trailing or a non-breaking space; it never changes its value).
  final bool dropWhitespace;

  CharsetInputFormatter(this.allowed, {this.dropWhitespace = false});

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final value = normalise(newValue);
    final forbidden = _forbiddenCount(value.text);
    if (forbidden == 0) return value;
    return forbidden <= _forbiddenCount(oldValue.text) ? value : oldValue;
  }

  /// Hook for subclasses: map the raw edit before it is checked. The default
  /// only removes white space when [dropWhitespace] is set.
  TextEditingValue normalise(TextEditingValue value) =>
      dropWhitespace ? _withoutWhitespace(value) : value;

  int _forbiddenCount(String text) {
    var n = 0;
    for (final ch in text.split('')) {
      if (!allowed.hasMatch(ch)) n++;
    }
    return n;
  }

  /// White space removed, with the cursor / selection moved left by the
  /// number of spaces removed before it.
  static TextEditingValue _withoutWhitespace(TextEditingValue v) {
    final text = v.text;
    if (!_space.hasMatch(text)) return v;
    int shift(int offset) {
      if (offset < 0) return offset;
      final end = offset.clamp(0, text.length);
      return end - _space.allMatches(text.substring(0, end)).length;
    }

    final sel = v.selection;
    return TextEditingValue(
      text: text.replaceAll(_space, ''),
      selection: sel.copyWith(
        baseOffset: shift(sel.baseOffset),
        extentOffset: shift(sel.extentOffset),
      ),
    );
  }

  static final RegExp _space = RegExp(r'\s');
}

/// The numeric-field formatter: digits, `,` `.` (when [decimal]) and `-`
/// (when [signed]); white space dropped, the Unicode minus `−` read as `-`,
/// anything else refused (see [CharsetInputFormatter]).
class NumberInputFormatter extends CharsetInputFormatter {
  final bool decimal;
  final bool signed;

  NumberInputFormatter({this.decimal = true, this.signed = false})
      : super(numberInputPattern(decimal: decimal, signed: signed),
            dropWhitespace: true);

  @override
  TextEditingValue normalise(TextEditingValue value) {
    final text = value.text.replaceAll('\u2212', '-');
    return super.normalise(
        text == value.text ? value : value.copyWith(text: text));
  }
}

String _charClass({required bool decimal, required bool signed}) =>
    '0-9${decimal ? '.,' : ''}${signed ? r'\-' : ''}';

final List<TextInputFormatter> _decimalFormatters =
    List.unmodifiable([NumberInputFormatter()]);
final List<TextInputFormatter> _signedDecimalFormatters =
    List.unmodifiable([NumberInputFormatter(signed: true)]);
final List<TextInputFormatter> _integerFormatters =
    List.unmodifiable([NumberInputFormatter(decimal: false)]);
final List<TextInputFormatter> _signedIntegerFormatters =
    List.unmodifiable([NumberInputFormatter(decimal: false, signed: true)]);
