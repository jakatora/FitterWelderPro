import 'dart:math' as math;

/// Integer coefficient and decimal scale of a validated finite double.
/// Arithmetic uses its canonical decimal representation, as shown to the user.
(BigInt, int) decimalComponents(double value) {
  if (!value.isFinite) {
    throw ArgumentError.value(value, 'value', 'Must be finite');
  }
  final parts = value.toString().split('e');
  final mantissa = parts.first;
  final dot = mantissa.indexOf('.');
  final scale = (dot < 0 ? 0 : mantissa.length - dot - 1) -
      (parts.length == 1 ? 0 : int.parse(parts[1]));
  return (BigInt.parse(mantissa.replaceAll('.', '')), scale);
}

(BigInt, int) _sumParts(Iterable<double> values) {
  final parts = values.map(decimalComponents).toList();
  final scale = parts.fold<int>(0, (s, p) => math.max(s, p.$2));
  var total = BigInt.zero;
  for (final (coefficient, places) in parts) {
    total += coefficient * BigInt.from(10).pow(scale - places);
  }
  return (total, scale);
}

/// Compare the exact decimal sum with a bound, without rounding either side.
int compareDecimalSum(Iterable<double> values, double bound) =>
    _sumParts([...values, -bound]).$1.sign;

double decimalSum(Iterable<double> values) {
  final (coefficient, scale) = _sumParts(values);
  return double.parse('${coefficient}e${-scale}');
}

double decimalProduct(double a, double b) {
  final (left, leftScale) = decimalComponents(a);
  final (right, rightScale) = decimalComponents(b);
  return double.parse('${left * right}e${-(leftScale + rightScale)}');
}
