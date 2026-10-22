import 'cone_development.dart';

/// Complete native payload; the derived vertical-side offset is never supplied
/// as an independent value, and no concentric-mode fields are silently ignored.
class EccentricConeAssistantInput {
  EccentricConeAssistantInput._(this.input, this.result);
  final EccentricConeInput input;
  final EccentricConeResult result;
  static const fields = {
    'shape',
    'mode',
    'large_dia_mm',
    'small_dia_mm',
    'height_mm',
    'thickness_mm',
    'reference',
    'parts',
    'divisions',
    'vertical_side',
    'offset_mm',
    'seam_on_short_side'
  };
  factory EccentricConeAssistantInput.fromFields(Map<String, Object?> v) {
    Never invalid() =>
        throw const FormatException('Invalid eccentric cone inputs');
    final vertical = v['vertical_side'], seam = v['seam_on_short_side'];
    if (v['shape'] != 'eccentric' ||
        v['mode'] != 'height' ||
        vertical is! bool ||
        seam is! bool) {
      invalid();
    }
    final required = {...fields}..remove('offset_mm');
    if (!vertical || v.containsKey('offset_mm')) required.add('offset_mm');
    if (vertical && v['offset_mm'] != null) {
      invalid();
    }
    if (v.length != required.length || !required.every(v.containsKey)) {
      invalid();
    }
    final ref =
        DiameterRef.values.where((r) => r.name == v['reference']).firstOrNull;
    final parts = v['parts'], divisions = v['divisions'];
    if (ref == null || parts is! int || divisions is! int) {
      invalid();
    }
    double number(String k) {
      final n = v[k];
      if (n is! num || !n.isFinite) {
        invalid();
      }
      return n.toDouble();
    }

    final i = EccentricConeInput(
        largeDiaMm: number('large_dia_mm'),
        smallDiaMm: number('small_dia_mm'),
        heightMm: number('height_mm'),
        thicknessMm: number('thickness_mm'),
        ref: ref,
        verticalSide: vertical,
        offsetMm: vertical ? 0 : number('offset_mm'),
        parts: parts,
        divisions: divisions,
        seamOnShortSide: seam);
    final r = computeEccentricCone(i);
    if (r == null ||
        ![
          r.offsetMm,
          r.shortestGeneratorMm,
          r.longestGeneratorMm,
          r.developedAngleDeg,
          r.bottomEdgeMm,
          r.topEdgeMm
        ].every((n) => n.isFinite) ||
        r.parts.any((p) => !p.widthMm.isFinite || !p.heightMm.isFinite)) {
      invalid();
    }
    return EccentricConeAssistantInput._(i, r);
  }
}
