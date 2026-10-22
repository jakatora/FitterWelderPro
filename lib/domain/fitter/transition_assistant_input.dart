import 'cone_development.dart';
import 'transition_development.dart';

class TransitionAssistantInput {
  TransitionAssistantInput._(this.input, this.result);
  final TransitionInput input;
  final TransitionResult result;
  static const fields = {
    'shape',
    'side_a_mm',
    'side_b_mm',
    'diameter_mm',
    'height_mm',
    'offset_x_mm',
    'offset_y_mm',
    'thickness_mm',
    'reference',
    'parts',
    'divisions',
    'seam'
  };
  factory TransitionAssistantInput.fromFields(Map<String, Object?> v) {
    Never invalid() => throw const FormatException('Invalid transition inputs');
    if (v['shape'] != 'transition' ||
        v.length != fields.length ||
        !fields.every(v.containsKey)) {
      invalid();
    }
    final ref =
        DiameterRef.values.where((e) => e.name == v['reference']).firstOrNull;
    final seam =
        TransitionSeam.values.where((e) => e.name == v['seam']).firstOrNull;
    final parts = v['parts'], divisions = v['divisions'];
    if (ref == null || seam == null || parts is! int || divisions is! int) {
      invalid();
    }
    double number(String k) {
      final n = v[k];
      if (n is! num || !n.isFinite) {
        invalid();
      }
      return n.toDouble();
    }

    final i = TransitionInput(
        sideAMm: number('side_a_mm'),
        sideBMm: number('side_b_mm'),
        diameterMm: number('diameter_mm'),
        heightMm: number('height_mm'),
        offsetXMm: number('offset_x_mm'),
        offsetYMm: number('offset_y_mm'),
        thicknessMm: number('thickness_mm'),
        ref: ref,
        parts: parts,
        divisions: divisions,
        seam: seam);
    final r = computeTransition(i);
    if (r == null ||
        ![r.bottomEdgeMm, r.topEdgeMm, r.maxWallSlopeDeg]
            .every((n) => n.isFinite) ||
        r.parts.any((p) =>
            !p.pattern.widthMm.isFinite || !p.pattern.heightMm.isFinite)) {
      invalid();
    }
    return TransitionAssistantInput._(i, r);
  }
}
