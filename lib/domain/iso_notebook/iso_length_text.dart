import '../../utils/decimal_input_text.dart';

/// Lossless positive millimetre literal accepted by the native ISO expression
/// parser. Display rounding must never change a stored input dimension.
String isoLengthExpression(double mm) {
  if (!mm.isFinite || mm <= 0) {
    throw ArgumentError.value(mm, 'mm', 'expected a finite positive length');
  }
  final text = decimalInputText(mm);
  return text.endsWith('.0') ? text.substring(0, text.length - 2) : text;
}
