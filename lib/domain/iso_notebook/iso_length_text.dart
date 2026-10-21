/// Lossless positive millimetre literal accepted by the native ISO expression
/// parser. Display rounding must never change a stored input dimension.
String isoLengthExpression(double mm) {
  if (!mm.isFinite || mm <= 0) {
    throw ArgumentError.value(mm, 'mm', 'expected a finite positive length');
  }
  final text = mm.toString();
  final parts = text.split('e');
  if (parts.length == 1) {
    return text.endsWith('.0') ? text.substring(0, text.length - 2) : text;
  }
  final mantissa = parts[0], exponent = int.parse(parts[1]);
  final point = mantissa.indexOf('.');
  final digits = mantissa.replaceAll('.', '');
  final split = (point < 0 ? mantissa.length : point) + exponent;
  if (split <= 0) return '0.${'0' * -split}$digits';
  if (split >= digits.length) return '$digits${'0' * (split - digits.length)}';
  return '${digits.substring(0, split)}.${digits.substring(split)}';
}
