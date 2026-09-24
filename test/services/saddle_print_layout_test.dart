import 'package:flutter_test/flutter_test.dart';
import 'package:cut_list_app/services/saddle_geometry.dart';
import 'package:cut_list_app/services/saddle_print_layout.dart';

void main() {
  test('15 degree profile needs two columns and three rows without scaling',
      () {
    final geometry =
        SaddleGeometry(headerOdMm: 200, branchOdMm: 100, angleDeg: 15);
    final layout = SaddlePrintLayout(geometry);
    expect(layout.columns, 2);
    expect(layout.rows, 3);
    expect(layout.tiles, hasLength(6));
    expect(layout.tiles.first.startX, 0);
    expect(layout.tiles.first.endX, 260);
    expect(layout.tiles[1].startX, 255);
    expect(layout.tiles[2].startY, 135);
    expect(layout.tiles.last.endX, closeTo(314.1592653589793, 1e-8));
    expect(layout.tiles.last.endY, closeTo(373.2050807568877, 1e-8));
    for (final tile in layout.tiles) {
      expect(tile.endX - tile.startX, lessThanOrEqualTo(260));
      expect(tile.endY - tile.startY, lessThanOrEqualTo(140));
      final line = geometry.profileBetween(tile.startX, tile.endX);
      expect(line.first.xMm, tile.startX);
      expect(line.last.xMm, tile.endX);
    }
  });

  test('100/60 perpendicular profile fits one physical tile', () {
    final layout = SaddlePrintLayout(
        SaddleGeometry(headerOdMm: 100, branchOdMm: 60, angleDeg: 90));
    expect(layout.tiles, hasLength(1));
    expect(layout.tiles.single.endY, closeTo(10, 1e-9));
  });

  test(
      'excessive page counts fail explicitly instead of clipping or exhausting memory',
      () {
    final g = SaddleGeometry(headerOdMm: 2000, branchOdMm: 2000, angleDeg: 15);
    expect(() => SaddlePrintLayout(g), throwsA(isA<SaddlePrintTooLarge>()));
  });
}
