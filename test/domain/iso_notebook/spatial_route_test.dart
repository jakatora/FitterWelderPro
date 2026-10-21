import 'dart:math' as math;
import 'package:flutter_test/flutter_test.dart';
import 'package:cut_list_app/domain/iso_notebook/spatial_route.dart';

void expectVector(IsoSpatialVector actual, IsoSpatialVector expected,
    {double tolerance = 1e-9}) {
  expect(actual.i, closeTo(expected.i, tolerance));
  expect(actual.ii, closeTo(expected.ii, tolerance));
  expect(actual.iii, closeTo(expected.iii, tolerance));
}

void main() {
  test(
      'spatial tee preserves unknown roll and accepts only perpendicular unit branches',
      () {
    final run = IsoSpatialVector.gridHeading(0)
        .turnTowards(IsoSpatialVector.gridHeading(1), 45);
    final pending = IsoSpatialTee(run: run);
    expect(IsoSpatialTee.fromJson(pending.toJson())!.branch, isNull);
    final tee =
        IsoSpatialTee(run: run, branch: IsoSpatialVector.gridHeading(2));
    expect(IsoSpatialTee.fromJson(tee.toJson())!.run.toJson(), run.toJson());
    for (final branch in [
      run,
      IsoSpatialVector.gridHeading(1),
      const IsoSpatialVector(0, 2, 0),
      IsoSpatialVector.zero
    ]) {
      expect(
          () => IsoSpatialTee(run: run, branch: branch), throwsArgumentError);
    }
    expect(IsoSpatialTee.fromJson({...tee.toJson(), 'future': true}), isNull);
    expect(
        IsoSpatialTee.fromJson({
          'run': run.toJson(),
          'branch': [0, 1]
        }),
        isNull);
  });

  test('angle computation does not invent a bend after unit normalization', () {
    final diagonal = IsoSpatialVector.gridHeading(0)
        .turnTowards(IsoSpatialVector.gridHeading(1), 45);
    expect(diagonal.angleTo(diagonal), 0);
    expect(diagonal.angleTo(diagonal.unit), closeTo(0, 1e-12));
    const x = IsoSpatialVector(1, 0, 0);
    expect(x.angleTo(const IsoSpatialVector(1, 1e-12, 0)),
        closeTo(1e-12 * 180 / math.pi, 1e-14));
    expect(x.angleTo(const IsoSpatialVector(-1, 1e-9, 0)),
        closeTo(180 - 1e-9 * 180 / math.pi, 1e-12));
  });

  test('finite projections avoid intermediate arithmetic overflow', () {
    final p = const IsoSpatialVector(1e308, 1e308, 1e308).projected;
    expect(p.x, closeTo(1e308, 1e293));
    expect(p.y, closeTo(math.sqrt(3) * 1e308, 1e293));
    final q = const IsoSpatialVector(1.7e308, .3e308, .3e308).projected;
    expect(q.x, closeTo(1.7e308, 1e293));
    expect(q.y, closeTo(.6e308 * math.sqrt(3) / 2, 1e293));
  });

  final right = IsoSpatialVector.gridHeading(0),
      up = IsoSpatialVector.gridHeading(1),
      back = IsoSpatialVector.gridHeading(2);
  test('all six grid rays project onto the existing notebook axes', () {
    final h = math.sqrt(3) / 2;
    final expected = [
      (1.0, 0.0),
      (.5, -h),
      (-.5, -h),
      (-1.0, 0.0),
      (-.5, h),
      (.5, h)
    ];
    for (var i = 0; i < 6; i++) {
      final p = IsoSpatialVector.gridHeading(i).projected;
      expect(p.x, closeTo(expected[i].$1, 1e-12));
      expect(p.y, closeTo(expected[i].$2, 1e-12));
    }
  });
  test(
      'grid rays have physical 0, 90 or 180 degree angles regardless of paper angles',
      () {
    for (var a = 0; a < 6; a++) {
      for (var b = 0; b < 6; b++) {
        final expected = a == b
            ? 0.0
            : (a - b).abs() == 3
                ? 180.0
                : 90.0;
        expect(isoSpatialGridTurnDegrees(a, b), closeTo(expected, 1e-10));
      }
    }
    final p = up.projected;
    expect(math.atan2(p.y, p.x) * 180 / math.pi, closeTo(-60, 1e-10));
    expect(right.angleTo(up), 90);
  });
  test(
      'a 45 degree bend is calculated in 3D rather than snapping to a paper axis',
      () {
    final bend = right.turnTowards(up, 45);
    final half = math.sqrt(.5);
    expectVector(bend, IsoSpatialVector(half, 0, -half));
    expect(bend.magnitude, closeTo(1, 1e-12));
    expect(right.angleTo(bend), closeTo(45, 1e-10));
    expect(bend.angleTo(up), closeTo(45, 1e-10));
    final p = bend.projected;
    expect(math.atan2(p.y, p.x) * 180 / math.pi, closeTo(-30, 1e-10));
  });
  test('parallel paper rays can represent perpendicular spatial directions',
      () {
    final diagonal = right.turnTowards(back, 45);
    final a = diagonal.projected, b = up.projected;
    expect(a.x * b.y - a.y * b.x, closeTo(0, 1e-12));
    expect(diagonal.angleTo(up), closeTo(90, 1e-10));
  });
  test(
      'two 45 degree bends preserve physical lengths and reach the target axis',
      () {
    final route = planIsoSpatialRoute([
      const IsoSpatialPipe(1000),
      IsoSpatialTurn(degrees: 45, towards: up),
      const IsoSpatialPipe(1000),
      IsoSpatialTurn(degrees: 45, towards: up),
      const IsoSpatialPipe(500)
    ], heading: right);
    expect(route.segments, hasLength(3));
    expect(route.bends, hasLength(2));
    expectVector(route.heading, up);
    expectVector(
        route.end,
        IsoSpatialVector(
            1000 + 1000 * math.sqrt(.5), 0, -500 - 1000 * math.sqrt(.5)),
        tolerance: 1e-8);
    for (final s in route.segments) {
      expect((s.end - s.start).magnitude, closeTo(s.lengthMm, 1e-8));
    }
    for (final b in route.bends) {
      expect(b.incoming.angleTo(b.outgoing), closeTo(b.degrees, 1e-10));
    }
    expect(() => route.segments.clear(), throwsUnsupportedError);
    expect(() => route.bends.clear(), throwsUnsupportedError);
  });
  test('straight continuation retains a sloping heading and translated origin',
      () {
    final steps = <IsoSpatialStep>[
      const IsoSpatialPipe(100),
      IsoSpatialTurn(degrees: 45, towards: up),
      const IsoSpatialPipe(200),
      const IsoSpatialPipe(300)
    ];
    final first = planIsoSpatialRoute(steps, heading: right);
    const origin = IsoSpatialVector(123, 456, -78);
    final shifted = planIsoSpatialRoute(steps, heading: right, origin: origin);
    expectVector(shifted.end, first.end + origin);
    expectVector(shifted.segments[1].direction, shifted.segments[2].direction);
    expect(shifted.bends, hasLength(1));
  });
  test(
      'opposite targets, overshoot and zero directions cannot invent a bend plane',
      () {
    expect(() => right.turnTowards(right * (-1), 45), throwsArgumentError);
    expect(() => right.turnTowards(up, 135), throwsArgumentError);
    expect(() => right.turnTowards(right, 45), throwsArgumentError);
    expect(() => right.turnTowards(right, 1e-12), throwsArgumentError);
    expect(() => right.turnTowards(IsoSpatialVector.zero, 45),
        throwsArgumentError);
    expectVector(right.turnTowards(up, 0), right);
    for (final angle in [-1.0, 181.0, double.nan, double.infinity]) {
      expect(() => right.turnTowards(up, angle), throwsArgumentError);
    }
  });
  test('large finite directions normalise without overflow', () {
    final v = const IsoSpatialVector(1e308, 1e308, 1e308).unit;
    expect(v.magnitude, closeTo(1, 1e-12));
    expect(v.i, closeTo(1 / math.sqrt(3), 1e-12));
    expect(const IsoSpatialVector(1e308, 0, 0).magnitude, 1e308);
  });
  test(
      'invalid and trailing steps fail without changing a previous valid route',
      () {
    final valid =
        planIsoSpatialRoute([const IsoSpatialPipe(100)], heading: right);
    final before = valid.end;
    final bad = <List<IsoSpatialStep>>[
      [IsoSpatialTurn(degrees: 45, towards: up), const IsoSpatialPipe(100)],
      [const IsoSpatialPipe(100), IsoSpatialTurn(degrees: 45, towards: up)],
      [
        const IsoSpatialPipe(100),
        IsoSpatialTurn(degrees: 45, towards: up),
        IsoSpatialTurn(degrees: 45, towards: up),
        const IsoSpatialPipe(100)
      ],
      [
        const IsoSpatialPipe(100),
        IsoSpatialTurn(degrees: 0, towards: up),
        const IsoSpatialPipe(100)
      ],
      for (final n in [0.0, -1.0, double.nan, double.infinity])
        [const IsoSpatialPipe(100), IsoSpatialPipe(n)],
    ];
    for (final steps in bad) {
      expect(() => planIsoSpatialRoute(steps, heading: right),
          throwsArgumentError);
    }
    expect(valid.end, before);
    expect(valid.segments, hasLength(1));
  });
  test(
      'spatial metadata round-trips without rounding and rejects damaged coordinates',
      () {
    const v = IsoSpatialVector(.125, -.5, 3.75);
    expect(IsoSpatialVector.fromJson(v.toJson()), v);
    for (final raw in <Object?>[
      null,
      {},
      [],
      [1, 2],
      ['1', 2, 3],
      [double.nan, 2, 3],
      [1, double.infinity, 3]
    ]) {
      expect(IsoSpatialVector.fromJson(raw), isNull);
    }
    expect(() => const IsoSpatialVector(double.nan, 0, 1).toJson(),
        throwsArgumentError);
    expect(() => IsoSpatialVector.gridHeading(6), throwsRangeError);
    expect(() => planIsoSpatialRoute([], heading: IsoSpatialVector.zero),
        throwsArgumentError);
  });
}
