/// Lossless finite number text for fields which accept decimals but reject
/// exponent notation. Ordinary input spelling (including .0) is preserved.
String decimalInputText(double value) {
  if (!value.isFinite) {
    throw ArgumentError.value(value, 'value', 'expected a finite number');
  }
  final text = value.toString();
  if (!text.contains('e')) return text;
  final negative = text.startsWith('-');
  final parts = (negative ? text.substring(1) : text).split('e');
  final mantissa = parts[0], exponent = int.parse(parts[1]);
  final point = mantissa.indexOf('.');
  final digits = mantissa.replaceAll('.', '');
  final split = (point < 0 ? mantissa.length : point) + exponent;
  final String expanded;
  if (split <= 0) {
    expanded = '0.${'0' * -split}$digits';
  } else if (split >= digits.length) {
    expanded = '$digits${'0' * (split - digits.length)}';
  } else {
    expanded = '${digits.substring(0, split)}.${digits.substring(split)}';
  }
  return negative ? '-$expanded' : expanded;
}
