/// Spatial centreline geometry for the ISO notebook. Paper angles are not
/// physical bend angles: the projection maps different 3D rays to the same
/// 2D line. Lengths here are centre-to-centre millimetres; fitting take-outs
/// stay in the existing CUT engine and are never subtracted a second time.
library;

import 'dart:math' as math;

const _epsilon = 1e-10;

/// Components in the notebook's orthogonal I / II / III frame. Its positive
/// paper axes are headings 0 / 5 / 4 respectively. These are grid axes,
/// independent of how a particular north arrow labels them geographically.
class IsoSpatialVector {
  const IsoSpatialVector(this.i, this.ii, this.iii);
  static const zero = IsoSpatialVector(0, 0, 0);
  final double i, ii, iii;
  bool get isFinite => i.isFinite && ii.isFinite && iii.isFinite;
  double get magnitude {
    if (!isFinite) return double.nan;
    final scale = math.max(i.abs(), math.max(ii.abs(), iii.abs()));
    if (scale == 0) return 0;
    final a = i / scale, b = ii / scale, c = iii / scale;
    return scale * math.sqrt(a * a + b * b + c * c);
  }

  IsoSpatialVector operator +(IsoSpatialVector b) =>
      IsoSpatialVector(i + b.i, ii + b.ii, iii + b.iii);
  IsoSpatialVector operator -(IsoSpatialVector b) =>
      IsoSpatialVector(i - b.i, ii - b.ii, iii - b.iii);
  IsoSpatialVector operator *(double scale) =>
      IsoSpatialVector(i * scale, ii * scale, iii * scale);
  double dot(IsoSpatialVector b) => i * b.i + ii * b.ii + iii * b.iii;

  IsoSpatialVector get unit {
    if (!isFinite) throw ArgumentError('Non-finite spatial direction');
    final scale = math.max(i.abs(), math.max(ii.abs(), iii.abs()));
    if (scale == 0) throw ArgumentError('A direction cannot be zero');
    // Scale first: finite large components must not overflow during sqrt.
    final a = i / scale, b = ii / scale, c = iii / scale;
    final length = math.sqrt(a * a + b * b + c * c);
    return IsoSpatialVector(a / length, b / length, c / length);
  }

  double angleTo(IsoSpatialVector other) {
    final cosine = unit.dot(other.unit).clamp(-1.0, 1.0);
    return math.acos(cosine) * 180 / math.pi;
  }

  /// Rotate within the plane spanned by this ray and [towards]. The target
  /// determines the side of the bend, not an invented extra rotation axis.
  /// An antiparallel target leaves that plane ambiguous and is rejected.
  IsoSpatialVector turnTowards(IsoSpatialVector towards, double degrees) {
    if (!degrees.isFinite || degrees < 0 || degrees > 180) {
      throw ArgumentError('Invalid bend angle');
    }
    final incoming = unit, target = towards.unit;
    if (degrees == 0) return incoming;
    final angle = incoming.angleTo(target);
    if (angle <= _epsilon) {
      throw ArgumentError('The target does not define a bend plane');
    }
    if ((180 - angle).abs() < _epsilon) {
      throw ArgumentError('The bend plane is ambiguous');
    }
    if (degrees > angle + _epsilon) {
      throw ArgumentError('The bend would overshoot its target');
    }
    if ((degrees - angle).abs() < _epsilon) return target;
    final tangent = (target - incoming * incoming.dot(target)).unit;
    final radians = degrees * math.pi / 180;
    return (incoming * math.cos(radians) + tangent * math.sin(radians)).unit;
  }

  /// Same isometric projection as the notebook grid. The result is a paper
  /// displacement, not a physical pipe length or a way to recover 3D rays.
  ({double x, double y}) get projected {
    if (!isFinite) throw ArgumentError('Non-finite spatial vector');
    final scale = math.max(i.abs(), math.max(ii.abs(), iii.abs()));
    if (scale == 0) return (x: 0, y: 0);
    final a = i / scale, b = ii / scale, c = iii / scale;
    final x = (a + b * .5 - c * .5) * scale;
    final y = (b + c) * (math.sqrt(3) / 2) * scale;
    if (!x.isFinite || !y.isFinite) throw ArgumentError('Projection overflow');
    return (x: x, y: y);
  }

  factory IsoSpatialVector.gridHeading(int heading) => switch (heading) {
        0 => const IsoSpatialVector(1, 0, 0),
        1 => const IsoSpatialVector(0, 0, -1),
        2 => const IsoSpatialVector(0, -1, 0),
        3 => const IsoSpatialVector(-1, 0, 0),
        4 => const IsoSpatialVector(0, 0, 1),
        5 => const IsoSpatialVector(0, 1, 0),
        _ => throw RangeError.range(heading, 0, 5, 'heading'),
      };

  List<double> toJson() {
    if (!isFinite) throw ArgumentError('Cannot encode non-finite geometry');
    return List.unmodifiable([i, ii, iii]);
  }

  static IsoSpatialVector? fromJson(Object? raw) {
    if (raw is! List ||
        raw.length != 3 ||
        raw.any((v) => v is! num || !v.isFinite)) {
      return null;
    }
    return IsoSpatialVector((raw[0] as num).toDouble(),
        (raw[1] as num).toDouble(), (raw[2] as num).toDouble());
  }

  @override
  bool operator ==(Object other) =>
      other is IsoSpatialVector &&
      i == other.i &&
      ii == other.ii &&
      iii == other.iii;
  @override
  int get hashCode => Object.hash(i, ii, iii);
}

double isoSpatialGridTurnDegrees(int incoming, int outgoing) =>
    IsoSpatialVector.gridHeading(incoming)
        .angleTo(IsoSpatialVector.gridHeading(outgoing));

sealed class IsoSpatialStep {
  const IsoSpatialStep();
}

class IsoSpatialPipe extends IsoSpatialStep {
  const IsoSpatialPipe(this.lengthMm);
  final double lengthMm;
}

class IsoSpatialTurn extends IsoSpatialStep {
  const IsoSpatialTurn({required this.degrees, required this.towards});
  final double degrees;
  final IsoSpatialVector towards;
}

class IsoSpatialSegment {
  const IsoSpatialSegment(
      {required this.start,
      required this.end,
      required this.direction,
      required this.lengthMm});
  final IsoSpatialVector start, end, direction;
  final double lengthMm;
}

class IsoSpatialBend {
  const IsoSpatialBend(
      {required this.at,
      required this.incoming,
      required this.outgoing,
      required this.degrees});
  final IsoSpatialVector at, incoming, outgoing;
  final double degrees;
}

class IsoSpatialRoute {
  IsoSpatialRoute._(this.origin, this.end, this.heading,
      List<IsoSpatialSegment> segments, List<IsoSpatialBend> bends)
      : segments = List.unmodifiable(segments),
        bends = List.unmodifiable(bends);
  final IsoSpatialVector origin, end, heading;
  final List<IsoSpatialSegment> segments;
  final List<IsoSpatialBend> bends;
}

/// Pure, atomic plan. Invalid later steps return no partial result and cannot
/// mutate a drawing. Every bend needs an incoming and an outgoing pipe.
IsoSpatialRoute planIsoSpatialRoute(List<IsoSpatialStep> steps,
    {required IsoSpatialVector heading,
    IsoSpatialVector origin = IsoSpatialVector.zero}) {
  if (!origin.isFinite) throw ArgumentError('Non-finite route origin');
  var direction = heading.unit;
  var point = origin;
  var awaitingPipe = false;
  final segments = <IsoSpatialSegment>[];
  final bends = <IsoSpatialBend>[];
  for (final step in steps) {
    switch (step) {
      case IsoSpatialPipe(:final lengthMm):
        if (!lengthMm.isFinite || lengthMm <= 0) {
          throw ArgumentError('Pipe length must be positive and finite');
        }
        final end = point + direction * lengthMm;
        if (!end.isFinite) throw ArgumentError('Route coordinate overflow');
        segments.add(IsoSpatialSegment(
            start: point, end: end, direction: direction, lengthMm: lengthMm));
        point = end;
        awaitingPipe = false;
      case IsoSpatialTurn(:final degrees, :final towards):
        if (!degrees.isFinite || degrees <= 0 || degrees >= 180) {
          throw ArgumentError('A route bend must be between 0 and 180 degrees');
        }
        if (segments.isEmpty || awaitingPipe) {
          throw ArgumentError('A bend needs a pipe on each side');
        }
        final outgoing = direction.turnTowards(towards, degrees);
        bends.add(IsoSpatialBend(
            at: point,
            incoming: direction,
            outgoing: outgoing,
            degrees: degrees));
        direction = outgoing;
        awaitingPipe = true;
    }
  }
  if (awaitingPipe) throw ArgumentError('A bend cannot end the route');
  return IsoSpatialRoute._(origin, point, direction, segments, bends);
}
