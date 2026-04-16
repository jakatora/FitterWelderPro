// Parses ISO expression allowing only numbers, spaces, comma/dot and +/- operators.
// Examples:
// - "3000" -> 3000
// - "3000+525-80" -> 3445
// - " 1000,5 + 20 " -> 1020.5
//
// NOTE: No parentheses in MVP (keeps it safe and predictable).

double parseIsoExpression(String expr) {
  final s = expr.replaceAll(' ', '').replaceAll(',', '.');
  if (s.isEmpty) throw const FormatException('empty');

  // Validate allowed characters
  if (RegExp(r'[^0-9\+\-\.]').hasMatch(s)) {
    throw const FormatException('bad chars');
  }

  // Normalize: if starts with + or -, keep it; else add +
  String normalized = s;
  if (!normalized.startsWith('+') && !normalized.startsWith('-')) {
    normalized = '+$normalized';
  }

  // Tokenize by sign
  final reg = RegExp(r'([\+\-])([0-9]*\.?[0-9]+)');
  final matches = reg.allMatches(normalized).toList();
  if (matches.isEmpty) throw const FormatException('no tokens');

  double sum = 0;
  for (final m in matches) {
    final sign = m.group(1)!;
    final numStr = m.group(2)!;
    final val = double.parse(numStr);
    sum += (sign == '-') ? -val : val;
  }

  return sum;
}
