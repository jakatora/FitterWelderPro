/// Big operator keys for an ISO-dimension field (`3000+525-80`, `5×200`,
/// `(1500+200)×2`, `76"`).
///
/// WHY: the ISO field used to open the full QWERTY keyboard, because the
/// expression needs `+ - × ( )` — and a gloved fitter then had to hunt for
/// digits on the letters layout, or flip between two keyboard pages for every
/// `+`. The iOS decimal pad is the right keyboard for the numbers, but it has
/// none of the operators. So the field takes the decimal pad and this bar puts
/// the operators under it as large (min. 48 dp) keys that insert at the cursor.
///
/// What the keys insert is exactly what `services/iso_parser.dart` reads:
///   * `+` and `-` (ASCII minus — the parser's canonical form; the key face
///     shows the typographic `−`);
///   * `×` for multiplication — the sign printed on isometrics, accepted by
///     the parser next to `*` / `x` / `·`, and it survives the CSV (UTF-8 with
///     BOM) and PDF (Roboto) exports unchanged;
///   * `(` `)`;
///   * `"` — the inch suffix (`76"` = 1930.4 mm). Feet (`'`) are deliberately
///     NOT offered: the ISO parser reads a single apostrophe as a thousands
///     separator and never as feet (see `_unitSuffixRe` there);
///   * `⌫` deletes the selection or the character before the cursor.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../i18n/app_language.dart';
import 'number_field.dart' show CharsetInputFormatter;

/// Characters an ISO expression may contain — everything
/// `parseIsoExpression` understands: digits, both decimal separators,
/// `+ - * x X × ·`, brackets, the inch marks `"` / `''`, the apostrophe
/// thousands separator, unit letters (`mm`, `in`, `inch`), spaces, the
/// vulgar fractions `½ ¼ ¾` and `/` of a mixed fraction (`4 1/2"`), the
/// Unicode minus / dashes a paste from a PDF brings along, and the
/// (narrow) non-breaking space used as a thousands separator.
///
/// An edit bringing in anything else (emoji, line breaks, `=`, `;`…) is
/// refused as a whole rather than trimmed: trimming `3000;525` would leave
/// the valid-looking — and wrong — `3000525` (see [CharsetInputFormatter]).
final RegExp isoExpressionInputPattern = RegExp(
  '[0-9.,+*xX×·()"\' a-zA-Z½¼¾/\\-\u2212\u2010-\u2015\u00A0\u202F]',
);

final List<TextInputFormatter> _isoExpressionFormatters = List.unmodifiable(
  [CharsetInputFormatter(isoExpressionInputPattern)],
);

/// Input formatters for an ISO-expression field (see [isoExpressionInputPattern]).
List<TextInputFormatter> isoExpressionInputFormatters() =>
    _isoExpressionFormatters;

/// One key of [IsoExpressionKeyBar].
class IsoExpressionKey {
  /// What the key face shows.
  final String label;

  /// What the key inserts at the cursor; `null` = backspace.
  final String? insert;

  final String semanticsPl;
  final String semanticsEn;

  const IsoExpressionKey(
    this.label,
    this.insert, {
    required this.semanticsPl,
    required this.semanticsEn,
  });

  bool get isBackspace => insert == null;
}

/// The keys, in reading order of the 4-column grid:
///
/// ```
///   +   −   ×   ⌫
///   (   )   "
/// ```
///
/// The two operators used on nearly every drawing sit top-left; backspace is
/// top-right, where every phone keyboard has it.
const List<IsoExpressionKey> kIsoExpressionKeys = [
  IsoExpressionKey('+', '+', semanticsPl: 'plus', semanticsEn: 'plus'),
  IsoExpressionKey('−', '-', semanticsPl: 'minus', semanticsEn: 'minus'),
  IsoExpressionKey('×', '×', semanticsPl: 'razy', semanticsEn: 'times'),
  IsoExpressionKey('⌫', null,
      semanticsPl: 'usuń znak', semanticsEn: 'delete character'),
  IsoExpressionKey('(', '(',
      semanticsPl: 'nawias otwierający', semanticsEn: 'open bracket'),
  IsoExpressionKey(')', ')',
      semanticsPl: 'nawias zamykający', semanticsEn: 'close bracket'),
  IsoExpressionKey('"', '"', semanticsPl: 'cale', semanticsEn: 'inches'),
];

/// Selection of [value] as an ordered, clamped `(start, end)`; a field that
/// has never had a cursor (selection -1) works at the end of its text.
(int, int) _range(TextEditingValue value) {
  final length = value.text.length;
  final sel = value.selection;
  var start = sel.isValid ? sel.start : length;
  var end = sel.isValid ? sel.end : length;
  if (start > end) {
    final t = start;
    start = end;
    end = t;
  }
  return (start.clamp(0, length), end.clamp(0, length));
}

/// Inserts [text] at the cursor of [controller] (replacing a selection), or
/// appends it when the field has no cursor yet. Returns the new text.
String insertAtCursor(TextEditingController controller, String text) {
  final value = controller.value;
  final (start, end) = _range(value);
  final newText = value.text.replaceRange(start, end, text);
  controller.value = TextEditingValue(
    text: newText,
    selection: TextSelection.collapsed(offset: start + text.length),
  );
  return newText;
}

/// Deletes the selection, or the one character (grapheme) before the cursor —
/// the end of the text when the field has no cursor yet. Returns the new text.
String backspaceAtCursor(TextEditingController controller) {
  final value = controller.value;
  var (start, end) = _range(value);
  if (start == end) {
    if (start == 0) return value.text;
    final before = value.text.substring(0, start).characters;
    start -= before.last.length;
  }
  final newText = value.text.replaceRange(start, end, '');
  controller.value = TextEditingValue(
    text: newText,
    selection: TextSelection.collapsed(offset: start),
  );
  return newText;
}

/// A grid of large operator keys placed directly under an ISO-expression
/// field. Each tap edits [controller] at its cursor and then calls
/// [onChanged] with the new text — a programmatic edit does not fire the
/// field's own `onChanged`, so the live CUT preview needs this callback.
///
/// Built from plain Rows of Expanded keys (no LayoutBuilder) so it also lays
/// out inside an AlertDialog, which sizes its content by intrinsic width.
class IsoExpressionKeyBar extends StatelessWidget {
  final TextEditingController controller;
  final ValueChanged<String>? onChanged;
  final List<IsoExpressionKey> keys;
  final int columns;

  /// Minimum key size — the gloved-hands target from the Material / Apple
  /// guidelines (48 dp).
  static const double minKeySize = 48;

  /// Actual key height: a little over the minimum for thick gloves.
  static const double keyHeight = 52;

  static const double _gap = 6;

  const IsoExpressionKeyBar({
    super.key,
    required this.controller,
    this.onChanged,
    this.keys = kIsoExpressionKeys,
    this.columns = 4,
  });

  void _press(IsoExpressionKey key) {
    HapticFeedback.selectionClick();
    final text = key.isBackspace
        ? backspaceAtCursor(controller)
        : insertAtCursor(controller, key.insert!);
    onChanged?.call(text);
  }

  Widget _key(BuildContext context, IsoExpressionKey key) {
    final cs = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      label: context.tr(pl: key.semanticsPl, en: key.semanticsEn),
      excludeSemantics: true,
      child: SizedBox(
        key: ValueKey('iso-key-${key.label}'),
        height: keyHeight,
        child: OutlinedButton(
          onPressed: () => _press(key),
          style: OutlinedButton.styleFrom(
            minimumSize: const Size(minKeySize, minKeySize),
            padding: EdgeInsets.zero,
            foregroundColor: cs.onSurface,
            side: BorderSide(color: cs.outline),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
          child: key.isBackspace
              ? const Icon(Icons.backspace_outlined, size: 24)
              : Text(
                  key.label,
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w700,
                  ),
                ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[];
    for (var i = 0; i < keys.length; i += columns) {
      final cells = <Widget>[];
      for (var c = 0; c < columns; c++) {
        if (c > 0) cells.add(const SizedBox(width: _gap));
        final k = i + c;
        // Pad a short last row with empty cells so the keys stay on the grid.
        cells.add(Expanded(
          child: k < keys.length ? _key(context, keys[k]) : const SizedBox(),
        ));
      }
      if (rows.isNotEmpty) rows.add(const SizedBox(height: _gap));
      rows.add(Row(children: cells));
    }
    // A tap on the bar counts as a tap inside the text field, so the field
    // keeps focus (and the keyboard stays up) while operators are added.
    return TextFieldTapRegion(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: rows,
      ),
    );
  }
}
