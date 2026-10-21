import 'package:cut_list_app/domain/iso_notebook/spatial_route.dart';
import 'iso_sketch_fixture.dart';

Map<String, Object?> spatialSketch() {
  final sketch = representativeIsoSketch()..['format'] = 4;
  final items = sketch['items'] as List<Object?>;
  final pipe = items.first as Map<String, Object?>;
  final right = IsoSpatialVector.gridHeading(0),
      up = IsoSpatialVector.gridHeading(1);
  final direction = right.turnTowards(up, 45);
  final p = direction.projected;
  pipe['b'] = <double>[64 + p.x * 100, isoRow4 + p.y * 100];
  pipe['spatialDirection'] = direction.toJson();
  final elbow =
      items.whereType<Map>().firstWhere((c) => c['tool'] == 'elbow45');
  elbow['spatialBend'] =
      IsoSpatialElbow(incoming: right, outgoing: direction).toJson();
  return sketch;
}
