import 'tube_bending.dart';

/// Exact, complete native calculator update. The assistant and the page share
/// this decoder; no remembered bender setting can silently change the answer.
enum TubeCalculationMode { single, offset, multi }

const kTubeCalculationFields = {
  'mode',
  'unit',
  'clr_mm',
  'min_straight_mm',
  'marker_offset_mm',
  'springback_deg',
  'angle_deg',
  'leg_a_mm',
  'leg_b_mm',
  'height_mm',
  'spread_mm',
  'segments_mm',
  'angles_deg',
  'rotations_deg',
};

class TubeBendingCommand {
  TubeBendingCommand._(
      this.mode, this.unit, this.run, this.offset, this.fields);
  final TubeCalculationMode mode;
  final TubeUnit unit;
  final TubeRunResult run;
  final TubeOffsetResult? offset;
  final Map<String, Object?> fields;

  factory TubeBendingCommand.fromFields(Map<String, Object?> fields) {
    Never bad(String key) => throw FormatException(key);
    final mode = TubeCalculationMode.values
        .where((v) => v.name == fields['mode'])
        .firstOrNull;
    if (mode == null) bad('mode');
    final unit =
        TubeUnit.values.where((v) => v.name == fields['unit']).firstOrNull;
    if (unit == null) bad('unit');
    final required = {
      'mode',
      'unit',
      'clr_mm',
      'min_straight_mm',
      'marker_offset_mm',
      'springback_deg',
      if (mode != TubeCalculationMode.multi) ...[
        'angle_deg',
        'leg_a_mm',
        'leg_b_mm'
      ],
      if (mode == TubeCalculationMode.offset) ...['height_mm', 'spread_mm'],
      if (mode == TubeCalculationMode.multi) ...[
        'segments_mm',
        'angles_deg',
        'rotations_deg'
      ],
    };
    if (fields.keys.any((key) => !required.contains(key))) bad('fields');
    for (final key in required) {
      if (!fields.containsKey(key)) bad(key);
    }
    double number(String key) {
      final value = fields[key];
      if (value is! num || !value.isFinite) bad(key);
      return (value).toDouble();
    }

    List<double> numbers(String key) {
      final values = fields[key];
      if (values is! List ||
          values.isEmpty ||
          values.length >
              (key == 'segments_mm' ? kMaxTubeBends + 1 : kMaxTubeBends) ||
          values.any((v) => v is! num || !v.isFinite)) {
        bad(key);
      }
      return List<double>.unmodifiable(
          (values).map((v) => (v as num).toDouble()));
    }

    final clr = number('clr_mm'), minimum = number('min_straight_mm');
    final marker = number('marker_offset_mm'),
        springback = number('springback_deg');
    TubeOffsetResult? offset;
    late final TubeRunInput input;
    if (mode == TubeCalculationMode.offset) {
      final i = TubeOffsetInput(
          clrMm: clr,
          heightMm: number('height_mm'),
          spreadMm: number('spread_mm'),
          angleDeg: number('angle_deg'),
          legAMm: number('leg_a_mm'),
          legBMm: number('leg_b_mm'),
          minStraightMm: minimum,
          markerOffsetMm: marker,
          springbackDeg: springback);
      if (i.problems.isNotEmpty) bad(_fieldFor(i.problems.first, mode));
      offset = computeTubeOffset(i);
      input = i.run;
    } else if (mode == TubeCalculationMode.single) {
      input = TubeRunInput.single(
          clrMm: clr,
          angleDeg: number('angle_deg'),
          legAMm: number('leg_a_mm'),
          legBMm: number('leg_b_mm'),
          minStraightMm: minimum,
          markerOffsetMm: marker,
          springbackDeg: springback);
    } else {
      final segments = numbers('segments_mm'), angles = numbers('angles_deg');
      final rotations = numbers('rotations_deg');
      // The native first rotation is ignored. Never discard a nonzero value
      // supplied by the user, or pad/truncate an explicitly supplied list.
      if (rotations.length != angles.length ||
          rotations.isEmpty ||
          rotations.first != 0) {
        bad('rotations_deg');
      }
      input = TubeRunInput(
          clrMm: clr,
          segmentsMm: segments,
          anglesDeg: angles,
          rotationsDeg: rotations,
          minStraightMm: minimum,
          markerOffsetMm: marker,
          springbackDeg: springback);
    }
    if (input.problems.isNotEmpty) bad(_fieldFor(input.problems.first, mode));
    final run = offset?.run ?? computeTubeRun(input);
    if (run == null || !run.developedMm.isFinite) bad('geometry');
    if (!run.feasible) bad('geometry');
    final frozen = Map<String, Object?>.unmodifiable({
      ...fields,
      if (mode == TubeCalculationMode.multi) ...{
        'segments_mm': input.segmentsMm,
        'angles_deg': input.anglesDeg,
        'rotations_deg': input.rotationsDeg,
      },
    });
    return TubeBendingCommand._(mode, unit, run, offset, frozen);
  }
}

String _fieldFor(TubeBendProblem p, TubeCalculationMode mode) =>
    switch (p.kind) {
      TubeBendProblemKind.radius => 'clr_mm',
      TubeBendProblemKind.angle =>
        mode == TubeCalculationMode.multi ? 'angles_deg' : 'angle_deg',
      TubeBendProblemKind.segment => mode == TubeCalculationMode.multi
          ? 'segments_mm'
          : mode == TubeCalculationMode.offset && p.index == 2
              ? 'height_mm'
              : p.index == 1
                  ? 'leg_a_mm'
                  : 'leg_b_mm',
      TubeBendProblemKind.minStraight => 'min_straight_mm',
      TubeBendProblemKind.markerOffset => 'marker_offset_mm',
      TubeBendProblemKind.springback => 'springback_deg',
      TubeBendProblemKind.rotation => 'rotations_deg',
      TubeBendProblemKind.bendCount =>
        mode == TubeCalculationMode.multi ? 'segments_mm' : 'geometry',
      TubeBendProblemKind.offsetHeight => 'height_mm',
      TubeBendProblemKind.offsetSpread => 'spread_mm',
    };
