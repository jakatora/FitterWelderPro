import '../fitter/unit_conversion.dart';

/// Existing pressure factors shared with the general converter, plus the
/// welding screen's conventional water-column units (standard gravity).
final Map<String, double> welderPressureFactors = Map.unmodifiable({
  for (final unit in PressureUnit.values) unit.symbol: unit.toBar,
  'Pa': 0.00001,
  'inH₂O': 25.4 * 0.0000980665,
  'mmH₂O': 0.0000980665,
});

Map<String, double>? convertWelderPressure(double value, String from) {
  final factor = welderPressureFactors[from];
  if (factor == null || !value.isFinite || value < 0) return null;
  final base = value * factor;
  final result = {
    for (final e in welderPressureFactors.entries) e.key: base / e.value
  };
  return result.values.every((v) => v.isFinite)
      ? Map.unmodifiable(result)
      : null;
}

class PressureCalculatorInput {
  static const keys = {'value', 'from'};
  PressureCalculatorInput._(this.value, this.from, this.results);
  final double value;
  final String from;
  final Map<String, double> results;
  factory PressureCalculatorInput.fromFields(Map<String, Object?> fields) {
    final value = fields['value'], from = fields['from'];
    if (fields['tab'] != 'pressure' ||
        fields.keys.any((k) => k != 'tab' && !keys.contains(k)) ||
        value is! num ||
        from is! String) {
      throw const FormatException('Pressure inputs');
    }
    final results = convertWelderPressure(value.toDouble(), from);
    if (results == null) throw const FormatException('Pressure range or unit');
    return PressureCalculatorInput._(value.toDouble(), from, results);
  }
  Map<String, Object?> get fields =>
      {'tab': 'pressure', 'value': value, 'from': from};
}
