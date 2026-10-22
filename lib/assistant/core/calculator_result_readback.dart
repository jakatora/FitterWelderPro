import '../../domain/welding/heat_input.dart';

// Explicit native output port. Only this sealed family may enter AI context.
sealed class CalculatorResultReadback {
  const CalculatorResultReadback();
  Map<String, Object?> toJson();
}

enum EfficiencyReadbackSource { processDefault, explicitOverride, notUsed }

final class HeatInputResultReadback extends CalculatorResultReadback {
  const HeatInputResultReadback(
      {required this.valueKjPerMm,
      required this.displayValue,
      required this.unit,
      required this.efficiency,
      required this.efficiencySource});
  final double? valueKjPerMm, displayValue, efficiency;
  final HeatInputUnit unit;
  final EfficiencyReadbackSource efficiencySource;
  @override
  Map<String, Object?> toJson() => {
        'value_kj_per_mm': valueKjPerMm,
        'display_value': displayValue,
        'display_unit': unit.name,
        'efficiency_used': efficiency,
        'efficiency_source': switch (efficiencySource) {
          EfficiencyReadbackSource.processDefault => 'process_default',
          EfficiencyReadbackSource.explicitOverride => 'explicit_override',
          EfficiencyReadbackSource.notUsed => 'not_used',
        },
      };
}
