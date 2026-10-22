import 'cone_development.dart';

/// Complete, millimetre-based native contract. Never merges a model payload
/// with hidden UI defaults or accepts fields for another cone shape.
class ConeAssistantInput {
  ConeAssistantInput._(this.input, this.result);
  final ConeInput input;
  final ConeResult result;
  static const fields = {
    'shape',
    'mode',
    'large_dia_mm',
    'small_dia_mm',
    'thickness_mm',
    'reference',
    'parts',
    'allowance_mm',
    'height_mm',
    'half_angle_deg',
    'slant_mm',
  };
  factory ConeAssistantInput.fromFields(Map<String, Object?> values) {
    Never invalid() => throw const FormatException('Invalid cone inputs');
    if (values['shape'] != 'concentric') invalid();
    final mode =
        ConeSizeMode.values.where((v) => v.name == values['mode']).firstOrNull;
    final ref = DiameterRef.values
        .where((v) => v.name == values['reference'])
        .firstOrNull;
    if (mode == null || ref == null) invalid();
    final sizeKey = switch (mode) {
      ConeSizeMode.height => 'height_mm',
      ConeSizeMode.halfAngle => 'half_angle_deg',
      ConeSizeMode.slant => 'slant_mm',
    };
    final required = {
      'shape',
      'mode',
      'large_dia_mm',
      'small_dia_mm',
      'thickness_mm',
      'reference',
      'parts',
      'allowance_mm',
      sizeKey
    };
    if (values.length != required.length ||
        !required.every(values.containsKey)) {
      invalid();
    }
    double number(String key) {
      final v = values[key];
      if (v is! num || !v.isFinite) invalid();
      return v.toDouble();
    }

    final parts = values['parts'];
    if (parts is! int || !kConePartOptions.contains(parts)) invalid();
    final input = ConeInput(
        largeDiaMm: number('large_dia_mm'),
        smallDiaMm: number('small_dia_mm'),
        mode: mode,
        heightMm: mode == ConeSizeMode.height ? number(sizeKey) : 0,
        halfAngleDeg: mode == ConeSizeMode.halfAngle ? number(sizeKey) : 0,
        slantMm: mode == ConeSizeMode.slant ? number(sizeKey) : 0,
        thicknessMm: number('thickness_mm'),
        ref: ref,
        parts: parts,
        allowanceMm: number('allowance_mm'));
    final result = computeCone(input);
    if (result == null ||
        ![
          result.outerRadiusMm,
          result.innerRadiusMm,
          result.sectorAngleDeg,
          result.slantMm,
          result.areaMm2
        ].every((v) => v.isFinite)) {
      invalid();
    }
    return ConeAssistantInput._(input, result);
  }
}
