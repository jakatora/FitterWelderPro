import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter_test/flutter_test.dart';
import 'package:cut_list_app/domain/iso_notebook/spatial_route.dart';
import 'package:cut_list_app/screens/iso_notebook_screen.dart';
import '../support/iso_sketch_fixture.dart';
import '../support/iso_spatial_fixture.dart';

void main() {
  test(
      'format 5 preserves axial fitting direction without upgrading format 4 drawings',
      () {
    final sketch = spatialSketch()..['format'] = 5;
    final items = sketch['items'] as List;
    final direction = (items.first as Map)['spatialDirection'];
    final valve = items.whereType<Map>().firstWhere(
        (c) => c['tool'] == 'gateValve',
        orElse: () =>
            items.whereType<Map>().firstWhere((c) => c['kind'] == 'comp'));
    valve['tool'] = 'ballValve';
    valve['elbowSubtype'] = null;
    valve.remove('spatialBend');
    valve['spatialDirection'] = direction;
    expect(
        jsonDecode(isoSketchRoundTripForTesting(jsonEncode(sketch))), sketch);
    sketch['format'] = 4;
    expect(() => isoSketchRoundTripForTesting(jsonEncode(sketch)),
        throwsA(isA<IsoSketchFormatException>()));
    sketch['format'] = 5;
    for (final raw in [
      <num>[0, 0, 0],
      <num>[2, 0, 0],
      <num>[1, 2],
      <String>['1', '0', '0']
    ]) {
      valve['spatialDirection'] = raw;
      expect(isoSketchSkippedItemsForTesting(jsonEncode(sketch)), 1);
    }
    valve['spatialDirection'] = direction;
    valve['tool'] = 'northArrow';
    expect(isoSketchSkippedItemsForTesting(jsonEncode(sketch)), 1);
  });

  test(
      'format 4 preserves full precision spatial geometry and legacy CUT fields',
      () {
    final original = spatialSketch();
    final encoded = isoSketchRoundTripForTesting(jsonEncode(original));
    expect(jsonDecode(encoded), original);
    expect(isoSketchRoundTripForTesting(encoded), encoded);
    expect(isoSketchSkippedItemsForTesting(encoded), 0);
    expect(kIsoSketchFormatVersion, 5);
  });
  test('legacy sketches retain their original format and fields', () {
    final old = representativeIsoSketch();
    expect(jsonDecode(isoSketchRoundTripForTesting(jsonEncode(old))), old);
  });
  test(
      'spatial geometry in an older declared format is refused rather than silently dropped',
      () {
    final sketch = spatialSketch()..['format'] = 3;
    expect(() => isoSketchRoundTripForTesting(jsonEncode(sketch)),
        throwsA(isA<IsoSketchFormatException>()));
  });
  for (final raw in <Object?>[
    [0, 0, 0],
    [2, 0, 0],
    [0, 1],
    ['1', 0, 0],
    {'i': 1},
    [0, 0, 1]
  ]) {
    test('damaged or reversed segment direction is counted as unreadable: $raw',
        () {
      final sketch = spatialSketch();
      ((sketch['items'] as List).first as Map)['spatialDirection'] = raw;
      expect(isoSketchSkippedItemsForTesting(jsonEncode(sketch)), 1);
    });
  }
  test(
      'non-elbow tools and wrong actual bend angles cannot carry elbow metadata',
      () {
    for (final tool in ['elbow90', 'gateValve', 'tee']) {
      final sketch = spatialSketch();
      final item = (sketch['items'] as List)
          .whereType<Map>()
          .firstWhere((c) => c['tool'] == 'elbow45');
      item['tool'] = tool;
      expect(isoSketchSkippedItemsForTesting(jsonEncode(sketch)), 1);
    }
  });
  test('unknown spatial fields cannot disappear on the next autosave', () {
    final sketch = spatialSketch();
    final item = (sketch['items'] as List)
        .whereType<Map>()
        .firstWhere((c) => c['tool'] == 'elbow45');
    (item['spatialBend'] as Map)['futureField'] = 1;
    expect(isoSketchSkippedItemsForTesting(jsonEncode(sketch)), 1);
  });
  test('projected elbow arc is tangent to both actual spatial rays', () {
    final a = IsoSpatialVector.gridHeading(0),
        b = a.turnTowards(IsoSpatialVector.gridHeading(1), 45);
    final bend = IsoSpatialElbow(incoming: a, outgoing: b),
        arc = bend.projectedArc(tangentMm: 10, samples: 128);
    expect(bend.degrees, closeTo(45, 1e-9));
    expect(arc.first.x, -10);
    expect(arc.first.y, 0);
    expect(arc.last.x, closeTo(b.projected.x * 10, 1e-9));
    expect(arc.last.y, closeTo(b.projected.y * 10, 1e-9));
    final firstDx = arc[1].x - arc[0].x, firstDy = arc[1].y - arc[0].y;
    expect(math.atan2(firstDy, firstDx), closeTo(0, .01));
    final lastDx = arc.last.x - arc[arc.length - 2].x,
        lastDy = arc.last.y - arc[arc.length - 2].y;
    expect(math.atan2(lastDy, lastDx),
        closeTo(math.atan2(b.projected.y, b.projected.x), .01));
  });
  test('elbow metadata rejects invalid rays instead of repairing their scale',
      () {
    expect(
        IsoSpatialElbow.fromJson({
          'incoming': [2, 0, 0],
          'outgoing': [0, 0, -1]
        }),
        isNull);
    expect(
        IsoSpatialElbow.fromJson({
          'incoming': [1, 0, 0],
          'outgoing': [-1, 0, 0]
        }),
        isNull);
  });
}
