import 'core/skill.dart';

// Explicit visible numeric/choice ports only. No records, text fields, accounts
// or inferred outputs. Keep the server contract in calculatorQuestionContext.js.
class CalculatorQuestionContext {
  CalculatorQuestionContext._(this.toolId, Map<String, Object?> inputs)
      : inputs = Map.unmodifiable(inputs);
  final String toolId;
  final Map<String, Object?> inputs;
  Map<String, Object?> toJson() => {'tool_id': toolId, 'inputs': inputs};

  static const _numeric = {
    'heat_input': {'volts', 'amps', 'travel_mm_min', 'efficiency'},
    'rolling_offset': {'rise_mm', 'spread_mm', 'angle_deg', 'dn', 'gap_mm'},
    'pipe_slope': {'length_mm', 'rise_mm', 'slope_pct'},
    'pipe_route': {'h1_mm', 'h2_mm', 'x_mm', 'y_mm', 'r_mm', 'gap_mm', 'dn'},
  };
  static const _choices = {
    'heat_input': {
      'process': {'SMAW', 'GMAW', 'FCAW-G', 'FCAW-S', 'GTAW', 'SAW'},
      'standard': {'en1011', 'asmeIx'},
    },
    'pipe_slope': {
      'mode': {'length_to_rise', 'rise_to_length', 'slope_from_lr'}
    },
  };

  static CalculatorQuestionContext? capture(ModuleContext modules) {
    final id = modules.activeToolId;
    if (!_numeric.containsKey(id) || modules is! FieldModuleContext) {
      return null;
    }
    final fields = (modules as FieldModuleContext).inputFields(id!);
    if (fields == null || fields.isEmpty) return null;
    final values = <String, Object?>{};
    for (final key in _numeric[id]!) {
      if (!fields.containsKey(key)) continue;
      final value = fields[key];
      // An invalid/blank visible number is explicitly missing, never zero.
      values[key] = value is num && value.isFinite ? value : null;
    }
    for (final entry
        in (_choices[id] ?? const <String, Set<String>>{}).entries) {
      if (!fields.containsKey(entry.key)) continue;
      final value = fields[entry.key];
      values[entry.key] = entry.value.contains(value) ? value : null;
    }
    if (id == 'pipe_route' && fields.containsKey('end_welds')) {
      final value = fields['end_welds'];
      values['end_welds'] = value is bool ? value : null;
    }
    return values.isEmpty ? null : CalculatorQuestionContext._(id, values);
  }
}
