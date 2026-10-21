import 'dart:math' as math;
import '../../data/elbow_takeouts.dart';

/// Straight-pipe lengths of the route X (horizontal) → |H1−H2| (vertical) →
/// Y (horizontal): TWO 90° elbows, three pipe segments, four butt welds at
/// the elbows (+ two at the route ends when X / Y are measured to a face).
class PipeRouteResult {
  /// X − R − g (− g at the start weld): reference → face of elbow 1.
  final double seg1;

  /// |H1−H2| − 2R − 2g: between the faces of elbow 1 and elbow 2.
  final double seg2;

  /// Y − R − g (− g at the end weld): face of elbow 2 → reference.
  final double seg3;

  /// Σ of the (non-negative) straight segments — what goes on the saw.
  final double total;

  /// Number of 90° elbows in this route.
  final int elbowCount;

  /// Number of butt welds whose root gap was deducted.
  final int weldCount;

  /// Centreline arc length of the elbows: 2 × (π·R/2) = π·R.
  final double arcsMm;

  /// Developed centreline length: straights + weld gaps + arcs
  /// (= X + |H1−H2| + Y − (4 − π)·R for positive segments).
  final double developedMm;

  const PipeRouteResult({
    required this.seg1,
    required this.seg2,
    required this.seg3,
    required this.total,
    required this.elbowCount,
    required this.weldCount,
    required this.arcsMm,
    required this.developedMm,
  });
}

/// Pure calculation behind [PipeRouteCalculatorScreen]; [r] is the take-out
/// (centre-to-face) of one 90° elbow — for an LR elbow its CLR radius, ASME
/// B16.9 dimension A. [gapMm] is the weld root gap deducted at every butt
/// weld: the 4 elbow welds always, the 2 route-end welds when [endWelds]
/// (X and Y measured to the face of a flange / pipe that gets welded on).
PipeRouteResult computePipeRoute({
  required double h1,
  required double h2,
  required double x,
  required double y,
  required double r,
  double gapMm = 0,
  bool endWelds = false,
}) {
  const elbows = 2;
  final endGap = endWelds ? gapMm : 0.0;
  final seg1 = x - r - gapMm - endGap;
  final seg2 = (h1 - h2).abs() - 2 * r - 2 * gapMm;
  final seg3 = y - r - gapMm - endGap;
  final total = math.max(0.0, seg1) + math.max(0.0, seg2) + math.max(0.0, seg3);
  final welds = 2 * elbows + (endWelds ? 2 : 0);
  final arcs = elbows * (math.pi * r / 2);
  return PipeRouteResult(
    seg1: seg1,
    seg2: seg2,
    seg3: seg3,
    total: total,
    elbowCount: elbows,
    weldCount: welds,
    arcsMm: arcs,
    developedMm: total + welds * gapMm + arcs,
  );
}

/// Complete, validated input shared by the assistant and the native bridge.
class PipeRouteInput {
  PipeRouteInput._(this.fields, this.result);
  final Map<String, Object?> fields;
  final PipeRouteResult result;
  static const keys = {
    'h1_mm',
    'h2_mm',
    'x_mm',
    'y_mm',
    'r_mm',
    'gap_mm',
    'end_welds',
    'dn'
  };
  factory PipeRouteInput.fromFields(Map<String, Object?> fields) {
    Never bad(String key) => throw FormatException(key);
    if (fields.keys.any((key) => !keys.contains(key))) bad('fields');
    double n(String key) {
      final v = fields[key];
      if (v is! num || !v.isFinite) bad(key);
      return (v).toDouble();
    }

    final h1 = n('h1_mm'),
        h2 = n('h2_mm'),
        x = n('x_mm'),
        y = n('y_mm'),
        r = n('r_mm'),
        gap = n('gap_mm');
    if ((h1 - h2).abs() < 1e-9 || !(h1 - h2).isFinite) bad('heights');
    if (x <= 0) bad('x_mm');
    if (y <= 0) bad('y_mm');
    if (r < 0) bad('r_mm');
    if (gap < 0) bad('gap_mm');
    final ends = fields['end_welds'];
    if (ends is! bool) bad('end_welds');
    final dn = fields['dn'];
    if (dn != null && (dn is! int || elbowTakeoutForDn(dn)?.lr90 != r)) {
      bad('r_mm');
    }
    final result = computePipeRoute(
        h1: h1, h2: h2, x: x, y: y, r: r, gapMm: gap, endWelds: ends);
    if ([
      result.seg1,
      result.seg2,
      result.seg3,
      result.total,
      result.arcsMm,
      result.developedMm
    ].any((v) => !v.isFinite)) {
      bad('geometry');
    }
    if (result.seg1 < 0 || result.seg2 < 0 || result.seg3 < 0) bad('geometry');
    return PipeRouteInput._(
        Map<String, Object?>.unmodifiable({...fields}), result);
  }
}
