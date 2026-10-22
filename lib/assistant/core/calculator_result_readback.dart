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

// These are the displayed native fields, deliberately not invented precision.
final class RollingOffsetResultReadback extends CalculatorResultReadback {
  const RollingOffsetResultReadback(
      {this.trueOffsetMm,
      this.travelMm,
      this.runMm,
      this.multiplier,
      this.rollVerticalDeg,
      this.rollHorizontalDeg,
      this.takeoutMm,
      this.cutMm,
      this.cutElbowsOverlap});
  final double? trueOffsetMm,
      travelMm,
      runMm,
      multiplier,
      rollVerticalDeg,
      rollHorizontalDeg,
      takeoutMm,
      cutMm;
  final bool? cutElbowsOverlap;
  @override
  Map<String, Object?> toJson() => {
        'precision': 'displayed',
        'true_offset_mm': trueOffsetMm,
        'travel_mm': travelMm,
        'run_mm': runMm,
        'multiplier': multiplier,
        'roll_vertical_deg': rollVerticalDeg,
        'roll_horizontal_deg': rollHorizontalDeg,
        'takeout_mm': takeoutMm,
        'cut_mm': cutMm,
        'cut_elbows_overlap': cutElbowsOverlap,
      };
}

final class PipeSlopeResultReadback extends CalculatorResultReadback {
  const PipeSlopeResultReadback(
      {this.lengthMm, this.riseMm, this.slopePct, this.angleDeg, this.mmPerM});
  final double? lengthMm, riseMm, slopePct, angleDeg, mmPerM;
  @override
  Map<String, Object?> toJson() => {
        'precision': 'displayed',
        'length_mm': lengthMm,
        'rise_mm': riseMm,
        'slope_pct': slopePct,
        'angle_deg': angleDeg,
        'mm_per_m': mmPerM,
      };
}
