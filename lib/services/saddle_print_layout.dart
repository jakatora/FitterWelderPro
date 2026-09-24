import 'dart:math' as math;
import 'saddle_geometry.dart';

class SaddlePrintTooLarge implements Exception {
  final int pages;
  const SaddlePrintTooLarge(this.pages);
  @override
  String toString() => 'Template needs $pages tiles; limit is 100';
}

class SaddlePrintTile {
  final int row;
  final int column;
  final double startX, endX, startY, endY;
  const SaddlePrintTile(
      this.row, this.column, this.startX, this.endX, this.startY, this.endY);
}

/// All dimensions in physical millimetres. No fit-to-page scaling.
class SaddlePrintLayout {
  static const widthMm = 260.0;
  static const heightMm = 140.0;
  static const overlapMm = 5.0;
  static const maxTiles = 100;
  final SaddleGeometry geometry;
  late final int columns;
  late final int rows;
  late final List<SaddlePrintTile> tiles;

  SaddlePrintLayout(this.geometry) {
    final height = math.max(1.0, geometry.maxDepthMm);
    columns = math.max(1,
        ((geometry.stripLengthMm - overlapMm) / (widthMm - overlapMm)).ceil());
    rows = math.max(1, ((height - overlapMm) / (heightMm - overlapMm)).ceil());
    if (columns * rows > maxTiles) throw SaddlePrintTooLarge(columns * rows);
    tiles = List.unmodifiable([
      for (var row = 0; row < rows; row++)
        for (var column = 0; column < columns; column++)
          SaddlePrintTile(
              row,
              column,
              column * (widthMm - overlapMm),
              math.min(column * (widthMm - overlapMm) + widthMm,
                  geometry.stripLengthMm),
              row * (heightMm - overlapMm),
              math.min(row * (heightMm - overlapMm) + heightMm, height)),
    ]);
  }
}
