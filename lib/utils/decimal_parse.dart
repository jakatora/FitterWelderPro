/// The one parser for a plain number a fitter or welder types into the app.
///
/// WHY one function: the same `double.tryParse(text.replaceAll(',', '.'))`
/// used to be copied into every calculator screen, and the copies had already
/// drifted — some trimmed, some did not, some forgot the comma entirely. A
/// Polish keyboard types `60,3`, an English one `60.3`, and a value pasted from
/// a spreadsheet may carry a stray (non-breaking) space. They all mean the same
/// pipe, so they all go through here.
///
/// Rules:
///   * a comma is a decimal separator, exactly like a dot (`114,3` == `114.3`);
///   * white space anywhere is ignored (`1 234,5` == `1234.5`), including the
///     non-breaking spaces a copied value brings along;
///   * the Unicode minus sign `−` (U+2212) reads as `-`;
///   * empty input, anything that is not a number, and non-finite values
///     (`NaN`, `Infinity`) give `null` — never a silent 0.
///
/// Pure Dart on purpose (no Flutter import), so data and service code can use
/// it too. Screens get it through `widgets/number_field.dart`.
library;

double? parseDecimal(String? text) {
  if (text == null) return null;
  final cleaned = text
      .replaceAll(RegExp(r'\s'), '')
      .replaceAll('\u2212', '-')
      .replaceAll(',', '.');
  if (cleaned.isEmpty) return null;
  final value = double.tryParse(cleaned);
  if (value == null || !value.isFinite) return null;
  return value;
}
