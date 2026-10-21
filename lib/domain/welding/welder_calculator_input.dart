import 'purge.dart';
import 'shielding_gas.dart';

Map<String, double> _numbers(Map<String, Object?> fields, Set<String> keys,
    Map<String, double> defaults, String tab) {
  if (fields['tab'] != tab ||
      fields.keys.any((k) => k != 'tab' && !keys.contains(k))) {
    throw const FormatException('Unsupported calculator input');
  }
  final values = {...defaults};
  for (final key in keys) {
    if (!fields.containsKey(key)) continue;
    final value = fields[key];
    if (value is! num || !value.isFinite) throw FormatException(key);
    values[key] = value.toDouble();
  }
  return values;
}

class GasCalculatorInput {
  static const keys = {
    'welds',
    'weld_minutes',
    'torch_lpm',
    'pre_flow_s',
    'post_flow_s',
    'purge_lpm',
    'purge_minutes',
    'water_l',
    'fill_bar',
    'reserve_bar',
    'current_bar'
  };
  // Existing app presets, not a recommended welding procedure.
  static const defaults = {
    'pre_flow_s': 5.0,
    'post_flow_s': 10.0,
    'purge_lpm': 0.0,
    'purge_minutes': 0.0,
    'water_l': 50.0,
    'fill_bar': 200.0,
    'reserve_bar': 0.0
  };
  GasCalculatorInput._(
      this.values, this.consumption, this.cylinderL, this.bottles);
  final Map<String, double> values;
  final GasConsumption consumption;
  final double cylinderL, bottles;
  factory GasCalculatorInput.fromFields(Map<String, Object?> fields) {
    final v = _numbers(fields, keys, defaults, 'gas');
    if (!const ['welds', 'weld_minutes', 'torch_lpm'].every(v.containsKey)) {
      throw const FormatException('Missing gas inputs');
    }
    final result = estimateGasConsumption(
        welds: v['welds']!,
        weldMinutes: v['weld_minutes']!,
        torchLpm: v['torch_lpm']!,
        preFlowS: v['pre_flow_s']!,
        postFlowS: v['post_flow_s']!,
        purgeLpm: v['purge_lpm']!,
        purgeMinutes: v['purge_minutes']!);
    if (result == null ||
        !result.totalL.isFinite ||
        result.totalL <= 0 ||
        (v['purge_lpm']! > 0) != (v['purge_minutes']! > 0)) {
      throw const FormatException('Gas flow or time');
    }
    final cylinder = usableCylinderGasL(
        waterCapacityL: v['water_l']!,
        fillPressureBar: v['fill_bar']!,
        reserveBar: v['reserve_bar']!);
    if (cylinder == null || !cylinder.isFinite) {
      throw const FormatException('Cylinder');
    }
    final bottles = cylindersNeeded(
        totalGasL: result.totalL, usableGasPerCylinderL: cylinder);
    if (bottles == null || !bottles.isFinite) {
      throw const FormatException('Gas result');
    }
    if (v.containsKey('current_bar')) {
      final remaining = cylinderRemaining(
          waterCapacityL: v['water_l']!,
          currentPressureBar: v['current_bar']!,
          torchLpm: v['torch_lpm']!,
          reserveBar: v['reserve_bar']!,
          weldMinutes: v['weld_minutes']!,
          preFlowS: v['pre_flow_s']!,
          postFlowS: v['post_flow_s']!);
      if (remaining == null ||
          !remaining.flowMinutes.isFinite ||
          !remaining.gasL.isFinite ||
          remaining.welds?.isFinite == false) {
        throw const FormatException('Current pressure');
      }
    }
    return GasCalculatorInput._(Map.unmodifiable(v), result, cylinder, bottles);
  }
  Map<String, Object?> get fields => {'tab': 'gas', ...values};
}

class PurgeCalculatorInput {
  static const keys = {
    'od_mm',
    'wall_mm',
    'length_mm',
    'flow_lpm',
    'initial_ppm',
    'target_ppm'
  };
  PurgeCalculatorInput._(this.values, this.estimate);
  final Map<String, double> values;
  final PurgeEstimate estimate;
  factory PurgeCalculatorInput.fromFields(Map<String, Object?> fields) {
    final v = _numbers(fields, keys, const {}, 'purge');
    if (!keys.every(v.containsKey)) {
      throw const FormatException('Missing purge inputs');
    }
    final result = estimatePurge(
        odMm: v['od_mm']!,
        wallMm: v['wall_mm']!,
        lengthMm: v['length_mm']!,
        flowLpm: v['flow_lpm']!,
        initialPpm: v['initial_ppm']!,
        targetPpm: v['target_ppm']!);
    final estimate = result.estimate;
    if (estimate == null ||
        !estimate.volumeL.isFinite ||
        !estimate.timeSec.isFinite ||
        !estimate.volumeChanges.isFinite ||
        estimate.volumeL <= 0 ||
        estimate.timeSec <= 0 ||
        estimate.volumeChanges <= 0) {
      throw const FormatException('Purge input');
    }
    return PurgeCalculatorInput._(Map.unmodifiable(v), estimate);
  }
  Map<String, Object?> get fields => {'tab': 'purge', ...values};
}
