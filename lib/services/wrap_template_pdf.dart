/// Szablon „owijany” na rurze, drukowany 1:1: krzywa cięcia y(x), gdzie x
/// to łuk po obwodzie (nie cięciwa), a y — odsunięcie od linii bazowej
/// prostopadłej do osi rury. Strona 1: tabela rzędnych i instrukcja; dalej
/// kafle A4 (pozioma) 260 × 140 mm z zakładką 5 mm i podziałkami 100 mm
/// do sprawdzenia skali wydruku.
///
/// Ogólny — używa go kolano segmentowe; szablon siodła ma własny,
/// starszy generator (saddle_template.dart), którego nie ruszamy.
///
/// Drugi generator w tym pliku — [buildFlatTemplatePdf] — drukuje 1:1
/// płaskie rozwinięcia blach (stożki, przejścia kwadrat–koło): dowolne
/// obrysy w mm, kafle A4 albo A3 z zakładką, opisami sklejania i tymi
/// samymi podziałkami 100 mm. Kafelkowanie wspólne ([WrapTileLayout]).
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

class WrapTemplateSpec {
  final String title;
  final List<String> summaryLines;
  final double stripLengthMm;
  final double maxDepthMm;
  final double Function(double xMm) depthAt;
  final List<String> tableHeaders;
  final List<List<String>> tableRows;
  final List<String> instructions;
  final String note;

  /// Krótka podpowiedź na każdym kaflu (orientacja).
  final String tileHint;

  /// Pionowe kreski podziału obwodu (np. 16 = co 22,5°); 0 = bez.
  final int divisions;

  const WrapTemplateSpec({
    required this.title,
    required this.summaryLines,
    required this.stripLengthMm,
    required this.maxDepthMm,
    required this.depthAt,
    required this.tableHeaders,
    required this.tableRows,
    required this.instructions,
    required this.note,
    required this.tileHint,
    this.divisions = 16,
  });
}

class WrapTile {
  final int row;
  final int column;
  final double startX, endX, startY, endY;
  const WrapTile(
      this.row, this.column, this.startX, this.endX, this.startY, this.endY);
}

/// Format arkusza kafli (strona pozioma).
enum TemplatePaper {
  /// A4 poziomo, pole rysunku 260 × 140 mm (jak szablon kolana).
  a4(260, 140, 'A4'),

  /// A3 poziomo, pole rysunku 380 × 230 mm.
  a3(380, 230, 'A3');

  const TemplatePaper(this.tileWidthMm, this.tileHeightMm, this.label);
  final double tileWidthMm;
  final double tileHeightMm;
  final String label;

  PdfPageFormat get pageFormat => this == TemplatePaper.a4
      ? PdfPageFormat.a4.landscape
      : PdfPageFormat.a3.landscape;
}

/// Podział na kafle: wszystkie wymiary w milimetrach, bez skalowania.
class WrapTileLayout {
  static const widthMm = 260.0;
  static const heightMm = 140.0;
  static const overlapMm = 5.0;

  /// Zapas papieru nad krzywą, mm.
  static const headroomMm = 10.0;
  static const maxTiles = 100;

  final double stripLengthMm;
  final double heightNeededMm;

  /// Pole rysunku jednego kafla, mm (A4: [widthMm] × [heightMm]).
  final double tileWidthMm;
  final double tileHeightMm;
  late final int columns;
  late final int rows;
  late final List<WrapTile> tiles;

  /// Pasek szablonu owijanego: długość × (głębokość + zapas), kafle A4.
  WrapTileLayout(double stripLengthMm, double maxDepthMm)
      : this._(stripLengthMm, math.max(1.0, maxDepthMm) + headroomMm, widthMm,
            heightMm);

  /// Dowolny prostokąt [areaWidthMm] × [areaHeightMm] (np. rozwinięcie
  /// blachy z marginesem), kafle w formacie [paper].
  WrapTileLayout.area(double areaWidthMm, double areaHeightMm,
      {TemplatePaper paper = TemplatePaper.a4})
      : this._(
            areaWidthMm, areaHeightMm, paper.tileWidthMm, paper.tileHeightMm);

  WrapTileLayout._(this.stripLengthMm, this.heightNeededMm, this.tileWidthMm,
      this.tileHeightMm) {
    columns = _count(stripLengthMm, tileWidthMm);
    rows = _count(heightNeededMm, tileHeightMm);
    if (columns * rows > maxTiles) {
      throw ArgumentError('Template needs ${columns * rows} tiles; limit is '
          '$maxTiles');
    }
    tiles = List.unmodifiable([
      for (var r = 0; r < rows; r++)
        for (var c = 0; c < columns; c++)
          WrapTile(
            r,
            c,
            c * (tileWidthMm - overlapMm),
            math.min(
                c * (tileWidthMm - overlapMm) + tileWidthMm, stripLengthMm),
            r * (tileHeightMm - overlapMm),
            math.min(
                r * (tileHeightMm - overlapMm) + tileHeightMm, heightNeededMm),
          ),
    ]);
  }

  static int _count(double length, double tile) =>
      math.max(1, ((length - overlapMm) / (tile - overlapMm)).ceil());

  /// Ile kartek zająłby prostokąt (bez rzucania wyjątku przy limicie).
  static int sheetCount(double areaWidthMm, double areaHeightMm,
          {TemplatePaper paper = TemplatePaper.a4}) =>
      _count(areaWidthMm, paper.tileWidthMm) *
      _count(areaHeightMm, paper.tileHeightMm);
}

final PdfColor _ink = PdfColor.fromHex('#17252A');
final PdfColor _accent = PdfColor.fromHex('#C2410C');
final PdfColor _grid = PdfColor.fromHex('#C7CDD0');
const double _mm = PdfPageFormat.mm;

Future<Uint8List> buildWrapTemplatePdf(
  WrapTemplateSpec spec, {
  required pw.Font font,
  required pw.Font bold,
  required bool en,
  required DateTime generatedAt,
}) async {
  String tr(String pl, String e) => en ? e : pl;
  final layout = WrapTileLayout(spec.stripLengthMm, spec.maxDepthMm);
  final doc = pw.Document(theme: pw.ThemeData.withFont(base: font, bold: bold));
  pw.Widget text(String s,
          {double size = 9, PdfColor? color, bool b = false}) =>
      pw.Text(s,
          style: pw.TextStyle(
              fontSize: size,
              color: color ?? _ink,
              fontWeight: b ? pw.FontWeight.bold : pw.FontWeight.normal));
  pw.Widget cell(String s, {bool head = false}) => pw.Padding(
        padding: const pw.EdgeInsets.symmetric(vertical: 2.2, horizontal: 5),
        child: text(s, size: 8.5, b: head),
      );
  String two(int v) => v.toString().padLeft(2, '0');
  final stamp = '${generatedAt.year}-${two(generatedAt.month)}-'
      '${two(generatedAt.day)} ${two(generatedAt.hour)}:${two(generatedAt.minute)}';

  doc.addPage(pw.Page(
    pageFormat: PdfPageFormat.a4,
    margin: const pw.EdgeInsets.all(12 * _mm),
    build: (_) => pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        text('FITTER WELDER PRO', size: 11, color: _accent, b: true),
        text(spec.title, size: 18, b: true),
        text(stamp, size: 8),
        pw.SizedBox(height: 8),
        for (final l in spec.summaryLines) text(l, size: 10),
        pw.SizedBox(height: 8),
        pw.Table(
          border: pw.TableBorder.all(color: _grid, width: .4),
          children: [
            pw.TableRow(
              decoration: pw.BoxDecoration(color: PdfColor.fromHex('#F3EDE9')),
              children: [
                for (final h in spec.tableHeaders) cell(h, head: true)
              ],
            ),
            for (final row in spec.tableRows)
              pw.TableRow(children: [for (final c in row) cell(c)]),
          ],
        ),
        pw.SizedBox(height: 10),
        text(tr('Druk i trasowanie', 'Printing and marking'),
            size: 12, color: _accent, b: true),
        pw.SizedBox(height: 3),
        text(tr(
            'Strony 2+ drukuj w rozmiarze rzeczywistym (100%), bez dopasowania do strony. '
                'Sprawdź linijką podziałki 100 mm na każdej kartce.',
            'Print pages 2+ at actual size (100%), fit-to-page off. '
                'Check the 100 mm bars with a ruler on every sheet.')),
        text(tr(
            'Kafle: ${layout.columns} kolumn × ${layout.rows} rzędów, zakładka 5 mm (linie przerywane). '
                'Łącz po siatce, nie po brzegach papieru.',
            'Tiles: ${layout.columns} columns × ${layout.rows} rows, 5 mm overlap (dashed lines). '
                'Join on the grid, not on paper edges.')),
        for (final i in spec.instructions) text(i),
        pw.Spacer(),
        text(spec.note, size: 8),
      ],
    ),
  ));

  for (final tile in layout.tiles) {
    doc.addPage(pw.Page(
      pageFormat: PdfPageFormat.a4.landscape,
      margin: const pw.EdgeInsets.all(10 * _mm),
      build: (_) => pw.Stack(children: [
        pw.Positioned(
          left: 0,
          top: 0,
          right: 0,
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              text(
                  'FITTER WELDER PRO | R${tile.row + 1} C${tile.column + 1} | 1:1 / 100%',
                  size: 11,
                  color: _accent,
                  b: true),
              text(
                  'X: ${tile.startX.toStringAsFixed(1)}–${tile.endX.toStringAsFixed(1)} mm'
                  ' | Y: ${tile.startY.toStringAsFixed(1)}–${tile.endY.toStringAsFixed(1)} mm',
                  size: 8.5),
              text(spec.tileHint, size: 8),
            ],
          ),
        ),
        pw.Positioned(
          left: 0,
          top: 20 * _mm,
          child: pw.SizedBox(
            width: WrapTileLayout.widthMm * _mm,
            height: WrapTileLayout.heightMm * _mm,
            child: pw.CustomPaint(
              size: const PdfPoint(
                  WrapTileLayout.widthMm * _mm, WrapTileLayout.heightMm * _mm),
              painter: (canvas, size) => _drawTile(canvas, spec, layout, tile),
            ),
          ),
        ),
        pw.Positioned(
          left: 265 * _mm,
          top: 25 * _mm,
          child: pw.SizedBox(
            width: 10 * _mm,
            height: 106 * _mm,
            child: pw.Stack(children: [
              pw.CustomPaint(
                  size: const PdfPoint(8 * _mm, 100 * _mm),
                  painter: (canvas, size) => _ruler(canvas, vertical: true)),
              pw.Positioned(
                  left: 0, top: 101 * _mm, child: text('100 mm', size: 7)),
            ]),
          ),
        ),
        pw.Positioned(
          left: 0,
          top: 165 * _mm,
          child: pw.SizedBox(
            width: 100 * _mm,
            height: 12 * _mm,
            child: pw.Column(children: [
              pw.CustomPaint(
                  size: const PdfPoint(100 * _mm, 5 * _mm),
                  painter: (canvas, size) => _ruler(canvas, vertical: false)),
              text('100 mm', size: 8),
            ]),
          ),
        ),
      ]),
    ));
  }
  return doc.save();
}

void _ruler(PdfGraphics canvas, {required bool vertical}) {
  canvas.setColor(_ink);
  canvas.setLineWidth(.6);
  if (vertical) {
    canvas.drawLine(3 * _mm, 0, 3 * _mm, 100 * _mm);
  } else {
    canvas.drawLine(0, 3 * _mm, 100 * _mm, 3 * _mm);
  }
  canvas.strokePath();
  for (var i = 0; i <= 100; i += 10) {
    final tick = i % 50 == 0 ? 2.0 : 1.0;
    if (vertical) {
      canvas.drawLine((3 - tick) * _mm, i * _mm, (3 + tick) * _mm, i * _mm);
    } else {
      canvas.drawLine(i * _mm, (3 - tick) * _mm, i * _mm, (3 + tick) * _mm);
    }
    canvas.strokePath();
  }
}

void _drawTile(PdfGraphics canvas, WrapTemplateSpec spec, WrapTileLayout layout,
    WrapTile t) {
  final w = (t.endX - t.startX) * _mm;
  final h = (t.endY - t.startY) * _mm;
  canvas.saveContext();
  canvas.drawRect(0, 0, w, h);
  canvas.clipPath();
  // Siatka co 10 mm (cienka) i 50 mm (grubsza).
  canvas.setColor(_grid);
  for (final step in [10.0, 50.0]) {
    canvas.setLineWidth(step == 50 ? .5 : .15);
    for (var x = (t.startX / step).ceil() * step; x <= t.endX; x += step) {
      canvas.drawLine((x - t.startX) * _mm, 0, (x - t.startX) * _mm, h);
    }
    for (var y = (t.startY / step).ceil() * step; y <= t.endY; y += step) {
      canvas.drawLine(0, (y - t.startY) * _mm, w, (y - t.startY) * _mm);
    }
    canvas.strokePath();
  }
  // Zakładka 5 mm.
  canvas.setColor(_ink);
  canvas.setLineWidth(.5);
  canvas.setLineDashPattern([3, 2]);
  if (t.column > 0) canvas.drawLine(5 * _mm, 0, 5 * _mm, h);
  if (t.column < layout.columns - 1) {
    canvas.drawLine(w - 5 * _mm, 0, w - 5 * _mm, h);
  }
  if (t.row > 0) canvas.drawLine(0, 5 * _mm, w, 5 * _mm);
  if (t.row < layout.rows - 1) canvas.drawLine(0, h - 5 * _mm, w, h - 5 * _mm);
  canvas.strokePath();
  canvas.setLineDashPattern();
  // Podział obwodu (pionowe kreski), grubsze co ćwiartkę.
  if (spec.divisions > 0) {
    for (var i = 0; i <= spec.divisions; i++) {
      final x = spec.stripLengthMm * i / spec.divisions;
      if (x < t.startX || x > t.endX) continue;
      final quarter = spec.divisions % 4 == 0 && i % (spec.divisions ~/ 4) == 0;
      canvas.setColor(quarter ? _accent : _ink);
      canvas.setLineWidth(quarter ? .6 : .3);
      canvas.drawLine((x - t.startX) * _mm, 0, (x - t.startX) * _mm, h);
      canvas.strokePath();
    }
  }
  // Linia bazowa Y = 0.
  if (t.startY <= 0) {
    canvas.setColor(_ink);
    canvas.setLineWidth(1.0);
    canvas.drawLine(0, (0 - t.startY) * _mm, w, (0 - t.startY) * _mm);
    canvas.strokePath();
  }
  // Krzywa cięcia, próbkowana co 0,5 mm.
  canvas.setColor(_accent);
  canvas.setLineWidth(.8);
  var first = true;
  for (var x = t.startX; x <= t.endX + 1e-9; x += .5) {
    final xx = math.min(x, t.endX);
    final y = spec.depthAt(xx);
    final px = (xx - t.startX) * _mm, py = (y - t.startY) * _mm;
    if (first) {
      canvas.moveTo(px, py);
      first = false;
    } else {
      canvas.lineTo(px, py);
    }
  }
  canvas.strokePath();
  canvas.restoreContext();
  canvas.setColor(_ink);
  canvas.setLineWidth(.5);
  canvas.drawRect(0, 0, w, h);
  canvas.strokePath();
}

// ─── Płaskie rozwinięcia blach ───────────────────────────────────────────────

/// Opis punktu na szablonie (np. „3'”, „A”) — współrzędne w mm kształtu.
class FlatTemplateLabel {
  final double xMm;
  final double yMm;
  final String text;
  const FlatTemplateLabel(this.xMm, this.yMm, this.text);
}

/// Jeden kształt do wydruku 1:1 (część rozwinięcia). Układ: lewy dolny róg
/// prostokąta opisanego = (0, 0), X w prawo, Y w górę, mm.
class FlatTemplateShape {
  /// Np. „Część 1 (× 2)”.
  final String name;
  final double widthMm;
  final double heightMm;

  /// Linie cięcia — wielokąty zamknięte.
  final List<List<math.Point<double>>> cutLines;

  /// Linie gięcia / tworzących — łamane, przerywane.
  final List<List<math.Point<double>>> bendLines;

  /// Linie pomocnicze (naddatek) — wielokąty zamknięte, przerywane.
  final List<List<math.Point<double>>> dashedLines;
  final List<FlatTemplateLabel> labels;

  const FlatTemplateShape({
    required this.name,
    required this.widthMm,
    required this.heightMm,
    required this.cutLines,
    this.bendLines = const [],
    this.dashedLines = const [],
    this.labels = const [],
  });
}

class FlatTemplateTable {
  final String title;
  final List<String> headers;
  final List<List<String>> rows;
  const FlatTemplateTable(this.title, this.headers, this.rows);
}

class FlatTemplateSpec {
  final String title;
  final List<String> summaryLines;
  final List<FlatTemplateTable> tables;
  final List<String> instructions;
  final String note;
  final List<FlatTemplateShape> shapes;
  final TemplatePaper paper;

  /// Margines papieru wokół kształtu, mm.
  static const marginMm = 10.0;

  const FlatTemplateSpec({
    required this.title,
    required this.summaryLines,
    required this.tables,
    required this.instructions,
    required this.note,
    required this.shapes,
    this.paper = TemplatePaper.a4,
  });

  /// Liczba kartek z kaflami (bez stron z tabelami).
  int get sheetCount => flatTemplateSheetCount(
      [for (final s in shapes) (s.widthMm, s.heightMm)], paper);
}

/// Liczba kartek z kaflami dla kształtów [sizesMm] (szer., wys.) — bez
/// budowania PDF.
int flatTemplateSheetCount(
        Iterable<(double, double)> sizesMm, TemplatePaper paper) =>
    sizesMm.fold(
        0,
        (s, wh) =>
            s +
            WrapTileLayout.sheetCount(wh.$1 + 2 * FlatTemplateSpec.marginMm,
                wh.$2 + 2 * FlatTemplateSpec.marginMm,
                paper: paper));

Future<Uint8List> buildFlatTemplatePdf(
  FlatTemplateSpec spec, {
  required pw.Font font,
  required pw.Font bold,
  required bool en,
  required DateTime generatedAt,
}) async {
  String tr(String pl, String e) => en ? e : pl;
  final doc = pw.Document(theme: pw.ThemeData.withFont(base: font, bold: bold));
  pw.Widget text(String s,
          {double size = 9, PdfColor? color, bool b = false}) =>
      pw.Text(s,
          style: pw.TextStyle(
              fontSize: size,
              color: color ?? _ink,
              fontWeight: b ? pw.FontWeight.bold : pw.FontWeight.normal));
  pw.Widget cell(String s, {bool head = false}) => pw.Padding(
        padding: const pw.EdgeInsets.symmetric(vertical: 1.8, horizontal: 4),
        child: text(s, size: 8, b: head),
      );
  String two(int v) => v.toString().padLeft(2, '0');
  final stamp = '${generatedAt.year}-${two(generatedAt.month)}-'
      '${two(generatedAt.day)} ${two(generatedAt.hour)}:${two(generatedAt.minute)}';
  const m = FlatTemplateSpec.marginMm;
  final layouts = [
    for (final s in spec.shapes)
      WrapTileLayout.area(s.widthMm + 2 * m, s.heightMm + 2 * m,
          paper: spec.paper),
  ];
  final sheets = layouts.fold(0, (s, l) => s + l.tiles.length);

  doc.addPage(pw.MultiPage(
    pageFormat: PdfPageFormat.a4,
    margin: const pw.EdgeInsets.all(12 * _mm),
    build: (_) => [
      text('FITTER WELDER PRO', size: 11, color: _accent, b: true),
      text(spec.title, size: 18, b: true),
      text(stamp, size: 8),
      pw.SizedBox(height: 8),
      for (final l in spec.summaryLines) text(l, size: 10),
      for (final t in spec.tables) ...[
        pw.SizedBox(height: 10),
        text(t.title, size: 11, color: _accent, b: true),
        pw.SizedBox(height: 3),
        pw.Table(
          border: pw.TableBorder.all(color: _grid, width: .4),
          children: [
            pw.TableRow(
              decoration: pw.BoxDecoration(color: PdfColor.fromHex('#F3EDE9')),
              children: [for (final h in t.headers) cell(h, head: true)],
            ),
            for (final row in t.rows)
              pw.TableRow(children: [for (final c in row) cell(c)]),
          ],
        ),
      ],
      pw.SizedBox(height: 10),
      text(tr('Druk i trasowanie', 'Printing and marking'),
          size: 12, color: _accent, b: true),
      pw.SizedBox(height: 3),
      text(tr(
          'Kafle (${spec.paper.label} poziomo, razem $sheets ark.) drukuj w rozmiarze rzeczywistym (100%), '
              'bez dopasowania do strony. Sprawdź linijką podziałki 100 mm na każdej kartce.',
          'Print the tiles (${spec.paper.label} landscape, $sheets sheets in total) at actual size (100%), '
              'fit-to-page off. Check the 100 mm bars with a ruler on every sheet.')),
      text(tr(
          'Zakładka 5 mm (linie przerywane) — sklejaj po siatce 10 mm, nie po brzegach papieru. '
              'Każda kartka ma w nagłówku sąsiadów: R = rząd (od dołu), K = kolumna (od lewej).',
          '5 mm overlap (dashed lines) — join on the 10 mm grid, not on paper edges. '
              'Each sheet lists its neighbours in the header: R = row (from the bottom), C = column (from the left).')),
      for (final i in spec.instructions) text(i),
      pw.SizedBox(height: 8),
      text(spec.note, size: 8),
    ],
  ));

  for (var s = 0; s < spec.shapes.length; s++) {
    final shape = spec.shapes[s];
    final layout = layouts[s];
    final tw = layout.tileWidthMm, th = layout.tileHeightMm;
    for (final tile in layout.tiles) {
      String id(int r, int c) =>
          tr('R${r + 1} K${c + 1}', 'R${r + 1} C${c + 1}');
      final neighbours = <String>[
        if (tile.column > 0)
          '${tr('lewo', 'left')} ${id(tile.row, tile.column - 1)}',
        if (tile.column < layout.columns - 1)
          '${tr('prawo', 'right')} ${id(tile.row, tile.column + 1)}',
        if (tile.row < layout.rows - 1)
          '${tr('góra', 'up')} ${id(tile.row + 1, tile.column)}',
        if (tile.row > 0)
          '${tr('dół', 'down')} ${id(tile.row - 1, tile.column)}',
      ];
      final w = tile.endX - tile.startX, h = tile.endY - tile.startY;
      final labels = [
        for (final l in shape.labels)
          if (l.xMm + m >= tile.startX &&
              l.xMm + m <= tile.endX - 4 &&
              l.yMm + m >= tile.startY + 2 &&
              l.yMm + m <= tile.endY)
            l,
      ];
      doc.addPage(pw.Page(
        pageFormat: spec.paper.pageFormat,
        margin: const pw.EdgeInsets.all(10 * _mm),
        build: (_) => pw.Stack(children: [
          pw.Positioned(
            left: 0,
            top: 0,
            right: 0,
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                text(
                    'FITTER WELDER PRO | ${shape.name} | ${id(tile.row, tile.column)} | 1:1 / 100%',
                    size: 11,
                    color: _accent,
                    b: true),
                text(
                    'X: ${(tile.startX - m).toStringAsFixed(0)}–${(tile.endX - m).toStringAsFixed(0)} mm'
                    ' | Y: ${(tile.startY - m).toStringAsFixed(0)}–${(tile.endY - m).toStringAsFixed(0)} mm'
                    '${neighbours.isEmpty ? '' : ' | ${tr('sklej', 'join')}: ${neighbours.join(', ')}'}',
                    size: 8.5),
              ],
            ),
          ),
          pw.Positioned(
            left: 0,
            top: 20 * _mm,
            child: pw.SizedBox(
              width: tw * _mm,
              height: th * _mm,
              child: pw.Stack(
                overflow: pw.Overflow.clip,
                children: [
                  pw.CustomPaint(
                    size: PdfPoint(tw * _mm, th * _mm),
                    painter: (canvas, size) =>
                        _drawFlatTile(canvas, shape, layout, tile),
                  ),
                  for (final l in labels)
                    pw.Positioned(
                      left: (l.xMm + m - tile.startX) * _mm + 1.2 * _mm,
                      top: (th - (l.yMm + m - tile.startY)) * _mm - 3.4 * _mm,
                      child: text(l.text, size: 6.5),
                    ),
                  if (tile.column < layout.columns - 1)
                    pw.Positioned(
                      left: (w - 4.6) * _mm,
                      top: (th - h / 2) * _mm,
                      child: text(id(tile.row, tile.column + 1), size: 5.5),
                    ),
                  if (tile.row < layout.rows - 1)
                    pw.Positioned(
                      left: w / 2 * _mm,
                      top: (th - h) * _mm + 0.6 * _mm,
                      child: text(id(tile.row + 1, tile.column), size: 5.5),
                    ),
                ],
              ),
            ),
          ),
          pw.Positioned(
            left: (tw + 5) * _mm,
            top: 25 * _mm,
            child: pw.SizedBox(
              width: 10 * _mm,
              height: 106 * _mm,
              child: pw.Stack(children: [
                pw.CustomPaint(
                    size: const PdfPoint(8 * _mm, 100 * _mm),
                    painter: (canvas, size) => _ruler(canvas, vertical: true)),
                pw.Positioned(
                    left: 0, top: 101 * _mm, child: text('100 mm', size: 7)),
              ]),
            ),
          ),
          pw.Positioned(
            left: 0,
            top: (20 + th + 5) * _mm,
            child: pw.SizedBox(
              width: 100 * _mm,
              height: 12 * _mm,
              child: pw.Column(children: [
                pw.CustomPaint(
                    size: const PdfPoint(100 * _mm, 5 * _mm),
                    painter: (canvas, size) => _ruler(canvas, vertical: false)),
                text('100 mm', size: 8),
              ]),
            ),
          ),
        ]),
      ));
    }
  }
  return doc.save();
}

void _drawFlatTile(PdfGraphics canvas, FlatTemplateShape shape,
    WrapTileLayout layout, WrapTile t) {
  const m = FlatTemplateSpec.marginMm;
  final w = (t.endX - t.startX) * _mm;
  final h = (t.endY - t.startY) * _mm;
  double px(double x) => (x + m - t.startX) * _mm;
  double py(double y) => (y + m - t.startY) * _mm;
  void poly(List<math.Point<double>> pts, {bool close = false}) {
    if (pts.length < 2) return;
    canvas.moveTo(px(pts.first.x), py(pts.first.y));
    for (final p in pts.skip(1)) {
      canvas.lineTo(px(p.x), py(p.y));
    }
    if (close) canvas.closePath();
    canvas.strokePath();
  }

  canvas.saveContext();
  canvas.drawRect(0, 0, w, h);
  canvas.clipPath();
  // Siatka co 10 mm (cienka) i 50 mm (grubsza), od narożnika kształtu.
  canvas.setColor(_grid);
  for (final step in [10.0, 50.0]) {
    canvas.setLineWidth(step == 50 ? .5 : .15);
    for (var x = ((t.startX - m) / step).ceil() * step + m;
        x <= t.endX;
        x += step) {
      canvas.drawLine((x - t.startX) * _mm, 0, (x - t.startX) * _mm, h);
    }
    for (var y = ((t.startY - m) / step).ceil() * step + m;
        y <= t.endY;
        y += step) {
      canvas.drawLine(0, (y - t.startY) * _mm, w, (y - t.startY) * _mm);
    }
    canvas.strokePath();
  }
  // Zakładka 5 mm.
  canvas.setColor(_ink);
  canvas.setLineWidth(.5);
  canvas.setLineDashPattern([3, 2]);
  if (t.column > 0) canvas.drawLine(5 * _mm, 0, 5 * _mm, h);
  if (t.column < layout.columns - 1) {
    canvas.drawLine(w - 5 * _mm, 0, w - 5 * _mm, h);
  }
  if (t.row > 0) canvas.drawLine(0, 5 * _mm, w, 5 * _mm);
  if (t.row < layout.rows - 1) canvas.drawLine(0, h - 5 * _mm, w, h - 5 * _mm);
  canvas.strokePath();
  // Linie gięcia / tworzących.
  canvas.setLineWidth(.35);
  canvas.setLineDashPattern([4, 2]);
  for (final l in shape.bendLines) {
    poly(l);
  }
  // Naddatek.
  canvas.setColor(_accent);
  canvas.setLineWidth(.5);
  canvas.setLineDashPattern([2, 2]);
  for (final l in shape.dashedLines) {
    poly(l, close: true);
  }
  canvas.setLineDashPattern();
  // Linia cięcia.
  canvas.setLineWidth(.9);
  for (final l in shape.cutLines) {
    poly(l, close: true);
  }
  // Punkty trasowania.
  canvas.setColor(_ink);
  for (final l in shape.labels) {
    canvas.drawEllipse(px(l.xMm), py(l.yMm), .7 * _mm, .7 * _mm);
  }
  canvas.fillPath();
  canvas.restoreContext();
  canvas.setColor(_ink);
  canvas.setLineWidth(.5);
  canvas.drawRect(0, 0, w, h);
  canvas.strokePath();
}
